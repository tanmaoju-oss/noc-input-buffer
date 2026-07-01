param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [switch]$NoClean
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "run_tb_mesh.ps1") `
    -VivadoRoot $VivadoRoot `
    -SimDir $SimDir `
    -TbFile "tb_mesh_injection_sweep_5x5.sv" `
    -Top "tb_mesh_injection_sweep_5x5" `
    -NoClean:$NoClean

# Modify add dedicated 5x5 injection sweep simulation entry, Michael Tan, 20260629
