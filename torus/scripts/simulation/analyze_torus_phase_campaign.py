#!/usr/bin/env python3
# Modify audit immutable controls, identical traffic and replicated-VC performance/resource tradeoffs, Michael Tan, 20261104
import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path
from statistics import mean


def read(path):
    with path.open() as stream:
        return [{k:int(v) for k,v in row.items()} for row in csv.DictReader(stream)]


def save(path,rows):
    with path.open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n",fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)


def audit_sources(root):
    for line in (root/'source_sha256.txt').read_text().splitlines():
        digest,name=line.split(maxsplit=1)
        assert hashlib.sha256(Path(name.strip()).read_bytes()).hexdigest()==digest,name


def case_pass(path,marker):
    text=path.read_text()
    assert marker in text,path
    assert not any(x in text for x in ('Fatal:','Error:','ERROR:','FATAL:')),path
    return text


def main(args):
    manifest=json.loads(args.manifest.read_text());out=args.output;out.mkdir(parents=True,exist_ok=True)
    modes=('mesh','legacy','4','8','16');expected={(r,s,0) for r in (100,400,800,1200) for s in (1,42)}|{(400,1,1),(800,1,1)}
    metrics=[];resources=[]
    for mode in modes:
        root=Path(manifest['performance'][mode]);audit_sources(root)
        (out/f'performance_{mode}_source_sha256.txt').write_bytes((root/'source_sha256.txt').read_bytes())
        (out/f'performance_{mode}_configuration.txt').write_bytes((root/'configuration.txt').read_bytes())
        actual={tuple(int(row[k]) for k in ('rate','seed','traffic')) for p in root.glob('rate*/summary.csv') for row in read(p)}
        assert actual==expected,(mode,actual)
        if mode=='legacy':assert (root/'legacy_commit.txt').read_text().strip().startswith('3c31c2b')
    for rate,seed,traffic in sorted(expected):
        case=f'rate{rate}_seed{seed}_traffic{traffic}';traces=[]
        for mode in modes:
            root=Path(manifest['performance'][mode]);directory=root/case
            case_pass(directory/'xsim.log','[TB_TORUS_PHASE_PERFORMANCE] PASSED')
            traces.append((directory/'trace.csv').read_bytes())
            trace=read(directory/'trace.csv');packets=read(directory/'packets.csv');summary=read(directory/'summary.csv')[0]
            assert len(trace)==len(packets)==summary['generated']==summary['completed']
            assert summary['flits']==len(packets)*4
            hops=0
            for index,(t,p) in enumerate(zip(trace,packets)):
                assert t['id']==p['id']==index and t['birth']==p['birth']<=p['head_in']<=p['tail_out']
                hx=abs(t['sx']-t['dx']);hy=abs(t['sy']-t['dy'])
                hops+=(hx+hy) if mode=='mesh' else (min(hx,5-hx)+min(hy,5-hy))
            assert summary['link_flits']==4*hops
            if mode in ('mesh','legacy'):
                old=Path(manifest['original_mesh' if mode=='mesh' else 'original_torus'])/case
                for name in ('trace.csv','packets.csv','summary.csv'):
                    assert (directory/name).read_bytes()==(old/name).read_bytes(),(mode,case,name)
            sample=[p for p in packets if 1000<p['birth']<=4000]
            lat=sorted(p['tail_out']-p['birth']+1 for p in sample)
            q=mean(p['head_in']-p['birth'] for p in sample);net=mean(p['tail_out']-p['head_in']+1 for p in sample)
            assert abs(mean(lat)-q-net)<1e-9
            metrics.append(dict(mode=mode,rate=rate/10000,seed=seed,traffic=traffic,
                generated=len(packets),sample=len(sample),mean_latency=mean(lat),source_queue=q,network_latency=net,
                p95=lat[math.ceil(len(lat)*.95)-1],p99=lat[math.ceil(len(lat)*.99)-1],
                window_in=summary['window_in']/75000,window_out=summary['window_out']/75000,
                drain=summary['last_cycle']-4000,mean_hops=hops/len(trace),
                trace_sha256=hashlib.sha256(traces[-1]).hexdigest(),run=str(directory.resolve())))
        assert len(set(traces))==1,case
    functional=[];micro=[]
    for root_name in manifest['functional']:
        root=Path(root_name);audit_sources(root)
        config=(root/'configuration.txt').read_text();top=re.search(r'top=(\S+)',config)[1];mode=re.search(r'mode=(\S+)',config)[1]
        for case in sorted(p for p in root.iterdir() if p.is_dir() and (p/'xsim.log').exists()):
            log=case_pass(case/'xsim.log',f'[{top.upper()}] PASSED')
            functional.append(dict(top=top,mode=mode,case=case.name,pass_line=next(x for x in log.splitlines() if f'[{top.upper()}] PASSED' in x),run=str(case.resolve())))
            if top=='tb_torus_phase_singlehop':
                length=int(case.name.removeprefix('length'))
                with (case/'events.csv').open() as stream:events=list(csv.DictReader(stream))
                head=[e for e in events if e['kind']=='L' and int(e['beat'])==0]
                assert len(head)==256
                intervals=[int(b['cycle'])-int(a['cycle']) for a,b in zip(head,head[1:])]
                expected_interval=length+4 if mode=='legacy' else length
                assert all(i==expected_interval for i in intervals),(mode,length,set(intervals))
                micro.append(dict(mode=mode,length=length,packets=256,head_interval=mean(intervals),throughput=length/mean(intervals),gap=mean(intervals)-length,run=str(case.resolve())))
    counts={name:sum(r['top']==name for r in functional) for name in ('tb_torus_phase_rc','tb_torus_phase_vc_allocator','tb_torus_phase_integration','tb_torus_phase_congestion','tb_torus_phase_singlehop')}
    assert list(counts.values())==[3,3,6,3,10],counts
    for mode in modes:
        vcs=4 if mode in ('mesh','legacy') else int(mode)
        phase=4 if mode=='mesh' else (1 if mode=='legacy' else vcs//2)
        resources.append(dict(mode=mode,physical_vcs_per_input=vcs,eligible_vcs_per_network_hop=phase,
            endpoint_vcs=4,fifo_depth=8,flit_fifo_slots_per_input=vcs*8,flit_width_bits=24+int(math.log2(vcs))))
    save(out/'comparison.csv',metrics);save(out/'functional.csv',functional);save(out/'singlehop.csv',micro);save(out/'resources.csv',resources)
    lines=['| 流量 | 种子 | 包注入率 | Mesh4 | 旧Torus4 | 新Torus4 | 新Torus8 | 新Torus16 |',
           '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for rate,seed,traffic in sorted(expected):
        row=[next(r for r in metrics if r['mode']==mode and r['rate']==rate/10000 and r['seed']==seed and r['traffic']==traffic) for mode in modes]
        lines.append(f"| {'均匀' if traffic==0 else '环绕对角'} | {seed} | {rate/10000:.2f} | "+' | '.join(f"{r['mean_latency']:.3f}" for r in row)+' |')
    (out/'table.md').write_text('\n'.join(lines)+'\n')
    (out/'audit.txt').write_text(f'PASS: 50 performance cases; all 10 traffic traces identical across 5 modes; original Mesh and legacy exact trace/summary/packet timestamp reproduction; packet/timestamp/hop conservation; {len(functional)} functional case PASS logs including 10 single-hop cases and all 255 intervals each; current compiled-source hashes verified.\n')
    print('\n'.join(lines));print((out/'audit.txt').read_text())


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('manifest',type=Path);parser.add_argument('output',type=Path)
    main(parser.parse_args())
