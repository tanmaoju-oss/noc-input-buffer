#!/usr/bin/env bash
# Modify run isolated congestion self-check with retained logs, Michael Tan, 20261028
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TOP="${1:?top required}"; shift
source /home/tanma/tools/Xilinx/2025.2/Vivado/settings64.sh
mkdir -p "${PROJECT_ROOT}/vivado_sim_wsl/${TOP}_sim"
RUN_DIR="$(mktemp -d "${PROJECT_ROOT}/vivado_sim_wsl/${TOP}_sim/run_XXXXXXXX")"
cd "${RUN_DIR}"
printf 'TOP=%s\nARGS=%s\n' "${TOP}" "$*" > run_config.txt
FILES=(noc.sv input_block2crossbar.sv input_block2switch_allocator.sv input_block2vc_allocator.sv switch_allocator2crossbar.sv router2router.sv circular_buffer_Xiugai3.sv input_buffer_src_circular_full.sv congestion_decision.sv rc_unit_Xiugai2.sv input_port_Xiugai2.sv input_block_Xiugai2.sv crossbar.sv round_robin_arbiter.sv separable_input_first_allocator.sv vc_allocator.sv switch_allocator_Xiugai1.sv router.sv router_link.sv node_link.sv state_information_collection.sv mesh.sv)
SOURCES=()
for file in "${FILES[@]}"; do SOURCES+=("${PROJECT_ROOT}/src/${file}"); done
sha256sum "${SOURCES[@]}" "${PROJECT_ROOT}/testbench/${TOP}.sv" > source_sha256.txt
xvlog --sv --relax --work xil_defaultlib "${SOURCES[@]}" "${PROJECT_ROOT}/testbench/${TOP}.sv" --log xvlog.log
xelab --relax --mt 2 "xil_defaultlib.${TOP}" "$@" --snapshot test_sim --log xelab.log
xsim test_sim --runall --log xsim.log
if rg -n 'Fatal:|Error:|\[TB_.*\] FAILED' xsim.log; then exit 1; fi
rg -q '^\[TB_.*\] PASSED' xsim.log
printf 'Verified result: %s/xsim.log\n' "${RUN_DIR}"
