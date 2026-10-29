# Congestion 拥塞感知功能验证子项目

<!-- Modify by Michael Tan，20261027: document received congestion baseline and verification boundary. -->

用于接收同事修改的拥塞感知 NoC 系统，独立验证其功能正确性。

## 目录结构

```text
congestion/
├── README.md
├── src/                       # 接收的设计 RTL
├── testbench/                 # 接收的 tb，统一按项目规范存放
├── docs/                      # Excel 交付资料与导入校验清单
├── constraints/               # 约束预留，未新增 XDC
├── scripts/
│   ├── simulation/            # 后续编译、自检及分析入口
│   └── synthesis/             # 后续 Windows 综合入口
├── vivado_sim_wsl/            # WSL 仿真结果
├── vivado_sim_windows/        # Windows 仿真结果
└── vivado_synthesis_windows/  # Windows 综合结果
```

## 工作边界

- 遵循根目录 AGENTS.md；RTL、TB、脚本和生成结果均维护在 congestion/，不修改或自动回写根目录 src/、Torus、CHI 或 Verilator 子项目。
- 导入时接收文件逐字节保留；2026-10-28 经用户授权将 GB2312 注释无损转为 UTF-8，保持代码、文字、换行及文件名不变，详见转换清单；Windows 原交付保持不变。
- 后续源码修复需记录原因、修改文件并添加规定的 Modify 标注；导入副本的原始哈希记录在 docs/import_manifest.tsv。
- 功能验证使用 WSL/Linux Vivado 2025.2；如后续明确开展综合，使用 Windows Vivado 2019.2，目标器件 xcvu440-flga2892-2-e。
- 每个新验证功能配套独立 testbench/<top>.sv、scripts/simulation/run_<top>.sh 和 vivado_sim_wsl/<top>_sim/；不得混编主项目同名模块。
- 持续更新本文件的命令、结果路径及验证结论，关键进展同步根目录 README.md 和 AGENTS.md。

## 2026-10-27：目录建立与交付导入

来源：E:\Codex-Project\NoC-XY\congestion（WSL 路径 /mnt/e/Codex-Project/NoC-XY/congestion）。

导入映射：

- src/ → congestion/src/：22 个 SystemVerilog 设计文件。
- tb/ → congestion/testbench/：1 个测试平台 tb_mesh_injection_1.1.sv，声明的顶层为 tb_mesh。
- 测试结果5.1.xlsx → congestion/docs/测试结果5.1.xlsx。

共 24 个文件复制并逐文件字节比对一致，SHA256 及源目标映射见 [导入清单](docs/import_manifest.tsv)。复制使用 Python shutil.copy2，核对使用 read_bytes 和 hashlib.sha256；未生成仿真结果。

当前只完成资料导入，未修改 RTL/TB，未编译、仿真或综合。Excel 属于收到的历史资料，尚未核查其测试条件与结果，不能视为本环境功能验证证据。

## 后续验证顺序

1. 静态检查拥塞采集、拥塞决策、路由选择和接口，确认算法参数、编译依赖及测试平台自检能力。
2. 适配独立 WSL 编译/仿真入口，先复现接收基线，明确随机种子、流量、统计窗口及超时条件。
3. 针对拥塞信息采集、聚合、传播及路由决策建立自检，覆盖背压、竞争、复位、边界和拥塞恢复。
4. 检查无丢包、重复、错目的、包内乱序及资源泄漏；停注入后应完全排空。结果通过日志和计分板确认，再与历史表格对照。

## 2026-10-28：代码静态分析完成

已分析 22 个 RTL 与原始 TB，报告见 [代码分析](docs/congestion_code_analysis.md)。确认全局组合占用量采集与 HEAD 入队时选路；重点风险为 VC 未满即重新可分配、TB 静态局部初始化、ThreeAware 无 OE/逃逸约束，以及停注入未排空和缺失包自检。24 个导入文件 SHA256 复核一致，未修改 RTL/TB，未编译、仿真或综合；后续先做定向自检再评价性能。

<!-- Modify by Michael Tan，20261028: record completed static analysis and unresolved verification risks. -->

