#!/usr/bin/env bash
# Modify isolate fixed legal two-hop ranking from the maximum-matching control, Michael Tan, 20261029
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TOP=tb_oe_aged_va_fairness
MODE="${1:?policy 0/1/2 required}"; shift
FLOW="${1:?flow 0/1 required}"; shift
[[ "${MODE}" == 0 || "${MODE}" == 1 || "${MODE}" == 2 || "${MODE}" == 3 || "${MODE}" == 4 || "${MODE}" == 5 ]] || exit 2
[[ "${FLOW}" == 0 || "${FLOW}" == 1 ]] || exit 2
SA="${1:?SA mode 0/1 required}"; shift
[[ "${SA}" == 0 || "${SA}" == 1 ]] || exit 2
AGE="${1:?age guard 0/1 required}"; shift
[[ "${AGE}" == 0 || "${AGE}" == 1 ]] || exit 2
DEFINES=(--define "OE_READY_SELECTION_MODE=${MODE}")
if [[ "${FLOW}" == 1 ]]; then DEFINES+=(--define CURRENT_FAST_REOPEN); fi
if [[ "${SA}" == 1 ]]; then DEFINES+=(--define READY_FULL_SA); fi
if [[ "${AGE}" == 0 ]]; then DEFINES+=(--define READY_AGE_GUARD_DISABLED); fi
source /home/tanma/tools/Xilinx/2025.2/Vivado/settings64.sh
mkdir -p "${PROJECT_ROOT}/vivado_sim_wsl/${TOP}_sim"
RUN_DIR="$(mktemp -d "${PROJECT_ROOT}/vivado_sim_wsl/${TOP}_sim/run_mode${MODE}_flow${FLOW}_sa${SA}_age${AGE}_XXXXXXXX")"
cd "${RUN_DIR}"
printf 'TOP=%s\nMODE=%s\nFLOW=%s\nSA=%s\nAGE=%s\nDEFINES=%s\nARGS=%s\n' "${TOP}" "${MODE}" "${FLOW}" "${SA}" "${AGE}" "${DEFINES[*]}" "$*" > run_config.txt
FILES=(noc.sv input_block2crossbar.sv input_block2switch_allocator.sv input_block2vc_allocator.sv switch_allocator2crossbar.sv router2router.sv circular_buffer_Xiugai3.sv input_buffer_src_circular_full.sv congestion_decision.sv rc_unit_Xiugai2.sv input_port_Xiugai2.sv input_block_Xiugai2.sv crossbar.sv round_robin_arbiter.sv separable_input_first_allocator.sv vc_allocator.sv switch_allocator_Xiugai1.sv router.sv router_link.sv node_link.sv state_information_collection.sv mesh.sv)
SOURCES=()
for file in "${FILES[@]}"; do SOURCES+=("${PROJECT_ROOT}/src/${file}"); done
sha256sum "${SOURCES[@]}" "${PROJECT_ROOT}/testbench/${TOP}.sv" > source_sha256.txt
xvlog --sv --relax "${DEFINES[@]}" --work xil_defaultlib "${SOURCES[@]}" "${PROJECT_ROOT}/testbench/${TOP}.sv" --log xvlog.log
xelab --relax --mt 2 "xil_defaultlib.${TOP}" -generic_top "POLICY_MODE=${MODE}" -generic_top "FAST_REOPEN=${FLOW}" -generic_top "SA_FULL=${SA}" -generic_top "AGE_GUARD=${AGE}" "$@" --snapshot test_sim --log xelab.log
xsim test_sim --runall --log xsim.log
if rg -n 'Fatal:|Error:|\[TB_.*\] FAILED' xsim.log; then exit 1; fi
rg -q '^\[TB_.*\] PASSED' xsim.log
printf 'Verified result: %s/xsim.log\n' "${RUN_DIR}"
