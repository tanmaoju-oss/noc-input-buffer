# Congestion 第一轮 WSL 功能验证（2026-10-28）

<!-- Modify by Michael Tan，20261028: record passing buffer/network regressions and failing TwoAware cost checks. -->

> 后续更新（2026-10-28）：本文保留修复前结果。用户已授权修复 TwoAware，最新9组路由及全网回归通过，见 [修复验证报告](twoaware_fix_verification_20261028.md)。ThreeAware 按用户说明为未完成预留功能，不纳入当前验收。

<!-- Modify by Michael Tan，20261028: link completed TwoAware fix while retaining historical failure evidence. -->

## 结论

已验证两处缓冲修改和默认深度 8 的拥塞采集。13×13 全网在 XY、OneAware、TwoAware 三种算法下的三种确定性流量均通过包/逐 flit 自检。但 TwoAware 独立代价比较检查失败：东向 X 距离为 1 时缺少两跳代价赋值，不能宣称拥塞选优正确。ThreeAware 仅检查最短跳合法性，尚无死锁规避保证。原始 TB 不作本轮证据。

用户决定暂时保留接收宽 flit，未来再评估；代码实际 FLIT_DATA_SIZE=254，flit_t=258，head_pl=218，未改成精确 256 或 26 bit。仍用 13×13、4 VC，未更改包字段或路由算法。

## 本次 RTL 变更

- `src/input_buffer_src_circular_full.sv:192`：保留原 `~is_full_o` 注释行，下一行恢复 `vc_allocatable_o <= meta_pop_cmd`，包尾读出时释放。
- `src/circular_buffer_Xiugai3.sv:23`：保留原阈值 1 注释行，下一行恢复 `ON_OFF_LATENCY=2`，保留流控余量。
- 标注均为 `Original/Modify ..., Michael Tan, 20261028`。其他接收 RTL 仅有此前授权的注释 UTF-8 转码；本轮不修改 TwoAware。根 `src/` 无改动。

## 新增验证文件和命令

使用 Linux Vivado 2025.2，源码完全来自 congestion/src，不混编根 src。公共入口 `scripts/simulation/run_selfcheck.sh`，各 TB 配独立 `run_<top>.sh`；每次创建独立 `vivado_sim_wsl/<top>_sim/run_XXXXXXXX`，保存 xvlog/xelab/xsim 日志、参数和源码 SHA256。由于已知 xsim 加载沙箱限制，本轮所有仿真在沙箱外运行。脚本检查 PASS 且拒绝 Fatal/FAILED；路由失败命令退出码为 1，未将它改成预期 PASS。

| TB / 命令（路径前缀均为 congestion/） | 新结果 | 日志相对 congestion/vivado_sim_wsl/ |
|---|---|---|
| `bash scripts/simulation/run_tb_congestion_buffer_capacity.sh` | PASS：64 组容量、64 次满后拒写；逐 flit 回读、VC/路由元数据、包尾释放及清空 | `tb_congestion_buffer_capacity_sim/run_QStj6UUk/xsim.log` |
| `bash scripts/simulation/run_tb_congestion_metrics.sh` | PASS：54 快照×169 节点，54756 项比较 | `tb_congestion_metrics_sim/run_Fx9vqLo4/xsim.log` |
| `bash scripts/simulation/run_tb_congestion_routing.sh` | FAIL：TwoAware 270 次代价不符 | `tb_congestion_routing_sim/run_0XcVqgQh/xsim.log` |
| 同路由命令加 `-generic_top REFERENCE=1 -generic_top AGG=1` | FAIL：TwoAware 236 次代价不符 | `tb_congestion_routing_sim/run_WxynHma6/xsim.log` |
| 同路由命令加 `-generic_top REFERENCE=2 -generic_top AGG=2` | FAIL：TwoAware 48 次代价不符 | `tb_congestion_routing_sim/run_eMrq3frK/xsim.log` |
| `bash scripts/simulation/run_tb_congestion_mesh_selfcheck.sh -generic_top ALGORITHM=0` | PASS：XY，三阶段 | `tb_congestion_mesh_selfcheck_sim/run_k5yzmN1T/xsim.log` |
| `bash scripts/simulation/run_tb_congestion_mesh_selfcheck.sh -generic_top ALGORITHM=3` | PASS：OneAware，三阶段 | `tb_congestion_mesh_selfcheck_sim/run_oXNhgaRi/xsim.log` |
| `bash scripts/simulation/run_tb_congestion_mesh_selfcheck.sh` | PASS：TwoAware，三阶段 | `tb_congestion_mesh_selfcheck_sim/run_Lf97O3gC/xsim.log` |

