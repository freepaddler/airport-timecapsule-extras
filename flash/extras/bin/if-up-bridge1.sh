#!/bin/sh
### guest LAN interface UP

. /mnt/Flash/extras/include

TC_IP_guest=$4
RevZONE_guest="$(echo "$TC_IP_guest" | sed -rn 's/([0-9]{1,3}\.)([0-9]{1,3}\.)([0-9]{1,3}\.).*/\3\2\1in-addr.arpa/p')"
set_var TC_IP_guest "$TC_IP_guest"
set_var RevZONE_guest "$RevZONE_guest"
lg "Guest LAN vars setup complete"

# dns will be configured later after bridge0 setup complete
