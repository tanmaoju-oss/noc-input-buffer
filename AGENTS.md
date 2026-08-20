# AGENTS.md — AI 项目协作说明

Project name: `noc-input-buffer`

//Modify rewrite this file as Codex-first session memory, Michael Tan, 20260626

## Read This First

This file is the persistent memory for the NoC/Vivado work in this repository.

When a new Codex session starts, read this file before making changes or running simulations.

Repository path:

`/home/tanma/Documents/Project/noc-input-buffer`

## Current Execution Environment

- The repository now lives on the Linux filesystem of WSL2, not under `/mnt/c`.
- Current distribution: Ubuntu 24.04 on WSL2.
- Use Linux paths and Bash commands by default.
- Linux Vivado 2025.2 is installed at `/home/tanma/tools/Xilinx/2025.2/Vivado`; load it with `source /home/tanma/tools/Xilinx/2025.2/Vivado/settings64.sh` before using `vivado`, `xvlog`, `xelab`, or `xsim`.
- The required Ubuntu packages for xsim, including GCC/G++/Make and the Vivado Linux dependency set, are installed. A temporary `/tmp` smoke run of `tb_mesh` reached `[TB_MESH] PASSED` after xsim was allowed to run outside the Codex command sandbox.
- Codex sandbox execution can cause xsim snapshot loading to fail with only `ERROR: unexpected exception when evaluating tcl command`. If `xvlog` and `xelab` succeed but this exact xsim load error appears, rerun the xsim/simulation command with approved escalated execution instead of treating it as an RTL or missing-library failure.
- Windows Vivado 2019.2 is installed at `E:\Vivado\Vivado\2019.2`. All future Vivado synthesis tasks must use this licensed Windows installation, invoked from Codex through `powershell.exe`; do not use the unlicensed Linux Vivado installation for synthesis.//Modify establish Windows Vivado synthesis rule, Michael Tan, 20260729
- Existing `.ps1` simulation records later in this file belong to the former Windows workflow. Treat them as historical run records unless the workflow has first been adapted and verified for the current environment.
- Do not report a simulation as verified in the new environment merely because old Windows-generated logs or result files exist. Record whether a result is historical or newly reproduced.
- Before future simulation work, verify the Vivado 2025.2 path and use the matching Linux/Bash entry while keeping old Windows scripts for reproducibility.

## Canonical Repository Layout

The directory layout below is mandatory for all future work:

```text
noc-input-buffer/
├── src/          # SystemVerilog design/RTL files only
│   └── board_ila/ # Reserved board-level ILA/debug RTL; no generated Vivado files
├── constraints/  # Board-specific XDC constraints and their documentation
├── testbench/    # All SystemVerilog testbench files
├── scripts/
│   ├── simulation/ # All existing simulation, compile-check, and plotting scripts
│   └── synthesis/  # Windows Vivado synthesis scripts
├── vivado_sim_windows/ # Windows Vivado simulation outputs
├── vivado_sim_wsl/     # WSL/Linux Vivado simulation outputs
└── vivado_synthesis_windows/ # Windows Vivado synthesis outputs
```

- Put synthesizable/design `.sv` files in `src/`. Do not place testbench files, scripts, logs, waveforms, or generated Vivado data there.
- `src/board_ila/` contains the DDR-free board-level NoC/ILA RTL. Do not put XDC, IP outputs, logs, or bitstreams in it.//Modify add first DDR-free board top, Michael Tan, 20260804
- Put board-specific XDC files under `constraints/<board-model>/`. The `constraints/` directory was created on 2026-08-03, but no XDC may be added until the actual board model or its official constraints are available.//Modify reserve board-constraint directory for planned ILA bring-up, Michael Tan, 20260803
- Put every testbench `.sv` file in the top-level `testbench/` directory. Do not recreate `src/tb/`, `test/tb/`, or another nested tb directory.
- Put simulation, compile-check, and result-plotting scripts in `scripts/simulation/`. Put Windows Vivado synthesis scripts in `scripts/synthesis/`.
- When the script layout changes in the Linux working copy, synchronize `scripts/` to the Windows working copy `E:\Codex-Project\NoC-XY\scripts\` before running Windows Vivado. On 2026-07-29, the Windows scripts were mirrored from Linux: obsolete root-level simulation scripts were removed, and `simulation/` plus `synthesis/` now match the Linux contents.//Modify record Windows script-layout synchronization, Michael Tan, 20260729
- Put Windows Vivado synthesis outputs under `vivado_synthesis_windows/<top_module>_synthesis/`; do not write generated synthesis files into the repository root.
- After a Windows Vivado synthesis run, copy reusable text results such as `.log`, `.rpt`, `.tcl`, and `.jou` to the Linux working copy when needed, but do not copy `.dcp` checkpoint files from Windows to Linux. Keep `.dcp` only in the Windows result directory to avoid unnecessary duplicate storage.//Modify exclude Windows DCP files from Linux result synchronization, Michael Tan, 20260729
- Give every testbench its own result directory under the platform-specific result root, normally `<result_root>/<top_module>_sim/`.
- Keep a new testbench, its run script, and its result directory paired by the same descriptive top-module name. Do not reuse another testbench's output directory.
- Never write generated simulation files into the repository root, `src/`, or `testbench/`.
- Before running a simulation, inspect the entry script and confirm that its repository root, `src/`, `testbench/`, and output paths match this layout.
- Use this naming contract for a top module named `<top>`:
  - tb: `testbench/<top>.sv`
  - Windows entry: `scripts/simulation/run_<top>.ps1`
  - Windows results: `vivado_sim_windows/<top>_sim/`
  - WSL entry: `scripts/simulation/run_<top>.sh`
  - WSL results: `vivado_sim_wsl/<top>_sim/`
- Windows synthesis entry: `scripts/synthesis/run_<top>_synthesis.ps1`
- Windows synthesis results: `vivado_synthesis_windows/<top>_synthesis/`
- `scripts/simulation/run_tb_mesh.ps1` is the shared runner. It now resolves the repository root from `scripts/simulation/../..`, design files from `src/`, tb files from `testbench/`, and default outputs from `vivado_sim_windows/`.
- The PowerShell paths remain the Windows workflow. The first reusable WSL/Linux `tb_mesh` run was completed on 2026-07-14 through `scripts/simulation/run_tb_mesh.sh`, with results under `vivado_sim_wsl/tb_mesh_sim/`.

## Script/Layout Separation Completed 2026-07-13

- Moved all top-level PowerShell entry scripts from the former `vivado_sim/` to `scripts/`.
- Updated the shared scripts so sources resolve from `src/`, tb files from `testbench/`, and default outputs under `vivado_sim_windows/<top_module>_sim/`.
- Added missing lightweight wrappers so every current file in `testbench/` has a matching `scripts/simulation/run_<top>.ps1` entry. The shared `scripts/simulation/run_tb_mesh.ps1` is both the generic runner and the entry for `tb_mesh` through its defaults.
- `vivado_sim_windows/` is now exclusively for generated or retained simulation results.

## Platform Result Split Completed 2026-07-13

- Renamed the existing Windows-generated result root from `vivado_sim/` to `vivado_sim_windows/`.
- Created the matching `vivado_sim_wsl/` root for future WSL/Linux Vivado runs.
- Keep current PowerShell entries pointed at `vivado_sim_windows/`; future Linux/Bash runners must default to `vivado_sim_wsl/`.

## User Rules

- Reply mainly in concise Chinese.
- 当用户要求编写周报或下周工作计划时，使用与 `file/2026-08-下周工作计划.txt` 一致的简洁格式：按“周一上午”至“周五下午”逐项列出。除项目研发任务外，默认纳入党建学习/材料整理及公司融资资料整理/沟通等工作安排；如用户提供了具体事项，以用户事项为准。//Modify add weekly-plan format and党建融资 coverage rule, Michael Tan, 20260807
- Do not modify source files when the user asks only for analysis or says not to modify yet.
- Before starting any code feature change, testbench creation, or Vivado simulation task, update both `AGENTS.md` and `README.md` when the task changes project state or produces reusable results.//Modify add mandatory memory-sync rule before future code/tb/simulation work, Michael Tan, 20260626
- After finishing any code feature change, testbench creation, or Vivado simulation task, update both `AGENTS.md` and `README.md` with changed files, run commands, result paths, and important simulation results.//Modify add mandatory post-task documentation rule, Michael Tan, 20260626
- For every new simulation feature, create a new tb file and a corresponding simulation entry/result directory. Do not directly repurpose an existing tb such as the 2x3 baseline sweep.//Modify add new-tb-per-feature rule, Michael Tan, 20260629
- Follow the canonical layout strictly: RTL in `src/`, tb files in `testbench/`, scripts in `scripts/`, Windows results in `vivado_sim_windows/`, and WSL/Linux results in `vivado_sim_wsl/`.
- 当用户要求将变更 Git 提交并推送到远程仓库后，还必须将远程仓库同步拉取到 Windows 目录 `E:\\Codex-Project\\NoC-XY`；确认该目录中的工作副本已更新到对应提交。//Modify add Git-to-Windows repository synchronization rule, Michael Tan, 20260729
- Every code modification must be marked near the changed code with:

```systemverilog
//Modify ..., Michael Tan, YYYYMMDD
```

- If replacing old code and the old line is useful for traceability, keep it commented:

```systemverilog
//old_code_here;//Original, Michael Tan, YYYYMMDD
new_code_here;//Modify ..., Michael Tan, YYYYMMDD
```

- Prefer Vivado/xsim verification when the user asks whether a hardware change works.
- Check generated result files and logs instead of only relying on console output.

## Current State and Next Work

- First Windows RTL synthesis completed 2026-07-29: `mesh` was synthesized for `xcvu440-flga2892-2-e` using licensed Windows Vivado 2019.2 and `scripts/synthesis/run_mesh_synthesis.ps1`, with no testbench files. Outputs are in `vivado_synthesis_windows/mesh_synthesis/` (also generated in the Windows worktree at `E:\Codex-Project\NoC-XY\vivado_synthesis_windows\mesh_synthesis\`): `synthesis.log`, `utilization.rpt`, `timing_summary.rpt`, and `mesh_synth.dcp`. `synth_design` completed with 0 errors and 0 critical warnings. The 2x3 default mesh used 30,498 LUTs (1.20%), 22,081 registers (0.44%), 0 BRAM, 0 DSP, and 542 IOBs (37.23%); IOB usage is not a board-ready result because `mesh` is an unwrapped RTL top. There is no `.xdc`, so timing is unconstrained and cannot be used for timing closure. Struct-array memories were mapped to registers, producing warnings that require later hardware-focused review.//Modify record completed first Windows RTL synthesis, Michael Tan, 20260729
- The Noxim-like injection-rate/average-latency work has already expanded from the original 2x3 baseline to multiple 5x5 sweeps.
- The latest completed experiment is the 4-flit, queue-based 5x5 knee sweep, now reproduced with Linux Vivado 2025.2 under WSL as recorded at the end of this file.
- There is no pending code change implied solely by this document. Confirm the user's next requested experiment before modifying RTL or creating another tb.
- The WSL/Linux Vivado 2025.2 baseline flow is now reproducible through `scripts/simulation/run_tb_mesh.sh`; the verified baseline output is under `vivado_sim_wsl/tb_mesh_sim/`. Historical Windows results remain useful reference data.

## Planned Board Bring-Up Baseline 2026-08-03

- This is a multi-stage NoC board/ILA task; do not treat the current planning state as a request to finish all board work in one change.//Modify record persistent board bring-up baseline, Michael Tan, 20260803
- Target FPGA is `xcvu440-flga2892-2-e`. Build, implementation, and bitstream generation must continue to use the licensed Windows Vivado 2019.2 installation; Vivado 2022 Hardware Manager is planned only for direct JTAG programming and ILA observation of the generated `.bit`/matching `.ltx` pair.
- Initial board validation uses direct Vivado JTAG download only. Do not add SD, Flash boot, DDR, SPI, UART, or the SoC's user JTAG interfaces unless the user explicitly expands scope. The JTAG-loaded configuration is volatile and is expected to be reloaded after power loss.
- Board-clock evidence is stored under `constraints/soc_dcpu_j2/`: the 100 MHz differential clock is `l_pad_clk_p/n` on `AT49/AU49` with `DIFF_SSTL12`; active-low reset is `l_pad_rst_b` on `R12` with `LVCMOS18`.
- The SoC reference confirms an `IBUFDS` differential receiver but its subsequent clock/reset path depends on DDR MIG (`ddr_ui_clk`/`ddr_ui_rst`). The DDR-free NoC top must instead use `l_pad_clk_p/n -> IBUFDS -> BUFG -> 100 MHz noc_clk` plus a reset synchronizer driven by `l_pad_rst_b`.
- Planned first hardware workload: a synthesizable 5x5, 4-VC, 4-flit, source-queued traffic generator at per-node packet-generation probability 0.1, followed by a synthesizable monitor measuring source-queue entry to TAIL arrival. ILA observes the counters and selected per-packet signals; it does not require external XDC probe pins.
- The reference simulation result for the uniform random 4-VC, 4-flit, 0.1 point is in `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_results.txt`: 2545 measured packets received, zero queue-full/errors, and average latency `22.565` cycles. Hardware must use an LFSR/PRNG, so comparable statistics are required but cycle-by-cycle equality is not.

## Active Task Started 2026-08-04: DDR-Free Board Top Step 1

- Create the isolated `constraints/noc_board_ila/` directory. Do not modify or directly reuse `constraints/soc_dcpu_j2/soc_dcpu_j2.xdc`; it remains a read-only SoC/DDR-related reference.
- Create the first synthesizable board top in `src/board_ila/`. Its scope is limited to the confirmed differential clock, reset synchronization, and 5x5 NoC integration; traffic generation, monitor, ILA, XDC, implementation, and board download remain later steps.

//Modify record start of isolated DDR-free board top task, Michael Tan, 20260804

## Current Important Files

- `src/noc.sv`: global NoC parameters and flit type definitions.
- `src/mesh.sv`: parameterized mesh generation.
- `src/input_port_Xiugai2.sv`: contains the VC/crossbar selection fix.
- `src/circular_buffer_Xiugai3.sv`: contains the Vivado declaration-order fix.
- `constraints/soc_dcpu_j2/soc_dcpu_j2.xdc`: photo-transcribed board constraints for the planned board/ILA work; includes a 100 MHz differential clock on AT49/AU49 and reset on R12, but is not yet integrated with a board top.
- `constraints/soc_dcpu_j2/soc_mult_cpu_top_port_reference.v.txt`: photo-transcribed, non-compilable SoC top-port and clock/reset reference. It confirms the XDC clock/reset names use lowercase `l_pad_*`/`o_pad_*`, and records `IBUFDS` use for the differential clock. The original post-IBUFDS clock path depends on DDR MIG outputs and must not be copied into the DDR-free NoC top.//Modify record photo-transcribed board clock/reset top reference, Michael Tan, 20260803
- `constraints/noc_board_ila/constraints.md`: isolated DDR-free NoC board-constraint directory description; no new XDC has been created yet.
- `src/board_ila/noc_board_ila_top.sv`: DDR-free board top with `IBUFDS -> BUFG`, reset synchronization, 5x5/four-VC `mesh`, and the step-2 traffic-generator integration.
- `src/board_ila/noc_board_traffic_generator.sv`: synthesizable 5x5 source-queued LFSR random traffic generator for board step 2.
- `src/board_ila/noc_board_latency_monitor.sv`: synthesizable source-queue-entry to TAIL-arrival timestamp monitor for board step 3.
- `testbench/tb_noc_board_traffic_generator.sv`: board step 2 integration verification tb.
- `scripts/simulation/run_tb_noc_board_traffic_generator.sh`: WSL/Linux Vivado entry for the board traffic-generator tb.
- `testbench/tb_noc_board_latency_monitor.sv`: board step 3 monitor integration verification tb.
- `scripts/simulation/run_tb_noc_board_latency_monitor.sh`: WSL/Linux Vivado entry for the board latency-monitor tb.
- `testbench/`: all testbench files.
- `testbench/tb_mesh_injection_sweep.sv`: current injection-rate sweep testbench.
- `scripts/simulation/run_tb_mesh.ps1`: main Vivado command-line simulation script.
- `scripts/simulation/run_tb_mesh.sh`: verified WSL/Linux Vivado 2025.2 entry for the baseline `tb_mesh` simulation.
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh`: verified WSL/Linux entry for the 20-point 4-flit 5x5 queue-knee sweep.
- `AGENTS.md`: Codex-facing memory file.
- `README.md`: Chinese user-facing project summary.

