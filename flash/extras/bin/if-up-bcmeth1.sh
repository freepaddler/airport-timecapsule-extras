#!/bin/sh
### PUBLIC interface UP

# Shared runtime variables (stored in VAR_DIR):
# Owns/writes: TC_PUB - IPv4 address of the public interface.
# Reads: TC_PUB for logging; launched tunnels/DNS scripts read shared state too.

. /mnt/Flash/extras/include

# save public IP address
set_var TC_PUB "$4"
# setup tunnels
log "Setup tunnels"
"$SH_DIR/tunnels.sh"
# update dns $ZONE record with $TC_PUB ip
log "Set dns record $ZONE $TC_PUB"
"$SH_DIR/dns.sh" configure

exit 0
