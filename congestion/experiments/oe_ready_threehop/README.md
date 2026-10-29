# 固定合法三跳评分试验

<!-- Modify by Michael Tan，20261029: test one bounded additional legal hop without relaxing OE or tuning weights. -->

父4a01ca3。仅vc_allocator的可选评分深度改变：模式4仍是原两跳，模式5采用1+1+1等权三跳最小合法延续；每步按OE候选、到目的地立即截断。与交付中未完成/未受限ThreeAware无关。其余匹配、接收资格、归还、队列和流控保持，正式RTL不改。模式4控制须精确复现两跳结果后解释模式5。

模式5直接运行预先固定的同配置XY/OE三组矩阵：1234501/0.06、42/0.06、1234501/0.04，保留全部结果；不以选择成功种子或改变XY条件宣称达标。组合逻辑成本更高，仍未验收物理时序/面积。

## 首组与独立检查

合法三跳评分、目的截断和577图匹配参考通过。模式4控制复现两跳92.598762；模式5首组OE约81.412、XY约54.996，仍未达到目标。三组矩阵及原长包背压回归继续运行，保留全部结果；后续另建SA匹配副本检验输出空转，不修改本目录源码或运行SHA。

<!-- Modify by Michael Tan，20261029: checkpoint fixed third-hop policy and unmet first-case target. -->
