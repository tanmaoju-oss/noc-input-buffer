# 当前OE/XY流控滞回归因

<!-- Modify by Michael Tan，20261029: isolate buffer reopen hysteresis without changing allocation or packet ownership. -->

父版本eccd9af，22个RTL来源与SHA见docs/parent_manifest.tsv，仅circular_buffer变化。模式0保留7关闭、降至1重开；模式1保持7关闭和容量保护，降至6即重开。不会改变TAIL成功写入才归还VC、元数据、源调度、路由或仲裁，不使用~is_full_o重新分配。两模式共享源码，只切CURRENT_FAST_REOPEN宏及记录参数；OFF需精确复现正式基线22字段，ON仍通过全部包正确性与完全排空，不能只按延迟判断。

入口：bash congestion/experiments/oe_current_flow/scripts/simulation/run_flow.sh 0 -generic_top ALGORITHM=2（1为干预，0为原滞回）。正式congestion/src和根src不改。

## 本轮结果

全部用相同种子1234501、0.06、预热300+测量1200、15260生成/完成包、12277样本、哈希d84c82f8。OFF全部22字段复现正式OE；所有模式完整计分板、排空、源码SHA及共同task比较通过。

| 变体 | 平均总延迟 | 源排队 | P99 | run |
|---|---:|---:|---:|---|
| FLOW_OFF | 1092.088784 | 771.594526 | 2729 | congestion/experiments/oe_current_flow/vivado_sim_wsl/tb_oe_current_flow_sim/run_mode0_O09chAa4 |
| FLOW_READY_OE | 688.437403 | 375.371345 | 2210 | congestion/experiments/oe_current_flow/vivado_sim_wsl/tb_oe_current_flow_sim/run_mode1_qcFOyZR3 |
| FLOW_READY_XY | 55.736418 | 0.473161 | 165 | congestion/experiments/oe_current_flow/vivado_sim_wsl/tb_oe_current_flow_sim/run_mode1_jZBwwLfe |

详见../../docs/current_oe_root_cause_20261029.md及current_cause_controls_20261029.csv。仅为单因素归因，不自动合入正式RTL，未综合；延迟改善不能代替全部功能/参数回归。

<!-- Modify by Michael Tan，20261029: record exact OFF controls, counterexamples and provenance for completed experiments. -->
