# OE接近XY目标：就绪候选、联合匹配与合法前瞻试验

<!-- Modify by Michael Tan，20261029: preserve fixed-policy experiments, fair controls and unmet objectives rather than tune toward an expected curve. -->

## 目标与边界

用户授权继续试验，目标同条件让OE达到XY延迟水平并探索超过XY。主项目src、正式congestion/src、以前已交付实验均不改；全部改动在新实验副本，新增代码均有Modify标记，阶段Git检查点为806fc4f（候选就绪选择）、791cd3e（联合匹配）、4a01ca3（合法两跳）。每个副本docs/parent_manifest.tsv记录22RTL的父版本与原始SHA。

比较的是OE合法转向下的就绪/感知选路变体，不把它们冒称为原始RANDOM选择。所有策略在相同物理NoC、源调度、包长和流量上比较。没有改成非最短路径、没有放宽OE规则、没有丢弃慢包或改变XY的负载来获得收益。保持TAIL/HEADTAIL成功写入才归还接入资格，不恢复~is_full_o重新分配。

## 固定策略

- 模式0：原方向与最低可预约VC，OFF对照必须精确复现当前XY58.628085/OE1092.088784的全部22字段。
- 模式1：保留每包OE候选，在VA阶段仅从可预约且on_off开启的VC中选方向/VC，成功授权后轮询；无可接收候选就等待，获配后整包锁定。
- 模式2：模式1基础上优先邻居对应输入的较低总占用，同分轮询。
- 模式3：对所有输入端口的可请求头VC及合法就绪出口建立二分图，用有界增广路取得最大基数匹配；每输入至多一个VC获配，每输出至多一个输入获配，边按一跳存量排序。
- 模式4：保持模式3匹配，仅改边排序为第一跳存量＋最佳合法第二跳存量，固定权重1+1，抵达目的地立即截断。
- 模式5：另一个独立副本，仅增加最佳合法第三跳，固定1+1+1，不使用原交付中未完成且未受限的ThreeAware。

FLOW=0保留占用7关闭、降至1重开；FLOW=1保持7关闭、降至6重开。流控是独立开关。模式1～5的底层接收资格/匹配规则也适用于XY的一位合法候选，避免OE单独享受更好的底层机制而不提供同机制XY参照。

新候选元数据接口复用以前已验证的隔离实验，并移植当前安全写尾归还和元数据背压。算法0/3/4在候选生成处保持单方向，只有算法2保留完整OE合法候选；模式0在VA回写相同方向，精确OFF结果用于确认接口扩展没有改动原行为。

## 统一实验条件

13×13、4VC、每VC8槽、暂用258-bit flit、4-flit包、均匀非自身目的、预热300＋测量1200周期、接收端始终可收；源按原单游标和pid%4注入。按出生窗口选择全部样本，停生成后继续注入并完全排空，逐flit内容/目的/顺序/唯一性/VC所有权/error_o/X态及额外20周期空网检查。

首轮种子1234501、0.06；随后在结果前固定三组矩阵：1234501/0.06、42/0.06、1234501/0.04。每组复位DUT和统计，首组必须精确复现单档；报告全部组，不选择表现好的种子。平均、P99、窗口到达率、源积压和排空周期均保留。

## 已完成的阶段结果

| 相同0.06/种子1234501 | OE平均周期 | 同机制XY平均周期 | 状态 |
|---|---:|---:|---|
| 原策略/原滞回 | 1092.088784 | 58.628085 | OFF全部22字段精确复现 |
| 就绪轮询/原滞回 | 464.242左右 | 未单独运行 | 只作OE单因素，不称公平XY比值 |
| 就绪＋一跳存量/原滞回 | 309.187668 | 56.949499 | 仍5.43倍 |
| 就绪＋一跳存量/快重开 | 235.515272 | 54.763379 | 仍4.30倍 |
| 联合匹配＋一跳/快重开 | 164.498575 | 54.973772 | 仍2.99倍 |
| 联合匹配＋合法两跳/快重开 | 92.598762 | 54.951617 | 仍1.685倍 |

就绪轮询＋快重开OE423.737左右，也未达到目标。单独保留原TwoAware在到达时选择、只开快速重开的对照为109.532左右；它是算法4对照，不是原固定OE同义替换。所有前驱控制逐级精确复现，不能把跨机制收益简单相加。

## 两跳跨种子/负载结果

