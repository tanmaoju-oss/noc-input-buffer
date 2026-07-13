# Codex Session Memory

//Modify rewrite this file as Codex-first session memory, Michael Tan, 20260626

## Read This First

This file is the persistent memory for the NoC/Vivado work in this repository.

When a new Codex session starts, read this file before making changes or running simulations.

Repository path:

`C:\Users\tanma\Desktop\cc-work\Aware\6.input_buffer`

## User Rules

- Reply mainly in concise Chinese.
- Do not modify source files when the user asks only for analysis or says not to modify yet.
- Before starting any code feature change, testbench creation, or Vivado simulation task, update both `Remember.md` and `项目说明.md` when the task changes project state or produces reusable results.//Modify add mandatory memory-sync rule before future code/tb/simulation work, Michael Tan, 20260626
- After finishing any code feature change, testbench creation, or Vivado simulation task, update both `Remember.md` and `项目说明.md` with changed files, run commands, result paths, and important simulation results.//Modify add mandatory post-task documentation rule, Michael Tan, 20260626
- For every new simulation feature, create a new tb file and a corresponding simulation entry/result directory. Do not directly repurpose an existing tb such as the 2x3 baseline sweep.//Modify add new-tb-per-feature rule, Michael Tan, 20260629
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

## Current Goal

The current main goal is to build a Noxim-like NoC performance test:

- x-axis: injection rate
- y-axis: average packet latency
- injection rate sweep: 0.1 to 0.5, step 0.1
- output injection rate and latency to a txt file
- later work may expand the test from 2x3 to 5x5 mesh

## Current Important Files

- `test/noc.sv`: global NoC parameters and flit type definitions.
- `test/mesh.sv`: parameterized mesh generation.
- `test/input_port_Xiugai2.sv`: contains the VC/crossbar selection fix.
- `test/circular_buffer_Xiugai3.sv`: contains the Vivado declaration-order fix.
- `test/tb`: all testbench files.
- `test/tb/tb_mesh_injection_sweep.sv`: current injection-rate sweep testbench.
- `test/vivado_sim/run_tb_mesh.ps1`: main Vivado command-line simulation script.
- `Remember.md`: Codex-facing memory file.
- `项目说明.md`: Chinese user-facing project summary.

## Documentation Sync Rule

For every future task that changes code, creates/changes a tb, runs a new meaningful Vivado simulation, or produces a result file that should be reused later:

1. Update `Remember.md` for Codex/session handoff.
2. Update `项目说明.md` for the user's Chinese project record.
3. Record the date, changed files, simulation command, output paths, and key pass/fail or latency results.
4. Keep the documentation concise; only record reusable state, not temporary exploration noise.

//Modify add explicit documentation synchronization workflow, Michael Tan, 20260626

## Completed Work

1. Modified input buffer related logic so continuous packet injection can work.
2. Verified continuous packets with Vivado simulation.
3. Fixed a crossbar output bug in `input_port_Xiugai2.sv`.
4. Moved all testbench files into `test/tb`.
5. Created Vivado simulation scripts under `test/vivado_sim`.
6. Created `tb_mesh_injection_sweep.sv` to sweep injection rates from 0.1 to 0.5 and write txt results.
7. Verified eight consecutive packets could all be received without packet loss.

## Important Bug Fixes

### circular_buffer declaration-order fix

File:

`test/circular_buffer_Xiugai3.sv`

Fix:

- Moved `assign first_flit_o = memory[read_ptr]` after `read_ptr` declaration.
- Reason: Vivado `xvlog` required `read_ptr` to be declared before use.

### input_port VC selection fix

File:

`test/input_port_Xiugai2.sv`

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

`test/tb`

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
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh.ps1 -TbFile <tb_file>.sv -Top <top_module>
```

Injection sweep command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh.ps1 -TbFile tb_mesh_injection_sweep.sv -Top tb_mesh_injection_sweep
```

Injection sweep output directory:

`test/vivado_sim/tb_mesh_injection_sweep_sim`

Important output files:

- `xsim.log`
- `out.vcd`
- `injection_latency_results.txt`

