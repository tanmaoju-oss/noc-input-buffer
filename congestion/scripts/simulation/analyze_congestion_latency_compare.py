#!/usr/bin/env python3
"""Modify validate paired latency runs and write reproducible comparisons, Michael Tan, 20261028."""
import argparse
import csv
from pathlib import Path


def read_run(directory, algorithm):
    log = (directory / "xsim.log").read_text()
    if f"[TB_CONGESTION_LATENCY_COMPARE] PASSED alg={algorithm}" not in log or "Fatal:" in log:
        raise ValueError(f"Run is incomplete or failed: {directory}")
    with (directory / "latency_summary.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 6 or len({row["rate_ppm"] for row in rows}) != 6:
        raise ValueError("Expected six distinct rates")
    for row in rows:
        if int(row["algorithm"]) != algorithm or row["offered_packets"] != row["completed_packets"]:
            raise ValueError("Algorithm or packet conservation mismatch")
        if abs(float(row["mean_total"]) - float(row["mean_queue"]) - float(row["mean_network"])) > 0.00001:
            raise ValueError("Latency decomposition mismatch")
    return {int(row["rate_ppm"]): row for row in rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xy-run", required=True, type=Path)
    parser.add_argument("--twoaware-run", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    xy = read_run(args.xy_run, 0)
    two = read_run(args.twoaware_run, 4)
    if set(xy) != set(two):
        raise ValueError("Rate grids differ")
    if (args.xy_run / "source_sha256.txt").read_text() != (args.twoaware_run / "source_sha256.txt").read_text():
        raise ValueError("The algorithms were not run with identical source files")
    paired_fields = ("seed", "warmup", "measure", "offered_packets", "cohort_packets", "actual_offered_ppc", "trace_hash")
    combined = []
    for ppm in sorted(xy):
        x, t = xy[ppm], two[ppm]
        if any(x[field] != t[field] for field in paired_fields):
            raise ValueError(f"Offered traffic differs at rate {ppm}")
        result = {"target_packet_rate": f"{ppm / 1000000:.3f}", "cohort_packets_each": x["cohort_packets"], "trace_hash": x["trace_hash"]}
        for name in ("mean_total", "mean_queue", "mean_network", "p95_total", "p99_total", "arrival_ppc", "accepted_heads_ppc", "source_backlog_stop", "net_outstanding_stop"):
            result[f"xy_{name}"] = x[name]
            result[f"twoaware_{name}"] = t[name]
        result["twoaware_total_reduction_percent"] = f'{100 * (float(x["mean_total"]) - float(t["mean_total"])) / float(x["mean_total"]):.3f}'
        combined.append(result)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output_csv = args.output_dir / "xy_twoaware_latency_20261028.csv"
    with output_csv.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(combined[0]))
        writer.writeheader()
        writer.writerows(combined)
    text = """# XY 与 TwoAware 延迟对比（2026-10-28）

<!-- Modify by Michael Tan，20261028: report paired measured packet latency instead of drain-time proxies. -->

## 结论与分析

本轮均匀流量下，XY在六档注入率的平均总延迟均更低。0.005～0.04时TwoAware平均延迟增加0.33%～5.94%；0.06时为XY的4.67倍，0.08时为3.39倍。不能据此认定所有流量下XY都更优，但当前默认TwoAware没有在这组负载下体现优势。

0.06时，XY/TwoAware源排队分别11.048/162.643周期，网络内分别70.023/216.291周期。0.08时源排队303.374/1093.369周期，网络内97.593/264.403周期。因此差异同时存在于网内等待和源端积压，不能只归因于源FIFO。0.08的窗口到达率XY为0.056563，TwoAware为0.023964 packet/node/cycle，显示统计窗口内TwoAware完成包更少；停止生成后两者仍全部排空。

从RTL可确定，两者都选最短路径；轻载缺少可避开的排队，TwoAware不会减少跳数。TwoAware的选择还受OE候选约束、两跳瞬时占用量近似、同分偏Y和HEAD入队即锁定路由等设计影响。高负载退化的具体贡献尚未用逐链路占用/选路分布统计隔离，不能把这些可能机制直接当作已证实根因。当前应继续用XY作性能基线，再研究TwoAware高负载的路径与资源分布。

## 测试方法

WSL/Linux Vivado 2025.2，使用同一套 congestion RTL，仅 ALGORITHM=0/4 切换。13×13、4 VC、每VC深度8、完整flit258 bit、每包4 flit；TwoAware使用方向占用量和两跳求和（REFERENCE=0、AGG=0）。不修改RTL。

均匀非自身目的流量；固定种子1234501，用独立于DUT反馈的确定性散列逐源逐周期生成事件和目的。预热300周期，随后1200周期生成统计样本。源FIFO按包顺序发送，VC按packet ID轮转；上游遵守on_off，接收端始终ready，只在收到TAIL后释放目的VC。

同一注入率下，两算法的生成包数、出生窗口样本数、目的/时刻轨迹哈希及所有源码SHA256完全匹配。停止生成后继续发送全部源数据，完全排空并额外观察20周期。检查逐flit内容、目的、顺序、唯一性、VC所有权、error_o与最终零占用，无完成样本截尾。

统计对象为出生于1200周期窗口内的全部packet，全部跟踪至TAIL接收：总延迟=TAIL接收周期−生成周期；源排队=HEAD进入本地router周期−生成周期；网络内延迟=TAIL接收周期−HEAD进入本地router周期。三者逐包相加一致，单位均为周期。P95/P99使用最近秩法。网络内延迟包含包序列化及HEAD之后尚未注入flit的背压等待。

## 平均总延迟与尾延迟

“降低比例”=(XY−TwoAware)/XY，正值代表TwoAware延迟更低，负值代表更高。

| 目标注入率（packet/node/cycle） | 每算法统计包数 | XY均值 | TwoAware均值 | TwoAware降低比例 | XY P95 | TwoAware P95 | XY P99 | TwoAware P99 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
"""
    for row in combined:
        text += f'| {row["target_packet_rate"]} | {row["cohort_packets_each"]} | {float(row["xy_mean_total"]):.3f} | {float(row["twoaware_mean_total"]):.3f} | {row["twoaware_total_reduction_percent"]}% | {row["xy_p95_total"]} | {row["twoaware_p95_total"]} | {row["xy_p99_total"]} | {row["twoaware_p99_total"]} |\n'
    text += """
## 延迟分解与窗口到达率

窗口到达率统计同一1200周期窗口内的所有TAIL（含预热时生成的包），单位packet/node/cycle；它与出生窗口样本的平均延迟属于不同统计口径，不作为已证明的稳定吞吐量。

| 目标注入率 | XY源排队 | TwoAware源排队 | XY网络内 | TwoAware网络内 | XY窗口到达率 | TwoAware窗口到达率 | XY停生成时未进网包数 | TwoAware停生成时未进网包数 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
"""
    for row in combined:
        text += f'| {row["target_packet_rate"]} | {float(row["xy_mean_queue"]):.3f} | {float(row["twoaware_mean_queue"]):.3f} | {float(row["xy_mean_network"]):.3f} | {float(row["twoaware_mean_network"]):.3f} | {row["xy_arrival_ppc"]} | {row["twoaware_arrival_ppc"]} | {row["xy_source_backlog_stop"]} | {row["twoaware_source_backlog_stop"]} |\n'
    text += f"""
## 复现与结果文件

```bash
bash congestion/scripts/simulation/run_tb_congestion_latency_compare.sh -generic_top ALGORITHM=0
bash congestion/scripts/simulation/run_tb_congestion_latency_compare.sh -generic_top ALGORITHM=4
```

- XY run：`{args.xy_run}`。
- TwoAware run：`{args.twoaware_run}`。
- 每个run包含xvlog/xelab/xsim日志、参数、源码哈希和latency_summary.csv。
- 配对汇总：[CSV](xy_twoaware_latency_20261028.csv)。

## 解释边界

这是一组种子、均匀流量、固定4-flit包及有限生成窗口的比较。高负载可能尚未达到稳态，生成停止后的排空会让剩余包获得更轻的竞争环境；本表适合比较相同有限负载的完整包延迟，不是无限持续负载的稳态排队延迟或饱和点证明。不外推至转置/热点等流量，也不声称多种子统计显著性。实际硬件频率和实现成本未测，周期数不能直接替代纳秒延迟。ThreeAware不纳入本次对比。
"""
    (args.output_dir / "xy_twoaware_latency_20261028.md").write_text(text)
    print(f"Validated six matched pairs; wrote {output_csv}")
    for row in combined:
        print(row["target_packet_rate"], row["xy_mean_total"], row["twoaware_mean_total"], row["twoaware_total_reduction_percent"])


if __name__ == "__main__":
    main()
