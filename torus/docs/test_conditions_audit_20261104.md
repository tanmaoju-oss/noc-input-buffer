# Mesh/Torus 性能测试条件复核（2026-11-04）

<!-- Modify by Michael Tan，20261104: audit hidden comparison variables with exact controls and source admission experiments. -->

## 结论

外部测试条件已对齐，没有发现两侧包数、轨迹、种子、窗口、包长、缓存深度或接收背压被误设为不同值。但原比较同时改变了拓扑/路径与下游VC资格，不是单独改变拓扑的实验：Mesh每跳可选4个VC，当前Torus在非LOCAL出口的合法掩码为one-hot，每跳通常只能申请1个指定类别VC。四类VC不等于每条路径可同时用4个VC。

此外，固定`packet_id % 4`接入VC和每源单包游标会造成源队首阻塞。这是两侧相同但会与各自实现不同程度相互作用的注入条件。新增6组同轨迹对照证实它会放大延迟，却不足以解释整个差距。

原0.12种子1的800.932/31.616倍数为含源排队总延迟；入网后分别30.089/24.026周期，仅约1.25倍。Torus吞吐跟不上出生流量而积累源队列，是总延迟放大的直接表现；不能将25倍读作每个入网包在路由器里慢25倍。限制吞吐的内部机制仍未被受控实验独立定位，dateline单一合格VC、VC预约寿命及仲裁/回压是后续检查对象。

## 核对的相同条件与有意差异

| 项目 | 核对结果 |
| --- | --- |
| 网络规模、时钟、复位 | 两侧5×5、10ns、5个下降沿后解除复位；运行彼此独立 |
| 物理VC数、缓存 | 两侧4 VC，每VC深度8，默认参数和源码一致 |
| 流量出生和目的 | 原10对trace逐字节一致；新6组trace再次逐字节一致 |
| 包长与源策略 | 原测试均4flit、单源有序游标、id%4接入VC，不绕过受阻包 |
| 注入握手 | HEAD检查source_free和on_off，BODY/TAIL锁定同VC；source_free只由下游TAIL读出释放脉冲归还 |
| 接收端 | 两侧always-ready，TAIL收到后下一周期归还输出VC；无外加不同背压 |
| 延迟样本 | 同一出生窗口1001～4000，包含排空后收到的所有样本；不是按已收到包截断 |
| 吞吐口径 | 同一1001～4000窗口，flit数/(25×3000) |
| 路径与物理连接 | 有意不同：Mesh普通XY，Torus最短环绕XY，后者增加环绕链路 |
| 下游VC资格 | 有意不同：Mesh可选4个，Torus非LOCAL出口通常one-hot；不是资源资格等价 |
| 实际注入时刻和排空时长 | 不是预设成相同，属于背压下的输出结果，已分别保存 |

`input_buffer`的原/副本diff仅为逐包allowed_vcs字段及其输入输出，原TAIL读出归还逻辑保留；SA及两级仲裁实现未改。进一步用副本共享模块的Mesh模式做实际对照，排除仅凭静态diff推断性能相同。

## 六组新验证

固定0.12包/节点/周期、种子1、均匀非自身目的、相同4000周期流量。每组11889包/47556flit完整送达，延迟样本8925包，共6组71334包/285336flit。全部检查逐包负载/顺序/目的、跳数守恒和最终FIFO/metadata/VC释放，均PASS。

新增独立`tb_torus_conditions_control`，不改原TB、RTL。policy0保持固定id%4；policy1只在HEAD选择VC时从可接入且on_off开启集合中按id%4起点扫描，BODY/TAIL保持HEAD选中的VC，不绕过队首包。原Mesh、共享模块Mesh、Torus各运行两模式。

| 实现 | 源VC策略 | 总均延迟 | 源排队 | 入网后 | 窗口输出 | 排空周期 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 原Mesh | 固定 | 31.616 | 7.590 | 24.026 | 0.47807 | 29 |
| 副本Mesh模式 | 固定 | 31.616 | 7.590 | 24.026 | 0.47807 | 29 |
| Torus | 固定 | 800.932 | 770.843 | 30.089 | 0.36403 | 1838 |
| 原Mesh | 选择可用VC | 27.413 | 1.828 | 25.585 | 0.47748 | 27 |
| 副本Mesh模式 | 选择可用VC | 27.413 | 1.828 | 25.585 | 0.47748 | 27 |
| Torus | 选择可用VC | 614.187 | 562.538 | 51.648 | 0.38691 | 1367 |

