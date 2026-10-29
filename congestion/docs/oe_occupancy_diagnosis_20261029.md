# OE 相对 XY 大幅增延的存量诊断（2026-10-29）

<!-- Modify by Michael Tan，20261029: distinguish route-induced VC backpressure, storage occupancy and injection serialization. -->

## 问题与实验边界

已有0.06结果OE1774.974、XY81.072周期，约21.9倍。此次新增非侵入观测tb_oe_occupancy_profile；复用资源回退实验RTL、原散列、回退OFF。13×13、4VC、深度8、4-flit、种子1234501，预热300+测量1200周期，再完全排空，保持正式congestion/src和根src不变。

新增观测从输入缓冲直接读取has_packet、head_allocated和priority_usage_o，将每个输入VC分为无元数据包、队首等待VA、队首已获配但无flit、队首已获配且有flit；同时记录0～8存量。源端按发送游标区分HEAD与BODY/TAIL停发，并记录其他VC是否开启。所有计数在posedge的NBA更新前取样，源发送游标递增前取样，不驱动RTL。

网络输入分组含四个物理方向的全部VC，包含52个边界输入端口的空置VC。不能将该组未剔除边界的均值直接解释为624条实际网络链路的输入均值；等待状态计数不受空边界影响。此处“已获配”指该输入VC队首已获取其下一跳资源，不是上游对该输入VC的预约位。

## 因果证据如何合并

1. 基本OE禁转与最短路径检查已通过，没有额外跳数；不能把差距归于绕远。均匀流量轻载差距很小，随负载急增，是排队与有效服务能力问题。
2. 路径分布存在偏斜，OE静态峰值路由数921、XY546；动态垂直列流量也更不均。但更换散列未稳定改善，路径数增加不自动提高资源服务能力。
3. HEAD提前锁定单方向，VA只尝试该方向；合法替代出口空闲时仍可能等待。资源回退单因素在0.06消除了44.641%的OE—XY差距，证明它有因果影响，仍不足以解释全部差距。
4. 已有阶段统计将直接等待定位在所选出口无VC，占OE的VA等待98.293%。无VC是包预约资源不足，不能等价于FIFO满。
5. 下游包头等待更下一跳时，该输入VC仍持有上游分给它的资源；尾部离开后才归还。路径选择与占有时间会共同改变VC周转，形成逐跳回压。当前观测不跟踪逐个预约的授权至归还寿命，不能给出预约寿命均值或等待链长度。
6. 源端单包游标不会绕过阻塞包，网络回压可累积为很长的源排队。因此OE81.4%的延迟位于源端，不意味着源端独立制造81.4%的延迟。若改变源调度，必须作为独立实验并维持相同生成轨迹。

当前证据支持多机制耦合，不能把各单因素改善率相加，也不能将等待周期比例等同包延迟的因果份额。本轮全量排空才能排除该次有限流量中的永久阻塞，不能证明所有工作负载无死锁。

## 复现与验收

入口：`bash congestion/experiments/oe_va_fallback/scripts/simulation/run_tb_oe_occupancy_profile.sh -generic_top ALGORITHM=0`，OE改为2。编译使用WSL Vivado2025.2；沙箱xsim快照加载异常后在相同run目录沙箱外执行`source /home/tanma/tools/Xilinx/2025.2/Vivado/settings64.sh`及`xsim test_sim --runall --log xsim.log`，保持原编译快照。

分析脚本`congestion/experiments/oe_va_fallback/scripts/simulation/analyze_oe_occupancy_profile.py`要求两组源码哈希相同、完整计分板PASS、原22字段精确匹配，并检查采样总数守恒及独立状态与VA/SA请求计数相等。

## 新实测：等待的包已经在缓冲中，但拿不到下一跳

两组WSL Vivado2025.2沙箱外新运行均PASS，每组15260包全部送达、12277个出生窗口样本，逐flit内容/顺序/目的/VC检查及完全排空通过。源码哈希一致、原22个CSV字段全部精确复现；新增VC周期总数守恒、VA/SA状态与请求计数交叉核对通过。

