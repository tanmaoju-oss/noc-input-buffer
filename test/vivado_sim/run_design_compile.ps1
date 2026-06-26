param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [switch]$NoClean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..\..")).Path
$TestDir = Join-Path $RepoRoot "test"

. (Join-Path $ScriptDir "setup_vivado_env.ps1") -VivadoRoot $VivadoRoot
$XvlogBat = Join-Path $VivadoBin "xvlog.bat"

if (-not $SimDir) {
    $SimDir = Join-Path $ScriptDir "design_compile"
}

New-Item -ItemType Directory -Path $SimDir -Force | Out-Null
$SimDir = (Resolve-Path -LiteralPath $SimDir).Path

if (-not $NoClean) {
    $cleanItems = @(
        "xvlog.log",
        "xvlog.pb",
        "design_only_vlog.prj"
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
    "vc_allocator.sv"
)

$designFiles = @()
foreach ($name in $compileOrder) {
    $path = Join-Path $TestDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Expected design file is missing: $path"
    }

    $designFiles += (Resolve-Path -LiteralPath $path).Path
}

$unexpectedDesignFiles = Get-ChildItem -LiteralPath $TestDir -File -Filter "*.sv" |
    Where-Object { $_.Name -notmatch "^tb.*\.sv$" -and $compileOrder -notcontains $_.Name }

if ($unexpectedDesignFiles.Count -gt 0) {
    $names = ($unexpectedDesignFiles | Select-Object -ExpandProperty Name) -join ", "
    throw "Found design files that are not in the compile order: $names"
}

$projectFile = Join-Path $SimDir "design_only_vlog.prj"
$projectLines = @(
    "# compile SystemVerilog design source files from test, excluding tb*.sv",
    "sv xil_defaultlib  \"
)

foreach ($file in $designFiles) {
    $normalized = $file.Replace("\", "/")
    $projectLines += "`"$normalized`" \"
}

$projectLines += @(
    "",
    "# Do not sort compile order",
    "nosort"
)

Set-Content -LiteralPath $projectFile -Value $projectLines -Encoding ASCII

Push-Location $SimDir
try {
    Write-Host "Compiling $($designFiles.Count) design files from $TestDir"
    Write-Host "Project file: $projectFile"
    & $XvlogBat --incr --relax -prj "design_only_vlog.prj" -log "xvlog.log"
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE. See $SimDir\xvlog.log"
    }
}
finally {
    Pop-Location
}

Write-Host "Design compile completed successfully."
Write-Host "Log: $SimDir\xvlog.log"
