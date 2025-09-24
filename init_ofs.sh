#!/bin/bash
# Uso: ./init_ofs.sh <nombreOvS> <puerto1> <puerto2> ...
nombreOvS=$1
shift
puertos=("$@")

# Crea OvS si no existe
sudo ovs-vsctl br-exists $nombreOvS || sudo ovs-vsctl add-br $nombreOvS

# Limpia IPs y conecta puertos
for p in "${puertos[@]}"; do
    sudo ip addr flush dev $p
    sudo ovs-vsctl add-port $nombreOvS $p
    sudo ip link set $p up
done
