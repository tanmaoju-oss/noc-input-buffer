#!/usr/bin/env python3
# Modify distinguish VC-request pressure from SA waits and physical link load, Michael Tan, 20261028
import argparse
import csv
import statistics
from pathlib import Path

KINDS=['va_no_vc_alt_free','va_no_vc_no_alt','va_arbitration','sa_on_off','sa_arbitration','va_granted','sa_read']


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('xy-profile','oe-profile','xy-reference','oe-reference','output-dir'):
        p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args();output=[]
    if (args.xy_profile/'source_sha256.txt').read_text()!=(args.oe_profile/'source_sha256.txt').read_text():
        raise ValueError('Profile sources differ')
    for name,profile,reference in [('XY',args.xy_profile,args.xy_reference),('OE',args.oe_profile,args.oe_reference)]:
        log=(profile/'xsim.log').read_text()
        if '[TB_OE_STAGE_PROFILE] PASSED' not in log or 'Fatal:' in log:raise ValueError('Profile failed')
        records=list(csv.DictReader((profile/'latency_summary.csv').open()))
        if len(records)!=1:raise ValueError('Expected one observed rate')
        row=records[0];baseline=next(r for r in csv.DictReader((reference/'latency_summary.csv').open()) if r['rate_ppm']==row['rate_ppm'])
        for key in baseline:
            if row[key]!=baseline[key]:raise ValueError(f'Observation perturbed {name}: {key}')
        stage=list(csv.DictReader((profile/'wait_profile.csv').open()))
        if len(stage)!=7:raise ValueError('Missing stage categories')
        totals={KINDS[int(r['kind'])]:int(r['local_input_vc_cycles'])+int(r['network_input_vc_cycles']) for r in stage}
        links=list(csv.DictReader((profile/'link_profile.csv').open()))
        if len(links)!=624:raise ValueError('Missing directed links')
        utils=[int(r['flits'])/int(r['window_cycles']) for r in links]
        va_wait=sum(totals[k] for k in KINDS[:3]);no_vc=totals[KINDS[0]]+totals[KINDS[1]]
        columns=[sum(int(r['flits']) for r in links if int(r['x'])==x and int(r['port']) in (1,2)) for x in range(13)]
        result={'algorithm':name,'rate_ppm':row['rate_ppm'],'mean_total':row['mean_total'],**totals,
                'va_no_vc_share_of_va_wait_percent':100*no_vc/va_wait,
                'va_wait_cycles_per_window_grant':va_wait/totals['va_granted'],
                'sa_wait_cycles_per_window_read':(totals['sa_on_off']+totals['sa_arbitration'])/totals['sa_read'],
                'link_mean_utilization':statistics.mean(utils),'link_max_utilization':max(utils),
                'link_utilization_cv':statistics.pstdev(utils)/statistics.mean(utils),
                'vertical_column_min_flits':min(columns),'vertical_column_max_flits':max(columns)}
        output.append(result);print(name,result);print('vertical columns',columns)
    args.output_dir.mkdir(parents=True,exist_ok=True)
    target=args.output_dir/'oe_xy_stage_profile_006.csv'
    with target.open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(output[0]));writer.writeheader();writer.writerows(output)
    print('Both observed cases exactly reproduce all original CSV fields; saved',target)


if __name__=='__main__':
    main()
