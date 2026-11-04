# Torus 高负载退化：逐跳机制与理论分析（2026-11-04）

<!-- Modify by Michael Tan，20261104: establish VC-class serialization with nonintrusive profiling, exhaustive reachability and single-hop controls. -->

## 结论与证据强度

用户的拓扑直觉成立：保留Mesh的原链路和服务能力，再增加环绕链路，可以提供更短路径和更大可用连接集合。但当前实现同时改变了VC资格和路由，实际可用服务集合不再包含原Mesh的全部选择。首版为便于明确dateline资源顺序，采用X前/X后/Y前/Y后四个全局编号、每类仅1个VC。这是当前实现的保守方案，不是Torus必须付出的固定代价。

本次已定位一个确定的结构瓶颈：**单一合格下游VC，与“下游TAIL读出后才归还VC”的包级独占时序相结合，造成不能由其他VC填补的包间气泡；同一物理链路有余量、其他VC空闲，下一包仍必须等待指定VC。** 饱和单跳对照直接复现该机制；全网逐跳观测表明其也是主要阻塞位置。不能把所有性能差都归为任意单一因素的精确比例，但无需再仅凭总延迟猜测是否存在该问题。

新增4组全网观测和4组单跳微基准全部PASS。4组观测的trace/packets/summary/stalls与前一轮控制逐字节一致，证明观测没有改变已报告结果；本轮合计48580包/200464flit完成正确性检查。所有RTL、原性能TB及前一轮控制TB均未修改。

## 1. 理论收益确实存在，为何不自动表现为更低延迟

5×5均匀非自身目的的600条路径穷举结果：

| 理论项目 | Mesh | Torus |
| --- | ---: | ---: |
| 物理有向链路 | 80 | 100 |
| 平均最短跳数 | 3.333 | 2.500 |
| 最大最短跳数 | 8 | 4 |

即链路增加25%，平均跳数减少25%。本项目仿真时钟相同、环绕链路也不额外插入时延，因此没有长线/时钟降频导致Torus变慢的因素。低负载Torus的延迟改善与短路径相符。

