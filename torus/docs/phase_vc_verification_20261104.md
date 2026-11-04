# 分阶段多副本 VC 改造与验证（2026-11-04）

<!-- Modify by Michael Tan，20261104: document implemented phase pools, exact controls, resource costs and verified performance. -->

## 实际修改与默认行为

只修改3个RTL：`torus/src/noc.sv`、`rc_unit_Xiugai2.sv`、`torus.sv`。根`src/`未改；VA、SA、FIFO、metadata接口及TAIL读出归还时序均未改变。

- 默认仍为4个物理VC，保持原位宽和FIFO深度。通过编译宏`NOC_VC_NUM=8/16`选择扩展配置。
- 由物理输入端口确定X/Y维度，VC编号仅表示dateline前后阶段。低半区为前阶段、高半区为后阶段，每阶段分别有2/4/8个副本；RC输出整个阶段的合法掩码。
- 同维度一旦进入后阶段不能退回前阶段；跨界跳本身用后阶段；X→Y重新初始化Y阶段；Y→X仍拒绝。
- LOCAL注入的编号不携带网络阶段。性能对照源端始终固定`id%4`、单包有序游标，LOCAL弹出合法掩码始终仅低4位，接收端始终ready；扩网络VC不会同时扩大逻辑端点VC数量。
- 允许分配器按已有`available & allowed`机制选择副本；BODY/TAIL仍沿HEAD的出口/下游VC锁定。没有提前归还、修改散列/流量、升级仲裁或放宽死锁规则。

原RC/集成/拥塞TB的分类断言同步新协议，使原有默认入口继续可用。新功能仍建立独立phase命名的6组TB/入口，未用原TB冒充新功能结果；旧分类的历史版本保存在Git提交3c31c2b，可用固定源码重新编译。

## 控制变量与资源成本

| 比较对象 | 总VC/输入端口 | 每网络跳合格VC数 | 逻辑端点VC | 每VC flit深度 | flit位宽 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 原Mesh | 4 | 4 | 4 | 8 | 26 |
| 旧Torus | 4 | 1 | 4 | 8 | 26 |
| 新Torus默认 | 4 | 2 | 4 | 8 | 26 |
| 新Torus扩展 | 8 | 4 | 4 | 8 | 27 |
| 新Torus扩展 | 16 | 8 | 4 | 8 | 28 |

旧/新Torus4保持相同拓扑、最短XY方向、VC数、深度、位宽、端点和调度/归还协议，仅改变类别组织与相应资格解码，是本轮归因最直接的对照。Mesh4与新Torus4则控制VC数/数据FIFO深度；两种拓扑本身链路不同，Torus metadata还有合法掩码字段，不能称面积/功耗完全相同。新Torus8让每跳候选数等于Mesh4，但数据FIFO配置容量/物理输入端口为2倍；16为4倍且每跳候选8个，不是每跳等资源对照。mask/VC编码变宽还增加metadata、控制与连线开销，未综合，不能用容量比例替代真实面积比例。

所有模式的出生4000周期、前1000预热、4flit包、同种子/出生轨迹/非自身目的/接收条件和统计口径完全相同。总延迟覆盖出生窗口1001～4000全部样本，包含排空后才收到的包；保留出生到HEAD的源排队。名义注入率为包/节点/周期，吞吐为flit/节点/周期。

## 性能结果：50组完整通过

5种配置各执行预声明10点，共306930包/1227720flit全收发。10条轨迹跨5模式逐字节一致。原Mesh与旧Torus重新编译后，其trace/summary/逐包时间戳均与修改前结果精确相同；旧Torus源码从固定3c31c2b导出到独立运行目录，未拿已修改共享模块当旧控制。

平均总延迟单位为周期：

