#!/usr/bin/env bash
# crea bridge y puertos de datos con trunks , procuramos que no toque ens3
set -euo pipefail

if [[ -z "${OVS_BR:-}" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "Uso: $0 <OVS_BR> <IF1> [IF2 ...] [--trunks LISTA] o OVS_BR=... IFACES=... TRUNKS=... $0"; exit 1
  fi
  OVS_BR="$1"; shift
fi

TRUNKS="${TRUNKS:-}"
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  a="${ARGS[$i]}"
  case "$a" in
    --trunks)
      ((i++))
      TRUNKS="${ARGS[$i]// /}"
      ;;
    --trunks=*)
      TRUNKS="${a#--trunks=}"
      TRUNKS="${TRUNKS// /}"
      ;;
  esac
done

IFACES_ARR=()
if [[ -n "${IFACES:-}" ]]; then
  read -r -a IFACES_ARR <<< "$IFACES"
else
  skip_next=false
  for a in "$@"; do
    if $skip_next; then
      skip_next=false
      continue
    fi
    if [[ "$a" == --trunks ]]; then
      skip_next=true
      continue
    fi
    [[ "$a" == --trunks=* ]] && continue
    [[ "$a" == "ens3" ]] && { echo "skip ens3"; continue; }
    IFACES_ARR+=("$a")
  done
fi

if ! ovs-vsctl br-exists "$OVS_BR" 2>/dev/null; then
  echo "Creando bridge $OVS_BR"
  ovs-vsctl add-br "$OVS_BR"
fi
ip link set dev "$OVS_BR" up || true

for IF in "${IFACES_ARR[@]}"; do
  echo "Preparando $IF"
  ip addr flush dev "$IF" 2>/dev/null || true
  ip link set dev "$IF" up

  if ! ovs-vsctl list-ports "$OVS_BR" | grep -qx "$IF"; then
    echo "Añadiendo $IF a $OVS_BR"
    ovs-vsctl add-port "$OVS_BR" "$IF"
  else
    echo "$IF ya está en $OVS_BR"
  fi

  if [[ -n "$TRUNKS" ]]; then
    echo "trunks=$TRUNKS en $IF"
    ovs-vsctl set port "$IF" trunks="$TRUNKS"
  fi
done

echo "OFS listo en $OVS_BR"
ovs-vsctl show

# Uso: OVS_BR=br-ofs IFACES="ens5 ens6 ens7 ens8" TRUNKS="100,200,300" sudo -E ./init_ofs.sh
