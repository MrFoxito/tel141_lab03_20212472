#!/usr/bin/env bash
# Limpia todo el lab para ir probando que si funcione el script de orquestacion final
set -euo pipefail

W2=10.0.10.2; W3=10.0.10.3; W4=10.0.10.4
W_USER=ubuntu; W_PASS="cocacola"; W_SSH_PORT="${W_SSH_PORT:-22}"

OFS=10.0.10.5; OFS_USER=ubuntu; OFS_PASS="ubuntu"

HN_PASS="${HN_PASS:-}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Instalando sshpass"
  sudo apt -y update && sudo apt -y install sshpass
fi

clean_worker() {
  local HOST="$1"
  echo "worker $HOST: limpiando VMs, TAPs y br-int"
  sshpass -p "$W_PASS" ssh -p "$W_SSH_PORT" $SSH_OPTS "$W_USER@$HOST" "PASS='$W_PASS' bash -s" <<'EOF'
set -e
s(){ echo "\$PASS" | sudo -S -p '' "\$@"; }

s pkill -f qemu-system-x86_64 2>/dev/null || true
s pkill -f qemu-kvm 2>/dev/null || true

if s ovs-vsctl br-exists br-int 2>/dev/null; then
  s ovs-vsctl list-ports br-int 2>/dev/null | grep -E '_tap' | while read -r p; do
    [ -n "\$p" ] || continue
    s ovs-vsctl del-port br-int "\$p" 2>/dev/null || true
    s ip link del "\$p" 2>/dev/null || true
  done || true
  s ip link set br-int down 2>/dev/null || true
  s ovs-vsctl del-br br-int 2>/dev/null || true
  s ip link del br-int 2>/dev/null || true
else
  # Si OVS no reporta el bridge pero la interfaz existe, bórrala igual
  s ip link del br-int 2>/dev/null || true
fi

if command -v ip >/dev/null 2>&1; then
  ip tuntap list 2>/dev/null | awk -F: '/_tap/ {print $1}' | while read -r t; do
    [ -n "\$t" ] || continue
    s ip link del "\$t" 2>/dev/null || true
  done
fi
EOF
}

clean_ofs() {
  sshpass -p "$OFS_PASS" ssh $SSH_OPTS "$OFS_USER@$OFS" "PASS='$OFS_PASS' bash -s" <<'EOF'
set -e
s(){ echo "\$PASS" | sudo -S -p '' "\$@"; }

if s ovs-vsctl br-exists br-ofs 2>/dev/null; then
  # Remover posibles puertos internal usados como gateways (gw* o vlan*)
  for gw in gw100 gw200 gw300 vlan100 vlan200 vlan300; do
    s ip addr flush dev "\$gw" 2>/dev/null || true
    s ip link set "\$gw" down 2>/dev/null || true
    s ovs-vsctl del-port br-ofs "\$gw" 2>/dev/null || true
  done

  s ovs-vsctl list-ports br-ofs 2>/dev/null | while read -r p; do
    [ -n "\$p" ] || continue
    s ovs-vsctl del-port br-ofs "\$p" 2>/dev/null || true
  done

  s ip link set br-ofs down 2>/dev/null || true
  s ovs-vsctl del-br br-ofs 2>/dev/null || true
fi

WAN_IF="\$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
if [ -n "\$WAN_IF" ]; then
  s iptables -t nat -C POSTROUTING -o "\$WAN_IF" -j MASQUERADE 2>/dev/null && \
    s iptables -t nat -D POSTROUTING -o "\$WAN_IF" -j MASQUERADE || true
  s iptables -C FORWARD -i br-ofs -o "\$WAN_IF" -j ACCEPT 2>/dev/null && \
    s iptables -D FORWARD -i br-ofs -o "\$WAN_IF" -j ACCEPT || true
  s iptables -C FORWARD -i "\$WAN_IF" -o br-ofs -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null && \
    s iptables -D FORWARD -i "\$WAN_IF" -o br-ofs -m state --state ESTABLISHED,RELATED -j ACCEPT || true
fi
EOF
}

clean_headnode() {
  if [[ -n "$HN_PASS" ]]; then
    s(){ echo "$HN_PASS" | sudo -S -p '' "$@"; }
  else
    s(){ sudo -n "$@" ; }
  fi

  ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^(ns|ns-vlan)[0-9]+' | while read -r NS; do
    [ -n "$NS" ] || continue
    s ip netns pids "$NS" >/dev/null 2>&1 && s ip netns exec "$NS" pkill -f dnsmasq || true
    s ip netns del "$NS" 2>/dev/null || true
  done || true

  s rm -f /var/run/dnsmasq-*.pid /var/run/dnsmasq-*.leases /var/log/dnsmasq-*.log 2>/dev/null || true

  for BR in br-hn br-int; do
    if s ovs-vsctl br-exists "$BR" 2>/dev/null; then
      for vid in 100 200 300; do
        s ip addr flush dev "vlan$vid" 2>/dev/null || true
        s ip link set "vlan$vid" down 2>/dev/null || true
        s ovs-vsctl del-port "$BR" "vlan$vid" 2>/dev/null || true
      done
      s ovs-vsctl list-ports "$BR" 2>/dev/null | grep -E '^(vo-ns|veth-ns|veth-gw)' | while read -r p; do
        [ -n "$p" ] || continue
        s ovs-vsctl del-port "$BR" "$p" 2>/dev/null || true
      done
      s ip link set "$BR" down 2>/dev/null || true
      s ovs-vsctl del-br "$BR" 2>/dev/null || true
    fi
  done

  for BR in br-hn br-int; do
    if ip link show "$BR" >/dev/null 2>&1; then
      s iptables -C FORWARD -i "$BR" -o ens3 -j ACCEPT 2>/dev/null && s iptables -D FORWARD -i "$BR" -o ens3 -j ACCEPT || true
      s iptables -C FORWARD -i ens3 -o "$BR" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null && s iptables -D FORWARD -i ens3 -o "$BR" -m state --state ESTABLISHED,RELATED -j ACCEPT || true
    else
      s iptables -C FORWARD -i "$BR" -o ens3 -j ACCEPT 2>/dev/null && s iptables -D FORWARD -i "$BR" -o ens3 -j ACCEPT || true
      s iptables -C FORWARD -i ens3 -o "$BR" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null && s iptables -D FORWARD -i ens3 -o "$BR" -m state --state ESTABLISHED,RELATED -j ACCEPT || true
    fi
  done
  s iptables -t nat -C POSTROUTING -o ens3 -j MASQUERADE 2>/dev/null && s iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE || true
}

echo "Limpiando workers"
clean_worker "$W2"
clean_worker "$W3"
clean_worker "$W4"

echo "Limpiando HeadNode"
clean_headnode

echo "Limpiando OFS"
clean_ofs

echo "Limpieza lista"
