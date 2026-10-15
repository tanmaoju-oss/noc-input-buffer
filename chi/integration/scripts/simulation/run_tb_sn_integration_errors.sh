#!/usr/bin/env bash
# Modify by Michael Tan，20261015: isolated integration SN self-check using WSL Vivado 2025.2.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
VIVADO_ROOT="${VIVADO_ROOT:-/home/tanma/tools/Xilinx/2025.2/Vivado}"
TOP=tb_sn_integration_errors
# Preserve prior runs; latest_run.txt is updated only after verification succeeds.
RESULT_ROOT="${INTEGRATION_ROOT}/vivado_sim_wsl/${TOP}_sim"
mkdir -p "${RESULT_ROOT}"
RUN_DIR="$(mktemp -d "${RESULT_ROOT}/run_XXXXXXXX")"
set +u
source "${VIVADO_ROOT}/settings64.sh"
set -u
RTL="${INTEGRATION_ROOT}/src/sn"
SOURCES=("${RTL}/RxReq_Ch_new.v" "${RTL}/TxRsp_Ch_new.v" "${RTL}/TxDat_Ch_new.v"
         "${RTL}/RxDat_Ch_new.v" "${RTL}/SNF_AXI_Master_new.v" "${RTL}/SN_Top_new.v"
         "${INTEGRATION_ROOT}/testbench/${TOP}.sv")
printf 'SN error regression results: %s\n' "${RUN_DIR}"
cd "${RUN_DIR}"
xvlog --sv --work xil_defaultlib "${SOURCES[@]}" --log xvlog.log
xelab --debug typical --snapshot "${TOP}_sim" "xil_defaultlib.${TOP}" --log xelab.log
xsim "${TOP}_sim" --runall --log xsim.log
# The unsupported-opcode ERROR(req_if) print is an expected negative test.
# Modify by Michael Tan，20261015: reject scoreboard diagnostics as well as simulator failures.
if rg -n '(^ERROR:|CRITICAL WARNING|CHECK_ERROR|FATAL|FAIL|Error:|Fatal:)' xvlog.log xelab.log xsim.log; then
    exit 1
fi
rg -q '^PASS tb_sn_integration_errors$' xsim.log
rg -q '^\[SN_ERRORS\].* errors=0$' xsim.log
printf '%s\n' "${RUN_DIR}" > "${RESULT_ROOT}/latest_run.txt"
printf 'SN error regression PASSED: %s/xsim.log\n' "${RUN_DIR}"
