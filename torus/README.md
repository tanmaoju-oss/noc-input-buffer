# Torus NoC 子项目

基于 `noc-input-buffer` 的 NoC 设计，独立开展二维 Torus（环面）拓扑改造与验证。

<!-- Modify by Michael Tan，20261021: initialize Torus subproject structure and progress record. -->

## 目录结构

```text
torus/
├── README.md                   # 子项目说明与持续进度
├── docs/                       # 设计分析与基线校验清单
├── src/                        # Torus RTL 及主项目 RTL 的独立副本
├── testbench/                  # 独立 SystemVerilog 测试平台
├── constraints/                # 板级约束及说明
├── scripts/
│   ├── simulation/             # 编译、仿真、扫描与绘图入口
│   └── synthesis/              # Windows Vivado 综合/实现入口
├── vivado_sim_wsl/             # WSL/Linux 仿真结果
├── vivado_sim_windows/         # Windows 仿真结果
└── vivado_synthesis_windows/   # Windows 综合/实现结果
```

## 工作边界与规范

- 开始工作前读取根目录 `../AGENTS.md` 和本文件，遵守主项目代码标注、工具环境和验证规则。
- RTL 仅在本子项目 `src/` 中修改；主项目 `../src/`、CHI 和 Verilator 工作区保持独立。不得自动向主线回写。
- 导入 Mesh 基线时记录源路径、Git 提交与工作区修改情况，核对副本一致性；不将原有 Mesh 的通过记录视为 Torus 验证结果。
- Torus 方案须明确边界环绕链路、目的地址与路由规则、VC/流控及死锁规避机制；首版规则与支持范围见 [设计分析的实施状态](docs/torus_design_analysis.md)。
- 每个新仿真功能配套独立 `testbench/<top>.sv`、`scripts/simulation/run_<top>.sh`（或 `.ps1`）及 `vivado_sim_<平台>/<top>_sim/`，脚本必须解析到 `torus/` 内的源文件和结果目录。
- 使用 WSL/Linux Vivado 2025.2 做编译与仿真；目标器件综合/实现遵循主项目 Windows Vivado 2019.2 规则，器件完整名称为 `xcvu440-flga2892-2-e`。实际板卡确认前不新增 XDC。
- 每次工作更新本文件的修改文件、命令、结果路径及结论；影响主线的阶段性结论同步根目录 `README.md` 和 `AGENTS.md`。

## 逐次修改记录

每次修改均在 [docs/修改记录.md](docs/修改记录.md) 追加独立条目。开始时记录目的和范围，完成后补齐涉及文件、具体改动、验证命令、测试结果及日志路径、遗留问题，以及 Git 提交、推送和 Windows 同步状态。未执行的检查须明确标为未执行；保留失败及后续修复的记录。本 README 继续维护阶段进度与待办。

<!-- Modify by Michael Tan，20261102: add the mandatory per-change log entry point. -->

首版具体方案见 [实现方案详解](docs/torus_implementation_20261102.md)，原始改造分析与实测结果分别保留在设计分析和验证报告中。

## 当前状态（2026-11-04）

当前采用输入端口区分维度、跨dateline前后两阶段多副本VC；默认4VC，支持编译选择8/16VC。原全局X前/X后/Y前/Y后单VC方案保留在历史提交。本轮50点性能及25项新功能验证通过，默认4VC高负载平均21.512周期，独立Mesh4为31.616、旧Torus4为800.932；详见 [改造与验证报告](docs/phase_vc_verification_20261104.md)。未综合或板级验证。

<!-- Modify by Michael Tan，20261102: expose current implementation and verification status. -->

## 当前进度

### 2026-10-21：建立子项目

- 已创建上述目录，以 `.gitkeep` 保留空目录；根目录 `README.md`、`AGENTS.md` 已增加入口和隔离边界。
- 当前仅完成目录与文档初始化，`src/` 尚无 RTL，未开展 Torus 拓扑实现、编译、仿真或综合。
- 本次核查：检查目录完整性及文档链接；无仿真命令或功能验证结果。

### 2026-10-21：导入主项目 Mesh 基线并完成改造分析

