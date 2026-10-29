#!/usr/bin/env python3
# Modify validate nonintrusive controls and summarize occupancy/source waits, Michael Tan, 20261029
import argparse
import csv
from pathlib import Path


def rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def main():
    parser = argparse.ArgumentParser()
    for key in ('xy-profile', 'oe-profile', 'xy-reference', 'oe-reference', 'output-dir'):
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    output = []
    if (args.xy_profile / 'source_sha256.txt').read_text() != (args.oe_profile / 'source_sha256.txt').read_text():
        raise ValueError('Observed sources differ')
    for name, run, reference in [('XY', args.xy_profile, args.xy_reference), ('OE', args.oe_profile, args.oe_reference)]:
        log = (run / 'xsim.log').read_text()
        if '[TB_OE_OCCUPANCY_PROFILE] PASSED' not in log or 'Fatal:' in log:
            raise ValueError('Missing clean simulation PASS')
        observed = rows(run / 'latency_summary.csv')
        if len(observed) != 1:
            raise ValueError('Expected exactly one rate')
        current = observed[0]
        original = next(r for r in rows(reference / 'latency_summary.csv') if r['rate_ppm'] == current['rate_ppm'])
        for key, value in original.items():
            if current[key] != value:
                raise ValueError(f'{name} control mismatch: {key}')
        occupancy = rows(run / 'occupancy_profile.csv')
        if len(occupancy) != 72:
            raise ValueError('Missing occupancy bins')
        stage = rows(run / 'wait_profile.csv')
        for group in (0, 1):
            counts = {(int(r['state']), int(r['flits'])): int(r['vc_cycles']) for r in occupancy if int(r['input_group']) == group}
            total = sum(counts.values())
            expected = 13 * 13 * 4 * (1 if group == 0 else 4) * int(current['measure'])
            if total != expected:
                raise ValueError('Occupancy sample conservation failed')
            result = {'algorithm': name, 'input_group': group, 'sample_vc_cycles': total,
                      'mean_flits': sum(f * value for (s, f), value in counts.items()) / total,
                      'idle_cycles': sum(value for (s, f), value in counts.items() if s == 0),
                      'await_va_cycles': sum(value for (s, f), value in counts.items() if s == 1),
                      'await_va_mean_flits': sum(f * value for (s, f), value in counts.items() if s == 1) / max(1, sum(value for (s, f), value in counts.items() if s == 1)),
                      'allocated_empty_cycles': sum(value for (s, f), value in counts.items() if s == 2),
                      'allocated_nonempty_cycles': sum(value for (s, f), value in counts.items() if s == 3),
                      'full_cycles': sum(value for (s, f), value in counts.items() if f == 8)}
            # Modify cross-check independent state observations against request categories, Michael Tan, 20261029
            field = 'local_input_vc_cycles' if group == 0 else 'network_input_vc_cycles'
            va_requests = sum(int(r[field]) for r in stage if int(r['kind']) in (0, 1, 2, 5))
            sa_requests = sum(int(r[field]) for r in stage if int(r['kind']) in (3, 4, 6))
            if result['await_va_cycles'] != va_requests or result['allocated_nonempty_cycles'] != sa_requests:
                raise ValueError('State and request observations disagree')
            output.append(result)
            print(result)
        print(name, 'source waits', rows(run / 'source_profile.csv'))
        print(name, 'control fields matched', len(original))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / 'oe_xy_occupancy_006_20261029.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(output[0]))
        writer.writeheader()
        writer.writerows(output)


if __name__ == '__main__':
    main()
