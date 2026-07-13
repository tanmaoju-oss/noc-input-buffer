param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [string]$TbFile = "tb_mesh.sv",
    [string]$Top = "tb_mesh",
    [switch]$NoClean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path # Modify resolve repository root from top-level scripts directory, Michael Tan, 20260713
$SourceDir = Join-Path $RepoRoot "src" # Modify use top-level RTL source directory, Michael Tan, 20260713
$TbDir = Join-Path $RepoRoot "testbench" # Modify use top-level testbench directory, Michael Tan, 20260713
$SimRoot = Join-Path $RepoRoot "vivado_sim_windows" # Modify route PowerShell/Windows Vivado results to the Windows-specific root, Michael Tan, 20260713

. (Join-Path $ScriptDir "setup_vivado_env.ps1") -VivadoRoot $VivadoRoot
$XvlogBat = Join-Path $VivadoBin "xvlog.bat"
$XelabBat = Join-Path $VivadoBin "xelab.bat"
$XsimBat = Join-Path $VivadoBin "xsim.bat"

if (-not $SimDir) {
    $SimDir = Join-Path $SimRoot "$($Top)_sim" # Modify pair each top module with its own result directory, Michael Tan, 20260713
}

New-Item -ItemType Directory -Path $SimDir -Force | Out-Null
$SimDir = (Resolve-Path -LiteralPath $SimDir).Path

if (-not $NoClean) {
    $cleanItems = @(
        "xvlog.log",
        "xvlog.pb",
        "xelab.log",
        "xelab.pb",
        "xsim.log",
        "xsim.jou",
        "$($Top)_vlog.prj",
        "$($Top).tcl",
        "out.vcd",
        "$($Top)_sim.wdb"
    )

    foreach ($item in $cleanItems) {
        $target = Join-Path $SimDir $item
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force
        }
    }

    $workDir = Join-Path $SimDir "xsim.dir"
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}

$compileOrder = @(
    "noc.sv",
    "circular_buffer_Xiugai3.sv",
    "crossbar.sv",
    "input_block2crossbar.sv",
    "input_block2switch_allocator.sv",
    "input_block2vc_allocator.sv",
    "input_block_Xiugai2.sv",
    "input_buffer_src_circular_full.sv",
    "input_port_Xiugai2.sv",
    "mesh.sv",
    "node_link.sv",
    "rc_unit_Xiugai2.sv",
    "round_robin_arbiter.sv",
    "router.sv",
    "router2router.sv",
    "router_link.sv",
    "separable_input_first_allocator.sv",
    "switch_allocator2crossbar.sv",
    "switch_allocator_Xiugai1.sv",
    "vc_allocator.sv",
    $TbFile
)

$sourceFiles = @()
foreach ($name in $compileOrder) {
    # Modify resolve tb from top-level testbench and RTL from top-level src, Michael Tan, 20260713
    if ($name -eq $TbFile) {
        if ([System.IO.Path]::IsPathRooted($name)) {
            $path = $name
        }
        elseif ($name -match "[\\/]" ) {
            $path = Join-Path $RepoRoot $name
        }
        else {
            $path = Join-Path $TbDir $name
        }
    }
    else {
        $path = Join-Path $SourceDir $name # Modify compile design files only from src, Michael Tan, 20260713
    }

    if (-not (Test-Path -LiteralPath $path)) {
        throw "Expected source file is missing: $path"
    }

    $sourceFiles += (Resolve-Path -LiteralPath $path).Path
}

$projectFile = Join-Path $SimDir "$($Top)_vlog.prj"
$projectLines = @(
    "# compile SystemVerilog design and $Top source files",
    "sv xil_defaultlib  \"
)

foreach ($file in $sourceFiles) {
    $normalized = $file.Replace("\", "/")
    $projectLines += "`"$normalized`" \"
}

$projectLines += @(
    "",
    "# Do not sort compile order",
    "nosort"
)

Set-Content -LiteralPath $projectFile -Value $projectLines -Encoding ASCII
Set-Content -LiteralPath (Join-Path $SimDir "$($Top).tcl") -Value "run all" -Encoding ASCII

Push-Location $SimDir
try {
    Write-Host "Compiling $Top simulation sources."
    & $XvlogBat --incr --relax -prj "$($Top)_vlog.prj" -log "xvlog.log"
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE. See $SimDir\xvlog.log"
    }

    Write-Host "Elaborating $Top."
    & $XelabBat --incr --debug typical --relax --mt 2 -L xil_defaultlib --snapshot "$($Top)_sim" "xil_defaultlib.$Top" -log "xelab.log"
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE. See $SimDir\xelab.log"
    }

    Write-Host "Running $Top simulation."
    & $XsimBat "$($Top)_sim" -tclbatch "$($Top).tcl" -log "xsim.log"
    if ($LASTEXITCODE -ne 0) {
        throw "xsim failed with exit code $LASTEXITCODE. See $SimDir\xsim.log"
    }
}
finally {
    Pop-Location
}

Write-Host "$Top simulation completed."
Write-Host "Log: $SimDir\xsim.log"
Write-Host "VCD: $SimDir\out.vcd"
