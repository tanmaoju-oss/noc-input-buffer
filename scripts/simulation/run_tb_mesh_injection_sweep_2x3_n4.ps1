param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [switch]$NoClean
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "run_tb_mesh.ps1") `
    -VivadoRoot $VivadoRoot `
    -SimDir $SimDir `
    -TbFile "tb_mesh_injection_sweep_2x3_n4.sv" `
    -Top "tb_mesh_injection_sweep_2x3_n4" `
    -NoClean:$NoClean

# Modify add dedicated 2x3 four-flit packet sweep simulation entry, Michael Tan, 20260701
