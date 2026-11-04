#!/usr/bin/env bash

# Modify derive isolated Torus integration runner, Michael Tan, 20261102
# Modify add reproducible WSL/Linux Vivado 2025.2 tb_torus_scheduler_profile runner, Michael Tan, 20260714
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)" # Modify adjust repository root after scripts/simulation layout, Michael Tan, 20260729
SOURCE_DIR="${REPO_ROOT}/src"
TB_DIR="${REPO_ROOT}/testbench"
SIM_DIR="${REPO_ROOT}/vivado_sim_wsl/tb_torus_scheduler_profile_sim"
VIVADO_ROOT="${VIVADO_ROOT:-/home/tanma/tools/Xilinx/2025.2/Vivado}"
TOP="tb_torus_scheduler_profile"
# Modify compile original Mesh independently and run a fixed matched campaign, Michael Tan, 20261104
MODE="${1:-torus}"
if [[ "$MODE" != sharedmesh && "$MODE" != torus ]]; then echo "Usage: $0 sharedmesh|torus" >&2; exit 1; fi
XELAB_OPTIONS=()
XVLOG_OPTIONS=()
if [[ "$MODE" == mesh ]]; then
    SOURCE_DIR="${REPO_ROOT}/../src"
    XVLOG_OPTIONS=(-d PERFORMANCE_MESH)
fi
if [[ "$MODE" == sharedmesh ]]; then XVLOG_OPTIONS=(-d PERFORMANCE_MESH); fi
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

if [[ "$MODE" == torus ]]; then SOURCE_FILES+=("${SOURCE_DIR}/torus.sv"); fi

for source_file in "${SOURCE_FILES[@]}"; do
    if [[ ! -f "${source_file}" ]]; then
        echo "ERROR: Expected source file is missing: ${source_file}" >&2
        exit 1
    fi
done

# Modify preserve each baseline run and its source fingerprint, Michael Tan, 20261102
mkdir -p "${SIM_DIR}"
SIM_DIR="$(mktemp -d "${SIM_DIR}/run_${MODE}_XXXXXXXX")"
sha256sum "${SOURCE_FILES[@]}" > "${SIM_DIR}/source_sha256.txt"

pushd "${SIM_DIR}" >/dev/null
trap 'popd >/dev/null' EXIT

echo "Compiling ${TOP} with Vivado from ${VIVADO_ROOT}."
xvlog --sv --relax --work xil_defaultlib "${XVLOG_OPTIONS[@]}" "${SOURCE_FILES[@]}" --log xvlog.log

echo "Elaborating ${TOP}."
xelab --debug typical --relax --mt 2 \
    -L xil_defaultlib \
    --snapshot "${TOP}_sim" \
    "xil_defaultlib.${TOP}" "${XELAB_OPTIONS[@]}" \
    --log xelab.log

# Modify six-case source admission and shared-module controls, Michael Tan, 20261104
# Modify fixed matrix; each case has its own trace, metrics and simulator log, Michael Tan, 20261104
for policy in 0 1; do
    rate=1200; seed=1; traffic=0
    case_dir="${SIM_DIR}/policy${policy}"
    mkdir -p "$case_dir"
    xsim "${TOP}_sim" --runall --testplusarg "POLICY=$policy" --testplusarg "RATE=$rate" --testplusarg "SEED=$seed" --testplusarg "TRAFFIC=$traffic" --testplusarg "OUT=$case_dir" --log "$case_dir/xsim.log" > "$case_dir/console.log" 2>&1
    if ! grep -Fq '[TB_TORUS_SCHEDULER_PROFILE] PASSED' "$case_dir/xsim.log" || grep -Eq 'Error:|Fatal:|ERROR:|FATAL:' "$case_dir/xsim.log"; then
        echo "ERROR: Self-check failed: $case_dir/xsim.log" >&2; exit 1
    fi
    echo "PASSED $MODE policy=$policy: $case_dir"
done
echo "Result directory: ${SIM_DIR}"
