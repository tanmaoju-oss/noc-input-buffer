param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [switch]$NoClean
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "run_tb_mesh.ps1") `
    -VivadoRoot $VivadoRoot `
    -SimDir $SimDir `
    -TbFile "tb_mesh_injection_sweep.sv" `
    -Top "tb_mesh_injection_sweep" `
    -NoClean:$NoClean

# Modify add dedicated entry matching tb_mesh_injection_sweep and its result directory, Michael Tan, 20260713
