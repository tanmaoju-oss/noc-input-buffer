# noc-input-buffer

NoC 输入缓冲区设计、验证与性能仿真项目。

<!-- Modify add Chinese project summary for user reading, Michael Tan, 20260626 -->

## 这个文件的作用

这个文件是给你看的中文说明，用来记录当前 NoC/Vivado 仿真工作的进展、重要文件、已经修过的问题，以及后续如果继续做注入率-延迟曲线应该从哪里接着做。

另一个文件 `AGENTS.md` 主要是给我在新会话中读取的交接记忆。以后新开会话时，你可以直接说：

```text
先读 AGENTS.md，然后继续。
```

## 当前项目路径

```text
/home/tanma/Documents/Project/noc-input-buffer
```

## 当前运行环境

项目已经从 Windows 桌面目录迁移到 WSL2 的 Linux 文件系统，当前环境为 Ubuntu 24.04。后续操作默认使用 Linux 路径和 Bash 命令，不再把原来的 `C:\Users\...` 路径作为项目位置。

当前已确认：

- Git 可以在 WSL 中使用。
- Linux Vivado 2025.2 已安装在 `/home/tanma/tools/Xilinx/2025.2/Vivado`。使用前执行 `source /home/tanma/tools/Xilinx/2025.2/Vivado/settings64.sh`，即可调用 `vivado`、`xvlog`、`xelab` 和 `xsim`。
- Ubuntu 下的 GCC、G++、Make 和 Vivado/xsim 依赖已经安装。临时 `/tmp` 冒烟测试中，现有 `tb_mesh` 已输出 `[TB_MESH] PASSED`。
- Codex 命令沙箱会让 xsim 在加载快照时出现 `ERROR: unexpected exception when evaluating tcl command`；同一快照在获准的沙箱外执行后可正常仿真。因此以后由 Codex 运行 xsim 时，应直接使用获准的 escalated execution，避免把沙箱限制误判成 RTL 或缺库错误。
- Windows Vivado 2019.2 安装在 `E:\Vivado\Vivado\2019.2`，并具有综合所需许可证。以后所有 Vivado 综合均固定通过 Windows Vivado 2019.2 执行，不使用 Linux Vivado 进行综合。<!-- Modify establish Windows Vivado synthesis rule, Michael Tan, 20260729 -->
- 本文后面保存的大量 PowerShell 命令与仿真结果属于历史记录；在 WSL 中重新验证脚本以前，不应理解为可以直接运行。
- 已有 `xsim.log`、波形和结果文件是迁移过来的历史产物，不代表已经在新 Linux 环境重新仿真。

当前已增加并验证 WSL/Linux Bash 入口 `scripts/simulation/run_tb_mesh.sh`，同时继续保留 `.ps1` 脚本作为 Windows 复现入口。

## Vivado 使用分工

| 情况 | 使用环境 | 要求与结果位置 |
| --- | --- | --- |
| RTL 编译检查、功能仿真、回归仿真、注入率扫描、波形和结果分析 | WSL/Linux Vivado 2025.2 | 默认使用 Bash 入口；结果写入 `vivado_sim_wsl/<top>_sim/`。若 xsim 出现已知 Tcl 快照异常，应在沙箱外重跑。 |
| 新增或修改 RTL、TB、监测器、ILA wrapper 的功能验证 | 先用 WSL/Linux Vivado 2025.2 | 先验证功能、断言和统计关系；此结果不代表目标 FPGA 的实现结果。 |
| `xcvu440-flga2892-2-e` 的综合、实现、时序分析、生成 `.bit/.ltx` | Windows Vivado 2019.2（有许可证） | 必须通过 `powershell.exe` 调用 Windows Vivado；结果写入 `vivado_synthesis_windows/<top>_synthesis/`。 |
| ILA IP 创建、ILA 实例的最终综合实现、JTAG 上板文件生成 | Windows Vivado 2019.2（有许可证） | ILA IP 与 `.bit/.ltx` 必须来自同一 Windows 实现运行；不要将 2025.2 生成的 ILA IP 直接用于 2019.2。 |
| Windows Vivado 仿真复核 | Windows Vivado 2019.2（按需） | 仅在需要检查 2019.2 兼容性、ILA 仿真 stub 或与 Windows 历史结果比较时运行；先同步 Linux 的 `scripts/` 与相关源码，结果写入 `vivado_sim_windows/<top>_sim/`。 |

默认流程是“WSL 功能验证 → Windows 目标器件综合/实现 → 上板验证”。不要因 Linux 免费许可证无法实现 `xcvu440` 而提前维护两套 RTL；仅在 Windows 报告实际兼容性问题时修改共享 RTL。<!-- Modify define WSL and Windows Vivado workflow boundaries, Michael Tan, 20260908 -->

目标板 FPGA 的完整器件名固定为 `xcvu440-flga2892-2-e`；所有 Windows Vivado 综合、实现、ILA IP 生成及后续 `.bit/.ltx` 必须使用此完整 Part，不能以 `xcvu440` 简写替代。<!-- Modify record exact target FPGA part name, Michael Tan, 20260908 -->

## 2026-09-08 ILA 包装层与 WSL 验证（进行中）

- 新增板级 ILA 包装层，将 `noc_clk`、统计窗口状态、延迟累计计数和单包 TAIL 调试寄存器集中映射为稳定 probe。WSL 仿真默认采用 no-op 分支验证 probe 连线，不依赖 Windows 2019.2 生成的 ILA IP。
- Windows 2019.2 创建匹配的 `ila_0` IP 后，以 `NOC_BOARD_ILA_VIVADO_IP` 宏启用真实实例；本步不创建 XDC、Windows 综合实现、`.bit/.ltx` 或 JTAG 下载。

<!-- Modify record start of board ILA wrapper integration and WSL verification, Michael Tan, 20260908 -->

## 2026-09-08 ILA 包装层与 WSL 验证完成

- 新增 `src/board_ila/noc_board_ila_debug.sv`，并接入 `noc_board_ila_top.sv`。包装层固定映射 `noc_clk`、窗口相位/使能、五个统计计数、累计延迟和八个单包调试信号；默认 no-op 分支用于 WSL，Windows 2019.2 在包含匹配 `ila_0` IP 后以 `NOC_BOARD_ILA_VIVADO_IP` 宏启用真实 ILA 实例。
- 新增 `testbench/tb_noc_board_ila_wrapper.sv` 与 `scripts/simulation/run_tb_noc_board_ila_wrapper.sh`。Linux Vivado 2025.2 使用 `bash scripts/simulation/run_tb_noc_board_ila_wrapper.sh` 在沙箱外通过；结果位于 `vivado_sim_wsl/tb_noc_board_ila_wrapper_sim/xsim.log`：`enqueued=2525`、`tails=2525`、`tail_events=1134`、`probe_mismatches=0`、`total_latency=60569`。这证明包装层不改变流量/监测行为，且 16 个 WSL probe 均与其顶层源信号逐拍一致。
- 本步尚未创建 Windows ILA IP、XDC、综合实现、`.bit/.ltx` 或 JTAG 下载；下一步是在 Windows Vivado 2019.2 按包装层的 `probe0` 至 `probe15` 位宽创建 `ila_0`，启用宏后执行目标器件实现。

<!-- Modify record completed board ILA wrapper integration and WSL verification, Michael Tan, 20260908 -->

## 2026-09-08 Windows ILA IP 生成与综合验证（进行中）

- 为固定的 16 个 `probe` 创建 Windows Vivado 2019.2 ILA IP 生成 Tcl，并增加 `noc_board_ila_top` 的 VU440 综合入口。综合时定义 `NOC_BOARD_ILA_VIVADO_IP`，以验证真实 `ila_0` 实例、IP 配置和 RTL 端口连接。
- 综合展开显示原监测器每源 2048 项时间戳表超过 Vivado 2019.2 单变量规模限制；板级首版追踪表将设为 64 项（与默认源队列相同），并保持低 6 位序号索引。若极端拥塞使未到达包超过此容量，现有覆盖计数器会通过 ILA 显式报告。
- 本步仅生成 ILA IP 并执行综合网表检查；尚无独立新 XDC，因此不执行实现、时序收敛、`.bit/.ltx` 生成或 JTAG 下载。
- 已终止耗时过长的多维监测表综合，开始在不缩小原始 25×2048 追踪容量、不改变统计语义的条件下重构监测器存储；修改后必须逐项对比既有 ILA wrapper TB 的包数、总延迟、未匹配数、覆盖数及 probe 值。
- 已将监测器序号维度改为每源独立的 packed 存储，仍保留 `25×2048×32` 位时间戳和全部有效/测量标志。WSL Vivado 2025.2 回归命令 `bash scripts/simulation/run_tb_noc_board_ila_wrapper.sh` 通过，结果与重构前完全一致：`enqueued=2525`、`tails=2525`、`unmatched=0`、`overwrites=0`、`total_latency=60569`、`probe_mismatches=0`；结果文件为 `vivado_sim_wsl/tb_noc_board_ila_wrapper_sim/xsim.log`。本次仅修改监测器，等价性验证止于 WSL；不运行 Windows Vivado 综合。
- 下一步仅在 WSL 重排 `noc_board_traffic_generator.sv` 的多维状态和源队列存储；不得修改随机序列、目的地址映射、队列深度或任一入队/出队优先级。验收必须与既有 ILA wrapper TB 的全部统计和 probe 检查一致，不运行 Windows Vivado 综合。
- 已将流量发生器的 y 源维和 FIFO 槽位维改为 packed 存储；`[x][y]` 与 `[x][y][slot]` 的索引、64 项队列深度、LFSR/目的地址和发送优先级均未改动。WSL 命令 `bash scripts/simulation/run_tb_noc_board_ila_wrapper.sh` 通过，结果保持 `enqueued=2525`、`tails=2525`、`unmatched=0`、`overwrites=0`、`total_latency=60569`、`probe_mismatches=0`。

<!-- Modify record start of Windows ILA IP and synthesis verification, Michael Tan, 20260908 -->

## 周报与工作计划记录规则

当需要编写周报或下周工作计划时，统一使用 `file/周报/2026-08-下周工作计划.txt` 的简洁格式，按“周一上午”至“周五下午”逐项安排。计划除研发工作外，还应包含党建学习/材料整理及公司融资资料整理、数据核对或沟通协调；如有当周明确事项，则以实际事项为准。周报和下周工作计划的每条事项应为一条短句，篇幅不超过“完成板级随机流量发生器的均匀非自身目的地址映射与 LFSR 去相关方案整理，核对种子分散。”这一示例；MBO 的指标描述和衡量标准可按表格格式保留必要的完整说明。每次新建或修改该目录中的周报、工作计划或 MBO 文档后，均自动同步对应文件到 Windows 工作副本 `E:\\Codex-Project\\NoC-XY\\file\\周报\\`，并确认目标文件存在；此同步不依赖 Git。<!-- Modify scope concise weekly-item length and retain Windows synchronization rule, Michael Tan, 20260828 -->

`file/` 下的资料同步必须按同名子目录对应：`file/代码分析/ → E:\\Codex-Project\\NoC-XY\\file\\代码分析\\`，`file/仿真分析/ → E:\\Codex-Project\\NoC-XY\\file\\仿真分析\\`，`file/周报/ → E:\\Codex-Project\\NoC-XY\\file\\周报\\`。正常同步不得写入仓库外的临时备份目录；`E:\\Codex-Project\\NoC-XY-sync-backup-8777ef2` 仅保留当时 Windows 未跟踪文件的历史副本。<!-- Modify enforce corresponding file-subdirectory synchronization, Michael Tan, 20260908 -->

每次修改 `src/` 中的 RTL/设计代码并完成必要验证后，必须将相关变更 Git 提交并推送到 GitHub；推送完成后同步 Windows 工作副本，并确认其提交与远程一致。<!-- Modify require GitHub push after every verified src change, Michael Tan, 20260908 -->

<!-- Modify classify weekly-plan records under file/周报, Michael Tan, 20260825 -->

## 文件资料分类

- `file/周报/`：周报和下周工作计划 TXT 文件，仅作为本地工作记录保存，不纳入 Git。
- `file/代码分析/`：NoC 模块代码分析 Markdown，纳入 Git 以便跨工作副本复用。当前包括环形缓冲区、轮询仲裁器、分离式输入优先仲裁器、VC allocator、input buffer、input port 和 input block 的分析。

<!-- Modify classify local weekly records and tracked code analyses, Michael Tan, 20260825 -->

## 2026-08-03 上板与 ILA 长期工作基线

本项目的 NoC 上板/ILA 工作将分阶段完成，不要求在一次修改中完成所有 RTL、综合和实机验证。首版范围固定为无 DDR 的 NoC 调试工程：不使用 SD 卡、Flash、DDR、SPI、UART 或原 SoC 的用户 JTAG 接口。

- 目标 FPGA：`xcvu440-flga2892-2-e`。
- 综合、实现和生成位流：继续使用已授权的 Windows Vivado 2019.2。
- 下载和 ILA 调试：计划使用 Vivado 2022 Hardware Manager，通过 USB/JTAG 直接下载由 2019.2 生成的 `.bit`，并加载同一次构建生成的配套 `.ltx`。该配置为易失性，上电后需要重新下载。
- 已从板级照片确认：100 MHz 差分时钟端口为 `l_pad_clk_p/n`，管脚 `AT49/AU49`，标准 `DIFF_SSTL12`；低有效复位为 `l_pad_rst_b`，管脚 `R12`，标准 `LVCMOS18`。参考文件在 `constraints/soc_dcpu_j2/`。
- 新的无 DDR NoC 顶层将采用 `l_pad_clk_p/n → IBUFDS → BUFG → 100 MHz noc_clk`，并用 `l_pad_rst_b` 经过复位同步器生成内部复位。SoC 的后续时钟路径依赖 DDR MIG，不能照搬。
- 首个硬件负载与现有均匀随机 4VC、4-flit、5x5 的 0.1 注入率实验对齐：每节点每周期按 0.1 概率生成包、源端队列、可综合 LFSR、从“进入源队列”到“TAIL 到达”统计延迟。ILA 观察统计和内部调试信号，不需要额外 probe 引脚约束。
- 仿真参考点：`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_results.txt` 中 0.1 点为 2545 个测量包全部接收、无队列满/错误、平均延迟 22.565 cycles。硬件使用 LFSR，要求统计口径可比，不要求逐周期完全相同。

