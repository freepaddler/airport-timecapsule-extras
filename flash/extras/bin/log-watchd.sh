#!/bin/sh

. /mnt/Flash/extras/include

trap 'lg "exiting..."; exit 0' INT TERM HUP

h=$(date +%H)
m=$(date +%M)
s=$(date +%S)

h=${h#0}
m=${m#0}
s=${s#0}

[ -n "$h" ] || h=0
[ -n "$m" ] || m=0
[ -n "$s" ] || s=0

firstRun=$((86400 - h * 3600 - m * 60 - s))
lg "started. next run in $firstRun seconds"

sleep "$firstRun"
while :; do
    mv -f "$LOGFILE" "$LOGYESTERDAY" > /dev/null || lg "ERROR: failed to move log file"
    lg "moved: "$LOGFILE" -> "$LOGYESTERDAY". next run in $firstRun seconds"
    sleep 86400
done
