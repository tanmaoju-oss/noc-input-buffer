# Mesh/Torus 同条件功能与性能验证（2026-11-04）

<!-- Modify by Michael Tan，20261104: document measured matched-traffic comparison and adverse high-load results. -->

## 结论

WSL Vivado 2025.2 沙箱外新运行的20组测试全部通过。每种实现共61386包/245544 flit完整收发，两种实现合计122772包/491088 flit；10对流量轨迹逐字节一致。逐包目的、HEAD/BODY/TAIL顺序、负载、重复、错误/X、物理跳数、最终FIFO/metadata、接入所有权和下游VC释放均通过自检。

Torus在均匀低负载0.01下均延迟降低9.96%～11.43%，0.04下仅降低0.89%～3.70%且P99变差；0.08下均延迟增加80.33%～109.01%；0.12下Mesh约32周期、Torus768～801周期，Torus窗口输出约0.364～0.369 flit/节点/周期，低于Mesh约0.477～0.478。环绕对角邻居流量同样出现低负载改善、高负载退化。短路径不保证当前实现全负载性能更好。

0.12种子1的Torus源排队均值770.843周期、入网后30.089周期；Mesh分别7.590/24.026周期。主要延迟差体现在源排队，不能由此直接确定内部仲裁、某个VC类别或流控的独立因果贡献。实际瓶颈尚未定位，本次没有改变RTL来追求更好的结果。

## 公平条件与统计口径

- Mesh只编译根目录`src/`，Torus只编译`torus/src/`，共同使用新增`torus/testbench/tb_torus_performance.sv`。根目录25个RTL逐一匹配2026-10-21导入清单，无差异；两次独立编译都保存并复核源码SHA256。基于工作提交`3c31c2b`，本轮所有RTL保持原样。
- 固定5×5、4 VC、每VC深度8、每包4 flit、相同10ns时钟、接收端始终可接收。Mesh的路由可使用全部4 VC，Torus受dateline类别约束；Torus具有额外环绕链路。此为两套实际实现的比较，不是等链路数或单独改变拓扑的消融实验。
- 预生成4000周期的出生流量，使用固定32-bit xorshift与种子1/42，Bernoulli到达概率为rate/10000。均匀流量目的均为非自身节点；环绕流量固定`((x-1) mod 5,(y-1) mod 5)`。每档独立重置，不依据结果调整矩阵。
- 源端保留无限于网络背压的外部排队（实际有限数组容量并检查溢出），每节点单包游标，按全局packet ID模4选择接入VC，HEAD同时检查接入所有权和on_off，整包锁定该VC。不绕过受阻包。该注入器的源队首阻塞是本次比较条件之一。
- 所有生成包含预热包均做正确性检查并最终送达；停止生成后继续发送排队包，最多排空100000周期。完全排空后再等待40周期，检查所有输入FIFO空、metadata为0、无开放写包、所有下游VC和源接入VC释放。
- 周期1～1000预热；延迟样本固定为出生周期1001～4000的包，涵盖排空阶段才收到的包，两个实现使用完全相同样本。含源排队延迟=`TAIL收到周期−出生周期+1`；入网后延迟=`TAIL收到周期−HEAD注入周期+1`；源排队=`HEAD注入周期−出生周期`。均值满足两项相加，单位均为周期。P95/P99使用nearest-rank。
- 窗口输入/输出吞吐分别为周期1001～4000实际注入/收到flit数除以`25×3000`，单位flit/节点/周期，包含窗口内收到的预热包。表中注入率为名义包/节点/周期，换为名义flit率需乘4；实际生成率存在有限随机偏差。
- 排空周期为最后完成周期减4000；平均跳数为全部生成包的最短路均值，并与真实物理链路传输总数逐项守恒核对。未把环绕距离公式用于Mesh。

## 完整结果

以下均延迟含源排队，百分比为`Torus/Mesh−1`；窗口输出单位为flit/节点/周期。

| 流量 | 种子 | 注入率（包/节点/周期） | Mesh 均延迟 | Torus 均延迟 | 延迟变化 | Mesh / Torus P99 | Mesh / Torus 窗口输出 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| uniform | 1 | 0.01 | 12.802 | 11.527 | -9.96% | 21 / 21 | 0.0420 / 0.0421 |
| uniform | 42 | 0.01 | 13.001 | 11.516 | -11.43% | 22 / 19 | 0.0388 / 0.0388 |
| uniform | 1 | 0.04 | 14.348 | 13.817 | -3.70% | 26 / 31 | 0.1562 / 0.1562 |
| wrap_diagonal | 1 | 0.04 | 12.775 | 11.419 | -10.62% | 22 / 24 | 0.1563 / 0.1562 |
| uniform | 42 | 0.04 | 14.621 | 14.491 | -0.89% | 27 / 37 | 0.1569 / 0.1567 |
| uniform | 1 | 0.08 | 18.130 | 37.894 | +109.01% | 38 / 218 | 0.3144 / 0.3101 |
| wrap_diagonal | 1 | 0.08 | 13.570 | 16.032 | +18.15% | 26 / 47 | 0.3147 / 0.3147 |
| uniform | 42 | 0.08 | 18.265 | 32.937 | +80.33% | 38 / 134 | 0.3188 / 0.3178 |
| uniform | 1 | 0.12 | 31.616 | 800.932 | +2433.27% | 102 / 1878 | 0.4781 / 0.3640 |
| uniform | 42 | 0.12 | 31.990 | 767.808 | +2300.19% | 102 / 1702 | 0.4767 / 0.3689 |

