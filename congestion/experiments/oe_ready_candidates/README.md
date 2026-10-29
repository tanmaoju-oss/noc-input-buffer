# OE合法候选与可接收VC联合选择试验

<!-- Modify by Michael Tan，20261029: predeclare fixed policies and fair controls for OE-to-XY latency experiments. -->

父提交c79ad7b，22个正式RTL原始SHA见docs/parent_manifest.tsv。候选元数据接口复用已验证a758a3c实验，移植当前安全TAIL写入归还和元数据背压；正式congestion/src、根src及其他实验不改。

固定模式：0精确原选择；1在合法候选且下游可预约/on_off开启集合中轮询方向与VC；2在同一集合中优先邻居对应输入的较低总占用，同分按相同轮询。指针只在成功授权后推进，获配后整包锁定。模式1/2的可接收VC规则也应用于XY的一位候选，避免只为OE改善底层VC选择。容量、包长、统计、源调度不变，不使用~is_full_o归还。

FLOW为独立开关：0保留7关闭/1重开；1保留7关闭/6重开。模式与FLOW在首个运行前固定，不按单个成功种子调权重。首轮0.06、种子1234501，OFF先精确复现XY/OE全部22字段；随后按结果扩展同条件负载/种子，不以不完整送达或慢包截尾换取低延迟。

入口：bash congestion/experiments/oe_ready_candidates/scripts/simulation/run_ready.sh POLICY FLOW -generic_top ALGORITHM=2。每run独立存参数、宏、源码SHA、完整计分板/合法候选与接收资格检查、占用/等待计数及全量排空。

## 首轮0.06结果（尚未达到目标）

OFF OE全部22字段精确复现1092.088784，OFF XY复现58.628085；模式1/2定向各67项通过。相同15260包、12277样本、d84c82f8下，模式1原滞回464.242、快速重开423.737；模式2原滞回309.188、快速重开235.515。全部包计分板、OE授权合法性、未占用/接收资格和完全排空通过；仍远高于XY，不宣称达标。当前两级选择中VA存在大量可分配请求而输出未授权，后续另建联合匹配副本检验，不修改本轮源码或运行SHA。精确数据/同配置XY对照在本目录docs后续报告中维护。

<!-- Modify by Michael Tan，20261029: checkpoint initial ready-candidate results including the unmet latency target. -->