## Documentation Sync Rule

For every future task that changes code, creates/changes a tb, runs a new meaningful Vivado simulation, or produces a result file that should be reused later:

1. Update `AGENTS.md` for Codex/session handoff.
2. Update `README.md` for the user's Chinese project record.
3. Record the date, changed files, simulation command, output paths, and key pass/fail or latency results.
4. Keep the documentation concise; only record reusable state, not temporary exploration noise.

//Modify add explicit documentation synchronization workflow, Michael Tan, 20260626

## Completed 2026-08-04: DDR-Free Board Top Step 1

- Added `constraints/noc_board_ila/constraints.md`; the original `constraints/soc_dcpu_j2/` files are left unchanged and remain reference-only.
- Added `src/board_ila/noc_board_ila_top.sv`. Its only top-level ports are `l_pad_clk_p`, `l_pad_clk_n`, and `l_pad_rst_b`; it creates `noc_clk` through `IBUFDS` and `BUFG`, synchronizes reset release over two clock cycles, and instantiates the configured 5x5/four-VC `mesh` with idle local inputs.
- Linux Vivado 2025.2 compile and elaboration were run in a temporary `/tmp/noc_board_ila_compile.*` directory with all RTL sources, `xvlog --sv --relax`, and `xelab -L unisims_ver ... xil_defaultlib.noc_board_ila_top`. Both completed with no errors. Existing `mesh.sv` generate/interface warnings and inherited missing-timescale warnings remain; no simulation, synthesis, XDC, ILA, or bitstream was produced.

//Modify record completed first DDR-free board top implementation and compile check, Michael Tan, 20260804

## Completed 2026-08-05: DDR-Free Board Top Step 2

- Added `src/board_ila/noc_board_traffic_generator.sv` and integrated it into `src/board_ila/noc_board_ila_top.sv`. Every 5x5 node has an independent nonzero 16-bit LFSR, a 64-entry source queue, non-self random destination selection, and four-flit `HEAD/BODY/BODY/TAIL` packet emission through VC0. The generation threshold is `6554/65536`, approximately packet probability 0.1 per node per cycle; the NoC configuration remains four VC.
- Added `testbench/tb_noc_board_traffic_generator.sv` and `scripts/simulation/run_tb_noc_board_traffic_generator.sh`. Linux Vivado 2025.2 verification was run with `bash scripts/simulation/run_tb_noc_board_traffic_generator.sh`; sandbox xsim snapshot loading first showed the documented unexpected Tcl exception, and the approved outside-sandbox rerun passed. The result log is `vivado_sim_wsl/tb_noc_board_traffic_generator_sim/xsim.log` and reports `[TB_BOARD_TRAFFIC] PASSED received_flits=8970 errors=0` after 1000 clock cycles.
- No monitor, ILA, XDC, Windows synthesis/implementation, bitstream, or hardware download was created in this step. The next isolated step is the synthesizable source-queue-entry to TAIL-arrival monitor.

//Modify record completed synthesizable board traffic-generator step, Michael Tan, 20260805

## Active Task Started 2026-08-17: DDR-Free Board Top Step 3

- Add a synthesizable monitor under `src/board_ila/` that timestamps each source-queue enqueue and matches the encoded source/sequence packet ID when its TAIL reaches a local destination.
- Integrate the monitor into `noc_board_ila_top.sv`, expose reusable aggregate counters for later ILA observation, and add a separate WSL/Linux verification tb, runner, and result directory.
- This isolated step does not add ILA IP, XDC, Windows synthesis/implementation, bitstream generation, or board download.

//Modify record start of synthesizable board latency-monitor step, Michael Tan, 20260817

## Completed 2026-08-17: DDR-Free Board Top Step 3

- Added `src/board_ila/noc_board_latency_monitor.sv` and integrated it into `src/board_ila/noc_board_ila_top.sv`. The monitor timestamps every accepted source-queue entry and matches its four-flit packet TAIL at the local destination, retaining `monitor_packets_enqueued`, `monitor_tails_received`, `monitor_unmatched_tails`, `monitor_timestamp_overwrites`, and `monitor_total_latency_cycles` for the later ILA step. The overwrite counter flags an ID timestamp slot reused before its older packet reaches TAIL.
- Updated `src/board_ila/noc_board_traffic_generator.sv` so its existing 16-bit packet ID is unique across the 5x5 workload: upper 5 bits encode the source node index and lower 11 bits the source-local sequence. The same ID remains encoded in BODY/TAIL payloads, so no NoC routing fields changed.
- Added `testbench/tb_noc_board_latency_monitor.sv` and `scripts/simulation/run_tb_noc_board_latency_monitor.sh`. Linux Vivado 2025.2 verification used `bash scripts/simulation/run_tb_noc_board_latency_monitor.sh`; the sandbox run hit the documented xsim Tcl snapshot exception, and the approved outside-sandbox rerun passed. `vivado_sim_wsl/tb_noc_board_latency_monitor_sim/xsim.log` reports `[TB_BOARD_MONITOR] PASSED enqueued=2867 tails=2232 unmatched=0 overwrites=0 total_latency=393419 mesh_errors=0` after 1000 clock cycles. `xvlog.log`, `xelab.log`, and `xsim.log` contain no RTL `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL` records; existing mesh interface/timescale environment warnings remain.
- No ILA IP, XDC, Windows synthesis/implementation, bitstream, or board download was created. The next isolated board step is ILA integration using these counters and selected packet/debug signals.

