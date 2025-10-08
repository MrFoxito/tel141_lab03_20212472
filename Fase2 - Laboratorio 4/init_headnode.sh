#!/usr/bin/env bash
# crea bridge OVS y conecta uplinks (trunk)
set -euo pipefail

[[ $# -lt 2 ]] && { echo "Uso: $0 <OVS_BR> \"<IFACES...>\""; exit 1; }
BR="$1"; IFACES_STR="$2"
TRUNKS="${TRUNKS:-100,200,300}"

command -v ovs-vsctl >/dev/null || { echo "Falta ovs-vsctl"; exit 1; }

echo "HeadNode: bridge=$BR ifaces=[$IFACES_STR]"
ovs-vsctl --may-exist add-br "$BR"
ip link set "$BR" up || true

for IF in $IFACES_STR; do
  [[ "$IF" == "ens3" ]] && { echo "skip $IF (mgmt)"; continue; }
  ip link set "$IF" up
  ovs-vsctl --may-exist add-port "$BR" "$IF"
  ovs-vsctl set port "$IF" trunks="$TRUNKS"
  echo "$IF -> $BR (trunks=$TRUNKS)"
done

ovs-vsctl show
echo "HeadNode listo"

# Uso: sudo ./init_headnode.sh <OVS_BR> "<IFACES...>"
