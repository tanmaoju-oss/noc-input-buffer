# Torus 外部参考仓库

<!-- Modify by Michael Tan，20261023: record reference clone provenance and review boundary. -->

- 来源：https://github.com/fatemekhasraji/Torus-Systolic-array-HDL.git
- 本地目录：`Torus-Systolic-array-HDL/`（保留独立 `.git`，原始代码未修改）
- 克隆日期：2026-10-23
- 提交：`6284e28ebdca0d22c15b27639616e6dfae719eaa`
- 命令：`git clone https://github.com/fatemekhasraji/Torus-Systolic-array-HDL.git torus/docs/reference_repositories/Torus-Systolic-array-HDL`
- 检查：`git -C torus/docs/reference_repositories/Torus-Systolic-array-HDL status --short` 输出为空。

## 初步定位

该仓库是矩阵乘法 Torus 脉动阵列，包含 `rtl/Torus.v`、`rtl/PE.v`、`rtl/Controller.v` 和 `tb/Torus_tb.v`。可从 `Torus.v` 学习二维生成结构、边界回接和时钟寄存的数据循环；它并非分组交换 NoC，不能直接用作本项目路由、VC 分配、背压或死锁规避方案。

边界回接使用 `down[mat_size-1][c]` 和 `right[r][mat_size-1]`，后续评估应注意它与独立行列尺寸参数的关系。上游 README 中的部分文件名与实际目录不一致，以实际文件为准。

本次仅克隆与初步静态浏览，未运行编译、仿真或综合，未引入代码到 `torus/src/`。详细可借鉴性分析待后续开展；引用代码时保留上游 MIT 许可证。
