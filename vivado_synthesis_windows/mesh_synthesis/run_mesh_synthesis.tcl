# Modify RTL-only mesh synthesis for VU440, Michael Tan, 20260729
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
synth_design -top mesh -part xcvu440-flga2892-2-e
report_utilization -file {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/mesh_synthesis/utilization.rpt}
report_timing_summary -delay_type max -max_paths 10 -file {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/mesh_synthesis/timing_summary.rpt}
write_checkpoint -force {E:/Codex-Project/NoC-XY/vivado_synthesis_windows/mesh_synthesis/mesh_synth.dcp}
exit
