param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [string]$TbFile = "tb_mesh.sv",
    [string]$Top = "tb_mesh",
    [switch]$NoClean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..\..")).Path
$TestDir = Join-Path $RepoRoot "test"
$TbDir = Join-Path $TestDir "tb" # Modify to keep all testbench files under test/tb, Michael Tan, 20260617

. (Join-Path $ScriptDir "setup_vivado_env.ps1") -VivadoRoot $VivadoRoot
$XvlogBat = Join-Path $VivadoBin "xvlog.bat"
$XelabBat = Join-Path $VivadoBin "xelab.bat"
$XsimBat = Join-Path $VivadoBin "xsim.bat"

if (-not $SimDir) {
    $SimDir = Join-Path $ScriptDir "$($Top)_sim"
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
    # Modify tb source lookup after moving testbenches into test/tb, Michael Tan, 20260617
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
        $path = Join-Path $TestDir $name
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
