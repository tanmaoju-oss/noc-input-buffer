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
    "noc_board_traffic_generator.sv", "noc_board_latency_monitor.sv", "noc_board_ila_debug.sv", "noc_board_ila_top.sv"
)

$normalizedOutput = $OutputDir.Replace("\", "/")
$normalizedIlaIpTcl = $IlaIpTcl.Replace("\", "/")
$tclLines = @(
    "# Modify VU440 board ILA synthesis with real ila_0 IP, Michael Tan, 20260908",
    "set argv [list {$normalizedOutput} {$Part}]",
    "source {$normalizedIlaIpTcl}",
    "set_property verilog_define {NOC_BOARD_ILA_VIVADO_IP} [current_fileset]"
)
foreach ($name in $compileOrder) {
    $sourceFile = Join-Path $SourceDir $name
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "Expected RTL source is missing: $sourceFile"
    }
    $normalized = $sourceFile.Replace("\", "/")
    $tclLines += "read_verilog -sv [list {$normalized}]"
}
foreach ($name in $boardIlaCompileOrder) {
    $sourceFile = Join-Path $BoardIlaSourceDir $name
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "Expected board ILA RTL source is missing: $sourceFile"
    }
    $normalized = $sourceFile.Replace("\", "/")
    $tclLines += "read_verilog -sv [list {$normalized}]"
}

$tclLines += @(
    "synth_design -top $Top -part $Part",
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