<!-- Modify record persistent board bring-up and direct-JTAG ILA baseline, Michael Tan, 20260803 -->

## 2026-08-04 上板第一步：独立顶层

- 本步骤新建 `constraints/noc_board_ila/`，作为新的无 DDR NoC 上板工程约束目录；`constraints/soc_dcpu_j2/soc_dcpu_j2.xdc` 保持只读参考，不修改、不直接用于新工程。
- 首版板级顶层将放入 `src/board_ila/`，仅实现已确认的差分时钟接收、复位同步和 5×5 NoC 接入。流量发生器、监控器、ILA、专用 XDC、实现和上板验证均为后续步骤。

<!-- Modify record start of isolated DDR-free board top task, Michael Tan, 20260804 -->

## 2026-08-04 上板第一步完成：无 DDR 顶层

- 新增 `src/board_ila/noc_board_ila_top.sv`：顶层仅含 `l_pad_clk_p`、`l_pad_clk_n`、`l_pad_rst_b` 三个端口；通过 `IBUFDS → BUFG` 生成内部 `noc_clk`，以两级同步器释放内部复位，并接入静默的 5×5、4VC `mesh`。
- 新增 `constraints/noc_board_ila/constraints.md`，使新约束目录可独立保留。原 `constraints/soc_dcpu_j2/` 文件未修改，继续只作为 SoC/DDR 相关参考；本步骤没有创建或接入 XDC。
- 已用 Linux Vivado 2025.2 在临时目录完成 `xvlog --sv --relax` 编译及 `xelab -L unisims_ver` 展开，顶层无错误。未运行仿真，未做 Windows 综合、实现、位流或实机下载。

<!-- Modify record completed first DDR-free board top implementation and compile check, Michael Tan, 20260804 -->

## 2026-08-05 上板第二步：可综合流量发生器

- 本步骤在 `src/board_ila/` 增加独立、可综合的源端排队随机流量发生器，并接入已完成的无 DDR 顶层；范围不包括延迟监控器、ILA、XDC、Windows 综合实现、位流或上板下载。
- 发生器固定为 5×5、4VC NoC 的 4-flit packet，所有节点使用独立非零 16-bit LFSR；每周期的生成门限为 `6554/65536`（约 0.1），目的节点保证不等于源节点。源端 FIFO 深度为 64，入口使用 VC0，NoC 内部仍保持 4VC 配置。

<!-- Modify record start of synthesizable board traffic-generator step, Michael Tan, 20260805 -->

## 2026-08-05 上板第二步完成：流量发生器与验证

- 新增 `src/board_ila/noc_board_traffic_generator.sv`，并将其接入 `src/board_ila/noc_board_ila_top.sv`。每个 5×5 节点独立使用非零 16-bit LFSR 和 64 项源端队列；产生非自身目的节点的 `HEAD/BODY/BODY/TAIL` 四 flit 包，经 VC0 注入。生成门限为 `6554/65536`，即每节点每周期约 0.1 packet；NoC 内部仍为 4VC。
- 新增 `testbench/tb_noc_board_traffic_generator.sv` 与 `scripts/simulation/run_tb_noc_board_traffic_generator.sh`。使用 Linux Vivado 2025.2 执行 `bash scripts/simulation/run_tb_noc_board_traffic_generator.sh`；因 xsim 沙箱快照加载限制，在允许的沙箱外重跑后通过。结果见 `vivado_sim_wsl/tb_noc_board_traffic_generator_sim/xsim.log`：1000 个时钟周期接收 8970 个 flit，`errors=0`。
- 本步骤未加入延迟监控器、ILA、XDC、Windows 综合/实现、位流或实机下载；下一步单独实现从源队列入队到 TAIL 到达的可综合监控器。

<!-- Modify record completed synthesizable board traffic-generator step, Michael Tan, 20260805 -->

## 2026-08-17 上板第三步：源队列到 TAIL 延迟监控器

- 本步骤将在 `src/board_ila/` 新增加可综合监控器：源端 packet 进入源队列时记录周期计数，在目的端收到对应 TAIL 时累加端到端延迟，并保留入队数、TAIL 到达数、未匹配 TAIL 数与累计延迟等计数器，供后续 ILA 连接。
- 为让 25 个源节点的包可唯一匹配，16 位 packet ID 将固定划分为 5 位源节点编号和 11 位源内序号；本步还会新建独立 tb、WSL/Linux 仿真入口及结果目录验证该统计链路。
- 范围仍不包含 ILA IP、XDC、Windows 综合/实现、位流或实机下载。

<!-- Modify record start of synthesizable board latency-monitor step, Michael Tan, 20260817 -->

## 2026-08-17 上板第三步完成：可综合延迟监控与验证

- 新增 `src/board_ila/noc_board_latency_monitor.sv`，并接入 `src/board_ila/noc_board_ila_top.sv`。监控器在 packet 成功进入源端队列时记下周期，在目的节点输出对应 TAIL 时匹配并累计延迟；顶层保留 `monitor_packets_enqueued`、`monitor_tails_received`、`monitor_unmatched_tails`、`monitor_timestamp_overwrites`、`monitor_total_latency_cycles` 五个内部计数器，供下一步 ILA 直接观察。其中覆盖计数器会在旧 packet 尚未到达 TAIL 时其 ID 时间戳槽被复用时置数，避免静默统计失真。
- 更新 `src/board_ila/noc_board_traffic_generator.sv` 的既有 16 位 packet ID 编码：高 5 位为 5×5 源节点编号，低 11 位为该源节点的递增序号。BODY/TAIL 中沿用该 ID，因此不改变路由目的字段，也能避免多源 packet 误匹配。
- 新增 `testbench/tb_noc_board_latency_monitor.sv` 与 `scripts/simulation/run_tb_noc_board_latency_monitor.sh`。执行命令为：

```bash
bash scripts/simulation/run_tb_noc_board_latency_monitor.sh
```

- Linux Vivado 2025.2 的沙箱内 xsim 首先出现已知 Tcl 快照加载异常；在允许的沙箱外重跑后通过。结果目录为 `vivado_sim_wsl/tb_noc_board_latency_monitor_sim/`，其中 `xsim.log` 记录：`[TB_BOARD_MONITOR] PASSED enqueued=2867 tails=2232 unmatched=0 overwrites=0 total_latency=393419 mesh_errors=0`。这表明有 2232 个 TAIL 被正确匹配，未匹配数、时间戳覆盖数和 NoC 错误均为 0；剩余入队包仍在网络或源队列中，符合持续注入的 1000 周期测试。
- 本步没有加入 ILA IP、XDC、Windows 综合/实现、位流或实机下载。下一步才是将这些计数器及所需调试信号接入 ILA。

<!-- Modify record completed synthesizable board latency-monitor step, Michael Tan, 20260817 -->

## 2026-08-20 延迟计算波形可观测性

- 为便于 Vivado WDB 和后续 ILA 直接查看单包延迟计算，本步骤将为延迟监控器及板级顶层增加稳定调试寄存器：TAIL 匹配事件、包 ID、源节点 ID、源内序号、入队时间戳、当前周期和本次计算的延迟周期数。
- `tail_event` 为单周期脉冲；如同一周期内出现多个匹配 TAIL，调试寄存器按监控器既有 x/y 扫描顺序保留最后一个匹配项，不改变累计统计结果。

<!-- Modify record start of latency-monitor waveform-debug task, Michael Tan, 20260820 -->

## 2026-08-20 延迟计算调试信号完成与验证

- 已更新 `src/board_ila/noc_board_latency_monitor.sv`、`src/board_ila/noc_board_ila_top.sv` 和 `testbench/tb_noc_board_latency_monitor.sv`。顶层可直接加入波形窗口的信号为：`monitor_debug_tail_event`、`monitor_debug_tail_packet_id`、`monitor_debug_tail_source_id`、`monitor_debug_tail_sequence`、`monitor_debug_enqueue_cycle`、`monitor_debug_current_cycle`、`monitor_debug_last_packet_latency`；其中事件为 1 时满足：`last_packet_latency = current_cycle - enqueue_cycle`。这些顶层信号带有 `MARK_DEBUG`/`KEEP`，也可复用于后续 ILA。
- 使用 Linux Vivado 2025.2 运行 `bash scripts/simulation/run_tb_noc_board_latency_monitor.sh` 验证通过；重新生成的波形数据库是 `vivado_sim_wsl/tb_noc_board_latency_monitor_sim/tb_noc_board_latency_monitor_sim.wdb`。`xsim.log` 结果仍为 `PASSED enqueued=2867 tails=2232 unmatched=0 overwrites=0 total_latency=393419 mesh_errors=0`，tb 同时检查了新增信号的减法关系。

<!-- Modify record completed latency-monitor waveform-debug task, Michael Tan, 20260820 -->

## 2026-08-27 板级延迟统计窗口对齐（进行中）

- 本任务使可综合板级流量发生器和延迟监控器采用性能 TB 的窗口定义：200 周期 Warm-up、1000 周期 Measurement、停止新生包后的最多 8000 周期 Drain。
- Warm-up 包仍保留时间戳并在 TAIL 到达时正常匹配，但只有 Measurement 窗口内成功进入源队列的包计入包数与累计延迟；原有 1000 周期冒烟 TB 保持不变，另建专用窗口对齐 TB、脚本及结果目录。
- 本任务不包含 ILA IP、XDC、Windows 综合/实现、位流或上板下载。<!-- Modify record start of board latency statistics-window alignment task, Michael Tan, 20260827 -->

## 2026-08-27 板级延迟统计窗口对齐完成

- 更新 `src/board_ila/noc_board_ila_top.sv`、`noc_board_traffic_generator.sv` 和 `noc_board_latency_monitor.sv`：可综合顶层现依次执行 200 周期 Warm-up、1000 周期 Measurement、最多 8000 周期 Drain；Drain 内停止新生 packet、继续发送既有 packet。监控器继续保存 Warm-up 包时间戳以正确匹配其 TAIL，但仅将 Measurement 窗口内成功进入源队列的包计入包数和延迟；并新增 Measurement 窗口的源队列满计数。
- 新增 `testbench/tb_noc_board_latency_monitor_windowed.sv`、`scripts/simulation/run_tb_noc_board_latency_monitor_windowed.sh`，结果目录为 `vivado_sim_wsl/tb_noc_board_latency_monitor_windowed_sim/`。为与性能 TB 的队列容量一致，新 TB 将可参数化顶层的 `SOURCE_QUEUE_DEPTH` 覆盖为 2048；实际板级顶层默认值仍为 64。
- 使用 Linux Vivado 2025.2 执行 `bash scripts/simulation/run_tb_noc_board_latency_monitor_windowed.sh`。沙箱内先出现已知 xsim Tcl 快照异常，允许的沙箱外重跑通过：`enqueued=2688`、`queue_full=0`、`tails=2688`、`unmatched=0`、`overwrites=0`、`mesh_errors=0`，累计延迟 `666712` cycles，平均延迟 `248.032` cycles。说明 Measurement 包已在 Drain 内全部收齐，统计窗口和源队列容量均已与旧性能 TB 对齐。
- 此平均延迟仍不同于历史性能 TB 的 `22.565` cycles：板级发生器按每节点独立 LFSR 产生注入与目的地址，而性能 TB 使用 `$urandom` 序列及不同的目的地址采样；因此这是流量模型的差异，不是统计窗口截断、队列满或 packet ID 匹配错误。未加入 ILA IP、XDC、Windows 综合/实现、位流或上板下载。<!-- Modify record completed board latency statistics-window alignment task, Michael Tan, 20260827 -->

## 2026-08-27 板级 0.01 注入率窗口化诊断（进行中）

- 将新增独立的 0.01 每节点每周期 packet 注入率窗口化 TB，窗口仍为 200 周期 Warm-up、1000 周期 Measurement、8000 周期 Drain，且沿用 2048 项源队列以便与性能 TB 比较。
- 板级顶层的注入门限将参数化；该新 TB 使用 `655/65536≈0.01`，默认板级负载保持 `6554/65536≈0.1`。本实验用于诊断 0.1 统计值偏高，不涉及性能优化或 ILA/XDC/实现。<!-- Modify record start of 0.01 board windowed latency diagnostic, Michael Tan, 20260827 -->

## 2026-08-27 板级 0.01 注入率窗口化诊断完成

- 已将 `src/board_ila/noc_board_ila_top.sv` 的 `INJECTION_THRESHOLD` 参数化，默认仍为 `16'd6554≈0.1`；新增 `testbench/tb_noc_board_latency_monitor_windowed_rate_001.sv` 和 `scripts/simulation/run_tb_noc_board_latency_monitor_windowed_rate_001.sh`，其独立结果目录为 `vivado_sim_wsl/tb_noc_board_latency_monitor_windowed_rate_001_sim/`。
- 在 Linux Vivado 2025.2 沙箱外执行 `bash scripts/simulation/run_tb_noc_board_latency_monitor_windowed_rate_001.sh` 通过。`xsim.log`：`rate_threshold=655`、`enqueued=356`、`queue_full=0`、`tails=356`、`unmatched=0`、`overwrites=0`、`mesh_errors=0`、累计延迟 `8563` cycles、平均延迟 `24.053` cycles。
- 相比 0.1 的 `248.032` cycles，约 0.01 负载下降至 `24.053` cycles，且所有统计包均在 Drain 内完成。这表明延迟监控器、时间戳匹配和 Drain 统计在低负载下工作正常；0.1 偏高仍需从流量/拥塞模型继续分析，而不是未完成包、队列满或 packet ID 匹配错误。未加入 ILA IP、XDC、Windows 综合/实现、位流或上板下载。<!-- Modify record completed 0.01 board windowed latency diagnostic, Michael Tan, 20260827 -->

## 2026-08-27 板级均匀目的地址映射诊断（进行中）

- 将替换板级发生器原有的 3-bit `% 5` 目的坐标映射：该映射使坐标 0、1、2 的概率各为 25%，坐标 3、4 的概率各为 12.5%，且命中自身后的 x 轴修正会进一步偏置流量。
- 新映射直接在 24 个非自身目的节点中选择；新增独立的 0.1 窗口化 TB、脚本和结果目录，保留原偏置映射结果用于对照。<!-- Modify record start of uniform board destination-mapping diagnostic, Michael Tan, 20260827 -->

## 2026-08-27 板级均匀目的地址映射诊断完成

