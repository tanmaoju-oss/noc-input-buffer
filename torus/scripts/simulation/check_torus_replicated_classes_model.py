#!/usr/bin/env python3
# Modify analyze two replicated VCs per dateline phase without modifying RTL, Michael Tan, 20261104
"""Design-space model only: physical input port supplies dimension, VC0/1
are before-dateline and VC2/3 after-dateline in either dimension. All legal
replica transitions are included; this is not implemented RTL verification.
"""
import argparse
import json
from collections import defaultdict,deque
from pathlib import Path
from check_torus_channel_dependencies import route


def check(nx,ny):
    edges=defaultdict(set);paths=0
    for sx in range(nx):
      for sy in range(ny):
       for dx in range(nx):
        for dy in range(ny):
         previous={(sx,sy,'L',0)}
         x,y,dimension,after=sx,sy,None,False
         while (direction:=route(x,y,dx,dy,nx,ny))!='L':
            dim='X' if direction in 'EW' else 'Y'
            assert not (dimension=='Y' and dim=='X')
            if dim!=dimension:after=False
            after|=((direction=='E' and x==nx-1) or (direction=='W' and x==0) or
                    (direction=='S' and y==ny-1) or (direction=='N' and y==0))
            dimension=dim
            x=(x+(direction=='E')-(direction=='W'))%nx
            y=(y+(direction=='S')-(direction=='N'))%ny
            replicas=(2,3) if after else (0,1)
            current={(x,y,{'E':'W','W':'E','S':'N','N':'S'}[direction],v) for v in replicas}
            for a in previous:
                edges[a].update(current)
            for b in current:edges.setdefault(b,set())
            previous=current
         sink=(x,y,'SINK',0)
         for a in previous:edges[a].add(sink)
         edges.setdefault(sink,set());paths+=1
    indegree=dict.fromkeys(edges,0)
    for targets in edges.values():
        for v in targets:indegree[v]+=1
    queue=deque(v for v,d in indegree.items() if d==0);removed=0
    while queue:
        v=queue.popleft();removed+=1
        for w in edges[v]:
            indegree[w]-=1
            if indegree[w]==0:queue.append(w)
    assert removed==len(edges),(nx,ny,'cycle')
    return dict(nx=nx,ny=ny,paths=paths,resources=len(edges),edges=sum(map(len,edges.values())),acyclic=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args()
    results=[check(nx,ny) for nx in range(2,9) for ny in range(2,9)]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(results,indent=2)+'\n')
    print(f'MODEL PASS: {len(results)} sizes, {sum(r["paths"] for r in results)} paths; two replicas/phase; no RTL changed')