命令从根目录执行时，给 scripts 前加 congestion/。结果目录已通过 congestion/.gitignore 排除自动提交，本文保留可复用的结果摘要和重现命令。

## 覆盖范围

容量：真实 input_block 的 NORTH/SOUTH/WEST/EAST，每方向 VC0～3，包长 1/2/4/8 flit。以物理容量测试绕过 on_off 写满 8 槽，包容量分别 8/4/2/1；同时验证占用达 7 时关闭接收。此 TB 不代替全网 VC 仲裁测试。

采集：全部方向占用总量 0～32（覆盖每个拥塞等级阈值）、节点全满到 160、多节点/端口/VC 空间非对称模式、输入归零。额外改变 full/empty，确认输出按 occupancy 计算。

路由：13 个对角当前坐标（覆盖全部列及奇偶、边界）、全部 169 目的、7 个源列、4 标签、4 种非对称/零指标图；每种算法每配置 246064 项。分别检查最短跳/边界/LOCAL、XY/YX 顺序、OE 候选限制，OneAware 一跳代价和 TwoAware 两跳几何参考。ThreeAware 只查最短跳，没有比较三跳成本或证明死锁安全。三组 REFERENCE/AGG 为 (0,0)、(1,1)、(2,2)，不是全部九种组合。

全网：169 个源，每源每阶段 6 包，包长依次为 1/2/4/8/12/1，覆盖所有 4 VC、长于缓冲的包、HEADTAIL、多包排队、镜像/分散/热点流量。目的端前 80 周期停收，此后周期性按 VC 背压；目的端释放信号仅在收到包尾后脉冲，保持真实包级所有权。源端按 on_off 在负边沿驱动，正边沿计数/采样。全部 payload 高低位都参与比对，逐包/逐 beat 检查唯一性、内容、标签、目的、顺序、接收 VC 所有权、error_o 和有效态；继续送完全部源数据后完全排空，并多观察 20 周期确认无额外输出、全网占用为零。

每算法每阶段 1014 包/4732 flit，共 3 算法×3 阶段=9126 包/42588 flit，全部通过。流量是有限确定性突发，不是注入率/延迟性能实验，不用这些完成周期给算法排名。

| 算法 | 镜像完成/观察周期 | 分散完成/观察周期 | 热点完成/观察周期 |
|---|---:|---:|---:|
| XY | 343 | 320 | 4842 |
| OneAware | 426 | 354 | 4881 |
| TwoAware | 378 | 357 | 4876 |

## TwoAware 新发现：东向最后一列缺少代价计算

位置 `src/congestion_decision.sv:219` 的 ALGORITHM=4 分支。x_flits/y_flits 默认 0；东向的南北两个分支只处理 X 距离大于 1 的场景，缺少 X 距离为 1 的 g/h 情况，随后仍执行代价比较。西向已有四种场景，东向不完整。

具体重现（默认 REFERENCE=0、AGG=0，TB 非对称图 pattern=1）：当前=(0,0)，源 X=0，目的=(1,1)，HEAD 或 HEADTAIL。OE 允许 EAST 和 SOUTH。

- 先 EAST：metrics(1,0).WEST=0，再 SOUTH：metrics(1,1).NORTH=3；总代价 3。
- 先 SOUTH：metrics(0,1).NORTH=29，再 EAST：metrics(1,1).WEST=13；总代价 42。
- 应选 EAST；RTL 两个本地代价值未更新，按 0==0 的平局策略选择 SOUTH。日志有明确 ROUTE_MISMATCH。

这是负载感知决策缺陷；本轮全网输送通过不消除这一缺陷。本次用户要求先验证，因此保留失败测试和原算法，未自动修复该新问题。

## 剩余边界

- ThreeAware 仍为预留实现，未套 OE 候选限制/逃逸 VC；有限测试通过不能证明长期无死锁。
- 未执行全部聚合/指标组合的全网验证、随机种子压力矩阵、运行中复位、非法目的/错误包恢复、形式验证、综合或硬件验证。
- 默认 BUFFER_SIZE=8 固定位宽的参数化风险仍在；此次未扩大深度或缩小网格。
- xvlog/xelab 的现有 enum/timescale、LIBRARY_PATH 警告保留在日志，不宣称零警告。
- 原始 TB 的静态局部初始化、统计、排空问题未修改；历史 Excel 未核查。
- Git/Windows 同步状态在后续进度中记录。Windows 工作副本当前有大量既有修改及未跟踪 congestion，禁止覆盖、清理或自动 stash。

代码检查：新增 TB/脚本/报告的空白检查通过；全量首次导入的 staged whitespace 检查报告接收源码既有行尾空格和 CRLF，按保留原交付格式的要求未批量清理。