| 流量 | 种子 | 包注入率 | Mesh4 | 旧Torus4 | 新Torus4 | 新Torus8 | 新Torus16 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 均匀 | 1 | 0.01 | 12.802 | 11.527 | 11.273 | 11.263 | 11.263 |
| 均匀 | 42 | 0.01 | 13.001 | 11.516 | 11.227 | 11.228 | 11.228 |
| 均匀 | 1 | 0.04 | 14.348 | 13.817 | 12.299 | 12.291 | 12.291 |
| 环绕对角 | 1 | 0.04 | 12.775 | 11.419 | 10.376 | 10.376 | 10.376 |
| 均匀 | 42 | 0.04 | 14.621 | 14.491 | 12.562 | 12.543 | 12.544 |
| 均匀 | 1 | 0.08 | 18.130 | 37.894 | 14.883 | 14.674 | 14.688 |
| 环绕对角 | 1 | 0.08 | 13.570 | 16.032 | 11.197 | 11.197 | 11.197 |
| 均匀 | 42 | 0.08 | 18.265 | 32.937 | 14.969 | 14.789 | 14.791 |
| 均匀 | 1 | 0.12 | 31.616 | 800.932 | 21.512 | 19.271 | 19.293 |
| 均匀 | 42 | 0.12 | 31.990 | 767.808 | 21.847 | 19.214 | 19.277 |

在本矩阵中，新4/8/16的均延迟均低于Mesh，P99均不高于Mesh；仅是所测两种子/两个流量模式/有限窗口结论，不是所有流量的普遍保证。8→16未见有意义的额外收益，不据此宣称16VC在所有场景都无效。

0.12、种子1的分项：

| 指标 | Mesh4 | 旧Torus4 | 新Torus4 | 新Torus8 | 新Torus16 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 总均延迟 | 31.616 | 800.932 | 21.512 | 19.271 | 19.293 |
| 源排队 | 7.590 | 770.843 | 4.854 | 3.509 | 3.507 |
| 入网后 | 24.026 | 30.089 | 16.658 | 15.762 | 15.787 |
| P99 | 102 | 1878 | 58 | 45 | 45 |
| 窗口输出 | 0.47807 | 0.36403 | 0.47756 | 0.47753 | 0.47751 |
| 停止生成后排空周期 | 29 | 1838 | 20 | 20 | 20 |

默认4VC已把均延迟从800.932降到21.512，说明本次无需先扩到16VC才能解除首版严重限制。8VC是每跳候选数对齐的补充结果，不用扩容结果掩盖默认配置的表现。高负载窗口输出主要跟随约0.48的输入，不能据此确定这些实现的最大吞吐或稳态饱和点；本轮没有提升到更高注入率。

完整数据含样本量、P95/P99、源排队、在网延迟、输入/输出、排空、跳数、trace SHA与日志目录：[comparison.csv](phase_vc_20261104/comparison.csv)。

## 结构验证：单跳气泡消除

同一非跨界一跳、单源饱和、always-ready，源端仅在4个接入VC内选择可用者，每档256包。所有255个相邻HEAD间隔均核对：

| 配置 | 4flit HEAD间隔 / 吞吐 | 16flit HEAD间隔 / 吞吐 |
| --- | ---: | ---: |
| Mesh4 | 4 / 1.0 | 16 / 1.0 |
| 旧Torus4 | 8 / 0.5 | 20 / 0.8 |
| 新Torus4/8/16 | 4 / 1.0 | 16 / 1.0 |

新方案使用阶段内副本隐藏原归还间隙，而不是改变归还协议。数据见[singlehop.csv](phase_vc_20261104/singlehop.csv)。这不意味着全网任意竞争下所有链路都始终线速。

## 功能与依赖检查

新增phase功能25次仿真全部PASS：

- RC：4/8/16VC各覆盖5×5、4×4、2×3、2×2的全坐标、全标签、全部输入端口/VC及非法地址，共1827840检查。
- VA/metadata：3配置均验证合法副本、合法池耗尽但另一池空闲时拒绝、释放后重分配、zero mask、逐包不同mask保存。
- 集成：4/8/16的5×5，以及8VC的4×4/2×3/2×2，全源目的HEADTAIL/4flit、并发、多包metadata、周期背压、复位后重传；分别950/950/950/464/114/68包。
- 拥塞：3配置各650包，含600包持续注入/接收端暂停及恢复、复位后传输和额外25个16flit长包（超过深度8）在周期背压下排空。每组2450flit。
- 单跳：5配置×2包长共10次，每次256包，前述气泡检查全部通过。