//Modify record completed synthesizable board latency-monitor step, Michael Tan, 20260817

## Completed Work

1. Modified input buffer related logic so continuous packet injection can work.
2. Verified continuous packets with Vivado simulation.
3. Fixed a crossbar output bug in `input_port_Xiugai2.sv`.
4. Moved all testbench files into `testbench`.
5. Created Vivado simulation scripts, now organized under `scripts/`.
6. Created `tb_mesh_injection_sweep.sv` to sweep injection rates from 0.1 to 0.5 and write txt results.
7. Verified eight consecutive packets could all be received without packet loss.

## Important Bug Fixes

### circular_buffer declaration-order fix

File:

`src/circular_buffer_Xiugai3.sv`

Fix:

- Moved `assign first_flit_o = memory[read_ptr]` after `read_ptr` declaration.
- Reason: Vivado `xvlog` required `read_ptr` to be declared before use.

### input_port VC selection fix

File:

`src/input_port_Xiugai2.sv`

Original:

```systemverilog
//xb_flit_o = data_out[sa_sel_vc_reg];//Original, Michael Tan, 20260617
```

Modified:

```systemverilog
xb_flit_o = data_out[sa_sel_vc_i];//Modify to align crossbar flit with current SA-selected VC, Michael Tan, 20260617
```

Reason:

- Continuous packets could output the wrong flit when current SA-selected VC and registered VC did not match.
- The symptom was duplicate or mismatched TAIL flits.

## Testbench List

Directory:

`testbench`

Known testbenches:

- `tb_mesh.sv`: basic single packet mesh test.
- `tb_mesh_two_packets.sv`: two consecutive packets with same source and destination.
- `tb_mesh_two_distinct_packets.sv`: two packets with different source and destination.
- `tb_mesh_eight_packets.sv`: eight consecutive packets.
- `tb_mesh_injection_rate.sv`: one randomized injection-rate run.
- `tb_mesh_injection_sweep.sv`: injection-rate sweep from 0.1 to 0.5.

## Vivado Simulation

Vivado version/path used previously:

`E:\Vivado\Vivado\2019.2`

Run command template:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh.ps1 -TbFile <tb_file>.sv -Top <top_module>
```

Injection sweep command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh.ps1 -TbFile tb_mesh_injection_sweep.sv -Top tb_mesh_injection_sweep
```

Injection sweep output directory:

`vivado_sim_windows/tb_mesh_injection_sweep_sim`

Important output files:

- `xsim.log`
- `out.vcd`
- `injection_latency_results.txt`

## Latest Injection Sweep Result

Result file:

`vivado_sim_windows/tb_mesh_injection_sweep_sim/injection_latency_results.txt`

Latest verified content:

```text
injection_rate_permille injection_rate attempted injected blocked received avg_latency_cycles_x1000 error_count
100 0.100 550 550 0 550 6865 0
200 0.200 996 995 1 995 8014 0
300 0.300 1427 1314 113 1314 10861 0
400 0.400 1817 1420 397 1420 12369 0
500 0.500 2274 1447 827 1447 13490 0
```

Interpretation:

- `avg_latency_cycles_x1000` means average latency multiplied by 1000.
- Real average latency in cycles is `avg_latency_cycles_x1000 / 1000`.
- Latest run had `injected == received` for every injection rate.
- Latest run had `error_count == 0`.

## Injection Sweep Behavior

File:

`testbench/tb_mesh_injection_sweep.sv`

Current traffic:

- Every node independently attempts packet injection every cycle according to current injection rate.
- Destination is random.
- Destination is never equal to source.
- Packet is currently 2 flits: HEAD + TAIL.
- Latency is measured from packet injection cycle to TAIL arrival cycle.

Important tb behavior:

- After the measurement window, the tb stops creating new packets.
- It then finishes already-started packets by sending pending TAIL flits.
- Then it drains the network and writes statistics.
- This avoids false packet loss caused by stopping after HEAD but before TAIL.

## Noxim-Like Curve Notes

The current sweep is a functional first version, not yet a rigorous Noxim-equivalent performance experiment.

For better Noxim-like data, add or improve:

- warm-up cycles
- longer measurement cycles
- packet length configuration
- clear packet injection rate vs flit injection rate definition
- average latency in cycles
- possibly 5x5 mesh instead of 2x3

Noxim default clock period is commonly:

- `clock_period_ps = 1000`
- 1 cycle = 1 ns

But performance plots usually use latency in cycles.

## 5x5 Mesh Status

`src/noc.sv` currently has:

```systemverilog
localparam MESH_SIZE_X = 5;
localparam MESH_SIZE_Y = 5;
```

Address width:

```systemverilog
localparam DEST_ADDR_SIZE_X = $clog2(MESH_SIZE_X);
localparam DEST_ADDR_SIZE_Y = $clog2(MESH_SIZE_Y);
```

So destination address width is enough for 5x5.

Potential changes for 5x5 testing:

- `src/mesh.sv` default parameters are still 2x3.
- Most tb files still default to 2x3.
- `testbench/tb_mesh.sv` hard-codes `.MESH_SIZE_X(2)` and `.MESH_SIZE_Y(3)`.
- For the performance curve, first update `testbench/tb_mesh_injection_sweep.sv`.

Recommended first 5x5 change later:

```systemverilog
parameter MESH_SIZE_X = 5,
parameter MESH_SIZE_Y = 5,
```

in `testbench/tb_mesh_injection_sweep.sv`, then rerun Vivado simulation.

## Active Task Started 2026-06-29

Goal:

- Continue the Noxim-like injection-rate/average-latency sweep by creating a separate 5x5 sweep tb and keeping the original 2x3 sweep tb unchanged.
- First target files: `testbench/tb_mesh_injection_sweep_5x5.sv` and `scripts/simulation/run_tb_mesh_injection_sweep_5x5.ps1`.
- Planned simulation command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5.ps1
```

Expected reusable output:

- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_sim/injection_latency_results.txt`

//Modify record start of 5x5 injection sweep continuation task, Michael Tan, 20260629

## Latest 5x5 Injection Sweep Result

Date: 2026-06-29

Changed files:

- `testbench/tb_mesh_injection_sweep_5x5.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5.ps1`

Change:

- Kept the original `testbench/tb_mesh_injection_sweep.sv` as the 2x3 baseline.
- Added a separate 5x5 sweep tb with top module `tb_mesh_injection_sweep_5x5`.
- Added a dedicated 5x5 simulation script so the run produces an independent `tb_mesh_injection_sweep_5x5_sim` directory.

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5.ps1
```

Output files:

- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_sim/xsim.log`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_sim/out.vcd`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_sim/injection_latency_results.txt`

Verified result:

```text
injection_rate_permille injection_rate attempted injected blocked received avg_latency_cycles_x1000 error_count
100 0.100 2324 2321 3 2321 11189 0
200 0.200 4299 3694 605 3694 19317 0
300 0.300 6304 3923 2381 3923 24565 0
400 0.400 8355 3983 4372 3983 26400 0
500 0.500 10504 3965 6539 3965 27182 0
```

Interpretation:

- The 5x5 sweep completed successfully in Vivado/xsim.
- `injected == received` for every injection rate.
- `error_count == 0` for every injection rate.
- Average latency in cycles is `avg_latency_cycles_x1000 / 1000`, so the curve points are 11.189, 19.317, 24.565, 26.400, and 27.182 cycles.

//Modify record completed 5x5 injection sweep simulation results, Michael Tan, 20260629

## Active Task Started 2026-06-29: Noxim-Style 5x5 Sweep

Goal:

- Create a new Noxim-style 5x5 injection-rate/average-latency sweep tb.
- Keep the existing 2x3 tb and regular 5x5 tb unchanged.
- Add warm-up cycles, a measurement window, and a drain window.
- Only packets injected during the measurement window should contribute to average latency.
- Create a corresponding dedicated Vivado simulation script and independent result directory.

Planned files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_style.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_style.ps1`

Planned command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

//Modify record start of Noxim-style 5x5 sweep task, Michael Tan, 20260629

## Latest Noxim-Style 5x5 Injection Sweep Result

Date: 2026-06-29

Added files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_style.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_style.ps1`

Key behavior:

- Keeps existing 2x3 and regular 5x5 sweep tb files unchanged.
- Uses `WARMUP_CYCLES_PER_RATE = 200`, `MEASURE_CYCLES_PER_RATE = 1000`, and `DRAIN_CYCLES_PER_RATE = 3000`.
- Warm-up packets create network load but do not contribute to average latency.
- Only packets injected during the measurement window contribute to `measure_injected`, `measure_received`, and average latency.
- Drain stops new packet creation and waits for measured packets to arrive.

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

Output files:

- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_style_sim/xsim.log`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_style_sim/out.vcd`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_style_sim/injection_latency_results.txt`

Verified result:

```text
injection_rate_permille injection_rate warmup_cycles measure_cycles drain_cycles measure_attempted measure_injected measure_blocked measure_received avg_latency_cycles_x1000 error_count
100 0.100 200 1000 3000 2286 2283 3 2283 11219 0
200 0.200 200 1000 3000 4265 3689 576 3689 19164 0
300 0.300 200 1000 3000 6300 3769 2531 3769 24906 0
400 0.400 200 1000 3000 8481 3919 4562 3919 26224 0
500 0.500 200 1000 3000 10405 3944 6461 3944 27113 0
```

Interpretation:

- The Noxim-style 5x5 sweep completed successfully in Vivado/xsim.
- `measure_injected == measure_received` for every injection rate.
- `error_count == 0` for every injection rate.
- Average latency in cycles is `avg_latency_cycles_x1000 / 1000`, so the curve points are 11.219, 19.164, 24.906, 26.224, and 27.113 cycles.
- A longer first attempt with `1000 warm-up + 5000 measurement + 10000 drain` compiled and started, but was too slow for normal iteration and timed out after completing only rates 0.1 and 0.2. The current default is intentionally bounded for complete Vivado verification.

//Modify record completed Noxim-style 5x5 sweep simulation results, Michael Tan, 20260629

## Active Task Started 2026-07-01: Queue-Based Noxim-Style 5x5 Sweep

Goal:

- Create a new queue-based Noxim-style 5x5 sweep tb without modifying RTL source design files.
- Add a source queue per node inside the tb.
- Generate packets into the source queue; if the router cannot accept immediately, packets wait in the queue instead of being discarded as blocked attempts.
- Measure latency from packet generation time to TAIL arrival time for measurement-window packets.
- Add a dedicated Vivado simulation script and independent result directory.
- Generate a latency curve image after simulation.

Planned files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1`

