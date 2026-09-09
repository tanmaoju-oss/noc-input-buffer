param(
    [string]$VivadoRoot = "E:\Vivado\Vivado\2019.2",
    [string]$Part = "xcvu440-flga2892-2-e",
    [string]$OutputDir = "",
    [switch]$NoClean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "../..")).Path # Modify resolve repository root from scripts/synthesis directory, Michael Tan, 20260908
$SourceDir = Join-Path $RepoRoot "src"
$BoardIlaSourceDir = Join-Path $SourceDir "board_ila"
$SynthesisRoot = Join-Path $RepoRoot "vivado_synthesis_windows"
$VivadoBat = Join-Path $VivadoRoot "bin\vivado.bat"
$IlaIpTcl = Join-Path $ScriptDir "create_noc_board_ila_ip.tcl"
$Top = "noc_board_ila_top"

if (-not (Test-Path -LiteralPath $VivadoBat)) {
    throw "Windows Vivado batch executable was not found: $VivadoBat"
}
if (-not (Test-Path -LiteralPath $IlaIpTcl)) {
    throw "ILA IP creation Tcl is missing: $IlaIpTcl"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $SynthesisRoot "${Top}_synthesis"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

if (-not $NoClean) {
    @("${Top}_synth.dcp", "utilization.rpt", "timing_summary.rpt", "debug_core.rpt", "synthesis.log", "synthesis.jou", "run_${Top}_synthesis.tcl") | ForEach-Object {
        Remove-Item -LiteralPath (Join-Path $OutputDir $_) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath (Join-Path $OutputDir "ip") -Recurse -Force -ErrorAction SilentlyContinue # Modify clean only generated ILA IP artifacts, Michael Tan, 20260908
    Remove-Item -LiteralPath (Join-Path $OutputDir "ip_project") -Recurse -Force -ErrorAction SilentlyContinue # Modify clean only generated temporary ILA project, Michael Tan, 20260908
    Remove-Item -LiteralPath (Join-Path $OutputDir "synthesis_project") -Recurse -Force -ErrorAction SilentlyContinue # Modify clean the generated project-run workspace before its next OOC IP and top synthesis, Michael Tan, 20260909
}

$compileOrder = @(
    "noc.sv", "circular_buffer_Xiugai3.sv", "crossbar.sv", "input_block2crossbar.sv",
    "input_block2switch_allocator.sv", "input_block2vc_allocator.sv", "input_block_Xiugai2.sv",
    "input_buffer_src_circular_full.sv", "input_port_Xiugai2.sv", "mesh.sv", "node_link.sv",
    "rc_unit_Xiugai2.sv", "round_robin_arbiter.sv", "router.sv", "router2router.sv",
    "router_link.sv", "separable_input_first_allocator.sv", "switch_allocator2crossbar.sv",
    "switch_allocator_Xiugai1.sv", "vc_allocator.sv"
)
$boardIlaCompileOrder = @(
    "noc_board_traffic_generator.sv", "noc_board_latency_tracker.sv", "noc_board_latency_monitor.sv", "noc_board_ila_debug.sv", "noc_board_ila_top.sv"
)

$normalizedOutput = $OutputDir.Replace("\", "/")
$normalizedIlaIpTcl = $IlaIpTcl.Replace("\", "/")
$tclLines = @(
    "# Modify VU440 board ILA synthesis with real ila_0 IP, Michael Tan, 20260908",
    "set argv [list {$normalizedOutput} {$Part}]",
    "source {$normalizedIlaIpTcl}",
    "close_project", # Modify leave the temporary IP-generation project before opening the project-run top synthesis workspace, Michael Tan, 20260909
    "create_project -force noc_board_ila_synthesis_project {$normalizedOutput/synthesis_project} -part $Part", # Modify create a writable project-run workspace that manages ILA OOC synthesis, Michael Tan, 20260909
    "set_property target_language Verilog [current_project]",
    "read_ip [list {$normalizedOutput/ip/ila_0/ila_0.xci}]", # Modify add the generated ILA XCI to the synthesis fileset before elaborating its wrapper, Michael Tan, 20260909
    "generate_target all [get_ips ila_0]", # Modify prepare ILA output products for the project-managed OOC run, Michael Tan, 20260909
    "set_property verilog_define {NOC_BOARD_ILA_VIVADO_IP} [current_fileset]"
)
foreach ($name in $compileOrder) {
    $sourceFile = Join-Path $SourceDir $name
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "Expected RTL source is missing: $sourceFile"
    }
    $normalized = $sourceFile.Replace("\", "/")
    $tclLines += "add_files -norecurse [list {$normalized}]" # Modify add RTL to the Vivado project so synth_1 can schedule IP OOC dependencies, Michael Tan, 20260909
}
foreach ($name in $boardIlaCompileOrder) {
    $sourceFile = Join-Path $BoardIlaSourceDir $name
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "Expected board ILA RTL source is missing: $sourceFile"
    }
    $normalized = $sourceFile.Replace("\", "/")
    $tclLines += "add_files -norecurse [list {$normalized}]" # Modify add board ILA RTL to the Vivado project-run synthesis fileset, Michael Tan, 20260909
}

$tclLines += @(
    "set_property top $Top [current_fileset]",
    "update_compile_order -fileset sources_1",
    "launch_runs synth_1 -jobs 4", # Modify let Vivado schedule ila_0_synth_1 and link its OOC checkpoint before top synthesis, Michael Tan, 20260909
    "wait_on_run synth_1",
    "open_run synth_1",
    "report_utilization -file {$normalizedOutput/utilization.rpt}",
    "report_timing_summary -delay_type max -max_paths 10 -file {$normalizedOutput/timing_summary.rpt}",
    "report_debug_core -file {$normalizedOutput/debug_core.rpt}",
    "write_checkpoint -force {$normalizedOutput/${Top}_synth.dcp}",
    "exit"
)

$TclFile = Join-Path $OutputDir "run_${Top}_synthesis.tcl"
Set-Content -LiteralPath $TclFile -Value $tclLines -Encoding ascii

Write-Host "Synthesizing $Top with real ila_0 IP for $Part using Windows Vivado: $VivadoBat"
& $VivadoBat -mode batch -source $TclFile -log (Join-Path $OutputDir "synthesis.log") -journal (Join-Path $OutputDir "synthesis.jou")
if ($LASTEXITCODE -ne 0) {
    throw "Vivado synthesis failed with exit code $LASTEXITCODE. See $OutputDir\synthesis.log"
}

Write-Host "Synthesis completed: $OutputDir"
