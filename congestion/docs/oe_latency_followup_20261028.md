# OE 延迟退化继续分析

<!-- Modify by Michael Tan，20261028: consolidate factorial counterexamples and observed VC-allocation pressure. -->

## 新结论

不能继续把剩余差距简单归为散列相关性。固定新散列把代表流4096个ID的路径数从2增加到2113，但延迟并未稳定改善；只改散列在0.04/0.08反而恶化。与资源回退组合的收益也随负载变化，说明路径策略和资源状态存在非线性交互。[完整四组消融](../experiments/oe_hash_ablation/docs/results_20261028.md)。

更直接的运行观测显示：0.06下OE的VA等待请求周期中98.293%因所选出口没有空闲VC；有VC但仲裁未获配只占1.707%，内部SA on_off等待为0。每次窗口授权对应的等待请求周期压力指标，OE50.284、XY3.962。OE平均链路利用率14.797%、最忙链路窗口平均55.583%，低于XY54.581%/85.083%，而列间流量更不均匀。[阶段与链路报告](../experiments/oe_va_fallback/docs/stage_profile_20261028.md)。

因此当前应定位为“选路与VC占有/资源等待耦合造成回压和低利用率”，不能说是额外比较器周期或物理链路普遍跑满。下一步应核查VC占有寿命、实际FIFO占用及每VC/源队首阻塞，再选择单因素实验；尚未证明某个释放规则或VC数本身有错误。

全部新运行逐flit正确性和完全排空通过，阶段观测逐项复现旧CSV字段。正式congestion/src和根src未改，实验不自动合入。
