#!/usr/bin/env bash
# Modify isolate phase-replicated configurations, immutable legacy control and common verification setup, Michael Tan, 20261104
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TOP="${1:?top required}"; MODE="${2:-8}"; NX="${3:-5}"; NY="${4:-5}"
case "$TOP" in tb_torus_phase_rc|tb_torus_phase_vc_allocator|tb_torus_phase_integration|tb_torus_phase_congestion|tb_torus_phase_performance|tb_torus_phase_singlehop) ;; *) echo 'Invalid top' >&2; exit 1;; esac
case "$MODE" in 4|8|16|legacy|mesh) ;; *) echo 'Mode must be 4, 8, 16, legacy or mesh' >&2; exit 1;; esac
[[ "$NX" =~ ^[2-8]$ && "$NY" =~ ^[2-8]$ ]] || { echo 'Geometry must be 2..8' >&2; exit 1; }
# Modify reject source modes whose package contract cannot support phase-only unit tests, Michael Tan, 20261104
if [[ "$MODE" == legacy || "$MODE" == mesh ]]; then
  [[ "$TOP" == tb_torus_phase_performance || "$TOP" == tb_torus_phase_singlehop ]] || { echo 'Legacy/Mesh modes support performance and singlehop only' >&2; exit 1; }
fi
VIVADO_ROOT="${VIVADO_ROOT:-/home/tanma/tools/Xilinx/2025.2/Vivado}"
[[ -f "$VIVADO_ROOT/settings64.sh" ]]
source "$VIVADO_ROOT/settings64.sh"
SIM_DIR="${REPO_ROOT}/vivado_sim_wsl/${TOP}_sim"
mkdir -p "$SIM_DIR"
SIM_DIR="$(mktemp -d "${SIM_DIR}/run_${MODE}_${NX}x${NY}_XXXXXXXX")"
SOURCE_DIR="${REPO_ROOT}/src"
XVLOG_OPTIONS=(); XELAB_OPTIONS=()
SOURCE_NAMES=(noc.sv circular_buffer_Xiugai3.sv crossbar.sv input_block2crossbar.sv input_block2switch_allocator.sv input_block2vc_allocator.sv input_block_Xiugai2.sv input_buffer_src_circular_full.sv input_port_Xiugai2.sv mesh.sv node_link.sv rc_unit_Xiugai2.sv round_robin_arbiter.sv router.sv router2router.sv router_link.sv separable_input_first_allocator.sv switch_allocator2crossbar.sv switch_allocator_Xiugai1.sv vc_allocator.sv)
case "$MODE" in
  mesh) SOURCE_DIR="${REPO_ROOT}/../src"; XVLOG_OPTIONS=(-d PERFORMANCE_MESH);;
  legacy)
    LEGACY_COMMIT=3c31c2b
    SOURCE_DIR="${SIM_DIR}/legacy_src"; mkdir -p "$SOURCE_DIR"
    git -C "$REPO_ROOT" rev-parse "$LEGACY_COMMIT" > "$SIM_DIR/legacy_commit.txt"
    for name in "${SOURCE_NAMES[@]}" torus.sv; do git -C "$REPO_ROOT" show "${LEGACY_COMMIT}:torus/src/${name}" > "$SOURCE_DIR/$name"; done
    ;;
  *) XVLOG_OPTIONS=(-d "NOC_VC_NUM=$MODE");;
esac
[[ "$MODE" == mesh ]] || SOURCE_NAMES+=(torus.sv)
SOURCE_FILES=(); for name in "${SOURCE_NAMES[@]}"; do SOURCE_FILES+=("$SOURCE_DIR/$name"); done
SOURCE_FILES+=("${REPO_ROOT}/testbench/${TOP}.sv")
for name in "${SOURCE_FILES[@]}"; do [[ -f "$name" ]]; done
sha256sum "${SOURCE_FILES[@]}" > "$SIM_DIR/source_sha256.txt"
printf '%s\n' "top=$TOP mode=$MODE nx=$NX ny=$NY endpoint_vcs=4 buffer_depth=8 performance_source_vc=id%4" > "$SIM_DIR/configuration.txt"
if [[ "$TOP" == tb_torus_phase_integration || "$TOP" == tb_torus_phase_congestion ]]; then
  XELAB_OPTIONS=(-generic_top "NX=$NX" -generic_top "NY=$NY")
fi
pushd "$SIM_DIR" >/dev/null
trap 'popd >/dev/null' EXIT
xvlog --sv --relax --work xil_defaultlib "${XVLOG_OPTIONS[@]}" "${SOURCE_FILES[@]}" --log xvlog.log
xelab --debug typical --relax --mt 2 -L xil_defaultlib --snapshot "${TOP}_sim" "xil_defaultlib.${TOP}" "${XELAB_OPTIONS[@]}" --log xelab.log
run_case() {
  local case_name="$1"; shift
  local case_dir="$SIM_DIR/$case_name"
  mkdir -p "$case_dir"
  xsim "${TOP}_sim" --runall "$@" --testplusarg "OUT=$case_dir" --log "$case_dir/xsim.log" > "$case_dir/console.log" 2>&1
  local marker="[${TOP^^}] PASSED"
  if ! grep -Fq "$marker" "$case_dir/xsim.log" || grep -Eq 'Error:|Fatal:|ERROR:|FATAL:' "$case_dir/xsim.log"; then
    echo "ERROR: self-check failed: $case_dir/xsim.log" >&2; exit 1
  fi
  echo "PASSED $TOP mode=$MODE $case_name: $case_dir"
}
case "$TOP" in
  tb_torus_phase_performance)
    for spec in '100 1 0' '400 1 0' '800 1 0' '1200 1 0' '100 42 0' '400 42 0' '800 42 0' '1200 42 0' '400 1 1' '800 1 1'; do
      read -r rate seed traffic <<< "$spec"
      run_case "rate${rate}_seed${seed}_traffic${traffic}" --testplusarg "RATE=$rate" --testplusarg "SEED=$seed" --testplusarg "TRAFFIC=$traffic"
    done;;
  tb_torus_phase_singlehop) for length in 4 16; do run_case "length$length" --testplusarg "LENGTH=$length"; done;;
  *) run_case case;;
esac
echo "Result directory: $SIM_DIR"
