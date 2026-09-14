#!/bin/sh

. /mnt/Flash/extras/include

trap 'log "exiting..."; exit 0' INT TERM HUP
log "started for volumes: $DISKS"

while :; do
    for disk in $DISKS; do
        volume=$(getVolume "$disk")
        d="${volume%%:*}"
        p="${volume#*:}"
        p="${p%%:*}"
        u="${volume##*:}"
        if [ -z "$d" ] || [ -z "$p" ] || [ -z "$u" ]; then
            log "skip $disk ($volume)"
            continue
        fi
        if ! volumeIsMounted "/Volumes/$p" || [ "$u" -eq 0 ]; then
            log "mounting: $volume"
            while [ "$u" -ne 0 ]; do
                previousUsers="$u"
                if ! /usr/bin/acp rpc diskd.unuseVolume path:s:/Volumes/"$p" > /dev/null; then
                    log "ERROR: failed to unuse $volume"
                    continue 2
                fi
                volume=$(getVolume "$disk")
                u="${volume##*:}"
                if [ -z "$u" ] || [ "$u" -ge "$previousUsers" ]; then
                    log "ERROR: failed to reduce users for $disk ($previousUsers -> $u)"
                    continue 2
                fi
            done
            if ! /usr/bin/acp rpc diskd.useVolume path:s:/Volumes/"$p" > /dev/null; then
                log "ERROR: failed to mount $volume"
                continue
            fi
            /sbin/atactl "$d" setidle "$DISK_IDLE_TIMEOUT" || log "ERROR: failed to set DISK_IDLE_TIMEOUT for $d"
            log "mounted: $volume"
        else
            debug "mounted: $volume"
        fi
    done
    sleep "$DISK_CHECK_TIMEOUT"
done