- 已更新 `src/board_ila/noc_board_traffic_generator.sv`：先在 24 个非自身节点编号中选择，再转换为 x/y 坐标；不再从 3-bit 数值做 `% 5`，也不再使用仅改变 x 坐标的自身目的地修正。完整 LFSR 状态对 24 取模的剩余偏差最多为每个目的节点一个状态，远小于已消除的原坐标偏置。
- 新增 `testbench/tb_noc_board_latency_monitor_windowed_uniform_dest.sv` 和 `scripts/simulation/run_tb_noc_board_latency_monitor_windowed_uniform_dest.sh`。在 Linux Vivado 2025.2 沙箱外执行该脚本通过；结果目录为 `vivado_sim_wsl/tb_noc_board_latency_monitor_windowed_uniform_dest_sim/`，`xsim.log` 为：`enqueued=2688`、`queue_full=0`、`tails=2688`、`unmatched=0`、`overwrites=0`、`mesh_errors=0`、累计延迟 `285493` cycles、平均延迟 `106.210` cycles。
- 在相同 0.1 门限及统计窗口下，平均延迟从偏置映射的 `248.032` 降至 `106.210` cycles，证明空间目的地址偏置是严重拥塞的重要来源；但仍高于历史 `$urandom` 性能 TB 的 `22.565` cycles，后续需单独分析 LFSR 注入时刻相关性及有限窗口的流量分布。未加入 ILA IP、XDC、Windows 综合/实现、位流或上板下载。<!-- Modify record completed uniform board destination-mapping diagnostic, Michael Tan, 20260827 -->

## 2026-08-27 板级注入 LFSR 去相关化（进行中）

- RTL 等价统计确认：旧的相邻种子 `1..25` 与每周期仅前进一步的注入 LFSR，在 1000 周期 Measurement 内出现 10 次 25 节点同时注入、1444 次同节点连续两周期注入，远偏离独立 0.1 随机流量。
- 将改为分散的确定性非零种子，并在每个活跃周期中将注入 LFSR 前进 16 步后再比较门限。只读重放预计最大并发约为 9、同节点连续注入约为 230（独立 0.1 随机的期望约 250）；将用独立 TB/脚本/结果目录验证。<!-- Modify record start of board injection LFSR decorrelation task, Michael Tan, 20260827 -->

## 2026-08-27 板级注入 LFSR 去相关化完成

- 已更新 `src/board_ila/noc_board_traffic_generator.sv`：每个源节点使用由 `16'h9e37 * (source_index + 1)` 派生的分散确定性非零种子；每个活跃周期先以既有 XOR/移位 LFSR 前进 16 步，再作注入门限比较。该实现不引入运行时乘法器、保持约 0.1 门限，并继续使用已修正的均匀非自身目的地址映射。
- 新增 `testbench/tb_noc_board_latency_monitor_windowed_decorrelated_lfsr.sv` 和 `scripts/simulation/run_tb_noc_board_latency_monitor_windowed_decorrelated_lfsr.sh`。在 Linux Vivado 2025.2 沙箱外执行该脚本通过；结果目录为 `vivado_sim_wsl/tb_noc_board_latency_monitor_windowed_decorrelated_lfsr_sim/`，`xsim.log`：`enqueued=2525`、`queue_full=0`、`tails=2525`、`unmatched=0`、`overwrites=0`、`mesh_errors=0`、累计延迟 `60569` cycles、平均延迟 `23.987` cycles。
- 在对齐的约 0.1 负载下，仅修正目的地址后的 `106.210` cycles 已进一步降至 `23.987` cycles，接近历史 `$urandom` 性能 TB 的 `2545` 包、`22.565` cycles。剩余差异来自不同的确定性 PRNG 序列，不再是严重同步突发拥塞的伪影。未加入 ILA IP、XDC、Windows 综合/实现、位流或上板下载。<!-- Modify record completed board injection LFSR decorrelation task, Michael Tan, 20260827 -->

## 2026-09-08 板级 0.11–0.20 注入率扫描（进行中）

- 新增独立板级扫描 TB，使用 200 周期 Warm-up、1000 周期 Measurement、8000 周期 Drain、2048 项源队列及已去相关的 LFSR 流量，依次验证每节点 packet 注入率 0.11 至 0.20。
- 扫描结果将与既有 5×5、4-VC、4-flit 性能 TB 的对应注入率结果对比，并写入 `file/仿真分析/`；不涉及 ILA、XDC、Windows 实现、位流或板卡下载。

<!-- Modify record start of board 0.11-to-0.20 injection-rate comparison sweep, Michael Tan, 20260908 -->

## 2026-09-08 板级 0.11–0.20 注入率扫描完成

- 新增板级扫描 TB/脚本：`testbench/tb_noc_board_latency_monitor_rate_sweep_011_to_020.sv`、`scripts/simulation/run_tb_noc_board_latency_monitor_rate_sweep_011_to_020.sh`，逐点运行 0.11–0.20；结果日志在 `vivado_sim_wsl/tb_noc_board_latency_monitor_rate_sweep_011_to_020_sim/`。十点均满足入队包全部在 Drain 内以 TAIL 收齐，且 queue-full、未匹配、时间戳覆盖和 NoC 错误均为零；延迟从 0.11 的 `28.149` cycles 增至 0.20 的 `371.774` cycles。
- 新增独立性能 TB 扫描 `tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_rate_011_to_020`，并用两点补充 TB 完成 0.19、0.20。性能 TB 的 0.20 延迟为 `401.387` cycles；完整对比见 `file/仿真分析/板级监测模块与性能TB_011至020注入率对比.md`。两组曲线均在约 0.13–0.15 后出现明显排队增长，差异来自可综合 LFSR 与 `$urandom` 流量序列，不是监测或 Drain 失败。

<!-- Modify record completed board 0.11-to-0.20 injection-rate comparison sweep, Michael Tan, 20260908 -->

## 2026-09-08 存储重排后的 0.10–0.20 等价性复核（进行中）

- 已确认重排后的 0.10 ILA-wrapper 回归保持 `enqueued=2525`、`tails=2525`、`total_latency=60569` 和零异常；现将保存重排前的 0.11–0.20 十点结果，并以同一 WSL 扫频脚本逐点复跑比较。仅补齐脚本对 ILA 调试包装模块的编译依赖，不改变注入、路由或统计行为。

<!-- Modify record start of traffic-generator storage refactor 0.10-to-0.20 equivalence recheck, Michael Tan, 20260908 -->

## 2026-09-08 存储重排后的 0.10–0.20 等价性复核完成

- 补齐 `scripts/simulation/run_tb_noc_board_latency_monitor_rate_sweep_011_to_020.sh` 对 `noc_board_ila_debug.sv` 的编译依赖后，使用 WSL Vivado 2025.2 执行 `bash scripts/simulation/run_tb_noc_board_latency_monitor_rate_sweep_011_to_020.sh`。新结果位于 `vivado_sim_wsl/tb_noc_board_latency_monitor_rate_sweep_011_to_020_sim/board_latency_results.txt`，十点全部 `PASSED`。
- 0.10 的 ILA-wrapper 基线仍为 `2525` 包、`60569` 总 cycles、`23.987` cycles；0.11–0.20 十点与重排前记录逐字段完全一致，平均延迟依次为 `28.149`、`37.650`、`57.399`、`85.318`、`125.131`、`168.746`、`215.469`、`265.748`、`322.862`、`371.774` cycles。各点均为 `enqueued==tails`，且 queue-full、未匹配、时间戳覆盖和 NoC 错误均为零；因此本次存储维度重排未改变功能或性能结果。

<!-- Modify record completed traffic-generator storage refactor 0.10-to-0.20 equivalence recheck, Michael Tan, 20260908 -->

## 2026-09-08 ILA 顶层 Windows 综合复测（进行中）

- 在尚未添加 XDC 前，使用 Windows Vivado 2019.2 对 `xcvu440-flga2892-2-e` 的 `noc_board_ila_top` 重新执行仅综合，量化重排后前端综合耗时，并检查 ILA IP、probe 连接和资源报告。不会运行实现、生成 bitstream 或修改 XDC。

<!-- Modify record start of post-storage-refactor Windows ILA-top synthesis measurement, Michael Tan, 20260908 -->

## 2026-09-08 ILA 顶层 Windows 综合复测结果

- Windows Vivado 2019.2 使用 `xcvu440-flga2892-2-e` 运行 `scripts/synthesis/run_noc_board_ila_top_synthesis.ps1`；ILA `ila_0` 的 16 个 probe IP 已成功生成并读入，但 `synth_design` 在 RTL 展开阶段失败，未进入网表优化或资源报告阶段。
- 失败耗时为 CPU `24 s`、墙钟 `27 s`、峰值内存约 `2381 MB`。根因是 `noc_board_latency_monitor.sv` 的 `enqueue_cycle` 单变量大小为 `25×2048×32=1,638,400 bits`，超过 Vivado 2019.2 的 `1,000,000-bit` 单变量上限（`Synth 8-4556`）。这不是 XDC、ILA probe 或功能仿真的问题；需将监测器时间戳表分成多个独立 bank 后再综合，且必须保持已验证的索引语义和 0.10–0.20 仿真结果。

<!-- Modify record failed post-storage-refactor Windows ILA-top synthesis measurement, Michael Tan, 20260908 -->

## 2026-09-08 监测器时间戳双 Bank 重构（进行中）

- 为消除 Vivado 2019.2 的单变量上限，仅将 `enqueue_cycle` 按 packet sequence 的最高位拆为两个 `25×1024×32` 位时间戳 bank；每个 bank 为 `819200 bits`。valid/measurement 表、包 ID、统计口径和流量发生器均不改。修改后依次复核 0.10 wrapper、0.11–0.20 扫频，再重跑 Windows 综合。
- WSL Vivado 2025.2 已通过 `bash scripts/simulation/run_tb_noc_board_ila_wrapper.sh` 与 `bash scripts/simulation/run_tb_noc_board_latency_monitor_rate_sweep_011_to_020.sh`：0.10 保持 `2525` 包、`60569` 总 cycles、`23.987` cycles；0.11–0.20 十点的所有包数、总延迟、平均延迟与既有表逐字段完全一致，所有异常计数仍为零。

<!-- Modify record start of monitor timestamp dual-bank synthesis-limit refactor, Michael Tan, 20260908 -->

## 2026-09-08 板级与性能 TB 对比图（进行中）

- 基于 `file/仿真分析/板级监测模块与性能TB_011至020注入率对比.md` 的十个实测点，新增可复用绘图脚本和双曲线 PNG，直观比较两种流量发生模型在 0.11–0.20 区间的平均延迟。

<!-- Modify record start of board-monitor and performance-TB comparison plot, Michael Tan, 20260908 -->

## 2026-09-08 板级与性能 TB 对比图完成

- 新增 `scripts/simulation/plot_board_monitor_vs_performance_tb_rate_011_to_020.py`；执行 `python3 scripts/simulation/plot_board_monitor_vs_performance_tb_rate_011_to_020.py` 后生成 `file/仿真分析/板级监测模块与性能TB_011至020注入率对比.png`。图像为 1100×719 RGB PNG，双曲线和图例分别标识板级 LFSR 与性能 TB `$urandom`，直观显示二者在 0.13–0.15 后的共同排队增长趋势。

<!-- Modify record completed board-monitor and performance-TB comparison plot, Michael Tan, 20260908 -->

- 同一脚本现额外生成 `file/仿真分析/板级监测模块与性能TB_010至017注入率对比放大图.png`，范围为 0.10–0.17、0–250 cycles，可清楚观察 0.13–0.15 的斜率增大与两种流量模型的差异。<!-- Modify add knee-focused board-monitor and performance-TB comparison plot, Michael Tan, 20260908 -->
- 同一脚本还生成 `file/仿真分析/板级监测模块与性能TB_000至016注入率对比图.png`，范围为 0–0.16、0–250 cycles；0–0.10 分别保持板级 `23.987` cycles 和性能 TB `22.565` cycles 的水平线，0.11 后使用实测点。<!-- Modify add pre-knee horizontal-reference comparison plot, Michael Tan, 20260908 -->
- 三张对比图已重绘为 800×800 的近似正方形 PNG，提高纵轴延迟变化的可读性。<!-- Modify use square comparison-plot geometry, Michael Tan, 20260908 -->

## 标准目录结构

以后新增或修改文件时，统一遵守下面的结构：

```text
noc-input-buffer/
├── src/          # 只放 SystemVerilog 设计/RTL 代码
│   └── board_ila/ # 预留给板级 ILA/调试 RTL，不放 Vivado 生成文件
├── constraints/  # 按开发板型号存放 XDC 约束及说明
├── testbench/    # 统一存放所有 SystemVerilog testbench
├── scripts/
│   ├── simulation/ # 仿真、编译检查和结果绘图脚本
│   └── synthesis/  # Windows Vivado 综合脚本
├── vivado_sim_windows/ # Windows Vivado 仿真结果
├── vivado_sim_wsl/     # WSL/Linux Vivado 仿真结果
└── vivado_synthesis_windows/ # Windows Vivado 综合结果
```

具体规则：

- `src/` 只放项目设计代码，不放 tb、脚本、日志、波形或 Vivado 生成文件。
- `src/board_ila/` 存放无 DDR 的上板 NoC/ILA RTL；当前已包含首版 `noc_board_ila_top.sv`，不存放 XDC、IP 生成物、日志或位流。//Modify add first DDR-free board top, Michael Tan, 20260804
- `constraints/` 已于 2026-08-03 创建；后续从官方工程取得 XDC 后，按 `constraints/<开发板型号>/` 存放。未确认实际开发板及其官方约束前，不自行填写具体管脚号。//Modify reserve board-constraint directory for planned ILA bring-up, Michael Tan, 20260803
- 所有 tb 文件直接放在顶层 `testbench/`，不要再创建 `src/tb/`、`test/tb/` 等目录。
- 仿真、编译检查和结果绘图脚本统一放在 `scripts/simulation/`；Windows Vivado 综合脚本统一放在 `scripts/synthesis/`。
- 每个 tb 使用独立结果目录：Windows 结果放 `vivado_sim_windows/<顶层模块名>_sim/`，WSL/Linux 结果放 `vivado_sim_wsl/<顶层模块名>_sim/`。
- Windows Vivado 综合结果放在 `vivado_synthesis_windows/<顶层模块名>_synthesis/`，与仿真结果分开保存。
- Windows Vivado 综合完成后，可将 `.log`、`.rpt`、`.tcl`、`.jou` 等可复用结果同步到 Linux 工作副本；`.dcp` checkpoint 文件只保留在 Windows 结果目录，不再复制到 Linux，避免重复占用磁盘空间。
- 新增实验时，tb、运行脚本和结果目录应使用一致的描述性名称，不能复用其他 tb 的结果目录。
- 仿真生成物不能散落到项目根目录、`src/` 或 `testbench/`。