延迟单位周期，吞吐单位flit/节点/周期。三组固定策略的trace、summary、逐包时间戳均逐字节精确复现原结果；副本/原Mesh在两种策略的逐包时间戳及源阻塞计数也完全一致。故新增观测没有改变原测试，副本共享模块本身没有使Mesh在该测试点发生性能偏移。

Torus选择可用VC后总均延迟降低约23.32%，但与同策略Mesh仍差约22.4倍；Torus入网后延迟从30.089升至51.648，说明把包更早送入网络也会增加在网等待。不能用此实验把剩余差距都归给某一个RTL模块，也不能将23.32%当成所有机制可相加的独立份额。

## 源阻塞和路径需求复核

固定策略下，Torus有75743个源节点周期因选定HEAD接入VC未归还而等待，其中74485周期另有可接入且ready的VC；Mesh对应14325/14265周期。这说明固定VC策略的确存在明显空等机会。可用VC策略下Torus仍有65168个HEAD所有权阻塞节点周期。六组source HEAD on_off和BODY/TAIL on_off阻塞计数都为0。本次采样覆盖整个生成与排空过程，计数单位是当前队首的源节点周期，不能直接除以包数替代所有包的累计排队延迟，也不等于内部网络没有on_off等待。

用原trace重放最短路径，仅计算生成期4000周期平均需求，最忙物理有向链路Mesh为0.639、Torus为0.358 flit/生成周期，两者无链路超过1。此为预定路径需求、不是实测利用率；未包含突发、VC预约导致的有效服务下降或仲裁空转。它不支持“因为Torus某条物理链路的平均需求超过每周期1flit才积压”的解释，也不证明网络实际可达到1flit/周期。

## 证据与复现

新增文件：`torus/testbench/tb_torus_conditions_control.sv`、`torus/scripts/simulation/run_tb_torus_conditions_control.sh`、`torus/scripts/simulation/analyze_torus_conditions_control.py`及本报告/`conditions_control_20261104/`；更新根与子项目进度文档。RTL无改动。

```bash
bash torus/scripts/simulation/run_tb_torus_conditions_control.sh mesh
bash torus/scripts/simulation/run_tb_torus_conditions_control.sh sharedmesh
bash torus/scripts/simulation/run_tb_torus_conditions_control.sh torus
python3 torus/scripts/simulation/analyze_torus_conditions_control.py \
  torus/vivado_sim_wsl/tb_torus_conditions_control_sim/run_mesh_00h1FbnU \
  torus/vivado_sim_wsl/tb_torus_conditions_control_sim/run_sharedmesh_cuqJfWCx \
  torus/vivado_sim_wsl/tb_torus_conditions_control_sim/run_torus_5O9fsxpc \
  torus/vivado_sim_wsl/tb_torus_performance_sim/run_mesh_JqyjmuA2/rate1200_seed1_traffic0 \
  torus/vivado_sim_wsl/tb_torus_performance_sim/run_torus_nfsUpoFJ/rate1200_seed1_traffic0 \
  torus/docs/conditions_control_20261104
```

WSL Vivado2025.2沙箱外通过目录均位于`torus/vivado_sim_wsl/tb_torus_conditions_control_sim/`，分别为上述run名；每个`policy0/1`保存xsim.log、console.log、trace.csv、packets.csv、summary.csv、stalls.csv，run根保存编译/展开日志及源SHA256。

便携数据：[controls.csv](conditions_control_20261104/controls.csv)、[路径需求](conditions_control_20261104/route_demand.csv)、[自动审计](conditions_control_20261104/audit.txt)，同目录保留三份源码指纹。分析脚本首次运行有重复policy键的Python TypeError，修正分析脚本后审计通过，未改动测试或结果文件。仿真无功能失败，保留既有接口/环境展开警告。

本次受控验证仅覆盖上述一个高负载点，不能替代多种子/多负载归因。未改变dateline约束来做不安全的“关闭死锁规避”比较。没有修改RTL或运行综合，没有提交/推送/Windows同步。

## 后续逐跳诊断

[逐跳机制报告](bottleneck_analysis_20261104.md)补充了确定的结构瓶颈证据：单一合格VC与TAIL读出归还导致无竞争4flit单跳每包4周期气泡，Torus链路吞吐0.5/Mesh1；全网主要阻塞位于合法VC预约。已区分拓扑收益、不可达VC资源、局部服务开销与源排队放大，候选资源重组仍仅模型、未改RTL。

<!-- Modify by Michael Tan，20261104: link verified hop-level bottleneck evidence and preserve original measurements. -->
