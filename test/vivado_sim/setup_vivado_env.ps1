param(
    [string]$VivadoRoot = ""
)

$ErrorActionPreference = "Stop"

function Resolve-VivadoRoot {
    param([string]$RequestedRoot)

    $candidates = @()
    if ($RequestedRoot) {
        $candidates += $RequestedRoot
    }

    if ($env:XILINX_VIVADO) {
        $candidates += $env:XILINX_VIVADO
    }

    $candidates += @(
        "E:\Vivado\Vivado\2019.2",
        "C:\Xilinx\Vivado\2019.2",
        "C:\Program Files\Xilinx\Vivado\2019.2"
    )

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }

        $settings = Join-Path $candidate "settings64.bat"
        if (Test-Path -LiteralPath $settings) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Vivado settings64.bat was not found. Pass -VivadoRoot or set XILINX_VIVADO."
}

$ResolvedVivadoRoot = Resolve-VivadoRoot -RequestedRoot $VivadoRoot
$SettingsBat = Join-Path $ResolvedVivadoRoot "settings64.bat"
$VivadoBin = Join-Path $ResolvedVivadoRoot "bin"

$envDump = cmd.exe /c "`"$SettingsBat`" && set"
foreach ($line in $envDump) {
    if ($line -match "^([^=]+)=(.*)$") {
        Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
    }
}

$requiredTools = @("vivado", "xvlog", "xelab", "xsim")
foreach ($tool in $requiredTools) {
    $toolBat = Join-Path $VivadoBin "$tool.bat"
    if (-not (Test-Path -LiteralPath $toolBat)) {
        throw "Vivado tool '$tool' is not available after loading $SettingsBat."
    }
}

Write-Host "Vivado environment loaded from $ResolvedVivadoRoot"
Write-Host "xvlog: $(Join-Path $VivadoBin 'xvlog.bat')"
