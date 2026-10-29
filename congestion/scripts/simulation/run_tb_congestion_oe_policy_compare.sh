#!/usr/bin/env bash
# Modify isolate existing output-selection policies with the same current-protocol router, Michael Tan, 20261029
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_selfcheck.sh" tb_congestion_oe_policy_compare "$@"
