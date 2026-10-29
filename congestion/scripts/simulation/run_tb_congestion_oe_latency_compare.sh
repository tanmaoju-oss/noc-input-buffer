#!/usr/bin/env bash
# Modify pair independent OE control TB with isolated result directory, Michael Tan, 20261028
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_selfcheck.sh" tb_congestion_oe_latency_compare "$@"