Planned command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

//Modify record start of queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260701

## Latest Queue-Based Noxim-Style 5x5 Sweep Result

Date: 2026-07-01

Added files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1`

Generated files:

- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_sim/injection_latency_results.txt`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_sim/injection_latency_curve.png`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_sim/xsim.log`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_sim/out.vcd`

Important note:

- No RTL source design file was modified for this queue-based experiment.
- The source queues are implemented only inside the tb traffic generator.
- Latency is measured from packet generation time to TAIL arrival time for measurement-window packets.

Key settings:

- `WARMUP_CYCLES_PER_RATE = 200`
- `MEASURE_CYCLES_PER_RATE = 1000`
- `DRAIN_CYCLES_PER_RATE = 8000`
- `SOURCE_QUEUE_DEPTH = 2048`

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

Verified result:

```text
injection_rate_permille injection_rate warmup_cycles measure_cycles drain_limit_cycles drain_used_cycles measure_generated measure_enqueued measure_queue_full measure_injected measure_received max_source_queue avg_latency_cycles_x1000 error_count
100 0.100 200 1000 8000 19 2513 2513 0 2513 2513 4 12007 0
200 0.200 200 1000 8000 581 5023 5023 0 5023 5023 109 210522 0
300 0.300 200 1000 8000 1450 7497 7497 0 7497 7497 221 657669 0
400 0.400 200 1000 8000 2058 10029 10029 0 10029 10029 353 1099917 0
500 0.500 200 1000 8000 2828 12422 12422 0 12422 12422 451 1488601 0
```

Interpretation:

- The queue-based Noxim-style 5x5 sweep completed successfully in Vivado/xsim.
- `measure_injected == measure_received` for every injection rate.
- `measure_queue_full == 0` for every injection rate.
- `error_count == 0` for every injection rate.
- Average latency in cycles is `avg_latency_cycles_x1000 / 1000`, so the curve points are 12.007, 210.522, 657.669, 1099.917, and 1488.601 cycles.
- This queue-based traffic generator creates a much sharper latency increase because packets wait in source queues instead of being dropped/blocked before injection.

//Modify record completed queue-based Noxim-style 5x5 sweep simulation results, Michael Tan, 20260701

## Active Task Started 2026-07-09: Queue-Based 5x5 Sweep With Low Injection Rates

Goal:

- Create a new queue-based 5x5 Noxim-style sweep tb based on the existing queue version.
- Add injection-rate points before 0.1 so the low-load region can be checked; theoretically this part should be nearly horizontal.
- Keep previous queue tb and RTL source design files unchanged.
- Generate a dedicated simulation result directory and latency curve.

Planned files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1`

Planned rates:

- 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.20, 0.30, 0.40, 0.50

//Modify record start of low-rate queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260709

## Latest Low-Rate Queue-Based Noxim-Style 5x5 Sweep Result

Date: 2026-07-09

Added files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1`

Generated files:

- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_results.txt`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_curve_full.png`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_curve_lowrate_zoom.png`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/xsim.log`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/out.vcd`

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1
```

Verified result:

```text
injection_rate_permille injection_rate warmup_cycles measure_cycles drain_limit_cycles drain_used_cycles measure_generated measure_enqueued measure_queue_full measure_injected measure_received max_source_queue avg_latency_cycles_x1000 error_count
10 0.010 200 1000 8000 9 218 218 0 218 218 1 9724 0
20 0.020 200 1000 8000 9 491 491 0 491 491 1 10109 0
30 0.030 200 1000 8000 12 763 763 0 763 763 1 9854 0
40 0.040 200 1000 8000 13 992 992 0 992 992 2 10204 0
50 0.050 200 1000 8000 15 1261 1261 0 1261 1261 2 10268 0
60 0.060 200 1000 8000 20 1437 1437 0 1437 1437 2 10503 0
70 0.070 200 1000 8000 14 1789 1789 0 1789 1789 2 10839 0
80 0.080 200 1000 8000 12 1999 1999 0 1999 1999 2 11143 0
90 0.090 200 1000 8000 16 2227 2227 0 2227 2227 2 11602 0
100 0.100 200 1000 8000 17 2522 2522 0 2522 2522 3 11903 0
200 0.200 200 1000 8000 484 4989 4989 0 4989 4989 88 194311 0
300 0.300 200 1000 8000 1405 7530 7530 0 7530 7530 228 671800 0
400 0.400 200 1000 8000 2068 9943 9943 0 9943 9943 325 1080137 0
500 0.500 200 1000 8000 3163 12522 12522 0 12522 12522 477 1540083 0
```

Interpretation:

- The low-rate queue-based sweep completed successfully in Vivado/xsim.
- `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0` for every injection rate.
- Average latency points in cycles are 9.724, 10.109, 9.854, 10.204, 10.268, 10.503, 10.839, 11.143, 11.602, 11.903, 194.311, 671.800, 1080.137, and 1540.083.
- The 0.01 to 0.10 region is near the expected low-load horizontal region around 10 to 12 cycles, while 0.20 and above show source-queue delay growth.

//Modify record completed low-rate queue-based Noxim-style 5x5 sweep simulation results, Michael Tan, 20260709

## Active Task Started 2026-07-09: Queue-Based 5x5 Sweep With Denser Knee Rates

Goal:

- Create a new queue-based 5x5 Noxim-style sweep tb based on the low-rate queue version.
- Keep existing low-rate queue tb and RTL source design files unchanged.
- Add denser injection-rate points around 0.10 to 0.30 to check whether the high-rate curve only looks linear because sampling is too sparse.
- Generate a dedicated simulation result directory and latency curve.

Planned files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1`

Planned rates:

- 0.01, 0.03, 0.05, 0.07, 0.09, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20, 0.22, 0.24, 0.26, 0.28, 0.30, 0.35, 0.40, 0.45, 0.50

//Modify record start of knee-rate queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260709

## Latest Knee-Rate Queue-Based Noxim-Style 5x5 Sweep Result

Date: 2026-07-09

Added files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1`

Generated files:

- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_results.txt`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_curve_full.png`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_curve_knee_zoom.png`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/xsim.log`
- `vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/out.vcd`

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1
```

Verified result:

```text
injection_rate avg_latency_cycles
0.010 9.724
0.030 9.962
0.050 10.308
0.070 10.801
0.090 11.374
0.100 11.923
0.120 13.852
0.140 20.497
0.160 51.046
0.180 111.037
0.200 199.594
0.220 310.151
0.240 418.607
0.260 444.717
0.280 553.714
0.300 614.892
0.350 831.810
0.400 1064.048
0.450 1331.869
0.500 1560.861
```

Interpretation:

- The dense knee-rate queue-based sweep completed successfully in Vivado/xsim.
- `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0` for every injection rate.
- Dense sampling shows the latency knee starts around 0.14 to 0.18.
- The previously observed almost-linear high-rate segment was partly caused by sparse sampling at only 0.2/0.3/0.4/0.5.

//Modify record completed knee-rate queue-based Noxim-style 5x5 sweep simulation results, Michael Tan, 20260709

## Active Task Started 2026-07-09: 4-Flit Queue-Based 5x5 Knee Sweep

Goal:

- Create a new 4-flit packet version based on the queue knee tb.
- Keep existing queue knee tb and RTL source design files unchanged.
- Use packet format `HEAD + BODY + BODY + TAIL`.
- Keep packet-level latency measured from packet generation time to TAIL arrival time.
- Reuse the knee-rate injection points so the 4-flit curve can be compared with the previous 2-flit packet curve.

Planned files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1`

//Modify record start of 4-flit queue-based Noxim-style 5x5 knee sweep task, Michael Tan, 20260709

## Active Task Started 2026-07-01: 2x3 Four-Flit Packet Injection Sweep

Goal:

- Return to the original 2x3 `tb_mesh_injection_sweep` direction and do not modify or rerun 5x5 experiments for this task.
- Create a new dedicated 2x3 injection-rate sweep tb that keeps the original 2-flit baseline tb unchanged.
- Normalize packet format with a configurable packet length:
  - one HEAD flit
  - `PACKET_FLIT_NUM - 2` BODY flits
  - one TAIL flit
- First setting: `PACKET_FLIT_NUM = 4`, so each packet is HEAD + BODY + BODY + TAIL.
- Use the previous 2x3 sweep-style simulation cycles and result format as the base.

Planned files:

- `testbench/tb_mesh_injection_sweep_2x3_n4.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_2x3_n4.ps1`

Planned command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_2x3_n4.ps1
```

Expected reusable output:

- `vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/injection_latency_results.txt`

//Modify record start of 2x3 four-flit packet sweep task, Michael Tan, 20260701

## Latest 2x3 Four-Flit Packet Injection Sweep Result

Date: 2026-07-01

Added files:

- `testbench/tb_mesh_injection_sweep_2x3_n4.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_2x3_n4.ps1`

Key behavior:

