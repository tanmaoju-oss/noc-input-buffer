#!/usr/bin/env python3
# Modify quantify hash and fallback effects without summing nonlinear causal shares, Michael Tan, 20261028
import argparse
import csv
from pathlib import Path


def load(directory,tag,mode):
    log=(directory/'xsim.log').read_text()
    if f'[{tag}] PASSED' not in log or 'Fatal:' in log:
        raise ValueError(f'Incomplete/failed run: {directory}')
    rows=list(csv.DictReader((directory/'latency_summary.csv').open()))
    if len(rows)!=6 or len({r['rate_ppm'] for r in rows})!=6:
        raise ValueError('Expected six distinct rates')
    for row in rows:
        if int(row['fallback_mode'])!=mode or row['offered_packets']!=row['completed_packets']:
            raise ValueError('Mode/conservation mismatch')
        if abs(float(row['mean_total'])-float(row['mean_queue'])-float(row['mean_network']))>1e-5:
            raise ValueError('Latency decomposition mismatch')
    return {int(r['rate_ppm']):r for r in rows}


def rtl_manifest(directory):
    result={}
    for line in (directory/'source_sha256.txt').read_text().splitlines():
        digest,name=line.split(maxsplit=1)
        if Path(name).parent.name=='src':result[Path(name).name]=digest
    if len(result)!=22:raise ValueError('Expected 22 RTL sources')
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('old-off','old-on','mixed-off','mixed-on','xy','output-dir'):
        p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args()
    paths={'old_off':args.old_off,'old_on':args.old_on,'mixed_off':args.mixed_off,'mixed_on':args.mixed_on}
    data={key:load(directory,'TB_OE_HASH_LATENCY' if key.startswith('mixed') else 'TB_OE_VA_FALLBACK_LATENCY',int(key.endswith('_on'))) for key,directory in paths.items()}
    xy_log=(args.xy/'xsim.log').read_text()
    if '[TB_CONGESTION_LATENCY_COMPARE] PASSED alg=0' not in xy_log:raise ValueError('XY reference failed')
    xy={int(r['rate_ppm']):r for r in csv.DictReader((args.xy/'latency_summary.csv').open())}
    manifests={key:rtl_manifest(directory) for key,directory in paths.items()}
    if manifests['old_off']!=manifests['old_on'] or manifests['mixed_off']!=manifests['mixed_on']:
        raise ValueError('Sources differ within a fallback pair')
    changed={name for name,digest in manifests['old_off'].items() if digest!=manifests['mixed_off'][name]}
    if changed!={'rc_unit_Xiugai2.sv'}:raise ValueError(f'Unexpected source changes: {changed}')
    for key in ('mixed_off','mixed_on'):
        config=(paths[key]/'run_config.txt').read_text()
        if 'OE_MIXED_HASH' not in config:raise ValueError('Mixed hash macro missing')
        if ('OE_VA_FALLBACK_DISABLED' in config)!=key.endswith('_off'):raise ValueError('Fallback macro mismatch')
    rows=[]
    for rate in sorted(xy):
        values={key:table[rate] for key,table in data.items()}
        for field in ('seed','warmup','measure','offered_packets','cohort_packets','actual_offered_ppc','trace_hash'):
            if len({value[field] for value in [xy[rate],*values.values()]})!=1:
                raise ValueError(f'Traffic mismatch at {rate}: {field}')
        y=float(xy[rate]['mean_total'])
        means={key:float(value['mean_total']) for key,value in values.items()}
        a,b,c,d=(means[key] for key in ('old_off','old_on','mixed_off','mixed_on'))
        row={'packet_rate':f'{rate/1000000:.3f}','xy_mean_total':y,**{f'{key}_mean_total':value for key,value in means.items()},
             'hash_only_reduction_percent':100*(a-c)/a,'combined_reduction_percent':100*(a-d)/a,
             'hash_only_gap_closed_percent':100*(a-c)/(a-y),'combined_gap_closed_percent':100*(a-d)/(a-y),
             'fallback_old_hash_benefit_cycles':a-b,'fallback_mixed_hash_benefit_cycles':c-d,
             'nonadditive_overlap_cycles':a-b-c+d,'cohort_packets':xy[rate]['cohort_packets'],'trace_hash':xy[rate]['trace_hash']}
        for field in ('mean_queue','mean_network','p95_total','p99_total','arrival_ppc','fallback_grants'):
            for key,value in values.items():row[f'{key}_{field}']=value[field]
        rows.append(row)
    args.output_dir.mkdir(parents=True,exist_ok=True)
    output=args.output_dir/'oe_hash_factorial_comparison.csv'
    with output.open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print('Validated matched traces, two fallback pairs and RC-only source intervention.')
    for row in rows:
        print(row['packet_rate'],row['xy_mean_total'],row['old_off_mean_total'],row['old_on_mean_total'],row['mixed_off_mean_total'],row['mixed_on_mean_total'],row['hash_only_gap_closed_percent'])
    print(f'Wrote {output}')


if __name__=='__main__':
    main()
