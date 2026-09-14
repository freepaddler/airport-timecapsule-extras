#!/bin/sh
### Script to run on interface UP events
### bridge0 - LAN (not ! guest LAN)
### bcmeth1 - PUB internet

. /mnt/Flash/extras/include

# we're not interested in ipv6 events
if isIPv4 "$4"; then
    case $1 in
        bridge0)
            log "UP LAN: $*"
            ;;
        bridge1)
            log "UP Guest LAN: $*"
            ;;
        bcmeth1)
            # avoid link_local ip actions
            if isPubIP "$4"; then
                log "UP PUB: $*"
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
if [ -x "$SH_DIR/if-up-$1.sh" ]; then
    log "Runnig if-up-$1.sh $*"
    "$SH_DIR/if-up-$1.sh" $* > /dev/null 2>&1 &
fi

exit 0