## 2026-10-28：接收源码注释编码统一为 UTF-8

将 10 个 RTL 与 1 个 TB 从 GB2312 无损转为 UTF-8（无 BOM），其余 12 个 ASCII/UTF-8 RTL 保持原字节。非 ASCII 字符全部位于注释；逐文件验证 UTF-8 解码后转回 GB2312 与转换前原字节完全一致，剔除注释后的代码字节完全一致，并保留 CRLF/LF、文件末尾换行及全部注释文字。不添加或修改 RTL/TB 逻辑、代码标注，未编译、仿真或综合。

原始 `docs/import_manifest.tsv` 保留导入时哈希，不更新为转换后值；当前编码转换记录和前后 SHA256 见 [转换清单](docs/utf8_conversion_manifest.tsv)。此前“接收文件保持原字节”的记录为转换前状态；目前文件内容无损、字节因编码转换而变化。Excel 未修改。

<!-- Modify by Michael Tan，20261028: record lossless GB2312-to-UTF-8 comment conversion without code changes. -->

## 2026-10-28：Congestion 缓冲逻辑修复与 26-bit flit 适配（启动记录，缩减已暂缓）

用户要求将 flit 恢复为 26 bit，并将 input_buffer 的 VC 释放与 circular_buffer 流控阈值恢复到主项目。先独立修改两处缓冲逻辑，保留原行并下一行添加 Modify 说明；26-bit 格式对现有源坐标、12-bit packet ID 和 13×13 目的地址存在容量约束，待用户确定字段处理后继续。所有功能修改和后续验证限于 congestion/；根 src/ 不变。尚未验证，不宣称修复完成。

<!-- Modify by Michael Tan，20261028: begin authorized congestion buffer fixes and narrow-flit adaptation. -->

## 2026-10-28：Congestion 分层自检启动，暂时保留接收 flit 格式

用户决定暂时沿用接收的宽 flit，后续再评估；当前实际 FLIT_DATA_SIZE=254、完整 flit_t=258 bit，HEAD_PAYLOAD_SIZE=218，不执行此前讨论的 26-bit 缩减。已完成的两处缓冲逻辑修改待验证。新增独立容量/释放、状态采集、路由和全网包级自检及配套 WSL 入口；仅使用 congestion/src，检查错误、内容、目的、顺序、背压及完全排空。ThreeAware 保留预留算法身份，仿真不等同于无死锁证明；原始 TB 保留不改。根 src 不变，不运行综合。

<!-- Modify by Michael Tan，20261028: start congestion self-checks and retain received wide flit temporarily. -->

## 2026-10-28：Congestion 第一轮自检结果

暂时保留接收格式：完整 flit_t=258 bit（数据 254、payload 218），以后再评估。两处缓冲修复按原行注释+下一行 Modify 标注：input_buffer 包尾释放、circular_buffer 阈值 2。新增 4 个独立 TB 与 WSL 配套入口；容量 64 组及满后拒写、采集 54756 项通过。13×13 XY/OneAware/TwoAware 各三种流量、每阶段 1014 包/4732 flit，合计 9126 包/42588 flit 通过内容/目的/顺序/背压/释放/完全排空自检。

路由独立参考检查发现 TwoAware 东向 X 距离=1 的代价分支遗漏，三种指标/聚合配置分别 270/236/48 次不符；例 (0,0)→(1,1) X成本3、Y成本42却选SOUTH。未改该算法，保留失败证据；ThreeAware 无死锁保证。命令、源码范围、所有新日志路径和限制见 [验证报告](docs/verification_20261028.md)。本轮沙箱外 WSL Vivado 2025.2，根 src 不变，未综合。不能宣称整套 congestion 功能全部通过。

<!-- Modify by Michael Tan，20261028: record verified congestion fixes and newly reproduced TwoAware defect. -->

### 2026-10-28：Congestion Git 交付与 Windows 同步状态

