#!/usr/bin/env bash
# Workers + OFS (bridge/trunks) + 9 VMs
set -euo pipefail

W2_HOST=10.0.10.2
W3_HOST=10.0.10.3
W4_HOST=10.0.10.4
OFS_HOST=10.0.10.5

W_USER=ubuntu
W_PASS=cocacola

OFS_USER=ubuntu
OFS_PASS=ubuntu

OVS_BR_WORKER=br-int
UPLINK_IF=ens4
OVS_BR_OFS=br-ofs
TRUNKS="100,200,300"

BASE="$HOME"
INIT_WORKER="${BASE}/init_worker.sh"
INIT_OFS_F1="${BASE}/init_ofs.sh"
VM_CREATE="${BASE}/vm_create.sh"
IMG_LOCAL_PATH="${BASE}/cirros-0.5.1-x86_64-disk.img"

for f in "$INIT_WORKER" "$INIT_OFS_F1" "$VM_CREATE"; do
  [[ -f "$f" ]] || { echo "Falta $f"; exit 1; }
done

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Instalando sshpass"
  sudo apt -y update && sudo apt -y install sshpass
fi

echo "Copiando scripts a workers"
for H in "$W2_HOST" "$W3_HOST" "$W4_HOST"; do
  sshpass -p "$W_PASS" scp -o StrictHostKeyChecking=no "$INIT_WORKER" "$VM_CREATE" "${W_USER}@${H}:~/"
done

if [[ -f "$IMG_LOCAL_PATH" ]]; then
  echo "Distribuyendo imagen base a workers"
  for H in "$W2_HOST" "$W3_HOST" "$W4_HOST"; do
    sshpass -p "$W_PASS" scp -o StrictHostKeyChecking=no "$IMG_LOCAL_PATH" "${W_USER}@${H}:/tmp/cirros-0.5.1-x86_64-disk.img"
    sshpass -p "$W_PASS" ssh -o StrictHostKeyChecking=no "${W_USER}@${H}" bash -lc "set -e; \
      sudo mkdir -p /var/lib/images; \
      sudo mv /tmp/cirros-0.5.1-x86_64-disk.img /var/lib/images/cirros-0.5.1-x86_64-disk.img || true; \
      sudo chown root:root /var/lib/images/cirros-0.5.1-x86_64-disk.img"
  done
else
  echo "Imagen base no encontrada en $IMG_LOCAL_PATH; se asumirá que existe en los workers"
fi

echo "Copiando init_ofs.sh al OFS"
sshpass -p "$OFS_PASS" scp -o StrictHostKeyChecking=no "$INIT_OFS_F1" "${OFS_USER}@${OFS_HOST}:~/"

echo "Inicializando workers (bridge $OVS_BR_WORKER + uplink $UPLINK_IF)"
for H in "$W2_HOST" "$W3_HOST" "$W4_HOST"; do
  sshpass -p "$W_PASS" ssh -o StrictHostKeyChecking=no "${W_USER}@${H}" bash -lc "set -e; \
sudo chmod +x ~/init_worker.sh ~/vm_create.sh; \
sudo ./init_worker.sh $OVS_BR_WORKER $UPLINK_IF"
done

echo "Inicializando OFS (trunks $TRUNKS)"
sshpass -p "$OFS_PASS" ssh -o StrictHostKeyChecking=no "${OFS_USER}@${OFS_HOST}" bash -lc "set -e; \
sudo chmod +x ~/init_ofs.sh; \
OVS_BR=$OVS_BR_OFS IFACES='ens5 ens6 ens7 ens8' TRUNKS='$TRUNKS' sudo -E ./init_ofs.sh"

echo "Creando VMs (3 por worker: VLAN 100/200/300)"
create_triple () {
  local host="$1" pass="$2" prefix="$3"
  sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "ubuntu@${host}" bash -lc "set -e; \
sudo ./vm_create.sh ${prefix}vm1 $OVS_BR_WORKER 100 11 --persist; \
sudo ./vm_create.sh ${prefix}vm2 $OVS_BR_WORKER 200 12 --persist; \
sudo ./vm_create.sh ${prefix}vm3 $OVS_BR_WORKER 300 13 --persist"
}
create_triple "$W2_HOST" "$W_PASS" "w2"
create_triple "$W3_HOST" "$W_PASS" "w3"
create_triple "$W4_HOST" "$W_PASS" "w4"

echo "Fase 1 lista"
