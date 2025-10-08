#!/usr/bin/env bash
# Fase 2: HeadNode con DHCP/namespaces, gateways y NAT en ens3; OFS solo bridge de datos
set -euo pipefail

OFS_HOST=10.0.10.5
OFS_PORT=22
OFS_USER=ubuntu
OFS_PASS=ubuntu

HN_BR=br-hn
HN_UPLINK=ens4

V100_RANGE="192.168.100.10,192.168.100.200,12h"
V200_RANGE="192.168.200.10,192.168.200.200,12h"
V300_RANGE="192.168.30.10,192.168.30.200,12h"

GW100=192.168.100.1
GW200=192.168.200.1
GW300=192.168.30.1

OFS_BR=br-ofs
OFS_DATA_PORTS="ens5 ens6 ens7 ens8"
OFS_VLANS="100,200,300"

HN_WAN_IF=ens3

BASE="$HOME"
INIT_HN="${BASE}/init_headnode.sh"
NS_CREATE="${BASE}/ns_create.sh"
INIT_OFS_F1="${BASE}/init_ofs.sh"
INET_CONNECT="${BASE}/internet_conectivity.sh"

[[ -f "$INIT_HN" && -f "$NS_CREATE" && -f "$INIT_OFS_F1" && -f "$INET_CONNECT" ]] || { echo "Faltan scripts en $BASE"; exit 1; }

if ! command -v sshpass >/dev/null 2>&1; then
	echo "Instalando sshpass"
	sudo apt -y update && sudo apt -y install sshpass
fi

echo "HeadNode: init bridge $HN_BR (uplink $HN_UPLINK)"
sudo chmod +x "$INIT_HN" "$NS_CREATE" "$INIT_OFS_F1"
sudo "$INIT_HN" "$HN_BR" "$HN_UPLINK"

echo "Namespaces: ns100 ns200 ns300 con DHCP"
sudo "$NS_CREATE" ns100 "$HN_BR" 100 "$V100_RANGE" "$GW100"
sudo "$NS_CREATE" ns200 "$HN_BR" 200 "$V200_RANGE" "$GW200"
sudo "$NS_CREATE" ns300 "$HN_BR" 300 "$V300_RANGE" "$GW300"

echo "HeadNode: gateways vlan100/200/300 + NAT en $HN_WAN_IF"
for VID in 100 200 300; do
	INTPORT="vlan${VID}"
	GW_CIDR=""
	case "$VID" in
		100) GW_CIDR="${GW100}/24" ;;
		200) GW_CIDR="${GW200}/24" ;;
		300) GW_CIDR="${GW300}/24" ;;
	esac
	sudo ovs-vsctl --may-exist add-port "$HN_BR" "$INTPORT" tag="$VID" -- set Interface "$INTPORT" type=internal
	sudo ip addr flush dev "$INTPORT" || true
	sudo ip addr add "$GW_CIDR" dev "$INTPORT" 2>/dev/null || true
	sudo ip link set "$INTPORT" up
done

HN_BR="$HN_BR" HN_WAN_IF="$HN_WAN_IF" sudo -E "$INET_CONNECT" 100 >/dev/null || true
HN_BR="$HN_BR" HN_WAN_IF="$HN_WAN_IF" sudo -E "$INET_CONNECT" 200 >/dev/null || true
HN_BR="$HN_BR" HN_WAN_IF="$HN_WAN_IF" sudo -E "$INET_CONNECT" 300 >/dev/null || true

echo "OFS: bridge/trunks sin NAT"
sshpass -p "$OFS_PASS" scp -P "$OFS_PORT" -o StrictHostKeyChecking=no "$INIT_OFS_F1" "$OFS_USER@$OFS_HOST:~/init_ofs.sh"
sshpass -p "$OFS_PASS" ssh -p "$OFS_PORT" -o StrictHostKeyChecking=no "$OFS_USER@$OFS_HOST" bash -lc "set -e; \
	sudo chmod +x ~/init_ofs.sh; \
	OVS_BR=$OFS_BR IFACES='${OFS_DATA_PORTS}' TRUNKS='${OFS_VLANS}' sudo -E ./init_ofs.sh"

echo 'Fase 2 lista'