提交 `3a18a77`（Verify congestion buffers and expose TwoAware route-cost defect）已推送至 origin/chore/reorganize-project-layout，范围仅 congestion 源码、TB、脚本、导入/编码清单与验证报告；根 src 未改。Windows `E:\Codex-Project\NoC-XY` 已 fetch 到该提交，但 `git pull --ff-only origin chore/reorganize-project-layout` 因已有 AGENTS/README、板级 RTL/脚本修改及未跟踪 congestion 文件而中止，Windows HEAD 保持 `cdcc7a9`。未覆盖、stash 或清理既有文件；原交付仍保留。后续需用户处理 Windows 既有工作后再同步，不能宣称两端提交一致。

<!-- Modify by Michael Tan，20261028: record congestion pushed commit and protected Windows synchronization block. -->

## 2026-10-28：TwoAware 东向最后一跳修复启动

用户授权修复 TwoAware 东向 X 距离=1 的两跳代价遗漏并重新测试。仅在 congestion/src/congestion_decision.sv 的东北/东南分支补充 g/h 场景，保留既有分支并添加 Modify 标注；不改 OE 候选限制、聚合函数、位宽或根 src。复用原失败路由自检，扩展到全部 3×3 指标/聚合组合，并重新执行 13×13 TwoAware 包级回归。ThreeAware 按用户说明为未完成预留功能，不纳入本次验收。

<!-- Modify by Michael Tan，20261028: start authorized TwoAware last-X-hop fix and regression. -->

## 2026-10-28：TwoAware 东向最后一跳修复通过

仅 congestion/src/congestion_decision.sv 增加东北/东南 X距离=1 的 g/h 代价分支，34行纯新增，原代码保留，带 Modify 标注。命令 `bash congestion/scripts/simulation/run_tb_congestion_routing.sh -generic_top REFERENCE=<0|1|2> -generic_top AGG=<0|1|2>` 覆盖全部9组，TwoAware 2214576项零错误，原270/236/48不符消除。命令 `bash congestion/scripts/simulation/run_tb_congestion_mesh_selfcheck.sh` 新日志 `congestion/vivado_sim_wsl/tb_congestion_mesh_selfcheck_sim/run_EW2vUWjM/xsim.log`，13×13默认TwoAware三阶段共3042包/14196flit通过内容/目的/顺序/背压/释放/完全排空。路由9组日志、源码哈希及范围见 [修复报告](docs/twoaware_fix_verification_20261028.md)。暂用258-bit完整flit，根src不变，未综合。ThreeAware仅预留，不计作当前缺陷或验收项。

<!-- Modify by Michael Tan，20261028: record passing TwoAware fix and regression evidence. -->

### TwoAware 修复交付（2026-10-28）

已提交并推送 `9891499`（Fix TwoAware eastbound last-hop congestion costs）至 origin/chore/reorganize-project-layout，范围仅该RTL及验证报告。Windows已fetch到9891499；快进拉取仍因既有已修改文件和未跟踪congestion源码被Git中止，HEAD保持cdcc7a9，未覆盖或stash。主项目src不变，暂用宽flit，ThreeAware不纳入验收。

<!-- Modify by Michael Tan，20261028: record pushed TwoAware fix and unchanged Windows synchronization block. -->

## 2026-10-28：XY 与 TwoAware 延迟对比启动

新增独立 tb_congestion_latency_compare 及配套入口，复用同一 congestion RTL，仅 ALGORITHM=0/4 切换；保持13×13、深度8、4VC、258-bit暂用flit、固定4-flit包。首先比较均匀非自身目的流量，固定种子1234501、注入率0.005/0.01/0.02/0.04/0.06/0.08 packet/node/cycle，预热300周期、生成统计窗口1200周期。按出生窗口选样，停生成后继续发送并完全排空，分别统计源排队、网络内和总延迟及P95/P99；比较生成轨迹哈希确保两算法负载相同。仅新增TB/脚本与文档，不改RTL、不综合。该有限窗口比较不是全流量/多种子饱和点证明。

<!-- Modify by Michael Tan，20261028: start fair XY versus TwoAware packet latency experiment. -->

## 2026-10-28：XY/TwoAware 延迟实测完成

