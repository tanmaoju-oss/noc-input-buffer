# Mesh 到二维 Torus 的改造分析

<!-- Modify by Michael Tan，20261021: document source-based Torus implementation plan without RTL changes. -->

## 2026-11-02 实施状态

首版已在 `torus/src/` 实现，验证结果以 [验证报告](torus_verification_20261102.md) 和 [修改记录](修改记录.md) 为准。以下 2026-10-21 分析保留作为方案来源，其中“尚未实施/未仿真”描述为历史状态。

<!-- Modify by Michael Tan，20261102: distinguish implemented routing contract from historical analysis. -->

### 已落实的接口与状态规则

- `torus.sv` 默认 5×5，可设置独立 X/Y 尺寸，各维支持 2..8；小于 2、超过 flit 坐标范围或 VC 数不等于 4 时拒绝运行。偶数等距固定 EAST/SOUTH；采用先 X 后 Y，禁止 Y→X。
- `router/input_block/input_port/rc_unit` 传递 `TORUS_MODE`、`NETWORK_SIZE_X/Y`，输入端口编号由 generate 显式传入。`TORUS_MODE` 默认 0，原 `mesh.sv` 仍使用普通 XY；两模式共享模块已变化，因此不能将该 Mesh 当作未经修改的性能对照。
- VC0/1 为 X 跨界前/后，VC2/3 为 Y 跨界前/后；跨界跳本身使用后类。同一维度沿用输入后类，X→Y 清除 X 阶段再判断 Y 跨界。

| 输入情况 | 输出情况 | 合法下游 VC |
| --- | --- | --- |
| LOCAL 任意注入 VC | X 方向 | 非跨界 VC0；跨界 VC1 |
| LOCAL 任意注入 VC | Y 方向 | 非跨界 VC2；跨界 VC3 |
| X 输入 VC0/1 | 继续 X | 输入已为 VC1 或本跳跨界时 VC1，否则 VC0 |
| X 输入 VC0/1 | 转 Y | 本跳跨界时 VC3，否则 VC2 |
| Y 输入 VC2/3 | 继续 Y | 输入已为 VC3 或本跳跨界时 VC3，否则 VC2 |
| 任意合法输入 | LOCAL 弹出 | 本地四个接收 VC 均可，作为终端资源 |
| Y 输入要求转 X，或转发时输入 VC 维度不匹配 | 网络方向 | 拒绝该包头，给出错误指示 |

- 非法目的坐标的 HEAD/HEADTAIL 被输入端口拒绝写入，`error_o` 在 valid 期间指示错误；不承诺自动清除随后到来的 BODY/TAIL 或重同步，非法上游包需由系统恢复/复位。BODY/TAIL 不重新计算路由资格。
- 合法掩码随包头写入 `packet_meta_t`，只输出 metadata 队首资格；VA 请求和实际选择均使用该掩码。分配后 BODY/TAIL 复用同一输出端口和下游 VC。
- `is_on_off` 是 flit 接收容量；`is_allocatable` 是包的下游 VC 释放通知。VA 复位时初始可用，之后只能在 TAIL/HEADTAIL 离开下游缓冲时重新释放。测试接收端模拟后者为单周期脉冲，不可恒置 1。

### 依赖模型假设与边界

`check_torus_channel_dependencies.py` 用目标输入节点、输入端口和 VC 建立实际共享 FIFO 资源，合并所有合法路径的资源依赖；每个输入 VC 的 flit/metadata 独立存储，同 FIFO 多包的队首阻塞计入该资源的依赖并集。注入端为只被本地源写入的起点，弹出端为独立终点；抽象源 VC0 代表任意本地注入 VC，因为这些起点没有网络入边。检查 2..8 的全部 49 种尺寸和全部 41,209 条路径无环，并检查跳数最短。

该模型依赖：逐包独占 VC 直至 TAIL、包内不交织、维度/类别合法、终端最终服务、源最终提供完整包；不包含端点协议导致的反向等待、SA 饥饿的形式化公平性、任意 RTL 故障。模型检查与有限仿真不能直接等同于完整 RTL 的形式化无死锁证明。

## 分析范围与基线

2026-10-21 将主项目 `src/` 的 25 个文件完整复制到 `torus/src/`（包含 5 个 board_ila 文件），逐文件字节一致。来源 HEAD 为 `bf1ae956bb9ebb2075a04d3d47a377ea0bb130a1`，复制时根目录 `src/` 无 Git 未提交改动。校验清单见 [mesh_baseline_sha256.txt](mesh_baseline_sha256.txt)。本次无 RTL 编辑、编译、仿真或综合，副本仍是 Mesh。

## 现有实现

