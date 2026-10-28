# Congestion 代码静态分析

<!-- Modify by Michael Tan，20261028: record received RTL architecture, static findings and verification gaps. -->

分析日期：2026-10-28。范围：22 个接收 RTL 文件及原始 `tb_mesh_injection_1.1.sv`。只读分析源码，未编译、仿真或综合，未核查 Excel 数据。24 个导入文件重新按 import_manifest.tsv 核对 SHA256，全部一致。以下明确区分代码事实与需要动态验证的影响。

## 1. 总体结构与数据流

当前为 13×13 二维 Mesh，169 个路由器，每路由器 5 个端口、每端口 4 VC、默认每 VC 8 flit。noc.sv 声明 noc_params 包，并非 NoC 顶层；mesh.sv 为网络顶层。共有 3380 个 VC、默认 27040 个 flit 存储槽。flit 为 258 位（标签 2、VC 2、数据 254）。

数据通路：mesh → router → input_block → input_port → input_buffer → circular_buffer；input_buffer 用独立元数据 FIFO 保存每包的输出方向、下游 VC 及分配状态，VA 分配下游 VC，SA 仲裁，crossbar 和 router_link 送到下一跳。router_link 为组合直连，没有独立链路寄存器。

拥塞通路：circular_buffer.num_flits → input_buffer.priority_usage_o → input_port.vc_occupancy_o → router.router_state_o → state_information_collection → 全网 metrics → 每个 input_port 的 rc_unit/congestion_decision。HEAD 接收时将所选方向写入元数据，后续 BODY/TAIL 沿同一方向；排队期间不会重新选路。

这是全局状态组合分发模型：各路由器直接读取全网实时 metrics，没有逐跳传播协议、状态延迟、采样周期或寄存流水。占用量来自寄存器，当前未发现拥塞反馈本身构成组合环；但大规模布线、扇出和时序代价仍需综合验证。

## 2. 采集和决策含义

state_information_collection 对每输入方向的 4 VC 求和，默认范围 0～32；再对五方向求和得到 0～160 的 node_total_flow。该名字表示当前存量，并非每周期流量或历史吞吐量。is_full/is_empty 虽随 router_state 输出，采集计算实际只使用 occupancy。

拥塞等级按容量百分比划分 1～9：默认占用 0～3 为 1，4～6 为 2，7～9 为 3，10～12 为 4，13～16 为 5，17～19 为 6，20～22 为 7，23～25 为 8，26～32 为 9。空队列也是等级 1。

| 参数 | 行为 |
|---|---|
| ALGORITHM=0/1 | XY / YX 固定维序 |
| ALGORITHM=2 | Odd-Even 合法候选中，按包 ID 和坐标的异或位选择；是确定性散列，并非时序随机源 |
| ALGORITHM=3 | OneAware，在 OE 候选中比较相邻节点对应输入方向指标 |
| ALGORITHM=4 | TwoAware，按剩余 X/Y 距离组合两跳，部分第二跳包含转弯 |
| ALGORITHM=5 | ThreeAware，沿 X/Y 直线各取三跳比较，未套用 OE 候选限制 |
| DECISION_REFERENCE=0/1/2 | 方向占用量 / 方向拥塞等级 / 节点总存量 |
| AGGREGATION=0/1/其他 | 求和 / 最大值 / 加权和；默认权重 7、3、0 |

取东邻居 WEST 输入、北邻居 SOUTH 输入等方向关系与网络连线相符。所谓平均实际为求和：同样两个或三个有效项时排序等价；边界缺项、不同路径项时需另行定义。OneAware 不使用聚合参数。One/TwoAware 相等时偏 Y，ThreeAware 相等时偏 X，性能比较存在不同平局策略。

## 3. 优先处理的问题

### P1：VC 可分配语义与分配器释放条件冲突

依据：input_buffer_src_circular_full.sv:192 将 vc_allocatable_o 每周期赋为上一周期的 ~is_full_o；vc_allocator.sv:99 将该信号作为已占 VC 的重新可用条件。一个包仍在传送、VC 尚未满时，分配器即可重新开放它。元数据 FIFO 支持多个完整包排队，但 write_packet_open 不接受前包 TAIL 之前的新 HEAD，也没有多源包交织重组能力。

由此存在前包未结束，另一输入获配同一输出 VC，导致包交织、写拒绝和资源滞留的风险。具体触发需用两个不同输入竞争同一输出、前包中途停顿的定向 TB 证实。不能仅用增加元数据 FIFO 证明 VC 共享安全；必须明确包所有权保持到 TAIL、或设计严格的包级序列化协议。

### P1：原始 TB 的监测变量具有静态初始化语义

