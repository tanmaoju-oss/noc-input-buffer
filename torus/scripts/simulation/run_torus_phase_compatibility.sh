#!/usr/bin/env bash
# Modify retain maintained default-entry regression coverage after phase contract migration, Michael Tan, 20261104
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$REPO_ROOT/vivado_sim_wsl/torus_phase_campaign"
OUT="$(mktemp -d "$REPO_ROOT/vivado_sim_wsl/torus_phase_campaign/compatibility_XXXXXXXX")"
for top in tb_torus_rc tb_torus_integration tb_torus_congestion; do
  bash "$SCRIPT_DIR/run_${top}.sh" > "$OUT/${top}.log" 2>&1
  echo "PASS $top $(sed -n 's/^Result directory: //p' "$OUT/${top}.log" | tail -n 1)"
done
echo "Compatibility directory: $OUT"