- Keeps the original 2x3 `testbench/tb_mesh_injection_sweep.sv` unchanged as the 2-flit baseline.
- Adds configurable packet length through `PACKET_FLIT_NUM`.
- Current setting is `PACKET_FLIT_NUM = 4`, so each packet is HEAD + BODY + BODY + TAIL.
- BODY flits use `BODY` as `flit_label` and carry the packet id in `bt_pl`.
- The monitor accepts and counts BODY flits, checks that exactly `PACKET_FLIT_NUM - 2` BODY flits arrive before TAIL, and still counts packet latency on TAIL arrival.

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_2x3_n4.ps1
```

Output files:

- `vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/xsim.log`
- `vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/out.vcd`
- `vivado_sim_windows/tb_mesh_injection_sweep_2x3_n4_sim/injection_latency_results.txt`

Verified result:

```text
packet_flit_num injection_rate_permille injection_rate attempted injected blocked received avg_latency_cycles_x1000 error_count
4 100 0.100 457 457 0 457 10008 0
4 200 0.200 780 732 48 732 12596 0
4 300 0.300 1032 829 203 829 14498 0
4 400 0.400 1361 865 496 865 15662 0
4 500 0.500 1569 889 680 889 16068 0
```

Interpretation:

- The 2x3 four-flit packet sweep completed successfully in Vivado/xsim.
- `injected == received` for every injection rate.
- `error_count == 0` for every injection rate.
- Average latency in cycles is `avg_latency_cycles_x1000 / 1000`, so the curve points are 10.008, 12.596, 14.498, 15.662, and 16.068 cycles.
- Log check found no `ERROR:`, `CRITICAL WARNING`, or `$error`; only the existing-style timescale warning appeared.

//Modify record completed 2x3 four-flit packet sweep simulation results, Michael Tan, 20260701

## Git / Backup Preference

The user previously backed up folders manually, for example `test - 20260622备份`.

Future recommendation:

- Use Git commits as backup checkpoints.
- Before making changes, check `git status`.
- After a verified working state, commit the relevant files.
- Do not run destructive Git commands unless the user explicitly asks.

Current Git setup notes:

- `.gitignore` was added to keep source files, tb files, scripts, and docs in Git while excluding Vivado generated outputs, waveform/database files, and manual backup archives.
- `kpi/` is ignored by default because it appears to contain report/material files rather than active NoC source.//Modify clarify kpi folder is excluded from code backup, Michael Tan, 20260626
- Local Git repository has been initialized, current branch is `main`, and the first backup commit is `8b2abe7 Initial NoC source backup`.//Modify record completed local Git initialization, Michael Tan, 20260626
- GitHub remote `origin` is bound to `https://github.com/tanmaoju-oss/noc-input-buffer.git`, and local `main` tracks `origin/main`.//Modify record GitHub remote binding, Michael Tan, 20260626
- GitHub access from command-line Git may need the user's v2rayN proxy. The usual local proxy is `http://127.0.0.1:10808`; configure with `git config --global http.proxy http://127.0.0.1:10808` and `git config --global https.proxy http://127.0.0.1:10808` if `git push` cannot connect to `github.com:443`.//Modify record v2rayN proxy configuration for GitHub push/pull, Michael Tan, 20260713
- `AGENTS.md` and `README.md` are tracked and must be pushed to GitHub with reusable project-state changes, as explicitly requested by the user.//Modify change documentation GitHub tracking policy, Michael Tan, 20260729
- Initial local Git setup should use repository-local identity if global identity is not configured:

```powershell
git config user.name "Michael Tan"
git config user.email "tanma@local"
```

//Modify add current Git setup notes, Michael Tan, 20260626

## Weekly Report Writing Preference

- When drafting a "下周进展" weekly report, use a fixed Monday-to-Friday schedule with separate morning and afternoon entries, for a total of ten entries.
- Balance the entries across: (1) R&D work currently focused on Vivado `mesh` synthesis flow, report review, and script debugging, (2) Party-building work, and (3) company financing work.
- When possible, concentrate Party-building and company-financing entries into no more than two weekdays, leaving the remaining weekdays focused on R&D work.
- For the August-September two-month plan, keep the R&D plan paced through synthesis-to-board preparation and debugging; do not list clock/XDC constraints as an immediate task or prematurely claim timing closure, implementation completion, or board-level validation.

//Modify record weekly-report schedule and scope preference, Michael Tan, 20260731

## Latest MBO Document Status

Date: 2026-06-29

Current latest MBO file:

`kpi/MBO/MBO-7月-v0.5.docx`

Version history in `kpi/MBO`:

- `MBO-7月-v0.1.docx`: original file, mostly previous month's content with the first three indicator names changed by user.
- `MBO-7月-v0.2.docx`: first Codex rewrite; included 5x5/Noxim wording, later rejected for MBO wording.
- `MBO-7月-v0.3.docx`: removed 5x5/Noxim but over-emphasized progress retention, later rejected.
- `MBO-7月-v0.4.docx`: rewrote MBO wording toward objective/result/acceptance style.
- `MBO-7月-v0.5.docx`: current accepted direction; based on user feedback, mainly revised the third item and removed current-stage latency-statistics wording.

Current v0.5 first three indicators:

1. `注入率功能逻辑设计和逻辑代码编写`
2. `随机模式流量测试场景的逻辑设计和代码编写`
3. `流量场景仿真验证与结果分析`

Important MBO writing preferences for next month:

- Do not write personal progress retention / progress sorting as an MBO objective; those are internal work records.
- Do not write intermediate process details as MBO acceptance criteria, such as specific result directories, `xsim.log`, `out.vcd`, or exact output file names.
- Do not over-list raw statistic field names such as `attempted`, `blocked`, `received`, or `avg_latency` in MBO language.
- For the current stage, do not emphasize latency statistics in the MBO. v0.5 intentionally removed `平均延迟`, `延迟统计`, `avg_latency`, and `性能结果` wording.
- Avoid writing `5x5` or `Noxim` into this MBO unless the user explicitly asks next time.
- The third indicator should remain about simulation and verification, but its title should not be too similar to the second indicator.
- Preferred MBO style: describe target, verification outcome, and acceptance result; avoid explaining why the work matters or how it preserves future progress.

Rendering note:

- DOCX structural/text checks passed for v0.5.
- Visual render QA could not be completed in this environment because `soffice`/LibreOffice is not available.

//Modify record latest MBO v0.5 status and future MBO writing preferences, Michael Tan, 20260629

## Latest MBO Update After Leader Feedback

Date: 2026-06-29

Current latest MBO file is now:

`kpi/MBO/MBO-7月-v0.7.docx`

Changes from v0.6:

- First indicator was changed from a verification-module-like description to code optimization:
  `注入率控制与统计逻辑代码优化`
- Second indicator was changed to code optimization and traffic-mode expansion:
  `多流量模式测试场景代码优化`
- Added `定向流量模式` alongside random traffic mode, because leader feedback was that random traffic mode alone is too limited.
- Third indicator was synchronized to mention `随机及定向流量模式` in simulation/verification wording.
- Keep the MBO style focused on code optimization, traffic mode coverage, simulation verification, and acceptance results. Avoid low-level file/log/process details.

//Modify record latest MBO v0.7 after leader feedback on traffic modes and code optimization wording, Michael Tan, 20260629

## Latest MBO Structural Rewrite

Date: 2026-06-29

Current latest MBO file is now:

`kpi/MBO/MBO-7月-v0.8.docx`

Current logic for the first three MBO indicators:

1. `流量测试代码设计与优化`
   - Test-code design and optimization.
   - Includes injection-rate configuration optimization and multi-mode injection implementation.
2. `流量场景仿真验证与结果分析`
   - Based on the optimized test code, run simulation verification.
   - Covers different injection rates plus random and directed traffic modes.
3. `NoC设计逻辑代码优化`
   - Based on simulation verification results, feed findings back into NoC design logic code optimization.
   - Focus is the SystemVerilog design logic files under `src/`, not the testbench itself.

Important wording direction:

- First indicator combines the previous first and second code-oriented items.
- Second indicator carries the simulation verification content.
- Third indicator is newly written for design logic optimization based on simulation feedback.
- Avoid saying "20 sv files" in the MBO; describe it as `src目录下NoC设计逻辑相关SystemVerilog代码`.

//Modify record latest MBO v0.8 structure: test code optimization, simulation verification, design logic optimization, Michael Tan, 20260629

## Active Task Completed 2026-07-09: 4-Flit Queue-Based 5x5 Knee Sweep

User request:

- Based on the previous queue-based knee version, create a packet=4-flit version and inspect the final latency curve.
- Keep old tb files unchanged; create a new tb and a new simulation entry.

New files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1`

Key tb behavior:

- `PACKET_FLIT_NUM = 4`
- Packet format is `HEAD + BODY + BODY + TAIL`.
- Injection rate is still packet injection probability per node per cycle.
- Average latency is packet latency, measured from packet generation/source-queue entry to TAIL arrival.
- BODY flits are checked for destination correctness but are not counted as received packets.

Simulation command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\simulation\run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1
```

Result directory:

`vivado_sim_windows/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim`

Important outputs:

- `injection_latency_results.txt`
- `xsim.log`
- `out.vcd`
- `injection_latency_curve_full.png`
- `injection_latency_curve_knee_zoom.png`
- `injection_latency_curve_compare_2flit_4flit.png`

Result summary:

```text
rate latency_cycles injected received queue_full errors
0.010 11.926 218 218 0 0
0.030 12.885 717 717 0 0
0.050 14.321 1246 1246 0 0
0.070 17.837 1726 1726 0 0
0.090 32.167 2272 2272 0 0
0.100 43.648 2508 2508 0 0
0.120 144.500 3013 3013 0 0
0.140 322.095 3549 3549 0 0
0.160 443.284 3953 3953 0 0
0.180 549.853 4488 4488 0 0
0.200 708.787 5017 5017 0 0
0.220 876.969 5571 5571 0 0
0.240 1012.406 6116 6116 0 0
0.260 1078.915 6430 6430 0 0
0.280 1278.587 6915 6915 0 0
0.300 1328.675 7406 7406 0 0
0.350 1724.089 8697 8697 0 0
0.400 2059.889 9894 9894 0 0
0.450 2521.052 11161 11161 0 0
0.500 2863.854 12588 12588 0 0
```

Conclusion:

- Vivado/xsim completed all 20 injection-rate points.
- For every point, `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0`.
- Compared with the previous 2-flit knee run, the 4-flit packet curve rises earlier and higher because the x-axis remains packet injection rate while each packet consumes more flit bandwidth.
- No RTL source design files were modified for this task; only a new tb, a new simulation entry, generated result files, and documentation were changed.

//Modify record completed 4-flit 5x5 queue-knee sweep simulation and plot outputs, Michael Tan, 20260709

## Environment Migration 2026-07-13

- Renamed the AI-facing `Remember.md` to the standard repository instruction file `AGENTS.md`.
- Renamed the user-facing Chinese `项目说明.md` to `README.md`.
- Updated internal document references and the repository path for WSL/Linux.
- Added an explicit environment boundary: existing PowerShell commands and Vivado results are Windows-era records; Vivado/xsim has not yet been reproduced in the new WSL environment.
- No RTL, testbench, simulation script, or generated result was changed as part of this migration.

## Project Rename 2026-07-13

- Renamed the repository directory from `6.input_buffer` to `noc-input-buffer`.
- Naming rationale: lowercase kebab-case is conventional for Git/Linux projects, and the name matches the existing GitHub repository.
- Current canonical local path: `/home/tanma/Documents/Project/noc-input-buffer`.

## Repository Layout Migration 2026-07-13

- Design/RTL `.sv` files moved from the former `test/` design area to top-level `src/`.
- Testbench files moved from `test/tb/` to top-level `testbench/`.
- Vivado scripts and historical simulation directories first moved from `test/vivado_sim/` to the top level; scripts were later separated into `scripts/`, and Windows results were renamed to `vivado_sim_windows/`.
- Updated this file and `README.md` to use the new canonical paths throughout.
- A later layout task separated PowerShell scripts into `scripts/` and fixed their canonical source/tb/result path resolution.

## Legacy Buffer Directory Removal 2026-07-13

