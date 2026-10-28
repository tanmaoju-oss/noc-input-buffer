#!/usr/bin/env python3
# Modify validate OFF reproduction before attributing ON latency changes, Michael Tan, 20261028
import argparse
import csv
from pathlib import Path


def read(directory, tag, mode=None):
    log=(directory/'xsim.log').read_text()
    if f'[{tag}] PASSED' not in log or 'Fatal:' in log:
        raise ValueError(f'Failed or incomplete run: {directory}')
    rows=list(csv.DictReader((directory/'latency_summary.csv').open()))
    if len(rows)!=6 or len({r['rate_ppm'] for r in rows})!=6:
        raise ValueError('Expected six rates')
    for row in rows:
        if row['offered_packets']!=row['completed_packets']:
            raise ValueError('Packet conservation mismatch')
        if mode is not None and int(row['fallback_mode'])!=mode:
            raise ValueError('Fallback mode mismatch')
        if abs(float(row['mean_total'])-float(row['mean_queue'])-float(row['mean_network']))>1e-5:
            raise ValueError('Latency decomposition mismatch')
    return {int(r['rate_ppm']):r for r in rows}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('off-run','on-run','oe-reference','xy-reference','output-dir'):
        parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    off=read(args.off_run,'TB_OE_VA_FALLBACK_LATENCY',0)
    on=read(args.on_run,'TB_OE_VA_FALLBACK_LATENCY',1)
    oe=read(args.oe_reference,'TB_CONGESTION_OE_LATENCY_COMPARE')
    xy=read(args.xy_reference,'TB_CONGESTION_LATENCY_COMPARE')
    if (args.off_run/'source_sha256.txt').read_text()!=(args.on_run/'source_sha256.txt').read_text():
        raise ValueError('OFF and ON source fingerprints differ')
    if 'OE_VA_FALLBACK_DISABLED' not in (args.off_run/'run_config.txt').read_text():
        raise ValueError('OFF macro missing')
    if 'OE_VA_FALLBACK_DISABLED' in (args.on_run/'run_config.txt').read_text():
        raise ValueError('ON incorrectly disabled')
    rows=[]
    for rate in sorted(oe):
        b,o,n,x=oe[rate],off[rate],on[rate],xy[rate]
        for field in b:
            if o[field]!=b[field]:
                raise ValueError(f'OFF does not reproduce baseline at {rate}: {field}={o[field]} vs {b[field]}')
        if int(o['fallback_grants'])!=0:
            raise ValueError('OFF emitted fallback grants')
        for field in ('seed','warmup','measure','offered_packets','cohort_packets','actual_offered_ppc','trace_hash'):
            if len({b[field],n[field],x[field]})!=1:
                raise ValueError(f'Offered trace mismatch: {field}')
        if int(n['fallback_grants'])>int(n['fallback_possible_request_cycles']):
            raise ValueError('Fallback counter mismatch')
        gap=float(b['mean_total'])-float(x['mean_total'])
        row={'packet_rate':f'{rate/1000000:.3f}','xy_mean_total':x['mean_total'],'oe_off_mean_total':o['mean_total'],'oe_on_mean_total':n['mean_total'],
             'oe_latency_reduction_percent':f'{100*(float(o["mean_total"])-float(n["mean_total"]))/float(o["mean_total"]):.3f}',
             'oe_xy_gap_removed_percent':f'{100*(float(o["mean_total"])-float(n["mean_total"]))/gap:.3f}' if gap else '',
             'fallback_grants':n['fallback_grants'],'off_opportunity_request_cycles':o['fallback_possible_request_cycles'],'on_opportunity_request_cycles':n['fallback_possible_request_cycles'],
             'cohort_packets':b['cohort_packets'],'trace_hash':b['trace_hash']}
        for field in ('mean_queue','mean_network','p95_total','p99_total','arrival_ppc','source_backlog_stop'):
            for label,value in (('xy',x),('off',o),('on',n)):
                row[f'{label}_{field}']=value[field]
        rows.append(row)
    args.output_dir.mkdir(parents=True,exist_ok=True)
    output=args.output_dir/'oe_va_fallback_comparison.csv'
    with output.open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print('OFF exactly reproduces every original CSV field for all six rates.')
    print('Identical OFF/ON source files, only compile switch differs; all offered traces match.')
    for row in rows:
        print(row['packet_rate'],row['oe_off_mean_total'],row['oe_on_mean_total'],row['oe_xy_gap_removed_percent'],row['fallback_grants'])
    print(f'Wrote {output}')


if __name__=='__main__':
    main()
