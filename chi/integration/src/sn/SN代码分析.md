# SN 代码分析

更新说明（2026-10-15）：下文是导入基线的静态分析。当前 integration SN 已完成 v0.2 错误反馈、ID 保护和异常写回收，正常/异常两套 WSL 自检均通过；已解决项、接口变更与仍存边界见 [SN进展.md](../../SN进展.md)。请勿将下文历史问题描述直接当作当前 RTL 状态。

<!-- Modify by Michael Tan，20261015: distinguish baseline analysis from verified v0.2 implementation. -->

## 1. 范围与结论

本文分析 `chi/integration/src/sn/` 中于 2026-10-15 从 `chi/new/CHI-SN/rtl_new/` 导入的 7 个 Verilog 文件，共 3,429 行。分析采用静态源码阅读、实例关系及字段/握手检索；没有修改 RTL，没有运行编译、仿真或综合。接手时记录的 ModelSim PASS 属于历史局部验证，不代表 integration 副本已在当前环境通过。

该 SN 以 `SN_Top_new` 为顶层，是面向固定 64-byte 数据块的 CHI 风格 FIFO↔AXI 桥：处理 ReadNoSnp、WriteNoSnpPtl/Full，读写均映射为四拍 128-bit AXI INCR burst。DMT 改写读数据返回的 TgtID/TxnID，DWT 改写写请求 DBID 响应的目的节点。模块内部有 valid/ready 暂存、事务上下文和背压保持，结构比 RN 原型更清晰；系统集成仍需处理直传 sideband、事务号编码、FIFO 时序与错误上报等边界。

## 2. 文件与层次

```text
SN_Top_new                         直传属性暂存、模块连线、错误/活动状态
├── RxReq_Ch_new → RxReq_Ch
│   ├── req_if                     REQ 抓取/分类、待写表、读写地址冲突检查
│   ├── req_r                      读上下文和 AXI 请求的独立握手分发
│   └── req_w                      先登记写地址，再发 DBID 响应上下文
├── TxRsp_Ch_new → TxRsp_Ch         CompDBIDResp 单槽输出
├── TxDat_Ch_new → TxDat_Ch         读上下文表、DMT、四拍 CompData 输出
├── RxDat_Ch_new → RxDat_Ch
│   ├── rd_w_if                    写地址表与数据 TxnID 查询
│   └── rd_w_da                    四拍写 DAT 聚合及 byte enable 收集
└── SNF_AXI_Master_new → AXI_Master → snf_axi_master
    ├── snf_axi_read_burst_engine   单笔 AXI 读引擎
    └── snf_axi_write_burst_engine  单笔 AXI 写引擎

mem4KB_new                         独立仿真内存，由测试环境连接
```

| 文件 | 行数 | 主要职责 |
| --- | ---: | --- |
| `SN_Top_new.v` | 379 | 外部 CHI FIFO/AXI 接口，64 项直传属性表，DMT/DWT 合法性检查和返回路由选择。 |
| `RxReq_Ch_new.v` | 525 | REQ 解包、读写分类、写地址冲突表，以及读/写上下文分发；同时包含旧核心与 `_new` 包装模块。 |
| `RxDat_Ch_new.v` | 486 | 维护写地址上下文，按接收顺序聚合四个 DAT flit，输出 512-bit 数据、64-bit BE、地址和 12-bit ID。 |
| `TxDat_Ch_new.v` | 407 | 保存读上下文，匹配完整 AXI 返回 ID，生成四拍 CompData 并统计完整数据包。 |
| `TxRsp_Ch_new.v` | 188 | 单槽保存响应上下文，在 FIFO 非满时发送 CompDBIDResp；可同拍发旧响应和接收新上下文。 |
| `SNF_AXI_Master_new.v` | 1,225 | 参数化 AXI 读写引擎及两层接口包装；固定顶层配置为 40-bit 地址、12-bit ID、128-bit AXI 数据和 512-bit 数据块。 |
| `mem4KB_SourceCode_new.v` | 219 | `mem4KB_new`：64×512-bit 内存模型，支持 WSTRB，每方向一笔事务，BID 仅输出低 7 位。 |

`mem4KB_new` 没有实例化在 SN 顶层中，属于仿真支撑模型；真实系统需要外接 AXI 存储控制器。7 个文件包含多个模块，不能把文件数当作模块数，也不能只按 `_new` 名字收集编译单元。

