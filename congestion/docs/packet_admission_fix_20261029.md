# 安全多包接入：归还时机修改与回归（2026-10-29）

<!-- Modify by Michael Tan，20261029: record ingress ownership protocol, safety coverage and isolated source boundary. -->

## 修改范围与版本

用户授权在congestion中实现，不修改根src；要求Git控制、Modify注释、保护原功能且禁止恢复按未满重新分配。修改前检查点c0bcd8f，保存此前未跟踪的诊断TB、脚本与报告。历史隔离实验RTL不变。

唯一修改的设计文件为`congestion/src/input_buffer_src_circular_full.sv`：

1. 新增packet_write_done，条件严格为accept_write且输入标签TAIL/HEADTAIL。非法顺序、满时拒收或仅看到TAIL标签，都不能归还所有权。
2. 将注册输出vc_allocatable_o从meta_pop_cmd改为packet_write_done，并保留原行Original及Modify日期。
3. meta_pop_cmd保持accept_read且输出TAIL/HEADTAIL，只负责队首元数据出队，不再触发第二次归还。
4. 保留circular_buffer原ON_OFF_LATENCY=2、深度8和7关闭/1重开滞回；输入缓冲输出on_off增加元数据满保护。元数据满时禁止开始新包，正在写入的包仍可继续。条件只依赖注册状态，不新增跨路由器组合反馈环。

没有采用~is_full_o作为归还条件，没有修改VA仲裁、最低VC优先、XY/OE/感知选路、宽flit、包长或源端调度。VA原有的可用位清除/脉冲归还接口继续使用；上游获配即独占写入，前包尾部实际进入下游后才可再次分配，下一包排在元数据队列后方。

归还接入资格不代表有存储空间：下一包可以预约VC但仍须等待on_off允许SA传输。保留输入缓冲accept_write及write_order_ok拒收防线。对异常/丢失TAIL不提供自动恢复，未完成写入的包继续持有所有权，不应为了性能提前开放。

## 测试文件

- 新增`testbench/tb_congestion_packet_admission.sv`及同名run入口：两个真实router，真实VA/SA，XY/OE分别运行。观察第一包未读出时第二包通过上游VA再次获得同一个下游VC0，并拥有不同的EAST/SOUTH路由元数据；竞争输入、前包HEAD后停顿、HEADTAIL及12-flit长包均检查。
- 新增`tb_congestion_admission_edges.sv`及入口：100步骤覆盖非法HEAD、未打开包的TAIL、满FIFO拒收TAIL、合法同时读写、元数据push/pop、20次指针回绕、复位打断开放包及复位后重新接入；每步检查释放脉冲、错误、flit/包计数和读出标签。
- 更新原`tb_congestion_buffer_capacity.sv`：保留64组物理容量/64次满后拒写/逐flit回读；增加写入包尾时归还、拒收不归还、读出不二次归还检查。只修改新协议的期望，容量/数据/路由检查未删除。
- 新增`tb_congestion_admission_latency.sv`及入口：保留原延迟TB的生成器、完整计分板、出生窗口和完全排空，只选择单档0.06、XY/OE；附加网络FIFO占用观测。

每个新TB拥有独立脚本和输出目录；脚本复用congestion/scripts/simulation/run_selfcheck.sh，日志/参数/SHA256保留在各run。WSL Vivado2025.2；首次XY定向及容量快照沙箱加载失败后，使用原run快照在沙箱外执行xsim，后续运行直接沙箱外执行。不使用Windows综合。

## 定向与原有回归结果

结果根目录为`congestion/vivado_sim_wsl/`，各run日志名xsim.log。

| 测试 | 结果 | 结果目录 |
|---|---|---|
| 双路由器XY | PASS，3场景 | tb_congestion_packet_admission_sim/run_D3X2qZuf |
| 双路由器OE | PASS，3场景 | tb_congestion_packet_admission_sim/run_v1pUH65q |
| 边界 | PASS，100步骤 | tb_congestion_admission_edges_sim/run_hfLwR5lq |
| 原容量回归 | PASS，64容量+64满后拒写 | tb_congestion_buffer_capacity_sim/run_78HDI1k9 |
| XY全网 | PASS，3阶段 | tb_congestion_mesh_selfcheck_sim/run_IM3FyHR7 |
| OE全网 | PASS，3阶段 | tb_congestion_mesh_selfcheck_sim/run_97ITAbjz |
| OneAware全网 | PASS，3阶段 | tb_congestion_mesh_selfcheck_sim/run_ZkeA5rkx |
| TwoAware全网 | PASS，3阶段 | tb_congestion_mesh_selfcheck_sim/run_kVznzS1C |
| 拥塞采集 | PASS，54756项 | tb_congestion_metrics_sim/run_8tcxjEHX |
| 原路由默认指标/聚合 | PASS，reference=0 aggregation=0 | tb_congestion_routing_sim/run_h4xpVl8j |