新增 tb_congestion_latency_compare、独立run入口和配对分析脚本；未改RTL。WSL Vivado2025.2沙箱外比较13×13、4VC、深度8、258-bit暂用flit、4-flit包、均匀非自身目的、种子1234501，预热300+生成统计1200周期；6档注入率0.005/0.01/0.02/0.04/0.06/0.08。每档两算法生成轨迹哈希、样本数及源码SHA256相同，按出生窗口选样并完全排空，无慢包截尾。

结果：XY六档平均总延迟23.067/23.258/24.498/29.679/81.072/400.967周期；TwoAware23.144/23.388/24.903/31.443/378.933/1357.772周期。本轮XY均更低，高负载TwoAware退化同时体现在网络内与源排队。单种子有限窗口，不宣称全部流量或稳态饱和点结论。新日志为 congestion/vivado_sim_wsl/tb_congestion_latency_compare_sim/run_9BfBkWtn（XY）及run_yYSsWYXk（TwoAware）/xsim.log，12组全部PASS、完整排空；每算法生成/送达54494包、出生窗口样本43890包。

命令 `bash congestion/scripts/simulation/run_tb_congestion_latency_compare.sh -generic_top ALGORITHM=0`（或4）；配对分析 `python3 congestion/scripts/simulation/analyze_congestion_latency_compare.py --xy-run congestion/vivado_sim_wsl/tb_congestion_latency_compare_sim/run_9BfBkWtn --twoaware-run congestion/vivado_sim_wsl/tb_congestion_latency_compare_sim/run_yYSsWYXk --output-dir congestion/docs`。详见 [延迟对比报告](docs/xy_twoaware_latency_20261028.md) 和同名CSV；未综合，不纳入ThreeAware。

<!-- Modify by Michael Tan，20261028: record matched-source latency comparison and load-dependent TwoAware regression. -->

## 2026-10-28：TwoAware 延迟退化静态诊断

仅分析、不改RTL。冻结指标为零，枚举13×13全部28392个非自身源—目的组合：XY/TwoAware总跳数均246064，但最繁忙链路路由数546/1008，后者1.846倍；OE候选与同分偏Y形成明显列间负载偏斜。4-flit固定路径模型峰值负载为13r/24r，在r=0.06分别0.78/1.44 flit/cycle；该模型只是静态风险证据，不是动态饱和点或全部退化根因证明。详见 [诊断报告](docs/twoaware_latency_diagnosis_20261028.md)，复现脚本 analyze_congestion_static_routes.py、624链路计数CSV均在congestion内。下一步应做动态链路/等待计数及OE基线消融，暂不修改算法。

<!-- Modify by Michael Tan，20261028: record static route-bias evidence and dynamic attribution limits. -->

## 2026-10-28：OE 与 TwoAware 延迟对照启动

新增独立 tb_congestion_oe_latency_compare 和配套入口，保持与既有延迟TB完全相同的工作负载、计分板和统计方法，仅选择 ALGORITHM=2。复用已通过的TwoAware（run_yYSsWYXk）及XY（run_9BfBkWtn）结果，先核对RTL哈希与共同TB主体，再补测OE六档0.005/0.01/0.02/0.04/0.06/0.08，固定种子1234501、13×13、4VC、4-flit、暂用258-bit flit、预热300+统计1200周期、完整排空。比较当前OE散列选择和TwoAware占用量求和策略；均为单种子有限窗口，不外推所有OE实现。仅新增TB/脚本及文档，不改RTL。

<!-- Modify by Michael Tan，20261028: start paired OE versus TwoAware latency ablation. -->

## 2026-10-28：OE/TwoAware 延迟对照完成

新增 testbench/tb_congestion_oe_latency_compare.sv、scripts/simulation/run_tb_congestion_oe_latency_compare.sh 和 analyze_congestion_oe_latency_compare.py（均在congestion）。命令 `bash congestion/scripts/simulation/run_tb_congestion_oe_latency_compare.sh` 在WSL Vivado2025.2沙箱外通过；新日志 `congestion/vivado_sim_wsl/tb_congestion_oe_latency_compare_sim/run_vnnZ0OLT/xsim.log`，六档共54494包完全送达，统计出生窗口样本43890包。与既有XY/TwoAware核对22个RTL哈希、规范化TB主体、流量轨迹及样本数一致，未修改RTL。

