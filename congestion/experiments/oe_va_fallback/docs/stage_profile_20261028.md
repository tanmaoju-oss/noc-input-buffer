# OE 与 XY 等待阶段和链路观测

<!-- Modify by Michael Tan，20261028: localize pressure to VC allocation rather than assume a bandwidth or hash-only cause. -->

## 条件和无扰动验证

回退OFF，原散列，ALGORITHM=0/2，注入率0.06；其余与原延迟实验相同。只新增TB观察，RTL完全相同。分别逐项匹配原XY/OE对应行全部22个CSV字段，包括总延迟81.071679/1774.974179、分位数、窗口到达率、结束周期和轨迹哈希，确认观测不改变行为。15,260包/算法全部送达、12,277包进入出生窗口样本；计数仅覆盖预热后的1200周期窗口，不包含排空。

## 请求等待计数

| 类别（输入VC请求周期） | XY | OE |
|---|---:|---:|
| VA首选无VC、合法替代有VC | 0 | 554189 |
| VA首选无VC、无可用合法替代 | 397830 | 974411 |
| VA首选有VC但未获仲裁 | 53790 | 26541 |
| SA因下游on_off关闭等待 | 0 | 0 |
| SA资源允许但未获仲裁 | 378893 | 69204 |
| 成功VA授权 | 113983 | 30927 |
| 成功SA读取flit | 455880 | 124438 |

OE的VA等待1555141输入VC请求周期中，1528600因首选无VC，占98.293%；VA仲裁竞争只占其余1.707%。XY无VC占其VA等待的88.090%。窗口等待请求周期/成功授权压力指标为XY3.962、OE50.284；它不是已完成packet的平均VA延迟，不能与包总延迟直接相加。SA等待/读取压力指标XY0.831、OE0.556；SA流控关闭等待本窗口为0，不意味着所有时刻或源端on_off均无影响。

这些是互斥的请求阶段类别，不覆盖没有发起请求、队列后方包或已获配但等待上游flit的时间；不能称98.3%的包延迟都由VA贡献。

## 动态链路

| 624条有向链路、1200周期窗口 | XY | OE |
|---|---:|---:|
| 平均利用率 | 54.581% | 14.797% |
| 最忙链路窗口平均利用率 | 85.083% | 55.583% |
| 链路利用率变异系数 | 0.358 | 0.801 |
| 垂直列累计flit数最小/最大 | 15225/16097 | 845/9209 |

OE最忙链路为(9,7)向NORTH，窗口发送667 flit；XY最忙为(5,7)向NORTH、1021 flit。OE各列垂直流量明显偏斜；总体链路使用不足与大量VC资源等待同时出现。窗口平均未跑满不能排除短时拥堵；不能只从平均值反推物理带宽永远充裕。

## 当前可支持的定位

直接阻塞主要出现在拿下游VC之前，而不是有VC却被VA仲裁长期拒绝，或内部SA on_off关闭。下游VC“已占用/预约”不等于其FIFO存储已满，也不等于相邻链路正在发送；当前按meta_pop_cmd在尾flit读出后释放给上游，VC可能在等待下一跳时持续占有。OE路径和资源占有形成的等待/回压链是优先排查方向，但本次没有逐个VC追踪占有者和空置周期，不能据此直接断言释放逻辑错误、只要增加VC就能解决，或证明某个单一机制为全部根因。

源端排队OE1444.830周期、网内330.144，对应XY11.048/70.023；VC头包长期不能前进会把压力传回源队列。后续应观察VC占有寿命、实际FIFO占用、每VC使用分布和源队列队首阻塞，再做公平预算的数量/策略对照。暂不更改保证包不交织的正式释放规则。

## 复现与文件

```bash
bash congestion/experiments/oe_va_fallback/scripts/simulation/run_tb_oe_stage_profile.sh -generic_top ALGORITHM=0
bash congestion/experiments/oe_va_fallback/scripts/simulation/run_tb_oe_stage_profile.sh -generic_top ALGORITHM=2
```

- XY新run：vivado_sim_wsl/tb_oe_stage_profile_sim/run_mode0_x2pQcP2N/xsim.log。
- OE新run：vivado_sim_wsl/tb_oe_stage_profile_sim/run_mode0_TOb1KNq0/xsim.log。
- [汇总CSV](oe_xy_stage_profile_006.csv)。原始stage_xy_006_wait_profile.csv、stage_oe_006_wait_profile.csv保留LOCAL/网络输入分组，stage_*_006_link_profile.csv保留624链路。
- scripts/simulation/analyze_oe_stage_profile.py校验无扰动并计算统计；--xy-profile/--oe-profile指定新run，--xy-reference/--oe-reference指定既有参考，--output-dir指定docs。

单种子、均匀流量、有限窗口，未推广至其他负载；不是稳态或形式验证。正式RTL未改，未综合，ThreeAware不纳入。
