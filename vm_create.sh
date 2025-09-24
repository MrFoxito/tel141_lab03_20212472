#!/bin/bash
# Uso: ./vm_create.sh <NombreVM> <NombreOvS> <VLAN_ID> <PuertoVNC>
VMNAME=$1
OVSNAME=$2
VLANID=$3
VNC=$4

# Genera una MAC aleatoria con prefijo QEMU (52:54:00)
MAC=$(printf '52:54:00:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

# Elimina TAP y puerto si existen
sudo ip link delete tap-$VMNAME 2>/dev/null
sudo ovs-vsctl del-port $OVSNAME tap-$VMNAME 2>/dev/null

# Crea TAP
sudo ip tuntap add dev tap-$VMNAME mode tap
sudo ip link set tap-$VMNAME up

# Conecta TAP al OvS
sudo ovs-vsctl add-port $OVSNAME tap-$VMNAME tag=$VLANID

# Crea y lanza la VM
sudo qemu-system-x86_64 -m 512 -hda /home/ubuntu/cirros-0.5.1-x86_64-disk.img \
-netdev tap,id=net0,ifname=tap-$VMNAME,script=no,downscript=no \
-device virtio-net-pci,netdev=net0,mac=$MAC \
-vnc :$VNC &
