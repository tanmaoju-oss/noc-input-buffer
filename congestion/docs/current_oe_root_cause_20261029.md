# 修改后 OE 与 XY 大差距：根因证据（2026-10-29）

<!-- Modify by Michael Tan，20261029: replace speculative attribution with current-protocol observations, exact offered-route demand and controlled counterfactuals. -->

## 本轮定位

当前比较的是已交付eccd9af/3581978的安全多包接入协议，正式congestion/src和根src均未改。主问题定位到当前ALGORITHM=2的无状态固定出口选择与该工作点的局部超载，而不是OE禁转规则必然导致18.6倍延迟。原滞回流控进一步放大回压。最低VC优先和两级仲裁有损失，但本轮不支持把巨大差距主要归给这两项。

这是针对13×13、4VC、深度8、4-flit、均匀非自身目的、种子1234501、预热300+测量1200、注入0.06的结论；不是所有OE、所有流量或稳态性能证明。单因素差值不能当成可相加的固定原因占比。

## 1. 不是只看到积压，而是重建出具体链路的过量需求

analyze_congestion_offered_routes.py逐周期重建原始生成器：每源ID、源目的、出生时刻均保留；15260总生成包、12277出生窗口样本、哈希d84c82f8逐项与实际RTL记录一致。使用此前已被真实rc_unit全坐标/ID校验位路径审计核对的独立path函数。当前正式ALGORITHM=2不读取动态资源，也不在VA等待期间重选；所以给定头字段后，各包路径固定，可以确定重放。

对出生窗口中每个样本的完整路径累计4-flit需求，再除以1200生成周期：

| 精确流量路径需求 | XY | 当前OE |
|---|---:|---:|
| 峰值链路需求flit/生成周期 | 0.893333 | 1.343333 |
| 需求超过1的有向链路数 | 0 | 49 |

OE的(11,5)→SOUTH、(11,6)→SOUTH、(11,7)→SOUTH各承接403个样本包，即1612个flit；单链路每周期只能发送1 flit，至少需要1612个发送周期，超过1200生成周期。即便理想仲裁也不能在1200周期内处理完这批需求；实际包还有到达和逐跳依赖，必须延长排空。需求/生成周期不是该链路在测量窗口内实际利用率，也不直接给出平均延迟下界或长期饱和点。

同一OE测量窗口中上述三条链路实际利用率约61.58%/68.08%/66.83%；不仅需求集中，还存在阻塞链和非满速服务。只说全网平均利用率低，不能排除局部路径需求超载；只说局部超载，也不足以量化全部1092周期。

完整624链路×2算法计数见current_offered_route_demand_20261029.csv。它是精确刺激重放和已审计的路径模型结果，没有冒充本轮逐包链路实测。

## 2. 当前OE到底在等什么

新增tb_congestion_current_profile，只读VA/SA/流控/VC选择和输出。XY/OE全部22个CSV字段精确复现当前正式结果58.628085/1092.088784；源码SHA与当前文件一致，生成、驱动、计分板等共同task未改变。

| 输入VC请求周期，1200测量周期 | XY | OE |
|---|---:|---:|
| VA：所选方向无可预约VC | 52307 | 417686 |
| VA：有VC但仲裁未获配 | 14061 | 16510 |
| SA：已获配但所选VC的on_off关闭 | 83101 | 854850 |
| SA：允许发送但未获仲裁 | 470588 | 139497 |
| 成功VA授权 | 117656 | 45794 |
| 成功SA传输 | 470370 | 183815 |
| 全网624链路平均利用率 | 56.344% | 21.962% |
| 链路利用率变异系数 | 0.355 | 0.701 |

修改后的直接大等待已经转到SA背压，不能沿用旧协议“SA等待为0、98.3%等VA”的比例。计数单位是输入VC请求周期，覆盖不同包和等待阶段，不是包延迟的独立因果份额。

OE无VC等待中，有173349周期存在另一个合法方向的可预约且on_off开启VC；已获配但阻塞时有325666周期存在其他合法方向可接收资源。不过SA阶段可能已发送HEAD，不能直接切换方向，以上只能标记早期选择可能错失的机会，不能据此在包中途改路由。