- `mesh.sv` 生成 `mesh_row[y].mesh_col[x]` 路由器，外部数组按 `[x][y]` 排列。垂直连接仅覆盖 `y=0..NY-2`，水平连接仅覆盖 `x=0..NX-2`，没有首尾环绕连接；边界端口也没有在该模块中统一终接。
- `rc_unit_Xiugai2.sv` 的模块名为 `rc_unit`，采用确定性 X 后 Y 路由：X 小走 WEST、X 大走 EAST，然后 Y 小走 NORTH、Y 大走 SOUTH。现有 signed offset 信号未参与选择，不可直接拿来算模距离；非 HEAD/HEADTAIL 分支没有完整组合赋值，改造时应给默认值并确保仅在有效包头接收时存储路由结果。
- `router.sv → input_block_Xiugai2.sv → input_port_Xiugai2.sv → rc_unit` 逐级传递当前坐标，尚未逐级传递实际网络尺寸。
- `noc.sv` 包定义尺寸为 5×5、4VC、五端口；`mesh` 模块默认尺寸却为 2×3。当前普通 XY 方向选择无需知道环长，Torus 模距离必须使用实例实际尺寸，不能混用包常量和顶层参数。包中的坐标位宽还须覆盖实际尺寸。
- `input_buffer_src_circular_full.sv` 每个 VC 有 flit FIFO 和逐包 metadata FIFO，metadata 当前只含输出端口、下游 VC、已分配位。一个 VC 可排队多个包，任何新增路由类别必须逐包保存。
- `vc_allocator.sv` 在目标输出端口的全部空闲 VC 中选最低编号，没有合法 VC 类别掩码；`input_block2vc_allocator.sv` 也没有对应字段。
- `input_port` 按输入 `vc_id` 写缓冲；输出缓冲在包级保存下游 VC，并将其写入转发 flit。现有链路会传递 VC ID，因此可以利用 VC 编码承载通道类别，无需先增加 flit 字段。

## 建议的首版方案

采用双向二维 Torus、确定性最短路径 X 后 Y 路由，以及明确受约束的 dateline VC 分配。先以 5×5/4VC 验证，保留本地接口和 flit 格式，暂不加入自适应路由。

### 连接与端口

保留 LOCAL/NORTH/SOUTH/WEST/EAST 五端口。新增每行最右端 EAST 到最左端 WEST，以及每列最下端 SOUTH 到最上端 NORTH 的双向连接，数据、valid、on_off、allocatable 成套连接。优先保留现有内部连接循环，再增加独立边界 generate，避免重复驱动。

注意 `router_link` 的参数名不能直接当作数据流向：现有 `router_if_up` 接收 down 接口数据、并反向送流控，新增连接应照现有端口组合核对。

5×5 Mesh 有 40 条相邻节点双向链路，Torus 为 50 条，新增 10 条双向链路。二维 Torus 两节点之间的最短跳数为 `min(|dx|, NX-|dx|)+min(|dy|, NY-|dy|)`。

尺寸为 2 时正负方向通向同一邻居，但应保留为两条独立端口链路，不能合并驱动。首版建议要求 NX、NY 至少为 2；尺寸为 1 的自环行为暂不支持，并在后续实现中显式检查。

### 路由计算

```text
X 未到达：
    east = (dst_x + NX - cur_x) % NX
    west = (cur_x + NX - dst_x) % NX
    选较小者；等距固定选 EAST
X 已到达而 Y 未到达：
    south = (dst_y + NY - cur_y) % NY
    north = (cur_y + NY - dst_y) % NY
    选较小者；等距固定选 SOUTH
X、Y 均到达：LOCAL
```

实际 RTL 可用比较、加减替代 `%`，并显式扩展运算位宽。每跳等距规则保持一致。例：5×5 中 `(0,0) → (4,0)` 应向 WEST 环绕一步，而 `(0,0) → (4,4)` 为 WEST 后 NORTH，共两跳。非法目的坐标须由 TB 检查，并在实现方案中定义拒绝或诊断行为。

### 环内死锁与 4VC 的使用

