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
- Initial local Git setup should use repository-local identity if global identity is not configured:

```powershell
git config user.name "Michael Tan"
git config user.email "tanma@local"
```

//Modify add current Git setup notes, Michael Tan, 20260626