每个输出有原始可发送请求却没有发送的周期为XY62799、OE27933（包括LOCAL）；VA有可分配请求却没有授权的输出周期为886/636。这类输出计数与输入VC等待周期不是同一单位，不能混算或声称更大匹配一定能回收全部空转。当前没有证据把主要差距归给“仲裁器逻辑写错”。

## 3. 排查一个此前怀疑：选中了关闭的低编号VC

隔离oe_current_diagnosis复制当前22RTL，仅vc_allocator增加现有on_off输入及可接收VC优先选择，router接线；不改变归还、方向、仲裁、缓冲。OFF/ON共用同一源码，只切编译宏/记录参数，OFF全部22字段精确复现当前OE。

当前OE窗口内，45794次授权中，539次选中的VC关闭，216次同时有另一可预约且可接收VC。干预消除了“还有可接收VC却选关闭VC”的计数，但结果只把均值1092.088784降为947.116885（13.275%），P99反而2729→2993，排空4010→4306周期。

它有可测影响，但不能解释主要差距，也不是已验收的正式优化。不能只根据均值改善忽略尾延迟恶化。正式RTL不合入。

## 4. 验证流控强滞回的放大作用

隔离oe_current_flow仅修改circular_buffer的重开阈值：OFF保持占用7关闭、降至1重开；ON仍在7关闭，但降至6即重开，容量、关闭阈值、TAIL成功写入归还、元数据和所有路由/仲裁不变。OFF/ON共享源码，OFF全部22字段精确复现OE。并补测相同ON策略下XY。

| 保持关闭阈值，仅减小重开滞回 | 原策略 | 快速重开 |
|---|---:|---:|
| OE平均总延迟 | 1092.088784 | 688.437403 |
| XY平均总延迟 | 58.628085 | 55.736418 |

OE明显更敏感；SA on_off等待由854850降为697000输入VC周期。这里没有使用~is_full_o重新分配VC，所有权仍由成功写入TAIL/HEADTAIL结束。干预有因果收益，但OE仍远慢于XY，说明不能把全部差距归给滞回；结果不自动合入正式RTL，也没有为该实验跑完整生产回归。

## 5. 区分OE规则和出口选择策略

新增tb_congestion_oe_policy_compare，使用完全相同的22个正式RTL、流量、缓冲、VA/SA、源调度和原滞回，只切已有ALGORITHM=3/4的OneAware/TwoAware。ALGORITHM在mesh/router/input层仅传参，实际改变rc_unit/congestion_decision的选择。两策略仍受相同OE合法候选限制，但按实时占用指标选择，包含其原有平局策略。

最终结果：OneAware184.587周期、TwoAware136.862周期，远低于当前OE1092.089，XY为58.628。逐次真实VA授权的OE候选断言通过，核对没有违规转向；精确值及目录见下节。

这组比较把巨大差距主要定位到“如何在合法候选中选择出口”的整套策略，包含资源反馈和同分处理；不能单独证明单比特散列本身是全部原因。昨天“只换完整字段散列”没有稳定改善，本轮仍保留这个反例。流控收益、VC选择收益和选路收益有交互，不能相加。

## 可支持的因果链

固定头字段异或选择、不看资源且入队锁定方向 → 在该均匀流量工作点把路径需求集中到部分链路 → 包在下一跳和on_off处等待、缓冲不能及时排出 → 强滞回延长停止接收 → 上游及单游标源发送器回压 → 后续出生样本长时间排队。

缓冲接入修复只允许更多包排队，没有改变固定路径需求矩阵；因此之前仅修复多包接入后仍高延迟是可以预期的。当前差距不应作为OE理论性能结论，应标为这套固定选择实现、流控和测试工作点共同作用的结果。

## 代码和复现

