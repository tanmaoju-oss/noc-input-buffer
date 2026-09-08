//Modify add a stable board-level ILA probe wrapper with a WSL no-op verification branch, Michael Tan, 20260908
module noc_board_ila_debug (
    input logic clk,
    input logic [1:0] traffic_window_phase_i,
    input logic traffic_generate_enable_i,
    input logic monitor_measurement_enable_i,
    input logic [31:0] monitor_packets_enqueued_i,
    input logic [31:0] monitor_queue_full_i,
    input logic [31:0] monitor_tails_received_i,
    input logic [31:0] monitor_unmatched_tails_i,
    input logic [31:0] monitor_timestamp_overwrites_i,
    input logic [63:0] monitor_total_latency_cycles_i,
    input logic monitor_debug_tail_event_i,
    input logic [15:0] monitor_debug_tail_packet_id_i,
    input logic [4:0] monitor_debug_tail_source_id_i,
    input logic [10:0] monitor_debug_tail_sequence_i,
    input logic [31:0] monitor_debug_enqueue_cycle_i,
    input logic [31:0] monitor_debug_current_cycle_i,
    input logic [31:0] monitor_debug_last_packet_latency_i
);

`ifdef NOC_BOARD_ILA_VIVADO_IP
    //Modify bind the fixed probe contract to the Windows Vivado 2019.2 generated ila_0 IP, Michael Tan, 20260908
    ila_0 board_ila_core (
        .clk(clk),
        .probe0(traffic_window_phase_i),
        .probe1(traffic_generate_enable_i),
        .probe2(monitor_measurement_enable_i),
        .probe3(monitor_packets_enqueued_i),
        .probe4(monitor_queue_full_i),
        .probe5(monitor_tails_received_i),
        .probe6(monitor_unmatched_tails_i),
        .probe7(monitor_timestamp_overwrites_i),
        .probe8(monitor_total_latency_cycles_i),
        .probe9(monitor_debug_tail_event_i),
        .probe10(monitor_debug_tail_packet_id_i),
        .probe11(monitor_debug_tail_source_id_i),
        .probe12(monitor_debug_tail_sequence_i),
        .probe13(monitor_debug_enqueue_cycle_i),
        .probe14(monitor_debug_current_cycle_i),
        .probe15(monitor_debug_last_packet_latency_i)
    );
`else
    //Modify retain all probe ports as WSL-visible no-op inputs until Windows Vivado generates ila_0, Michael Tan, 20260908
    logic unused_probe_activity;
    always_comb begin
        unused_probe_activity = clk ^ traffic_window_phase_i[0] ^ traffic_window_phase_i[1] ^
                                traffic_generate_enable_i ^ monitor_measurement_enable_i ^
                                monitor_packets_enqueued_i[0] ^ monitor_queue_full_i[0] ^
                                monitor_tails_received_i[0] ^ monitor_unmatched_tails_i[0] ^
                                monitor_timestamp_overwrites_i[0] ^ monitor_total_latency_cycles_i[0] ^
                                monitor_debug_tail_event_i ^ monitor_debug_tail_packet_id_i[0] ^
                                monitor_debug_tail_source_id_i[0] ^ monitor_debug_tail_sequence_i[0] ^
                                monitor_debug_enqueue_cycle_i[0] ^ monitor_debug_current_cycle_i[0] ^
                                monitor_debug_last_packet_latency_i[0];
    end
`endif

endmodule
