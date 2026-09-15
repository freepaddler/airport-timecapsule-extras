#!/bin/sh
### LAN interface UP after TC start or reconfiguration
### It's time to get (re)configured settings

# Shared runtime variables (stored in VAR_DIR):
# Owns/writes: TC_IP - LAN IPv4 address; RevZONE - LAN reverse DNS zone.
# Other components own their values; LAN updates do not clear shared state.

. /mnt/Flash/extras/include

set_var TC_IP "$4"
RevZONE="$(echo "$TC_IP" | sed -rn 's/([0-9]{1,3}\.)([0-9]{1,3}\.)([0-9]{1,3}\.).*/\3\2\1in-addr.arpa/p')"
set_var RevZONE "$RevZONE"
log "LAN vars updated"

# the start of dhcpd means all IPs are set up
# and dchpd.conf is (re)confgured
while [ ! -f /var/run/dhcpd.pid ]; do
    log "Waiting for default dhcpd to start"
    sleep 1
done

# check which dhcpd server is running
# if parent process is ACPd we should kill dhcpd
# it will never start if ours is running
log "Check running dhcpd"
"$SH_DIR/dhcpd.sh" check_running

# Install dns binaries
"$SH_DIR/dns.sh" setup &
# wait for tinydns dirs to be created
sleep 1
# configure dns-managed zones
"$SH_DIR/dns.sh" configure
# reconfigure dns resolver
"$SH_DIR/dns.sh" setup_dnscache
# start dhcp ddns_update script
log "Start ddns-update"
"$SH_DIR/dns.sh" ddns_update &

# setup dhcpd server
log "Setup dhcpd"
"$SH_DIR/dhcpd.sh"
# update dns fixed-address records
"$SH_DIR/dns.sh" configure

log "Setup Samba"
"$SH_DIR/samba.sh" &

exit 0
