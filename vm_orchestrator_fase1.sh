#!/bin/bash
# Script maestro para fase 1

# Inicializa Worker (ajusta interfaz si es necesario)
./init_worker.sh br-int ens4

# Crea VMs en el Worker
./vm_create.sh vm1 br-int 100 1
./vm_create.sh vm2 br-int 200 2
./vm_create.sh vm3 br-int 300 3

# (En el OFS, inicializa así:)
# ./init_ofs.sh br-ofs ens4 ens5 ens6
