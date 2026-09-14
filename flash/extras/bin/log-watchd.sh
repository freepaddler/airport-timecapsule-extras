#!/bin/sh

. /mnt/Flash/extras/include

trap 'log "exiting..."; exit 0' INT TERM HUP

# Require positive integers before arithmetic or sleep.
for value in "$LOG_FILE_SIZE" "$LOG_FILE_SIZE_CHECK"; do
    case "$value" in
        ""|*[!0-9]*)
            log "ERROR: LOG_FILE_SIZE and LOG_FILE_SIZE_CHECK must be positive integers"
            exit 1
            ;;
    esac
    if [ "$value" -le 0 ]; then
        log "ERROR: LOG_FILE_SIZE and LOG_FILE_SIZE_CHECK must be positive integers"
        exit 1
    fi
done

maxSize=$((LOG_FILE_SIZE * 1024))
log "started. log size threshold: $LOG_FILE_SIZE KiB; check interval: $LOG_FILE_SIZE_CHECK seconds"

# Check immediately, then at a fixed interval independent of the time of day.
while :; do
    if [ -f "$LOG_FILE" ]; then
        # Read the byte size from metadata without reading the log contents.
        set -- $(ls -ln "$LOG_FILE" 2>/dev/null)
        size=${5:-}
        case "$size" in
            ""|*[!0-9]*)
                log "ERROR: failed to read log file size"
                ;;
            *)
                if [ "$size" -ge "$maxSize" ]; then
                    if mv -f "$LOG_FILE" "$LOG_FILE_OLD"; then
                        log "rotated $LOG_FILE -> $LOG_FILE_OLD"
                    else
                        log "ERROR: failed to rotate $LOG_FILE"
                    fi
                fi
                ;;
        esac
    fi
    sleep "$LOG_FILE_SIZE_CHECK"
done
