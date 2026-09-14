#!/bin/sh
### tinydns management script
. /mnt/Flash/extras/include

DNSROOT="$FLASHDIR/tinydns"
DATA="$DNSROOT/root/data"
DYNAMIC="$CONFDIR/dns.dynamic"
STATIC="$CONFDIR/dns.static"
tmp="$DNSROOT/temp"
DNSCACHE="/var/sv/dnscache"
TTL=300
CACHESIZE=8000000
DATALIMIT=8388608

# update root dns servers list
update_root() {
    curl -k https://www.internic.net/domain/named.root | sed -rn 's/^.*( A )[ ]*([0-9].*)$/\2/p' > "$CONFDIR/root.ip"
    lg "dns roots updated"
}

# install tinydns: copy binaries to $BINDIR
setup() {
    lg "Request setup dns"
    # setup tinydns environment
    [ -d "$DNSROOT" ] || mkdir -p "$DNSROOT"
    [ -d "$DNSROOT/root" ] || mkdir -p "$DNSROOT/root"
    [ -d "$DNSROOT/env" ] || mkdir -p "$DNSROOT/env"
    echo 0 > "$DNSROOT/env/GID"
    echo 0 > "$DNSROOT/env/UID"
    echo "127.0.0.4" > "$DNSROOT/env/IP"
    echo "$DNSROOT/root" > "$DNSROOT/env/ROOT"

    echo '#!/bin/sh' > "$DNSROOT/run"
    echo 'exec 2>&1' >> "$DNSROOT/run"
    echo "exec envdir env $BINDIR/tinydns" >> "$DNSROOT/run"
    chmod +x "$DNSROOT/run"

    [ -d "$DNSROOT/log" ] || mkdir -p "$DNSROOT/log"
    echo '#!/bin/sh' > "$DNSROOT/log/run"
    echo 'exec >/dev/null' >> "$DNSROOT/log/run"
    echo 'exec cat -' >> "$DNSROOT/log/run"
    chmod +x "$DNSROOT/log/run"

    [ -f "$CONFDIR/root.ip" ] || update_root
    # check if binaries already exist
    if [ ! -x "$BINDIR/tinydns" -o ! -x "$BINDIR/tinydns-data" ]; then
        lg "Need to install tinydns..."
        waitMount "$HDDDIR/bin"
        lg "copying files from $HDDDIR/bin/"
        cp -f "$HDDDIR/bin/tinydns" "$BINDIR/" || lg "ERROR: can't copy tinydns"
        cp -f "$HDDDIR/bin/tinydns-data" "$BINDIR/" || lg "ERROR: can't copy tinydns-data"
    fi
    # ip for tinydns
    lg "creating ip alias 127.0.0.4"
    ifconfig lo0 alias 127.0.0.4
    # make link for svcscan supervised service
    if [ ! -L /var/sv/tinydns ]; then
        lg "linking tinydns to svc"
        ln -fs "$DNSROOT" /var/sv/tinydns
    fi
    # normally 5 seconds should be enough, but...
    lg "Wait 7s and check if tynydns is running"
    sleep 6
    svc -u "/var/sv/tinydns"
    sleep 1
    r=$(netstat -an | sed -nr 's/(.*)(127.0.0.4.53)(.*)/\2/p')
    if [ "$r" = "127.0.0.4.53" ]; then
        lg "tinydns is running"
        # set global var DNS is working
    else
        lg "ERROR: tinydns is not running"
        # set global var DNS is NOT working
    fi
    # all zone files are alredy created
    # let them go live
    dns_mk
    lg "Complete setup dns"
}

