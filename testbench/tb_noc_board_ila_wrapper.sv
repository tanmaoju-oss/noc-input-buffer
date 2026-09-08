`timescale 1ns / 1ps

import noc_params::*;

//Modify add WSL verification that the board ILA wrapper is passive and maps every probe to its intended top-level signal, Michael Tan, 20260908
module tb_noc_board_ila_wrapper;
    localparam WARMUP_CYCLES = 200;
    localparam MEASURE_CYCLES = 1000;
    localparam DRAIN_CYCLES = 8000;
    localparam SOURCE_QUEUE_DEPTH = 2048;

    logic l_pad_clk_p;
    logic l_pad_clk_n;
    logic l_pad_rst_b;
    int error_count;
    int probe_mismatch_count;
    int debug_tail_event_count;

    noc_board_ila_top #(
        .WARMUP_CYCLES(WARMUP_CYCLES),
        .MEASURE_CYCLES(MEASURE_CYCLES),
        .DRAIN_CYCLES(DRAIN_CYCLES),
        .SOURCE_QUEUE_DEPTH(SOURCE_QUEUE_DEPTH)
    ) dut (
        .l_pad_clk_p(l_pad_clk_p),
        .l_pad_clk_n(l_pad_clk_n),
        .l_pad_rst_b(l_pad_rst_b)
    );

    always #5 l_pad_clk_p = ~l_pad_clk_p;
    always #5 l_pad_clk_n = ~l_pad_clk_n;

    always @(posedge dut.noc_clk) begin
        if (!dut.noc_rst) begin
            for (int x = 0; x < MESH_SIZE_X; x++) begin
                for (int y = 0; y < MESH_SIZE_Y; y++) begin
                    for (int port = 0; port < PORT_NUM; port++) begin
                        for (int vc = 0; vc < VC_NUM; vc++) begin
                            if (dut.mesh_error[x][y][port][vc])
                                error_count++;//Modify retain mesh-error surveillance during ILA-wrapper verification, Michael Tan, 20260908
                        end
                    end
                end
            end
        end
    end

    always @(negedge dut.noc_clk) begin
        if (!dut.noc_rst) begin
            if ((dut.board_ila_debug.clk !== dut.noc_clk) ||
                (dut.board_ila_debug.traffic_window_phase_i !== dut.traffic_window_phase) ||
                (dut.board_ila_debug.traffic_generate_enable_i !== dut.traffic_generate_enable) ||
                (dut.board_ila_debug.monitor_measurement_enable_i !== dut.monitor_measurement_enable) ||
                (dut.board_ila_debug.monitor_packets_enqueued_i !== dut.monitor_packets_enqueued) ||
                (dut.board_ila_debug.monitor_queue_full_i !== dut.monitor_queue_full) ||
                (dut.board_ila_debug.monitor_tails_received_i !== dut.monitor_tails_received) ||
                (dut.board_ila_debug.monitor_unmatched_tails_i !== dut.monitor_unmatched_tails) ||
                (dut.board_ila_debug.monitor_timestamp_overwrites_i !== dut.monitor_timestamp_overwrites) ||
                (dut.board_ila_debug.monitor_total_latency_cycles_i !== dut.monitor_total_latency_cycles) ||
                (dut.board_ila_debug.monitor_debug_tail_event_i !== dut.monitor_debug_tail_event) ||
                (dut.board_ila_debug.monitor_debug_tail_packet_id_i !== dut.monitor_debug_tail_packet_id) ||
                (dut.board_ila_debug.monitor_debug_tail_source_id_i !== dut.monitor_debug_tail_source_id) ||
                (dut.board_ila_debug.monitor_debug_tail_sequence_i !== dut.monitor_debug_tail_sequence) ||
                (dut.board_ila_debug.monitor_debug_enqueue_cycle_i !== dut.monitor_debug_enqueue_cycle) ||
                (dut.board_ila_debug.monitor_debug_current_cycle_i !== dut.monitor_debug_current_cycle) ||
                (dut.board_ila_debug.monitor_debug_last_packet_latency_i !== dut.monitor_debug_last_packet_latency))
                probe_mismatch_count++;//Modify require every WSL no-op ILA probe to equal its source signal, Michael Tan, 20260908

            if (dut.monitor_debug_tail_event) begin
                debug_tail_event_count++;
                if (dut.monitor_debug_last_packet_latency != (dut.monitor_debug_current_cycle - dut.monitor_debug_enqueue_cycle))
                    $fatal(1, "[TB_BOARD_ILA_WRAPPER] debug latency operands do not match the reported packet latency");
            end
        end
    end

    initial begin
        l_pad_clk_p = 1'b0;
        l_pad_clk_n = 1'b1;
        l_pad_rst_b = 1'b0;
        error_count = 0;
        probe_mismatch_count = 0;
        debug_tail_event_count = 0;

        repeat (4) @(posedge l_pad_clk_p);
        l_pad_rst_b = 1'b1;
        repeat (WARMUP_CYCLES + MEASURE_CYCLES + DRAIN_CYCLES + 4) @(posedge l_pad_clk_p);

        if (dut.traffic_window_phase != 2'd3)
            $fatal(1, "[TB_BOARD_ILA_WRAPPER] traffic-window controller did not reach DONE");//Modify require a completed drain before evaluating ILA probes, Michael Tan, 20260908
        if (dut.monitor_packets_enqueued == 0 || dut.monitor_tails_received != dut.monitor_packets_enqueued)
            $fatal(1, "[TB_BOARD_ILA_WRAPPER] enqueued=%0d tails=%0d after drain", dut.monitor_packets_enqueued, dut.monitor_tails_received);//Modify require the passive wrapper to preserve completed measurement traffic, Michael Tan, 20260908
        if (dut.monitor_queue_full != 0 || dut.monitor_unmatched_tails != 0 || dut.monitor_timestamp_overwrites != 0 || error_count != 0 || probe_mismatch_count != 0)
            $fatal(1, "[TB_BOARD_ILA_WRAPPER] queue_full=%0d unmatched=%0d overwrites=%0d mesh_errors=%0d probe_mismatches=%0d", dut.monitor_queue_full, dut.monitor_unmatched_tails, dut.monitor_timestamp_overwrites, error_count, probe_mismatch_count);//Modify require clean monitor and exact probe mapping, Michael Tan, 20260908
        if (debug_tail_event_count == 0)
            $fatal(1, "[TB_BOARD_ILA_WRAPPER] no matched-TAIL debug event was observed");//Modify require observable ILA tail-event activity, Michael Tan, 20260908

        $display("[TB_BOARD_ILA_WRAPPER] PASSED warmup=%0d measure=%0d drain=%0d enqueued=%0d tails=%0d tail_events=%0d probe_mismatches=%0d total_latency=%0d", WARMUP_CYCLES, MEASURE_CYCLES, DRAIN_CYCLES, dut.monitor_packets_enqueued, dut.monitor_tails_received, debug_tail_event_count, probe_mismatch_count, dut.monitor_total_latency_cycles);//Modify report passive ILA-wrapper verification results, Michael Tan, 20260908
        $finish;
    end
endmodule
