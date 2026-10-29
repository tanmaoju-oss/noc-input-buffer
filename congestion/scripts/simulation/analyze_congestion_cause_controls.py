#!/usr/bin/env python3
# Modify verify matched-workload causal controls, source provenance and unchanged traffic/scoreboard tasks, Michael Tan, 20261029
import argparse
import csv
import hashlib
import re
from pathlib import Path

INPUT_KEYS = ['rate_ppm', 'seed', 'warmup', 'measure', 'offered_packets', 'cohort_packets',
              'completed_packets', 'actual_offered_ppc', 'trace_hash']


def read_row(run):
    log = (run / 'xsim.log').read_text()
    if 'PASSED' not in log or 'Fatal:' in log or 'Error:' in log:
        raise ValueError(f'Unclean simulation {run}')
    with (run / 'latency_summary.csv').open() as stream:
        records = list(csv.DictReader(stream))
    if len(records) != 1:
        raise ValueError('Expected one rate')
    return records[0]


def normalize(text):
    return re.sub(r'\s+', '', re.sub(r'//[^\n]*', '', text))


def tasks(text):
    return {m.group(1): m.group(0) for m in re.finditer(r'task automatic (\w+).*?endtask', text, re.S)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--run', action='append', required=True, help='label=run_directory')
    p.add_argument('--output-dir', type=Path, default=Path('congestion/docs'))
    args = p.parse_args()
    ref_xy = read_row(Path('congestion/vivado_sim_wsl/tb_congestion_admission_latency_sim/run_E0qbFekc'))
    ref_oe = read_row(Path('congestion/vivado_sim_wsl/tb_congestion_admission_latency_sim/run_EheVCm52'))
    baseline_tasks = tasks(Path('congestion/testbench/tb_congestion_admission_latency.sv').read_text())
    output = []
    manifests = {}
    for value in args.run:
        label, directory = value.split('=', 1)
        run = Path(directory)
        row = read_row(run)
        for key in INPUT_KEYS:
            if row[key] != ref_oe[key]:
                raise ValueError(f'{label} input mismatch: {key}')
        if label in ('XY', 'OE', 'VC_OFF', 'FLOW_OFF'):
            if row != (ref_xy if label == 'XY' else ref_oe):
                raise ValueError(f'{label} does not reproduce all 22 baseline fields')
        manifest = (run / 'source_sha256.txt').read_text()
        manifests[label] = manifest
        tb = None
        src = {}
        for line in manifest.splitlines():
            digest, filename = line.split(maxsplit=1)
            path = Path(filename)
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise ValueError(f'Final source mismatch: {path}')
            if '/src/' in filename:
                src[path.name] = digest
            else:
                tb = path
        if len(src) != 22 or tb is None:
            raise ValueError('Incomplete manifest')
        changes = [name for name, digest in src.items() if hashlib.sha256((Path('congestion/src') / name).read_bytes()).hexdigest() != digest]
        allowed = []
        if label.startswith('VC_'):
            allowed = ['vc_allocator.sv', 'router.sv']
        if label.startswith('FLOW_'):
            allowed = ['circular_buffer_Xiugai3.sv']
        if sorted(changes) != sorted(allowed):
            raise ValueError(f'Unexpected RTL changes {label}: {changes}')
        tested = tasks(tb.read_text())
        for name, original in baseline_tasks.items():
            observed = tested[name].replace('current_sample();', '')
            if normalize(original) != normalize(observed):
                raise ValueError(f'Changed workload/scoreboard task {label}: {name}')
        result = {'variant': label, 'algorithm': row['algorithm'], **{k: row[k] for k in INPUT_KEYS},
                  **{k: row[k] for k in ['mean_total', 'mean_queue', 'mean_network', 'p95_total', 'p99_total', 'finish_cycle', 'source_backlog_stop']},
                  'run_directory': str(run)}
        output.append(result)
        print(label, row['mean_total'], 'queue', row['mean_queue'], 'network', row['mean_network'], 'P99', row['p99_total'])
    for left, right in [('VC_OFF', 'VC_READY'), ('FLOW_OFF', 'FLOW_READY_OE'), ('FLOW_OFF', 'FLOW_READY_XY')]:
        if left in manifests and right in manifests and manifests[left] != manifests[right]:
            raise ValueError(f'OFF/ON source files differ: {left}/{right}')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / 'current_cause_controls_20261029.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(output[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(output)
    print('All controls, source hashes, allowed RTL differences and common traffic/scoreboard tasks verified.')


if __name__ == '__main__':
    main()