| 种子 | 注入率packet/node/cycle | XY均值 | OE均值 | OE/XY | XY P99 | OE P99 |
|---|---:|---:|---:|---:|---:|---:|
| 1234501 | 0.06 | 54.951617 | 92.598762 | 1.6851 | 159 | 330 |
| 42 | 0.06 | 52.030724 | 96.797503 | 1.8604 | 144 | 366 |
| 1234501 | 0.04 | 29.685933 | 30.264172 | 1.0195 | 65 | 63 |

0.04下均值相差约1.95%，P99略低，已接近但没有均值胜出；0.06两个种子明显未达目标，不能用0.04结果概括重载。源排队在原种子0.06降至0.556650左右，剩余差距主要在网络内92.042对54.439周期；这不同于最初以源端积压为主的现象。

## 功能与检查

- 模式1/2分配器定向各67项：关闭首选时合法备用、无就绪资源不授权、轮询/存量选择、已占VC不重用、显式归还只恢复对应VC。
- 模式3匹配器：全部512个3×3请求图、64个5×5图和1个增广路径场景，授权数量与独立递归枚举最大匹配一致，检查输入/输出唯一性。
- 模式4重复577图参考；固定两跳反例、到目的地截断、LOCAL代价检查通过。
- 两跳新策略原全网三阶段回归通过，每阶段1014包/4732flit，共3042包/14196flit，覆盖1/2/4/8/12-flit、4VC、镜像/分散/热点、源/接收背压及完全排空。
- 所有性能运行逐授权独立核对OE合法候选、存储候选、VC未被占用、active模式接收开启；匹配版本还核对每输入/输出最多一授权。原种子每算法147697次授权、15260包/61040flit、12277出生窗口样本。
- 三跳另有独立第三跳拥塞反例、目的截断及577图匹配参考，完整矩阵/回归在同目录后续结果中记录。

这些是有限功能与性能检查，不是形式无死锁证明，也不是全参数/全流量覆盖。更复杂的组合匹配与前瞻尚未综合，不能把周期级改善当作已验证的频率、面积或板级收益。

## 复现与数据

每个实验目录的scripts/simulation/入口与独立top/输出配对：

```bash
bash congestion/experiments/oe_ready_candidates/scripts/simulation/run_ready.sh 0 0 -generic_top ALGORITHM=2
bash congestion/experiments/oe_ready_candidates/scripts/simulation/run_ready.sh 2 1 -generic_top ALGORITHM=0
bash congestion/experiments/oe_ready_matching/scripts/simulation/run_matching.sh 3 1 -generic_top ALGORITHM=2
bash congestion/experiments/oe_ready_lookahead/scripts/simulation/run_campaign.sh 4 1 -generic_top ALGORITHM=0
bash congestion/experiments/oe_ready_lookahead/scripts/simulation/run_campaign.sh 4 1 -generic_top ALGORITHM=2
bash congestion/experiments/oe_ready_threehop/scripts/simulation/run_campaign.sh 5 1 -generic_top ALGORITHM=0
bash congestion/experiments/oe_ready_threehop/scripts/simulation/run_campaign.sh 5 1 -generic_top ALGORITHM=2
```

WSL Vivado2025.2沙箱外运行，未Windows综合。各run保留参数/宏、23份源文件SHA、编译/展开/仿真日志、完整latency_summary.csv及等待/链路统计。campaign每组统计文件按seed/rate命名，不跨组覆盖。

统一分析：oe_ready_candidates/scripts/simulation/analyze_ready_trials.py支持多个--root；核对所有运行SHA、仅允许的父源码差异、共同生成/驱动/计分板task（campaign仅将固定SEED替换为记录的case_seed）、OFF全部22字段、逐级前驱控制、重复运行精确一致和相同配置XY/OE的轨迹/样本一致。

完整数值和每个run目录见[oe_ready_trials_20261029.csv](oe_ready_trials_20261029.csv)，仅同配置公平配对见[oe_ready_pairs_20261029.csv](oe_ready_pairs_20261029.csv)。未配对的旧策略单因素会明确标记，不拿其他配置XY冒充参照。

## SA 联合匹配与必须保留的失败证据

在模式5之上，仅把SA从先选输入VC、再争输出改为对所有可发送的已锁定VC/出口联合匹配，XY/OE使用相同机制。未保护版本三组平均值分别为XY48.835465/OE49.083245、XY46.287111/OE47.121581、XY29.144004/OE28.889959。另加种子7与0.08压力点，全部记录于CSV；0.08仍是OE约567.859、XY约207.318，不能宣称全负载达到目标。

严格最大基数存在具体饥饿反例：LOCAL/VC0→EAST、LOCAL/VC1→SOUTH、NORTH/VC0→EAST同时持续合格时，追求两路传输会永久跳过LOCAL/VC0。原SA测试在第41个等待周期失败（目标0次、其他82次传输）；新VA负对照同样触发持续合格头部超40周期断言。不得把这两项改成通过或删掉。有限包排空和较低均值无法排除此类持续竞争问题。