新增环绕也引入环形资源依赖，不能只连接边界就保留不受约束的分配。Dally/Seitz原论文讨论的是通过虚拟通道与通道依赖顺序消除环，而不是要求每个维度占一个全局独立VC编号：[原论文PDF](https://comp.anu.edu.au/courses/comp4300/assets/lectures/refs/dallyDeadlockAvoid87.pdf)。无死锁保证依赖受约束的依赖图，不意味着必须采用本项目首版低利用率的四类单VC方案。

## 2. 当前实现比“4VC Torus”这个名称更受限制

### 2.1 逐跳只能请求一个指定编号

`src/rc_unit_Xiugai2.sv:63/74`实际计算`allowed_vcs_o = 1 << next_class`，非LOCAL出口只有一个bit。X阶段仅VC0/1，Y阶段仅VC2/3，是否跨dateline确定其中哪一个。`src/vc_allocator.sv`的请求和分配都使用该掩码，不能在指定VC忙时改用其他空闲VC。

X/Y维度本来已由物理输入端口区分：水平链路进入水平输入端口，垂直链路进入垂直输入端口。当前又用全局VC编号重复区分维度，导致水平输入中的VC2/3、垂直输入中的VC0/1无法用于合法网络转发。

### 2.2 5×5最短路径使资源浪费进一步扩大

枚举625条含自身路径，汇总每条有向物理链路可能写入的所有下游VC编号：

- 100条链路中的80条，在**全部**合法最短路径中始终只会用一个VC编号。
- 其余20条最多用两个VC编号。
- 网络方向物理输入端口共配置400个VC，实际可到达`80×1+20×2=120`个，即30%；280个VC对这些路径永久不可达。
- 对应FIFO配置槽位为3200个，可达类别对应960个。原Mesh的80条实际有向链路可使用全部320个VC，即2560个槽位。

这些是静态可达资源上限，不是动态FIFO占用或可同时装满的容量；没有包括LOCAL注入/弹出资源，也不把Mesh未接线的边界端口算作有效链路。不能将“70%不可达”当作“性能必然下降70%”。

5节点环中最短单维段至多2跳，许多链路根本不会同时出现跨界前/后两种历史，因此不能认为同一条链路总能轮流利用两个dateline类。结果见[静态资源JSON](bottleneck_analysis_20261104/reachable_resources.json)和[每链路VC集合](bottleneck_analysis_20261104/reachable_resources.csv)。

## 3. 无竞争单跳实验：明确的四周期包间气泡

独立`tb_torus_singlehop_service`在同一5×5环境中只注入`(1,1)→(2,1)`一个饱和源，路径在两侧都为向EAST一跳，不经过环绕、不存在其他竞争流，接收端始终ready，源选择可用接入VC。两侧使用相同子项目共享模块，仅拓扑模式及其VC资格不同。每档256包，检查逐flit内容、目的、顺序、链路/接收计数及最终所有FIFO/metadata/VC释放。

| 包长 | 实现 | 相邻HEAD间隔（全部255次） | 包间空周期 | 周期性链路吞吐 |
| ---: | --- | ---: | ---: | ---: |
| 4 | Mesh模式 | 4 | 0 | 1.0 flit/周期 |
| 4 | Torus | 8 | 4 | 0.5 flit/周期 |
| 16 | Mesh模式 | 16 | 0 | 1.0 flit/周期 |
| 16 | Torus | 20 | 4 | 0.8 flit/周期 |

周期性吞吐按`包长/相邻HEAD平均间隔`计算，排除首尾截断影响。每条原始间隔均一致，不是只挑首个包或平均值接近。Mesh实际上只需交替使用下游VC0/1，即可隐藏归还间隙；Torus在此路径只能使用VC0。

4flit的实际链路时序如下，H/B/T为一个包的HEAD/BODY/TAIL：

```text
周期               3  4  5  6  7  8  9 10 11
Mesh 一跳输出      H  B  B  T  H  B  B  T  H
Torus 一跳输出     H  B  B  T  ·  ·  ·  ·  H
```

首包上游在第2周期获配，3～6周期跨链路；下游第5周期开始向终端输出，至第8周期TAIL读出。在此期间下游VC仍属首包，尽管上游第6周期已发完TAIL、链路从第7周期起空闲。

`input_buffer_src_circular_full.sv:302`在下游TAIL成功读出后寄存`vc_allocatable_o`；上游第9周期处理释放，第10周期才获配下一包，第11周期发下一个HEAD。Mesh可在第6周期先获配另一个VC，第7周期立即发下一包；Torus的单类单VC做不到。

因此单跳同类流中，本设计出现`有效服务率=L/(L+4)`的固定开销，实测L=4与16吻合。这不是所有Torus算法的理论上限；不同类流有时可交错，整个网络也不能直接按`100×0.5`计算总带宽。但该对照已经把路径、物理环绕、输入随机性、多流热点和接收背压排除，直接证明当前类别/归还组合会损失链路服务能力。

数据与前24周期事件见[单跳汇总](bottleneck_analysis_20261104/singlehop_summary.csv)及同目录`singlehop_*_first24.csv`。

## 4. 全网观测：实际等待在哪里

条件保持0.12包/节点/周期、种子1、均匀流量；窗口1001～4000，分别保留固定接入VC与可用接入VC两模式。VA分类取队首包资格，SA分类取已经锁定的SA出口与下游VC；没有以当前VA组合方向代替已锁定SA方向。以下为固定源VC、全输入端口的请求周期统计：

| 窗口计数 | Mesh | Torus |
| --- | ---: | ---: |
| VA无合法空闲下游VC | 32580 | 130736 |
| 上项中仍有其他不合法VC空闲 | 0 | 130733 |
| VA有合法空闲VC但仲裁未获配 | 6137 | 5921 |
| SA因下游on_off关闭等待 | 0 | 0 |
| SA可发送但未获交换授权 | 124702 | 14368 |
| 物理FIFO满的VC周期 | 0 | 0 |

Torus VA等待中95.667%为无合法空闲VC；其中99.998%同时存在其他类别空闲VC。Torus等待的主要直接门槛是**包级合法VC资格/预约资源**，不是物理FIFO存满，也不是SA on_off抖动。在本窗口所有VA/SA等待请求周期中，无合法空闲VC占86.566%，Mesh为19.936%。这些是位置分类，不是各机制对包延迟的独立因果份额。

可用接入VC策略下结论相同：Torus VA等待95.199%因无合法空闲VC，99.991%的此类周期另有不合法空闲VC。可用源VC无法扩大网络内部的合法下游集合。

Torus有64186个“物理输出空闲且存在无合格VC请求”的端口周期，Mesh为3723。该统计是同时发生，不宣称每个空闲周期都仅由该请求造成；单跳测试提供了对应机制的直接对照。实际有向链路平均利用率Mesh49.842%、Torus22.796%，但不能单看此均值判定效率，因为Torus本来就需要更少跳、拥有更多链路。

### 4.1 不是每次预约都比Mesh更久

对网络出口的A(获配)/H(跨链路HEAD)/T(跨链路TAIL)/R(释放通知被采样)完整配对，按A在窗口内取样：

| 项目 | Mesh | Torus |
| --- | ---: | ---: |
| 预约样本 | 29896 | 17098 |
| 平均R−A | 13.694 | 10.785 |
| 最小R−A | 7 | 7 |
| 平均H−A | 1.288 | 1.002 |
| 平均R−T | 5.639 | 6.324 |

Torus平均预约寿命反而较短，不能误判为其所有预约本身特别慢。问题是可同时承载请求的合格资源少，且释放/重新获配的间隙无别的同类VC隐藏；Torus一旦获配通常下一周期就发HEAD，进一步排除主要耗时在获配后的首跳SA执行的解释。

数据见[阶段计数](bottleneck_analysis_20261104/stage_summary.csv)、[端口计数](bottleneck_analysis_20261104/port_summary.csv)、[预约寿命](bottleneck_analysis_20261104/reservation_summary.csv)。

## 5. 半带宽机制如何被放大为25倍总延迟

拓扑收益有限，排队积压则可随运行时间增长。0.12包×4flit对应名义0.48flit/节点/周期；在原固定源VC高负载点，Mesh窗口输出约0.478，Torus只有0.364。源持续生成，网络无法同速接纳，就会在源端积累等待。

从原逐包时间戳直接重建“已经出生但HEAD尚未注入”的包数：

| 周期 | Mesh源等待HEAD的包 | Torus源等待HEAD的包 |
| ---: | ---: | ---: |
| 1000 | 35 | 649 |
| 2000 | 13 | 1386 |
| 3000 | 23 | 2083 |
| 4000 | 4 | 2761 |

Torus在本次运行中持续积压，反观第4000周期HEAD已入网但未完成的包仅68个，Mesh为52个。巨大的等待量大多尚在网络外，不是几千个包同时挤在路由器FIFO里。

对应原样本均值：Mesh总延迟31.616=源排队7.590+入网后24.026；Torus800.932=770.843+30.089。原25倍是总延迟，不是每一跳逻辑慢25倍。固定源VC还会放大队首阻塞，但前轮同改可用VC后Torus614.187、Mesh27.413，已证明其不是完整解释。

排队增长依赖出生率、持续时间及初始积压，不能把800周期当作Torus的固定硬件延迟，也不能以此给出精确稳态饱和阈值。本次证据足以确认该点发生持续积压。[重建数据](bottleneck_analysis_20261104/backlog_summary.csv)逐时刻满足出生=源等待HEAD+HEAD已入未完成+完成的守恒。

## 6. 合理的后续设计方向，尚未修改RTL

首选是修正VC资源组织，而非直接删除dateline限制或贸然提前归还所有权。

候选：物理输入端口决定X/Y维度；4个VC按“跨线前两副本(VC0/1)、跨线后两副本(VC2/3)”组织，两维可复用编号，各方向仍保持独立FIFO。每跳允许从同阶段的两个副本中选；同维不从后阶段退回前阶段，X→Y重新初始化Y阶段，禁止Y→X。这样无需增加VC数量/存储，单跳同类流可有两个VC交替隐藏归还间隙。当前Mesh单跳实验已显示两VC足以隐藏本测试的4周期气泡，但不能据此预先保证整个Torus网络性能达到Mesh。

已用独立Python候选模型把同阶段所有副本选择的依赖并集合并，而非只挑一条有利路径；2..8全部49种尺寸/41209条源目的路径的物理输入VC依赖图无环。[模型结果](bottleneck_analysis_20261104/replicated_classes_model.json)。这是方案层面的可行性证据，不是候选RTL已实现、性能已通过或完整形式化证明。沿用独立FIFO、包级独占、终端最终服务等假设。

若后续实施，必须同时修改RC类别解码与非法状态检查、逐包mask、相关断言和依赖模型，不可只放宽掩码却仍保留旧`vc_id==VC_X_AFTER`的解码。应先保留当前TAIL读出归还规则，验证新资源组织和包内锁定，再做原矩阵、多种子、高压/长包/背压、全尺寸及公平性回归；只有证据指向归还协议还不足时再单独研究提前接入和metadata背压。

## 7. 复现、交付与边界

新增文件：

- `testbench/tb_torus_bottleneck_profile.sv`、`scripts/simulation/run_tb_torus_bottleneck_profile.sh`：只读观测，无DUT驱动策略改动。
- `testbench/tb_torus_singlehop_service.sv`、`scripts/simulation/run_tb_torus_singlehop_service.sh`：独立饱和单跳微基准。
- `scripts/simulation/analyze_torus_bottleneck.py`、`analyze_torus_resource_reachability.py`、`check_torus_replicated_classes_model.py`：证据审计、静态资源穷举与候选模型。
- 本报告及`docs/bottleneck_analysis_20261104/`便携数据、短事件轨迹、4份编译源码指纹；同步根及子项目进度文档。

```bash
bash torus/scripts/simulation/run_tb_torus_bottleneck_profile.sh sharedmesh
bash torus/scripts/simulation/run_tb_torus_bottleneck_profile.sh torus
bash torus/scripts/simulation/run_tb_torus_singlehop_service.sh sharedmesh
bash torus/scripts/simulation/run_tb_torus_singlehop_service.sh torus
python3 torus/scripts/simulation/analyze_torus_resource_reachability.py torus/docs/bottleneck_analysis_20261104
python3 torus/scripts/simulation/check_torus_replicated_classes_model.py torus/docs/bottleneck_analysis_20261104/replicated_classes_model.json
python3 torus/scripts/simulation/analyze_torus_bottleneck.py \
  torus/vivado_sim_wsl/tb_torus_bottleneck_profile_sim/run_sharedmesh_Dq6nIn6u \
  torus/vivado_sim_wsl/tb_torus_bottleneck_profile_sim/run_torus_d03AnazR \
  torus/vivado_sim_wsl/tb_torus_conditions_control_sim/run_sharedmesh_cuqJfWCx \
  torus/vivado_sim_wsl/tb_torus_conditions_control_sim/run_torus_5O9fsxpc \
  torus/vivado_sim_wsl/tb_torus_singlehop_service_sim/run_sharedmesh_VCsRdyH8 \
  torus/vivado_sim_wsl/tb_torus_singlehop_service_sim/run_torus_3N3I1lUQ \
  torus/docs/bottleneck_analysis_20261104
```

WSL Vivado2025.2沙箱外新运行通过。上述profile的每个policy0/1保存xsim.log、原4类数据、vc_profile/port_profile/events.csv；singlehop的每个length4/16保存xsim.log与逐周期events.csv。编译/展开日志及源码SHA在各run根目录。

[自动审计](bottleneck_analysis_20261104/audit.txt)检查：四组观测精确复现；每个输入VC的VA/SA分类和每个输出的传输计数守恒；所有网络预约/HEAD/TAIL/归还完整配对且无残留；四组单跳每次HEAD间隔均核对；编译源码SHA与当前文件一致。脚本语法、Python编译、文档链接及差异格式检查通过。仿真无功能失败，保留既有跨generate接口/环境警告。

本轮动态观测限一个高负载种子/窗口，单跳仅4/16flit、单源、非跨界、always-ready；不能将单跳公式当作全网吞吐定律。候选模型未转成RTL，未运行候选性能仿真。本轮没有修改任何RTL、没有综合/板级验证、未提交/推送或同步Windows。

## 后续：VC 数量以外的限制

[非VC数量限制分析](nonvc_limits_20261104.md)新增同状态最大匹配审计，Torus当前SA/VA已达99.748%/99.766%，低负载时延接近RTL无竞争下界。区分包级归还、逐跳启动、源HOL与尚未证实的路径/流控问题，避免把任意仲裁等待都当作低效空转或已量化的优化收益。

<!-- Modify by Michael Tan，20261104: link quantified scheduler and pipeline-bound follow-up. -->
