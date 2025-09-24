#!/bin/bash
# Uso: ./init_worker.sh <nombreOvS> <InterfacesAConectar>
nombreOvS=$1
shift
interfaces=("$@")

# Crea OvS si no existe
sudo ovs-vsctl br-exists $nombreOvS || sudo ovs-vsctl add-br $nombreOvS

# Conecta interfaces al OvS
for iface in "${interfaces[@]}"; do
    sudo ovs-vsctl add-port $nombreOvS $iface
    sudo ip link set $iface up
done