- 完整复制根目录 `src/` 的 25 个文件至 `torus/src/`，包含板级 RTL；逐文件字节核对一致，未增加代码注释以保持原始副本。
- 来源 HEAD：`bf1ae956bb9ebb2075a04d3d47a377ea0bb130a1`；复制时源 `src/` 无未提交改动。SHA256 与相对路径记录在 [基线清单](docs/mesh_baseline_sha256.txt)。
- [Torus 改造分析](docs/torus_design_analysis.md) 记录连接规则、最短路径 XY 路由、拟采用的 dateline/4VC 分类、逐包 metadata 和 VA 改造、模块清单及验证步骤。
- 当前 `torus/src/` 仍为原 Mesh 逻辑，尚未实施 Torus 改造；未编译、仿真或综合。前一节的“src 尚无 RTL”为建立时状态，已由本节更新。
- 本次检查命令：`diff -qr src torus/src --exclude=.gitkeep`、`git diff --check`；结果应无差异/格式错误。详细分析为静态结论，不能视为 Torus 功能验证。

<!-- Modify by Michael Tan，20261021: record completed source import and Torus analysis. -->

## 后续工作与文件清单（2026-10-21）

以下为原计划及首版更新状态，路径相对 `torus/`；具体设计依据见 [改造分析](docs/torus_design_analysis.md)，实际覆盖与结果以验证报告为准。

### 1. 固定方案并建立基线

- [x] 更新 `docs/torus_design_analysis.md`：确定尺寸范围、等距方向、非法地址处理、注入/弹出规则和 VC 类别状态表。
- [x] 新建 `scripts/simulation/check_torus_channel_dependencies.py`：枚举带 VC 的通道依赖并检查有向环，输出到 `vivado_sim_wsl/torus_channel_dependencies/`；明确模型假设，覆盖实际缓冲共享语义。
- [x] 新建 `testbench/tb_torus_mesh_baseline.sv` 和 `scripts/simulation/run_tb_torus_mesh_baseline.sh`：只使用子项目源码复现 Mesh 自检，结果存入 `vivado_sim_wsl/tb_torus_mesh_baseline_sim/`。
- [x] 在共享 router/RC/VA 修改前完成基线，并保存日志及源码版本。后续即使保留 `mesh.sv`，其共享内部模块变化后也不能视为原始 Mesh 对照；性能对照使用主项目基线的独立编译结果。

### 2. 实现拓扑、路由及 VC 约束

| 状态 | 文件 | 待修改内容 |
| --- | --- | --- |
| 已实现 | `src/torus.sv` | 基于 `src/mesh.sv` 建立 Torus 顶层；保留内部链路，补齐左右、上下边界双向连接和反向流控，传递实际尺寸。 |
| 已实现 | `src/noc.sv` | 定义 VC 类别及相关类型，检查网络尺寸与坐标位宽，首版保持 flit 格式。 |
| 已实现 | `src/rc_unit_Xiugai2.sv` | 实现环形最短距离 XY、固定等距规则、跨界识别与下一跳类别，补全组合默认赋值。 |
| 已实现 | `src/router.sv` | 传递实际网络尺寸，衔接新增 VC 资格接口。 |
| 已实现 | `src/input_block_Xiugai2.sv` | 向每个输入端口传尺寸和端口编号，汇总逐 VC 的合法分配信息。 |
| 已实现 | `src/input_port_Xiugai2.sv` | 利用输入端口、输入 VC 和目标方向计算包头资格，与输出端口一起送入缓冲。 |
| 已实现 | `src/input_buffer_src_circular_full.sv` | metadata FIFO 按包保存合法 VC 类别/掩码，输出队首资格，保持 BODY/TAIL 的路径与下游 VC 锁定。 |
| 已实现 | `src/input_block2vc_allocator.sv` | 增加逐端口、逐 VC 的合法下游 VC 掩码，更新两个 modport。 |
| 已实现 | `src/vc_allocator.sv` | 请求条件和实际 VC 选择均过滤合法掩码，无合法空闲 VC 时等待，维持释放时序。 |

上述改动已作为同一组接口变更实现。每处修改按主项目规则添加 `Modify`、Michael Tan 和实际日期标注；不得只完成连接就宣布 Torus 验证通过。

