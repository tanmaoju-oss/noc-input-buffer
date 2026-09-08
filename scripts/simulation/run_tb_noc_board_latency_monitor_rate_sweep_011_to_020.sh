#!/usr/bin/env bash

# Modify add WSL/Linux Vivado runner for the board 0.11-to-0.20 injection-rate comparison sweep, Michael Tan, 20260908
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/src"
TB_DIR="${REPO_ROOT}/testbench"
SIM_DIR="${REPO_ROOT}/vivado_sim_wsl/tb_noc_board_latency_monitor_rate_sweep_011_to_020_sim"
VIVADO_ROOT="${VIVADO_ROOT:-/home/tanma/tools/Xilinx/2025.2/Vivado}"
TOP="tb_noc_board_latency_monitor_rate_sweep_011_to_020"

# shellcheck disable=SC1090
source "${VIVADO_ROOT}/settings64.sh"

SOURCE_FILES=(
    "${SOURCE_DIR}/noc.sv" "${SOURCE_DIR}/circular_buffer_Xiugai3.sv" "${SOURCE_DIR}/crossbar.sv"
    "${SOURCE_DIR}/input_block2crossbar.sv" "${SOURCE_DIR}/input_block2switch_allocator.sv" "${SOURCE_DIR}/input_block2vc_allocator.sv"
    "${SOURCE_DIR}/input_block_Xiugai2.sv" "${SOURCE_DIR}/input_buffer_src_circular_full.sv" "${SOURCE_DIR}/input_port_Xiugai2.sv"
    "${SOURCE_DIR}/mesh.sv" "${SOURCE_DIR}/node_link.sv" "${SOURCE_DIR}/rc_unit_Xiugai2.sv"
    "${SOURCE_DIR}/round_robin_arbiter.sv" "${SOURCE_DIR}/router.sv" "${SOURCE_DIR}/router2router.sv"
    "${SOURCE_DIR}/router_link.sv" "${SOURCE_DIR}/separable_input_first_allocator.sv" "${SOURCE_DIR}/switch_allocator2crossbar.sv"
    "${SOURCE_DIR}/switch_allocator_Xiugai1.sv" "${SOURCE_DIR}/vc_allocator.sv"
    "${SOURCE_DIR}/board_ila/noc_board_traffic_generator.sv" "${SOURCE_DIR}/board_ila/noc_board_latency_monitor.sv"
    "${SOURCE_DIR}/board_ila/noc_board_ila_top.sv" "${TB_DIR}/${TOP}.sv"
)

RATE_PERMILLE=(110 120 130 140 150 160 170 180 190 200)
THRESHOLDS=(7209 7864 8521 9175 9830 10486 11141 11796 12452 13107)

mkdir -p "${SIM_DIR}"
rm -rf -- "${SIM_DIR}/xsim.dir"
rm -f -- "${SIM_DIR}"/*.log "${SIM_DIR}/board_latency_results.txt"

pushd "${SIM_DIR}" >/dev/null
xvlog --sv --relax --work xil_defaultlib "${SOURCE_FILES[@]}" --log xvlog.log
printf '%s\n' 'rate_permille injection_threshold enqueued queue_full tails unmatched overwrites total_latency_cycles avg_latency_cycles_x1000 mesh_errors' > board_latency_results.txt

for index in "${!RATE_PERMILLE[@]}"; do
    rate="${RATE_PERMILLE[index]}"
    threshold="${THRESHOLDS[index]}"
    snapshot="${TOP}_${rate}_sim"
    xelab -mt off --debug off --relax -L unisims_ver -L xil_defaultlib --snapshot "${snapshot}" \
        -generic_top "INJECTION_THRESHOLD=${threshold}" -generic_top "RATE_PERMILLE=${rate}" \
        "xil_defaultlib.${TOP}" --log "xelab_${rate}.log" #Modify serialize elaboration and disable unneeded WDB generation during the ten-point batch sweep, Michael Tan, 20260908
    xsim "${snapshot}" --runall --log "xsim_${rate}.log"
    awk -v expected_rate="${rate}" -v expected_threshold="${threshold}" '
        /\[TB_BOARD_MONITOR_RATE_SWEEP\] PASSED/ {
            for (i = 1; i <= NF; i++) {
                split($i, field, "=");
                if (field[1] == "rate_permille") rate = field[2];
                else if (field[1] == "threshold") threshold = field[2];
                else if (field[1] == "enqueued") enqueued = field[2];
                else if (field[1] == "queue_full") queue_full = field[2];
                else if (field[1] == "tails") tails = field[2];
                else if (field[1] == "unmatched") unmatched = field[2];
                else if (field[1] == "overwrites") overwrites = field[2];
                else if (field[1] == "total_latency") total_latency = field[2];
                else if (field[1] == "avg_latency_x1000") avg_latency = field[2];
                else if (field[1] == "mesh_errors") mesh_errors = field[2];
            }
            if (rate != expected_rate || threshold != expected_threshold) exit 2;
            print rate, threshold, enqueued, queue_full, tails, unmatched, overwrites, total_latency, avg_latency, mesh_errors;
            found = 1;
        }
        END { if (!found) exit 1; }
    ' "xsim_${rate}.log" >> board_latency_results.txt
    rm -rf -- "xsim.dir/${snapshot}" #Modify retain textual evidence while releasing each completed batch snapshot, Michael Tan, 20260908
done
popd >/dev/null

echo "${TOP} completed: ${SIM_DIR}/board_latency_results.txt"