对于顶层模块 `<top>`，统一使用下面的对应关系：

| 类型 | 路径 |
|---|---|
| testbench | `testbench/<top>.sv` |
| Windows 运行脚本 | `scripts/simulation/run_<top>.ps1` |
| Windows 仿真结果 | `vivado_sim_windows/<top>_sim/` |
| WSL 运行脚本 | `scripts/simulation/run_<top>.sh` |
| WSL 仿真结果 | `vivado_sim_wsl/<top>_sim/` |
| Windows 综合脚本 | `scripts/synthesis/run_<top>_synthesis.ps1` |
| Windows 综合结果 | `vivado_synthesis_windows/<top>_synthesis/` |

公共 PowerShell 脚本 `scripts/simulation/run_tb_mesh.ps1` 继续用于 Windows，并把结果写入 `vivado_sim_windows/`。WSL/Linux 使用独立 Bash 脚本和 `vivado_sim_wsl/`，避免覆盖 Windows 历史结果。

## 2026-07-29 脚本目录与综合规则

- 原有仿真、编译检查和结果绘图脚本已统一移入 `scripts/simulation/`，脚本内部的仓库根目录计算已同步调整。
- 已建立 `scripts/synthesis/`，用于后续 Windows Vivado 2019.2 综合脚本；本次未执行综合。
- Windows Vivado 综合结果统一保存到 `vivado_synthesis_windows/<top>_synthesis/`。
- 2026-07-29 已将 Linux 的 `scripts/` 镜像同步到 Windows 工作副本 `E:\Codex-Project\NoC-XY\scripts\`：Windows 旧的根目录平铺仿真脚本已移除，`simulation/` 和 `synthesis/` 目录结构及文件内容与 Linux 一致。

## 2026-07-29 首次 Windows RTL 综合任务

- 目标顶层：`mesh`；目标器件：`xcvu440-flga2892-2-e`。
- 已使用 Windows Vivado 2019.2 和 `scripts/synthesis/run_mesh_synthesis.ps1` 完成综合，只读取 `src/` 中的 RTL，不加入 `testbench/`。
- 结果目录：`vivado_synthesis_windows/mesh_synthesis/`（Windows 工作副本对应路径为 `E:\Codex-Project\NoC-XY\vivado_synthesis_windows\mesh_synthesis\`）；包含 `synthesis.log`、`utilization.rpt`、`timing_summary.rpt` 和 `mesh_synth.dcp`。
- 实际命令：

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File E:\Codex-Project\NoC-XY\scripts\synthesis\run_mesh_synthesis.ps1
```

- `synth_design` 成功完成：`0 errors`、`0 critical warnings`。默认 2×3 `mesh` 使用 30,498 LUT（1.20%）、22,081 个寄存器（0.44%）、0 BRAM、0 DSP；顶层直接暴露 NoC 接口，报告中的 542 IOB（37.23%）不代表最终板级 I/O 方案。
- 本次没有 `.xdc` 时钟/引脚约束，因此 `timing_summary.rpt` 只记录无约束路径，不能用于时序收敛结论；也没有生成 bitstream。综合警告主要提示结构体数组存储器未推断为 BRAM、而将实现为寄存器，后续板级设计时需要评估。

## 快速开始

进入项目并查看当前状态：

```bash
cd /home/tanma/Documents/Project/noc-input-buffer
git status --short
```

主要代码和结果位置：

- `src/`：只存放当前 NoC SystemVerilog 设计/RTL 代码。
- `testbench/`：各个独立测试场景的 testbench。
- `scripts/`：Windows PowerShell 仿真入口、WSL/Linux Bash 入口和环境设置脚本。
- `vivado_sim_windows/`：迁移来的 Windows 历史结果，以及以后由 PowerShell/Windows Vivado 生成的结果。
- `vivado_sim_wsl/`：WSL/Linux Vivado 仿真结果；当前已包含通过验证的 `tb_mesh_sim/` 基础结果。
- `constraints/soc_dcpu_j2/soc_dcpu_j2.xdc`：根据提供的 XDC 照片转写的板级约束；已确认 100 MHz 差分时钟为 `AT49/AU49`、低有效复位为 `R12`。端口前缀为小写字母 `l_pad_*`/`o_pad_*`，不是数字。照片在 DDR 标题处截断，未转写任何 DDR 管脚；该文件尚未接入新的板级顶层。
- `constraints/soc_dcpu_j2/soc_mult_cpu_top_port_reference.v.txt`：根据照片转写的 SoC 顶层端口与时钟参考片段，确认差分时钟通过 `IBUFDS` 接收；原 SoC 后续时钟生成依赖 DDR MIG 的 `ddr_ui_clk/ddr_ui_rst`，不能用于本项目的无 DDR 顶层。该文件不能参与本项目编译。//Modify record photo-transcribed board clock/reset top reference, Michael Tan, 20260803
- `constraints/noc_board_ila/constraints.md`：新的无 DDR NoC 上板约束目录说明。原 `soc_dcpu_j2` 文件保持参考性质；当前尚未新建 XDC。
- `src/board_ila/noc_board_ila_top.sv`：首版无 DDR 板级顶层，含差分时钟接收、复位同步和静默的 5×5/4VC NoC 实例。
- `project_*`：迁移过来的 Vivado 工程目录。
- `buffer/`：早期 input buffer 相关代码和分析材料；当前工作区内该目录已有删除项，处理前先看 Git 状态。
- `kpi/`：报告与绩效材料，不是当前 NoC RTL 主线。
- `AGENTS.md`：给 AI/Codex 使用的项目规则和交接记录。
- `README.md`：给你阅读的项目介绍、使用方法和历史进展。

只查看最近一次 4-flit 5x5 sweep 的结果：

```bash
sed -n '1,40p' vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_results.txt
```

开始修改前，建议先确认工作区已有改动，避免覆盖未提交内容：

```bash
git status --short
git diff --stat
```

## 你的代码标注规则

后续每次修改代码，都需要在修改处添加类似下面的注释：

```systemverilog
//Modify ..., Michael Tan, YYYYMMDD
```

如果是替换原代码，建议保留原代码并注释，例如：

```systemverilog
//old_code_here;//Original, Michael Tan, YYYYMMDD
new_code_here;//Modify ..., Michael Tan, YYYYMMDD
```

## 文档同步规则

后续每次开始新的代码功能修改、tb 文件设计，或者进行有意义的 Vivado 仿真时，都需要同步维护这两个文件：

- `AGENTS.md`：主要给新会话里的我读取，用来恢复上下文。
- `README.md`：主要给你查看，用中文记录当前进展。
- 每次执行新的仿真功能，都在 `testbench/` 新建 tb，在 `scripts/` 新建对应入口，并根据执行平台把独立结果放入 `vivado_sim_windows/` 或 `vivado_sim_wsl/`；不要直接改旧 tb。

每次任务完成后，需要把下面内容补充进去：

- 修改日期
- 修改了哪些文件
- 新增或修改了哪些 tb
- 使用的 Vivado 仿真命令
- 结果文件路径
- 关键仿真结果，例如是否通过、是否丢包、平均延迟是多少

这样以后新开会话或者回头检查项目时，你和我都能快速接上。

<!-- Modify add documentation synchronization rule for future code/tb/simulation tasks, Michael Tan, 20260626 -->

## 当前项目主线

项目用于研究和验证 NoC input buffer、连续 packet 传输以及注入率—平均延迟关系。最初的 2x3、0.1～0.5 注入率扫描已经完成，后续又完成了多组 5x5、Noxim-style、源队列、低注入率、拐点加密采样以及 4-flit packet 实验。

当前最新完成项是 4-flit、queue-based 的 5x5 knee sweep，并已在 WSL/Linux Vivado 2025.2 下重新跑通。项目目前没有仅由文档自动推导出的“待修改任务”；下一次应根据你的具体目标选择已有 tb，或者新建独立 tb 和结果目录。

## 已完成内容

1. 已经修改 input buffer / circular buffer 相关逻辑，使连续 packet 注入可以工作。
2. 已经通过 Vivado 仿真验证连续 packet 能正常接收。
3. 已经修复 `input_port_Xiugai2.sv` 中 crossbar 输出 flit 选择错误的问题。
4. 已经把 tb 文件统一放到 `testbench`。
5. 已经建立 Vivado 命令行仿真脚本，当前位置为 `scripts/`。
6. 已经建立 `tb_mesh_injection_sweep.sv`，用于扫注入率 0.1 到 0.5，并输出延迟结果。
7. 已经验证连续发送 8 个 packet 没有丢包。

## 重要修复记录

### 1. circular_buffer 声明顺序问题

文件：

```text
src/circular_buffer_Xiugai3.sv
```

问题：

Vivado 编译时，`read_ptr` 在声明前被使用，导致 `xvlog` 报错。

解决：

把下面这类赋值移动到 `read_ptr` 声明之后：

```systemverilog
assign first_flit_o = memory[read_ptr];
```

2026-08-25 已将该旧 `first_flit_o` 端口及其赋值注释：当前 `input_buffer` 使用的是 `data_o` 队首输出，旧 peek 接口没有实例连接。本次仅清理未使用接口，未重新运行 Vivado 仿真。

<!-- Modify record unused legacy circular-buffer peek cleanup, Michael Tan, 20260825 -->

### 2. input_port 输出 flit 和当前 VC 选择不一致

文件：

```text
src/input_port_Xiugai2.sv
```

原问题：

crossbar 输出 flit 使用的是上一拍寄存的 VC 选择：

```systemverilog
//xb_flit_o = data_out[sa_sel_vc_reg];//Original, Michael Tan, 20260617
```

修改后：

```systemverilog
xb_flit_o = data_out[sa_sel_vc_i];//Modify to align crossbar flit with current SA-selected VC, Michael Tan, 20260617
```

原因：

连续 packet 注入时，如果当前 SA 选择的 VC 和寄存的 VC 不一致，可能会输出错误 flit，表现为 TAIL 重复或 packet 顺序异常。

## 当前 tb 文件

tb 文件目录：

```text
testbench
```

主要 tb：

- `tb_mesh.sv`：基础 mesh packet 测试。
- `tb_mesh_two_packets.sv`：两个连续 packet，源节点和目的节点相同。
- `tb_mesh_two_distinct_packets.sv`：两个 packet，源节点和目的节点都不同。
- `tb_mesh_eight_packets.sv`：连续 8 个 packet 测试。
- `tb_mesh_injection_rate.sv`：单个注入率随机注入测试。
- `tb_mesh_injection_sweep.sv`：注入率 0.1 到 0.5 扫描测试。

## Vivado 仿真方法

Vivado 路径：

```text
E:\Vivado\Vivado\2019.2
```

主要脚本：

```text
scripts/simulation/run_tb_mesh.ps1
```

命令格式：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh.ps1 -TbFile <tb文件名>.sv -Top <顶层模块名>
```

运行注入率扫描 tb：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh.ps1 -TbFile tb_mesh_injection_sweep.sv -Top tb_mesh_injection_sweep
```

结果目录：

```text
vivado_sim_windows/tb_mesh_injection_sweep_sim
```

重要输出文件：

- `xsim.log`
- `out.vcd`
- `injection_latency_results.txt`

## 最近一次注入率-延迟结果

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_sim/injection_latency_results.txt
```

最近一次结果：

```text
injection_rate_permille injection_rate attempted injected blocked received avg_latency_cycles_x1000 error_count
100 0.100 550 550 0 550 6865 0
200 0.200 996 995 1 995 8014 0
300 0.300 1427 1314 113 1314 10861 0
400 0.400 1817 1420 397 1420 12369 0
500 0.500 2274 1447 827 1447 13490 0
```

解释：

- `avg_latency_cycles_x1000` 是平均延迟乘以 1000。
- 实际平均延迟 = `avg_latency_cycles_x1000 / 1000`。
- 最近一次仿真中，每个注入率下都是 `injected == received`。
- `error_count == 0`，说明没有检测到错误输出。

换算后的平均延迟：

```text
0.1 -> 6.865 cycles
0.2 -> 8.014 cycles
0.3 -> 10.861 cycles
0.4 -> 12.369 cycles
0.5 -> 13.490 cycles
```

## 当前注入率 tb 的行为

文件：

```text
testbench/tb_mesh_injection_sweep.sv
```

当前行为：

- 每个节点每个周期都按当前注入率独立尝试注入 packet。
- 源节点相当于是全节点随机注入。
- 目的节点随机选择。
- 目的节点不会等于源节点。
- 当前 packet 是 2 个 flit：HEAD + TAIL。
- 延迟统计口径是：从 packet 注入周期到 TAIL 到达周期。

注意：

之前 tb 有一个统计窗口问题：可能在发出 HEAD 后还没发 TAIL 就停止注入，造成假丢包。现在已经修复为：停止产生新 packet 后，先把已经开始的 packet 的 TAIL 发完，再 drain 网络并统计。

## 和 Noxim 对比时的不足

当前 tb 可以验证“注入率功能”和初步趋势，但还不是严格的 Noxim 风格性能评估。

后续建议补充：

- warm-up 阶段，不计入统计。
- 更长的 measurement 阶段。
- 可配置 packet 长度。
- 明确 packet injection rate 和 flit injection rate 的区别。
- 统计平均延迟时继续使用 cycle，不建议换成 ns。
- 网络规模最好从 2x3 扩展到 5x5。

Noxim 默认周期通常可理解为：

```text
clock_period_ps = 1000
1 cycle = 1 ns
```

但画性能曲线时，纵坐标通常仍然写 `Average delay (cycles)`。

## 5x5 扩展检查

当前 `src/noc.sv` 中已经是：

```systemverilog
localparam MESH_SIZE_X = 5;
localparam MESH_SIZE_Y = 5;
```

目的地址位宽是：

```systemverilog
localparam DEST_ADDR_SIZE_X = $clog2(MESH_SIZE_X);
localparam DEST_ADDR_SIZE_Y = $clog2(MESH_SIZE_Y);
```

所以地址位宽对 5x5 是够的。

需要注意的地方：

- `src/mesh.sv` 的默认参数还是 2x3。
- 很多 tb 文件默认参数还是 2x3。
- `tb_mesh.sv` 中有硬编码 `.MESH_SIZE_X(2)` 和 `.MESH_SIZE_Y(3)`。
- 如果只做注入率-延迟曲线，优先改 `testbench/tb_mesh_injection_sweep.sv`。

后续第一步可以先改：

```systemverilog
parameter MESH_SIZE_X = 5,
parameter MESH_SIZE_Y = 5,
```

然后重新跑 Vivado 仿真。

## 关于备份

你之前会手动备份整个 `test` 文件夹，例如：

```text
test - 20260622备份
```

后续更推荐使用 Git：

1. 每次修改前看状态：

```powershell
git status
```

2. 仿真通过后提交一次：

```powershell
git add test AGENTS.md README.md
git commit -m "Save current NoC simulation state"
```

这样每个 commit 就相当于一个可回退的备份点。

当前 Git 设置记录：

- 已添加 `.gitignore`，用于忽略 Vivado 生成文件、波形文件、仿真数据库、手动备份文件夹和 zip 压缩包。
- Git 主要跟踪源码、tb、仿真脚本和说明文档。
- `kpi/` 默认不提交，因为它更像报告/材料目录，不属于当前 NoC 源码备份。<!-- Modify clarify kpi folder is excluded from code backup, Michael Tan, 20260626 -->
- 当前已经初始化本地 Git 仓库，分支名是 `main`，第一次备份提交是 `8b2abe7 Initial NoC source backup`。<!-- Modify record completed local Git initialization, Michael Tan, 20260626 -->
- 当前已经绑定 GitHub 远程仓库 `origin`：`https://github.com/tanmaoju-oss/noc-input-buffer.git`，本地 `main` 已跟踪 `origin/main`。<!-- Modify record GitHub remote binding, Michael Tan, 20260626 -->
- `AGENTS.md` 和 `README.md` 需要随可复用项目状态变更提交并推送到 GitHub。<!-- Modify change documentation GitHub tracking policy, Michael Tan, 20260729 -->
- 以后用户要求将变更 Git 提交并推送到远程仓库时，也要同步拉取到 Windows 目录 `E:\\Codex-Project\\NoC-XY`，并确认该工作副本已更新到对应提交。<!-- Modify add Git-to-Windows repository synchronization rule, Michael Tan, 20260729 -->
- 如果本机没有配置 Git 用户名和邮箱，可以先在当前仓库内使用：

