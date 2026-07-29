#!/usr/bin/env bash

# Modify add WSL/Linux Vivado 2025.2 entry for the 4-flit 5x5 queue-knee sweep, Michael Tan, 20260714
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)" # Modify adjust repository root after scripts/simulation layout, Michael Tan, 20260729
SOURCE_DIR="${REPO_ROOT}/src"
TB_DIR="${REPO_ROOT}/testbench"
TOP="tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit"
SIM_DIR="${REPO_ROOT}/vivado_sim_wsl/${TOP}_sim"
VIVADO_ROOT="${VIVADO_ROOT:-/home/tanma/tools/Xilinx/2025.2/Vivado}"

SETTINGS_FILE="${VIVADO_ROOT}/settings64.sh"
if [[ ! -f "${SETTINGS_FILE}" ]]; then
    echo "ERROR: Vivado environment script not found: ${SETTINGS_FILE}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${SETTINGS_FILE}"

for tool in xvlog xelab xsim; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "ERROR: ${tool} is unavailable after sourcing ${SETTINGS_FILE}" >&2
        exit 1
    fi
done

SOURCE_FILES=(
    "${SOURCE_DIR}/noc.sv"
    "${SOURCE_DIR}/circular_buffer_Xiugai3.sv"
    "${SOURCE_DIR}/crossbar.sv"
    "${SOURCE_DIR}/input_block2crossbar.sv"
    "${SOURCE_DIR}/input_block2switch_allocator.sv"
    "${SOURCE_DIR}/input_block2vc_allocator.sv"
    "${SOURCE_DIR}/input_block_Xiugai2.sv"
    "${SOURCE_DIR}/input_buffer_src_circular_full.sv"
    "${SOURCE_DIR}/input_port_Xiugai2.sv"
    "${SOURCE_DIR}/mesh.sv"
    "${SOURCE_DIR}/node_link.sv"
    "${SOURCE_DIR}/rc_unit_Xiugai2.sv"
    "${SOURCE_DIR}/round_robin_arbiter.sv"
    "${SOURCE_DIR}/router.sv"
    "${SOURCE_DIR}/router2router.sv"
    "${SOURCE_DIR}/router_link.sv"
    "${SOURCE_DIR}/separable_input_first_allocator.sv"
    "${SOURCE_DIR}/switch_allocator2crossbar.sv"
    "${SOURCE_DIR}/switch_allocator_Xiugai1.sv"
    "${SOURCE_DIR}/vc_allocator.sv"
    "${TB_DIR}/${TOP}.sv"
)

for source_file in "${SOURCE_FILES[@]}"; do
    if [[ ! -f "${source_file}" ]]; then
        echo "ERROR: Expected source file is missing: ${source_file}" >&2
        exit 1
    fi
done

mkdir -p "${SIM_DIR}"

# Modify isolate and clean only this WSL sweep result directory for reproducible reruns, Michael Tan, 20260714
rm -rf -- "${SIM_DIR}/xsim.dir"
rm -f -- \
    "${SIM_DIR}/xvlog.log" \
    "${SIM_DIR}/xvlog.pb" \
    "${SIM_DIR}/xelab.log" \
    "${SIM_DIR}/xelab.pb" \
    "${SIM_DIR}/xsim.log" \
    "${SIM_DIR}/xsim.jou" \
    "${SIM_DIR}/out.vcd" \
    "${SIM_DIR}/injection_latency_results.txt" \
    "${SIM_DIR}/${TOP}_sim.wdb"

pushd "${SIM_DIR}" >/dev/null
trap 'popd >/dev/null' EXIT

echo "Compiling ${TOP} with Vivado from ${VIVADO_ROOT}."
xvlog --sv --relax --work xil_defaultlib "${SOURCE_FILES[@]}" --log xvlog.log

echo "Elaborating ${TOP}."
xelab --debug typical --relax --mt 2 \
    -L xil_defaultlib \
    --snapshot "${TOP}_sim" \
    "xil_defaultlib.${TOP}" \
    --log xelab.log

echo "Running ${TOP}."
xsim "${TOP}_sim" --runall --log xsim.log

echo "${TOP} simulation completed."
echo "Result directory: ${SIM_DIR}"
echo "Statistics: ${SIM_DIR}/injection_latency_results.txt"
echo "Log: ${SIM_DIR}/xsim.log"
echo "VCD: ${SIM_DIR}/out.vcd"
