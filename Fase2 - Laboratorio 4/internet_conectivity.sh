#!/usr/bin/env bash
set -euo pipefail
[[ $# -lt 1 ]] && { echo "uso: $0 <VLAN_ID>"; exit 1; }
VID="$1"
HN_BR="${HN_BR:-br-hn}"
HN_WAN_IF="${HN_WAN_IF:-ens3}"
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo iptables -C FORWARD -i "$HN_BR" -o "$HN_WAN_IF" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD 1 -i "$HN_BR" -o "$HN_WAN_IF" -j ACCEPT
sudo iptables -C FORWARD -i "$HN_WAN_IF" -o "$HN_BR" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD 1 -i "$HN_WAN_IF" -o "$HN_BR" -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -C POSTROUTING -o "$HN_WAN_IF" -j MASQUERADE 2>/dev/null || sudo iptables -t nat -I POSTROUTING 1 -o "$HN_WAN_IF" -j MASQUERADE
echo "OK $VID"
