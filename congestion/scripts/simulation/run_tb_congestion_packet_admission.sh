#!/usr/bin/env bash
# Modify run two-router packet admission safety regression, Michael Tan, 20261029
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/run_selfcheck.sh" tb_congestion_packet_admission "$@"