## Latest Injection Sweep Result

Result file:

`test/vivado_sim/tb_mesh_injection_sweep_sim/injection_latency_results.txt`

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

`test/tb/tb_mesh_injection_sweep.sv`

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

`test/noc.sv` currently has:

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

- `test/mesh.sv` default parameters are still 2x3.
- Most tb files still default to 2x3.
- `test/tb/tb_mesh.sv` hard-codes `.MESH_SIZE_X(2)` and `.MESH_SIZE_Y(3)`.
- For the performance curve, first update `test/tb/tb_mesh_injection_sweep.sv`.

Recommended first 5x5 change later:

```systemverilog
parameter MESH_SIZE_X = 5,
parameter MESH_SIZE_Y = 5,
```

in `test/tb/tb_mesh_injection_sweep.sv`, then rerun Vivado simulation.

## Active Task Started 2026-06-29

Goal:

- Continue the Noxim-like injection-rate/average-latency sweep by creating a separate 5x5 sweep tb and keeping the original 2x3 sweep tb unchanged.
- First target files: `test/tb/tb_mesh_injection_sweep_5x5.sv` and `test/vivado_sim/run_tb_mesh_injection_sweep_5x5.ps1`.
- Planned simulation command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5.ps1
```

Expected reusable output:

- `test/vivado_sim/tb_mesh_injection_sweep_5x5_sim/injection_latency_results.txt`

//Modify record start of 5x5 injection sweep continuation task, Michael Tan, 20260629

## Latest 5x5 Injection Sweep Result

Date: 2026-06-29

Changed files:

- `test/tb/tb_mesh_injection_sweep_5x5.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5.ps1`

Change:

- Kept the original `test/tb/tb_mesh_injection_sweep.sv` as the 2x3 baseline.
- Added a separate 5x5 sweep tb with top module `tb_mesh_injection_sweep_5x5`.
- Added a dedicated 5x5 simulation script so the run produces an independent `tb_mesh_injection_sweep_5x5_sim` directory.

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5.ps1
```

Output files:

- `test/vivado_sim/tb_mesh_injection_sweep_5x5_sim/xsim.log`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_sim/out.vcd`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_sim/injection_latency_results.txt`

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

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_style.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_style.ps1`

Planned command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

//Modify record start of Noxim-style 5x5 sweep task, Michael Tan, 20260629

## Latest Noxim-Style 5x5 Injection Sweep Result

Date: 2026-06-29

Added files:

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_style.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_style.ps1`

Key behavior:

- Keeps existing 2x3 and regular 5x5 sweep tb files unchanged.
- Uses `WARMUP_CYCLES_PER_RATE = 200`, `MEASURE_CYCLES_PER_RATE = 1000`, and `DRAIN_CYCLES_PER_RATE = 3000`.
- Warm-up packets create network load but do not contribute to average latency.
- Only packets injected during the measurement window contribute to `measure_injected`, `measure_received`, and average latency.
- Drain stops new packet creation and waits for measured packets to arrive.

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_style.ps1
```

Output files:

- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_style_sim/xsim.log`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_style_sim/out.vcd`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_style_sim/injection_latency_results.txt`

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

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1`

Planned command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
```

//Modify record start of queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260701

## Latest Queue-Based Noxim-Style 5x5 Sweep Result

Date: 2026-07-01

Added files:

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1`

Generated files:

- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_sim/injection_latency_results.txt`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_sim/injection_latency_curve.png`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_sim/xsim.log`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_sim/out.vcd`

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
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_queue.ps1
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

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1`

Planned rates:

- 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.20, 0.30, 0.40, 0.50

//Modify record start of low-rate queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260709

## Latest Low-Rate Queue-Based Noxim-Style 5x5 Sweep Result

Date: 2026-07-09

