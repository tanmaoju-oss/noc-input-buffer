param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [switch]$NoClean
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "run_tb_mesh.ps1") `
    -VivadoRoot $VivadoRoot `
    -SimDir $SimDir `
    -TbFile "tb_mesh_injection_sweep_5x5_noxim_queue.sv" `
    -Top "tb_mesh_injection_sweep_5x5_noxim_queue" `
    -NoClean:$NoClean

# Modify add dedicated queue-based Noxim-style 5x5 sweep simulation entry, Michael Tan, 20260701