## 等待保护版本

新副本oe_ready_aged（父2421b17）只修改VA/SA仲裁优先级。固定AGE_LIMIT=PORT_NUM*VC_NUM=20个合格未服务机会，饱和255；达到阈值后输入仅保留最老合格VC，输入顺序按龄期和轮询排序，先保护老请求，再匹配其他输入。暂时阻塞不增加龄期但保留已有等待，服务/请求消失才清零。没有改变OE合法候选、下游预约、TAIL写入归还或容量，也没有增加丢弃/超时完成路径。XY使用同样保护。该阈值按本地请求数固定，未按性能调参。

保持原断言的持续竞争测试：保护后SA目标128周期获6次服务、其他244次；VA目标128周期获6次分配，二者PASS。VA577图/SA593图独立枚举参考仍PASS；这些检查覆盖年轻请求图的最大匹配，老请求保护可有意牺牲基数。它们不是任意背压条件下的形式活性证明。

复现五点矩阵：

```bash
bash congestion/experiments/oe_ready_aged/scripts/simulation/run_campaign.sh 5 1 1 1 -generic_top ALGORITHM=0
bash congestion/experiments/oe_ready_aged/scripts/simulation/run_campaign.sh 5 1 1 1 -generic_top ALGORITHM=2
bash congestion/experiments/oe_ready_aged/scripts/simulation/run_mesh.sh 5 1 1 1 -generic_top ALGORITHM=0
bash congestion/experiments/oe_ready_aged/scripts/simulation/run_mesh.sh 5 1 1 1 -generic_top ALGORITHM=2
```

AGE0关闭对照已精确复现未保护OE49.083245全部22字段。最终五点和回归见下表，源SHA及公平配对已重新核验。

## 最终五点：同机制、同流量的周期级结果

|注入率 packet/node/cycle|种子|XY平均|OE平均|OE/XY|XY P99|OE P99|
|---|---|---:|---:|---:|---:|---:|
|0.06|1234501|48.420217|48.075426|0.9929|139|149|
|0.06|42|46.136860|46.830773|1.0150|126|148|
|0.04|1234501|29.166975|28.907373|0.9911|63|57|
|0.06|7|47.688213|46.031417|0.9653|140|136|
|0.08|1234501|212.116171|492.447056|2.3216|760|1359|

中档四点平均差距为−3.47%～+1.50%，三点略优、种子42略差，平均基本同水平；前两个0.06点OE P99仍偏高。0.08平均2.32倍、P99亦较差，饱和区目标未达到。原种子0.06的OE从正式版本1092.088784降到48.075426；公平参照须用同机制XY48.420217，不能只拿旧XY58.628085作比较。

0.08源队列平均等待XY58.110173/OE224.017995，网络平均等待154.005998/268.429061；停止生成时源积压1636/4995、网络在途2104/2678；测量窗口接收率0.067170/0.047751，完全排空周期2215/2668。这表明仍有明显高负载吞吐/回压差距，不能靠排除源队列等待或只统计已到包掩盖。现有数据不足以把剩余差距唯一归到某个仲裁或OE约束，应下一步针对锁定方向的真实SA等待及路线分布建立独立只读诊断。

观测边界：这些候选实验的current_waits中，SA部分沿用了VA组合granted_port作为方向；无VA请求时它不一定等于包已锁定的SA out_port。因此SA等待/备用出口分类不作为本轮归因证据。上述延迟、源积压、真实链路计数和SA授权合法性断言分别使用计分板/实际接口，不受此观测口径影响。保留原TB及SHA，不为美化结果回改已运行源码。

保护版XY/OE三阶段全网长包/背压回归均PASS，每算法3042包/14196flit全部完成，覆盖1/2/4/8/12-flit与源/接收背压。最终统一核验49组唯一性能记录、20组同配置XY/OE配对、所有23源SHA、共同流量/计分板task、OFF22字段和逐级父控制均通过；保留饥饿负对照失败。各run精确路径在CSV。

最终campaign：XY run_mode5_flow1_sa1_age1_XFQtlh2L、OE run_mode5_flow1_sa1_age1_NfKXwwfB，位于oe_ready_aged/vivado_sim_wsl/tb_oe_aged_campaign_sim。全网回归：同子项目tb_oe_aged_mesh_sim下XY M5DU75ml、OE WwmRDUAB。尚未综合或验证频率/面积；本轮不将实验代码合入正式congestion/src或根src。
