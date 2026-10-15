# SN 完善与验证进展

## v0.2 — 2026-10-15：异常处理、ID 保护与资源回收

本版本只修改 `chi/integration/` 的 SN 副本与自检。原交付 `chi/new/`、HN/RN RTL 和主项目 `src/` 不变；当前验收层级为 SN 单模块 WSL 功能验证。

### 已实现功能

| 修改文件 | 功能与原因 |
| --- | --- |
| `src/sn/SNF_AXI_Master_new.v` | 将读响应码、写错误和完整写完成 ID 穿过兼容包装导出，避免原有 AXI 错误被丢弃。写错误 ID 来自写完成上下文，不依赖已可能开始接收下一事务的 RxDat 输出。 |
| `src/sn/TxDat_Ch_new.v` | 与 AXI 读数据一起保存状态，SLVERR/DECERR、RID/RLAST 检测失败在四拍 CompData 的 RespErr `[42:41]` 中均返回 NDERR=`2'b10`；状态经过 FIFO 背压保持。 |
| `src/sn/SN_Top_new.v` | 低 7-bit ID 在实际读末拍、写 B 完成或 abort 前保持占用；相同 ID 和高位不同但低位相同的请求在 REQ FIFO 处等待，避免覆盖直传属性。非法 TxnID 分组消费后产生请求错误，不送 AXI。 |
| `src/sn/RxDat_Ch_new.v` | `_new` 入口采用新的有界四拍接收器：检查完整 TxnID、NCBWrData opcode 和 DataID 0/1/2/3；非法数据不送 AXI。保存完整 ID/地址，避免低位别名数据错误写内存。旧 `RxDat_Ch/rd_w_if/rd_w_da` 保留为历史实现，当前 SN 顶层不实例化它们。 |
| `src/sn/RxReq_Ch_new.v` | 接收独立 abort 事件并清除 pending write 地址保护；不再只能等待 AXI B。abort 与 B 可分别释放不同槽。 |
| `testbench/tb_sn_integration_baseline.sv` | 正常写数据模型补入合法 opcode=3 和 DataID；原模型这两字段全零。检查普通流量不产生 AXI 错误/abort，保留原普通读写/DMT/DWT/背压/非法组合自检。 |
| `testbench/tb_sn_integration_errors.sv` | 新增独立定向回归，覆盖错误注入、缺拍/孤立数据、ID 冲突、同地址读写保护和异常后无复位复用。 |
| `scripts/simulation/run_tb_sn_integration_errors.sh` | 新增独立编译/仿真入口、结果目录和 PASS/错误判据，保留每次运行结果；原基线 runner 继续独立存在。 |

所有新增/修改功能区均包含 `Modify by Michael Tan，20261015` 注释。`TxRsp_Ch_new.v` 和 `mem4KB_SourceCode_new.v` 本次未改动。

### 新增顶层接口与恢复合同

- `axi_read_error_o/axi_read_error_txnid_o`：读响应交给 TxDat 时的错误事件及原始 12-bit ID；CompData 本身也携带 RespErr。
- `axi_write_error_o/axi_write_error_txnid_o`：AXI 写完成后的错误事件及完整 ID。因为 CompDBIDResp 已先发出，不能事后修改那一拍响应；该事件必须由后续系统集成层接收处理。本版本没有另造一条未经定义的 CHI 写错误响应。
- `axi_error_o/axi_error_txnid_o/axi_error_write_o`：汇总诊断；同拍读写错误时写优先，完整记录两项错误应使用两组独立输出，定向 TB 已检查同拍双错误和各自 ID。
- `write_abort_valid_o/write_abort_txnid_o`：非法或超时写事务的释放通知。`chi_rx_dat_error_o` 由原 sticky 行为改为错误事件，便于恢复后继续监控；无匹配上下文的孤立数据只报接收错误，不取消其他同低位事务。
- 参数 `DATA_TIMEOUT_CYCLES` 默认 256；异常 TB 取 80。上下文计时在 CompDBIDResp 被写入出站 FIFO 后启动，不在地址登记时启动，避免响应 FIFO 背压期间误超时。必须根据真实网络最大延迟配置，FIFO 入队不等于 RN 实际收包。
- 只接受同一事务连续、按 DataID 顺序的四拍数据；交错/重复/乱序视为非法，不执行数据重排。缺少部分拍、完全没有数据、孤立不完整包均有有界回收。已组成有效 AXI 请求的数据不会因为 AXI 背压触发写数据超时。
- **超时/abort 后，上游必须停止并清理该 ID 的迟到数据，再复用 ID。** 没有事务 epoch 的接口无法区分旧事务迟到数据和同 ID 新事务数据。本次验证的是无迟到残留条件下无需复位的槽复用，不宣称任意迟到网络流量能自动重新同步。
- AXI 已发出后的无限 R/B 无响应不在本版本自动撤销；AXI 没有通用的事务取消握手，应由系统超时/复位策略处理。BID 保持原有 7-bit 外部兼容合同，高 5 位由单笔活动写上下文恢复。

