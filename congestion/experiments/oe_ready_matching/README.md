# OE候选联合匹配试验

<!-- Modify by Michael Tan，20261029: isolate bounded matching after ready-only selection failed the latency target. -->

父806fc4f，22个RTL SHA见docs/parent_manifest.tsv。仅在vc_allocator新增模式3：在输入端口与输出端口间建立所有可请求头VC的合法/可接收边，用有界增广路寻找最大基数匹配，邻居输入存量排序、成功授权轮询；每输入至多一VC获配，每输出至多一输入获配。保留模式0/1/2，模式2+FLOW1须精确复现235.515再解释模式3。TAIL写入归还、容量、流控开关和所有路由约束保持；XY同样使用新分配机制，正式RTL不改。

此为组合分配器功能/性能实验，没有综合时序保证。不能用更复杂组合逻辑的周期优势代替频率/面积验收。入口run_matching.sh POLICY FLOW -generic_top ALGORITHM=0/2。

## 首轮联合匹配结果

单元577图与独立递归穷举最大匹配参考一致。模式2+FLOW1精确复现父235.515272；模式3+FLOW1下OE164.498575、XY54.974，完整计分板/授权合法与唯一/接收资格/完全排空通过，但OE仍约3倍，不宣称达标。后续应检验下一跳以后信息，不再仅依据邻居输入存量；模式3副本保留用于对照。

<!-- Modify by Michael Tan，20261029: retain matching benefit and the remaining latency gap honestly. -->
