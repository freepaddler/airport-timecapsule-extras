#!/bin/sh
### Start script, launches the process chain
### place or softlink to /mnt/Flash/rc.local

# Shared runtime variables (stored in VAR_DIR):
# Owns/writes: BASE_NAME - base station name read from ACP syNm.

. /mnt/Flash/extras/include
log "Request run setup.sh"

# on restart kill all custom running processes (NOT dhcp!)
for f in $RUN_DIR/*; do
    if [ -e "$f" ]; then
        log "killing $f"
        kill $(cat "$f")
        rm -f "$f"
    fi
done

# Minimal grep replacement: extended-regexp line filtering via sed.
# No grep options or grep-style no-match exit status; escape / in patterns.
if cat <<'EOF' > /usr/bin/grep
#!/bin/sh

if [ "$#" -eq 0 ]; then
    echo 'Usage: grep PATTERN [FILE ...]' >&2
    exit 2
fi

pattern="$1"
shift
exec sed -rn "/$pattern/p" "$@"
EOF
then
    chmod 755 /usr/bin/grep || log "ERROR: failed to make /usr/bin/grep executable"
else
    log "ERROR: failed to create /usr/bin/grep"
fi

# Read the base station name before starting interface handlers.
if baseNameProperty=$(/usr/bin/acp -A syNm); then
    case "$baseNameProperty" in
        syNm=*)
            baseName=$(acpGetValue "$baseNameProperty")
            if [ -n "$baseName" ]; then
                set_var BASE_NAME "$baseName"
            else
                log "ERROR: acp returned an empty base station name"
            fi
            ;;
        *) log "ERROR: unexpected acp syNm response" ;;
    esac
else
    log "ERROR: failed to read base station name"
fi

# launch interface changes watcher process
# on the start time it checks unterface state
# if UP - calls up scripts (-u option)
log "Start ifwatchd bridge0 bcmeth1"
/usr/sbin/ifwatchd -u "$SH_DIR/if-up.sh" -d "$SH_DIR/if-down.sh" bridge0 bcmeth1 bridge1
sleep 1
# save pid in file
ps x -o pid,command | sed -nr 's|(([^ ]+ ){1})/usr/sbin/ifwatchd.*|\1|p' > "$RUN_DIR/ifwatchd.pid"

# permanent volumes mount
"$SH_DIR/disk-watchd.sh" &
echo "$!" > "$RUN_DIR/disk-watchd.pid"

# log rotation
"$SH_DIR/log-watchd.sh" &
echo "$!" > "$RUN_DIR/log-watchd.pid"

log "Complete run setup.sh"

exit 0
