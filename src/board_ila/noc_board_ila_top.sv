import noc_params::*;

//Modify add DDR-free board-level NoC top shell, Michael Tan, 20260804
module noc_board_ila_top (
    input logic l_pad_clk_p,
    input logic l_pad_clk_n,
    input logic l_pad_rst_b
);

    //Modify receive the confirmed 100 MHz differential board clock, Michael Tan, 20260804
    logic noc_clk_ibuf;
    logic noc_clk;
    logic [1:0] reset_sync;
    logic noc_rst;

    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("FALSE")
    ) noc_clock_ibufds (
        .I(l_pad_clk_p),
        .IB(l_pad_clk_n),
        .O(noc_clk_ibuf)
    );

    BUFG noc_clock_bufg (
        .I(noc_clk_ibuf),
        .O(noc_clk)
    );

    //Modify synchronize the active-low board reset into the NoC clock domain, Michael Tan, 20260804
    always_ff @(posedge noc_clk or negedge l_pad_rst_b) begin
        if (!l_pad_rst_b) begin
            reset_sync <= 2'b00;
        end else begin
            reset_sync <= {reset_sync[0], 1'b1};
        end
    end

    assign noc_rst = ~reset_sync[1];

    //Modify provide the 5x5 mesh local interfaces for later traffic-generator integration, Michael Tan, 20260804
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_data_i;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_valid_i;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] local_on_off_i;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] local_allocatable_i;
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_data_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_valid_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] local_on_off_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] local_allocatable_o;
    logic [VC_NUM-1:0] mesh_error [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0];
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_enqueued;
    logic [HEAD_PAYLOAD_SIZE-1:0] enqueued_packet_id [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [31:0] monitor_packets_enqueued;
    logic [31:0] monitor_tails_received;
    logic [31:0] monitor_unmatched_tails;
    logic [31:0] monitor_timestamp_overwrites;
    logic [63:0] monitor_total_latency_cycles;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic monitor_debug_tail_event;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [HEAD_PAYLOAD_SIZE-1:0] monitor_debug_tail_packet_id;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [$clog2(MESH_SIZE_X * MESH_SIZE_Y)-1:0] monitor_debug_tail_source_id;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [HEAD_PAYLOAD_SIZE-$clog2(MESH_SIZE_X * MESH_SIZE_Y)-1:0] monitor_debug_tail_sequence;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [31:0] monitor_debug_enqueue_cycle;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [31:0] monitor_debug_current_cycle;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) logic [31:0] monitor_debug_last_packet_latency;//Modify retain per-TAIL latency operands/results at board-top scope for WDB and later ILA, Michael Tan, 20260820

    //Modify keep the downstream local sinks always available during traffic-generator bring-up, Michael Tan, 20260805
    assign local_on_off_i = '1;
    assign local_allocatable_i = '1;

    //Modify drive every 5x5 local input with queued four-flit LFSR traffic at the board-workload rate, Michael Tan, 20260805
    noc_board_traffic_generator #(
        .MESH_SIZE_X(MESH_SIZE_X),
        .MESH_SIZE_Y(MESH_SIZE_Y),
        .SOURCE_QUEUE_DEPTH(64),
        .PACKET_FLIT_NUM(4),
        .INJECTION_THRESHOLD(16'd6554)
    ) board_traffic_generator (
        .clk(noc_clk),
        .rst(noc_rst),
        .local_on_off_i(local_on_off_o),
        .local_data_o(local_data_i),
        .local_valid_o(local_valid_i),
        .packet_enqueued_o(packet_enqueued),
        .enqueued_packet_id_o(enqueued_packet_id)
    );

    //Modify instantiate the intended 5x5, four-VC NoC beneath the board top, Michael Tan, 20260804
    (* DONT_TOUCH = "yes" *) mesh #(
        .MESH_SIZE_X(MESH_SIZE_X),
        .MESH_SIZE_Y(MESH_SIZE_Y)
    ) noc_mesh (
        .clk(noc_clk),
        .rst(noc_rst),
        .error_o(mesh_error),
        .data_o(local_data_o),
        .is_valid_o(local_valid_o),
        .is_on_off_i(local_on_off_i),
        .is_allocatable_i(local_allocatable_i),
        .data_i(local_data_i),
        .is_valid_i(local_valid_i),
        .is_on_off_o(local_on_off_o),
        .is_allocatable_o(local_allocatable_o)
    );

    //Modify measure source-queue entry to destination TAIL latency and retain counters for the later ILA step, Michael Tan, 20260817
    noc_board_latency_monitor #(
        .MESH_SIZE_X(MESH_SIZE_X),
        .MESH_SIZE_Y(MESH_SIZE_Y),
        .PACKET_FLIT_NUM(4),
        .COUNTER_WIDTH(32)
    ) board_latency_monitor (
        .clk(noc_clk),
        .rst(noc_rst),
        .packet_enqueued_i(packet_enqueued),
        .enqueued_packet_id_i(enqueued_packet_id),
        .local_data_i(local_data_o),
        .local_valid_i(local_valid_o),
        .packets_enqueued_o(monitor_packets_enqueued),
        .tails_received_o(monitor_tails_received),
        .unmatched_tails_o(monitor_unmatched_tails),
        .timestamp_overwrites_o(monitor_timestamp_overwrites),
        .total_latency_cycles_o(monitor_total_latency_cycles),
        .debug_tail_event_o(monitor_debug_tail_event),
        .debug_tail_packet_id_o(monitor_debug_tail_packet_id),
        .debug_tail_source_id_o(monitor_debug_tail_source_id),
        .debug_tail_sequence_o(monitor_debug_tail_sequence),
        .debug_enqueue_cycle_o(monitor_debug_enqueue_cycle),
        .debug_current_cycle_o(monitor_debug_current_cycle),
        .debug_last_packet_latency_o(monitor_debug_last_packet_latency)
    );

endmodule