OE六档平均总延迟23.207/23.597/25.920/118.563/1774.974/2676.622周期；TwoAware相对OE降低0.271%/0.887%/3.924%/73.480%/78.651%/49.273%。本轮说明当前感知决策对该OE基线有净改善，XY仍更低；OE的单比特异或选择不等同于理想独立随机。单种子、均匀流量、有限窗口，不泛化所有OE或稳态。对比包含感知与平局策略共同作用，未单独归因。完整命令、延迟分解、P95/P99和哈希验证见 [报告](docs/oe_twoaware_latency_20261028.md) 及同名CSV。ThreeAware不纳入，未综合，根src不变。

<!-- Modify by Michael Tan，20261028: record complete OE latency control and paired comparison. -->

## 2026-10-28：OE 实现专项排查启动

用户要求排查当前OE，不修改RTL。对照Chiu原论文的OE最短路径约束与输出选择机制；新增独立 tb_congestion_oe_audit/对应WSL入口，在全部169个坐标实例化真实rc_unit，枚举所有源目的及packet ID校验位，检查实际路径最短性、越界、禁转、源节点异或抵消、逐跳选择位翻转和完整ID依赖。补充静态选择策略分布对照，明确规则正确性、选择策略质量与延迟归因的证据边界。原论文 https://fgmoraes.github.io/sichip/2noc/odd-even.pdf 。根src和congestion RTL均不改。

<!-- Modify by Michael Tan，20261028: start source-backed OE legality and hash-correlation audit. -->

OE专项补充：新增 tb_congestion_oe_availability，使用真实router/VA/SA，在EAST四VC均已占用、SOUTH仍空闲时验证HEAD已锁定方向的等待行为；随后按实际包尾释放资源并检查5包清空。此为诊断性行为复现，不修改RTL或改写期望来宣称性能正确。

<!-- Modify by Michael Tan，20261028: add directed resource-availability diagnosis to OE audit. -->

## 2026-10-28：OE 专项排查完成（未改RTL）

新增 tb_congestion_oe_audit、tb_congestion_oe_availability及配套脚本。命令 `bash congestion/scripts/simulation/run_tb_congestion_oe_audit.sh`：57122路径/492128跳无越界、非最短或禁转错误，4096个ID仅两种路由映射，逐跳位翻转通过；日志 congestion/vivado_sim_wsl/tb_congestion_oe_audit_sim/run_NFn4dIQP/xsim.log。命令 `bash congestion/scripts/simulation/run_tb_congestion_oe_availability.sh`：真实router复现EAST四VC忙、SOUTH四VC空闲仍固定等待EAST30周期，释放后5包清空；日志 tb_congestion_oe_availability_sim/run_GnFZZ4Fl/xsim.log。

对照Chiu原论文，基本OE约束相符；问题应收窄为当前单比特异或选择与HEAD提前锁定/VA只尝试唯一方向的性能风险，不能称OE规则写错。独立静态模型逐项匹配624条RTL链路计数，OE峰值921、XY546；代表流有18564条合法最短路但当前只选2条。各因素动态延迟贡献未量化。详见 [专项报告](docs/oe_implementation_audit_20261028.md)，复现脚本analyze_congestion_oe_audit.py及CSV在congestion内。根src和congestion/src均未改，未综合；当前宽flit暂用。

<!-- Modify by Michael Tan，20261028: record OE rule correctness, hash correlation and unavailable-output wait reproduction. -->

## 2026-10-28：OE 唯一方向锁定的单因素对照启动

用户要求仔细验证该机制是否是OE相对XY延迟升高的主因。在 congestion/experiments/oe_va_fallback/ 建立隔离实验副本，22个RTL逐字节复制并记录SHA256；正式congestion/src和根src均不改。实验保留OE合法候选、原异或首选及所有缓冲/流水，只在首选方向无可分配VC时允许另一个合法方向；获配后锁定整包方向。候选/授权接口与元数据只在实验副本扩展，修改保留Original并添加Modify。