种子1均匀流量的分项如下，跳数统计所有生成包，延迟统计出生窗口样本：

| 注入率 | 实现 | 源排队均值 | 入网后均延迟 | 平均跳数 | 排空周期 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0.01 | Mesh | 0.073 | 12.729 | 3.244 | 10 |
| 0.01 | Torus | 0.086 | 11.441 | 2.485 | 10 |
| 0.04 | Mesh | 0.410 | 13.938 | 3.370 | 18 |
| 0.04 | Torus | 0.491 | 13.326 | 2.480 | 17 |
| 0.08 | Mesh | 1.544 | 16.586 | 3.361 | 30 |
| 0.08 | Torus | 15.768 | 22.126 | 2.501 | 173 |
| 0.12 | Mesh | 7.590 | 24.026 | 3.336 | 29 |
| 0.12 | Torus | 770.843 | 30.089 | 2.514 | 1838 |

完整20行数据含P95、P99、实际窗口输入/输出、样本量、逐轨迹SHA256及原始日志目录，见[comparison.csv](performance_20261104/comparison.csv)。低负载下输出率主要跟随输入率，不能据其接近就认定两者最大吞吐相同；0.12下Torus积压和窗口输出下降是本次有限运行的实测结果，不据此给出精确稳态饱和阈值。

## 文件、命令与证据

新增TB、`run_tb_torus_performance.sh`、`analyze_torus_performance.py`，报告及`performance_20261104/`下的CSV/表格/审计和源码指纹；同步根AGENTS/README、子项目README与修改记录。未修改任何RTL。

```bash
bash torus/scripts/simulation/run_tb_torus_performance.sh mesh
bash torus/scripts/simulation/run_tb_torus_performance.sh torus
python3 torus/scripts/simulation/analyze_torus_performance.py   torus/vivado_sim_wsl/tb_torus_performance_sim/run_mesh_JqyjmuA2   torus/vivado_sim_wsl/tb_torus_performance_sim/run_torus_nfsUpoFJ   torus/docs/performance_20261104
bash -n torus/scripts/simulation/run_tb_torus_performance.sh
git diff --check
```

实际通过目录：

- Mesh：`torus/vivado_sim_wsl/tb_torus_performance_sim/run_mesh_JqyjmuA2/`
- Torus：`torus/vivado_sim_wsl/tb_torus_performance_sim/run_torus_nfsUpoFJ/`

每目录含`xvlog.log`、`xelab.log`和`source_sha256.txt`；10个`rate{RATE}_seed{SEED}_traffic{0/1}/`各含`xsim.log`、`console.log`、`trace.csv`、`packets.csv`和`summary.csv`。rate=100/400/800/1200对应0.01/0.04/0.08/0.12；traffic=0均匀，1环绕对角邻居。生成的原始仿真数据按既有规则留在被忽略结果目录，便携汇总和源码指纹保存在本报告同级子目录。

[自动审计记录](performance_20261104/audit.txt)确认10对精确轨迹、20份PASS、完整包及时间戳/跳数/当前源码SHA256。根目录25文件导入基线的静态核对也全部一致。没有重跑既有RC穷举或VA定向测试，本次功能结论限于新增流量矩阵。

## 失败、警告与边界

第一次沙箱运行`run_torus_VMRjiORj/rate100_seed1_traffic0/xsim.log`出现`ERROR: unexpected exception when evaluating tcl command`，编译与展开成功；按环境规则改在沙箱外新建运行目录后通过，保留原失败日志，未因该错误修改RTL/TB。未出现功能失败后调参或删掉测试点。

展开保留原项目跨generate接口连接及LIBRARY_PATH相关警告；此次成功编译/仿真不构成Windows综合兼容性证据。有限窗口、两个均匀流量种子、固定四flit和单源游标不足以证明通用吞吐、稳态或形式化无死锁。本次不含新复位中断、HEADTAIL/长包、非5×5尺寸、接收端停顿或板级测试；这些功能的既有证据仍以首版验证报告为准。

本次未综合、未改板级设计、未提交或推送Git，也未尝试Windows同步；既有Windows同步阻挡状态未解决。后续若继续优化，应先在锁定的路由/VC类别下统计源HEAD等待、VA等待、SA等待、各类VC占用和链路利用率，以同轨迹反事实区分路径、VC划分、仲裁与流控的贡献，再决定是否改RTL。

## 测试条件后续复核

参见[独立条件复核报告](test_conditions_audit_20261104.md)：新增6组对照，固定策略精确复现；副本Mesh与原Mesh一致。源HEAD改选可用VC后两者均改善，但Torus614.187仍明显高于同机制Mesh27.413。原比较外部条件相同，拓扑/路径与每跳VC资格同时不同，不能单独归因拓扑；原25倍是含源排队总延迟。

<!-- Modify by Michael Tan，20261104: link subsequent exact controls and clarify comparison variables. -->

## 后续逐跳诊断

[逐跳机制报告](bottleneck_analysis_20261104.md)补充了确定的结构瓶颈证据：单一合格VC与TAIL读出归还导致无竞争4flit单跳每包4周期气泡，Torus链路吞吐0.5/Mesh1；全网主要阻塞位于合法VC预约。已区分拓扑收益、不可达VC资源、局部服务开销与源排队放大，候选资源重组仍仅模型、未改RTL。

<!-- Modify by Michael Tan，20261104: link verified hop-level bottleneck evidence and preserve original measurements. -->