- Removed the obsolete top-level `buffer/` directory after the canonical RTL and testbench files had been organized under `src/` and `testbench/`.
- The removal deletes only tracked legacy duplicates/notes from `buffer/`; the canonical project files remain in their required locations.
- Synchronized and uploaded `AGENTS.md` and `README.md` with this cleanup.

//Modify record removal of obsolete buffer directory and Markdown synchronization, Michael Tan, 20260713

## Active Task Started 2026-07-14: First Reproducible WSL tb_mesh Simulation

Goal:

- Add the first Linux/Bash Vivado simulation entry at `scripts/simulation/run_tb_mesh.sh`.
- Keep the existing Windows PowerShell workflow unchanged.
- Compile, elaborate, and run the existing `testbench/tb_mesh.sv` with Linux Vivado 2025.2.
- Save reusable WSL outputs under `vivado_sim_wsl/tb_mesh_sim/`.
- Run xsim with approved escalated execution when invoked by Codex, because sandboxed xsim snapshot loading was proven to produce a false `unexpected exception` failure even when all libraries were present.
- After the run, inspect generated logs and outputs and synchronize the verified result into both `AGENTS.md` and `README.md`.

Planned command:

```bash
bash scripts/simulation/run_tb_mesh.sh
```

Expected outputs:

- `vivado_sim_wsl/tb_mesh_sim/xvlog.log`
- `vivado_sim_wsl/tb_mesh_sim/xelab.log`
- `vivado_sim_wsl/tb_mesh_sim/xsim.log`
- `vivado_sim_wsl/tb_mesh_sim/out.vcd`

//Modify record start of first reproducible WSL/Linux tb_mesh simulation task, Michael Tan, 20260714

## First Reproducible WSL tb_mesh Simulation Completed 2026-07-14

Changed file:

- `scripts/simulation/run_tb_mesh.sh`

Environment:

- Ubuntu 24.04 on WSL2.
- Vivado/xvlog/xelab/xsim 2025.2 from `/home/tanma/tools/Xilinx/2025.2/Vivado`.
- GCC, G++, Make, and the checked Vivado Linux dependency packages are installed.

Command:

```bash
bash scripts/simulation/run_tb_mesh.sh
```

Result directory:

`vivado_sim_wsl/tb_mesh_sim/`

Verified outputs:

- `xvlog.log`
- `xelab.log`
- `xsim.log`
- `out.vcd` (391352 bytes)
- `tb_mesh_sim.wdb`

Verified result:

```text
[TB_MESH] output flit 0 at (1,2): label=0 vc=0 time=96000
[TB_MESH] output flit 1 at (1,2): label=2 vc=0 time=106000
[TB_MESH] PASSED
$finish called at time : 135 ns
```

Log interpretation:

- `xvlog`, `xelab`, and `xsim` all completed successfully.
- The generated logs contain no `ERROR:`, `CRITICAL WARNING`, `$error`, or `FAILED` result.
- Existing Vivado warnings remain for generated/array interface connections in `src/mesh.sv`, missing timescales in several design modules, and the detected `LIBRARY_PATH`; they did not prevent this test from passing.

Codex execution rule for future simulations:

- The earlier sandboxed xsim runs failed while loading a valid snapshot with `ERROR: unexpected exception when evaluating tcl command`.
- Running the same snapshot outside the Codex command sandbox passed. This establishes the command sandbox as the cause of that specific failure in this environment.
- Future Codex Vivado/xsim simulations must use an approved escalated command such as `bash scripts/simulation/run_tb_mesh.sh`. The approval prefix for this command was saved during this task.
- Always inspect the generated result-directory logs and output files after the run; do not rely only on console output.

No RTL or testbench file was modified for this environment/workflow task.

//Modify record verified WSL Vivado 2025.2 tb_mesh flow and sandbox execution rule, Michael Tan, 20260714

## Active Task Started 2026-07-14: WSL 4-Flit 5x5 Queue-Knee Sweep

Goal:

- Reproduce the previously Windows-verified `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv` experiment with Linux Vivado 2025.2 on WSL2.
- Keep the existing tb, RTL, PowerShell entry, and Windows result directory unchanged.
- Add `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh`.
- Save Linux outputs under `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/`.
- Run the script with approved escalated execution so xsim does not hit the confirmed Codex sandbox snapshot-loading failure.
- Verify all 20 injection-rate rows, `measure_injected == measure_received`, `measure_queue_full == 0`, `error_count == 0`, and generated logs/result files.

Planned command:

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh
```

Expected key outputs:

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_results.txt`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/xsim.log`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/out.vcd`

//Modify record start of WSL reproduction for 4-flit 5x5 queue-knee sweep, Michael Tan, 20260714

## WSL 4-Flit 5x5 Queue-Knee Sweep Completed 2026-07-14

Added file:

- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh`

Unchanged files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv`
- All RTL files under `src/`
- The existing PowerShell entry and `vivado_sim_windows/` historical results

Command:

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh
```

WSL result directory:

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/`

Key outputs:

- `injection_latency_results.txt` (header plus 20 data rows)
- `xvlog.log`
- `xelab.log`
- `xsim.log`
- `out.vcd` (2154609075 bytes)
- `tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim.wdb`

Linux Vivado 2025.2 result summary:

```text
rate latency_cycles injected received queue_full errors
0.010 11.953 235 235 0 0
0.030 12.921 739 739 0 0
0.050 14.762 1248 1248 0 0
0.070 18.578 1744 1744 0 0
0.090 37.283 2303 2303 0 0
0.100 61.024 2545 2545 0 0
0.120 176.726 3014 3014 0 0
0.140 316.597 3593 3593 0 0
0.160 412.535 4020 4020 0 0
0.180 551.897 4462 4462 0 0
0.200 712.666 5029 5029 0 0
0.220 856.253 5572 5572 0 0
0.240 987.239 6132 6132 0 0
0.260 1079.501 6453 6453 0 0
0.280 1293.909 6975 6975 0 0
0.300 1405.161 7499 7499 0 0
0.350 1846.494 8946 8946 0 0
0.400 2139.670 10089 10089 0 0
0.450 2558.392 11288 11288 0 0
0.500 2876.995 12530 12530 0 0
```

Verification:

- All 20 requested injection-rate points completed.
- Automated row validation reported `data_rows=20` and `bad_rows=0`.
- Every row has `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0`.
- The run finished at simulation time 586175 ns; xsim reported about 11 minutes 31 seconds elapsed and about 1450 MB peak process memory.
- Generated logs contain no `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL`.
- Existing interface/timescale/`LIBRARY_PATH` warnings remain non-fatal.

Windows comparison note:

- The WSL/Linux statistics are not numerically identical to the prior Windows Vivado 2019.2 results despite using the same tb seed.
- The likely reason is version/platform-dependent SystemVerilog `$urandom` sequence behavior between Vivado 2019.2 on Windows and Vivado 2025.2 on Linux. The acceptance invariants and overall latency-knee behavior remain consistent.

Codex execution rule:

- This long xsim run was executed outside the command sandbox using the approved prefix `bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sh`.
- Reuse that approved command for future reruns, then validate the generated result table and logs.

//Modify record completed Linux Vivado 2025.2 reproduction of 4-flit 5x5 queue-knee sweep, Michael Tan, 20260714

## Active Task Started 2026-07-14: WSL 4-Flit Queue-Knee Latency Plot

Goal:

- Generate a PNG curve from the WSL/Linux `injection_latency_results.txt` produced by the completed 4-flit 5x5 queue-knee sweep.
- Match the existing Windows full-curve presentation: injection rate on the x-axis, average packet latency in cycles on the y-axis, blue line/markers, grid, and 1100x720 output size.
- Save the image as `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_curve_full.png`.
- Verify that the plotted 20 points exactly match the WSL result table, then synchronize the final output into `AGENTS.md` and `README.md`.

//Modify record start of WSL 4-flit queue-knee latency plot task, Michael Tan, 20260714

## WSL 4-Flit Queue-Knee Latency Plot Completed 2026-07-14

Added reusable plotting script:

- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.py`

Command:

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.py
```

Generated image:

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_curve_full.png`

Plot details:

- Source: the WSL/Linux `injection_latency_results.txt` from the verified Vivado 2025.2 run.
- X-axis: injection rate in packet/cycle/node.
- Y-axis: average packet latency in cycles (`avg_latency_cycles_x1000 / 1000`).
- Contains all 20 result points.
- Uses a blue line with circular markers and gray grid, matching the existing Windows full-curve style.
- PNG dimensions are 1100x719 pixels and file size is 47828 bytes.
- The generator uses the already installed Graphviz `neato` renderer and Python standard library; matplotlib is not required.
- Visual inspection confirmed the expected low-load flat region, knee after approximately 0.10, and continued high-load latency growth.

//Modify record generated and verified WSL 4-flit injection-latency curve, Michael Tan, 20260714

## Active Task Started 2026-07-14: WSL 4-Flit Queue-Knee Zoom Plot

Goal:

- Extend the existing WSL plot generator to also create `injection_latency_curve_knee_zoom.png`.
- Match the Windows knee-zoom range: injection rate 0.00 to 0.16 and average packet latency 0 to 500 cycles.
- Plot the 9 WSL result points from 0.01 through 0.16 with the same blue line/marker and gray-grid style.
- Keep regenerating the existing full curve in the same command.

//Modify record start of WSL 4-flit queue-knee zoom plot task, Michael Tan, 20260714

## WSL 4-Flit Queue-Knee Zoom Plot Completed 2026-07-14

Command:

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.py
```