- 只读观测：run_tb_congestion_current_profile.sh；算法0/2。
- 观测分析：analyze_congestion_current_profile.py，检查22字段、授予计数守恒及源码SHA。
- 精确路径需求：analyze_congestion_offered_routes.py --reference congestion/vivado_sim_wsl/tb_congestion_admission_latency_sim/run_EheVCm52。
- 可接收VC优先：experiments/oe_current_diagnosis/scripts/simulation/run_vc_choice.sh，模式0/1、算法2。
- 流控重开：experiments/oe_current_flow/scripts/simulation/run_flow.sh，模式0/1、算法2，另模式1算法0。
- 现有OE选择策略对照：run_tb_congestion_oe_policy_compare.sh，算法3/4，含逐授权合法候选检查。
- 统一反事实核对：analyze_congestion_cause_controls.py --run LABEL=RUN_DIR，核对输入轨迹、完整计分板、所有源码SHA、仅允许的RTL差异和共同task。

所有脚本路径均在congestion/scripts/simulation或上列隔离实验内。WSL Vivado2025.2沙箱外执行，每run保留参数、编译/展开/仿真日志、source_sha256.txt、latency_summary.csv和观测CSV。无综合、无板级验证、无正式RTL修改。

## 最终授权合法性与统一验收

OneAware最终run_hSgyd1xo、TwoAware最终run_h22Tko79均通过147697次实际VA授权的独立OE合法候选断言，均值分别精确复现184.586870/136.862181。未增加绕远或违规转向以获得改善；两算法实际授权数相同，包全部送达，源队列和网络完全清空。相对当前OE—XY差距，切换OneAware/Twoware整套出口选择策略分别消除了本次差值的87.812%/92.430%；不是各机制可相加的份额，也不证明单比特异或一项独立造成92%。

| 正式RTL，保持原滞回 | 平均总延迟 | 源排队 | 网络内 |
|---|---:|---:|---:|
| XY | 58.628085 | 0.759387 | 57.868698 |
| 当前OE | 1092.088784 | 771.594526 | 320.494258 |
| 同OE候选的OneAware | 184.586870 | 21.795308 | 162.791561 |
| 同OE候选的TwoAware | 136.862181 | 13.108088 | 123.754093 |

9次最终运行全部通过统一脚本核验：生成和样本口径一致；两个OFF干预及只读观察逐项复现22字段；每run全部22RTL及TB的SHA256匹配最终文件；共同生成、驱动、计分板、统计、排空task规范化比较一致（仅剔除新增只读采样调用）；VC/流控实验仅有允许的2/1个RTL文件差异。每run15260包/61040flit送达，12277出生窗口样本，未使用慢包截尾均值。

原始精确数值和全部9个run目录在[current_cause_controls_20261029.csv](current_cause_controls_20261029.csv)。只读当前等待汇总在[current_protocol_profile_20261029.csv](current_protocol_profile_20261029.csv)。正式congestion/src及根src与本轮父版本保持一致。

当前工作已找到这档负载下巨大差距的主要性能来源，不意味着现有OE的禁转公式写错，也不意味着硬件实现某个单独布尔表达式是唯一根因。下一步若要正式修复，应明确OE的选择策略与软件参照配置，单独设计候选方向/资源选择的受控改造；不直接合入本轮实验的流控或VC策略，不按期望曲线反复调参。

Git空白检查：新TB/脚本/报告通过；隔离RTL副本保留正式源既有行尾空白和CRLF，新增的三个源码差异以no-index对比检查没有新增空白问题，未为了格式清理修改基线或使运行SHA失效。

### 当前 OE 归因交付（2026-10-29）

提交c165636（Identify current OE latency causes with matched controls and route-demand replay）已推送origin/chore/reorganize-project-layout，仅新增观测/隔离实验/分析与文档，正式congestion/src及根src不变。Windows fetch成功，pull --ff-only仍因已有修改及未跟踪congestion文件保护性中止，HEAD保持cdcc7a9；未覆盖、清理或stash。九组最终验证数据、完整run路径及因果边界见归因报告。

<!-- Modify by Michael Tan，20261029: record pushed current-protocol causal evidence and protected Windows synchronization. -->