先做定向资源选择和包正确性验证，再运行同一流量/样本/计分板的回退关闭与开启六档矩阵。关闭版必须精确复现既有OE数值，方可将开启版变化用于归因。复用XY参考，比较消除的OE—XY延迟差比例，记录回退获配次数；不同时更改散列或拥塞指标。实验不直接合入正式RTL，不综合。

<!-- Modify by Michael Tan，20261028: start isolated single-factor OE VC-availability fallback experiment. -->

## 2026-10-28：OE—XY 资源锁定单因素实验完成

隔离实验 congestion/experiments/oe_va_fallback/ 仅修改5个RTL副本，正式congestion/src和根src不变。资源回退OFF/ON定向测试和六档延迟均PASS，源码相同只切换宏；OFF逐项精确复现原OE全部22个CSV字段。ON保留原异或首选，仅首选无VC时选合法替代并在获配后锁定，每次授权合法/无重复/有资源、全部包计分板及排空通过。

0.04/0.06/0.08的OFF→ON延迟118.563→74.981、1774.974→1018.807、2676.622→1797.902，减少36.758%/42.602%/32.829%，仅消除原OE—XY差距49.032%/44.641%/38.614%，超过一半仍保留。应收窄前述主因判断：这是重要因素，单独改动不足以解释大部分差距；散列、路径分布、两候选都有资源时的选择等贡献未量化。

命令和结果见 [单因素报告](experiments/oe_va_fallback/docs/results_20261028.md)。新延迟日志位于实验 vivado_sim_wsl/tb_oe_va_fallback_latency_sim/run_mode0_IFBt49SP 与run_mode1_19vM0mJe/xsim.log；两定向日志为tb_oe_va_fallback_directed_sim/run_mode0_QkVuClKd、run_mode1_dnqAIiVr。单种子有限窗口，不证明普遍归因或稳态；实验不自动合入正式RTL，不综合，暂用258-bit flit。

<!-- Modify by Michael Tan，20261028: record exact OFF control and incomplete latency-gap closure from availability fallback. -->

### 资源回退实验交付（2026-10-28）

隔离实验和报告已提交推送 a758a3c（Add isolated OE VC-fallback latency ablation），正式congestion/src及根src未变。Windows fetch已更新远端引用，pull --ff-only仍被既有修改和未跟踪congestion文件保护性中止，HEAD保持cdcc7a9；未覆盖或stash。实验仅用于受控分析，不自动启用或合入正式RTL。

<!-- Modify by Michael Tan，20261028: record pushed fallback ablation and protected Windows synchronization block. -->

## 2026-10-28：OE 选路散列第二项消融启动

继续分析延迟主因，在 congestion/experiments/oe_hash_ablation/ 复制已验证的资源回退实验22个RTL（父提交a758a3c），仅改变rc_unit的选路位生成：原单比特奇偶异或与完整packet ID/源/目的/当前节点32-bit混合对照。固定一次函数及种子，不按结果调参；OE候选、仲裁、缓存、位宽和流量不变。新散列分别配回退OFF/ON，与已有原散列OFF/ON组成2×2对照，复用既有XY参考。

新增独立散列路由合法性/路径多样性TB、独立延迟TB及配套入口。统计六档单种子均匀流量、相同出生窗口与完全排空；核对生成轨迹/样本/源码差异，附加授权合法性检查。正式congestion/src和根src不改。32-bit混合仅用于检验相关性因素，不宣称已验证硬件成本或正式优化方案。

<!-- Modify by Michael Tan，20261028: start fixed-policy hash correlation ablation with 2x2 availability controls. -->

## 2026-10-28：等待阶段与动态链路观测启动

散列单因素未稳定改善，继续在已验证资源回退实验副本中新增纯观测 tb_oe_stage_profile，回退固定OFF，ALGORITHM=0/2各运行注入率0.06。复用相同出生流量/统计/排空，采集统计窗口内VA等待（首选无VC、有空闲替代/无空闲替代、有VC但仲裁未获配）、SA流控/仲裁等待、服务次数与624有向链路/列间流量；不改变RTL或选择策略。逐项匹配此前XY/OE对应CSV，确保观测无扰动。计数单位为输入VC请求周期，不直接等同于包延迟归因份额。

