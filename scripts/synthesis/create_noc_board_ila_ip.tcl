# Create the Vivado 2019.2 ILA IP used by noc_board_ila_debug.
#Modify create fixed board ILA IP contract, Michael Tan, 20260908

if {[llength $argv] != 2} {
    puts stderr "Usage: vivado -mode batch -source create_noc_board_ila_ip.tcl -tclargs <output-directory> <part>"
    exit 1
}

set output_dir [file normalize [lindex $argv 0]]
set part [lindex $argv 1]
set ip_dir [file normalize [file join $output_dir ip]]
set ip_project_dir [file normalize [file join $output_dir ip_project]]
set ip_name ila_0
file mkdir $ip_dir

create_project -force noc_board_ila_ip_project $ip_project_dir -part $part
set_property target_language Verilog [current_project]

create_ip -name ila -vendor xilinx.com -library ip -module_name $ip_name -dir $ip_dir

set_property -dict [list \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_NUM_OF_PROBES {16} \
    CONFIG.C_PROBE0_WIDTH {2} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {32} \
    CONFIG.C_PROBE4_WIDTH {32} \
    CONFIG.C_PROBE5_WIDTH {32} \
    CONFIG.C_PROBE6_WIDTH {32} \
    CONFIG.C_PROBE7_WIDTH {32} \
    CONFIG.C_PROBE8_WIDTH {64} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {16} \
    CONFIG.C_PROBE11_WIDTH {5} \
    CONFIG.C_PROBE12_WIDTH {11} \
    CONFIG.C_PROBE13_WIDTH {32} \
    CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_PROBE15_WIDTH {32} \
] [get_ips $ip_name]

generate_target all [get_ips $ip_name]
export_ip_user_files -of_objects [get_ips $ip_name] -no_script -sync -force -quiet
puts "[get_property IP_FILE [get_ips $ip_name]]: generated fixed 16-probe board ILA IP"