## 3. 接口与字段合同

SN 的 CHI 侧输入只有 REQ、DAT；输出只有 RSP、DAT。没有 SNP 或入站 RSP 接口，没有 CHI link credit/链路激活逻辑。REQ/DAT 入站使用 `flit + empty + read`，出站使用 `full + write + flit`；内部各模块使用 valid/ready。`req_if` 先登记 `fetch_pending_q`，随后在读请求有效的时钟沿采样 FIFO 数据；`rd_w_da` 也分开发出读请求和采样，适配层必须提供匹配的 FIFO 头数据时序。

| 通道 | 位宽 | 本实现使用的关键字段 |
| --- | ---: | --- |
| REQ | 128 | TgtID `[10:4]`、SrcID `[17:11]`、TxnID `[29:18]`、Opcode `[56:50]`、Addr `[99:60]`。 |
| RSP 输出 | 65 | TgtID `[10:4]`、SrcID `[17:11]`、TxnID `[29:18]`、Opcode `[34:30]`、DBID `[57:46]`；CompDBIDResp 默认 opcode 为 `5'h05`。 |
| DAT | 223 | TgtID `[10:4]`、SrcID `[17:11]`、TxnID `[29:18]`、HomeNID `[36:30]`、Opcode `[40:37]`、DBID `[65:54]`、DataID `[69:68]`、BE `[94:79]`、Data `[222:95]`。 |
| 直传 sideband | 独立端口 | `req_dmt_enable_i`、`req_dwt_enable_i`、`req_return_nid_i[6:0]`、`req_return_txnid_i[11:0]`，须与被读取的 REQ 同拍对应。 |

这些是源码中的字段布局，不构成对完整 CHI 协议版本的符合性认证。REQ 的 Size、其他内存属性没有驱动可变 burst 长度；AXI 顶层始终使用 `LEN=3`、`SIZE=4`、`BURST=INCR`。

## 4. 读事务路径

1. `req_if` 消费 opcode `7'h04` 的 ReadNoSnp；从 REQ 提取地址、原始 TxnID 和节点号，构造 92-bit 内部请求。若存在相同 64-byte 行地址的 pending write，读请求保持等待，直到对应 AXI B 完成释放待写项。
2. `req_r` 保存一笔请求，并独立向 `TxDat_Ch` 发送 45-bit 读上下文、向 AXI 引擎发送 `{Addr,TxnID}`。两个消费者均完成握手后才释放该分发槽，避免某一路背压导致另一条支路重复接收。
3. AXI 读引擎执行 IDLE→SEND_ADDRESS→RECEIVE_DATA→SEND_RESPONSE。AR 保持到握手；R 通道按四拍聚合为 512 bit，检查 RID、RLAST 并合并 RRESP，最终经内部 valid/ready 交给 `TxDat_Ch`。
4. `TxDat_Ch` 使用 AXI ID 低 7 位映射上下文表索引，再检查完整 12-bit TxnID；上下文未到时等待。数据按低位到高位分成四拍，DataID 为 0、1、2、3，BE 固定为 `16'hFFFF`。下游 FIFO 满时不写入、不推进 beat。
5. 第四拍写入成功后释放上下文并递增 10-bit 包计数。计数按完整 512-bit 数据包递增，会在 1,024 包后回绕。

普通返回时，响应 SrcID 为请求 TgtID，响应 TgtID 为请求 SrcID；HomeNID 来自请求 SrcID，DBID 使用原始请求 TxnID。本实现的普通工作模型据此假设请求由 HN 转发。

## 5. 写事务路径

1. `req_if` 识别 `7'h1c/1d` 的 WriteNoSnpPtl/Full，检查 TxnID 分组和对应待写项是否可用；分发时保存地址并置 pending。设计直接以请求 TxnID 作为 DBID，没有独立的空闲 DBID 分配器。
2. `req_w` 依次经过 IDLE→SEND_RXDAT→SEND_TXRSP：先将 `{Addr,TxnID}` 登记到 `rd_w_if`，再将响应上下文交给 `TxRsp_Ch`。因此正常流程先具备接收写数据所需的地址，再允许响应发出。
3. `TxRsp_Ch` 生成一拍 CompDBIDResp，交换源/目的 NID；有独立 pending 槽，FIFO 满时保留 payload。该响应在 AXI 写入和 B 响应之前发送。
4. `rd_w_da` 按接收顺序将四个 flit 的数据和 BE 拼成 512/64 bit；第一拍锁存完整 TxnID，后续拍比较 TxnID。收满后用低 7-bit TxnID 查询地址，地址匹配/数据 ID 出错时放弃送往 AXI，否则保持写请求直到 AXI 引擎接收。
5. AXI 写引擎独立保持 AW 与 W，允许两者分别握手。四拍 WSTRB 来自各拍 BE，WLAST 在第四拍；AW 与全部 W 完成后等待 B，再形成内部完成通知以释放 `req_if` 待写地址项。

