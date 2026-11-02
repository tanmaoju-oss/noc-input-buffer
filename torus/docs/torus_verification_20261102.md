# Torus 首版实现与验证（2026-11-02）

<!-- Modify by Michael Tan，20261102: record first actual Torus implementation and fresh simulation evidence. -->

## 实现内容

首版在 `torus/src/` 新增 `torus.sv`，将每行/列边界的双向数据和反向流控回接；保留 2 节点尺寸下的独立平行端口。路由采用最短路径 X 后 Y，等距选 EAST/SOUTH。VC0/1、VC2/3 分别对应 X/Y dateline 前后类别，逐包 metadata 保存合法掩码，VA 的请求和分配均过滤掩码。共享模块默认 Mesh 模式，Torus 顶层显式使能。

修改 `noc.sv`、`rc_unit_Xiugai2.sv`、`router.sv`、`input_block_Xiugai2.sv`、`input_port_Xiugai2.sv`、`input_buffer_src_circular_full.sv`、`input_block2vc_allocator.sv`、`vc_allocator.sv`；其余导入 RTL 保持原字节。每处改动标注 Michael Tan 和 20261102。未改主项目 `src/` 或其他子项目。

新增 RC、VA、集成和拥塞四组独立 TB/runner；沿用之前新建的独立 Mesh 基线 TB/runner。runner 每次建立独立目录，保存源码/TB SHA256，并检查 PASS 和错误日志。`torus/.gitignore` 排除生成结果与保留独立 Git 的外部参考克隆；不从外部参考仓库引入 RTL。

## 实际执行与结果

工具为 WSL/Linux Vivado 2025.2；首次沙箱加载失败后，功能仿真在获准的沙箱外完成。以下均为本次新运行，不引用历史 Windows 结果。全部行的源码及 TB SHA256 已与最终工作文件核对一致。

| 检查 | 日志结论 | 日志（相对本报告） |
| --- | --- | --- |
| Mesh 模式回归 | `[TB_TORUS_MESH_BASELINE] PASSED` | [run_de2OwV1j](../vivado_sim_wsl/tb_torus_mesh_baseline_sim/run_de2OwV1j/xsim.log) |
| RC 穷举 | `[TB_TORUS_RC] PASSED` | [run_XCA8XjAg](../vivado_sim_wsl/tb_torus_rc_sim/run_XCA8XjAg/xsim.log) |
| VA/metadata 定向 | `[TB_TORUS_VC_ALLOCATOR] PASSED grants=2 metadata_packets=2` | [run_iqgayG23](../vivado_sim_wsl/tb_torus_vc_allocator_sim/run_iqgayG23/xsim.log) |
| 集成 5×5 | `[TB_TORUS_INTEGRATION] PASSED size=5x5 packets=950 completed=950 flits=2414 link_flits=5784 seams=286/286/301/301` | [run_17S1g5RA](../vivado_sim_wsl/tb_torus_integration_sim/run_17S1g5RA/xsim.log) |
| 集成 4×4 | `[TB_TORUS_INTEGRATION] PASSED size=4x4 packets=464 completed=464 flits=1184 link_flits=2368 seams=208/88/216/136` | [run_IhTtH9OF](../vivado_sim_wsl/tb_torus_integration_sim/run_IhTtH9OF/xsim.log) |
| 集成 2×3 | `[TB_TORUS_INTEGRATION] PASSED size=2x3 packets=114 completed=114 flits=294 link_flits=382 seams=93/0/38/38` | [run_QJnNbE6z](../vivado_sim_wsl/tb_torus_integration_sim/run_QJnNbE6z/xsim.log) |
| 集成 2×2 | `[TB_TORUS_INTEGRATION] PASSED size=2x2 packets=68 completed=68 flits=176 link_flits=272 seams=58/0/78/0` | [run_IqNsaumZ](../vivado_sim_wsl/tb_torus_integration_sim/run_IqNsaumZ/xsim.log) |
| 持续拥塞 5×5 | `[TB_TORUS_CONGESTION] PASSED size=5x5 packets=625 completed=625 flits=2050 link_flits=4660 seams=325/195/345/215` | [run_6ymeeJqN](../vivado_sim_wsl/tb_torus_congestion_sim/run_6ymeeJqN/xsim.log) |