### 3. 新建独立验证文件

| 状态 | TB 文件 | 对应入口及结果目录 | 核查重点 |
| --- | --- | --- | --- |
| 已通过首版自检 | `testbench/tb_torus_rc.sv` | `scripts/simulation/run_tb_torus_rc.sh`；`vivado_sim_wsl/tb_torus_rc_sim/` | 全源目的路由、奇偶尺寸、等距选择、跨界和 VC 类别转换。 |
| 已通过首版自检 | `testbench/tb_torus_vc_allocator.sv` | `scripts/simulation/run_tb_torus_vc_allocator.sh`；`vivado_sim_wsl/tb_torus_vc_allocator_sim/` | 合法掩码、仅非法 VC 空闲、竞争、释放和重新分配。 |
| 已通过首版自检 | `testbench/tb_torus_integration.sv` | `scripts/simulation/run_tb_torus_integration.sh`；`vivado_sim_wsl/tb_torus_integration_sim/` | 四方向及双维环绕、全源目的、多 flit/HEADTAIL、多包 metadata、背压和复位。 |
| 已通过首版自检 | `testbench/tb_torus_congestion.sv` | `scripts/simulation/run_tb_torus_congestion.sh`；`vivado_sim_wsl/tb_torus_congestion_sim/` | 环形对抗流量、持续拥塞、VC 资格断言、停注入后排空。 |

验收要求：无丢包、重复、错目的或包内乱序，`error_o=0`，TAIL 后资源正确释放；通过日志和结果文件确认，不仅查看控制台。拥塞仿真与依赖图检查共同提供证据，有限仿真不等于形式化无死锁证明。

### 4. 功能通过后的工作

- [x] 新建 `testbench/tb_torus_performance.sv`、`scripts/simulation/run_tb_torus_performance.sh`，结果写入 `vivado_sim_wsl/tb_torus_performance_sim/`；与独立 Mesh 基线按相同尺寸、流量、种子和统计窗口比较延迟/吞吐，并说明 VC 划分差异。
- [ ] 板级任务开展时再修改 `src/board_ila/noc_board_ila_top.sv`，将实例切换到 Torus；届时单独确定板级 TB、Windows runner 和结果路径。
- [ ] 当前预计复用 `src/router_link.sv`、`src/router2router.sv`、`src/node_link.sv`、`src/crossbar.sv`、`src/circular_buffer_Xiugai3.sv`、`src/round_robin_arbiter.sv`、`src/separable_input_first_allocator.sv`、`src/switch_allocator_Xiugai1.sv` 及其相关接口，回归失败时再据证据调整。
- [x] 每阶段更新本 README 的实际修改文件、运行命令、结果路径和结论；关键阶段结论同步根目录 `README.md` 与 `AGENTS.md`。

<!-- Modify by Michael Tan，20261021: record actionable Torus file-level implementation and verification checklist. -->

### 2026-10-23：克隆外部 Torus 参考仓库

- 在 `docs/reference_repositories/Torus-Systolic-array-HDL/` 完整克隆上游，保留独立 Git 历史，提交为 `6284e28ebdca0d22c15b27639616e6dfae719eaa`；克隆后工作区干净。
- 来源、克隆命令及初步适用范围见 [参考仓库说明](docs/reference_repositories/README.md)。它是矩阵乘法脉动阵列，可参考边界回接；尚未完成 NoC 可借鉴性详细分析。
- 未修改主项目或 Torus RTL，未运行编译、仿真或综合。

<!-- Modify by Michael Tan，20261023: record isolated upstream Torus reference clone. -->

### 2026-11-02：建立 Torus 独立 Mesh 基线（完成）