### 命令与最终证据

从仓库根目录执行，使用 WSL/Linux Vivado 2025.2（xsim 需沙箱外执行）：

```bash
bash chi/integration/scripts/simulation/run_tb_sn_integration_baseline.sh
bash chi/integration/scripts/simulation/run_tb_sn_integration_errors.sh
```

| 回归 | 最终结果目录（相对 integration） | 结果 |
| --- | --- | --- |
| 正常基线 | `vivado_sim_wsl/tb_sn_integration_baseline_sim/run_JNsinBQI/` | 4 读/16 读拍/16 DAT、3 写/12 写拍/3 写响应/3 写完成；3 预期直传错误、1 预期 opcode 错误；`errors=0`，1805 ns PASS。 |
| 异常定向 | `vivado_sim_wsl/tb_sn_integration_errors_sim/run_d8YoZDJ7/` | 21 次 AXI 读、9 次 AXI 写；8 次预期接收错误、2 次非法 ID 拒绝、9 个汇总 AXI 错误事件（其中一次包含读写同拍双错误）；`errors=0`，11880 ns PASS。 |

两个目录均保存 `xvlog.log`、`xelab.log`、`xsim.log`；每个测试的 `latest_run.txt` 仅在 PASS 后更新。日志保留 `LIBRARY_PATH` 编译环境警告；异常 TB 的 RID/BID/RLAST 打印来自主动注入，不是计分失败。

异常覆盖包含：RRESP SLVERR/DECERR、EXOKAY 非错误、错误 RID、提前/缺少 RLAST、BRESP SLVERR/DECERR、错误 BID、完整 TxnID 不一致、非法 DAT opcode、重复 DataID、两拍后缺拍、完全无数据、孤立四拍/单拍、完整 ID 重复、低 7 位别名、DMT 属性保持、同 low7 跨读写串行化、不同 ID 同地址 RAW、DBID 响应长背压、无关上下文超时期间有效数据接收、同拍读写错误。错误后检查不误发 AXI 写、槽释放及同地址/同 ID 再次读完成。

开发过程保留了声明顺序编译失败、早期回归和 TB 错误检查的日志；最终验收以上述两个目录为准。`run_lxJoTXuW` 的“write slot released”失败是 TB 在槽已合法重分配给排队读请求后仍断言空闲，已将该并发用例改为检查新读能完成。

### 当前边界与后续工作

本版本通过的是固定整行、单笔 AXI 引擎、受支持 48 个低位索引范围内的定向功能回归；未宣称全部 CHI 协议符合性或系统交付完成。仍需 RN/HN 接入新增诊断/abort 接口、固化直传属性随 REQ 传输合同、目标 Windows Vivado 2019.2 综合及板级验证。未运行 Windows 综合、实现或系统联调。

## v0.1 — 2026-10-15：首次 WSL 基线

从只读交付 `chi/new/CHI-SN/sim_new/tb_SN_Top_new.v` 复制独立 TB，修复 WREADY 驱动竞争，初次 PASS 目录为 `vivado_sim_wsl/tb_sn_integration_baseline_sim/run_JKUUzgBy/`。此阶段只修改验证环境，SN RTL 原样；v0.2 开始实际 RTL 完善。

<!-- Modify by Michael Tan，20261015: track SN hardening changes, interface contracts, regression evidence and remaining work. -->