Added files:

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1`

Generated files:

- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_results.txt`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_curve_full.png`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/injection_latency_curve_lowrate_zoom.png`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/xsim.log`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_lowrate_sim/out.vcd`

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_queue_lowrate.ps1
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

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue_knee.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1`

Planned rates:

- 0.01, 0.03, 0.05, 0.07, 0.09, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20, 0.22, 0.24, 0.26, 0.28, 0.30, 0.35, 0.40, 0.45, 0.50

//Modify record start of knee-rate queue-based Noxim-style 5x5 sweep task, Michael Tan, 20260709

## Latest Knee-Rate Queue-Based Noxim-Style 5x5 Sweep Result

Date: 2026-07-09

Added files:

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue_knee.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1`

Generated files:

- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_results.txt`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_curve_full.png`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/injection_latency_curve_knee_zoom.png`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/xsim.log`
- `test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_knee_sim/out.vcd`

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_queue_knee.ps1
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

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1`

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

- `test/tb/tb_mesh_injection_sweep_2x3_n4.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_2x3_n4.ps1`

Planned command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_2x3_n4.ps1
```

Expected reusable output:

- `test/vivado_sim/tb_mesh_injection_sweep_2x3_n4_sim/injection_latency_results.txt`

//Modify record start of 2x3 four-flit packet sweep task, Michael Tan, 20260701

## Latest 2x3 Four-Flit Packet Injection Sweep Result

Date: 2026-07-01

Added files:

- `test/tb/tb_mesh_injection_sweep_2x3_n4.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_2x3_n4.ps1`

Key behavior:

- Keeps the original 2x3 `test/tb/tb_mesh_injection_sweep.sv` unchanged as the 2-flit baseline.
- Adds configurable packet length through `PACKET_FLIT_NUM`.
- Current setting is `PACKET_FLIT_NUM = 4`, so each packet is HEAD + BODY + BODY + TAIL.
- BODY flits use `BODY` as `flit_label` and carry the packet id in `bt_pl`.
- The monitor accepts and counts BODY flits, checks that exactly `PACKET_FLIT_NUM - 2` BODY flits arrive before TAIL, and still counts packet latency on TAIL arrival.

Vivado command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_2x3_n4.ps1
```

Output files:

- `test/vivado_sim/tb_mesh_injection_sweep_2x3_n4_sim/xsim.log`
- `test/vivado_sim/tb_mesh_injection_sweep_2x3_n4_sim/out.vcd`
- `test/vivado_sim/tb_mesh_injection_sweep_2x3_n4_sim/injection_latency_results.txt`

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
- `Remember.md` and `项目说明.md` should be kept locally only and removed from GitHub remote tracking.//Modify record local-only documentation policy, Michael Tan, 20260626
- Initial local Git setup should use repository-local identity if global identity is not configured:

```powershell
git config user.name "Michael Tan"
git config user.email "tanma@local"
```

//Modify add current Git setup notes, Michael Tan, 20260626

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
   - Focus is the SystemVerilog design logic files under `test/`, not the testbench itself.

Important wording direction:

- First indicator combines the previous first and second code-oriented items.
- Second indicator carries the simulation verification content.
- Third indicator is newly written for design logic optimization based on simulation feedback.
- Avoid saying "20 sv files" in the MBO; describe it as `test目录下NoC设计逻辑相关SystemVerilog代码`.

//Modify record latest MBO v0.8 structure: test code optimization, simulation verification, design logic optimization, Michael Tan, 20260629

## Active Task Completed 2026-07-09: 4-Flit Queue-Based 5x5 Knee Sweep

User request:

- Based on the previous queue-based knee version, create a packet=4-flit version and inspect the final latency curve.
- Keep old tb files unchanged; create a new tb and a new simulation entry.

New files:

- `test/tb/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.sv`
- `test/vivado_sim/run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1`

Key tb behavior:

- `PACKET_FLIT_NUM = 4`
- Packet format is `HEAD + BODY + BODY + TAIL`.
- Injection rate is still packet injection probability per node per cycle.
- Average latency is packet latency, measured from packet generation/source-queue entry to TAIL arrival.
- BODY flits are checked for destination correctness but are not counted as received packets.

Simulation command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test\vivado_sim\run_tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit.ps1
```

Result directory:

`test/vivado_sim/tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_sim`

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
