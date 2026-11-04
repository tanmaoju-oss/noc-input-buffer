#!/usr/bin/env python3
# Modify audit exact baseline controls and paired source admission counterfactuals, Michael Tan, 20261104
import argparse
import csv
import hashlib
from collections import Counter
from pathlib import Path
from statistics import mean


def read(path):
    with path.open() as stream:
        return [{k: int(v) for k, v in row.items()} for row in csv.DictReader(stream)]


def main(args):
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    results=[];traces=[]
    for mode, root, original in [('mesh',args.mesh,args.original_mesh),
                                 ('sharedmesh',args.sharedmesh,args.original_mesh),
                                 ('torus',args.torus,args.original_torus)]:
        for line in (root/'source_sha256.txt').read_text().splitlines():
            digest,name=line.split(maxsplit=1)
            assert hashlib.sha256(Path(name.strip()).read_bytes()).hexdigest()==digest
        (output/f'{mode}_source_sha256.txt').write_bytes((root/'source_sha256.txt').read_bytes())
        for policy in (0,1):
            case=root/f'policy{policy}'
            log=(case/'xsim.log').read_text()
            assert '[TB_TORUS_CONDITIONS_CONTROL] PASSED' in log
            assert not any(s in log for s in ('Fatal:','Error:','ERROR:','FATAL:'))
            traces.append((case/'trace.csv').read_bytes())
            if policy==0:
                for name in ('trace.csv','packets.csv','summary.csv'):
                    assert (case/name).read_bytes()==(original/name).read_bytes(),(mode,name)
            packets=read(case/'packets.csv');trace=read(case/'trace.csv');summary=read(case/'summary.csv')[0]
            assert len(packets)==len(trace)==summary['generated']==summary['completed']==11889
            assert summary['flits']==4*len(packets)
            for index,(p,t) in enumerate(zip(packets,trace)):
                assert p['id']==t['id']==index
                assert p['birth']==t['birth']<=p['head_in']<=p['tail_out']
            sample=[p for p in packets if 1000<p['birth']<=4000]
            results.append(dict(mode=mode,generated=len(packets),sample=len(sample),
                                mean_latency=mean(p['tail_out']-p['birth']+1 for p in sample),
                                source_queue=mean(p['head_in']-p['birth'] for p in sample),
                                network_latency=mean(p['tail_out']-p['head_in']+1 for p in sample),
                                window_out=summary['window_out']/75000,
                                drain=summary['last_cycle']-4000,
                                **read(case/'stalls.csv')[0],run=str(case.resolve())))
    assert len(set(traces))==1
    for policy in (0,1):
        for name in ('trace.csv','packets.csv','summary.csv','stalls.csv'):
            assert (args.mesh/f'policy{policy}'/name).read_bytes()==(args.sharedmesh/f'policy{policy}'/name).read_bytes()
    with (output/'controls.csv').open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n",fieldnames=results[0].keys());writer.writeheader();writer.writerows(results)
    demands=[]
    for topology in ('mesh','torus'):
        demand=Counter()
        for p in read(args.mesh/'policy0/trace.csv'):
            x,y,dx,dy=[p[k] for k in ('sx','sy','dx','dy')]
            for axis in (0,1):
                while (x if axis==0 else y)!=(dx if axis==0 else dy):
                    cur=x if axis==0 else y;dst=dx if axis==0 else dy
                    step=(1 if dst>cur else -1) if topology=='mesh' else (1 if (dst-cur)%5<=(cur-dst)%5 else -1)
                    direction=('E' if step==1 else 'W') if axis==0 else ('S' if step==1 else 'N')
                    demand[x,y,direction]+=4
                    if axis==0:x=(x+step)%5
                    else:y=(y+step)%5
        key,count=demand.most_common(1)[0]
        demands.append(dict(topology=topology,max_flits_per_generation_cycle=count/4000,
                            link=str(key),links_over_one=sum(n>4000 for n in demand.values())))
    with (output/'route_demand.csv').open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n",fieldnames=demands[0].keys());writer.writeheader();writer.writerows(demands)
    (output/'audit.txt').write_text('PASS: six simulator runs; identical six traces; three fixed policies exactly reproduce original trace/summary/packet timestamps; both shared-Mesh policies exactly match original Mesh; counts/timestamps/current source hashes verified.\n')
    for row in results:print(row)
    print(demands)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ('mesh','sharedmesh','torus','original_mesh','original_torus','output'):
        parser.add_argument(name,type=Path)
    main(parser.parse_args())