全网每算法3阶段，每阶段1014包/4732flit，4算法共12168包/56784flit，涵盖镜像/分散/热点、1/2/4/8/12-flit、4VC、接收背压；逐flit内容、目的、序号/标签、包唯一性、出口VC所有权、error_o及完全排空通过。原路由/采集未改；本轮不重复全部9组指标/聚合矩阵，不能称新跑完全部参数组合。

真实双路由器停读时的预期为占用7且有2条包元数据，第一包仍完整保留，第二包TAIL停在上游。原因是原流控在7关闭，本次不为追求“8槽写满”绕过背压。物理容量TB仍确认8槽、两个完整4-flit包；该容量测试与实际网络接入测试分别提供存储/协议证据。

## 失败记录与范围

新定向TB首次编译中使用变量索引interface阵列被Vivado拒绝，改为genvar展开的普通wire后通过。首次OE几何设置在偶数列发生不允许的E→S转弯，OE合法选择另一方向，触发TB路由期望失败；改用A=(2,1)、B=(3,1)及合法源/目的组合后，XY/OE使用同一测试通过。未为通过测试改变OE RTL，失败run保留。

没有修改根src、原交付Windows副本、CHI、Torus或Verilator代码。没有综合、时序/资源或板级验证；现有功能通过范围为上述新WSL回归，非形式证明或全流量无死锁证明。

## 复现命令（仓库根目录）

```bash
bash congestion/scripts/simulation/run_tb_congestion_packet_admission.sh -generic_top ALGORITHM=0
bash congestion/scripts/simulation/run_tb_congestion_packet_admission.sh -generic_top ALGORITHM=2
bash congestion/scripts/simulation/run_tb_congestion_admission_edges.sh
bash congestion/scripts/simulation/run_tb_congestion_buffer_capacity.sh
bash congestion/scripts/simulation/run_tb_congestion_mesh_selfcheck.sh -generic_top ALGORITHM=0
bash congestion/scripts/simulation/run_tb_congestion_mesh_selfcheck.sh -generic_top ALGORITHM=2
bash congestion/scripts/simulation/run_tb_congestion_mesh_selfcheck.sh -generic_top ALGORITHM=3
bash congestion/scripts/simulation/run_tb_congestion_mesh_selfcheck.sh -generic_top ALGORITHM=4
bash congestion/scripts/simulation/run_tb_congestion_metrics.sh
bash congestion/scripts/simulation/run_tb_congestion_routing.sh
bash congestion/scripts/simulation/run_tb_congestion_admission_latency.sh -generic_top ALGORITHM=0
bash congestion/scripts/simulation/run_tb_congestion_admission_latency.sh -generic_top ALGORITHM=2
```

## 匹配流量高负载验证

新TB复用原initialize_case/generate_packets/drive/sample/report_case/run_rate六个task；剔除新增只读占用采样调用及注释后逐task规范化比较一致。两算法各15260包/61040flit完全送达，出生窗口各12277包。新旧algorithm/rate/seed/warmup/measure、生成/完成/样本数、实际生成率、轨迹哈希d84c82f8均一致；22个RTL哈希只有input_buffer_src_circular_full.sv变化。其余21个RTL相同。

| 同一0.06流量 | 修改前总延迟 | 修改后总延迟 | 降低 | 修改前源排队 | 修改后源排队 |
|---|---:|---:|---:|---:|---:|
| XY | 81.071679 | 58.628085 | 27.684% | 11.048302 | 0.759387 |
| OE | 1774.974179 | 1092.088784 | 38.473% | 1444.830252 | 771.594526 |

网络内延迟XY70.023377→57.868698、OE330.143928→320.494258周期；主要OE改善体现在源排队。网络FIFO最大占用均为7，测量窗口占用大于4的VC周期为XY102232、OE744927；保留原背压，不要求达到8。源统计和完全排空均PASS。

新日志：`tb_congestion_admission_latency_sim/run_E0qbFekc`（XY）、`run_EheVCm52`（OE）；旧参考分别为`tb_congestion_latency_compare_sim/run_9BfBkWtn`及`tb_congestion_oe_latency_compare_sim/run_vnnZ0OLT`。前后汇总CSV：`packet_admission_latency_006_20261029.csv`。

这是单种子、均匀流量、单档有限窗口的结果，不是所有负载收益或稳态饱和点证明；OE仍显著慢于XY，不能把剩余问题宣称解决。全部12个新运行的22个RTL哈希与本次最终源码一致，报告中的最终PASS不使用编译失败/几何设置失败的run。

### 多包接入 Git 交付与 Windows 状态（2026-10-29）

实现提交3581978（Release congestion VC ingress ownership at accepted packet tail）已推送origin/chore/reorganize-project-layout，修改前检查点c0bcd8f。Windows工作副本fetch成功，pull --ff-only因已有AGENTS/README、板级RTL/脚本修改及未跟踪congestion文件而中止，HEAD仍为cdcc7a9；未覆盖、清理或stash。Linux根src无本次修改，验证日志和参数保留在congestion/vivado_sim_wsl。

<!-- Modify by Michael Tan，20261029: record pushed admission fix and preserve pre-existing Windows work. -->
