#!/bin/sh

. /mnt/Flash/extras/include

trap 'lg "exiting..."; exit 0' INT TERM HUP
lg "started for volumes: $DISKS"

while :; do
    for disk in $DISKS; do
        volume=$(getVolume "$disk")
        d=$(hddGetDisk "$volume")
        p=$(hddGetPartition "$volume")
        u=$(hddGetUsers "$volume")
        if [ -z "$d" ] || [ -z "$p" ] || [ -z "$u" ]; then
            lg "skip $disk ($volume)"
            continue
        fi
        if ! volumeIsMounted "/Volumes/$p"; then
            lg "mounting: $volume"
            error=""
            while [ "$u" -ne 0 ]; do
                /usr/bin/acp rpc diskd.unuseVolume path:s:/Volumes/"$p" > /dev/null || lg "ERROR: failed to unuse $volume"
                volume=$(getVolume "$disk")
                u=$(hddGetUsers "$volume")
                if [ -z "$u" ]; then
                    error="1"
                    break
                fi
            done
            if [ -z "$error" ]; then
                /usr/bin/acp rpc diskd.useVolume path:s:/Volumes/"$p" > /dev/null || lg "ERROR: failed to mount $volume"
                /sbin/atactl "$d" setidle "$DISK_IDLE_TIMEOUT" || lg "ERROR: failed to set DISK_IDLE_TIMEOUT for $d"
                lg "mounted: $volume"
            else
                lg "ERROR: failed to remount disk $disk ($volume)"
            fi
        else
            dbg "mounted: $volume"
        fi
    done
    sleep "$DISK_CHECK_TIMEOUT"
done