Ptl 与 Full 在请求分类后共用同一条四拍数据路径，部分写依靠 BE/WSTRB 实现；不能据此认为已经支持任意拍数、任意 Size 的 CHI 部分写。

## 6. DMT、DWT 与上下文容量

- 顶层在 `chi_rx_req_read_o` 时采样直传 sideband。DMT 只允许 ReadNoSnp，DWT 只允许上述两类 WriteNoSnp；两种 enable 同时有效、DMT 配写、DWT 配读会产生单周期 `direct_transfer_error_o`，并回退普通返回路由。非法 opcode 由 RxReq 报错并丢弃，不分发到 AXI。
- DMT 的 AXI ARID 仍是原始请求 TxnID；TxDat 保存 ReturnNID/ReturnTxnID，在发 CompData 时替换 TgtID/TxnID，保留原 HomeNID、DBID 和 SN SrcID。
- DWT 修改响应上下文中的请求 SrcID 槽，经过 TxRsp 源/目的交换后，使 CompDBIDResp 发往 ReturnNID；其响应 TxnID、DBID 和后续 AXI AW/B 关联继续使用原始请求 ID。ReturnTxnID 在该写响应路径中没有替换作用，需要与 RN/HN 的预期合同核对。
- `dmt_active_o`、`dwt_active_o` 表示当前上下文查表选中的属性，并非整个 SN 的事务忙标志或完成计数。
- 多处表均声明 64 项，但有效的 TxnID `[6:4]` 分组仅为 `000`、`010`、`110`，映射到三个 16 项区域，实际可接受的受支持索引为 48 项。TxnID `[11:7]` 不参与索引；TxDat 最后会比较完整 ID，不能据此允许相同低 7 位、高 5 位不同的事务同时占槽。
- 读写 AXI 引擎各自只有一笔活动事务，可以读写并行；上下文表项数不等于 AXI outstanding 数。顶层直传属性表在上下文移交下游时释放，TxDat 再自行保存 DMT 属性至发送结束。

## 7. 静态集成风险与待确认项

以下为源码观察及由此推导的风险，尚未通过当前环境定向仿真复现。

