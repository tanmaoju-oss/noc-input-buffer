# 当前 OE 实现专项排查（2026-10-28）

<!-- Modify by Michael Tan，20261028: record actual RTL turn/hash audits and a blocked-output counterexample without RTL changes. -->

## 结论

当前OE最短路径和奇偶列禁转约束未发现写反或漏写。已确认的性能风险主要在单比特异或选路的强相关性，以及HEAD入队即锁定唯一方向、不能在VC分配阶段利用另一个空闲合法方向。它们是实现策略/接口能力限制，不应等同于OE理论模型错误。此前“主要问题在OE”应收窄为当前OE实现及其与缓冲/分配器衔接的性能问题；各因素对既有延迟差距的独立贡献尚未量化。

本次仅新增诊断TB/脚本和文档，不修改根src或congestion/src，不重新跑已有延迟矩阵，不运行综合。当前宽flit继续暂用。

## 对照原始论文

参考 Ge-Ming Chiu，The Odd-Even Turn Model for Adaptive Routing，IEEE TPDS 11(7)，2000，DOI 10.1109/71.877831，[原始论文PDF](https://fgmoraes.github.io/sichip/2noc/odd-even.pdf)。核对第2节规则及2.2节最短路径实现，并查看第3节性能实验条件。

论文中的偶数列E→N/S禁转、奇数列N/S→W禁转，以及东向进入偶数目的列前完成Y、西向在未到目的列的奇数列不选Y等条件，与当前代码几何约束相符。论文的实验实例考虑可用输出通道选择，并非要求采用本项目的异或位。论文自身在均匀流量实验中也观察到XY高负载表现更好，因此“均匀流量下差于XY”本身不能证明OE规则实现错误。论文体系与本项目VC/流水/包长不同，不能直接移用其性能数值或整体无死锁证明到本系统。

## 1. 真实RTL全坐标路径核查通过

新增 `testbench/tb_congestion_oe_audit.sv`：169个真实rc_unit实例，ALGORITHM=2，覆盖所有13×13源/目的及packet ID校验位0/1，检查每步曼哈顿距离减1、边界、目的LOCAL、两条禁转，另外测试全部4096 ID及HEADTAIL/BODY/TAIL输出。

新日志 `vivado_sim_wsl/tb_congestion_oe_audit_sim/run_NFn4dIQP/xsim.log`：

```text
[TB_CONGESTION_OE_AUDIT] PASSED paths=57122 hops=492128 source_checks=57122 flip_checks=435344 turn_checks=435344 ids=4096 peak_routes_two_parities=1842
```

57122路径含338条源=目的的零跳路径；非自身为56784条（两个ID校验位）。这验证有限网格/有效坐标路径合法性，不等同于含错误包、非法目的或全部资源状态的形式验证。

首次TB用零时间while遍历时终点检查失败；改为显式有界for并核对全量跳数/CSV后通过。早期失败日志保留，不将其计作RTL问题。

## 2. 单比特异或选择具有确定性相关

`src/rc_unit_Xiugai2.sv:79`：

```systemverilog
oe_rand_bit = ^packet_id_i;
oe_rand_bit = oe_rand_bit ^ X_CURRENT[0] ^ Y_CURRENT[0]
              ^ x_dest_i[0] ^ y_dest_i[0] ^ x_source_i[0] ^ y_source_i[0];
```

- 位宽12的packet ID先约简为一个奇偶校验位，其余源/目的/当前位置只使用最低位。
- 源节点处当前与源坐标最低位抵消，选择只剩ID校验位和目的坐标最低位，跨源选择可能相关。
- 同一包每走一跳，当前x/y有一个最低位翻转，选择位必然翻转；两跳后重复。相邻两个同奇偶列之间的选择位相同，可能反复作出相同横向选择。
- 固定头字段下，4096个ID只产生两个全坐标路由映射，已由RTL检查确认。它是确定性单比特散列，不是逐节点独立随机。

独立Python与RTL的全部624条有向链路计数逐项一致。在每个源均匀选择其余168目的、ID校验位各占一半的静态路径分布中，当前OE峰值路由数921，XY为546，比例1.687；4-flit包的峰值flit需求分别21.929r/13r。这里是固定路由分布推导，未测动态链路利用率或实际饱和点。

代表例(0,0)→(12,12)：直接按禁转规则动态规划得到18564条允许的最短路径，但当前ID选择只能得到2条。这显示潜在路径多样性未被充分使用；仅有两条路径本身不构成正确性错误，也不单独证明是全部延迟根因。

## 3. 已复现：另一个合法输出空闲，仍等待原方向

当前rc_unit只有头字段/metrics输入，无下游VC可用性输入；input_buffer在HEAD入队时执行 `meta_mem[meta_wr_ptr].out_port <= out_port_i`（src/input_buffer_src_circular_full.sv:210）。之后vc_allocator只检查已存方向的可用VC（src/vc_allocator.sv:75），不会尝试另一个合法方向。这一锁定时机也用于TwoAware，属于共同架构限制。

新增 `tb_congestion_oe_availability.sv` 使用真实router、VA、SA：

1. 当前(1,1)，用四个HEADTAIL包占住EAST的四个下游VC，EAST先暂停接收，SOUTH四VC均未分配且可接收。
2. 注入源(1,0)、目的(3,3)、ID0的目标包，EAST与SOUTH都符合OE；异或位1让它选择EAST。
3. 连续30个周期断言EAST无空闲VC、SOUTH仍有四个空闲VC、目标持续请求EAST且未获配、SOUTH没有该包输出。
4. 恢复EAST接收，按真实TAIL逐个返还VC，验证全部5包送出且router清空，无错误或重复。

新日志 `vivado_sim_wsl/tb_congestion_oe_availability_sim/run_GnFZZ4Fl/xsim.log`：

```text
[OE_AVAILABILITY] CONFIRMED blocked_cycles=30 selected=EAST east_available=0 south_available=15
[TB_CONGESTION_OE_AVAILABILITY] PASSED reproduced_fixed_output_wait=30 drained_packets=5
```

30周期是人为保持EAST忙的诊断窗口，不是估计真实网络固定等待时间。此测试证明当前实现无法利用该场景中的空闲合法替代出口，不能量化它对六档延迟实验的贡献。

## 建议的改进顺序

保留已核查的OE合法候选约束；先设计“输出候选集合→结合可分配VC选择→获配后锁定”的接口，将选择与资源可用性衔接，不能在已获配/传输中途随意改方向。再评估完整字段混合的散列或更公平的同分规则，避免仅按单比特棋盘格选择。只更换散列不能消除唯一方向提前锁定的问题。

每次只改变一个机制，以同样流量分别对照现有OE、TwoAware和XY，同时检查包正确性和转向限制；增加均匀、转置、热点及多种子窗口，记录适用范围。当前未修改RTL，以上是后续实现方案，不宣称已经提升性能。

## 复现命令与文件

```bash
bash congestion/scripts/simulation/run_tb_congestion_oe_audit.sh
bash congestion/scripts/simulation/run_tb_congestion_oe_availability.sh
python3 congestion/scripts/simulation/analyze_congestion_oe_audit.py --rtl-run congestion/vivado_sim_wsl/tb_congestion_oe_audit_sim/run_NFn4dIQP
```

WSL Vivado2025.2沙箱外运行。每个run保留参数、源码SHA256和编译/展开/仿真日志；既有enum/timescale/LIBRARY_PATH警告未作为新缺陷。独立计数对照 [CSV](oe_audit_link_load_20261028.csv)。
