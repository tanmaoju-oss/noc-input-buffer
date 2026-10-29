#!/usr/bin/env python3
# Modify retain every trial and compare only identical mechanism/flow/workload XY-OE pairs, Michael Tan, 20261029
import argparse
import csv
import hashlib
import re
from pathlib import Path

INPUT_KEYS = ['rate_ppm', 'seed', 'warmup', 'measure', 'offered_packets', 'cohort_packets',
              'completed_packets', 'actual_offered_ppc', 'trace_hash']


def csv_rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', action='append', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, default=Path('congestion/docs'))
    args = parser.parse_args()
    records, unique = [], {}
    def norm(value):
        return re.sub(r'\s+', '', re.sub(r'//[^\n]*', '', value.replace('case_seed', 'SEED').replace('current_sample();', '')))
    def task_map(value):
        return {m.group(1):m.group(0) for m in re.finditer(r'task automatic (\w+).*?endtask', value, re.S)}
    original_tasks=task_map(Path('congestion/testbench/tb_congestion_admission_latency.sv').read_text())
    expected_changes={
        'oe_ready_candidates':{'circular_buffer_Xiugai3.sv','input_block2vc_allocator.sv','input_block_Xiugai2.sv','input_port_Xiugai2.sv','input_buffer_src_circular_full.sv','router.sv','vc_allocator.sv'},
        'oe_ready_matching':{'vc_allocator.sv'},
        'oe_ready_lookahead':{'input_block2vc_allocator.sv','input_block_Xiugai2.sv','input_port_Xiugai2.sv','router.sv','vc_allocator.sv'},
        'oe_ready_threehop':{'vc_allocator.sv'},
        'oe_ready_sa_matching':{'switch_allocator_Xiugai1.sv'},
        'oe_ready_aged':{'vc_allocator.sv','switch_allocator_Xiugai1.sv'},
    }
    baseline = {0: csv_rows(Path('congestion/vivado_sim_wsl/tb_congestion_admission_latency_sim/run_E0qbFekc/latency_summary.csv'))[0],
                2: csv_rows(Path('congestion/vivado_sim_wsl/tb_congestion_admission_latency_sim/run_EheVCm52/latency_summary.csv'))[0]}
    for root in args.root:
        with (root/'docs/parent_manifest.tsv').open() as stream:
            parent=list(csv.DictReader(stream,delimiter='\t'))
        changed={r['file'] for r in parent if hashlib.sha256((root/'src'/r['file']).read_bytes()).hexdigest()!=r['sha256']}
        if changed!=expected_changes[root.name]: raise ValueError(f'Unexpected parent changes {root}: {changed}')
        for run in sorted((root / 'vivado_sim_wsl').glob('*_sim/run_*')):
            if not (run / 'latency_summary.csv').exists() or not (run / 'xsim.log').exists():
                continue
            log = (run / 'xsim.log').read_text()
            if 'PASSED' not in log:
                print('INCOMPLETE_OR_FAILED retained', run)
                continue
            if 'Fatal:' in log or 'Error:' in log:
                raise ValueError(f'Unclean run {run}')
            tb=None
            for line in (run / 'source_sha256.txt').read_text().splitlines():
                digest, filename = line.split(maxsplit=1)
                if hashlib.sha256(Path(filename).read_bytes()).hexdigest() != digest:
                    raise ValueError(f'Changed run source {filename}')
                if '/testbench/' in filename: tb=Path(filename)
            tested_tasks=task_map(tb.read_text())
            for name,original in original_tasks.items():
                if norm(original)!=norm(tested_tasks[name]): raise ValueError(f'Changed traffic/scoreboard task {tb}: {name}')
            config = dict(line.split('=', 1) for line in (run / 'run_config.txt').read_text().splitlines())
            for row in csv_rows(run / 'latency_summary.csv'):
                alg, mode, flow = int(row['algorithm']), int(config['MODE']), int(config['FLOW'])
                if int(row['completed_packets']) != int(row['offered_packets']):
                    raise ValueError('Incomplete generated packet cohort')
                if alg in baseline and mode == 0 and flow == 0 and int(row['seed']) == 1234501 and int(row['rate_ppm']) == 60000:
                    if row != baseline[alg]:
                        raise ValueError(f'OFF control changed: {run}')
                sa = int(config.get('SA', '0'))
                age = int(config.get('AGE', '0'))
                key = (root.name, mode, flow, sa, age, alg, row['seed'], row['rate_ppm'], row['warmup'], row['measure'])
                if key in unique:
                    if unique[key]['data'] != row:
                        raise ValueError(f'Nonreproducing duplicate {key}')
                    print('EXACT_REPLICATE', run)
                    continue
                record = {'experiment': root.name, 'policy': mode, 'flow': flow, 'sa_full': sa, 'age_guard': age, **row, 'run_directory': str(run)}
                unique[key] = {'data': row, 'record': record}
                records.append(record)
    paired = []
    for key, value in unique.items():
        exp, mode, flow, sa, age, alg, seed, rate, warmup, measure = key
        if alg != 2:
            continue
        xy_key = (exp, mode, flow, sa, age, 0, seed, rate, warmup, measure)
        if xy_key not in unique:
            print('NO_SAME_POLICY_XY_REFERENCE', key)
            continue
        oe, xy = value['data'], unique[xy_key]['data']
        for k in INPUT_KEYS:
            if oe[k] != xy[k]:
                raise ValueError(f'Unfair pair {key}: {k}')
        result = {'experiment': exp, 'policy': mode, 'flow': flow, 'sa_full': sa, 'age_guard': age, 'seed': seed, 'rate_ppm': rate,
                  'xy_mean': xy['mean_total'], 'oe_mean': oe['mean_total'],
                  'oe_to_xy_ratio': float(oe['mean_total']) / float(xy['mean_total']),
                  'xy_p99': xy['p99_total'], 'oe_p99': oe['p99_total'], 'trace_hash': oe['trace_hash']}
        paired.append(result)
        print('FAIR_PAIR', result)
    # Preserve exact parent controls before crediting deeper scores or more complex matching.
    parents={('oe_ready_matching',2):('oe_ready_candidates',2),
             ('oe_ready_lookahead',3):('oe_ready_matching',3),
             ('oe_ready_threehop',4):('oe_ready_lookahead',4),
             ('oe_ready_sa_matching',5):('oe_ready_threehop',5)}
    for key,value in unique.items():
        if key[0]=='oe_ready_aged' and key[4]==0:
            parent_key=('oe_ready_sa_matching',*key[1:])
            if parent_key in unique and value['data']!=unique[parent_key]['data']: raise ValueError('Age OFF changed strict matching baseline')
        if (key[0],key[1]) in parents and key[3]==0 and key[4]==0:
            exp,mode=parents[(key[0],key[1])]
            parent_key=(exp,mode,*key[2:])
            if parent_key in unique and value['data']!=unique[parent_key]['data']:
                raise ValueError(f'Parent OFF control differs: {key}')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for filename, data in [('oe_ready_trials_20261029.csv', records), ('oe_ready_pairs_20261029.csv', paired)]:
        if not data:
            continue
        with (args.output_dir / filename).open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(data[0]), lineterminator='\n')
            writer.writeheader()
            writer.writerows(data)
    print('Checked runs', len(records), 'fair pairs', len(paired))


if __name__ == '__main__':
    main()