```powershell
git config user.name "Michael Tan"
git config user.email "tanma@local"
```

后续如果要推送到 GitHub，可以再换成 GitHub 对应邮箱。

<!-- Modify add current Git setup notes, Michael Tan, 20260626 -->

## 2026-06-29 继续任务：5x5 注入率-延迟 sweep

本次继续当前主线目标：保留原来的 `testbench/tb_mesh_injection_sweep.sv` 作为 2x3 sweep，新建单独的 5x5 sweep tb 和对应仿真入口。

计划使用的 Vivado 仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5.ps1
```

预期结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_sim/injection_latency_results.txt
```

<!-- Modify record start of 5x5 injection sweep continuation task, Michael Tan, 20260629 -->

## 2026-06-29 5x5 sweep 仿真结果

本次新增/修改文件：

```text
testbench/tb_mesh_injection_sweep_5x5.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5.ps1
```

修改内容：原来的 `testbench/tb_mesh_injection_sweep.sv` 保持 2x3 不变；新增 `tb_mesh_injection_sweep_5x5.sv`，top module 为 `tb_mesh_injection_sweep_5x5`，并新增专用仿真脚本，使结果进入独立的 `tb_mesh_injection_sweep_5x5_sim` 目录。

Vivado 仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5.ps1
```

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_sim/injection_latency_results.txt
```

最新 5x5 结果：

```text
injection_rate_permille injection_rate attempted injected blocked received avg_latency_cycles_x1000 error_count
100 0.100 2324 2321 3 2321 11189 0
200 0.200 4299 3694 605 3694 19317 0
300 0.300 6304 3923 2381 3923 24565 0
400 0.400 8355 3983 4372 3983 26400 0
500 0.500 10504 3965 6539 3965 27182 0
```

换算后的平均延迟：

```text
0.1 -> 11.189 cycles
0.2 -> 19.317 cycles
0.3 -> 24.565 cycles
0.4 -> 26.400 cycles
0.5 -> 27.182 cycles
```

结论：5x5 sweep 已经完整跑通；每个注入率下都是 `injected == received`，并且 `error_count == 0`。

<!-- Modify record completed 5x5 injection sweep simulation results, Michael Tan, 20260629 -->

## 2026-06-29 继续任务：Noxim-style 5x5 sweep

本次新增一个更接近 Noxim 统计口径的 5x5 注入率-延迟 sweep，不修改已有 2x3 tb，也不修改已有普通 5x5 tb。

计划新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_style.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

目标统计方式：

```text
warm-up 阶段：产生 traffic，但不统计延迟
measurement 阶段：继续产生 traffic，只统计这段时间注入的 packet
drain 阶段：停止产生新 packet，把 measurement 阶段注入的 packet 收完
```

计划仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

<!-- Modify record start of Noxim-style 5x5 sweep task, Michael Tan, 20260629 -->

## 2026-06-29 Noxim-style 5x5 sweep 仿真结果

本次新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_style.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

已有的 2x3 tb 和普通 5x5 tb 没有修改。

当前默认周期设置：

```text
warm-up:     200 cycles
measurement: 1000 cycles
drain:       3000 cycles
```

统计口径：

```text
warm-up 阶段产生 traffic，但不计入平均延迟。
measurement 阶段继续产生 traffic，只统计这段时间注入的 packet。
drain 阶段停止产生新 packet，只用于等待 measurement 阶段注入的 packet 到达。
```

Vivado 仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_style_sim/injection_latency_results.txt
```

最新结果：

```text
injection_rate_permille injection_rate warmup_cycles measure_cycles drain_cycles measure_attempted measure_injected measure_blocked measure_received avg_latency_cycles_x1000 error_count
100 0.100 200 1000 3000 2286 2283 3 2283 11219 0
200 0.200 200 1000 3000 4265 3689 576 3689 19164 0
300 0.300 200 1000 3000 6300 3769 2531 3769 24906 0
400 0.400 200 1000 3000 8481 3919 4562 3919 26224 0
500 0.500 200 1000 3000 10405 3944 6461 3944 27113 0
```

换算后的平均延迟：

```text
0.1 -> 11.219 cycles
0.2 -> 19.164 cycles
0.3 -> 24.906 cycles
0.4 -> 26.224 cycles
0.5 -> 27.113 cycles
```

结论：Noxim-style 5x5 sweep 已经完整跑通；每个注入率下都是 `measure_injected == measure_received`，并且 `error_count == 0`。

补充：之前尝试过更长的 `1000 warm-up + 5000 measurement + 10000 drain`，可以编译并开始运行，但默认迭代太慢，6 分钟只跑完 0.1 和 0.2 两个注入率。因此当前默认周期先采用较短但完整可验证的版本。后续若要做正式论文风格曲线，可以再新建一个 long-run tb 或 long-run 仿真入口。

<!-- Modify record completed Noxim-style 5x5 sweep simulation results, Michael Tan, 20260629 -->

## 2026-07-01 继续任务：queue 版 Noxim-style 5x5 sweep

本次继续改进曲线形状，新增一个 source queue 版 Noxim-style 5x5 sweep。仍然不修改 RTL 源设计文件，只新增 tb 和仿真脚本。

计划新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

目标行为：

```text
每个节点在 tb 侧有 source queue。
packet 生成后先进入 source queue。
如果 router 暂时不能接收，packet 留在 source queue 等待，不直接丢弃或只记 blocked。
measurement packet 的 latency 从生成时间开始算，到 TAIL 到达结束。
```

计划仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

<!-- Modify record start of queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260701 -->

## 2026-07-01 queue 版 Noxim-style 5x5 sweep 仿真结果

本次新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

注意：本次没有修改 RTL 源设计文件，source queue 只写在 tb 的 traffic generator 里。

当前参数：

```text
warm-up:       200 cycles
measurement:   1000 cycles
drain limit:   8000 cycles
source queue:  2048 entries per node
```

统计口径：

```text
packet 在 measurement 阶段生成后进入 source queue。
如果 router 暂时不能接收，packet 留在 source queue 等待。
latency 从 packet 生成时间开始算，到 TAIL 到达结束。
```

Vivado 仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_sim/injection_latency_results.txt
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_sim/injection_latency_curve.png
```

最新结果：

```text
injection_rate_permille injection_rate warmup_cycles measure_cycles drain_limit_cycles drain_used_cycles measure_generated measure_enqueued measure_queue_full measure_injected measure_received max_source_queue avg_latency_cycles_x1000 error_count
100 0.100 200 1000 8000 19 2513 2513 0 2513 2513 4 12007 0
200 0.200 200 1000 8000 581 5023 5023 0 5023 5023 109 210522 0
300 0.300 200 1000 8000 1450 7497 7497 0 7497 7497 221 657669 0
400 0.400 200 1000 8000 2058 10029 10029 0 10029 10029 353 1099917 0
500 0.500 200 1000 8000 2828 12422 12422 0 12422 12422 451 1488601 0
```

换算后的平均延迟：

```text
0.1 -> 12.007 cycles
0.2 -> 210.522 cycles
0.3 -> 657.669 cycles
0.4 -> 1099.917 cycles
0.5 -> 1488.601 cycles
```

结论：queue 版 Noxim-style 5x5 sweep 已经完整跑通；每个注入率下都是 `measure_injected == measure_received`，`measure_queue_full == 0`，并且 `error_count == 0`。相比前一个 blocked/drop 口径版本，这个版本因为 packet 会在 source queue 里等待，所以延迟曲线出现明显陡升，更接近 Noxim 饱和前后的排队效果。

<!-- Modify record completed queue-based Noxim-style 5x5 sweep simulation results, Michael Tan, 20260701 -->

## 2026-07-09 继续任务：加入 0.1 之前低注入率点

本次基于 queue 版 Noxim-style 5x5 测试新建一版，不修改已有 queue tb，也不修改 RTL 源设计文件。

目标：在原来 0.1 到 0.5 的基础上，增加 0.1 之前的低注入率点，用来观察理论上低负载区域平均延迟是否接近水平。

计划新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1
```

计划注入率：

```text
0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.20, 0.30, 0.40, 0.50
```

<!-- Modify record start of low-rate queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260709 -->

## 2026-07-09 低注入率 queue 版仿真结果

本次新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1
```

本次没有修改 RTL 源设计文件，也没有修改已有 queue 版 tb；是在 queue 版基础上新建一版，增加 0.1 之前的低注入率点。

仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1
```

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_results.txt
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_curve_full.png
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_curve_lowrate_zoom.png
```

最新结果：

```text
injection_rate avg_latency_cycles
0.010 9.724
0.020 10.109
0.030 9.854
0.040 10.204
0.050 10.268
0.060 10.503
0.070 10.839
0.080 11.143
0.090 11.602
0.100 11.903
0.200 194.311
0.300 671.800
0.400 1080.137
0.500 1540.083
```

完整结果中每个注入率下均满足：

```text
measure_injected == measure_received
measure_queue_full == 0
error_count == 0
```

结论：0.01 到 0.10 的低注入率区域平均延迟基本在 10 到 12 cycles 附近，接近理论上的低负载水平区域；0.20 以后 source queue 排队明显增加，平均延迟快速上升。

<!-- Modify record completed low-rate queue-based Noxim-style 5x5 sweep simulation results, Michael Tan, 20260709 -->

## 2026-07-09 继续任务：加密饱和拐点附近注入率

本次基于低注入率 queue 版再新建一版，不修改已有 tb，也不修改 RTL 源设计文件。

目标：在 0.10 到 0.30 附近增加更多注入率点，用来检查高注入率段看起来接近直线，是不是因为原来的采样点太稀。

计划新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1
```

计划注入率：

```text
0.01, 0.03, 0.05, 0.07, 0.09, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20, 0.22, 0.24, 0.26, 0.28, 0.30, 0.35, 0.40, 0.45, 0.50
```

<!-- Modify record start of knee-rate queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260709 -->

## 2026-07-09 加密拐点注入率仿真结果

本次新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1
```

本次没有修改 RTL 源设计文件，也没有修改已有 queue 版 tb；是在 0.10 到 0.30 附近增加更多注入率点，用来观察饱和拐点。

仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1
```

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_results.txt
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_curve_full.png
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_curve_knee_zoom.png
```

最新结果：

```text
injection_rate avg_latency_cycles
0.010 9.724
0.030 9.962
0.050 10.308
0.070 10.801
0.090 11.374
0.100 11.923
0.120 13.852
0.140 20.497
0.160 51.046
0.180 111.037
0.200 199.594
0.220 310.151
0.240 418.607
0.260 444.717
0.280 553.714
0.300 614.892
0.350 831.810
0.400 1064.048
0.450 1331.869
0.500 1560.861
```

完整结果中每个注入率下均满足：

```text
measure_injected == measure_received
measure_queue_full == 0
error_count == 0
```

结论：加密采样后可以看到延迟拐点大约从 0.14 到 0.18 附近开始出现，0.18 之后进入明显排队增长区。之前 0.2、0.3、0.4、0.5 看起来接近直线，主要是采样点太稀导致曲线细节不明显。

<!-- Modify record completed knee-rate queue-based Noxim-style 5x5 sweep simulation results, Michael Tan, 20260709 -->

## 2026-07-09 继续任务：4-flit packet 的 queue knee 版本

本次基于加密拐点的 queue 版再新建一版，不修改已有 tb，也不修改 RTL 源设计文件。

目标：把 packet 长度从当前 2 flit 改为 4 flit，用来观察 packet 变长后注入率-平均延迟曲线的变化。

计划 packet 格式：

```text
HEAD + BODY + BODY + TAIL
```