环绕会引入同一维度的通道依赖环；确定性 XY 只限制维度切换，不能单独消除这些环。VC 数量为 4 也不等于已经实现死锁规避，分配器必须限制可用类别。理论依据是通过 VC 拆分使通道依赖图无环，见 [Dally 与 Seitz 原论文](https://authors.library.caltech.edu/records/fd0yr-br438/)。以下是本项目的拟实施方案，尚未完成证明或验证。

建议将四个 VC 分别定义为 X 环绕前、X 环绕后、Y 环绕前、Y 环绕后（编号可为 0/1/2/3）。在每个有向环的坐标首尾边设置 dateline：跨界跳本身使用“环绕后”类别；同一维度继续前进时不得从后类退回前类。进入 Y 维度时按 Y 维度重新判定，禁止 Y 转回 X。本地注入独立初始化类别，本地弹出单独处理，不应直接继承源端任意 VC 的类别。

路由状态可由当前坐标、输入端口、输入 VC 类别和目标输出方向推导：输入端口需由 input_block 的 generate 索引明确传入；在同维度保留入 VC 的阶段，在 X→Y 时初始化 Y 阶段，并根据当前输出是否跨界确定下一跳类别。计算出的下一跳类别/合法 VC 掩码须随被接收包头存入 metadata FIFO，不能在 VA 时使用当前线上的另一个包头。

首版每类仅一个 VC，暂时牺牲通用 4VC 的自由选择换取清晰的资源顺序。该划分是方案选择，不是宣称 Torus 必须恰好四个 VC。必须在实现前枚举带 VC 的资源依赖图，确认同维无后→前依赖、维度只有 X→Y，并覆盖注入、弹出与多包共用缓冲语义；不能仅凭随机流量通过就声称无死锁。

## 模块改动清单（均限 torus/src/）

| 文件/模块 | 计划改动 |
| --- | --- |
| `mesh.sv` / 新 `torus.sv` | 建议新增 `torus` 顶层，复用 Mesh 内部连接并补首尾链路；传入实际 NX/NY，保留本地端口合同。原 Mesh 副本可作为对照，编译分别选择顶层。 |
| `noc.sv` / `noc_params` | 定义拓扑/VC 类别常量与类型，约束尺寸和地址宽度；首版保留现有 flit 格式。 |
| `rc_unit_Xiugai2.sv` | 改为环形最短距离路由、固定等距规则；计算跨界及下一跳通道类别，补完整组合赋值。 |
| `router.sv` | 向输入模块传实际网络尺寸，连接新增 VA 资格信息。 |
| `input_block_Xiugai2.sv` | 传尺寸和每个输入端口编号；汇总逐 VC 的资格信息。 |
| `input_port_Xiugai2.sv` | 输入端口/VC 类别参与路由资格推导，包头资格与 out_port 一起送入对应缓冲。 |
| `input_buffer_src_circular_full.sv` | metadata 增加逐包合法类别/掩码；输出队首包资格，维持 BODY/TAIL 的输出端口和下游 VC 锁定。 |
| `input_block2vc_allocator.sv` | 增加逐输入端口、逐 VC 的合法下游 VC 掩码及 modport 定义。 |
| `vc_allocator.sv` | request 与选择函数均使用 `available & allowed_mask`；禁止无合法 VC 时发 grant，并保持原释放时序。 |
| `board_ila/noc_board_ila_top.sv` | 后续需要板级验证时改为 Torus 顶层；首轮纯功能验证不必改。 |

预计复用 `router_link.sv`、`router2router.sv`、`node_link.sv`、`crossbar.sv`、`circular_buffer_Xiugai3.sv`、`round_robin_arbiter.sv` 及 SA 相关接口。`separable_input_first_allocator.sv` 与 `switch_allocator_Xiugai1.sv` 预计不需拓扑逻辑变化，但必须回归验证：VA 资格过滤后仍正确仲裁，SA 继续按已分配下游 VC 的 on/off 控流。若为新资格接口改变签名，再同步调整相关实例。板级流量发生器、监控和 ILA 探针优先保持不变。

## 实施与验证顺序

1. 独立编译当前复制的 Mesh 基线，建立子项目可复现入口；只编译 `torus/src/`，不得和根 `src/` 混编同名模块/包。
2. 新建路由单元 TB：穷举所有源/目的坐标，覆盖 5×5 与偶数尺寸的等距规则、实际尺寸与包尺寸差异。
3. 完成 dateline/VC 状态表和资源依赖图检查，再同步实现顶层、路由、metadata 与 VA；拓扑连接正确不等于功能已完成。
4. 新建 Torus 集成 TB：四个方向环绕、双维环绕、同节点、全源目的组合、HEADTAIL/多 flit、持续背压、VC 竞争、多包 metadata、TAIL 释放和复位。
5. 新建持续拥塞/环形对抗流量验证；停注入后必须完全排空，计分检查无丢失/重复/错目的/包内乱序、error_o=0，且 VC 选择满足资格断言。超时只作为失败检测，不能代替死锁证明。
6. 通过后再做同尺寸、同缓冲、同注入流量/种子的 Mesh–Torus 延迟与吞吐比较，明确 VC 划分类别的资源差异；不预先承诺性能收益。5×5 最大最短跳数由 Mesh 的 8 降为 Torus 的 4，但实际拥塞和时序仍须测量。

以上 TB、runner、结果均新建于子项目对应目录，不复用主项目结果目录；本次尚未执行任何步骤的编译或仿真。

## 文件级待办入口

后续执行顺序、拟新增/修改文件、TB 与 runner 配对及结果路径统一维护在 [子项目 README 的任务清单](../README.md#后续工作与文件清单2026-10-21)，完成后逐项更新状态。保留 `mesh.sv` 仅保留连接形式；共享 router/RC/VA 修改后，原始 Mesh 对照必须使用独立基线构建。

<!-- Modify by Michael Tan，20261021: link executable file checklist and clarify shared-module baseline boundary. -->
