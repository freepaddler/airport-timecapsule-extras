#!/bin/sh
### LAN interface UP after TC start or reconfiguration
### It's time to get (re)configured settings

. /mnt/Flash/extras/include

lg "Flushing vars"
# preserve TC_PUB when PUB interface
# goes UP before LAN (manual reconfig)
[ -n "$TC_PUB" ] && _tc_pub="$TC_PUB"
flush_vars
# preserve TC_PUB when PUB interface
# goes UP before LAN (manual reconfig)
if [ -n "$_tc_pub" ]; then
    set_var TC_PUB "$_tc_pub"
fi
TC_IP=$4
RevZONE="$(echo "$TC_IP" | sed -rn 's/([0-9]{1,3}\.)([0-9]{1,3}\.)([0-9]{1,3}\.).*/\3\2\1in-addr.arpa/p')"
set_var TC_IP "$TC_IP"
set_var RevZONE "$RevZONE"
lg "Vars setup complete"

# the start of dhcpd means all IPs are set up
# and dchpd.conf is (re)confgured
while [ ! -f /var/run/dhcpd.pid ]; do
    lg "Waiting for default dhcpd to start"
    sleep 1
done

# check which dhcpd server is running
# if parent process is ACPd we should kill dhcpd
# it will never start if ours is running
lg "Check running dhcpd"
"$SHDIR/dhcpd.sh" check_running

# Install dns binaries
"$SHDIR/dns.sh" setup &
# wait for tinydns dirs to be created
sleep 1
# configure dns-managed zones
"$SHDIR/dns.sh" configure
# reconfigure dns resolver
"$SHDIR/dns.sh" setup_dnscache
# start dhcp ddns_update script
lg "Start ddns-update"
"$SHDIR/dns.sh" ddns_update &

# setup dhcpd server
lg "Setup dhcpd"
"$SHDIR/dhcpd.sh"
# update dns fixed-address records
"$SHDIR/dns.sh" configure

exit 0
