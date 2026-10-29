#!/usr/bin/env bash
# Modify run ingress release edge cases with isolated result directory, Michael Tan, 20261029
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_selfcheck.sh" tb_congestion_admission_edges "$@"
