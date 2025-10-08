#!/usr/bin/env bash
set -euo pipefail
echo "Fase 1…"
bash ./vm_orchestrator_fase1.sh
echo "Fase 2…"
bash ./vm_orchestrator_fase2.sh
echo "Topología completa"
