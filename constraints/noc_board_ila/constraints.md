# NoC board ILA constraints

此目录用于 `noc_board_ila_top` 的无 DDR 板级约束。

- `constraints/soc_dcpu_j2/` 中的文件仅为原 SoC 照片转写参考，不修改，也不直接纳入本顶层工程。
- 后续只将经过确认、且由 `noc_board_ila_top` 实际使用的时钟和复位约束写入本目录。
- 当前尚未创建 XDC；不得复制 DDR、原 SoC JTAG 或其他未使用接口的约束。

<!-- Modify create isolated constraint directory documentation, Michael Tan, 20260804 -->
