#!/usr/bin/env python3
# Modify enumerate actual reachable physical-input VC resources across all 5x5 routes, Michael Tan, 20261104
import argparse
import csv
import json
from pathlib import Path
from collections import Counter,defaultdict
from check_torus_channel_dependencies import route


def main(output):
    result={};details=[]
    for mode in ('mesh','torus'):
        resources=defaultdict(set);hops=[]
        for sx in range(5):
         for sy in range(5):
          for dx in range(5):
           for dy in range(5):
            x,y=sx,sy;dimension=None;after=False;count=0
            while (x,y)!=(dx,dy):
                if mode=='mesh':
                    direction=('E' if dx>x else 'W') if x!=dx else ('S' if dy>y else 'N')
                    classes=range(4)
                else:
                    direction=route(x,y,dx,dy,5,5)
                    dim='X' if direction in 'EW' else 'Y'
                    if dim!=dimension:after=False
                    dimension=dim
                    after|=((direction=='E' and x==4) or (direction=='W' and x==0) or
                            (direction=='S' and y==4) or (direction=='N' and y==0))
                    classes=[(0 if dim=='X' else 2)+int(after)]
                resources[x,y,direction].update(classes)
                x=(x+(direction=='E')-(direction=='W'))%5
                y=(y+(direction=='S')-(direction=='N'))%5;count+=1
            if (sx,sy)!=(dx,dy):hops.append(count)
        active=len(resources);reachable=sum(map(len,resources.values()))
        result[mode]=dict(nonself_paths=len(hops),mean_hops=sum(hops)/len(hops),diameter=max(hops),
            directed_links=active,installed_network_vcs=active*4,reachable_network_vcs=reachable,
            reachable_fraction=reachable/(active*4),vcs_per_link_histogram=dict(Counter(map(len,resources.values()))),
            reachable_fifo_slots=reachable*8)
        for (x,y,p),vcs in sorted(resources.items()):
            details.append(dict(mode=mode,x=x,y=y,direction=p,classes='/'.join(map(str,sorted(vcs))),count=len(vcs)))
    output.mkdir(parents=True,exist_ok=True)
    (output/'reachable_resources.json').write_text(json.dumps(result,indent=2)+'\n')
    with (output/'reachable_resources.csv').open('w') as stream:
        writer=csv.DictWriter(stream,lineterminator="\n",fieldnames=details[0].keys());writer.writeheader();writer.writerows(details)
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path)
    main(parser.parse_args().output)
