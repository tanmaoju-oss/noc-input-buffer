`timescale 1ns / 1ps

import noc_params::*;

//Modify add board-step-2 traffic generator integration verification tb, Michael Tan, 20260805
module tb_noc_board_traffic_generator;
    localparam RUN_CYCLES = 1000;

    logic l_pad_clk_p;
    logic l_pad_clk_n;
    logic l_pad_rst_b;
    int received_flits;
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
                    if (dut.local_valid_o[x][y])
                        received_flits++;//Modify count the board-generated traffic that reaches a local destination, Michael Tan, 20260805
                    for (int port = 0; port < PORT_NUM; port++) begin
                        for (int vc = 0; vc < VC_NUM; vc++) begin
                            if (dut.mesh_error[x][y][port][vc])
                                error_count++;//Modify fail verification if the integrated mesh reports an error, Michael Tan, 20260805
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
        received_flits = 0;
        error_count = 0;

        repeat (4) @(posedge l_pad_clk_p);
        l_pad_rst_b = 1'b1;
        repeat (RUN_CYCLES) @(posedge l_pad_clk_p);

        if (received_flits == 0)
            $fatal(1, "[TB_BOARD_TRAFFIC] no generated flit reached a destination");//Modify require active traffic rather than a quiescent board top, Michael Tan, 20260805
        if (error_count != 0)
            $fatal(1, "[TB_BOARD_TRAFFIC] mesh reported %0d error bits", error_count);//Modify require error-free integrated traffic, Michael Tan, 20260805

        $display("[TB_BOARD_TRAFFIC] PASSED received_flits=%0d errors=%0d", received_flits, error_count);//Modify record board traffic integration pass condition, Michael Tan, 20260805
        $finish;
    end
endmodule
