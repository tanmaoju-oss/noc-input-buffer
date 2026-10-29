#!/usr/bin/env bash
# Modify run isolated nonintrusive occupancy diagnostics, Michael Tan, 20261029
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_experiment.sh" tb_oe_occupancy_profile 0 "$@"
