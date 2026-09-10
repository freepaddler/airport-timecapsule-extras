#!/bin/sh
### Script to run on interface DOWN events
### bridge0 - LAN (not ! guest LAN)
### bcmeth1 - PUB internet

. /mnt/Flash/extras/include

case $1 in
    bridge0)
        # down event happens with ipv6 :(
        lg "DOWN LAN: $*"
        ;;
    bcmeth1)
        # avoid link_local and ipv6 events
        if isIPv4 "$4" && isPubIP "$4"; then
            lg "DOWN PUB: $*"
        else
            exit 0
        fi
        ;;
    *)
        exit 0
        ;;
esac

# run if-down script
if [ -x "$SHDIR/if-down-$1.sh" ]; then
    lg "Runnig if-down-$1.sh $*"
    "$SHDIR/if-down-$1.sh" $* > /dev/null 2>&1 &
fi

exit 0
