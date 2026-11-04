#!/usr/bin/env bash
# Modify run declared functional and performance lanes with retained per-job logs, Michael Tan, 20261104
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LANE="${1:?functional or performance}"
case "$LANE" in
 functional) JOBS=(
   'rc 4 5 5' 'rc 8 5 5' 'vc_allocator 4 5 5' 'vc_allocator 16 5 5'
   'integration 4 5 5' 'integration 8 4 4' 'integration 8 2 3' 'integration 8 2 2' 'integration 16 5 5'
   'congestion 4 5 5' 'congestion 8 5 5' 'congestion 16 5 5'
   'singlehop mesh 5 5' 'singlehop legacy 5 5' 'singlehop 4 5 5' 'singlehop 8 5 5' 'singlehop 16 5 5');;
 performance) JOBS=('performance mesh 5 5' 'performance legacy 5 5' 'performance 4 5 5' 'performance 16 5 5');;
 *) echo 'Lane must be functional or performance' >&2;exit 1;;
esac
mkdir -p "$REPO_ROOT/vivado_sim_wsl/torus_phase_campaign"
CAMPAIGN="$(mktemp -d "$REPO_ROOT/vivado_sim_wsl/torus_phase_campaign/${LANE}_XXXXXXXX")"
printf 'top\tmode\tnx\tny\tresult\n' > "$CAMPAIGN/results.tsv"
for spec in "${JOBS[@]}"; do
 read -r feature mode nx ny <<< "$spec"
 top="tb_torus_phase_$feature"
 log="$CAMPAIGN/${feature}_${mode}_${nx}x${ny}.log"
 echo "START $spec"
 bash "$SCRIPT_DIR/run_torus_phase_verification.sh" "$top" "$mode" "$nx" "$ny" > "$log" 2>&1
 result="$(sed -n 's/^Result directory: //p' "$log" | tail -n 1)"
 [[ -n "$result" && -d "$result" ]]
 printf '%s\t%s\t%s\t%s\t%s\n' "$top" "$mode" "$nx" "$ny" "$result" >> "$CAMPAIGN/results.tsv"
 echo "PASS $spec $result"
done
echo "Campaign directory: $CAMPAIGN"
