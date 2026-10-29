#!/usr/bin/env python3
# Modify compare matched OE/TwoAware cohorts and retain XY reference, Michael Tan, 20261028
import argparse
import csv
import hashlib
import re
from pathlib import Path


def manifest(directory):
    result = {}
    for line in (directory / "source_sha256.txt").read_text().splitlines():
        digest, filename = line.split(maxsplit=1)
        result[Path(filename)] = digest
    return result


def read_run(directory, algorithm, tag):
    log = (directory / "xsim.log").read_text()
    if f"[{tag}] PASSED alg={algorithm}" not in log or "Fatal:" in log:
        raise ValueError(f"Incomplete/failed run: {directory}")
    with (directory / "latency_summary.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 6 or len({r["rate_ppm"] for r in rows}) != 6:
        raise ValueError("Expected six complete distinct rates")
    for row in rows:
        if int(row["algorithm"]) != algorithm or row["offered_packets"] != row["completed_packets"]:
            raise ValueError("Algorithm or conservation mismatch")
        if abs(float(row["mean_total"])-float(row["mean_queue"])-float(row["mean_network"]))>0.00001:
            raise ValueError("Latency decomposition mismatch")
    return {int(row["rate_ppm"]): row for row in rows}


def canonical_tb(text):
    text = text.replace("module tb_congestion_oe_latency_compare;", "module tb_congestion_latency_compare;")
    text = text.replace("parameter ALGORITHM=2,", "parameter ALGORITHM=0,")
    text = text.replace("if(ALGORITHM!=2 || $bits(flit_t)!=258)", "if(ALGORITHM!=0 && ALGORITHM!=4 || $bits(flit_t)!=258)")
    text = text.replace("[TB_CONGESTION_OE_LATENCY_COMPARE]", "[TB_CONGESTION_LATENCY_COMPARE]")
    return re.sub(r"//[^\n]*", "", text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("oe-run", "twoaware-run", "xy-run", "output-dir"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    directories = {"oe": args.oe_run, "two": args.twoaware_run, "xy": args.xy_run}
    data = {
        "oe": read_run(args.oe_run, 2, "TB_CONGESTION_OE_LATENCY_COMPARE"),
        "two": read_run(args.twoaware_run, 4, "TB_CONGESTION_LATENCY_COMPARE"),
        "xy": read_run(args.xy_run, 0, "TB_CONGESTION_LATENCY_COMPARE"),
    }
    manifests = {key: manifest(directory) for key, directory in directories.items()}
    rtl = [{p: h for p, h in mapping.items() if p.parent.name == "src"} for mapping in manifests.values()]
    if len(rtl[0]) != 22 or rtl[0] != rtl[1] or rtl[1] != rtl[2]:
        raise ValueError("RTL sources differ")
    tb_text = {}
    for key, mapping in manifests.items():
        paths = [p for p in mapping if p.parent.name == "testbench"]
        if len(paths) != 1:
            raise ValueError("Unexpected TB manifest")
        path = paths[0]
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != mapping[path]:
            raise ValueError("Recorded TB differs from current file")
        tb_text[key] = canonical_tb(raw.decode())
    if tb_text["oe"] != tb_text["two"] or tb_text["two"] != tb_text["xy"]:
        raise ValueError("Workloads/scoreboards differ after top/algorithm normalization")
    pairs = ("seed", "warmup", "measure", "offered_packets", "cohort_packets", "actual_offered_ppc", "trace_hash")
    rows = []
    for rate in sorted(data["oe"]):
        o, t, x = data["oe"][rate], data["two"][rate], data["xy"][rate]
        if any(o[field] != t[field] or t[field] != x[field] for field in pairs):
            raise ValueError("Offered traces differ")
        row = {"target_packet_rate": f"{rate/1000000:.3f}", "cohort_packets_each": o["cohort_packets"], "trace_hash": o["trace_hash"]}
        for name in ("mean_total", "mean_queue", "mean_network", "p95_total", "p99_total", "arrival_ppc", "source_backlog_stop", "net_outstanding_stop"):
            for key, source in (("oe", o), ("twoaware", t), ("xy", x)):
                row[f"{key}_{name}"] = source[name]
        row["twoaware_reduction_vs_oe_percent"] = f'{100*(float(o["mean_total"])-float(t["mean_total"]))/float(o["mean_total"]):.3f}'
        rows.append(row)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    path = args.output_dir / "oe_twoaware_latency_20261028.csv"
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    better = sum(float(r["twoaware_reduction_vs_oe_percent"]) > 0 for r in rows)
    text = f"""# OE 与 TwoAware 延迟比较（2026-10-28）

<!-- Modify by Michael Tan，20261028: isolate OE route restrictions from the current two-hop decision policy. -->

## 结论范围

同一均匀流量下，TwoAware在{better}档平均延迟低于当前OE，{6-better}档更高或相同。具体数值见表。对照的是现有OE实现（packet ID/坐标异或选择）与当前TwoAware占用量求和实现，不代表所有OE或所有拥塞感知算法。

## 结果分析

轻载两者均约23～26周期，感知收益较小。0.04时OE已出现明显排队，TwoAware仍接近XY；0.06时OE源排队1444.830、网络内330.144周期，TwoAware分别162.643、216.291周期，两个组成均改善。0.08时TwoAware网络内264.403高于OE的225.702，但源排队1093.369显著低于OE的2450.920，因此总延迟仍更低；单看入网后的延迟会掩盖源端等待。

当前证据支持两跳决策相对这份无感知OE的净收益，仍不足以证明优于XY。OE使用的“随机位”是坐标和packet ID的单比特异或，源节点处当前/源坐标最低位抵消，实际只剩packet ID奇偶校验与目的坐标最低位；不同源的选择可能相关，不能把它视为独立均匀随机的理想OE基线。TwoAware根据局部指标改变选择，收益包含感知比较与不同平局策略的共同作用，贡献分离仍需消融。

## 公平性与统计方法

- 复用[前次方法](xy_twoaware_latency_20261028.md)：13×13、4VC、每VC深度8、暂用258-bit完整flit、固定4-flit包、种子1234501、均匀非自身目的、预热300+生成统计1200周期，接收端始终ready，停止生成后继续注入直到完全排空。
- 新增独立OE TB与配套入口，不修改RTL；OE与原TB只在top/结果标签/算法默认值及配置保护上不同，其余共同主体逐字核对一致。
- 22个RTL文件SHA256完全相同，XY/TwoAware复用已通过结果；每档三种算法的生成包数、出生窗口样本数、实际生成率和轨迹哈希相同。
- 总延迟=出生到TAIL，源排队=出生到HEAD进网，网络内=HEAD进网到TAIL；按出生窗口选全部样本，完成后才计算，避免截尾。
- 每算法6档合计生成并送达54494包，出生窗口样本43890包；全部逐flit内容、目的、顺序、唯一性、VC所有权及最终零占用检查通过。

## 平均总延迟（周期）

正的降低比例表示TwoAware比OE更快。

| 注入率（packet/node/cycle） | 统计包数/算法 | XY | OE | TwoAware | TwoAware相对OE降低 |
|---:|---:|---:|---:|---:|---:|
"""
    for r in rows:
        text += f'| {r["target_packet_rate"]} | {r["cohort_packets_each"]} | {float(r["xy_mean_total"]):.3f} | {float(r["oe_mean_total"]):.3f} | {float(r["twoaware_mean_total"]):.3f} | {r["twoaware_reduction_vs_oe_percent"]}% |\n'
    text += """
## 延迟分解与尾延迟

| 注入率 | OE源排队 | TwoAware源排队 | OE网络内 | TwoAware网络内 | OE P95 | TwoAware P95 | OE P99 | TwoAware P99 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
"""
    for r in rows:
        text += f'| {r["target_packet_rate"]} | {float(r["oe_mean_queue"]):.3f} | {float(r["twoaware_mean_queue"]):.3f} | {float(r["oe_mean_network"]):.3f} | {float(r["twoaware_mean_network"]):.3f} | {r["oe_p95_total"]} | {r["twoaware_p95_total"]} | {r["oe_p99_total"]} | {r["twoaware_p99_total"]} |\n'
    text += f"""
## 实现差异及归因边界

两者具有相同的OE合法候选约束，均不增加最短路径跳数；OE在两个方向都允许时使用packet ID与源/目的/当前坐标最低位异或选择，属于确定性散列；TwoAware比较两跳方向占用量之和，同分偏Y。当前对照反映整套感知决策（含平局策略）的净效果，不能单独量化指标、平局规则或决策时机各自的贡献。XY仍为最终性能参照，优于OE不能自动等同于优于XY。

单种子、均匀流量、有限生成窗口，未证明稳态、多种子显著性或其他流量优势。窗口到达率列在CSV中，不等同于饱和吞吐量。ThreeAware不纳入。

## 复现

```bash
bash congestion/scripts/simulation/run_tb_congestion_oe_latency_compare.sh
```

- OE新run：`{args.oe_run}`。
- TwoAware复用run：`{args.twoaware_run}`。
- XY复用run：`{args.xy_run}`。
- 原始摘要为各run中的latency_summary.csv；完整日志、参数、SHA256一起保留。
- 配对[CSV](oe_twoaware_latency_20261028.csv)。
"""
    (args.output_dir / "oe_twoaware_latency_20261028.md").write_text(text)
    print(f"Validated six matched triplets; wrote {path}")
    for r in rows:
        print(r["target_packet_rate"], r["oe_mean_total"], r["twoaware_mean_total"], r["twoaware_reduction_vs_oe_percent"])


if __name__ == "__main__":
    main()