Generated image:

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim/injection_latency_curve_knee_zoom.png`

Plot details:

- Injection-rate range: 0.00 to 0.16.
- Average-latency range: 0 to 500 cycles.
- Includes the nine Linux/WSL data points at 0.01, 0.03, 0.05, 0.07, 0.09, 0.10, 0.12, 0.14, and 0.16.
- Image format and size: RGB PNG, 1100 x 719 pixels, 45,412 bytes.
- Visual inspection confirmed that the axes, blue line/circle style, grid, and zoom range correspond to the existing Windows knee-zoom plot.
- The reusable plotting script now regenerates both the full-range curve and this 0.16 zoom curve from the Linux result text file.

//Modify record completed WSL 4-flit queue-knee zoom plot, Michael Tan, 20260714

## Active Task Started 2026-07-15: Four-Virtual-Channel RTL

Goal:

- Expand the current NoC design from 2 virtual channels to 4 virtual channels.
- Audit VC identifier widths, input buffering, VC allocation, and switch allocation instead of assuming that changing only the global constant is sufficient.
- Keep existing testbenches unchanged and add a new simple dedicated testbench that exercises VC0, VC1, VC2, and VC3.
- Add a matching WSL/Linux Vivado 2025.2 run script and independent result directory.
- Verify the generated logs and test result before recording completion.

Planned files:

- RTL under `src/` as required by the four-VC audit, beginning with `src/noc.sv`.
- `testbench/tb_mesh_4vc_simple.sv`
- `scripts/simulation/run_tb_mesh_4vc_simple.sh`

Planned command:

```bash
bash scripts/simulation/run_tb_mesh_4vc_simple.sh
```

Expected result directory:

`vivado_sim_wsl/tb_mesh_4vc_simple_sim/`

//Modify record start of four-virtual-channel RTL and simple verification task, Michael Tan, 20260715

## Four-Virtual-Channel RTL and Simple Test Completed 2026-07-15

Changed RTL:

- `src/noc.sv`: changed global `VC_NUM` from 2 to 4; `VC_SIZE = $clog2(VC_NUM)` therefore becomes 2 bits.
- `src/separable_input_first_allocator.sv`: changed its standalone default `VC_NUM` from 2 to 4. Router instances already pass the global value explicitly, but the default is now consistent.

Added verification files:

- `testbench/tb_mesh_4vc_simple.sv`
- `scripts/simulation/run_tb_mesh_4vc_simple.sh`

Audit conclusion:

- Input ports generate one independent input buffer per `VC_NUM`.
- VC identifiers, allocator matrices, flow-control vectors, allocator loops, and switch-selection widths derive from `VC_NUM`/`VC_SIZE`.
- The round-robin allocator supports four agents, so no further fixed two-VC RTL was found in the active path.

Vivado command:

```bash
bash scripts/simulation/run_tb_mesh_4vc_simple.sh
```

Result directory:

`vivado_sim_wsl/tb_mesh_4vc_simple_sim/`

Verified result file:

```text
vc_num expected_flits received_flits head_seen tail_seen output_vc_seen error_count
4 8 8 1111 1111 0011 0
```

Verification interpretation:

- The tb first injects HEAD flits into input VC0, VC1, VC2, and VC3, then injects the four matching TAIL flits. This keeps all four source VCs active in the same test.
- All four packets and all eight flits arrived at the expected destination with correct packet IDs and ordering.
- `head_seen=1111`, `tail_seen=1111`, and `error_count=0`; xsim printed `[TB_MESH_4VC] PASSED` at 245 ns.
- `output_vc_seen=0011` is valid: downstream VC numbers are independently reallocated at every hop, and this traffic needed only downstream VC0/VC1 even though all four source input VCs were exercised.
- `xvlog.log`, `xelab.log`, and `xsim.log` contain no `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL`. Existing interface/timescale/`LIBRARY_PATH` warnings remain non-fatal.
- The Bash runner now requires the tb PASS marker, because xsim can return process status 0 even after a SystemVerilog `$fatal`.

Key generated files:

- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/tb_mesh_4vc_simple_results.txt`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/xvlog.log`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/xelab.log`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/xsim.log`
- `vivado_sim_wsl/tb_mesh_4vc_simple_sim/out.vcd`

//Modify record completed four-virtual-channel RTL and simple Vivado verification, Michael Tan, 20260715

## Active Task Started 2026-07-15: Four-VC 5x5 4-Flit Queue-Knee Sweep

Goal:

- Run the previous 5x5 Noxim-style queue-based 4-flit knee sweep with the new four-VC RTL.
- Do not reuse or overwrite the previous tb name or its WSL result directory.
- Create a separate tb named `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`.
- Add `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh` and save results under the matching independent WSL directory.
- Keep the same 20 injection-rate points, 4-flit packet format, queue depth, warm-up, measurement, and drain settings for comparison with the earlier run.
- Verify all rows, packet accounting invariants, queue-full/error counts, and generated Vivado logs.

Planned command:

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh
```

Expected result directory:

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/`

//Modify record start of independent four-VC 5x5 4-flit queue-knee sweep, Michael Tan, 20260715

## Four-VC 5x5 4-Flit Queue-Knee Sweep Completed 2026-07-15

Added files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`

Isolation and configuration:

- The previous `tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit` tb and result directory were not reused or overwritten.
- The new tb requires `VC_NUM=4` and `VC_SIZE=2` at runtime.
- It retains the previous 20 injection-rate points, `PACKET_FLIT_NUM=4`, `WARMUP_CYCLES_PER_RATE=200`, `MEASURE_CYCLES_PER_RATE=1000`, `DRAIN_CYCLES_PER_RATE=8000`, and `SOURCE_QUEUE_DEPTH=2048`.

Command:

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sh
```

Result directory:

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/`

Linux Vivado 2025.2 result summary:

```text
rate latency_cycles injected received queue_full errors
0.010 11.948 235 235 0 0
0.030 12.820 739 739 0 0
0.050 14.400 1248 1248 0 0
0.070 16.378 1744 1744 0 0
0.090 19.817 2303 2303 0 0
0.100 22.565 2545 2545 0 0
0.120 35.714 3014 3014 0 0
0.140 84.153 3593 3593 0 0
0.160 153.643 4020 4020 0 0
0.180 268.786 4462 4462 0 0
0.200 391.048 5029 5029 0 0
0.220 474.048 5572 5572 0 0
0.240 571.510 6132 6132 0 0
0.260 645.762 6453 6453 0 0
0.280 794.567 6975 6975 0 0
0.300 887.461 7499 7499 0 0
0.350 1223.836 8946 8946 0 0
0.400 1418.524 10089 10089 0 0
0.450 1704.706 11288 11288 0 0
0.500 1913.803 12530 12530 0 0
```

Verification:

- All 20 rows completed; automated validation reported `data_rows=20` and `bad_rows=0`.
- Every row has `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0`.
- `xvlog.log`, `xelab.log`, and `xsim.log` contain no `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL`.
- Simulation finished at 464335 ns in approximately 11 minutes 31 seconds, with about 1450 MB peak process memory.
- Key files include `injection_latency_results.txt` (1488 bytes), `xsim.log` (6108 bytes), and `out.vcd` (2604935407 bytes).

Comparison with the prior two-VC WSL run:

- The same random traffic counts were reproduced, so the latency comparison is directly useful for this experiment.
- At rates 0.10, 0.20, and 0.50, average latency changed from 61.024/712.666/2876.995 cycles to 22.565/391.048/1913.803 cycles with four VCs.
- The four-VC curve still saturates under high offered load, but its knee is later and queueing latency is lower across the sampled congested region.

//Modify record completed independent four-VC 5x5 4-flit queue-knee Vivado sweep, Michael Tan, 20260715

## Active Task Started 2026-07-15: Four-VC Queue-Knee Plots

Goal:

- Generate two PNG plots from the completed four-VC 5x5 4-flit queue-knee result table.
- Match the prior two-VC WSL plot style and axis ranges for direct visual comparison.
- Create one full-range plot for injection rate 0.00-0.50 and latency 0-3000 cycles.
- Create one knee zoom plot for injection rate 0.00-0.16 and latency 0-500 cycles.
- Use a separate reusable `_4vc` plotting script and save both images in the four-VC result directory.

Planned script:

`scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

//Modify record start of four-VC full and knee-zoom latency plots, Michael Tan, 20260715

## Four-VC Queue-Knee Plots Completed 2026-07-15

Added reusable script:

- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

Command:

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

Generated images:

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_curve_full.png`
- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_curve_knee_zoom.png`

Verification:

- The full plot contains all 20 result points and uses the same 0.00-0.50 injection-rate and 0-3000 cycle ranges as the prior two-VC full plot.
- The zoom plot contains the nine points from 0.01 through 0.16 and uses the same 0.00-0.16 and 0-500 cycle ranges as the prior two-VC zoom plot.
- Both images are RGB PNG files at 1100 x 719 pixels.
- Full image size is 45852 bytes; zoom image size is 40185 bytes.
- Visual inspection confirmed correct four-VC titles, blue line/circle style, grid, axes, no clipping, and the expected later latency knee.

//Modify record completed four-VC full and knee-zoom latency plots, Michael Tan, 20260715

## Active Task Started 2026-07-15: Adjust Four-VC Knee Zoom Range

Goal:

- Redraw the four-VC knee zoom because the inherited 0.00-0.16 range stops before the steep rise is fully visible.
- Use injection rate 0.00-0.24 and latency 0-700 cycles, covering 13 measured points through the 571.510-cycle result at rate 0.24.
- Use clean ticks of 0.04 injection rate and 100 latency cycles.
- Replace only the four-VC `injection_latency_curve_knee_zoom.png`; retain the full-range plot and the separate two-VC images.

//Modify record start of improved four-VC knee zoom range, Michael Tan, 20260715

## Four-VC Knee Zoom Range Adjustment Completed 2026-07-15

Changed script:

- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

Command:

```bash
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

Updated image:

- `vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/injection_latency_curve_knee_zoom.png`

Final zoom settings and verification:

- Injection-rate range: 0.00-0.24 with 0.04 tick spacing.
- Average-latency range: 0-700 cycles with 100-cycle tick spacing.
- Includes 13 measured points from rate 0.01 through 0.24.
- The 0.16-0.24 steep rise from 153.643 to 571.510 cycles is now fully visible.
- RGB PNG, 1100 x 719 pixels, 44257 bytes.
- Visual inspection confirmed readable axes, no clipping, useful top margin, and a clear flat-to-knee-to-steep-rise transition.
- The full-range image is still regenerated by the same command with its unchanged 0.00-0.50/0-3000 ranges.

//Modify record completed improved four-VC knee zoom range, Michael Tan, 20260715

## Active Task Started 2026-07-15: Four-VC Throughput Sweep

Goal:

- Add a new independent throughput experiment for the four-VC 5x5 4-flit queue-based traffic mode.
- Keep all existing latency testbenches and result directories unchanged.
- Measure delivered flits and completed packets strictly inside a fixed 1000-cycle measurement window after warm-up.
- Report normalized flit throughput in flit/cycle/node and packet throughput in packet/cycle/node.
- Continue draining after measurement only for packet-integrity checks; exclude drain traffic from throughput statistics.
- Sweep the same 20 offered packet rates from 0.01 through 0.50, then generate a throughput curve expected to plateau after saturation.

Planned files:

- `testbench/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `scripts/simulation/run_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`
- `scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

//Modify record start of independent four-VC throughput sweep and curve, Michael Tan, 20260715

## Four-VC Throughput Sweep and Curve Completed 2026-07-15

Added files:

- `testbench/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `scripts/simulation/run_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sh`
- `scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

Measurement definition:

- Counts every flit delivered at the 25 local outputs during exactly 1000 complete measurement clock edges after 200 warm-up cycles.
- Normalized flit throughput is `received_flits_window / (1000 * 25)` in flit/cycle/node.
- Packet throughput counts TAIL flits in the same window and uses packet/cycle/node.
- Drain traffic is excluded from throughput, while drain still verifies all measurement packets eventually arrive without loss.

Commands:

