#!/usr/bin/env python3
# Modify audit nonintrusive profiles, VC lifetimes and no-contention single-hop service, Michael Tan, 20261104
import argparse
import csv
import hashlib
from collections import Counter
from pathlib import Path
from statistics import mean


def read(path):
    with path.open() as stream:
        return [{k:(v if k=='kind' else int(v)) for k,v in row.items()} for row in csv.DictReader(stream)]


def save(path,rows):
    with path.open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n",fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)


def fingerprints(root,output,label):
    for line in (root/'source_sha256.txt').read_text().splitlines():
        digest,name=line.split(maxsplit=1)
        assert hashlib.sha256(Path(name.strip()).read_bytes()).hexdigest()==digest,name
    (output/f'{label}_source_sha256.txt').write_bytes((root/'source_sha256.txt').read_bytes())


def passed(case,marker):
    text=(case/'xsim.log').read_text()
    assert marker in text
    assert not any(s in text for s in ('Fatal:','Error:','ERROR:','FATAL:'))


def main(args):
    output=args.output;output.mkdir(parents=True,exist_ok=True)
    stage_rows=[];port_rows=[];lifetime_rows=[];micro_rows=[];backlog_rows=[]
    for mode,root,control in [('mesh',args.mesh,args.mesh_control),('torus',args.torus,args.torus_control)]:
        fingerprints(root,output,f'profile_{mode}')
        for policy in (0,1):
            case=root/f'policy{policy}';passed(case,'[TB_TORUS_BOTTLENECK_PROFILE] PASSED')
            for name in ('trace.csv','packets.csv','summary.csv','stalls.csv'):
                assert (case/name).read_bytes()==(control/f'policy{policy}'/name).read_bytes(),(mode,policy,name)
            packets=read(case/'packets.csv')
            for cycle in (1000,2000,3000,4000):
                born=sum(p['birth']<=cycle for p in packets)
                waiting=sum(p['birth']<=cycle<p['head_in'] for p in packets)
                active=sum(p['head_in']<=cycle<p['tail_out'] for p in packets)
                done=sum(p['tail_out']<=cycle for p in packets)
                assert born==waiting+active+done
                backlog_rows.append(dict(mode=mode,policy=policy,cycle=cycle,born=born,
                                         waiting_head=waiting,head_admitted_not_completed=active,completed=done))
            rows=read(case/'vc_profile.csv');ports=read(case/'port_profile.csv')
            for r in rows:
                assert r['va_requests']==r['va_no_eligible']+r['va_arb']+r['va_grant']
                assert r['sa_requests']==r['sa_onoff']+r['sa_arb']+r['sa_grant']
                assert r['sa_grant']==r['reads']
            assert sum(r['reads'] for r in rows)==sum(p['transfers'] for p in ports)
            for scope in ('all','network_inputs'):
                selected=[r for r in rows if scope=='all' or r['port']!=0]
                stats={k:sum(r[k] for r in selected) for k in selected[0] if k not in ('x','y','port','vc')}
                stage_rows.append(dict(mode=mode,policy=policy,scope=scope,**stats))
            # Mesh has 80 actual directed physical links; omit absent boundary ports.
            ports=[p for p in ports if p['port']!=0 and not(mode=='mesh' and (
                (p['port']==1 and p['y']==0) or (p['port']==2 and p['y']==4) or
                (p['port']==3 and p['x']==0) or (p['port']==4 and p['x']==4)))]
            assert len(ports)==(80 if mode=='mesh' else 100)
            assert all(p['window_cycles']==3000 for p in ports)
            port_rows.append(dict(mode=mode,policy=policy,physical_links=len(ports),
                utilization=sum(p['transfers'] for p in ports)/(len(ports)*3000),
                idle_pending=sum(p['idle_pending_va'] for p in ports),
                idle_blocked=sum(p['idle_blocked_va'] for p in ports),
                mean_reserved=sum(p['reserved_sum'] for p in ports)/(len(ports)*3000)))
            events=[e for e in read(case/'events.csv') if e['port']!=0]
            live={};timings=[]
            for e in sorted(events,key=lambda e:e['cycle']):
                key=tuple(e[k] for k in ('x','y','port','vc'))
                if e['kind']=='A':
                    assert key not in live
                    live[key]={'A':e['cycle'],'id':e['id']}
                elif e['kind'] in ('H','T'):
                    assert key in live and live[key]['id']==e['id']
                    live[key][e['kind']]=e['cycle']
                else:
                    assert e['kind']=='R'
                    a=live.pop(key);assert set(a)=={'A','H','T','id'}
                    assert a['A']<a['H']<=a['T']<e['cycle']
                    if 1000<a['A']<=4000:timings.append({**a,'R':e['cycle']})
            assert not live
            lifetime_rows.append(dict(mode=mode,policy=policy,samples=len(timings),
                mean_reservation=mean(t['R']-t['A'] for t in timings),
                min_reservation=min(t['R']-t['A'] for t in timings),
                mean_grant_to_head=mean(t['H']-t['A'] for t in timings),
                mean_tail_to_release=mean(t['R']-t['T'] for t in timings)))
    for mode,root in [('mesh',args.mesh_micro),('torus',args.torus_micro)]:
        fingerprints(root,output,f'singlehop_{mode}')
        for length in (4,16):
            case=root/f'length{length}';passed(case,'[TB_TORUS_SINGLEHOP_SERVICE] PASSED')
            events=read(case/'events.csv')
            link=[e for e in events if e['kind']=='L'];sink=[e for e in events if e['kind']=='S']
            headers=[e for e in link if e['beat']==0]
            assert len(headers)==256 and len(link)==len(sink)==256*length
            assert len({e['packet'] for e in headers})==256
            for kind in ('L','S'):
                grouped={i:[] for i in range(256)}
                for e in events:
                    if e['kind']==kind:grouped[e['packet']].append(e['beat'])
                assert all(beats==list(range(length)) for beats in grouped.values())
            intervals=[b['cycle']-a['cycle'] for a,b in zip(headers,headers[1:])]
            expected=length if mode=='mesh' else length+4
            assert Counter(intervals)=={expected:255},(mode,length,Counter(intervals))
            micro_rows.append(dict(mode=mode,length=length,packets=256,flits=256*length,
                head_interval=mean(intervals),packet_gap=mean(intervals)-length,
                periodic_flits_per_cycle=length/mean(intervals),
                downstream_vcs='/'.join(map(str,sorted({e['vc'] for e in headers}))),
                run=str(case.resolve())))
            # Preserve a short cycle trace for review without requiring ignored run data.
            first=[e for e in events if e['cycle']<=24]
            save(output/f'singlehop_{mode}_length{length}_first24.csv',sorted(first,key=lambda e:e['cycle']))
    save(output/'backlog_summary.csv',backlog_rows)
    save(output/'stage_summary.csv',stage_rows);save(output/'port_summary.csv',port_rows)
    save(output/'reservation_summary.csv',lifetime_rows);save(output/'singlehop_summary.csv',micro_rows)
    (output/'audit.txt').write_text('PASS: 4 nonintrusive profiles exactly match trace/packets/summary/stalls controls; per-VC VA/SA partitions and per-port transfer counts conserved; all network grants/headers/tails/releases paired; 4 single-hop runs pass with all 255 packet intervals checked; current source SHA256 verified.\n')
    for row in stage_rows+port_rows+lifetime_rows+micro_rows:print(row)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ('mesh','torus','mesh_control','torus_control','mesh_micro','torus_micro','output'):
        parser.add_argument(name,type=Path)
    main(parser.parse_args())
