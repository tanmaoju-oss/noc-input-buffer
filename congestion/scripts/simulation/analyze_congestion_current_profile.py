#!/usr/bin/env python3
# Modify validate current-protocol observations and quantify resource-loss categories, Michael Tan, 20261029
import argparse
import csv
import hashlib
import statistics
from pathlib import Path

KINDS = ['va_no_available', 'va_arbitration', 'va_grant', 'sa_on_off', 'sa_arbitration', 'sa_transfer',
         'va_no_available_other_legal_available', 'va_no_available_other_legal_ready',
         'va_grant_closed', 'va_grant_closed_other_ready', 'sa_closed_other_vc_ready',
         'sa_closed_other_legal_ready', 'sa_output_idle_despite_ready_request',
         'va_output_idle_despite_available_request']


def rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def summarize(run, reference, name):
    log = (run / 'xsim.log').read_text()
    if 'PASSED' not in log or 'Fatal:' in log or 'Error:' in log:
        raise ValueError(f'Unclean result {run}')
    current = rows(run / 'latency_summary.csv')
    if len(current) != 1:
        raise ValueError('Expected one observed rate')
    current = current[0]
    baseline = next(r for r in rows(reference / 'latency_summary.csv') if r['rate_ppm'] == current['rate_ppm'])
    for key, value in baseline.items():
        if current[key] != value:
            raise ValueError(f'Observation changed {name} {key}: {current[key]} vs {value}')
    for line in (run / 'source_sha256.txt').read_text().splitlines():
        digest, filename = line.split(maxsplit=1)
        if hashlib.sha256(Path(filename).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Source changed since run: {filename}')
    waits = rows(run / 'current_waits.csv')
    if len(waits) != len(KINDS):
        raise ValueError('Missing diagnostic categories')
    totals = {KINDS[int(r['kind'])]: int(r['local_cycles']) + int(r['network_cycles']) for r in waits}
    links = rows(run / 'current_links.csv')
    if len(links) != 624:
        raise ValueError('Missing directed links')
    vc_rows = rows(run / 'current_vcs.csv')
    if sum(int(r['grants']) for r in vc_rows) != totals['va_grant']:
        raise ValueError('VC grant counters do not conserve')
    window = int(current['measure'])
    utilizations = [int(r['flits']) / window for r in links]
    result = {'algorithm': name, 'mean_total': current['mean_total'], **totals,
              'link_mean_utilization': statistics.mean(utilizations),
              'link_peak_utilization': max(utilizations),
              'link_utilization_cv': statistics.pstdev(utilizations) / statistics.mean(utilizations)}
    for r in vc_rows:
        result['vc' + r['vc'] + '_grants'] = int(r['grants'])
    print(name, result)
    return result


def main():
    parser = argparse.ArgumentParser()
    for key in ('xy', 'oe', 'xy-reference', 'oe-reference', 'output-dir'):
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    if (args.xy / 'source_sha256.txt').read_text() != (args.oe / 'source_sha256.txt').read_text():
        raise ValueError('Observed source sets differ')
    records = [summarize(args.xy, args.xy_reference, 'XY'), summarize(args.oe, args.oe_reference, 'OE')]
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / 'current_protocol_profile_20261029.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(records[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(records)
    print('Both cases reproduce all 22 baseline fields; all grant counts and source hashes checked.')


if __name__ == '__main__':
    main()