已新增独立 `torus/testbench/tb_torus_mesh_baseline.sv` 和 `torus/scripts/simulation/run_tb_torus_mesh_baseline.sh`。命令 `bash torus/scripts/simulation/run_tb_torus_mesh_baseline.sh` 在 WSL Vivado 2025.2 沙箱外通过，日志 `torus/vivado_sim_wsl/tb_torus_mesh_baseline_sim/run_uQSII0Om/xsim.log` 报告 `[TB_TORUS_MESH_BASELINE] PASSED`：2×3 网络 `(0,0) → (1,2)` 两个 flit，目的、顺序、负载及错误信号检查通过。仅为单包基本传输证据；未验证全源目的、拥塞或 Torus。25 个 RTL 的导入 SHA256 复核一致。下一步固定 dateline VC 状态表和通道依赖模型。

<!-- Modify by Michael Tan，20261102: start isolated Torus Mesh baseline verification. -->


### 2026-11-02：Torus 首版实现与调试（通过首轮验证）

首版已实现双向环绕、最短路径 XY、dateline 四类 VC、逐包 metadata 合法掩码及 VA 过滤；仅修改 `torus/`。WSL Vivado 2025.2 新验证通过：RC 261120 次检查、VA/metadata 定向、5×5/4×4/2×3/2×2 集成（950/464/114/68 包）、5×5 持续拥塞与复位后重传（625 包），均完整收发且最终 FIFO/VC 资源释放；Mesh 模式基本回归通过。依赖模型 49 种尺寸/41209 路径无环；不等于完整 RTL 形式化证明。命令、源码指纹、日志路径、失败及边界见 [验证报告](docs/torus_verification_20261102.md) 和 [修改记录](docs/修改记录.md)。未运行综合或板级验证。

实现提交 `6d778dadbee4191e501fcf802621ede374275fae` 已推送至 `origin/chore/reorganize-project-layout`。Windows `E:\Codex-Project\NoC-XY` 已 fetch，但 `git pull --ff-only` 被既有 AGENTS/README、板级脚本/RTL 修改及未跟踪 congestion 等文件阻挡，HEAD 保持 `cdcc7a9d80226b314da695ee2d2e1af6f6d18e41`；未覆盖、丢弃或 stash 既有工作。Windows 工作树同步尚未完成。

<!-- Modify by Michael Tan，20261102: start first Torus routing, VC and topology implementation. -->

## 2026-11-04：Torus 与独立 Mesh 性能验证启动

建立独立 tb_torus_performance 及 WSL 入口，Mesh 单独编译根 src、Torus 编译 torus/src；相同尺寸、预生成流量、种子、出生窗口、四 flit 包和接收端条件。检查逐包目的/顺序/负载、完整排空及资源释放，比较含源排队延迟、入网后延迟、窗口吞吐和跳数。正式 RTL 不改，不运行综合。实际结果与命令完成后补齐至 torus/docs/performance_comparison_20261104.md。

<!-- Modify by Michael Tan，20261104: start isolated matched-traffic Mesh/Torus performance verification. -->

### 2026-11-04：Mesh/Torus 同条件验证完成

新增独立tb_torus_performance、WSL入口及分析脚本，Mesh独立编译根src，Torus编译子项目src，未改RTL。WSL Vivado2025.2沙箱外20组全部PASS，每侧61386包/245544flit完整收发、10对轨迹一致，最终FIFO/metadata/VC释放及物理跳数通过。均匀0.01下Torus均延迟降低约10%～11%；0.08下增加80%～109%；0.12下Mesh约32周期、Torus768～801周期，窗口输出分别约0.477～0.478/0.364～0.369 flit/节点/周期。高负载Torus主要延迟落在源排队，具体内部因果未定位，不宣称全负载优于Mesh或已测稳态饱和点。

命令`bash torus/scripts/simulation/run_tb_torus_performance.sh mesh`及`... torus`；通过目录为`torus/vivado_sim_wsl/tb_torus_performance_sim/run_mesh_JqyjmuA2/`、`run_torus_nfsUpoFJ/`，每组保留trace、逐包时间戳、summary、日志与源SHA。完整数据、分析命令和边界见 [比较报告](docs/performance_comparison_20261104.md)。未综合、未提交/推送或同步Windows。

<!-- Modify by Michael Tan，20261104: record fresh paired performance results including adverse Torus high-load behavior. -->

## 2026-11-04：性能比较测试条件复核启动

