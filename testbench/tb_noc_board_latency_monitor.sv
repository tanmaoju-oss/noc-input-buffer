`timescale 1ns / 1ps

import noc_params::*;

//Modify add board-step-3 latency-monitor integration verification tb, Michael Tan, 20260817
module tb_noc_board_latency_monitor;
    localparam RUN_CYCLES = 1000;

    logic l_pad_clk_p;
    logic l_pad_clk_n;
    logic l_pad_rst_b;
    int error_count;

    noc_board_ila_top dut (
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
                                error_count++;//Modify retain the integrated mesh error check while exercising the latency monitor, Michael Tan, 20260817
                        end
                    end
                end
            end
        end
    end

    initial begin
        l_pad_clk_p = 1'b0;
        l_pad_clk_n = 1'b1;
        l_pad_rst_b = 1'b0;
        error_count = 0;

        repeat (4) @(posedge l_pad_clk_p);
        l_pad_rst_b = 1'b1;
        repeat (RUN_CYCLES) @(posedge l_pad_clk_p);

        if (dut.monitor_packets_enqueued == 0)
            $fatal(1, "[TB_BOARD_MONITOR] no packet was timestamped at source-queue entry");//Modify require an active source-side timestamp stream, Michael Tan, 20260817
        if (dut.monitor_tails_received == 0)
            $fatal(1, "[TB_BOARD_MONITOR] no TAIL arrival was matched");//Modify require an active destination-side latency measurement stream, Michael Tan, 20260817
        if (dut.monitor_tails_received > dut.monitor_packets_enqueued)
            $fatal(1, "[TB_BOARD_MONITOR] matched TAIL count exceeds enqueue count");//Modify reject impossible monitor accounting, Michael Tan, 20260817
        if (dut.monitor_unmatched_tails != 0)
            $fatal(1, "[TB_BOARD_MONITOR] unmatched TAIL count=%0d", dut.monitor_unmatched_tails);//Modify require packet-ID correlation for every observed TAIL, Michael Tan, 20260817
        if (dut.monitor_timestamp_overwrites != 0)
            $fatal(1, "[TB_BOARD_MONITOR] timestamp overwrite count=%0d", dut.monitor_timestamp_overwrites);//Modify require the bounded packet-ID timestamp table not to wrap during verification, Michael Tan, 20260817
        if (dut.monitor_total_latency_cycles == 0)
            $fatal(1, "[TB_BOARD_MONITOR] latency accumulation did not advance");//Modify require nonzero measured latency, Michael Tan, 20260817
        if (error_count != 0)
            $fatal(1, "[TB_BOARD_MONITOR] mesh reported %0d error bits", error_count);//Modify retain error-free NoC requirement, Michael Tan, 20260817

        $display("[TB_BOARD_MONITOR] PASSED enqueued=%0d tails=%0d unmatched=%0d overwrites=%0d total_latency=%0d mesh_errors=%0d", dut.monitor_packets_enqueued, dut.monitor_tails_received, dut.monitor_unmatched_tails, dut.monitor_timestamp_overwrites, dut.monitor_total_latency_cycles, error_count);//Modify report reusable board latency-monitor counters, Michael Tan, 20260817
        $finish;
    end
endmodule
