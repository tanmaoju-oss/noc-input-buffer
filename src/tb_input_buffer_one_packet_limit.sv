`timescale 1ns / 1ps

import noc_params::*;

module tb_input_buffer_one_packet_limit #(
    parameter BUFFER_SIZE = 8
);

    logic clk;
    logic rst;
    logic read_i;
    logic write_i;
    logic [VC_SIZE-1:0] vc_new_i;
    logic vc_valid_i;

    port_t out_port_i;
    port_t out_port_o;

    flit_novc_t data_i;
    flit_t data_o;

    wire is_full_o;
    wire is_empty_o;
    wire on_off_o;
    wire vc_request_o;
    wire switch_request_o;
    wire vc_allocatable_o;
    wire [VC_SIZE-1:0] downstream_vc_o;
    wire error_o;

    input_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE)
    )
    dut (
        .data_i(data_i),
        .read_i(read_i),
        .write_i(write_i),
        .vc_new_i(vc_new_i),
        .vc_valid_i(vc_valid_i),
        .out_port_i(out_port_i),
        .rst(rst),
        .clk(clk),
        .data_o(data_o),
        .is_full_o(is_full_o),
        .is_empty_o(is_empty_o),
        .on_off_o(on_off_o),
        .out_port_o(out_port_o),
        .vc_request_o(vc_request_o),
        .switch_request_o(switch_request_o),
        .vc_allocatable_o(vc_allocatable_o),
        .downstream_vc_o(downstream_vc_o),
        .error_o(error_o)
    );

    always #5 clk = ~clk;

    initial
    begin
        dump_output();
        initialize();
        clear_reset();

        // Packet 0 starts normally.
        write_flit(HEAD, 8'h10);
        expect_no_error("HEAD P0 should be accepted");

        // Packet 0 is still open; no TAIL has been written or read.
        write_flit(BODY, 8'h11);
        expect_no_error("BODY P0 should be accepted");

        // Packet 1 tries to start in the same buffer before packet 0 completes.
        write_flit(HEAD, 8'h20);
        expect_error("HEAD P1 should be rejected while P0 is still active");

        $display("[ONE_PACKET_LIMIT] PASSED: original buffer rejects a second packet in the same VC");
        #20 $finish;
    end

    task dump_output();
        $dumpfile("one_packet_limit_out.vcd");
        $dumpvars(0, tb_input_buffer_one_packet_limit);
    endtask

    task initialize();
        clk = 0;
        rst = 1;
        read_i = 0;
        write_i = 0;
        vc_new_i = 0;
        vc_valid_i = 0;
        out_port_i = NORTH;
        data_i = '0;
    endtask

    task clear_reset();
        repeat(2) @(posedge clk);
        @(negedge clk);
        rst = 0;
    endtask

    task write_flit(input flit_label_t label,
                    input logic [7:0] payload_seed);
        begin
            @(negedge clk);
            read_i = 0;
            vc_valid_i = 0;
            write_i = 1;
            data_i.flit_label = label;

            if(label == HEAD || label == HEADTAIL)
            begin
                data_i.data.head_data.x_dest = payload_seed[DEST_ADDR_SIZE_X-1:0];
                data_i.data.head_data.y_dest = payload_seed[DEST_ADDR_SIZE_Y-1:0];
                data_i.data.head_data.head_pl = payload_seed;
            end
            else
            begin
                data_i.data.bt_pl = payload_seed;
            end

            @(posedge clk);
            @(negedge clk);
            write_i = 0;
        end
    endtask

    task expect_no_error(input string message);
        begin
            if(error_o !== 1'b0)
            begin
                $display("[ONE_PACKET_LIMIT] FAILED at %0t: %s; error_o=%0b",
                         $time, message, error_o);
                $finish;
            end
        end
    endtask

    task expect_error(input string message);
        begin
            if(error_o !== 1'b1)
            begin
                $display("[ONE_PACKET_LIMIT] FAILED at %0t: %s; expected error_o=1, got %0b",
                         $time, message, error_o);
                $finish;
            end
        end
    endtask

endmodule