# setup resolver
setup_dnscache() {
    lg "Request setup dnscache"
    # increase cache size
    echo $CACHESIZE > "$DNSCACHE/env/CACHESIZE"
    echo $DATALIMIT > "$DNSCACHE/env/DATALIMIT"
    # set zones served by tinydns
    (
        # delete all existing zones but default
        cd "$DNSCACHE/root/servers/"
        for f in *; do
            if [ ! "$f" = "local" ] && [ ! "$f" = "@" ]; then
                rm "$f"
            fi
        done
    )
    # add ZONE and RevZONE
    for zone in "$ZONE" "$RevZONE" "$RevZONE_guest"; do
        echo 127.0.0.4 > "$DNSCACHE/root/servers/$zone"
    done
    # set external networks served by dnscache
    for net in $DNS_ACCESS; do
        echo > "$DNSCACHE/root/ip/$net"
    done

    # add DNS_EXTERNAL zones
    (
        IFS=
        echo "$DNS_EXTERNAL" |
            while read ez; do
                (
                    IFS=" "
                    echo "$ez" |
                        while read z f; do
                            if [ -n "$z" -a -n "$f" ]; then
                                echo "$f" > "$DNSCACHE/root/servers/$z"
                            fi
                        done
                )
            done
    )

    # create copy of original dns-update-script
    if [ ! -x /sbin/dns-update-script-orig ]; then
        cp -f /sbin/dns-update-script /sbin/dns-update-script-orig
    fi
    # create modified copy of dns-update-script
    # to deny update dns servers on each lease renew
    if [ ! -x /sbin/dns-update-script-mod ]; then
        sed -n '1,48 p' /sbin/dns-update-script > /sbin/dns-update-script-mod
        echo 'echo "nameserver 127.0.0.1" >> ${resolv}' >> /sbin/dns-update-script-mod
        echo 'exit 0' >> /sbin/dns-update-script-mod
        echo >> /sbin/dns-update-script-mod
    fi

    # setup forwarders
    #remove#chmod +w "$DNSCACHE/root/servers/@"
    if [ "$DNS_FORWARD" = "root" ] && [ -s "$CONFDIR/root.ip" ]; then
        # root for recursive resolver from root servers
        cat "$CONFDIR/root.ip" > "$DNSCACHE/root/servers/@"
        echo 0 > "$DNSCACHE/env/FORWARDONLY"
        #chmod -w "$DNSCACHE/root/servers/@"
        cp -f /sbin/dns-update-script-mod /sbin/dns-update-script
    elif [ "$DNS_FORWARD" = "root" ]; then
        # no root.ip file, use default setup
        echo 1 > "$DNSCACHE/env/FORWARDONLY"
        cp -f /sbin/dns-update-script-orig /sbin/dns-update-script
        # get first string of /etc/resolve.conf
        # it is command to set default dns
        local dus=$(sed -n -e '1 p' -e 's/^# /\/sbin\//p' /etc/resolv.conf)
        # run it
        $dus
    elif [ -z "$DNS_FORWARD" ]; then
        # empty is default TC setup
        echo 1 > "$DNSCACHE/env/FORWARDONLY"
        cp -f /sbin/dns-update-script-orig /sbin/dns-update-script
        # get first string of /etc/resolve.conf
        # it is command to set default dns
        local dus=$(sed -n -e '1 p' -e 's/^# /\/sbin\//p' /etc/resolv.conf)
        # run it
        $dus
    else
        # list of predefined dns servers
        echo 1 > "$DNSCACHE/env/FORWARDONLY"
        echo > "$DNSCACHE/root/servers/@"
        for s in $DNS_FORWARD; do echo "$s"; done > "$DNSCACHE/root/servers/@"
        #remove#chmod -w "$DNSCACHE/root/servers/@"
        cp -f /sbin/dns-update-script-mod /sbin/dns-update-script
    fi

    lg "Restarting dnscache"
    svc -t "$DNSCACHE"
    svc -u "$DNSCACHE"
    lg "Complete setup dnscache"
}

# add dns record to dynamic file
# parameters
#   $1 ip address
#   $2 hostname
ddns_add() {
    # get ip network
    local n=$(echo $1 | sed -nr "s/^(([0-9]{1,3}\.){3}).*/\1/p")
    case $n in
        # network is from LAN segment
        "${TC_IP%[0-9]}")
            z=$ZONE
            ;;
        "${TC_IP_guest%[0-9]}")
            z=guest.$ZONE
            ;;
        *)
            z=
            ;;
    esac
    if [ -n "$z" ]; then
        # remove record by ip
        ddns_del "$1"
        if [ -z "$2" ]; then
            # client-hostname is not defined
            local l=$(echo "$1" | sed -nr "s/.*\.([0-9]{1,3})$/\1/p")
            local h="dhcp$l"
        else
            # client-hostname is defined
            local h=$2
        fi
        # if we already have record with same name
        # try to add postfix "-k" i.e. name-1.ZONE
        local nh="$h.$z"
        local k=0
        while check_dup_name "$nh"; do
            k=$((k + 1))
            nh=$h-$k.$z
        done
        echo "=$nh:$1:$TTL" >> "$DYNAMIC"
    fi
}

# delete dns record from dynamic file
# parameters
#   $1 ip address
ddns_del() {
    rm -rf "$tmp"
    local i=$(echo "$1" | sed -n 's/\./\\./gp')
    cat "$DYNAMIC" | sed "/\:$i\:/d" >> "$tmp"
    mv "$tmp" "$DYNAMIC"
}

# make zone file
dns_mk() {
    # update DATA file
    cat "$STATIC" "$DYNAMIC" > "$DATA"
    # make data.cdb (if dns binaries installed)
    if [ -x "$BINDIR/tinydns-data" ]; then
        (
            cd "$DNSROOT/root"
            "$BINDIR/tinydns-data" || lg "ERROR: data file failure"
        )
    fi
}

# check if hostname already exists
# parameters
#   $1 fqdn
check_dup_name() {
    local h=$(echo "$1" | sed -n 's/\./\\./gp')
    if [ -z "$(cat "$STATIC" "$DYNAMIC" | sed -nr "/(^.|\:)$h\:/p")" ]; then
        return 1
    else
        return 0
    fi
}

