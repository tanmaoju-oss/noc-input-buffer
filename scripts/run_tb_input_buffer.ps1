param(
    [string]$VivadoRoot = "",
    [string]$SimDir = "",
    [switch]$NoClean
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "run_tb_mesh.ps1") `
    -VivadoRoot $VivadoRoot `
    -SimDir $SimDir `
    -TbFile "tb_input_buffer.sv" `
    -Top "tb_input_buffer" `
    -NoClean:$NoClean

# Modify add dedicated entry matching tb_input_buffer and its result directory, Michael Tan, 20260713
