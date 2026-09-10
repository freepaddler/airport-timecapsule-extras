#!/bin/sh
### Script to run on interface UP events
### bridge0 - LAN (not ! guest LAN)
### bcmeth1 - PUB internet

. /mnt/Flash/extras/include

# we're not interested in ipv6 events
if isIPv4 "$4"; then
    case $1 in
        bridge0)
            lg "UP LAN: $*"
            ;;
        bridge1)
            lg "UP Guest LAN: $*"
            ;;
        bcmeth1)
            # avoid link_local ip actions
            if isPubIP "$4"; then
                lg "UP PUB: $*"
            else
                exit 0
            fi
            ;;
        *)
            exit 0
            ;;
    esac
else
    exit 0
fi

# run if-up script
if [ -x "$SHDIR/if-up-$1.sh" ]; then
    lg "Runnig if-up-$1.sh $*"
    "$SHDIR/if-up-$1.sh" $* > /dev/null 2>&1 &
fi

exit 0