依据：testbench/tb_mesh_injection_1.1.sv:416～428，monitor_outputs 为未声明 automatic 的模块级 task，xs、ys、pid、latency 用声明赋初值。SystemVerilog 静态局部变量的声明初始化仅执行一次，不会随每次进入该语句重新取当前 flit。这会破坏匹配和延迟统计；编译器可能给出静态初始化警告，尚未编译确认工具诊断。

应使用 automatic 生命周期或先声明后逐次赋值，再独立验证已知延迟的单包。不能把原始 TB 打印平均延迟当作正确性证据。

### P1：ThreeAware 无 OE/逃逸 VC 限制

依据：congestion_decision.sv:421～464，只在最短路径 X/Y 候选间按指标选择，没有奇偶列转向约束；4 VC 分配也没有逃逸通道分类。自适应路径可产生不同维度顺序的通道依赖，不能继承 XY 或 OE 的无死锁保证。当前仅能确定缺少该约束，未通过仿真证明实际死锁。

同时默认 WEIGHT_HOP3=0，加权 ThreeAware 的第三跳不参与结果；直线前瞻也没有按剩余目的距离截断，会采到目的节点之后的状态。越界取 0，而真实空方向等级为 1，对边缘路径有偏置。ThreeAware 注释标明预留，应按未完成算法处理。

### P1：原始 TB 无完整排空与包正确性判据

依据：run_single_rate 在生成阶段结束后直接停止 inject_from_fifo，仅等待 500 周期；源 FIFO 中可能有未发送的 BODY/TAIL，使已入网 HEAD 无法完成。monitor_outputs 只匹配尾 flit 的源和 ID，不核查实际出口是否等于目的，不检查 HEAD/BODY/TAIL 顺序、负载、重复或未知尾；不存在 assert/$fatal/$error 自检，也未读取 error_o。

多注入率之间仅清软件统计和源 FIFO，不复位 DUT，遗留包可能进入下一轮并与重置的 ID 混淆。正确顺序应为停生成、继续注入源队列、以所有已生成包完成且网络为空结束，超时显式失败；独立轮次复位或严格确认全网清空。

## 4. 参数化和实现问题

- mesh 的尺寸参数与 noc_params 中固定 13×13 类型并非统一来源。router 和 collection 使用包级尺寸；仅改 TB/mesh 参数不能可靠得到另一规模，可能发生端口宽度调整/维度不匹配。小规模验证前必须先解决配置一致性。
- occupancy、方向和总量位宽全部由 BUFFER_SIZE_DEFAULT=8 固定推导，但各模块允许单独改 BUFFER_SIZE；深度增大后会截断或累计溢出。当前默认 8 的数值范围可覆盖。
- input_port_Xiugai2.sv:125～126 的 data_cmd 只给动态选中的一个 VC 赋值，其余没有默认赋值，存在组合块不完全赋值/锁存风险。写使能为零可减少功能影响，但不能代替完整组合赋值。
- mesh 边界未显式终止外向接口。合法最短路径通常不访问外边界，但非法目的、未知态或路由异常会接触未驱动反馈；应定向检查 X 传播并加边界约束。
- circular_buffer 在空队列 read+write 时会写 memory，却保持占用/指针不变；当前 input_buffer 用 accept_read 屏蔽空读，正常顶层路径规避该组合，不能直接断言当前网络因此丢包。
- on_off 在满时关闭、仅排空到 0 才重新打开，属于强滞回；须评估吞吐影响及反馈延迟，当前没有量化结论。
- 两级 RR 的第一级按局部授权推进，即使未获第二级授权也会轮转；不能仅凭模块名宣称最终授予公平性已验证。

## 5. 性能统计口径

原始 TB 默认 ALGORITHM=4、AGGREGATION=0、DECISION_REFERENCE=0、Random、种子 1234501、四 flit、注入率 0.11、4000 周期。时间戳记在源软件 FIFO 生成时，因此理想修正后的延迟也包含源排队，并非只计网络内 HEAD 到 TAIL 延迟。

总生成率为 packet/node/cycle，四 flit 对应目标 flit 负载 4 倍。接收平均只涵盖窗口内已匹配的尾包，未完成包没有纳入平均，存在截尾偏差。injection_packet_invalid_num 用“理论最大包数减到达包数”，不能解释成实际丢包。12-bit packet_id 在长时间或高负载下回绕，而时间戳以未截断 int pid 索引；默认配置每源至多生成 4000 包，尚不会回绕。FLIT_LEN=1 仍生成 HEAD+TAIL 两 flit，需限制参数或实现 HEADTAIL。

## 6. 后续验证建议

