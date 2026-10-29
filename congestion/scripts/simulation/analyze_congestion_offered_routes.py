#!/usr/bin/env python3
# Modify reconstruct exact offered packet paths to separate unavoidable link demand from dynamic scheduling losses, Michael Tan, 20261029
import argparse
import csv
from collections import Counter
from pathlib import Path
from analyze_congestion_oe_audit import path

MASK = 0xffffffff


def mix(value):
    value &= MASK
    value = ((value ^ (value >> 16)) * 0x7feb352d) & MASK
    value = ((value ^ (value >> 15)) * 0x846ca68b) & MASK
    return value ^ (value >> 16)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, default=Path('congestion/docs'))
    args = parser.parse_args()
    with (args.reference / 'latency_summary.csv').open() as stream:
        ref = next(csv.DictReader(stream))
    seed, warmup, measure, rate = (int(ref[k]) for k in ('seed', 'warmup', 'measure', 'rate_ppm'))
    generated = [0] * 169
    offered = cohort = 0
    trace = 0x811c9dc5
    demand = {'XY': Counter(), 'OE': Counter()}
    for cycle in range(warmup + measure):
        for n in range(169):
            key = mix(seed ^ (((n + 1) * 0x9e3779b9) & MASK) ^ (((cycle + 1) * 0x85ebca6b) & MASK))
            if key % 1000000 >= rate:
                continue
            pid = generated[n]
            generated[n] += 1
            dest = mix(key ^ 0xa511e9b3) % 168
            if dest >= n:
                dest += 1
            offered += 1
            for value in (cycle, n * 512 + pid, dest):
                trace = ((trace ^ value) * 16777619) & MASK
            if cycle < warmup:
                continue
            cohort += 1
            for alg in demand:
                demand[alg].update(path(n % 13, n // 13, dest % 13, dest // 13, pid.bit_count() % 2, xy=(alg == 'XY')))
    if (offered, cohort, f'{trace:08x}') != (int(ref['offered_packets']), int(ref['cohort_packets']), ref['trace_hash']):
        raise ValueError('Reconstructed generation differs from actual RTL workload')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output = []
    for alg, loads in demand.items():
        overloaded = [(link, count * 4 / measure) for link, count in loads.items() if count * 4 > measure]
        print(alg, 'peak offered link flits/cycle', max(loads.values()) * 4 / measure, 'overloaded links', len(overloaded))
        print('top links', [(link, count * 4 / measure) for link, count in loads.most_common(10)])
        for link, count in sorted(loads.items()):
            output.append({'algorithm': alg, 'x': link[0], 'y': link[1], 'direction': link[2],
                           'cohort_packets_using_link': count, 'offered_flits_per_generation_cycle': count * 4 / measure})
    with (args.output_dir / 'current_offered_route_demand_20261029.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(output[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(output)
    print('Exact generation verified', offered, cohort, f'{trace:08x}')


if __name__ == '__main__':
    main()
