# 同事原始 TB、主项目扫描 TB 与当前对照 TB 的测试方法比较

<!-- Modify by Michael Tan，20261029: compare actual injector, drain, scoreboard and timing contracts without modifying source. -->

本次仅静态分析，不修改RTL/TB，不运行仿真。对照实际代码，不能以文件名或注释代替行为。

## 比较对象

- 同事交付：congestion/testbench/tb_mesh_injection_1.1.sv，顶层tb_mesh。
- 主项目代表：testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv。另核查rate_001_to_017变体的注入VC和排空机制，结论相同；不泛化到仓库所有TB。
- 这两天的新实测：congestion/testbench/tb_congestion_latency_compare.sv及其OE/隔离实验派生TB。既有OE1774.974、XY81.072来自该自检体系，不是同事原TB。

## 1. 源端注入机制有差别，也有共同限制

同事TB322～328行生成每源递增ID并用pid%VC_NUM固定目标VC；387～407行只看每源flit FIFO队首及其on_off，允许每周期一个flit。虽然包轮流使用四个VC，但队首不前进时后面的任何包都不能绕过。无可用VC搜索，不是四个独立可调度发送队列。

主项目297～339行使用每源一个包队列及GEN_IDLE/GEN_SEND_PAYLOAD状态机；315、324行只检查VC0的on_off，442行flit.vc_id=0。故“4VC”表示DUT有四个VC，不表示源端轮流注入四个本地输入VC。包头开始后必须依次发完BODY/TAIL，同样存在源队首阻塞。rate_001_to_017变体312、321、439行仍采用此策略。

当前新对照TB采用固定pid%4和单个send_pid/send_beat游标，在这一关键注入限制上接近同事TB，而非主项目固定VC0策略；新生成函数和原始PRNG不同。当前对照按算法共享生成轨迹，不能称逐周期复现同事原始刺激。

含义：原项目本身也没有实现后包绕过，不能将OE的大延迟简单归为同事独有的队首FIFO。固定VC0与轮转4VC会改变LOCAL缓冲并行度、存量与回压，性能数字不能直接横比；轮转并不自动消除单源HOL。需要在同一congestion RTL、同一生成轨迹下做固定VC0/轮转4VC独立对照，才能量化影响。

## 2. 统计口径总体相似，但同事TB存在实现性缺陷

双方延迟都从软件源生成时刻开始，包含源排队。主项目create_packet在360行附近记录pkt_inject_cycle，虽变量名含inject，实际早于start_packet；不能说原项目只统计网络内延迟。

同事TB无预热，监测TAIL后按源坐标/ID找时间戳。monitor_outputs为模块级非automatic task，424～428行xs/ys/pid/latency使用声明赋初值，具有静态初始化语义，不能保证每次收包重新取值，属于统计代码缺陷。主项目先声明局部变量，再在分支中赋当前值，避免了该问题。

主项目预热200、测量1000，生成于测量期的包计入均值；生成时间戳并不因排空而重置。当前对照预热300、测量1200，同样按出生窗口选样，并分解源排队与网络内延迟、输出P95/P99，缺样直接失败。

同事compute_results把理论物理最大包数减已到达包数命名invalid，不能理解为实际丢包。主项目分开输出generated/enqueued/queue_full/injected/received，更利于解释负载与丢弃。

## 3. 排空是最大的可靠性差距之一

同事run_single_rate276～311行到生成窗口结束立即停止所有注入，只接收500周期。此时源FIFO可能还留BODY/TAIL，网内HEAD因此根本不可能完成。只对已经收到的TAIL求平均，排除慢包，可能低估延迟，不能把未收到包视为已验证无丢包。clear_test_stats216～235行清队列/ID/统计但不复位DUT，多速率可能污染下一轮。

主项目reset_for_rate逐档复位DUT；drain_queued_traffic在停生成后仍调用drive_generators(0)，继续发送源队列，直到源无待发、测量injected==received或达到8000周期上限。这比同事的固定空等更合理。

但主项目也不是无条件完整排空：到达上限后直接停止，末尾仅检查error_seen及received==injected，没有显式强制enqueued==injected、源队列为空、所有路由器占用为零。若所有已注入测量包都完成而仍有未注入源包，其均值依然可能只反映子集；结果列可显示该问题，不能只看平均值或errors=0。has_pending_traffic也不追踪所有预热包是否完成。

当前新对照显式要求offered==completed、tx/rx flit守恒、每源游标追平、每包4 flit完成、出口无包所有者，并额外观察20周期全网存量为零；超时fatal。故当前OE高延迟不来自同事原始“等500周期”截尾方式。

## 4. 功能自检的覆盖差距明显

同事主要匹配尾包时间戳，缺少逐flit负载、实际目的出口、HEAD/BODY/TAIL序号、重复/未知包和资源所有权检查，也未将error_o纳入验收。输出平均延迟不等于功能PASS。

主项目monitor_outputs468～586行检查目的、未知ID、HEAD/TAIL重复、BODY/TAIL序号与顺序，监测error_o，并核对测量injected/received，属于更完整的自检。其编码字段检查不应夸大为完整flit逐位比对。

当前新对照在上述思路上增加完整flit期望值比较、按出口VC核对包所有权、全部样本完整性、X态和最终清空检查；不是直接沿用同事的尾计数统计。

## 5. 驱动/采样时序也不同，主项目仍有待规范之处

同事在posedge执行monitor_outputs，再以非阻塞赋值驱动下一拍输入。主项目在posedge用阻塞赋值drive_generators，另一个posedge进程延迟#1监测输出；其输入驱动和DUT顺序块同边沿，存在仿真调度竞争风险。仅静态标记风险，本轮没有新仿真，不能据此认定历史某个结果错误。

当前新对照在negedge驱动，在posedge采样本次传输、随后#1观察更新，避免把同边沿输入驱动竞争带入新算法对照。新旧TB绝对cycle口径也需统一后才横向比数值。

## 6. 平台参数不是同一组

主项目代表5×5、原始较窄flit，congestion13×13、暂用258-bit flit；包格式、工作负载种子/PRNG、窗口长度及注入VC策略也不同。即使同为4-flit和packet/node/cycle，同注入率也不代表相同网络压力。不能拿两个项目的历史拐点或平均延迟直接评价算法优劣。

## 结论与后续比较方式

同事原TB与主项目TB有明显差距，主要是统计变量、排空、轮次隔离和自检；主项目在源注入并行度、严格清空和驱动时序上也有局限。当前OE/XY异常是在新的相同条件自检TB中复现，不能由原始TB统计缺陷直接解释，也不应把源HOL说成同事TB独有的问题。

若验证注入方式对OE差距的影响，应在现有congestion13×13和同一生成轨迹上，仅切换源固定VC0/轮转4VC；沿用当前完整计分板/出生窗口/排空规则，分别测试XY与OE。之后另立实验评估可绕过源调度，不能同时改生成器、时序、尺寸、算法和统计口径。以上是实验建议，本轮未创建或运行新TB。
