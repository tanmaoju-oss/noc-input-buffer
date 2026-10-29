#!/usr/bin/env python3
# Modify cross-check actual OE route counts and quantify lost path diversity, Michael Tan, 20261028
import argparse
import csv
from collections import Counter
from functools import lru_cache
from pathlib import Path


def path(sx, sy, dx, dy, parity, xy=False):
    x, y = sx, sy
    result = []
    while (x, y) != (dx, dy):
        xd, yd = ("E" if dx > x else "W"), ("S" if dy > y else "N")
        if x == dx:
            port = yd
        elif y == dy:
            port = xd
        elif xy:
            port = xd
        else:
            if dx > x:
                allow_y, allow_x = (x % 2 == 1 or x == sx), (dx % 2 == 1 or dx - x != 1)
            else:
                allow_x, allow_y = True, x % 2 == 0
            bit = parity ^ ((x ^ y ^ dx ^ dy ^ sx ^ sy) & 1)
            port = xd if not allow_y or (allow_x and bit) else yd
        result.append((x, y, port))
        x += (port == "E") - (port == "W")
        y += (port == "S") - (port == "N")
    return tuple(result)


def legal_path_count(sx, sy, dx, dy):
    @lru_cache(None)
    def visit(x, y, previous):
        if (x, y) == (dx, dy):
            return 1
        total = 0
        choices = []
        if x != dx:
            choices.append(("E", x + 1, y) if dx > x else ("W", x - 1, y))
        if y != dy:
            choices.append(("S", x, y + 1) if dy > y else ("N", x, y - 1))
        for port, nx, ny in choices:
            if previous == "E" and x % 2 == 0 and port in ("N", "S"):
                continue
            if previous in ("N", "S") and x % 2 == 1 and port == "W":
                continue
            total += visit(nx, ny, port)
        return total
    return visit(sx, sy, "LOCAL")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rtl-run", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("congestion/docs"))
    args = parser.parse_args()
    log = (args.rtl_run / "xsim.log").read_text()
    if "[TB_CONGESTION_OE_AUDIT] PASSED" not in log or "Fatal:" in log:
        raise ValueError("RTL audit did not pass")
    model, xy = Counter(), Counter()
    for sx in range(13):
        for sy in range(13):
            for dx in range(13):
                for dy in range(13):
                    for parity in (0, 1):
                        model.update(path(sx, sy, dx, dy, parity))
                        xy.update(path(sx, sy, dx, dy, parity, xy=True))
    names = {1: "N", 2: "S", 3: "W", 4: "E"}
    with (args.rtl_run / "oe_static_rtl_links.csv").open() as stream:
        actual = {(int(r["x"]), int(r["y"]), names[int(r["port"])]): int(r["route_count_two_parities"]) for r in csv.DictReader(stream)}
    if actual != model:
        raise ValueError("RTL and independent static route counts differ")
    possible = legal_path_count(0, 0, 12, 12)
    selected = len({path(0, 0, 12, 12, bit) for bit in (0, 1)})
    assert possible == 18564 and selected == 2
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output = args.output_dir / "oe_audit_link_load_20261028.csv"
    with output.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["x", "y", "direction", "xy_routes_per_id_parity_average", "oe_routes_per_id_parity_average"])
        for key in sorted(model):
            writer.writerow([*key, xy[key] / 2, model[key] / 2])
    print(f"624 RTL link counts match; XY peak={max(xy.values())/2:g}, OE peak={max(model.values())/2:g}")
    print(f"(0,0)->(12,12): legal minimal OE paths={possible}, current ID-selected paths={selected}")
    print(f"Saved {output}; fixed-route distribution, not dynamic utilization.")


if __name__ == "__main__":
    main()