<!-- Modify by Michael Tan，20261028: start nonintrusive VA/SA wait and dynamic link profiling. -->

## 2026-10-28：OE 退化继续分析——散列反例与实际等待位置

新增 oe_hash_ablation 隔离实验，父a758a3c的22个RTL仅RC散列不同，原散列和固定32-bit全字段混合各配回退OFF/ON四组。代表流路径数2→2113；合法性228488路径/1968512跳通过，但新散列单独在0.04为440.392（原118.563）、0.08为3350.370（原2676.622），并未稳定改善；组合回退0.04为36.724，0.06/0.08为1071.570/2083.340，不能给机制分配可相加的主因份额。新运行run_mixed_mode0_BK12eGLT、run_mixed_mode1_54GXAypO，最终路由审计run_mixed_mode0_TqLPDi3j；均在新实验vivado_sim_wsl对应top目录。

另新增纯观测tb_oe_stage_profile，原散列回退OFF、0.06下XY/OE全部原22个CSV字段精确复现。VA等待中OE98.293%因首选无VC；VA仲裁只1.707%，内部SA流控等待0。窗口等待请求周期/授权压力XY3.962、OE50.284；624链路均利用率XY54.581%、OE14.797%，最忙链路窗口均值85.083%/55.583%。OE列间流量更偏斜，直接阻塞优先定位在VC获取和资源等待链，不能等同于物理FIFO满、仲裁器有bug或98.3%包延迟归因。观测run_mode0_x2pQcP2N/ run_mode0_TOb1KNq0在oe_va_fallback实验的tb_oe_stage_profile_sim。

命令/数据/范围见 [继续分析报告](docs/oe_latency_followup_20261028.md)。正式congestion/src及根src不变，实验不合入、不综合；下一步查VC占有寿命、实际FIFO占用及源队首阻塞，不直接改正式VC释放规则。单种子有限窗口，不作普适主因或稳态结论。

<!-- Modify by Michael Tan，20261028: record mixed-hash negative controls and nonintrusive stage/link evidence. -->

### 散列与阶段观测交付（2026-10-28）

已提交推送2e36279（Diagnose OE latency with hash ablation and VC-wait profiles），仅隔离实验/观测TB和报告，正式congestion/src和根src不变。Windows fetch成功，pull --ff-only仍因已有修改及未跟踪congestion被保护性中止，HEAD保持cdcc7a9；未覆盖、清理或stash。实验不自动合入正式RTL。

<!-- Modify by Michael Tan，20261028: record pushed follow-up experiment and protected Windows block. -->

## 2026-10-29：OE VC 生命周期与源队首阻塞续析

继续昨日分析，仅静态核查与复读既有CSV，未改RTL/TB或运行新仿真。确认当前VC在下游TAIL读出后归还，与FIFO未满无等价关系；默认流控已为占用7关闭、降至1重开。源注入器只有单个包游标，固定pid%4，受阻不会绕过到后包/其他VC。历史0.06下OE源排队占总延迟81.400%，停止生成时未发HEAD包8304（XY185）；这些是等待位置而非独立因果份额。下一步观测预约寿命、关联FIFO存量及源HEAD/BODY阻塞，保持原释放规则。详见 [续析报告](docs/oe_vc_lifecycle_analysis_20261029.md)。

<!-- Modify by Michael Tan，20261029: record static VC lifecycle and serialized source diagnosis with historical evidence limits. -->

## 2026-10-29：OE VC 存量与源阻塞动态诊断启动

新增独立tb_oe_occupancy_profile及入口，复用回退OFF实验RTL，观察输入VC的待VA/已获配/空置状态与0～8存量、源端HEAD和BODY/TAIL停发及其他VC开启机会。0.06对照XY/OE，保持流量、计分板、采样及完全排空，验收先逐项复现原22个CSV字段。正式RTL不改，不综合；结果记录后补充。

