`timescale 1ns / 1ps

import noc_params::*;

//Modify add a separate 0.1 board latency diagnostic using direct uniform non-self destination mapping, Michael Tan, 20260827
module tb_noc_board_latency_monitor_windowed_uniform_dest;
    localparam WARMUP_CYCLES = 200;
    localparam MEASURE_CYCLES = 1000;
    localparam DRAIN_CYCLES = 8000;
    localparam SOURCE_QUEUE_DEPTH = 2048;

    logic l_pad_clk_p;
    logic l_pad_clk_n;
    logic l_pad_rst_b;
    int error_count;
    int debug_tail_event_count;
    longint average_latency_x1000;

    noc_board_ila_top #(
        .WARMUP_CYCLES(WARMUP_CYCLES),
        .MEASURE_CYCLES(MEASURE_CYCLES),
        .DRAIN_CYCLES(DRAIN_CYCLES),
        .SOURCE_QUEUE_DEPTH(SOURCE_QUEUE_DEPTH)//Modify match the reference TB capacity while testing the corrected destination distribution, Michael Tan, 20260827
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
                                error_count++;//Modify retain mesh error surveillance during the corrected-traffic test, Michael Tan, 20260827
                        end
                    end
                end
            end
        end
    end

    always @(negedge dut.noc_clk) begin
        if (!dut.noc_rst && dut.monitor_debug_tail_event) begin
            debug_tail_event_count++;
            if (dut.monitor_debug_last_packet_latency != (dut.monitor_debug_current_cycle - dut.monitor_debug_enqueue_cycle))
                $fatal(1, "[TB_BOARD_MONITOR_UNIFORM_DEST] debug latency operands do not match the reported packet latency");
        end
    end

    initial begin
        l_pad_clk_p = 1'b0;
        l_pad_clk_n = 1'b1;
        l_pad_rst_b = 1'b0;
        error_count = 0;
        debug_tail_event_count = 0;
        average_latency_x1000 = 0;

        repeat (4) @(posedge l_pad_clk_p);
        l_pad_rst_b = 1'b1;
        repeat (WARMUP_CYCLES + MEASURE_CYCLES + DRAIN_CYCLES + 4) @(posedge l_pad_clk_p);

        if (dut.traffic_window_phase != 2'd3)
            $fatal(1, "[TB_BOARD_MONITOR_UNIFORM_DEST] traffic-window controller did not reach DONE phase");//Modify require a completed drain before evaluating the corrected destination distribution, Michael Tan, 20260827
        if (dut.monitor_packets_enqueued == 0 || dut.monitor_tails_received == 0)
            $fatal(1, "[TB_BOARD_MONITOR_UNIFORM_DEST] measurement traffic did not complete");//Modify require nonempty completed corrected-traffic measurement, Michael Tan, 20260827
        if (dut.monitor_tails_received != dut.monitor_packets_enqueued)
            $fatal(1, "[TB_BOARD_MONITOR_UNIFORM_DEST] measurement packets enqueued=%0d tails=%0d after drain", dut.monitor_packets_enqueued, dut.monitor_tails_received);//Modify require every measured packet to drain, Michael Tan, 20260827
        if (dut.monitor_queue_full != 0 || dut.monitor_unmatched_tails != 0 || dut.monitor_timestamp_overwrites != 0 || error_count != 0)
            $fatal(1, "[TB_BOARD_MONITOR_UNIFORM_DEST] queue_full=%0d unmatched=%0d overwrites=%0d mesh_errors=%0d", dut.monitor_queue_full, dut.monitor_unmatched_tails, dut.monitor_timestamp_overwrites, error_count);//Modify require zero loss, correlation, overwrite, and mesh errors, Michael Tan, 20260827
        if (debug_tail_event_count == 0)
            $fatal(1, "[TB_BOARD_MONITOR_UNIFORM_DEST] no matched-TAIL debug event was observed");//Modify retain per-packet debug verification after the destination-mapping correction, Michael Tan, 20260827

        average_latency_x1000 = (dut.monitor_total_latency_cycles * 1000) / dut.monitor_tails_received;
        $display("[TB_BOARD_MONITOR_UNIFORM_DEST] PASSED warmup=%0d measure=%0d drain=%0d enqueued=%0d queue_full=%0d tails=%0d unmatched=%0d overwrites=%0d total_latency=%0d avg_latency_x1000=%0d mesh_errors=%0d", WARMUP_CYCLES, MEASURE_CYCLES, DRAIN_CYCLES, dut.monitor_packets_enqueued, dut.monitor_queue_full, dut.monitor_tails_received, dut.monitor_unmatched_tails, dut.monitor_timestamp_overwrites, dut.monitor_total_latency_cycles, average_latency_x1000, error_count);//Modify report the corrected 0.1 destination-distribution result, Michael Tan, 20260827
        $finish;
    end
endmodule
