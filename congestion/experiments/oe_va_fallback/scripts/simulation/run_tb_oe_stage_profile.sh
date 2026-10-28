#!/usr/bin/env bash
# Modify pair nonintrusive stage/link profiling TB with isolated runs, Michael Tan, 20261028
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_experiment.sh" tb_oe_stage_profile 0 "$@"