计划新增文件：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1
```

统计口径保持 packet latency：从 packet 生成时间开始，到 TAIL flit 到达目的节点结束。

<!-- Modify record start of 4-flit queue-based Noxim-style 5x5 knee sweep task, Michael Tan, 20260709 -->

## 2026-06-29 MBO 文档当前进度

当前最新 MBO 文件：

```text
kpi/MBO/MBO-7月-v0.5.docx
```

当前 MBO 已迭代到 v0.5。后续下个月再写 MBO 时，以 v0.5 的写法和口径作为参考。

当前 v0.5 的前三个指标名称：

```text
1. 注入率功能逻辑设计和逻辑代码编写
2. 随机模式流量测试场景的逻辑设计和代码编写
3. 流量场景仿真验证与结果分析
```

后续写 MBO 时注意：

- 不要把“进度梳理”“进度保留”“为后续保留可复用进度”写进 MBO，这些属于自己的工作记录。
- 不要把中间过程写成 MBO 衡量标准，例如具体仿真目录、`xsim.log`、`out.vcd`、具体结果文件名等。
- 不要过细列出统计字段名，例如 `attempted`、`blocked`、`received`、`avg_latency` 等。
- 当前阶段先不体现延迟统计功能；v0.5 已去掉“平均延迟”“延迟统计”“avg_latency”“性能结果”等表述。
- 除非后续明确要求，不要在 MBO 中写 `5x5` 或 `Noxim`。
- 第三项仍然以“仿真与验证”为主，但标题要和第二项区分开，不要都写成随机流量测试场景。
- MBO 表述尽量写目标、结果和验收，不写工作意义和内部过程。

v0.5 已完成 docx 结构和文本检查；当前环境缺少 `soffice`，所以没有完成 Word 页面渲染检查。

<!-- Modify record latest MBO v0.5 status and future MBO writing preferences, Michael Tan, 20260629 -->

## 2026-06-29 MBO v0.7 更新

当前最新 MBO 文件已更新为：

```text
kpi/MBO/MBO-7月-v0.7.docx
```

本次根据领导反馈调整：

- 第一项改为代码优化方向：`注入率控制与统计逻辑代码优化`。
- 第二项改为代码优化和流量模式扩展方向：`多流量模式测试场景代码优化`。
- 在随机流量模式之外，增加 `定向流量模式`，避免流量模式过少。
- 第三项仿真验证表述同步为 `随机及定向流量模式`。
- 后续继续保持 MBO 口径：写代码优化、场景覆盖、仿真验证和验收结果，不写过细的文件、日志、目录等中间过程。

<!-- Modify record latest MBO v0.7 after leader feedback on traffic modes and code optimization wording, Michael Tan, 20260629 -->

## 2026-06-29 MBO v0.8 结构调整

当前最新 MBO 文件已更新为：

```text
kpi/MBO/MBO-7月-v0.8.docx
```

当前前三项逻辑线条：

```text
1. 流量测试代码设计与优化
2. 流量场景仿真验证与结果分析
3. NoC设计逻辑代码优化
```

本次调整原则：

- 第一项合并原来的第一、第二项，写测试代码的设计和优化，包括注入率配置优化、多模式注入功能实现。
- 第二项写基于优化后的测试代码开展仿真验证。
- 第三项新写为基于仿真验证结果，反推 `src` 目录下 NoC 设计逻辑相关 SystemVerilog 代码优化。
- MBO 里不要直接写“20个 sv 文件”，用“src目录下NoC设计逻辑相关SystemVerilog代码”这种表述。

<!-- Modify record latest MBO v0.8 structure: test code optimization, simulation verification, design logic optimization, Michael Tan, 20260629 -->

## 2026-07-01 2x3 四 flit packet 注入率 sweep 任务

本次先回到 2x3 仿真，不继续关注 5x5。目标是在不修改原有 2-flit baseline tb 的前提下，新建一个专用 tb，把 packet 格式规范为可配置长度：

```text
HEAD + (PACKET_FLIT_NUM - 2) 个 BODY + TAIL
```

本次先设置：

```text
PACKET_FLIT_NUM = 4
packet = HEAD + BODY + BODY + TAIL
```

计划新增文件：

```text
testbench/tb_mesh_injection_sweep_2x3_n4.sv
scripts/simulation/run_tb_mesh_injection_sweep_2x3_n4.ps1
```

计划仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_2x3_n4.ps1
```

预期结果目录：

```text
vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim
```

<!-- Modify record start of 2x3 four-flit packet sweep task, Michael Tan, 20260701 -->

## 2026-07-01 2x3 四 flit packet 注入率 sweep 仿真结果

本次新增文件：

```text
testbench/tb_mesh_injection_sweep_2x3_n4.sv
scripts/simulation/run_tb_mesh_injection_sweep_2x3_n4.ps1
```

关键行为：

```text
原 2x3 baseline tb 保持不变。
新 tb 使用 PACKET_FLIT_NUM 配置 packet 长度。
当前 PACKET_FLIT_NUM = 4，即 HEAD + BODY + BODY + TAIL。
monitor 会检查 TAIL 前收到的 BODY 数量是否等于 PACKET_FLIT_NUM - 2。
```

Vivado 仿真命令：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_2x3_n4.ps1
```

结果目录：

```text
vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim
```

结果文件：

```text
vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/injection_latency_results.txt
vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/xsim.log
vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/out.vcd
```

最新结果：

```text
packet_flit_num injection_rate_permille injection_rate attempted injected blocked received avg_latency_cycles_x1000 error_count
4 100 0.100 457 457 0 457 10008 0
4 200 0.200 780 732 48 732 12596 0
4 300 0.300 1032 829 203 829 14498 0
4 400 0.400 1361 865 496 865 15662 0
4 500 0.500 1569 889 680 889 16068 0
```

结论：2x3、四 flit packet 的注入率 sweep 已跑通；每个注入率下 `injected == received`，`error_count == 0`。换算后的平均延迟分别为 10.008、12.596、14.498、15.662、16.068 cycles。日志未发现 `ERROR:`、`CRITICAL WARNING` 或 `$error`，只有已有类型的 timescale warning。

<!-- Modify record completed 2x3 four-flit packet sweep simulation results, Michael Tan, 20260701 -->

## 2026-07-09 5x5 queue knee 的 4-flit packet 版本结果

本次基于前一个 queue knee 版本，新建了 4-flit packet 的独立 tb，没有修改原来的 2-flit tb，也没有修改 RTL 源设计文件。

新增文件：
```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1
```

packet 格式：
```text
HEAD + BODY + BODY + TAIL
```

统计方式：
```text
横轴仍然是 packet 注入率，也就是每个节点每个周期生成 packet 的概率。
纵轴是 packet latency，从 packet 生成进入源队列开始，到 TAIL flit 到达目的节点为止。
BODY flit 只检查目的节点是否正确，不单独统计延迟。
```

仿真命令：
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1
```

结果目录：
```text
vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim
```

主要结果文件：
```text
injection_latency_results.txt
xsim.log
injection_latency_curve_full.png
injection_latency_curve_knee_zoom.png
injection_latency_curve_compare_2flit_4flit.png
```

关键结果：
```text
rate latency_cycles injected received queue_full errors
0.010 11.926 218 218 0 0
0.030 12.885 717 717 0 0
0.050 14.321 1246 1246 0 0
0.070 17.837 1726 1726 0 0
0.090 32.167 2272 2272 0 0
0.100 43.648 2508 2508 0 0
0.120 144.500 3013 3013 0 0
0.140 322.095 3549 3549 0 0
0.160 443.284 3953 3953 0 0
0.200 708.787 5017 5017 0 0
0.300 1328.675 7406 7406 0 0
0.400 2059.889 9894 9894 0 0
0.500 2863.854 12588 12588 0 0
```

结论：
```text
20 个注入率点全部完成。
每个点都是 injected == received，queue_full == 0，error_count == 0。
和 2-flit packet 相比，4-flit packet 的曲线更早上升，整体延迟更高。
原因是横轴仍按 packet 注入率计算，但每个 packet 占用的 flit 带宽增加，所以网络更早接近饱和。
```

<!-- Modify record completed 4-flit 5x5 queue knee simulation result and curve conclusion, Michael Tan, 20260709 -->

## 2026-07-13 WSL/Linux 环境迁移

本次把项目从 Windows 桌面目录迁移到 WSL2 的 Linux 文件系统后，完成了以下文档整理：

- `Remember.md` 更名为 `AGENTS.md`，作为 AI/Codex 的项目规则与交接说明。
- `项目说明.md` 更名为 `README.md`，作为给用户阅读的中文项目介绍和使用指南。
- 文档内的项目路径改为 `/home/tanma/Documents/Project/noc-input-buffer`。
- 明确区分 Windows 历史仿真结果和未来在 WSL/Linux 中重新运行的结果。
- 本次没有修改 RTL、testbench、仿真脚本或已有仿真结果。

## 2026-07-13 项目更名

项目目录由不易记忆的 `6.input_buffer` 更名为 `noc-input-buffer`。新名称采用常见的全小写 kebab-case 形式，能够直接表达项目内容，并与 GitHub 远程仓库名称保持一致。

当前标准路径：

```text
/home/tanma/Documents/Project/noc-input-buffer
```

## 2026-07-13 目录结构调整

项目目录已经按职责拆分：

- 设计/RTL `.sv` 文件：`src/`
- testbench：`testbench/`
- Vivado/自动化脚本：`scripts/`
- Windows 仿真结果：`vivado_sim_windows/`
- WSL/Linux 仿真结果：`vivado_sim_wsl/`

两份 Markdown 中的旧路径已同步为新结构。随后又把 PowerShell 脚本独立移动到 `scripts/`，并修正了共享脚本的相对路径。

## 2026-07-13 脚本与仿真结果分离

- 顶层 PowerShell 脚本已从原 `vivado_sim/` 移到 `scripts/`。
- `scripts/simulation/run_tb_mesh.ps1` 统一从 `src/` 和 `testbench/` 取文件，并将结果写入 `vivado_sim_windows/<top>_sim/`。
- `scripts/simulation/run_design_compile.ps1` 从 `src/` 编译设计代码，并将结果写入 `vivado_sim_windows/design_compile/`。
- 已为原先缺少专用入口的 6 个 tb 补充轻量级包装脚本；当前每个 `testbench/<top>.sv` 都有对应的 `scripts/simulation/run_<top>.ps1`。`tb_mesh` 直接使用公共脚本的默认参数。
- 如果某个结果目录尚不存在，对应脚本会在第一次运行时创建 `vivado_sim_windows/<top>_sim/`。
- 当前完成了静态路径检查，真实 Vivado 仿真仍待工具环境就绪后验证。

## 2026-07-13 Windows 与 WSL 仿真结果分离

- 原 `vivado_sim/` 已更名为 `vivado_sim_windows/`，保留所有 Windows Vivado 历史结果。
- 新建对应的 `vivado_sim_wsl/`，专门用于以后 WSL/Linux Vivado 的仿真结果。
- 当前 `.ps1` 脚本默认写入 `vivado_sim_windows/`。
- 未来新增 Linux/Bash 仿真脚本时，必须默认写入 `vivado_sim_wsl/`，不能覆盖 Windows 历史结果。

## 2026-07-13 清理旧 `buffer/` 目录

- 已删除顶层旧 `buffer/` 目录及其中被 Git 跟踪的历史副本和说明文件。
- 当前有效 RTL、testbench 和项目文档仍分别保存在 `src/`、`testbench/`、`AGENTS.md` 与 `README.md` 中。
- 本次清理没有修改有效 RTL、testbench 或仿真结果。

<!-- Modify record removal of obsolete buffer directory and Markdown synchronization, Michael Tan, 20260713 -->

## 2026-07-14 首次可复现 WSL tb_mesh 仿真任务开始

本次任务计划：

- 新增 Linux/Bash 入口 `scripts/simulation/run_tb_mesh.sh`。
- 保留现有 Windows PowerShell 脚本不变。
- 使用 Linux Vivado 2025.2 重新仿真现有 `testbench/tb_mesh.sv`。
- 把可复用结果保存到 `vivado_sim_wsl/tb_mesh_sim/`。
- Codex 执行 xsim 时使用获准的沙箱外运行方式，避免再次遇到由命令沙箱导致的 `unexpected exception` 假失败。
- 仿真后检查 `xvlog.log`、`xelab.log`、`xsim.log` 和 `out.vcd`，再把结果同步到两份 Markdown。

计划命令：

```bash
bash scripts/simulation/run_tb_mesh.sh
```

<!-- Modify record start of first reproducible WSL/Linux tb_mesh simulation task, Michael Tan, 20260714 -->

## 2026-07-14 首次可复现 WSL tb_mesh 仿真完成

本次新增脚本：

```text
scripts/simulation/run_tb_mesh.sh
```

运行环境：

```text
WSL2 / Ubuntu 24.04
Vivado 2025.2
/home/tanma/tools/Xilinx/2025.2/Vivado
```

运行命令：

```bash
bash scripts/simulation/run_tb_mesh.sh
```

脚本会从 `src/` 按固定顺序编译 RTL，从 `testbench/tb_mesh.sv` 读取顶层 tb，并把生成文件隔离到：

```text
vivado_sim_wsl/tb_mesh_sim/
```

主要结果文件：

```text
vivado_sim_wsl/tb_mesh_sim/xvlog.log
vivado_sim_wsl/tb_mesh_sim/xelab.log
vivado_sim_wsl/tb_mesh_sim/xsim.log
vivado_sim_wsl/tb_mesh_sim/out.vcd
vivado_sim_wsl/tb_mesh_sim/tb_mesh_sim.wdb
```

验证结果：

```text
[TB_MESH] output flit 0 at (1,2): label=0 vc=0 time=96000
[TB_MESH] output flit 1 at (1,2): label=2 vc=0 time=106000
[TB_MESH] PASSED
$finish called at time : 135 ns
```

`out.vcd` 大小为 391352 bytes。检查 `xvlog.log`、`xelab.log` 和 `xsim.log` 后，未发现 `ERROR:`、`CRITICAL WARNING`、`$error` 或 `FAILED`。当前仍有 `mesh.sv` generate/array interface connection、部分模块缺少 timescale，以及 `LIBRARY_PATH` 的既有 warning，但没有影响本次测试通过。

### Codex 沙箱注意事项

此前所有依赖已经安装、`xvlog` 和 `xelab` 均成功时，沙箱内 xsim 仍会在加载快照时报告：

```text
ERROR: unexpected exception when evaluating tcl command
```

同一个快照在获准的沙箱外运行后立即通过，因此本环境中这个特定错误确认来自 Codex 命令沙箱，不是 RTL、许可证或缺库问题。以后由 Codex 执行仿真时，直接使用已批准的沙箱外命令：

