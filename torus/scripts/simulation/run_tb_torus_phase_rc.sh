#!/usr/bin/env bash
# Modify provide independent tb_torus_phase_rc verification entry, Michael Tan, 20261104
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run_torus_phase_verification.sh" tb_torus_phase_rc "$@"
