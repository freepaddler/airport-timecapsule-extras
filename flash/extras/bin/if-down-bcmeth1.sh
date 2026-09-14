#!/bin/sh
### PUBLIC interface DOWN

. /mnt/Flash/extras/include

# remove tunnels, because if any gif
# interface exist on UP event, TC light
# will stay amber until gif is destroyed
log "Remove tunnels"
"$SH_DIR/tunnels.sh" remove