```bash
bash scripts/simulation/run_tb_mesh.sh
```

该命令的批准前缀已经保存。仿真完成后仍需检查结果目录中的日志和输出文件，不能只看终端返回。

本次没有修改 RTL 或 testbench。

<!-- Modify record verified WSL Vivado 2025.2 tb_mesh result and sandbox execution rule, Michael Tan, 20260714 -->

## 2026-07-14 WSL 重新运行 4-flit 5x5 queue-knee sweep 任务开始

本次目标是把此前只在 Windows Vivado 下完成的下面这个实验，在当前 WSL/Linux Vivado 2025.2 环境重新跑通：

```text
testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv
```

本次保持原 tb、RTL、PowerShell 脚本和 Windows 历史结果不变，新增：

```text
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh
```

计划命令：

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh
```

WSL/Linux 独立结果目录：

```text
vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/
```

完成后需要验证 20 个注入率点全部输出，并检查 `measure_injected == measure_received`、`measure_queue_full == 0`、`error_count == 0`。Codex 运行脚本时继续使用已确认有效的沙箱外执行方式。

<!-- Modify record start of WSL reproduction for 4-flit 5x5 queue-knee sweep, Michael Tan, 20260714 -->

## 2026-07-14 WSL 4-flit 5x5 queue-knee sweep 完成

本次新增 Linux 脚本：

```text
scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh
```

原有 tb、`src/` 下 RTL、PowerShell 入口和 Windows 历史结果均未修改。

运行命令：

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh
```

WSL/Linux 结果目录：

```text
vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/
```

主要结果文件：

```text
injection_latency_results.txt
xvlog.log
xelab.log
xsim.log
out.vcd
tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim.wdb
```

Linux Vivado 2025.2 结果：

```text
rate latency_cycles injected received queue_full errors
0.010 11.953 235 235 0 0
0.030 12.921 739 739 0 0
0.050 14.762 1248 1248 0 0
0.070 18.578 1744 1744 0 0
0.090 37.283 2303 2303 0 0
0.100 61.024 2545 2545 0 0
0.120 176.726 3014 3014 0 0
0.140 316.597 3593 3593 0 0
0.160 412.535 4020 4020 0 0
0.180 551.897 4462 4462 0 0
0.200 712.666 5029 5029 0 0
0.220 856.253 5572 5572 0 0
0.240 987.239 6132 6132 0 0
0.260 1079.501 6453 6453 0 0
0.280 1293.909 6975 6975 0 0
0.300 1405.161 7499 7499 0 0
0.350 1846.494 8946 8946 0 0
0.400 2139.670 10089 10089 0 0
0.450 2558.392 11288 11288 0 0
0.500 2876.995 12530 12530 0 0
```

验证结论：

- 20 个注入率点全部完成，结果文件共有 1 行表头和 20 行数据。
- 自动逐行校验得到 `data_rows=20`、`bad_rows=0`。
- 每一点均满足 `measure_injected == measure_received`、`measure_queue_full == 0`、`error_count == 0`。
- 仿真在 586175 ns 正常 `$finish`；xsim 显示运行约 11 分 31 秒，峰值内存约 1450 MB。
- `out.vcd` 大小为 2154609075 bytes，整个结果目录约 2.1 GB。
- 三个日志未发现 `ERROR:`、`CRITICAL WARNING`、`$error`、`FAILED` 或 `FATAL`；已有 interface、timescale 和 `LIBRARY_PATH` warning 没有影响仿真通过。

### 与 Windows 2019.2 结果的区别

同一个 tb 和 seed 在 Linux Vivado 2025.2 下得到的具体 packet 数量与延迟数值和 Windows Vivado 2019.2 历史结果不完全相同。较可能的原因是 Vivado 版本或平台不同导致 SystemVerilog `$urandom` 随机序列实现存在差异。两次结果的关键验收条件一致：没有丢包、没有源队列满、没有错误，而且 4-flit 延迟曲线的拐点和高负载增长趋势一致。

该 Linux 脚本的沙箱外执行批准前缀已经保存，以后 Codex 可直接复用命令重新仿真，并在完成后检查结果表和日志。

<!-- Modify record completed Linux Vivado 2025.2 reproduction of 4-flit 5x5 queue-knee sweep, Michael Tan, 20260714 -->

## 2026-07-14 WSL 4-flit queue-knee 延迟曲线绘图任务开始

本次将使用刚生成的 WSL/Linux `injection_latency_results.txt` 绘制完整曲线：横坐标为 packet 注入率，纵坐标为平均 packet latency（cycles）。图片将参照 Windows 版的蓝色折线、圆点和网格样式，保存为：

```text
vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_curve_full.png
```

<!-- Modify record start of WSL 4-flit queue-knee latency plot task, Michael Tan, 20260714 -->

## 2026-07-14 WSL 4-flit queue-knee 延迟曲线完成

新增可复用绘图脚本：

```text
scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.py
```

运行命令：

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.py
```

生成图片：

```text
vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_curve_full.png
```

图片横坐标为 `Injection rate (packet/cycle/node)`，纵坐标为 `Average packet latency (cycles)`，包含 WSL 结果表中的全部 20 个点。样式参照 Windows 版，使用蓝色折线、圆点和灰色网格。

图片尺寸为 1100×719，文件大小为 47828 bytes。绘图脚本使用系统已有的 Graphviz `neato` 和 Python 标准库，不依赖 matplotlib。目视检查确认曲线低负载区域较平缓，约在 0.10 后进入拐点区域，高负载延迟持续上升。

<!-- Modify record generated and verified WSL 4-flit injection-latency curve, Michael Tan, 20260714 -->

## 2026-07-14 WSL 4-flit queue-knee 前 0.16 放大图任务开始

本次扩展现有绘图脚本，增加和 Windows 版对应的 `injection_latency_curve_knee_zoom.png`：横坐标范围 0～0.16，纵坐标范围 0～500 cycles，显示 WSL 结果中 0.01～0.16 的 9 个点，同时保留完整曲线的生成。

## 2026-07-14 WSL 4-flit queue-knee 前 0.16 放大图完成

生成命令：

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.py
```

生成文件：

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_curve_knee_zoom.png`

图像横坐标为注入率 0.00～0.16，纵坐标为平均延迟 0～500 cycles，包含 Linux/WSL 仿真的 9 个点：0.01、0.03、0.05、0.07、0.09、0.10、0.12、0.14、0.16。图像为 1100 x 719 的 RGB PNG，大小 45,412 字节。已目视检查，坐标范围、蓝色折线与圆点、网格样式均与 Windows 版拐点放大图对应，并清楚显示 0.10 之后的延迟拐点。同一绘图脚本现在会同时重新生成全范围图和前 0.16 注入率放大图。

<!-- Modify record completed WSL 4-flit queue-knee zoom plot, Michael Tan, 20260714 -->

## 2026-07-15 四虚拟通道 RTL 任务开始

本次任务把当前 NoC 从 2 个虚拟通道扩展为 4 个。修改前先检查 VC 编号宽度、输入缓冲、VC 分配器和交换分配器，不能只根据全局常量可参数化就直接判定正确。现有 tb 保持不变，新增独立简单测试 `testbench/tb_mesh_4vc_simple.sv`，明确测试 VC0、VC1、VC2、VC3；新增 WSL/Linux Vivado 2025.2 入口 `scripts/simulation/run_tb_mesh_4vc_simple.sh`，结果写入独立目录 `vivado_sim_wsl/tb_mesh_4vc_simple_sim/`。

计划命令：

```bash
bash scripts/simulation/run_tb_mesh_4vc_simple.sh
```

<!-- Modify record start of four-virtual-channel RTL and simple verification task, Michael Tan, 20260715 -->

## 2026-07-15 四虚拟通道 RTL 与简单测试完成

RTL 已从 2 个 VC 扩展为 4 个 VC：

- `src/noc.sv`：全局 `VC_NUM` 从 2 改为 4，`VC_SIZE = $clog2(VC_NUM)` 自动变成 2 bit。
- `src/separable_input_first_allocator.sv`：模块独立使用时的默认 `VC_NUM` 同步从 2 改为 4；路由器内部实例本来就会显式传入全局值。

检查确认，当前有效数据通路中的输入 buffer 数量、VC 编号宽度、流控向量、VC allocator、switch allocator 和 round-robin 仲裁循环都由 `VC_NUM`/`VC_SIZE` 推导，没有发现仍固定为 2 VC 的有效 RTL 路径。

新增文件：

- `testbench/tb_mesh_4vc_simple.sv`
- `scripts/simulation/run_tb_mesh_4vc_simple.sh`

运行命令：

```bash
bash scripts/simulation/run_tb_mesh_4vc_simple.sh
```

WSL/Linux 结果目录：

`vivado_sim_wsl/tb_mesh_4vc_simple_sim/`

结果表：

```text
vc_num expected_flits received_flits head_seen tail_seen output_vc_seen error_count
4 8 8 1111 1111 0011 0
```

这个简单 tb 先连续向输入 VC0、VC1、VC2、VC3 各注入一个 HEAD，再注入各自的 TAIL，因此同一测试中四个源 VC 都实际保存并发送了 packet。目的节点正确收到 4 个 packet、共 8 个 flit，packet ID 与 HEAD/TAIL 顺序正确，`head_seen=1111`、`tail_seen=1111`、`error_count=0`，xsim 在 245 ns 输出 `[TB_MESH_4VC] PASSED`。

`output_vc_seen=0011` 不是缺少 VC2/VC3：flit 每经过一跳都会重新分配下游 VC，本次负载只需要下游 VC0/VC1；是否测试了四个源 VC 由四组 packet ID 的完整 HEAD/TAIL 结果确认。

已检查 `xvlog.log`、`xelab.log`、`xsim.log` 和结果表，没有 `ERROR:`、`CRITICAL WARNING`、`$error`、`FAILED` 或 `FATAL`。既有 interface、timescale 和 `LIBRARY_PATH` warning 仍然存在但不影响通过。脚本还增加了 PASS 标记检查，避免 xsim 即使遇到 SystemVerilog `$fatal` 仍返回进程状态 0 而产生假通过。

关键输出：

- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/tb_mesh_4vc_simple_results.txt`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/xvlog.log`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/xelab.log`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/xsim.log`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/out.vcd`

<!-- Modify record completed four-virtual-channel RTL and simple Vivado verification, Michael Tan, 20260715 -->

## 2026-07-15 四 VC、5x5、4-flit queue-knee sweep 任务开始

本次使用新的 4-VC RTL，复现昨天的 5x5、Noxim-style、源队列、4-flit、20 点 knee sweep 模式，但不直接复用原 tb 名称和结果目录。新增独立 tb：`testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`，新增 WSL 脚本：`scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`，结果保存到 `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/`。

保持原实验的 20 个注入率、4-flit packet、源队列深度、warm-up、measurement 和 drain 设置不变，便于比较 2-VC 与 4-VC 结果。

计划命令：

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh
```

<!-- Modify record start of independent four-VC 5x5 4-flit queue-knee sweep, Michael Tan, 20260715 -->

## 2026-07-15 四 VC、5x5、4-flit queue-knee sweep 完成

新增独立文件：

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`

原来的 `tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit` tb 和结果目录没有被复用或覆盖。新 tb 会强制检查 `VC_NUM=4`、`VC_SIZE=2`，并保持原实验的 20 个注入率、4-flit packet、200-cycle warm-up、1000-cycle measurement、最多 8000-cycle drain 和 2048 深度源队列。

运行命令：

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh
```

独立结果目录：

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/`

Vivado 2025.2 结果：

```text
rate latency_cycles injected received queue_full errors
0.010 11.948 235 235 0 0
0.030 12.820 739 739 0 0
0.050 14.400 1248 1248 0 0
0.070 16.378 1744 1744 0 0
0.090 19.817 2303 2303 0 0
0.100 22.565 2545 2545 0 0
0.120 35.714 3014 3014 0 0
0.140 84.153 3593 3593 0 0
0.160 153.643 4020 4020 0 0
0.180 268.786 4462 4462 0 0
0.200 391.048 5029 5029 0 0
0.220 474.048 5572 5572 0 0
0.240 571.510 6132 6132 0 0
0.260 645.762 6453 6453 0 0
0.280 794.567 6975 6975 0 0
0.300 887.461 7499 7499 0 0
0.350 1223.836 8946 8946 0 0
0.400 1418.524 10089 10089 0 0
0.450 1704.706 11288 11288 0 0
0.500 1913.803 12530 12530 0 0
```

全部 20 行均完成，自动检查为 `data_rows=20`、`bad_rows=0`。所有注入率都满足 `measure_injected == measure_received`、`measure_queue_full == 0`、`error_count == 0`。三个 Vivado 日志中没有 `ERROR:`、`CRITICAL WARNING`、`$error`、`FAILED` 或 `FATAL`。仿真结束时间为 464335 ns，实际运行约 11 分 31 秒，峰值进程内存约 1450 MB；`out.vcd` 大小为 2604935407 bytes。

与昨天同平台的旧 2-VC WSL 结果相比，本次随机流量计数完全一致，可以直接观察 VC 数量变化。注入率 0.10、0.20、0.50 的平均延迟分别从 61.024、712.666、2876.995 cycles 降至 22.565、391.048、1913.803 cycles。4 VC 在高负载下仍会饱和，但拐点更晚，采样范围内的拥塞排队延迟明显降低。

