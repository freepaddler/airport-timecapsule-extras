#!/bin/sh
### Get TC configured dhcpd.conf
### and insert custom options
### Start dhcpd server with new options

. /mnt/Flash/extras/include

# source default dhcpd.conf
SRC="/etc/dhcpd.conf"

# check if dhcpd running correct instance
check_running() {
    if [ -f /var/run/dhcpd.pid ] && ps $(cat /var/run/dhcpd.pid); then
        # check which dhcpd server is running. if parent process is ACPd we should kill dhcpd
        if [ $(ps $(cat /var/run/dhcpd.pid) -o ppid=) -eq $(cat /var/run/ACPd.pid) ]; then
            lg "Default dhcpd is running. Killing..."
            kill -9 $(cat /var/run/dhcpd.pid)
            rm -f /var/run/dhcpd.pid
            return 1
        else
            lg "dhcpd is already running"
            return 0
        fi
    else
        lg "dhcpd is not running"
        return 1
    fi
}

# stop any running dhcpd instance
stop() {
    lg "Request stop dhcpd"
    if [ -f /var/run/dhcpd.pid ] && ps $(cat /var/run/dhcpd.pid); then
        lg "Killing dhcpd"
        kill $(cat /var/run/dhcpd.pid)
    else
        lg "No dhcpd server running"
    fi
    lg "Complete stop dhcpd"
}

start() {
    lg "Request start dhcpd"
    if check_running; then
        exit 0
    fi
    # start custom dhcpd server
    lg "/usr/sbin/dhcpd -q -cf $DHCPD_CONF -lf $DHCPD_LEASES bridge0 bridge1"
    if /usr/sbin/dhcpd -q -cf "$DHCPD_CONF" -lf "$DHCPD_LEASES" bridge0 bridge1; then
        sleep 1
        if [ -f /var/run/dhcpd.pid ] && ps $(cat /var/run/dhcpd.pid); then
            lg "dhcpd is running with pid $(cat /var/run/dhcpd.pid)"
        else
            lg "ERROR: dhcpd started but not running"
        fi
    else
        lg "WARNING: Failed to start dhcpd."
    fi
    lg "Complete start dhcpd"
}

configure() {
    lg "Request configure dhcpd.conf"
    # wait until /etc/dhcpd.conf is properly configured
    lg "Wait 5s to complete $SRC config"
    sleep 5
    until /usr/sbin/dhcpd -t -cf "$SRC"; do
        lg "WARN: invalid $SRC configuration. Waiting 5s to try again"
        sleep 5
    done
    # we only need to reconfigure if original was modified
    if [ $(getModTime "$SRC") -gt $(getModTime "$DHCPD_CONF") ]; then
        lg "Configuration was changed. Updating"

        # start line of LAN subnet declaration
        local p=$(sed -n "1,/subnet /{/subnet /=;}" "$SRC")

        # copy default global options
        sed -n "1,$((p - 1)) p" "$SRC" > "$DHCPD_CONF"
        # insert custom global options
        (
            IFS=
            echo $DHCPD_GLOBAL |
                while read -r l; do [ -n "$l" ] && echo $l; done
        ) >> "$DHCPD_CONF"

        # copy private subnet declaration
        sed -n "$p p" "$SRC" >> "$DHCPD_CONF"
        # insert custom subnet options
        echo "option domain-name \"$ZONE\";" >> "$DHCPD_CONF"
        (
            IFS=
            echo $DHCPD_LAN |
                while read -r l; do [ -n "$l" ] && echo $l; done
        ) >> "$DHCPD_CONF"

        # copy to the end of config
        sed -n "$((p + 1)),$ p" "$SRC" >> "$DHCPD_CONF"
        /usr/sbin/dhcpd -t -cf "$DHCPD_CONF" || lg "ERROR: invalid $DHCPD_CONF configuration"
        lg "Complete configure dhcpd.conf"
        return 0
    else
        lg "Nothing to update"
        return 1
    fi
}

case $1 in
    start | restart)
        stop
        start
        exit 0
        ;;
    stop)
        stop
        exit 0
        ;;
    configure)
        configure
        ;;
    check_running)
        check_running
        ;;
    *)
        configure && {
            stop
            start
        } || start
        exit 0
        ;;
esac
