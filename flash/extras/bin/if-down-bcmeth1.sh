#!/bin/sh
### PUBLIC interface DOWN

. /mnt/Flash/extras/include

# remove tunnels, because if any gif
# interface exist on UP event, TC light
# will stay amber until gif is destroyed
lg "Remove tunnels"
"$SHDIR/tunnels.sh" remove
