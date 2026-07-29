param(
    [string]$VivadoRoot = "E:\Vivado\Vivado\2019.2",
    [string]$Part = "xcvu440-flga2892-2-e",
    [string]$OutputDir = "",
    [switch]$NoClean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "../..")).Path # Modify resolve repository root from scripts/synthesis directory, Michael Tan, 20260729
$SourceDir = Join-Path $RepoRoot "src"
$SynthesisRoot = Join-Path $RepoRoot "vivado_synthesis_windows"
$VivadoBat = Join-Path $VivadoRoot "bin\vivado.bat"
$Top = "mesh"

if (-not (Test-Path -LiteralPath $VivadoBat)) {
    throw "Windows Vivado batch executable was not found: $VivadoBat"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $SynthesisRoot "${Top}_synthesis"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

if (-not $NoClean) {
    Remove-Item -LiteralPath (Join-Path $OutputDir "mesh_synth.dcp") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $OutputDir "utilization.rpt") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $OutputDir "timing_summary.rpt") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $OutputDir "synthesis.log") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $OutputDir "run_mesh_synthesis.tcl") -Force -ErrorAction SilentlyContinue
}

$compileOrder = @(
    "noc.sv", "circular_buffer_Xiugai3.sv", "crossbar.sv", "input_block2crossbar.sv",
    "input_block2switch_allocator.sv", "input_block2vc_allocator.sv", "input_block_Xiugai2.sv",
    "input_buffer_src_circular_full.sv", "input_port_Xiugai2.sv", "mesh.sv", "node_link.sv",
    "rc_unit_Xiugai2.sv", "round_robin_arbiter.sv", "router.sv", "router2router.sv",
    "router_link.sv", "separable_input_first_allocator.sv", "switch_allocator2crossbar.sv",
    "switch_allocator_Xiugai1.sv", "vc_allocator.sv"
)

$tclLines = @("# Modify RTL-only mesh synthesis for VU440, Michael Tan, 20260729")
foreach ($name in $compileOrder) {
    $sourceFile = Join-Path $SourceDir $name
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "Expected RTL source is missing: $sourceFile"
    }
    $normalized = $sourceFile.Replace("\", "/") # Modify normalize Windows RTL path for generated Tcl, Michael Tan, 20260729
    $tclLines += "read_verilog -sv [list {$normalized}]"
}

$normalizedOutput = $OutputDir.Replace("\", "/") # Modify normalize Windows result path for generated Tcl, Michael Tan, 20260729
$tclLines += @(
    "synth_design -top $Top -part $Part",
    "report_utilization -file {$normalizedOutput/utilization.rpt}",
    "report_timing_summary -delay_type max -max_paths 10 -file {$normalizedOutput/timing_summary.rpt}",
    "write_checkpoint -force {$normalizedOutput/mesh_synth.dcp}",
    "exit"
)

$TclFile = Join-Path $OutputDir "run_mesh_synthesis.tcl"
Set-Content -LiteralPath $TclFile -Value $tclLines -Encoding ascii

Write-Host "Synthesizing $Top for $Part with Windows Vivado: $VivadoBat"
& $VivadoBat -mode batch -source $TclFile -log (Join-Path $OutputDir "synthesis.log") -journal (Join-Path $OutputDir "synthesis.jou")
if ($LASTEXITCODE -ne 0) {
    throw "Vivado synthesis failed with exit code $LASTEXITCODE. See $OutputDir\\synthesis.log"
}

Write-Host "Synthesis completed: $OutputDir"