1. 先独立测 collection：全零、全满、各阈值边界、各方向/VC 独立变化与复位后结果。
2. 独立测 rc/decision：全坐标合法性、曼哈顿距离单调减少、OE 候选约束、One/TwoAware 各剩余距离分支、平局及边缘前瞻。
3. 针对 VC 所有权风险，测两输入竞争、HEAD 后停顿、长包背压、连续 HEADTAIL 和包尾交接；同时断言写拒绝为零、资源不重复持有。
4. 建立新全网自检 TB 和独立 WSL 入口，跟踪每个源/ID 的包和 flit 内容，核查错目的、丢包、重复、包内顺序、error_o、未知态和完全排空；性能比较放在功能通过之后。
5. 先 XY/YX 基线，再 OE、OneAware、TwoAware；ThreeAware 先明确死锁规避和前瞻定义。未经修正的历史 Excel 和现有 TB 输出都不作为新验证结论。

静态分析命令使用 rg、cat、sed、nl 和 Python hashlib；没有执行 xvlog、xelab、xsim 或 Vivado 综合。

## 7. 与当前主项目 src/ 的逐文件对比（2026-10-28）

<!-- Modify by Michael Tan，20261028: compare received congestion RTL against current mainline working tree. -->

对比对象是当前 Linux 工作区根 src/，不代表历史交付时版本。22 个 congestion RTL 中：2 个新增、9 个现有文件有代码差异、11 个逐字节一致。对已有文件剔除块/行注释、归一化行内空白后复核差异；没有仅注释变化的文件。未修改任何 RTL。

| 文件 | congestion 相对当前主项目的差异 |
|---|---|
| noc.sv | 包级规模 5×5→13×13；新增源坐标、12-bit packet_id、8-bit backup，head_pl 16→218；FLIT_DATA_SIZE 改用 $bits(head_data_t)，完整 flit 26→258 bit；新增状态/指标类型与固定位宽常量 |
| mesh.sv | 模块默认规模 2×3→13×13；增加算法参数、全网状态采集实例、metrics 分发和调试输出；已有节点/水平/垂直连线结构保持 |
| router.sv | 增加算法参数传递、VC 占用量汇总及 full/empty 推导、metrics 输入；VA/SA/crossbar 实例机制保持 |
| input_block_Xiugai2.sv | 增加算法参数与占用量、metrics 端口及逐层连接 |
| input_port_Xiugai2.sv | 增加算法参数、占用量输出，向 RC 传源坐标/包 ID/metrics；新增 sa_sel_vc_reg 和 sa_valid_reg 寄存器，但输出仍使用原始 SA 信号，新增寄存器未被消费 |
| input_buffer_src_circular_full.sv | 增加占用量输出；VC 释放由 meta_pop_cmd 改为 ~is_full_o；其余有效元数据 FIFO/读写控制基本保持，logic 合并声明拆开不改变语义 |
| circular_buffer_Xiugai3.sv | ON_OFF_LATENCY 2→1；新增 first_flit_o 与 num_flits_o 输出；核心指针、存储和占用计数逻辑保持 |
| rc_unit_Xiugai2.sv | 原 XY 扩展为 XY/YX/OE/OneAware/TwoAware/ThreeAware；增加源坐标、包 ID、metrics 输入与算法选择；原条件中的单 bit 位运算部分改为逻辑运算 |
| separable_input_first_allocator.sv | 默认 VC_NUM 4→2；现有 VA/SA 实例均显式传入包级 VC_NUM=4，因此在当前连接下不改变实际 VC 数 |
| state_information_collection.sv | 新增：全网占用量求和及拥塞等级计算 |
| congestion_decision.sv | 新增：拥塞感知路由决策 |

ON_OFF_LATENCY 的改变会改变实际流控：默认深度 8，主项目占用升至 7 即关闭、下降到 1 可重新打开；congestion 升至 8 才关闭、下降到 0 才打开。需结合发送端采样及反馈延迟验证，不能仅视为采集接口扩展。两套设计在规模、包格式和流控阈值上均不同，不宜直接将性能差异全部归因于拥塞算法。

逐字节一致的 11 个文件：crossbar.sv、input_block2crossbar.sv、input_block2switch_allocator.sv、input_block2vc_allocator.sv、node_link.sv、round_robin_arbiter.sv、router2router.sv、router_link.sv、switch_allocator2crossbar.sv、switch_allocator_Xiugai1.sv、vc_allocator.sv。

补充归属：input_port 的 data_cmd 部分赋值、mesh 边界未显式终止、两级 RR 推进方式等在主项目也存在，不能说是 congestion 新引入。本节只比较 RTL；此前原始 TB 问题并非与主项目某个同名 TB 的差异结论。
