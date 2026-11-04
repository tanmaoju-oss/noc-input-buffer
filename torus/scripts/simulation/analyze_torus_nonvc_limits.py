#!/usr/bin/env python3
# Modify audit scheduler opportunities, pipeline bounds and fluid topology limits without changing RTL, Michael Tan, 20261104
import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from statistics import mean


def read(path):
    with path.open() as stream:
        return [{k:int(v) for k,v in row.items()} for row in csv.DictReader(stream)]


def write(path,rows):
    with path.open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n",fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)


def route_hops(p,mode):
    hx=abs(p['sx']-p['dx']);hy=abs(p['sy']-p['dy'])
    return min(hx,5-hx)+min(hy,5-hy) if mode=='torus' else hx+hy


def main(args):
    output=args.output;output.mkdir(parents=True,exist_ok=True)
    scheduler=[];latency=[];traces=[]
    for mode,root,control in [('mesh',args.mesh,args.mesh_control),('torus',args.torus,args.torus_control)]:
        for line in (root/'source_sha256.txt').read_text().splitlines():
            digest,name=line.split(maxsplit=1)
            assert hashlib.sha256(Path(name.strip()).read_bytes()).hexdigest()==digest
        (output/f'{mode}_source_sha256.txt').write_bytes((root/'source_sha256.txt').read_bytes())
        for policy in (0,1):
            case=root/f'policy{policy}'
            log=(case/'xsim.log').read_text()
            assert '[TB_TORUS_SCHEDULER_PROFILE] PASSED' in log
            assert not any(s in log for s in ('Fatal:','Error:','ERROR:','FATAL:'))
            for name in ('trace.csv','packets.csv','summary.csv','stalls.csv','vc_profile.csv','port_profile.csv'):
                assert (case/name).read_bytes()==(control/f'policy{policy}'/name).read_bytes(),(mode,policy,name)
            traces.append((case/'trace.csv').read_bytes())
            rows=read(case/'scheduler.csv')
            assert len(rows)==25 and all(r['cycles']==3000 for r in rows)
            totals={k:sum(r[k] for r in rows) for k in rows[0] if k not in ('x','y')}
            vc=read(case/'vc_profile.csv')
            assert totals['sa_actual']==sum(r['sa_grant'] for r in vc)
            assert totals['va_actual']==sum(r['va_grant'] for r in vc)
            assert totals['sa_actual']<=totals['sa_best'] and totals['va_actual']<=totals['va_best']
            scheduler.append(dict(mode=mode,policy=policy,**totals,
                sa_actual_over_best=totals['sa_actual']/totals['sa_best'],
                va_actual_over_best=totals['va_actual']/totals['va_best'],
                run=str(case.resolve())))
    assert len(set(traces))==1
    for mode,root in [('mesh',args.original_mesh),('torus',args.original_torus)]:
        for rate in (100,400,800,1200):
            for seed in (1,42):
                case=root/f'rate{rate}_seed{seed}_traffic0'
                packets=read(case/'packets.csv');trace=read(case/'trace.csv')
                selected=[(p,t) for p,t in zip(packets,trace) if p['birth']>1000]
                assert all(p['id']==t['id'] and p['birth']==t['birth'] for p,t in selected)
                floor=[4+2*(route_hops(t,mode)+1) for p,t in selected]
                net=[p['tail_out']-p['head_in']+1 for p,t in selected]
                assert all(actual>=bound for actual,bound in zip(net,floor))
                latency.append(dict(mode=mode,rate=rate/10000,seed=seed,sample=len(selected),
                    mean_hops=mean(route_hops(t,mode) for p,t in selected),
                    rtl_uncontended_floor=mean(floor),network_latency=mean(net),
                    network_excess_over_floor=mean(a-b for a,b in zip(net,floor)),
                    source_queue=mean(p['head_in']-p['birth'] for p,t in selected),
                    total_latency=mean(p['tail_out']-p['birth']+1 for p,t in selected)))
    bounds={}
    for mode in ('mesh','torus'):
        loads=Counter()
        for sx in range(5):
         for sy in range(5):
          for dx in range(5):
           for dy in range(5):
            x,y=sx,sy
            while (x,y)!=(dx,dy):
                if x!=dx:
                    direction=('E' if dx>x else 'W') if mode=='mesh' else ('E' if (dx-x)%5<=(x-dx)%5 else 'W')
                else:
                    direction=('S' if dy>y else 'N') if mode=='mesh' else ('S' if (dy-y)%5<=(y-dy)%5 else 'N')
                loads[x,y,direction]+=1
                x=(x+(direction=='E')-(direction=='W'))%5
                y=(y+(direction=='S')-(direction=='N'))%5
        # Each source sends f flits/cycle, uniformly split over 24 nonself destinations.
        coefficient=max(loads.values())/24
        bounds[mode]=dict(max_link_load_per_unit_source_flit_rate=coefficient,
            physical_link_only_bound=1/coefficient,endpoint_bound=1,
            ideal_fluid_bound_flits_per_node_cycle=min(1,1/coefficient),
            model='uniform nonself mean flow; fixed routes; perfect service; ignores VC, scheduling, bursts and finite buffers')
    write(output/'scheduler_summary.csv',scheduler);write(output/'latency_floor.csv',latency)
    (output/'ideal_fluid_bounds.json').write_text(json.dumps(bounds,indent=2)+'\n')
    (output/'audit.txt').write_text('PASS: four simulator runs; six original data files exactly reproduced per case; all four traces equal; per-router 3000-cycle coverage; VA/SA counts match previous observers; current source hashes verified; all 16 uniform cases satisfy derived RTL uncontended per-packet latency floor.\n')
    for row in scheduler:print(row)
    print(bounds)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ('mesh','torus','mesh_control','torus_control','original_mesh','original_torus','output'):
        parser.add_argument(name,type=Path)
    main(parser.parse_args())
