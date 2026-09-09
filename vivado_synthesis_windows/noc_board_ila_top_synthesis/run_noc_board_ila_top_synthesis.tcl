# Modify VU440 board ILA synthesis with real ila_0 IP, Michael Tan, 20260908
set argv [list {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/noc_board_ila_top_synthesis} {xcvu440-flga2892-2-e}]
source {E:/Codex-Project/NoC-XY/scripts/synthesis/create_noc_board_ila_ip.tcl}
set_property verilog_define {NOC_BOARD_ILA_VIVADO_IP} [current_fileset]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/noc.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/circular_buffer_Xiugai3.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/crossbar.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/input_block2crossbar.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/input_block2switch_allocator.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/input_block2vc_allocator.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/input_block_Xiugai2.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/input_buffer_src_circular_full.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/input_port_Xiugai2.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/mesh.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/node_link.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/rc_unit_Xiugai2.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/round_robin_arbiter.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/router.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/router2router.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/router_link.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/separable_input_first_allocator.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/switch_allocator2crossbar.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/switch_allocator_Xiugai1.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/vc_allocator.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/board_ila/noc_board_traffic_generator.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/board_ila/noc_board_latency_monitor.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/board_ila/noc_board_ila_debug.sv}]
read_verilog -sv [list {E:/Codex-Project/NoC-XY/src/board_ila/noc_board_ila_top.sv}]
synth_design -top noc_board_ila_top -part xcvu440-flga2892-2-e
report_utilization -file {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/noc_board_ila_top_synthesis/utilization.rpt}
report_timing_summary -delay_type max -max_paths 10 -file {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/noc_board_ila_top_synthesis/timing_summary.rpt}
report_debug_core -file {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/noc_board_ila_top_synthesis/debug_core.rpt}
write_checkpoint -force {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/noc_board_ila_top_synthesis/noc_board_ila_top_synth.dcp}
exit