用户要求检查巨大差距的测试变量。新增独立conditions_control TB/入口：原Mesh、Torus副本Mesh模式、Torus各在固定接入VC/可用VC选择下运行0.12种子1同轨迹。固定模式须精确复现既有结果；只改变源HEAD选VC，BODY/TAIL锁定。增加源HEAD所有权/on_off及BODY阻塞观测；不改RTL。结果完成后记录条件复核报告。

<!-- Modify by Michael Tan，20261104: audit comparison variables using independent shared-Mesh and source-VC controls. -->

### 2026-11-04：性能测试变量复核完成

新增独立conditions_control TB/入口/分析及报告，0.12种子1六组各11889包全PASS，三组固定VC精确复现原trace/summary/逐包时间戳；副本Mesh两模式均与原Mesh完全一致。两侧同改可用接入VC后Mesh31.616→27.413、Torus800.932→614.187，固定VC放大退化但不能解释全部差距。外部参数/流量/窗口一致，实际可选下游VC不同（Mesh4个、Torus通常1个）；原25倍是含源排队总延迟，原入网后仅30.089/24.026。不可将差距单独归因拓扑或直接认定某个RTL模块主因。

通过目录`torus/vivado_sim_wsl/tb_torus_conditions_control_sim/run_mesh_00h1FbnU/`、`run_sharedmesh_cuqJfWCx/`、`run_torus_5O9fsxpc/`；命令`bash torus/scripts/simulation/run_tb_torus_conditions_control.sh mesh|sharedmesh|torus`。完整数据/口径见 [条件复核报告](docs/test_conditions_audit_20261104.md)。未改RTL、未综合、未提交/推送或同步Windows。

<!-- Modify by Michael Tan，20261104: record exact shared-Mesh controls and quantified source-VC sensitivity without over-attributing the remaining gap. -->

## 2026-11-04：Torus 高负载退化逐跳诊断启动

用户要求从理论和实际设计仔细分析。保持RTL不改，新增独立逐跳观测TB：同0.12种子1固定/可用源VC，统计合法VC耗尽与VA仲裁、SA流控/仲裁、FIFO存量、各端口服务和预约寿命；固定策略必须精确复现既有数据。另建饱和单跳微基准，剥离全网竞争与绕行，检查4flit包和单合格VC的释放/重分配间隙。开始前登记，结果后补齐。

<!-- Modify by Michael Tan，20261104: begin nonintrusive hop-level Torus bottleneck diagnosis and isolated single-hop timing checks. -->

### 2026-11-04：Torus 退化结构瓶颈确认

独立逐跳观测4组精确复现既有trace/packets/summary/stalls，另4组饱和单跳全PASS（本轮共48580包/200464flit）。相同非跨界一跳、无其他竞争、always-ready、可用源VC下，4flit Mesh HEAD间隔4/吞吐1，Torus间隔8/吞吐0.5；16flit Torus间隔20/吞吐0.8，证实单合格VC与TAIL读出归还组合产生固定4周期包间气泡。全网Torus VA等待95.667%因无合法空闲VC，其中99.998%仍有其他类空闲；SA on_off和物理FIFO满均0。5×5全路径网络VC可达120/400（80条链路仅1类、20条2类），源待入网包1000→4000周期649→2761，解释有限服务下降放大为源排队总延迟。

未改RTL。提出按输入端口区分维度、每dateline阶段2副本的候选资源组织；仅模型49尺寸/41209路径无环，不宣称RTL/性能已通过。命令、日志、全数据及边界见 [逐跳机制报告](docs/bottleneck_analysis_20261104.md)。profile通过run_sharedmesh_Dq6nIn6u/run_torus_d03AnazR，singlehop通过run_sharedmesh_VCsRdyH8/run_torus_3N3I1lUQ，各在torus/vivado_sim_wsl对应top结果目录。未综合、未提交/推送或Windows同步。

<!-- Modify by Michael Tan，20261104: record verified VC-class recycle bubbles, unreachable resources and queue buildup; retain RTL unchanged. -->

## 2026-11-04：VC 之外的性能限制复核启动