| 统计窗口指标 | XY | OE |
|---|---:|---:|
| 网络输入等待VA的VC周期 | 478947 | 1229229 |
| 网络输入有包时等待VA的占比 | 32.831% | 84.761% |
| 等待VA期间的平均flit存量（网络输入） | 2.881 | 3.890 |
| 等待VA期间恰有4 flit的占比（网络输入） | 54.397% | 95.463% |
| 网络输入已获下一跳但无flit的VC周期 | 219200 | 48431 |
| 网络输入已获下一跳且有flit的VC周期 | 760699 | 172561 |
| 网络输入最大存量 | 4 | 4 |
| 全部输入FIFO达到8的VC周期 | 0 | 0 |
| LOCAL有包时等待VA的占比 | 53.914% | 94.422% |
| 源端HEAD停发节点周期 | 10 | 46 |
| 源端BODY/TAIL停发节点周期 | 16383 | 155203 |
| 源端停发占169×1200节点周期 | 8.083% | 76.553% |

“有包”分母为has_packet为真的VC周期，包含队首已获配但暂空的状态；不是包数或全部VC周期。网络输入在等待VA时持有4 flit，结合固定4-flit包和网络VC包级独占，表示完整包已抵达该输入、等待继续前进。尚未逐个包测寿命，不能把聚合VC周期除以完成包数冒充平均预约寿命。

两算法全部源停发周期都至少有另一个VC的on_off开启；这证明单游标注入器没有使用其他开启VC，并不证明其他VC已经拥有可立即发送的独立后包。OE约99.970%的停发在BODY/TAIL阶段，当前包没有发完，后续包因此也不能发送；这种停顿会拉长后包的出生至HEAD入网排队。实际可绕过收益仍需带包上下文的独立源调度实验。

OE“已获下一跳但暂空”反而更少，不支持将本轮异常主要归于大量已获配空等上游数据的输入状态。最突出的新证据是：网络中大量完整包停在待VA状态。它们未发出的TAIL使其上游预约资源保持占用，阻塞可继续向源端传递。VC不足主要表现为包占有与周转受阻，物理存储未满；不能把增加FIFO深度当成已被证明有效的修复。

## 对“为什么差这么多”的回答

在这一实现和负载下，OE选出的路径与提前锁定的单方向导致下一跳VC获取困难；等待包维持上游VC占有，形成回压。源端顺序发送又把一个VC上的BODY/TAIL停顿传播给所有后包，因而大部分延迟积累在软件源队列，同时网络链路并未充分发送。这是一条得到状态观测支持的放大链，而不是多走若干跳或每跳比较多花周期。

最初触发资源压力的路径分布、同分选择、两方向都可用时的选择，以及周转机制各自的独立贡献仍未完全分离。资源回退已证明有效但只关闭部分差距；新散列已有反例。因此目前不能宣称查出了一个单独bug或某一改动必然恢复XY性能。下一项可做保持包所有权的源调度单因素对照，或逐预约追踪下游所有者及等待链；不提前释放未完成包，不直接改正式RTL。

## 新结果路径

- XY：`congestion/experiments/oe_va_fallback/vivado_sim_wsl/tb_oe_occupancy_profile_sim/run_mode0_cYCfoEIr/`。
- OE：同目录`run_mode0_TTguBBnE/`。
- 每run保留run_config.txt、source_sha256.txt、xvlog.log、xelab.log、xsim.log、latency_summary.csv、wait_profile.csv、link_profile.csv及新增occupancy_profile.csv/source_profile.csv。
- 汇总：[oe_xy_occupancy_006_20261029.csv](oe_xy_occupancy_006_20261029.csv)。源码范围仅新增观测TB、对应入口与分析脚本；没有修改实验RTL或正式RTL。

分析复现命令：

```bash
python3 congestion/experiments/oe_va_fallback/scripts/simulation/analyze_oe_occupancy_profile.py \
  --xy-profile congestion/experiments/oe_va_fallback/vivado_sim_wsl/tb_oe_occupancy_profile_sim/run_mode0_cYCfoEIr \
  --oe-profile congestion/experiments/oe_va_fallback/vivado_sim_wsl/tb_oe_occupancy_profile_sim/run_mode0_TTguBBnE \
  --xy-reference congestion/vivado_sim_wsl/tb_congestion_latency_compare_sim/run_9BfBkWtn \
  --oe-reference congestion/vivado_sim_wsl/tb_congestion_oe_latency_compare_sim/run_vnnZ0OLT \
  --output-dir congestion/docs
```

只覆盖单种子均匀流量0.06及有限窗口，不是全负载、稳态或普适归因；没有运行综合。
