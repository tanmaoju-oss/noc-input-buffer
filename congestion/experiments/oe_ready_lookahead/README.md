# 合法两跳代价与联合匹配试验

<!-- Modify by Michael Tan，20261029: predeclare an unweighted two-hop score after one-hop matching remained above XY. -->

父791cd3e。模式3保留已验证一跳联合匹配，须精确复现164.499；模式4仅改匹配边排序为“第一跳输入存量＋下一节点合法第二跳的最小输入存量”，固定权重1+1。队首头坐标从FIFO头读取，OE合法候选仍独立保存并运行断言；获配后整包锁定、TAIL成功写入归还、ready限定、容量和流控开关不变。XY同样使用匹配和流控，只有合法候选为单方向。正式RTL及以前实验不改，不按单种子结果调权重。

这是周期级功能/性能实验；全局metrics沿用交付模型，未验证布线、时序或资源成本，不能用复杂组合计算免费假设宣称物理实现达标。

后续验证矩阵在运行前固定为三组：种子1234501/0.06、种子42/0.06、种子1234501/0.04。两算法相同配置，全部保留；campaign首组须精确复现单档结果。每组重新复位与完全排空，统计按同一出生窗口；单个成功种子不能代表目标达成。

<!-- Modify by Michael Tan，20261029: freeze additional seed/load checks before examining their outcomes. -->

## 两跳首轮结果

模式3+FLOW1精确复现164.498575；模式4+FLOW1下OE92.598762、XY54.952，147697次授权合法/唯一/可接收及完整包/排空检查通过。三组种子/负载矩阵与原长包背压回归另行运行，未达到同延迟或优于XY，不宣称正式优化完成。固定两跳代价反例、到目的地截断及577图匹配参考通过。

<!-- Modify by Michael Tan，20261029: checkpoint legal two-hop progress without claiming the latency goal achieved. -->
