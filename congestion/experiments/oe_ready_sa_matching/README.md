# 开关分配最大匹配试验

<!-- Modify by Michael Tan，20261029: isolate work-conserving flit scheduling after source queueing is nearly removed. -->

父564b61e，22RTL来源SHA见docs/parent_manifest.tsv。只改变switch_allocator：可选最大基数匹配从已获配且下游允许接收的flit请求中选择，不改变任何包路由、分配VC、HEAD/TAIL顺序或归还；每输入/输出至多一传输。SA=0必须精确复现三跳控制；SA=1对XY/OE同时启用。保持预先固定三组矩阵，不按结果调排序、权重或负载。正式源码不改。

入口run_campaign.sh POLICY FLOW SA -generic_top ALGORITHM=0/2。本实验组合逻辑与公平指针不同，未验收综合时序/面积，周期收益不直接等价于硬件ns收益。

追加验证在运行前固定为两个点：未参与前轮选择的seed7/rate0.06，以及seed1234501/rate0.08压力点，XY/OE均使用POLICY5/FLOW1/SA1。它们不用于继续调权重或排序，全部保留；不会只报告表现较好的点。

<!-- Modify by Michael Tan，20261029: predeclare held-out seed and pressure checks before observing results. -->

## 固定三组矩阵与安全回归通过

POLICY5/FLOW1/SA1：原种子0.06 OE49.083245/XY48.835465；seed42 0.06 OE47.121581/XY46.287111；原种子0.04 OE28.889959/XY29.144004。均值已在约±2%内，但0.06 P99仍为162/145、152/125，不能称全部指标胜出。SA关闭精确复现三跳81.412479。

593图独立最大匹配参考、实际VA/SA授权合法/唯一/交叉开关映射及完整包检查通过。XY/OE各自原三阶段回归通过，每算法3042包/14196flit，覆盖长于FIFO的12-flit包、HEADTAIL、源/接收背压和完全排空。追加seed7及0.08压力点仍按预声明运行，全部保留。

<!-- Modify by Michael Tan，20261029: checkpoint matched average latency and residual P99 gap with safety regressions. -->

## 持续竞争反例：严格最大匹配不应直接采用

新增tb_oe_sa_fairness保持LOCAL/VC0→EAST、LOCAL/VC1→SOUTH、NORTH/VC0→EAST均可发送。严格最大基数只能一直选LOCAL/VC1和NORTH/VC0；实际目标VC连续41周期零服务，其他82次传输，非饥饿断言FAIL，日志保留。它是仲裁公平性反例，不把有限窗口无丢包当作长期公平性证明。该版本只作历史实验，不合入正式RTL；另建等待龄期保护副本并使用同一断言验收。

追加0.08压力点也未达目标：OE567.859左右、XY207.318左右；必须报告，不以中档结果代表饱和区间。seed7/0.06下OE47.188左右、XY47.849左右，仍仅是有限测试点。

<!-- Modify by Michael Tan，20261029: preserve starvation failure and high-pressure regression instead of promoting an unsafe mean-only optimization. -->
