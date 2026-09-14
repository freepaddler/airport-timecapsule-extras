#!/bin/sh
### Tunnels setup script:
### gif tunnels + IPSEC transport + routes

. /mnt/Flash/extras/include

remove() {
    log "Request remove tunnels"
    # clear ipsec SAD and SPD
    setkey -F
    setkey -FP
    # remove gif interfaces (routes delted as well)
    for i in $(ifconfig | sed -nr 's/^(gif[0-9]+).*/\1/p'); do
        ifconfig "$i" destroy
    done
    log "Complete remove tunnels"
}

setup() {
    log "Request setup tunnels"
    remove
    while [ -z "$TC_IP" ]; do
        log "WARN: TC_IP is undefined"
        sleep 5
        read_vars
    done
    local k=0
    for t in $tunnels; do
        # setup gif interfaces
        ifconfig gif$k create
        eval ifconfig gif$k $TC_IP '$'${t}_IP netmask 255.255.255.0
        eval ifconfig gif$k tunnel $TC_PUB '$'${t}_PUB
        log "Created gif$k"
        # setup routes
        for n in $(eval echo '$'${t}_NET); do
            route delete $n
            eval route add $n '$'${t}_IP
        done
        log "Routes added for gif$k"
        eval echo 'add ''$'${t}_PUB' '$TC_PUB' esp ''$'${t}_SPI_IN' -E rijndael-cbc \"''$'${t}_KEY_IN'\"\;' | setkey -c
        eval echo 'add '$TC_PUB' ''$'${t}_PUB' esp ''$'${t}_SPI_OUT' -E rijndael-cbc \"''$'${t}_KEY_OUT'\"\;' | setkey -c
        eval echo 'spdadd '$TC_PUB/32' ''$'${t}_PUB'/32 ip4 -P out ipsec esp/transport/'$TC_PUB'-''$'${t}_PUB'/require\;' | setkey -c
        log "IPSec setup for gif$k"
        k=$((k + 1))
    done
    log "Complete setup tunnels"
}

case $1 in
    remove)
        remove
        ;;
    *)
        setup
        ;;
esac

exit 0