每个网络TB检查目的、顺序、负载、重复、error/X、真实链路跳数守恒和最终FIFO/metadata/写包所有权/下游VC释放，不仅检查控制台PASS。

抽象依赖模型含同阶段所有副本转换的并集，4/8/16各49尺寸，共147配置/123627源目的路径无环。[dependencies.json](phase_vc_20261104/dependencies.json)。沿用独立输入VC、包级独占、源最终提供完整包、终端最终服务假设，不是完整RTL形式化证明。

另运行原默认RC/集成/拥塞入口，3项全部PASS，编译源SHA复核一致。目录分别为`tb_torus_rc_sim/run_Y231Py0K/`、`tb_torus_integration_sim/run_jFB2M9q9/`、`tb_torus_congestion_sim/run_wBCMt5Jy/`，均在`torus/vivado_sim_wsl/`内；[兼容性记录](phase_vc_20261104/compatibility.csv)。

## 复现与审计

独立入口`run_tb_torus_phase_{rc,vc_allocator,integration,congestion,performance,singlehop}.sh`统一调用公共runner，参数为`4|8|16`；performance/singlehop还可用`mesh|legacy`，集成/拥塞可再传NX NY。

```bash
python3 torus/scripts/simulation/check_torus_phase_dependencies.py torus/docs/phase_vc_20261104/dependencies.json
bash torus/scripts/simulation/run_tb_torus_phase_rc.sh 16
bash torus/scripts/simulation/run_tb_torus_phase_vc_allocator.sh 8
bash torus/scripts/simulation/run_tb_torus_phase_integration.sh 8
bash torus/scripts/simulation/run_tb_torus_phase_performance.sh 8
bash torus/scripts/simulation/run_torus_phase_campaign.sh functional
bash torus/scripts/simulation/run_torus_phase_campaign.sh performance
bash torus/scripts/simulation/run_torus_phase_compatibility.sh
python3 torus/scripts/simulation/analyze_torus_phase_campaign.py torus/docs/phase_vc_20261104/campaign_manifest.json torus/docs/phase_vc_20261104
```

实际campaign目录为`torus/vivado_sim_wsl/torus_phase_campaign/functional_tzh8PDxt/`及`performance_iIV0k11i/`。完整每项run路径见[campaign_manifest.json](phase_vc_20261104/campaign_manifest.json)，功能PASS行见[functional.csv](phase_vc_20261104/functional.csv)。每个top有独立结果目录，每次编译保留源码SHA、配置、xvlog/xelab日志，每个case保留xsim.log；性能附trace/packets/summary，单跳附events.csv。

[自动审计](phase_vc_20261104/audit.txt)核对50性能点、10条共同trace、20份旧控制精确复现、完整计数/时间戳/跳数、25功能case及10单跳所有间隔，当前编译源码SHA一致。[resources.csv](phase_vc_20261104/resources.csv)及配置/源码指纹随结果归档。公共runner后续把配置中的source_vc字段明确为performance_source_vc；此前该字段描述性能模式，功能模式的源策略以对应TB为准。

仿真无功能失败；保留原有跨generate接口及环境展开警告。未开展Windows综合、实际Fmax/面积/功耗或板级验证。原分析报告为修改前历史证据，本报告为修改后的当前状态。更高负载、多种子、其他流量与扩VC后的调度效率仍待后续任务，不在本轮结果中提前宣称。

## Git与Windows交付

待完成最终回归后按项目规则提交/推送；Windows工作副本只做fetch和保护性fast-forward，不覆盖既有修改。实际提交与同步结果完成后追加。
