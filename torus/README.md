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

## 当前状态（2026-11-02）

已实现真正的 Torus 环绕连接、最短路径 XY、dateline 四类 VC 和逐包合法掩码；详细测试证据见 [首版验证报告](docs/torus_verification_20261102.md)。历史初始化/导入记录保留，以下较早的“尚未实现”不代表当前状态。未开展综合、板级验证或性能比较。

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

- [ ] 新建 `testbench/tb_torus_performance.sv`、`scripts/simulation/run_tb_torus_performance.sh`，结果写入 `vivado_sim_wsl/tb_torus_performance_sim/`；与独立 Mesh 基线按相同尺寸、流量、种子和统计窗口比较延迟/吞吐，并说明 VC 划分差异。
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