<!-- Modify by Michael Tan，20261029: start nonintrusive occupancy and source-block profiling. -->

## 2026-10-29：OE 存量与源阻塞诊断完成

新增tb_oe_occupancy_profile、独立WSL入口和analyze_oe_occupancy_profile.py，仅观测、不改实验/正式RTL。WSL Vivado2025.2沙箱外0.06两组PASS，原22字段精确复现，每组15260包全送达；状态/请求计数交叉核对和采样守恒通过。OE网络输入有包时84.761%在等VA（XY32.831%），等待时95.463%已存4 flit；网络输入最大4/深度8、全网满8周期为0。源端停发76.553%节点周期（XY8.083%），OE约99.970%停在BODY/TAIL且其他VC开启。证据支持完整包待下一跳、上游预约保持、源单游标放大的回压链；不等同已量化每种机制的独立因果份额，未测逐预约寿命，不直接改释放或增加FIFO。新日志实验tb_oe_occupancy_profile_sim/run_mode0_cYCfoEIr（XY）、run_mode0_TTguBBnE（OE）。命令、口径与CSV见 [报告](docs/oe_occupancy_diagnosis_20261029.md)。未综合、不自动合入。

<!-- Modify by Michael Tan，20261029: record reproducible occupancy evidence for VC backpressure and source serialization. -->

## 2026-10-29：同事与主项目 TB 方法静态对照

对照同事tb_mesh_injection_1.1、根5×5四VC队列扫描及当前congestion自检TB。原TB有静态初始化、停止源注入仅等500周期、多率不复位和缺自检问题；主项目有预热/逐档复位/继续发送排空/序号与目的自检，但源实际固定VC0，同样单包顺序发送，排空上限后缺严格全部生成包验收，posedge阻塞驱动存在调度风险。当前OE/XY来自新自检TB，固定pid%4、相同轨迹并严格清空，不能用原TB统计缺陷直接解释已复现差距。详见 [方法对照](docs/tb_method_comparison_20261029.md)。仅分析，无RTL/TB改动或新仿真。

<!-- Modify by Michael Tan，20261029: record actual TB method differences and avoid attributing shared source HOL only to the received TB. -->

## 2026-10-29：安全多包接入修改启动

用户授权仅修改congestion，不改根src；已建立修改前Git检查点c0bcd8f。将接入所有权归还从TAIL读出改为TAIL/HEADTAIL成功写入，保留元数据读出出队，禁止按~is_full_o开放VC。补充元数据接收背压，使用真实双路由器定向测试及容量、长包、路由/全网回归；所有新改代码含Modify标注。未完成验证前不宣称通过，不修改隔离历史实验副本。

<!-- Modify by Michael Tan，20261029: start authorized packet-boundary admission release with regression protection. -->

## 2026-10-29：安全多包接入修改与回归完成

仅congestion/src/input_buffer_src_circular_full.sv改变设计：TAIL/HEADTAIL成功写入才归还上游接入资格，TAIL读出只弹元数据；保留拒收与包顺序保护、7关闭/1重开滞回，增加元数据满接收保护，未恢复~is_full_o分配。新双路由器XY/OE测试证明第一包未读出时第二包经真实VA进入同一VC，停读占用7/两条元数据，前包开放时竞争包不得重用其VC。100步边界及原64组容量/拒写通过；XY/OE/OneAware/TwoAware全网12阶段12168包/56784flit、54756项采集及默认路由自检均PASS。高负载同轨迹0.06下两组15260包全送达，网络FIFO最大7；XY总延迟81.072→58.628、OE1774.974→1092.089，剩余OE差距未解决。所有代码改动含Modify/Original，修改前Git检查点c0bcd8f；正式提交/推送随后记录。命令、源码SHA、全部run和限制见 [修改报告](docs/packet_admission_fix_20261029.md)。根src和历史隔离实验RTL不变，未综合。

<!-- Modify by Michael Tan，20261029: record packet-boundary reuse implementation and passing safety, network and high-load regressions. -->