1. **直传属性缺少网络承载合同。** DMT/DWT 和 ReturnNID/ReturnTxnID 来自独立输入，没有从 128-bit REQ 中解析。HN/NoC 适配层必须说明这些属性如何随 REQ 排队、传输和同步，否则单纯连接 flit 会丢失直传语义。
2. **事务表键受历史拓扑约束。** 写地址表/直传表依赖 TxnID 低 7 位编码 requester group；实际 REQ SrcID 没有参与索引。HN 必须生成符合分组的 ID，并保证低位唯一。读分发没有与写分发相同的分组拒绝检查；不支持的读 ID 可进入 AXI，但 TxDat 只做仿真打印/丢弃，缺少统一错误完成。
3. **直传属性在入口分配、下游才检查冲突。** 顶层收到新 REQ 即写同索引属性，而忙槽/读上下文容量控制分布在后续模块。重复索引请求可能覆盖尚未移交的属性；需验证重复低位 ID、读写同索引和属性回收/重分配同拍场景。
4. **AXI 错误没有映射回 CHI。** AXI 引擎检查 RRESP/BRESP、RID/BID 和 RLAST，但兼容包装将响应码和 protocol-error 仅归约到 `unused_new_status`。TxDat 输出 RespErr 为零，顶层也没有独立 AXI 错误端口；不能把错误检测等同于上游可见的错误完成。
5. **写数据接收约定较窄。** `rd_w_da` 根据接收次数放置四拍，不按 DataID 重排，也没有校验 DAT opcode、目标节点或 BE 与请求类型的一致性。只能在上游保证同一事务连续四拍时使用；事务交错、缺拍、乱序和非法 opcode 必须增加验证/恢复方案。
6. **错误事务的资源回收待补全。** 数据 TxnID 不一致或地址查询失败时，聚合器可放弃 AXI 写；`req_if` 的待写项却依赖 AXI B 完成释放。若错误路径未产生 B，相同行读请求可能持续阻塞。需定义清理、错误回报与超时机制。
7. **BID 为 7-bit 兼容接口。** 顶层对外仅接收 BID `[6:0]`，包装用当前单笔写上下文恢复高 5 位。这依赖单笔 outstanding 假设，也无法检测外部 BID 高位错误；接真实 12-bit AXI slave 或扩展 outstanding 时必须重审该接口。
8. **固定整行访问与属性范围。** AXI burst 固定为四拍 128 bit，未随 CHI Size/属性调整。必须约定 64-byte 对齐、地址范围、内存类型与排序语义；待写冲突比较的是 `[39:6]`，没有提供完整的跨地址内存顺序模型。
9. **仿真内存不能代表真实地址空间。** `mem4KB_new` 只以地址 `[11:6]` 索引 64 行，高地址位被忽略，会发生 4 KiB 镜像；其全数组复位和行为逻辑也不构成目标 FPGA 存储实现证据。实际内存控制器应单独集成和验证。
10. **模块名与接口统一。** `_new` 文件内仍含 `req_if`、`req_r`、`AXI_Master` 等通用旧模块名；后续编译清单应限定 integration 文件，避免与 old/new 基线重复。HN 的 valid/ready 输出需转换到 SN FIFO 输入，并逐位对齐 NID/TxnID/DBID 和 DAT beat/BE。

SN 不含 stash REQ/SNP 分支；stash 的系统级能力主要由 RN/HN 协议流程决定，不能从 SN 的 DMT/DWT 路由功能推断完整 CHI 已支持 stash 或缓存间直传。

## 8. 验证证据与建议顺序

已有 `chi/README.md` 记录接手的 2026-08-23 ModelSim 单元/顶层 PASS：覆盖普通读写、高 TxnID、DMT、DWT 部分写、背压、非法直传组合和非法 opcode。这些是历史证据，本次未重新执行；integration 还没有 SN 自检入口或新结果目录。

建议按以下顺序继续：

1. 固化 RN/HN/SN 字段表、FIFO 时序、ID 分配和直传 sideband 承载方式，明确只接受整行四拍的范围。
2. 在 `integration/testbench/` 和 `scripts/simulation/` 建立 SN 独立自检，先复现历史普通读写、DMT/DWT 和背压场景，结果写入独立平台目录。
3. 加入同低位不同高位 ID、重复槽、读写同索引、非法分组、交错/缺失 DataID、AXI 错误及错误后资源释放用例。
4. 建立 HN↔SN 最小内存事务回归，再接 RN，检查路由、BE、数据、完成次序和事务回收；最后进入 `chi/noc/` 适配。

## 9. 本次分析记录

后续进展（2026-10-15）：已通过独立 `tb_sn_integration_baseline` 的 WSL Vivado 2025.2 自检，覆盖普通读写、DMT/DWT、背压及非法组合；修复发生在迁入 TB 的 WREADY 驱动时序，SN RTL 未修改。结果和命令见 [integration README](../../README.md)。本文件上文“未运行”描述的是静态分析当时状态；异常恢复等风险仍待定向验证。

<!-- Modify by Michael Tan，20261015: link fresh baseline verification without overstating static-analysis coverage. -->

- 日期：2026-10-15。
- 阅读范围：`SN_Top_new.v`、`RxReq_Ch_new.v`、`RxDat_Ch_new.v`、`TxRsp_Ch_new.v`、`TxDat_Ch_new.v`、`SNF_AXI_Master_new.v`、`mem4KB_SourceCode_new.v`，共 3,429 行。
- 静态检查：模块层次、REQ/RSP/DAT 字段、DMT/DWT 属性生命周期、表项索引、AXI 单笔状态机、byte enable、错误输出与回收路径。
- 未修改 `.v` RTL，未运行编译、仿真或综合；原始 `chi/new/` 基线保持原样。

<!-- Modify add static SN code analysis and integration risks, Michael Tan, 20261015 -->
