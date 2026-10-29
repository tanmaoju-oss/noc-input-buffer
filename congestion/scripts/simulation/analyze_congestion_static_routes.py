#!/usr/bin/env python3
# Modify quantify fixed zero-metric routing bias without changing RTL, Michael Tan, 20261028
import argparse
import csv
from collections import Counter
from pathlib import Path


def route_load(algorithm, size):
    load = Counter()
    hops = 0
    for sx in range(size):
        for sy in range(size):
            for dx in range(size):
                for dy in range(size):
                    if (sx, sy) == (dx, dy):
                        continue
                    x, y = sx, sy
                    while (x, y) != (dx, dy):
                        before = abs(dx - x) + abs(dy - y)
                        xd, yd = ("E" if dx > x else "W"), ("S" if dy > y else "N")
                        if x == dx:
                            port = yd
                        elif y == dy:
                            port = xd
                        elif algorithm == "XY":
                            port = xd
                        elif dx > x:
                            allow_y = x % 2 == 1 or x == sx
                            allow_x = dx % 2 == 1 or dx - x != 1
                            assert allow_x or allow_y
                            port = yd if allow_y else xd  # all equal costs choose Y
                        else:
                            port = yd if x % 2 == 0 else xd
                        load[x, y, port] += 1
                        hops += 1
                        x += (port == "E") - (port == "W")
                        y += (port == "S") - (port == "N")
                        assert 0 <= x < size and 0 <= y < size
                        assert abs(dx - x) + abs(dy - y) == before - 1
    return load, hops


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("congestion/docs"))
    args = parser.parse_args()
    xy, xy_hops = route_load("XY", 13)
    two, two_hops = route_load("TwoAware_zero_metrics", 13)
    assert xy_hops == two_hops == 246064
    assert len(xy) == len(two) == 624
    assert max(xy.values()) == 546 and max(two.values()) == 1008
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output = args.output_dir / "static_zero_metric_link_load_20261028.csv"
    with output.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["x", "y", "output_direction", "xy_routes", "twoaware_zero_metric_routes"])
        for key in sorted(set(xy) | set(two)):
            writer.writerow([*key, xy[key], two[key]])
    for name, load in [("XY", xy), ("TwoAware_zero_metrics", two)]:
        peak = max(load.values())
        coefficient = 4 * peak / 168
        print(f"{name}: peak_routes={peak}, peak_flit_load={coefficient:g}*packet_rate, fixed_route_capacity_reference={1/coefficient:.6f}")
    print(f"Saved {output}; static frozen-metric model only, not dynamic RTL utilization.")


if __name__ == "__main__":
    main()