# create zone definitions
# and add static records
dns_static() {
    lg "Request static zones setup"
    # ZONE and RevZone definition
    # gw always points to TC_IP
    cat << EOF > "$STATIC"
#Primary zone
Z$ZONE:ns.$ZONE:root.$ZONE::900:90:86400:900:$TTL
Z$RevZONE:ns.$ZONE:root.$ZONE::900:90:86400:900:$TTL
&$ZONE:$TC_IP:ns.$ZONE:$TTL
&$RevZONE::ns.$ZONE:$TTL
=$(hostname).$ZONE:$TC_IP:$TTL
+gw.$ZONE:$TC_IP:$TTL

EOF
    if [ -n "$RevZONE_guest" ]; then
        cat << EOF >> "$STATIC"
#Guest zone
Zguest.$ZONE:ns.guest.$ZONE:root.guest.$ZONE::900:90:86400:900:$TTL
Z$RevZONE_guest:ns.guest.$ZONE:root.guest.$ZONE::900:90:86400:900:$TTL
&guest.$ZONE:$TC_IP_guest:ns.guest.$ZONE:$TTL
&$RevZONE_guest::ns.guest.$ZONE:$TTL
=gw.guest.$ZONE:$TC_IP_guest:$TTL

EOF
    fi
    echo "#Static records" >> "$STATIC"
    # set ZONE fqdn to TC_PUB
    if [ -n "$TC_PUB" ]; then
        echo "+$ZONE:$TC_PUB:$TTL" >> "$STATIC"
    fi
    # add static records
    (
        IFS=
        echo "$DNS_STATIC" |
            while read l; do [ -n "$l" ] && echo $l; done
    ) >> "$STATIC"

    echo >> "$STATIC"
    echo "#DHCP fixed-address records" >> "$STATIC"
    # add fixed_leases records
    scan_static_leases
    echo >> "$STATIC"
    echo "#DHCP controlled records" >> "$STATIC"
    dns_mk
    lg "Complete static zones setup"
}

# scan dhcpd.conf to get static records
scan_static_leases() {
    local a b c l_ip l_name
    [ -f "$DHCPD_CONF" ] && while read -r a b c; do
        # fixed-addres string: save ip
        if [ "$a" = "fixed-address" ]; then
            l_ip=${b%\;}
            l_name=
        # dhcp-client-identifier string: add to dns
        # string format is "\000hostname";
        elif [ "$b" = "dhcp-client-identifier" ]; then
            # remove trailing ";
            l_name=${c%\"\;}
            # remove leading "\000
            l_name=${l_name#\"\\000}
            # add record to static
            [ -n "$l_ip" ] && echo "=$l_name.$ZONE:$l_ip:$TTL" >> "$STATIC"
            l_ip=
            l_name=
        fi
    done < "$DHCPD_CONF"
}

# scan dhcpd.leases to get dynamic records
scan_leases() {
    local a b c l_name l_ip l_action
    while read -r a b c; do
        case $a in
            # end of lease record: update dns
            "}")
                case $l_action in
                    "active")
                        ddns_add "$l_ip" "$l_name"
                        lg "ddns_add $l_ip $l_name"
                        ;;
                    "free")
                        ddns_del "$l_ip"
                        dbg "ddns_del $l_ip"
                        ;;
                esac
                # clean lease vars
                l_ip=
                l_name=
                l_action=
                ;;
            # start of lease record
            # save ip address
            "lease")
                l_ip=$b
                # flush other lease vars
                l_name=
                l_action=
                ;;
            # client-hostname string
            "client-hostname")
                # remove ; and quotes
                l_name=$(echo "${b%\;}" | sed 's/\"//g')
                ;;
            # lease binding state
            "binding")
                # remove ;
                l_action=${c%\;}
                ;;
        esac
    done < "$DHCPD_LEASES"
}

# ddns_update cycle
# parameters
#   $1 "stop" - kill running instace
ddns_update() {
    # stop to avoid duplicate run
    if [ -f "$RUNDIR/ddns-update.pid" ]; then
        lg "killing ddns_update"
        kill "$(cat "$RUNDIR/ddns-update.pid")"
        rm -f "$RUNDIR/ddns-update.pid"
    fi
    # if stop request than we're done
    [ "$1" = "stop" ] && exit 0

    # log pid to file
    echo $$ > "$RUNDIR/ddns-update.pid"
    lg "DDNS-Update script started with pid $(cat "$RUNDIR/ddns-update.pid")"

    local lastMod=0
    # flush dynamic records
    echo > "$DYNAMIC"
    # main cycle
    while :; do
        if [ -f "$DHCPD_LEASES" ] && [ $lastMod -lt $(getModTime "$DHCPD_LEASES") ]; then
            lastMod=$(getModTime "$DHCPD_LEASES")
            read_vars
            scan_leases
            dns_mk
        fi
        sleep 10
    done
}

case $1 in
    setup)
        setup
        ;;
    configure)
        dns_static
        ;;
    setup_dnscache)
        setup_dnscache
        ;;
    update_root)
        update_root
        ;;
    ddns_update)
        ddns_update "$2"
        ;;
esac

exit 0