RC 覆盖四种尺寸共 261,120 次检查，包括全目的编码、HEAD/BODY/TAIL/HEADTAIL、全部输入端口与 VC、非法坐标、Y→X 拒绝及类别切换。VA 定向检查仅非法 VC 空闲时等待、释放重分配、零掩码不授权、两包排队时 metadata 掩码和下游 VC 不被后包覆盖。

集成测试穷举全源目的、混合 HEADTAIL/四 flit 包、12 轮所有源并发、周期性背压、排空后复位再传输。拥塞测试连续注入 600 包，混合热点、负方向环绕和置换流量；接收端先停止服务约 200 周期，再间歇服务，完成后复位重传 25 包。计分检查无丢失、重复、错目的、包交织或负载/包内顺序错误；检查每跳最短方向、环绕 VC 类别和每个 VA grant 合法性。最终所有输入 flit FIFO、metadata、包接收状态及下游 VC 可用位均恢复空闲。

实际网络链路 flit 传输次数与所有包的最短跳数乘包长度之和完全相等。2 节点维度固定正方向等距选择，因此负方向环绕计数为零是预期；5×5 和 4×4 的四方向 seam 均有流量。

依赖检查命令 `python3 torus/scripts/simulation/check_torus_channel_dependencies.py`：2..8 的全部 49 种尺寸、41,209 条路径检查无环且跳数最短，结果为 `torus/vivado_sim_wsl/torus_channel_dependencies/summary.json`。模型假设详见 [设计合同](torus_design_analysis.md#依赖模型假设与边界)。

复现命令（仓库根目录）：

```bash
python3 torus/scripts/simulation/check_torus_channel_dependencies.py
bash torus/scripts/simulation/run_tb_torus_mesh_baseline.sh
bash torus/scripts/simulation/run_tb_torus_rc.sh
bash torus/scripts/simulation/run_tb_torus_vc_allocator.sh
bash torus/scripts/simulation/run_tb_torus_integration.sh
bash torus/scripts/simulation/run_tb_torus_integration.sh 4 4
bash torus/scripts/simulation/run_tb_torus_integration.sh 2 3
bash torus/scripts/simulation/run_tb_torus_integration.sh 2 2
bash torus/scripts/simulation/run_tb_torus_congestion.sh
```

## 失败与调试

- `tb_torus_integration_sim/run_xeVTDYgW/xsim.log` 为沙箱快照加载失败，编译及展开已通过；沙箱外重跑成功。
- `tb_torus_congestion_sim/run_hQuGIUz4/xsim.log` 在 2075 ns 报包交织。根因是 TB 接收端把 VC 释放信号恒置 1，而接口要求 TAIL/HEADTAIL 消费后脉冲释放；修正接收端模型后重新运行全部尺寸和拥塞测试通过，DUT 无需为该失败修改。详情见 [修改记录第 04 项](修改记录.md)。
- 展开保留原 Mesh generate 跨层接口连接警告及 LIBRARY_PATH 环境警告；本次未通过改写既有连接结构来消除警告。

## 验证边界与后续

当前结论是首版 Torus 的模型与定向/集成/有限拥塞仿真通过。尚未进行完整 RTL 形式化验证、无限时间公平性证明、流量/随机种子大规模扫描、在途复位丢包恢复、端点协议依赖检查、性能比较、Windows 综合/实现或板级验证。非法地址在 RC 穷举检查中覆盖，系统级非法包恢复尚未验证；尺寸 2..8 由模型覆盖，RTL 网络集成实际覆盖上述四种尺寸。下一步可开展更长流量/背压回归及 Mesh–Torus 公平性能对比。

## Git 与交付

实现提交 `6d778dadbee4191e501fcf802621ede374275fae` 已推送至 `origin/chore/reorganize-project-layout`。Windows `E:\Codex-Project\NoC-XY` 已 fetch，但 `git pull --ff-only` 被既有 AGENTS/README、板级脚本/RTL 修改及未跟踪 congestion 等文件阻挡，HEAD 保持 `cdcc7a9d80226b314da695ee2d2e1af6f6d18e41`；未覆盖、丢弃或 stash 既有工作。Windows 工作树同步尚未完成。

本次提交只纳入 Torus 子项目及根目录文档中的 Torus 章节；其他项目已有修改留在工作区。本交付状态作为后续文档提交推送。