用户要求继续定位VC外的性能差距。保持RTL不改，新增独立scheduler_profile TB/runner，在同一0.12种子1固定/可用源VC条件下，逐周期比较实际SA/VA授权与相同请求图最大匹配，统计两级选择落空与已分配但暂缺flit的周期。精确复现原流量/时间戳作为观测无扰动验收；结合已有包级预约、源队首、路径需求和低负载时序评估，不把请求等待直接当作可消除延迟。

<!-- Modify by Michael Tan，20261104: audit scheduler efficiency and non-VC-count limitations without changing RTL. -->

### 2026-11-04：VC 之外性能限制复核完成

新增scheduler_profile独立TB/runner/分析，4组共47556包/190224flit全PASS，六类原观测文件精确复现。相同候选图/物理输入输出约束下，Torus固定策略SA实际/最大匹配99.748%、VA99.766%，当前仲裁损失不是巨大退化的主要证据；Mesh SA94.548%。包级TAIL读出归还、每跳约2周期启动、单源游标/HOL仍是数量外的协议与结构限制；FIFO满/on_off本点为0，不应归因。低负载Torus无竞争下界10.947/实测在网11.441，严重差距发生高载积压，不是所有负载离RTL下界很远。

报告 [非VC数量限制分析](docs/nonvc_limits_20261104.md)区分理想均匀流体容量上界Mesh0.8/Torus1.0与可达性能，不能当已测饱和点。命令`bash torus/scripts/simulation/run_tb_torus_scheduler_profile.sh sharedmesh|torus`；日志在对应top_sim的run_sharedmesh_40Npc0M2/run_torus_srg3rBbH。未扩VC/改RTL，未综合、未提交/推送或同步Windows。

<!-- Modify by Michael Tan，20261104: quantify scheduler headroom and distinguish protocol, injection and theoretical bounds from VC count. -->

## 2026-11-04：分阶段多副本 VC 实现与验证启动

用户授权开始修改。仅改torus/src的noc、RC和拓扑参数检查：输入端口区分维度，4/8/16 VC按跨线前后两阶段等分，LOCAL注入/弹出保持4个逻辑VC；保留全部归还、仲裁、FIFO和源队列协议。4VC为同物理数量对照，8VC每阶段4个候选，与Mesh每跳4个候选对照，并披露硬件增加。新增独立phase RC/VA/集成/拥塞/单跳/性能TB与入口，原方案固定3c31c2b作为legacy控制，原始Mesh根src不改。按顺序做依赖模型、功能及原10点流量矩阵，失败保留；验证后提交/推送并按规则尝试Windows同步，不覆盖既有修改。

<!-- Modify by Michael Tan，20261104: start authorized phase-replicated VC implementation with controlled endpoint resources and verification. -->

### 2026-11-04：阶段副本VC完成首轮改造验证

仅改noc/RC/torus参数检查3个RTL，默认4VC按2+2阶段划分，8/16为4+4/8+8；保留4个逻辑端点VC、归还/仲裁/流控。50性能点与25项新功能PASS，旧控制精确复现。默认4VC已消除单跳4周期气泡，0.12种子1均延迟21.512、8VC19.271、16VC19.293，Mesh31.616、旧版800.932。完整命令/日志/资源成本/限制见 [验证报告](docs/phase_vc_verification_20261104.md)。原默认入口的分类断言随协议维护，Git及Windows交付状态随后记录。

<!-- Modify by Michael Tan，20261104: expose implemented phase VC pools and measured default/expanded results. -->

### 2026-11-04：阶段VC改造 Git 交付与 Windows 状态

实现及验证提交`a837e1ac81ab449212b551a2082c580fe869a5cc`已推送`origin/chore/reorganize-project-layout`。Windows fetch成功，pull --ff-only因既有AGENTS/README、板级RTL/脚本修改及未跟踪congestion/综合文件保护性中止；Windows HEAD仍为`cdcc7a9d80226b314da695ee2d2e1af6f6d18e41`。未覆盖、删除或stash既有工作。Linux既有根文档修改也保留，本轮只暂存新增进度记录。默认4VC新方案与完整资源对照见阶段VC验证报告，Windows工作树同步尚未完成。

<!-- Modify by Michael Tan，20261104: record pushed phase-VC delivery and protected Windows synchronization blocker. -->