关键输出：

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_results.txt`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/xvlog.log`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/xelab.log`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/xsim.log`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/out.vcd`

<!-- Modify record completed independent four-VC 5x5 4-flit queue-knee Vivado sweep, Michael Tan, 20260715 -->

## 2026-07-15 四 VC queue-knee 两张曲线图任务开始

本次基于已经完成的 4-VC、5x5、4-flit queue-knee 结果表，生成和昨天 2-VC 图片风格及坐标范围一致的两张 PNG：完整范围图使用注入率 0.00～0.50、延迟 0～3000 cycles；knee 放大图使用注入率 0.00～0.16、延迟 0～500 cycles。新增独立绘图脚本 `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py`，图片保存到 4-VC 独立结果目录。

<!-- Modify record start of four-VC full and knee-zoom latency plots, Michael Tan, 20260715 -->

## 2026-07-15 四 VC queue-knee 两张曲线图完成

新增可复用脚本：

- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

生成命令：

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

生成图片：

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_curve_full.png`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_curve_knee_zoom.png`

完整图包含全部 20 个数据点，坐标范围与 2-VC 完整图一致：注入率 0.00～0.50、延迟 0～3000 cycles。放大图包含 0.01～0.16 的 9 个数据点，坐标范围与 2-VC 放大图一致：注入率 0.00～0.16、延迟 0～500 cycles。

两张图都是 1100×719 的 RGB PNG；完整图大小 45852 bytes，放大图大小 40185 bytes。已目视检查，4-VC 标题、蓝色折线与圆点、网格和坐标范围正确，没有裁切或数据越界，并能看到相对于 2 VC 更晚出现的延迟拐点。

<!-- Modify record completed four-VC full and knee-zoom latency plots, Michael Tan, 20260715 -->

## 2026-07-15 调整四 VC knee 放大图范围

原来的 0.00～0.16 范围沿用了 2-VC 图，但在 4 VC 下只显示到快速上升的起点。现将 4-VC knee 放大图改为注入率 0.00～0.24、延迟 0～700 cycles，包含截至 0.24/571.510 cycles 的 13 个实测点；横轴采用 0.04 间隔，纵轴采用 100-cycle 间隔。只替换 4-VC 的 `injection_latency_curve_knee_zoom.png`，完整图和 2-VC 图片保持不变。

<!-- Modify record start of improved four-VC knee zoom range, Michael Tan, 20260715 -->

## 2026-07-15 四 VC knee 放大图范围调整完成

修改脚本：

- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

重新生成命令：

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

更新图片：

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_curve_knee_zoom.png`

最终采用注入率 0.00～0.24、延迟 0～700 cycles；横轴刻度间隔 0.04，纵轴刻度间隔 100 cycles。图片包含从 0.01 到 0.24 的 13 个实测点，现在完整显示了 0.16～0.24 区间从 153.643 cycles 快速上升到 571.510 cycles 的趋势。

图片为 1100×719 RGB PNG，大小 44257 bytes。目视检查确认坐标清晰、顶部余量合理、没有裁切，低负载平坦区、拐点和陡峭上升区都能同时看到。同一命令仍会重新生成范围保持为 0.00～0.50/0～3000 的完整曲线图。

<!-- Modify record completed improved four-VC knee zoom range, Michael Tan, 20260715 -->

## 2026-07-15 四 VC throughput sweep 任务开始

新增一套独立的 4-VC、5x5、4-flit、源队列吞吐量实验，保留现有延迟 tb 和结果不变。吞吐量在 warm-up 后固定 1000-cycle measurement window 内统计目的端实际收到的 flit 和完成的 packet，并分别归一化为 `flit/cycle/node` 与 `packet/cycle/node`。measurement 后仍会 drain 以验证无丢包，但 drain 流量不计入吞吐量。继续扫描 0.01～0.50 的相同 20 个 offered packet rate，并生成预期在饱和后形成平台的 throughput 曲线。

计划新增：

- `testbench/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `scripts/simulation/run_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`
- `scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

<!-- Modify record start of independent four-VC throughput sweep and curve, Michael Tan, 20260715 -->

## 2026-07-15 四 VC throughput sweep 与曲线完成

新增文件：

- `testbench/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `scripts/simulation/run_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`
- `scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

吞吐量定义：warm-up 200 cycles 后，在严格覆盖 1000 个完整接收采样沿的 measurement window 内，统计 25 个节点本地输出实际收到的全部 flit。归一化 flit throughput 为 `received_flits_window / (1000 * 25)`，单位是 `flit/cycle/node`；packet throughput 统计同一窗口内的 TAIL，单位是 `packet/cycle/node`。后续 drain 流量不进入 throughput，但仍用于验证全部 measurement packet 最终无丢失到达。

命令：

```bash
bash scripts/simulation/run_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sh
python3 scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

结果目录：

`vivado_sim_wsl/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/`

关键结果：

```text
packet_rate flit_throughput packet_throughput
0.010 0.03772 0.00940
0.030 0.11836 0.02964
0.050 0.19900 0.04956
0.070 0.27900 0.06968
0.090 0.36696 0.09184
0.100 0.40676 0.10168
0.120 0.47488 0.11872
0.140 0.53252 0.13296
0.160 0.54460 0.13628
0.180 0.52464 0.13100
0.200 0.52144 0.13004
0.220 0.54492 0.13624
0.240 0.53748 0.13432
0.260 0.54424 0.13596
0.280 0.54220 0.13540
0.300 0.54016 0.13520
0.350 0.52584 0.13140
0.400 0.54940 0.13732
0.450 0.54016 0.13508
0.500 0.54052 0.13532
```

全部 20 行完成，检查结果为 `data_rows=20`、`bad_rows=0`；每行均满足 `measure_injected == measure_received`、`measure_queue_full == 0`、`error_count == 0`。低负载时 throughput 随 offered load 近似线性增加，约在 packet rate 0.14～0.16 后进入平台。0.16～0.50 的 12 个点中，flit throughput 平均值为 0.537967，最小 0.521440，最大 0.549400 flit/cycle/node；小幅波动来自 1000-cycle 有限窗口和随机流量。

Vivado 仿真约运行 11 分 20 秒，在 464335 ns 结束，日志无 `ERROR:`、`CRITICAL WARNING`、`$error`、`FAILED` 或 `FATAL`。生成的 `throughput_curve.png` 包含全部 20 个点，为 1100×719 RGB PNG，大小 47974 bytes；目视检查确认曲线呈现教材预期的“低负载线性增长—饱和后水平平台”。`out.vcd` 大小为 2605528334 bytes。

本实验沿用现有生成器从本地 VC0 注入的行为；网络内部仍使用 4-VC 进行下游 VC 分配。

<!-- Modify record completed four-VC fixed-window throughput sweep and saturation curve, Michael Tan, 20260715 -->

<!-- Modify record start of WSL 4-flit queue-knee zoom plot task, Michael Tan, 20260714 -->

## 2026-07-22 四 VC 中心热点延迟实验开始

新增一套独立的 5x5、4-flit、4VC、源队列热点流量延迟扫描，不修改现有均匀随机延迟/吞吐量实验和 RTL。热点固定为中心节点 `(2,2)`，热点概率为 `H = 0.2`：每个非热点源节点生成 packet 时，有 20% 概率选择 `(2,2)`，其余 80% 均匀随机选择非自身且非热点的目的节点，避免随机分支再次命中热点而抬高真实热点概率；热点节点自身始终选择其他节点。

实验保留随机基准的 20 个注入率、packet 长度、源队列深度、warm-up、measurement、seed 和四 VC 检查，以便直接比较。由于单一热点的 4-flit 本地输出在高负载下需要更长排空时间，热点实验采用独立的 16000-cycle drain 上限。

计划新增：

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh`

计划命令：

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh
```

独立结果目录：

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot_sim/`

<!-- Modify record start of four-VC center-hotspot latency sweep, Michael Tan, 20260722 -->

## 2026-07-22 四 VC 中心热点延迟实验完成

新增文件：

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh`
- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.py`

本实验没有修改 RTL。热点固定为中心节点 `(2,2)`，`HOTSPOT_PROBABILITY_PERMILLE=200`，即 `H=0.2`。非热点源节点有 20% 概率显式选择热点，剩余随机分支排除自身和热点；热点源节点随机选择其他节点。因此所有节点合计的理论热点 packet 占比为 `0.2 × 24/25 = 0.192`。结果文件额外记录每个注入率下的热点 packet 数量与实测占比。

其他主要配置与四 VC 随机基准一致：5x5、4-flit、20 个注入率点、200-cycle warm-up、1000-cycle measurement、2048 深度源队列和相同 seed。考虑单热点 4-flit 本地输出的高负载排空需求，drain 上限使用 16000 cycles。

命令：

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.py
```

结果目录：

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot_sim/`

关键结果：

```text
packet_rate avg_latency_cycles
0.010 12.137
0.030 13.324
0.050 19.243
0.070 181.573
0.090 385.141
0.100 569.483
0.120 886.364
0.140 1057.084
0.160 1335.380
0.180 1585.764
0.200 1769.841
0.220 2114.957
0.240 2345.978
0.260 2401.783
0.280 2974.747
0.300 3159.688
0.350 3943.168
0.400 4332.622
0.450 5093.534
0.500 5672.454
```

20 行全部完成，每行均满足 `measure_injected == measure_received`、`measure_queue_full == 0`、`error_count == 0`。共生成 104102 个 measurement packets，其中 19811 个发往热点，实测总体热点占比为 0.190304，与理论 0.192 接近。

热点曲线在 0.01～0.05 仍接近低负载区，但从 0.07 开始快速上升；相比之下，已有四 VC 均匀随机曲线约在 0.12～0.16 才进入明显拐点。0.50 点实际 drain 为 10661 cycles，低于 16000 上限，12460 个 measurement packets 全部到达。

Linux Vivado 2025.2 xsim 在 1026495 ns 结束，约运行 9 分 38 秒；`xvlog.log`、`xelab.log`、`xsim.log` 未发现 `ERROR:`、`CRITICAL WARNING`、`$error`、`FAILED` 或 `FATAL`。

生成文件包括：

- `injection_latency_results.txt`
- `injection_latency_curve_full.png`
- `injection_latency_curve_knee_zoom.png`
- `xvlog.log`、`xelab.log`、`xsim.log`
- `out.vcd`

两张曲线图均为 1100×719 RGB PNG。完整图范围为注入率 0.00～0.50、延迟 0～6000 cycles；拐点放大图范围为注入率 0.00～0.12、延迟 0～1000 cycles。已目视检查，数据没有裁切，热点导致的提前拐点显示清楚。

<!-- Modify record completed four-VC center-hotspot latency sweep and plots, Michael Tan, 20260722 -->

## 2026-07-23 packet ID + flit index 编码任务开始

本次只修改 `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`，不修改 RTL 和其他实验。BODY/TAIL 的 `bt_pl` 将同时编码 `packet_id` 与 `flit_index`，接收端解码后逐 flit 检查编号，从而明确发现重复、丢失或乱序的 BODY/TAIL。HEAD 的目的地址和现有 packet 延迟、统计口径保持不变。

计划使用 Linux Vivado 2025.2 在临时目录完成编译与 elaboration，不覆盖已有的完整 sweep 结果。

<!-- Modify record start of packet-id plus flit-index payload encoding task, Michael Tan, 20260723 -->

## 2026-07-23 packet ID + flit index 编码完成

已修改：

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `AGENTS.md`
- `README.md`

当前 4-flit packet 的编码定义如下：

- `FLIT_INDEX_SIZE = $clog2(PACKET_FLIT_NUM) = 2`。
- HEAD 保持原路由字段，并在 `head_pl` 保存 16-bit packet ID。
- BODY/TAIL 的 `bt_pl[1:0]` 保存 `flit_index`，随后 16 bit 保存 `packet_id`，其余高位清零。
- 四个 flit 的 index 依次是 HEAD=0、BODY=1、BODY=2、TAIL=3。

接收端新增每个 packet 的期望 flit index 状态。现在会分别解码 BODY/TAIL 的 packet ID 和 flit index，并检查重复 HEAD、非法 packet ID、目的节点错误、BODY/TAIL 丢失、重复、乱序和异常 label；这些错误除输出 `$error` 外，也会计入结果中的 `error_count`。同时增加启动期位宽检查，避免 packet ID 或 flit index 被静默截断。本次没有修改 RTL 和其他 tb。

验证使用 Linux Vivado 2025.2，在临时目录执行 `xvlog`、`xelab`，然后通过 elaboration 参数把冒烟测试缩短为：

```text
WARMUP_CYCLES_PER_RATE=2
MEASURE_CYCLES_PER_RATE=8
DRAIN_CYCLES_PER_RATE=1000
```

20 个注入率点全部执行完成，结果为 `data_rows=20`、`bad_rows=0`；每行均满足 `measure_injected == measure_received`、`measure_queue_full == 0`、`error_count == 0`。第一次沙箱内 xsim 命中了已知 snapshot 加载异常，按项目规则在沙箱外重跑同一 snapshot 后通过。验证日志没有 `ERROR:`、`CRITICAL WARNING`、`$error`、`FAILED` 或 `FATAL`，仅保留既有 interface、timescale 和环境 warning。

本次没有覆盖 `vivado_sim_wsl/` 中已有的完整 sweep 结果，也没有重新运行约 11 分钟的正式完整 sweep。

<!-- Modify record completed packet-id plus flit-index payload encoding and bounded xsim verification, Michael Tan, 20260723 -->

## 2026-07-24 packet 单位吞吐量曲线任务开始

保留现有纵轴为 `flit/cycle/node` 的吞吐量图片，不重新运行 Vivado。基于已经验证的 `throughput_results.txt`，扩展现有绘图脚本，新增一张横轴、纵轴都使用 `packet/cycle/node` 的曲线，独立保存为 `throughput_curve_packet.png`。

计划命令：

```bash
python3 scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

<!-- Modify record start of packet-unit throughput curve task, Michael Tan, 20260724 -->

## 2026-07-24 packet 单位吞吐量曲线完成

修改了可复用绘图脚本：

- `scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

生成命令：

```bash
python3 scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

新增图片：

- `vivado_sim_wsl/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/throughput_curve_packet.png`

新图直接读取结果表中已经统计的 `throughput_packets_per_cycle_per_node_x1000000`，没有用 flit throughput 简单除以 4 代替。横轴是 offered injection rate，纵轴是 delivered packet throughput，两者单位均为 `packet/cycle/node`。坐标范围为 x=0.00～0.50、y=0.00～0.16，纵轴刻度间隔为 0.02。

20 个实测点全部绘制。packet throughput 在 offered rate 0.01、0.14、0.16、0.50 时分别为 0.00940、0.13296、0.13628、0.13532；0.16～0.50 平台区的平均值、最小值、最大值分别为 0.134463、0.130040、0.137320 `packet/cycle/node`。图中低负载区接近 `throughput = offered packet rate`，约在 0.14～0.16 后进入饱和平台。

新图为 1100×719 RGB PNG，大小 54251 bytes。已目视检查坐标单位、两位小数纵轴刻度、20 个数据点和平台范围，未发现标签重叠、裁切或数据越界。原来的 `throughput_curve.png` 继续保留为 flit 单位图。本次没有修改 RTL、testbench 或结果 TXT，也没有重新运行 Vivado。

<!-- Modify record completed packet-unit throughput curve and verification, Michael Tan, 20260724 -->
