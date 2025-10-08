#!/usr/bin/env bash
# Crea namespace + veth + puerto OVS VLAN y dnsmasq 

set -euo pipefail

if [[ $# -lt 5 || $# -gt 6 ]]; then
  echo "Uso: $0 <NS_NAME> <OVS_BR> <VLAN_ID> \"<DHCP_RANGE>\" <ROUTER_IP> [NS_IP_CIDR]" >&2
  exit 1
fi

NS="$1"             
BR="$2"           
VLAN="$3"          
DHCP_RANGE="$4"    
ROUTER_IP="$5"      
NS_IP_CIDR="${6:-}" 

need() { command -v "$1" >/dev/null || { echo "Falta: $1" >&2; exit 1; }; }
need ip
need ovs-vsctl
need dnsmasq
HAS_SYSTEMD_RUN=0
if command -v systemd-run >/dev/null && [[ -d /run/systemd/system ]]; then
  HAS_SYSTEMD_RUN=1
else
  need setsid
fi
need awk
need sed
need sleep

VETH_NS="veth-${NS}"    
VETH_OVS="vo-${NS}"        
PID="/var/run/dnsmasq-${NS}.pid"
LEASES="/var/run/dnsmasq-${NS}.leases"
LOG="/var/log/dnsmasq-${NS}.log"
DNS_SERVERS_DEFAULT="8.8.8.8,1.1.1.1"
DNS_SERVERS="${DNS_SERVERS:-$DNS_SERVERS_DEFAULT}"

if [[ -z "$NS_IP_CIDR" ]]; then
  BASE="$(echo "$ROUTER_IP" | awk -F. '{print $1"."$2"."$3}')"
  NS_IP_CIDR="${BASE}.254/24"
fi

echo "NS=$NS VLAN=$VLAN BR=$BR IP=$NS_IP_CIDR gw=$ROUTER_IP range=$DHCP_RANGE"

ip netns add "$NS" 2>/dev/null || true

if ! ip link show "$VETH_OVS" &>/dev/null && ! ip netns exec "$NS" ip link show "$VETH_NS" &>/dev/null; then
  ip link add "$VETH_NS" type veth peer name "$VETH_OVS"
  ip link set "$VETH_NS" netns "$NS"
fi

if ip link show "$VETH_NS" &>/dev/null; then
  ip link set "$VETH_NS" netns "$NS" 2>/dev/null || true
fi

ip netns exec "$NS" ip link set lo up
ip netns exec "$NS" ip addr flush dev "$VETH_NS" 2>/dev/null || true
ip netns exec "$NS" ip addr add "$NS_IP_CIDR" dev "$VETH_NS" 2>/dev/null || true
ip netns exec "$NS" ip link set "$VETH_NS" up

if ! ip link show "$VETH_OVS" &>/dev/null; then
  ip link add "$VETH_NS" type veth peer name "$VETH_OVS" || true
  ip link set "$VETH_NS" netns "$NS" 2>/dev/null || true
  ip netns exec "$NS" ip link set "$VETH_NS" up
fi

ip link set "$VETH_OVS" up 2>/dev/null || true
ovs-vsctl --may-exist add-port "$BR" "$VETH_OVS" tag="$VLAN"
ovs-vsctl set port "$VETH_OVS" tag="$VLAN" >/dev/null

if [[ -f "$PID" ]]; then
  if kill -0 "$(cat "$PID")" 2>/dev/null; then
    kill "$(cat "$PID")" 2>/dev/null || true
    sleep 0.2
  fi
fi
pgrep -af "dnsmasq" | grep -E -- "--interface=${VETH_NS}(\s|$)" | awk '{print $1}' | xargs -r kill 2>/dev/null || true

rm -f "$PID" "$LEASES" "$LOG"
touch "$LEASES" "$LOG"
chmod 644 "$LEASES" "$LOG"

DNSMASQ_CMD=( ip netns exec "$NS" dnsmasq
  --keep-in-foreground --no-daemon --conf-file=/dev/null
  --log-async --log-facility="$LOG"
  --dhcp-authoritative
  --interface="$VETH_NS" --bind-interfaces --except-interface=lo
  --dhcp-range="$DHCP_RANGE"
  --dhcp-option=option:router,"$ROUTER_IP"
  --dhcp-option=option:dns-server,"$DNS_SERVERS"
  --pid-file="$PID"
  --dhcp-leasefile="$LEASES"
)

if [[ "$HAS_SYSTEMD_RUN" -eq 1 ]]; then
  systemd-run --quiet --unit="dnsmasq-${NS}" --description="dnsmasq for ${NS}" \
    -- "${DNSMASQ_CMD[@]}" >/dev/null 2>&1 || true
else
  ( setsid bash -c "${DNSMASQ_CMD[*]} >/dev/null 2>&1 & disown" ) >/dev/null 2>&1 || true
fi

sleep 1
if ip netns exec "$NS" ss -lunp | grep -q ":67"; then
  echo "NS ${NS} listo (IP ${NS_IP_CIDR}, VLAN ${VLAN}, gw ${ROUTER_IP})"
else
  echo "dnsmasq no escucha en ${NS}. Ver ${LOG}" >&2
  exit 1
fi

# Uso: sudo ./ns_create.sh <NS> <OVS_BR> <VLAN> "<DHCP_RANGE>" <ROUTER_IP> [NS_IP_CIDR]
