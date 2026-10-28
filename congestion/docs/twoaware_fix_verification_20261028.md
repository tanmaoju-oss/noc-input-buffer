# TwoAware 东向最后一跳代价修复与回归

<!-- Modify by Michael Tan，20261028: record verified eastbound last-X-hop cost fix and nine-configuration regression. -->

日期：2026-10-28。基于上一提交 3a18a77，按用户授权仅修改 congestion/src/congestion_decision.sv；保留当前 13×13、4 VC、完整 flit_t=258 bit（数据254，payload218），位宽为暂用，后续再评估。ThreeAware 为未完成预留功能，不纳入验收。

## 修改

TwoAware 东北、东南各增加 X 距离=1/Y距离>1、X距离=1/Y距离=1 的两个场景，共 4 个分支、34 行。东向路径第一跳读取东邻 WEST 输入，第二跳按目标 Y 转向读取 SOUTH/NORTH；南北路径第二跳按剩余 Y 距离继续直行或转向东。

本次为纯补充：原有 RTL 每一行均保留，无原行被替换或删除；新增两处代码区域以 `//Modify ..., Michael Tan, 20261028` 标明。插入脚本已校验移除新增区域后与修复前原文件逐字节一致，保留 UTF-8、CRLF。未改 OE 合法候选、既有平局规则、聚合函数或其他 RTL，根 src 不变。

修复前例 (0,0)→(1,1)、源X=0，X路径成本3、Y路径成本42却选SOUTH；原路由自检保留不改，修复后该配置不再出现 ROUTE_MISMATCH。

## 路由参考模型回归

命令（根目录）：

```bash
bash congestion/scripts/simulation/run_tb_congestion_routing.sh -generic_top REFERENCE=<0|1|2> -generic_top AGG=<0|1|2>
```

使用 WSL/Linux Vivado 2025.2，在已批准沙箱外执行，全部 9 组配置 PASS。ThreeAware 在原 TB 中仍有既有最短跳输出检查，本次不将该输出计入功能验收；验收算法为 XY/YX/OE/OneAware/TwoAware（0～4），每算法每配置 246064 项零错误。TwoAware 共 2214576 项，0～4 总计 11072880 项检查。全部9组而非此前仅3组指标/聚合配对。

| REFERENCE | AGG | TwoAware 检查数 | 错误 | 新日志相对 congestion/vivado_sim_wsl/ |
|---:|---:|---:|---:|---|
| 0 | 0 | 246064 | 0 | `tb_congestion_routing_sim/run_XRGcmXXQ/xsim.log` |
| 0 | 1 | 246064 | 0 | `tb_congestion_routing_sim/run_eUc4laVd/xsim.log` |
| 0 | 2 | 246064 | 0 | `tb_congestion_routing_sim/run_FncfmvUl/xsim.log` |
| 1 | 0 | 246064 | 0 | `tb_congestion_routing_sim/run_3ryPYUYk/xsim.log` |
| 1 | 1 | 246064 | 0 | `tb_congestion_routing_sim/run_spRqDVdK/xsim.log` |
| 1 | 2 | 246064 | 0 | `tb_congestion_routing_sim/run_NbbyFQa2/xsim.log` |
| 2 | 0 | 246064 | 0 | `tb_congestion_routing_sim/run_9Dzyu3YU/xsim.log` |
| 2 | 1 | 246064 | 0 | `tb_congestion_routing_sim/run_IWayZr8m/xsim.log` |
| 2 | 2 | 246064 | 0 | `tb_congestion_routing_sim/run_YnP7e3vl/xsim.log` |

此前 (0,0)、(1,1)、(2,2) 三组的 270/236/48 次不符全部消除；其余已有分支在相同参考检查中未见回归。参考覆盖仍为13个对角当前坐标、169目的、7源列、4标签和4种指标图，不能等同于全部可能状态的形式证明。

## 13×13 TwoAware 全网回归

命令：`bash congestion/scripts/simulation/run_tb_congestion_mesh_selfcheck.sh`。

新日志：`congestion/vivado_sim_wsl/tb_congestion_mesh_selfcheck_sim/run_EW2vUWjM/xsim.log`。

| 流量 | 包数 | flit数 | 含最后20周期观察的周期计数 | 结果 |
|---|---:|---:|---:|---|
| 镜像目的 | 1014 | 4732 | 378 | PASS |
| 分散目的 | 1014 | 4732 | 383 | PASS |
| 汇聚热点 | 1014 | 4732 | 4876 | PASS |

共3042包/14196 flit。复用原计分板，检查包长1/2/4/8/12、所有4VC、长包和HEADTAIL、宽payload全部位、错误/未知态、接收背压、输出VC所有权、错目的、重复、顺序、源队列和网络完全排空；三个阶段均通过。全网参数 REFERENCE=0、AGG=0；其他8组本轮覆盖独立路由，不宣称均已全网验证。

最后日志：`[TB_CONGESTION_MESH_SELFCHECK] PASSED alg=4 reference=0 aggregation=0 phases=3 packets_per_phase=1014`。有限流量回归不能证明所有压力条件下无死锁；未运行综合/硬件，也不将这些完成周期作为算法性能排名。

## 复现与检查

所有 run_* 目录保留 run_config.txt、source_sha256.txt、xvlog/xelab/xsim 日志，确保每次仿真对应当前修复源码。原失败日志保留。原 TB/脚本、容量和采集 RTL 均未改，已通过的独立容量/采集测试不重复运行。CRLF-aware whitespace 检查通过；现有 Vivado enum/timescale/LIBRARY_PATH 警告未新增修复，不宣称零警告。

本轮 congestion_decision.sv SHA256：`0e4897ba53447aa784a44c705d36eea1bdc8a2bbc424cb11978dcd784c543e14`。

验证结论：TwoAware 本次已发现的代价遗漏已修复，9组路由与默认配置全网回归通过。
