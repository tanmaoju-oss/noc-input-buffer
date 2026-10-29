# 当前协议下OE延迟归因实验

<!-- Modify by Michael Tan，20261029: isolate current-protocol resource-choice interventions from official RTL. -->

父版本eccd9af/3581978，22个正式RTL复制SHA见docs/parent_manifest.tsv。正式congestion/src和根src不改。

第一项单因素：仅比较最低可预约VC与“存在可接收的可预约VC时优先选择它”。不改变归还、包所有权、OE方向、缓冲或仲裁。两模式共享源码和计分板，mode0须精确复现正式当前基线全部22个CSV字段；mode1必须保持同样生成轨迹和全量排空，验证通过后才解释结果。接入资格和on_off是独立条件，任何模式都不能按~is_full_o重新分配。

命令：bash congestion/experiments/oe_current_diagnosis/scripts/simulation/run_vc_choice.sh 0 -generic_top ALGORITHM=2（1为干预，0为OFF）。使用WSL Vivado2025.2，生成结果在本实验vivado_sim_wsl/tb_oe_current_vc_choice_sim/。

## 本轮结果

全部用相同种子1234501、0.06、预热300+测量1200、15260生成/完成包、12277样本、哈希d84c82f8。OFF全部22字段复现正式OE；所有模式完整计分板、排空、源码SHA及共同task比较通过。

| 变体 | 平均总延迟 | 源排队 | P99 | run |
|---|---:|---:|---:|---|
| VC_OFF | 1092.088784 | 771.594526 | 2729 | congestion/experiments/oe_current_diagnosis/vivado_sim_wsl/tb_oe_current_vc_choice_sim/run_mode0_qUB7kK4o |
| VC_READY | 947.116885 | 648.991692 | 2993 | congestion/experiments/oe_current_diagnosis/vivado_sim_wsl/tb_oe_current_vc_choice_sim/run_mode1_5LUPlXhW |

详见../../docs/current_oe_root_cause_20261029.md及current_cause_controls_20261029.csv。仅为单因素归因，不自动合入正式RTL，未综合；延迟改善不能代替全部功能/参数回归。

<!-- Modify by Michael Tan，20261029: record exact OFF controls, counterexamples and provenance for completed experiments. -->
