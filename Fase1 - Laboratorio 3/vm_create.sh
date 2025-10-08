#!/usr/bin/env bash
# Crea una VM conectada a OVS con VLAN y VNC

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Uso: $0 <VM_NAME> <OVS_BR> <VLAN_ID> <VNC_IDX> [DISK_IMG|--persist]"; exit 1
fi

VM_NAME="$1"; OVS_BR="$2"; VLAN_ID="$3"; VNC_IDX="$4"; shift 4

PERSIST=0; USER_PATH=""; BASE_HINT=""
while (( "$#" )); do
  case "$1" in
    --persist) PERSIST=1; shift ;;
    --base)    BASE_HINT="${2:-}"; shift 2 ;;
    *)         USER_PATH="$1"; shift ;;
  esac
done

command -v qemu-system-x86_64 >/dev/null || { echo "Falta qemu-system-x86_64"; exit 1; }
command -v ovs-vsctl >/dev/null || { echo "Falta openvswitch-switch"; exit 1; }

DEFAULT_BASE="/var/lib/images/cirros-base.img"
LEGACY_BASE="/var/lib/images/cirros-0.5.1-x86_64-disk.img"

SNAPSHOT_ARG="-snapshot"
DISK_IMG=""

if [[ -n "$USER_PATH" && "$USER_PATH" == *.qcow2 ]]; then
  DISK_IMG="$USER_PATH"; SNAPSHOT_ARG=""
elif [[ -n "$USER_PATH" && "$PERSIST" -eq 0 ]]; then
  DISK_IMG="$USER_PATH"; SNAPSHOT_ARG="-snapshot"
elif [[ "$PERSIST" -eq 1 ]]; then
  BASE_IMG="${BASE_HINT:-${USER_PATH:-$DEFAULT_BASE}}"
  [[ -e "$BASE_IMG" ]] || BASE_IMG="$LEGACY_BASE"
  [[ -e "$BASE_IMG" ]] || { echo "Base no encontrada: $BASE_IMG"; exit 1; }
  DISK_IMG="/var/lib/images/${VM_NAME}.qcow2"
  command -v qemu-img >/dev/null || { echo "Falta qemu-img"; exit 1; }
  if [[ ! -e "$DISK_IMG" ]]; then
    echo "Creando overlay $DISK_IMG -> base $BASE_IMG"
    qemu-img create -f qcow2 -b "$BASE_IMG" "$DISK_IMG" >/dev/null
  else
    echo "Reusando overlay $DISK_IMG"
  fi
  SNAPSHOT_ARG=""
else
  DISK_IMG="${USER_PATH:-$DEFAULT_BASE}"
  [[ -e "$DISK_IMG" ]] || DISK_IMG="$LEGACY_BASE"
  [[ -e "$DISK_IMG" ]] || { echo "No encuentro base u overlay ($DEFAULT_BASE / $LEGACY_BASE)"; exit 1; }
  SNAPSHOT_ARG="-snapshot"
fi

TAP="${VM_NAME}_tap"
if ! ip tuntap list 2>/dev/null | grep -q "^${TAP}:"; then
  echo "Creando TAP ${TAP}"; ip tuntap add mode tap name "$TAP"
fi
ip link set dev "$TAP" up

if ! ovs-vsctl list-ports "$OVS_BR" | grep -q "^${TAP}\$"; then
  echo "Añadiendo $TAP a $OVS_BR (VLAN $VLAN_ID)"
  ovs-vsctl add-port "$OVS_BR" "$TAP" tag="$VLAN_ID"
else
  ovs-vsctl set port "$TAP" tag="$VLAN_ID" >/dev/null
fi

VMID="${HOSTNAME}-${VM_NAME}"
HEX=$(printf "%s" "$VMID" | md5sum | cut -c1-10)
MAC="52:54:00:${HEX:0:2}:${HEX:2:2}:${HEX:4:2}"

echo "Lanzando $VM_NAME (VNC :$VNC_IDX, VLAN $VLAN_ID, DISK=$DISK_IMG ${SNAPSHOT_ARG:+[SNAPSHOT]})"
qemu-system-x86_64 \
  -enable-kvm \
  -vnc 0.0.0.0:"$VNC_IDX" \
  -netdev tap,id="${TAP}",ifname="${TAP}",script=no,downscript=no \
  -device virtio-net-pci,netdev="${TAP}",mac="$MAC" \
  -daemonize \
  ${SNAPSHOT_ARG} \
  "$DISK_IMG"

echo "$VM_NAME listo → $OVS_BR (VLAN $VLAN_ID) MAC $MAC"

# Uso: sudo ./vm_create.sh <NAME> <OVS_BR> <VLAN> <VNC_IDX> [DISK_IMG|--persist [--base PATH]]
