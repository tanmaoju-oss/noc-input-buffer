#!/usr/bin/env python3
# Modify audit paired traffic and emit reproducible latency/throughput comparison, Michael Tan, 20261104
import argparse
import csv
import hashlib
import math
from pathlib import Path
from statistics import mean


def rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def percentile(values, quantile):
    return sorted(values)[math.ceil(len(values) * quantile) - 1]


def analyze(mesh, torus, output):
    expected = {(rate, seed, 0) for rate in (100, 400, 800, 1200) for seed in (1, 42)}
    expected |= {(rate, 1, 1) for rate in (400, 800)}
    results = []
    for root in (mesh, torus):
        for line in (root / 'source_sha256.txt').read_text().splitlines():
            digest, name = line.split(maxsplit=1)
            assert hashlib.sha256(Path(name.strip()).read_bytes()).hexdigest() == digest, name
        actual = {tuple(map(int, (r['rate'], r['seed'], r['traffic'])))
                  for p in root.glob('rate*/summary.csv') for r in rows(p)}
        assert actual == expected, (root, actual)
    for rate, seed, traffic in sorted(expected):
        case = f'rate{rate}_seed{seed}_traffic{traffic}'
        traces = [(root / case / 'trace.csv').read_bytes() for root in (mesh, torus)]
        assert traces[0] == traces[1], f'traffic differs: {case}'
        trace = rows(mesh / case / 'trace.csv')
        for label, root in (('Mesh', mesh), ('Torus', torus)):
            directory = root / case
            log = (directory / 'xsim.log').read_text()
            assert '[TB_TORUS_PERFORMANCE] PASSED' in log
            assert not any(s in log for s in ('Fatal:', 'Error:', 'ERROR:', 'FATAL:'))
            summary = {k: int(v) for k, v in rows(directory / 'summary.csv')[0].items()}
            packets = [{k: int(v) for k, v in r.items()} for r in rows(directory / 'packets.csv')]
            assert len(trace) == len(packets) == summary['generated'] == summary['completed']
            assert summary['flits'] == 4 * len(packets)
            hops = 0
            for index, (p, t) in enumerate(zip(packets, trace)):
                assert p['id'] == int(t['id']) == index
                assert p['birth'] == int(t['birth']) <= p['head_in'] <= p['tail_out']
                hx = abs(int(t['sx']) - int(t['dx']))
                hy = abs(int(t['sy']) - int(t['dy']))
                hops += (min(hx, 5-hx) + min(hy, 5-hy)) if label == 'Torus' else hx+hy
            assert summary['link_flits'] == 4*hops
            sample = [p for p in packets if 1000 < p['birth'] <= 4000]
            latency = [p['tail_out'] - p['birth'] + 1 for p in sample]
            network = [p['tail_out'] - p['head_in'] + 1 for p in sample]
            queue = [p['head_in'] - p['birth'] for p in sample]
            assert abs(mean(latency)-mean(network)-mean(queue)) < 1e-9
            results.append(dict(topology=label, rate=rate/10000, seed=seed,
                                traffic='uniform' if traffic == 0 else 'wrap_diagonal',
                                generated=len(packets), sample=len(sample), mean_latency=mean(latency),
                                p95=percentile(latency, .95), p99=percentile(latency, .99),
                                network_latency=mean(network), source_queue=mean(queue),
                                window_in=summary['window_in']/(25*3000),
                                window_out=summary['window_out']/(25*3000),
                                drain_cycles=summary['last_cycle']-4000,
                                mean_hops=hops/len(packets),
                                trace_sha256=hashlib.sha256(traces[0]).hexdigest(), run=str(directory)))
    output.mkdir(parents=True, exist_ok=True)
    # Modify preserve exact compiled-source manifests beside portable result tables, Michael Tan, 20261104
    for label, root in (('mesh', mesh), ('torus', torus)):
        (output/f'{label}_source_sha256.txt').write_bytes((root/'source_sha256.txt').read_bytes())
    with (output/'comparison.csv').open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n", fieldnames=results[0].keys())
        writer.writeheader(); writer.writerows(results)
    lines=['| 流量 | 种子 | 注入率（包/节点/周期） | Mesh 均延迟 | Torus 均延迟 | 延迟变化 | Mesh / Torus P99 | Mesh / Torus 窗口输出 |',
           '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for m,t in zip(results[::2], results[1::2]):
        lines.append(f"| {m['traffic']} | {m['seed']} | {m['rate']:.2f} | {m['mean_latency']:.3f} | {t['mean_latency']:.3f} | {(t['mean_latency']/m['mean_latency']-1)*100:+.2f}% | {m['p99']} / {t['p99']} | {m['window_out']:.4f} / {t['window_out']:.4f} |")
    (output/'table.md').write_text('\n'.join(lines)+'\n')
    (output/'audit.txt').write_text(f'PASS: 10 exact trace pairs, 20 simulator PASS logs, all packets/timestamps/hops and current source SHA256 verified.\nMesh: {mesh}\nTorus: {torus}\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mesh', type=Path)
    parser.add_argument('torus', type=Path)
    parser.add_argument('output', type=Path)
    args=parser.parse_args()
    analyze(args.mesh.resolve(), args.torus.resolve(), args.output.resolve())