```bash
bash scripts/simulation/run_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.sh
python3 scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

Result directory:

`vivado_sim_wsl/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/`

Verified throughput summary:

```text
packet_rate flit_throughput packet_throughput
0.010 0.03772 0.00940
0.030 0.11836 0.02964
0.050 0.19900 0.04956
0.070 0.27900 0.06968
0.090 0.36696 0.09184
0.100 0.40676 0.10168
0.120 0.47488 0.11872
0.140 0.53252 0.13296
0.160 0.54460 0.13628
0.180 0.52464 0.13100
0.200 0.52144 0.13004
0.220 0.54492 0.13624
0.240 0.53748 0.13432
0.260 0.54424 0.13596
0.280 0.54220 0.13540
0.300 0.54016 0.13520
0.350 0.52584 0.13140
0.400 0.54940 0.13732
0.450 0.54016 0.13508
0.500 0.54052 0.13532
```

Verification and interpretation:

- All 20 rows completed with `data_rows=20`, `bad_rows=0`, `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0`.
- Throughput follows offered load at low rates and reaches a clear plateau around packet rate 0.14-0.16.
- Across the 12 points from rate 0.16 through 0.50, flit throughput mean/min/max are 0.537967/0.521440/0.549400 flit/cycle/node.
- Small plateau fluctuations are expected from the finite 1000-cycle window and randomized traffic.
- Vivado run completed in approximately 11 minutes 20 seconds at simulation time 464335 ns.
- Logs contain no `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL`.
- Generated `throughput_curve.png` contains all 20 points, is 1100 x 719 RGB PNG, and is 47974 bytes. Visual inspection confirmed the expected linear-growth-to-saturation-platform shape.
- `out.vcd` is 2605528334 bytes.
- This experiment inherits the existing traffic generator behavior that injects local source traffic through VC0; the internal four-VC fabric remains active for downstream VC allocation.

//Modify record completed four-VC fixed-window throughput sweep and saturation curve, Michael Tan, 20260715

## Active Task Started 2026-07-22: Four-VC Center-Hotspot Latency Sweep

Goal:

- Add a new independent 5x5, 4-flit, four-VC, queue-based latency sweep using hotspot traffic, without changing the existing uniform-random latency/throughput experiments or RTL.
- Use center node `(2,2)` as the single hotspot and `HOTSPOT_PROBABILITY_PERMILLE = 200` (`H = 0.2`).
- For every non-hotspot source, choose `(2,2)` with probability 0.2; otherwise choose a uniformly random destination excluding both itself and the hotspot, so the explicit hotspot probability remains exactly 0.2. The hotspot source itself always chooses another node.
- Retain the existing 20 injection-rate points and the random baseline's packet length, queue depth, warm-up, measurement, seed, and four-VC checks for direct comparison. Use a hotspot-specific 16000-cycle drain limit because the single hotspot's 4-flit local output needs more time than the random baseline to empty high-rate queues.
- Add an independent WSL/Linux Vivado runner and result directory, then verify the complete result table and Vivado logs.

Planned files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh`

Planned command:

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh
```

Expected result directory:

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot_sim/`

//Modify record start of four-VC center-hotspot latency sweep, Michael Tan, 20260722

## Four-VC Center-Hotspot Latency Sweep Completed 2026-07-22

Added files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sv`
- `scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh`
- `scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.py`

Traffic and measurement definition:

- No RTL source file was changed for this experiment.
- The single hotspot is center node `(2,2)` with `HOTSPOT_PROBABILITY_PERMILLE=200` (`H=0.2`).
- A non-hotspot source uses the hotspot branch with probability 0.2; the remaining random branch excludes both self and hotspot. The hotspot source selects a random non-self destination.
- The theoretical hotspot share across all generated packets is `0.2 * 24/25 = 0.192`; the result table records the realized hotspot packet count/share per rate.
- Configuration is otherwise the four-VC random baseline: 5x5 mesh, 4-flit packets, 20 injection-rate points, 200 warm-up cycles, 1000 measurement cycles, source queue depth 2048, and the same seed. The hotspot drain limit is 16000 cycles.

Commands:

```bash
bash scripts/simulation/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.sh
python3 scripts/simulation/plot_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot.py
```

Result directory:

`vivado_sim_wsl/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_hotspot_sim/`

Verified latency summary:

```text
packet_rate avg_latency_cycles
0.010 12.137
0.030 13.324
0.050 19.243
0.070 181.573
0.090 385.141
0.100 569.483
0.120 886.364
0.140 1057.084
0.160 1335.380
0.180 1585.764
0.200 1769.841
0.220 2114.957
0.240 2345.978
0.260 2401.783
0.280 2974.747
0.300 3159.688
0.350 3943.168
0.400 4332.622
0.450 5093.534
0.500 5672.454
```

Verification and interpretation:

- All 20 rows completed; every row has `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0`.
- Across 104102 measurement-generated packets, 19811 targeted the hotspot, giving a realized overall hotspot share of 0.190304 versus the theoretical 0.192.
- The hotspot curve is near the low-load baseline through rate 0.05, then rises sharply at 0.07; the random four-VC baseline did not show its comparable knee until roughly 0.12-0.16.
- The maximum actual drain was 10661 cycles at rate 0.50, within the 16000-cycle limit; all 12460 measurement packets at that rate arrived.
- Linux Vivado 2025.2 xsim finished at 1026495 ns in approximately 9 minutes 38 seconds. `xvlog.log`, `xelab.log`, and `xsim.log` contain no `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL`.
- Generated full and knee-zoom plots are 1100 x 719 RGB PNG files. The full plot uses rate 0.00-0.50 and latency 0-6000 cycles; the zoom uses rate 0.00-0.12 and latency 0-1000 cycles. Visual inspection confirmed that all points are inside the axes and the early hotspot knee is clear.

Key generated files:

- `injection_latency_results.txt`
- `injection_latency_curve_full.png`
- `injection_latency_curve_knee_zoom.png`
- `xvlog.log`, `xelab.log`, `xsim.log`
- `out.vcd`

//Modify record completed four-VC center-hotspot latency sweep and plots, Michael Tan, 20260722

## Active Task Started 2026-07-23: Packet ID and Flit Index Encoding

Goal:

- Modify only `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`; keep RTL and the other experiments unchanged.
- Encode both `packet_id` and `flit_index` in each BODY/TAIL `bt_pl`.
- Decode and validate both fields at the destination so a duplicated, missing, or reordered BODY/TAIL flit is reported with its packet ID and flit index.
- Preserve the HEAD destination fields and packet-level latency/statistics definition.

Planned verification:

- Compile and elaborate the modified top with Linux Vivado 2025.2 in a temporary directory, without overwriting the existing reusable sweep results.

//Modify record start of packet-id plus flit-index payload encoding task, Michael Tan, 20260723

## Packet ID and Flit Index Encoding Completed 2026-07-23

Changed files:

- `testbench/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc.sv`
- `AGENTS.md`
- `README.md`

Encoding and checking:

- For the current 4-flit packet, `FLIT_INDEX_SIZE = $clog2(PACKET_FLIT_NUM) = 2`.
- HEAD keeps its routing fields and 16-bit packet ID in `head_pl`.
- BODY/TAIL `bt_pl[1:0]` stores `flit_index`; the next 16 bits store `packet_id`; unused upper payload bits are zero.
- The transmitted indices are HEAD=0, BODY=1, BODY=2, TAIL=3.
- The monitor decodes BODY/TAIL packet ID and flit index separately and maintains `pkt_expected_flit_index` for every packet. Duplicate HEAD, invalid packet ID, destination mismatch, missing/duplicated/reordered BODY/TAIL, and unexpected labels now increment `error_seen` and issue `$error`.
- Static startup checks ensure the encoding fits `FLIT_DATA_SIZE` and the maximum possible packets generated in one rate fit the shared 16-bit packet-ID field.
- No RTL file or other testbench was changed by this task.

Verification:

- Linux Vivado 2025.2 `xvlog` and `xelab` passed in a temporary directory.
- A bounded xsim smoke run used elaboration overrides `WARMUP_CYCLES_PER_RATE=2`, `MEASURE_CYCLES_PER_RATE=8`, and `DRAIN_CYCLES_PER_RATE=1000`, while retaining all 20 injection-rate points.
- The sandbox run first encountered the documented `ERROR: unexpected exception when evaluating tcl command`; rerunning the same xsim snapshot with approved escalated execution completed successfully.
- Smoke result: `data_rows=20`, `bad_rows=0`; every row has `measure_injected == measure_received`, `measure_queue_full == 0`, and `error_count == 0`.
- Verification logs contain no `ERROR:`, `CRITICAL WARNING`, `$error`, `FAILED`, or `FATAL`; only the existing interface, timescale, and environment warnings remain.
- The existing full-sweep result directory under `vivado_sim_wsl/` was not modified or overwritten. A new full-length sweep was not run for this encoding-only change.

//Modify record completed packet-id plus flit-index payload encoding and bounded xsim verification, Michael Tan, 20260723

## Active Task Started 2026-07-24: Packet-Unit Throughput Curve

Goal:

- Keep the existing flit-throughput PNG unchanged.
- Reuse the verified `throughput_results.txt`; do not rerun Vivado.
- Extend the throughput plotting script to generate a second curve whose x-axis and y-axis are both normalized in `packet/cycle/node`.
- Save the new plot independently as `throughput_curve_packet.png`.

Planned command:

```bash
python3 scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

//Modify record start of packet-unit throughput curve task, Michael Tan, 20260724

## Packet-Unit Throughput Curve Completed 2026-07-24

Changed file:

- `scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py`

Generated file:

- `vivado_sim_wsl/tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc_sim/throughput_curve_packet.png`

Command:

```bash
python3 scripts/simulation/plot_tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc.py
```

Result:

- The existing `throughput_curve.png` remains the flit-unit curve.
- The new curve reads the recorded `throughput_packets_per_cycle_per_node_x1000000` column directly.
- Both axes of the new curve use `packet/cycle/node`; x spans 0.00-0.50 and y spans 0.00-0.16 with 0.02 tick spacing.
- All 20 verified result points are plotted. The delivered packet throughput is 0.00940 at offered rate 0.01, 0.13296 at 0.14, 0.13628 at 0.16, and 0.13532 at 0.50.
- Across offered rates 0.16-0.50, the packet-throughput plateau mean/min/max are 0.134463/0.130040/0.137320 packet/cycle/node.
- The PNG is 1100 x 719 RGB and 54251 bytes. Visual inspection confirmed correct labels, distinct y ticks, no clipping, low-load `throughput approximately equals offered packet rate`, and a clear saturation plateau.
- No RTL, testbench, result TXT, or Vivado simulation was changed or rerun.

//Modify record completed packet-unit throughput curve and verification, Michael Tan, 20260724
