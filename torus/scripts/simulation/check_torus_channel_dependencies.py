#!/usr/bin/env python3
# Modify enumerate deterministic Torus paths and physical input-VC dependencies, Michael Tan, 20261102
"""Check routing-resource DAG; assumes independent per-input-VC FIFOs,
exclusive downstream ownership until TAIL, no endpoint reinjection dependency,
no flit interleaving and no Y->X turn. Not a proof of arbitrary RTL behavior.
"""
import json
from collections import defaultdict, deque
from pathlib import Path


def route(x, y, dx, dy, nx, ny):
    if x != dx:
        return 'E' if (dx-x) % nx <= (x-dx) % nx else 'W'
    if y != dy:
        return 'S' if (dy-y) % ny <= (y-dy) % ny else 'N'
    return 'L'


def check(nx, ny):
    edges = defaultdict(set)
    paths = 0
    max_hops = 0
    for sx in range(nx):
        for sy in range(ny):
            for dx in range(nx):
                for dy in range(ny):
                    # LOCAL injection resources cannot be requested by transit traffic.
                    previous = (sx, sy, 'L', 0)
                    x, y, dimension, after, hops = sx, sy, None, False, 0
                    while (direction := route(x, y, dx, dy, nx, ny)) != 'L':
                        dim = 'X' if direction in 'EW' else 'Y'
                        assert not (dimension == 'Y' and dim == 'X')
                        if dim != dimension:
                            after = False
                        crossing = ((direction == 'E' and x == nx-1) or
                                    (direction == 'W' and x == 0) or
                                    (direction == 'S' and y == ny-1) or
                                    (direction == 'N' and y == 0))
                        after |= crossing
                        dimension = dim
                        vc = (0 if dim == 'X' else 2) + int(after)
                        x = (x + (direction == 'E') - (direction == 'W')) % nx
                        y = (y + (direction == 'S') - (direction == 'N')) % ny
                        current = (x, y, {'E':'W','W':'E','S':'N','N':'S'}[direction], vc)
                        edges[previous].add(current)
                        edges.setdefault(current, set())
                        previous = current
                        hops += 1
                        assert hops <= nx//2 + ny//2
                    # Endpoint ejection is a terminal resource, separate from injection.
                    edges[previous].add((x, y, 'SINK', 0))
                    edges.setdefault((x, y, 'SINK', 0), set())
                    assert hops == min(abs(dx-sx), nx-abs(dx-sx)) + min(abs(dy-sy), ny-abs(dy-sy))
                    paths += 1
                    max_hops = max(hops, max_hops)
    indegree = dict.fromkeys(edges, 0)
    for values in edges.values():
        for v in values:
            indegree[v] += 1
    queue = deque(v for v, d in indegree.items() if d == 0)
    removed = 0
    while queue:
        v = queue.popleft()
        removed += 1
        for w in edges[v]:
            indegree[w] -= 1
            if indegree[w] == 0:
                queue.append(w)
    assert removed == len(edges), f'cycle: {nx}x{ny}'
    return dict(nx=nx, ny=ny, paths=paths, resources=len(edges),
                edges=sum(map(len, edges.values())), max_hops=max_hops, acyclic=True)


if __name__ == '__main__':
    results = [check(nx, ny) for nx in range(2, 9) for ny in range(2, 9)]
    root = Path(__file__).resolve().parents[2]
    out = root / 'vivado_sim_wsl/torus_channel_dependencies'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'summary.json').write_text(json.dumps(results, indent=2)+'\n')
    print(f'PASS: {len(results)} sizes, {sum(r["paths"] for r in results)} paths; {out}/summary.json')
