#!/usr/bin/env bash

# Modify add WSL/Linux Vivado runner for the independent 0.01-rate board latency diagnostic, Michael Tan, 20260827
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/src"
TB_DIR="${REPO_ROOT}/testbench"
SIM_DIR="${REPO_ROOT}/vivado_sim_wsl/tb_noc_board_latency_monitor_windowed_rate_001_sim"
VIVADO_ROOT="${VIVADO_ROOT:-/home/tanma/tools/Xilinx/2025.2/Vivado}"
TOP="tb_noc_board_latency_monitor_windowed_rate_001"

# shellcheck disable=SC1090
source "${VIVADO_ROOT}/settings64.sh"

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
    "${SOURCE_DIR}/board_ila/noc_board_traffic_generator.sv"
    "${SOURCE_DIR}/board_ila/noc_board_latency_monitor.sv"
    "${SOURCE_DIR}/board_ila/noc_board_ila_top.sv"
    "${TB_DIR}/${TOP}.sv"
)

mkdir -p "${SIM_DIR}"
rm -rf -- "${SIM_DIR}/xsim.dir"
rm -f -- "${SIM_DIR}/xvlog.log" "${SIM_DIR}/xelab.log" "${SIM_DIR}/xsim.log"

pushd "${SIM_DIR}" >/dev/null
xvlog --sv --relax --work xil_defaultlib "${SOURCE_FILES[@]}" --log xvlog.log
xelab --debug typical --relax -L unisims_ver -L xil_defaultlib --snapshot "${TOP}_sim" "xil_defaultlib.${TOP}" --log xelab.log
xsim "${TOP}_sim" --runall --log xsim.log
popd >/dev/null

echo "${TOP} completed: ${SIM_DIR}/xsim.log"
