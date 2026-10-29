# 有界等待保护的OE/XY候选

<!-- Modify by Michael Tan，20261029: repair a demonstrated starvation risk before accepting mean-latency improvements. -->

父2421b17，只修改VA/SA等待优先规则，22RTL父SHA见docs/parent_manifest.tsv。AGE_LIMIT固定为PORT_NUM*VC_NUM=20次合格等待机会，不按性能结果调节。达到阈值后，一个输入端口只保留其最老合格VC的候选，输入优先顺序按最老龄期、同分轮询；增广匹配保留已匹配老输入，不为最大基数跳过它。其他输入仍匹配。暂时不可接收时保留龄期但不计新机会，获服务/请求消失才清零。计数饱和255，同分轮询；保护默认开启，仅显式AGE0用于负对照。

该策略必要时牺牲单周期最大基数来保证持续合格VC前进；不改变包路由约束、已分配方向/VC、TAIL成功写入归还、容量或流控。新老版本使用同一持续竞争断言，原严格匹配FAIL后保护版本必须PASS；不得改期望。正式src和以前实验不改。

入口run_campaign.sh POLICY FLOW SA AGE -generic_top ALGORITHM=0/2。固定最终五点：seed1234501/0.06、seed42/0.06、seed1234501/0.04、seed7/0.06、seed1234501/0.08，全部保留，首点AGE0需精确复现49.083245。组合时序/面积和任意背压下的形式活性未验收。

最终五点均完整排空PASS：0.06原种子XY48.420217/OE48.075426；0.06种子42为46.136860/46.830773；0.04原种子29.166975/28.907373；0.06种子7为47.688213/46.031417；0.08原种子212.116171/492.447056。前四点平均接近，压力点未达目标，P99亦非普遍优于XY。VA/SA饥饿反例保护后通过，VA577图/SA593图通过，XY/OE各3042包/14196flit长包背压回归通过。性能表、负对照和观测边界见../../docs/oe_xy_ready_selection_trials_20261029.md。
