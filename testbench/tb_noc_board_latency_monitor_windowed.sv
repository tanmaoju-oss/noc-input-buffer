`timescale 1ns / 1ps

import noc_params::*;

//Modify add board latency-monitor verification using the performance-TB warm-up, measurement, and drain windows, Michael Tan, 20260827
module tb_noc_board_latency_monitor_windowed;
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
        .SOURCE_QUEUE_DEPTH(SOURCE_QUEUE_DEPTH)//Modify match the reusable performance TB's source-queue capacity for a directly comparable windowed result, Michael Tan, 20260827
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
                                error_count++;//Modify retain mesh error surveillance throughout warm-up, measurement, and drain, Michael Tan, 20260827
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
                $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] debug latency operands do not match the reported packet latency");
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
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] traffic-window controller did not reach DONE phase");//Modify require the bounded drain window to complete before evaluating statistics, Michael Tan, 20260827
        if (dut.monitor_packets_enqueued == 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] no measurement-window packet was accepted into a source queue");//Modify require nonempty measurement traffic, Michael Tan, 20260827
        if (dut.monitor_tails_received == 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] no measurement-window TAIL was matched");//Modify require completed measurement traffic, Michael Tan, 20260827
        if (dut.monitor_tails_received != dut.monitor_packets_enqueued)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] measurement packets enqueued=%0d tails=%0d after drain", dut.monitor_packets_enqueued, dut.monitor_tails_received);//Modify require every measured enqueue to reach a matched TAIL after drain, Michael Tan, 20260827
        if (dut.monitor_queue_full != 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] measurement source-queue-full count=%0d", dut.monitor_queue_full);//Modify match the reusable 0.1 reference point's zero queue-full requirement, Michael Tan, 20260827
        if (dut.monitor_unmatched_tails != 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] unmatched TAIL count=%0d", dut.monitor_unmatched_tails);//Modify reject packet-ID correlation failures from all windows, Michael Tan, 20260827
        if (dut.monitor_timestamp_overwrites != 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] timestamp overwrite count=%0d", dut.monitor_timestamp_overwrites);//Modify reject packet-ID timestamp reuse before a matching TAIL, Michael Tan, 20260827
        if (dut.monitor_total_latency_cycles == 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] measurement latency accumulation did not advance");//Modify require positive measured latency, Michael Tan, 20260827
        if (debug_tail_event_count == 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] no matched-TAIL debug event was observed");//Modify preserve single-packet waveform observability during windowed testing, Michael Tan, 20260827
        if (error_count != 0)
            $fatal(1, "[TB_BOARD_MONITOR_WINDOWED] mesh reported %0d error bits", error_count);//Modify require error-free NoC operation for a comparable statistic, Michael Tan, 20260827

        average_latency_x1000 = (dut.monitor_total_latency_cycles * 1000) / dut.monitor_tails_received;
        $display("[TB_BOARD_MONITOR_WINDOWED] PASSED warmup=%0d measure=%0d drain=%0d enqueued=%0d queue_full=%0d tails=%0d unmatched=%0d overwrites=%0d total_latency=%0d avg_latency_x1000=%0d mesh_errors=%0d", WARMUP_CYCLES, MEASURE_CYCLES, DRAIN_CYCLES, dut.monitor_packets_enqueued, dut.monitor_queue_full, dut.monitor_tails_received, dut.monitor_unmatched_tails, dut.monitor_timestamp_overwrites, dut.monitor_total_latency_cycles, average_latency_x1000, error_count);//Modify emit a directly comparable measurement-window latency statistic, Michael Tan, 20260827
        $finish;
    end
endmodule
