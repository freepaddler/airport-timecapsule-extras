#!/bin/sh
### guest LAN interface UP

# Shared runtime variables (stored in VAR_DIR):
# Owns/writes: TC_IP_guest - guest LAN IPv4 address;
#             RevZONE_guest - guest LAN reverse DNS zone.

. /mnt/Flash/extras/include

set_var TC_IP_guest "$4"
RevZONE_guest="$(echo "$TC_IP_guest" | sed -rn 's/([0-9]{1,3}\.)([0-9]{1,3}\.)([0-9]{1,3}\.).*/\3\2\1in-addr.arpa/p')"
set_var RevZONE_guest "$RevZONE_guest"
log "Guest LAN vars setup complete"

# dns will be configured later after bridge0 setup complete
