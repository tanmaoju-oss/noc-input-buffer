#!/usr/bin/env bash
# Modify provide paired congestion self-check entry, Michael Tan, 20261028
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_selfcheck.sh" tb_congestion_metrics "$@"
