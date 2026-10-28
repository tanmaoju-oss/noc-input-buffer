#!/usr/bin/env bash
# Modify pair isolated mixed-hash verification entry, Michael Tan, 20261028
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_experiment.sh" tb_oe_hash_routes "$@"
