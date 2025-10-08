#!/usr/bin/env bash
# crea br-int y conecta uplinks
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <OVS_BR> <IF1> [IF2 ...]"; exit 1
fi

OVS_BR="$1"; shift
IFACES=("$@")

if ! ovs-vsctl br-exists "$OVS_BR" 2>/dev/null; then
  echo "Creando bridge $OVS_BR"
  ovs-vsctl add-br "$OVS_BR"
fi

ip link set dev "$OVS_BR" up

for IFACE in "${IFACES[@]}"; do
  echo "Subiendo $IFACE"
  ip addr flush dev "$IFACE" || true
  ip link set dev "$IFACE" up
  if ! ovs-vsctl list-ports "$OVS_BR" | grep -q "^${IFACE}\$"; then
    echo "Añadiendo $IFACE a $OVS_BR"
    ovs-vsctl add-port "$OVS_BR" "$IFACE"
  fi
done

echo "Worker listo en $OVS_BR: ${IFACES[*]}"

# Uso: sudo ./init_worker.sh <OVS_BR> <IF1> [IF2 ...]
