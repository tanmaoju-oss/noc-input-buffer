`timescale 1ns / 1ps

import noc_params::*;

module tb_input_buffer_multi_packet #(
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
    flit_t expected_queue[$];

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

        // New test: write two complete packets back-to-back before reading any flit.
        write_packet(NORTH, 1'b1, 8'h10);
        write_packet(WEST,  1'b0, 8'h20);

        // New check: both packets are resident, and only the first packet requests VA.
        expect_is_empty(1'b0);
        expect_vc_request(1'b1);

        // New check: allocate and drain packet 0. Packet 1 must wait behind it.
        allocate_head_packet(1'b1);
        expect_switch_request(1'b1);
        expect_head_route(NORTH, 1'b1);
        read_expected_flit();
        read_expected_flit();
        read_expected_flit();
        expect_allocatable_pulse();

        // New check: after packet 0 tail leaves, packet 1 becomes head and requests VA.
        wait_one_cycle();
        expect_vc_request(1'b1);
        allocate_head_packet(1'b0);
        expect_switch_request(1'b1);
        expect_head_route(WEST, 1'b0);
        read_expected_flit();
        read_expected_flit();
        read_expected_flit();
        expect_allocatable_pulse();

        wait_one_cycle();
        expect_is_empty(1'b1);
        expect_no_error();
        $display("[MULTI_PACKET] PASSED");
        #20 $finish;
    end

    task dump_output();
        $dumpfile("multi_packet_out.vcd");
        $dumpvars(0, tb_input_buffer_multi_packet);
    endtask

    task initialize();
        clk = 0;
        rst = 1;
        read_i = 0;
        write_i = 0;
        vc_new_i = 0;
        vc_valid_i = 0;
        out_port_i = LOCAL;
        data_i = '0;
    endtask

    task clear_reset();
        repeat(2) @(posedge clk);
        @(negedge clk);
        rst = 0;
    endtask

    task wait_one_cycle();
        @(negedge clk);
        read_i = 0;
        write_i = 0;
        vc_valid_i = 0;
        @(posedge clk);
    endtask

    task write_packet(input port_t packet_port,
                      input logic [VC_SIZE-1:0] downstream_vc,
                      input logic [7:0] base_payload);
        begin
            write_flit(HEAD, packet_port, downstream_vc, base_payload);
            write_flit(BODY, packet_port, downstream_vc, base_payload + 8'h1);
            write_flit(TAIL, packet_port, downstream_vc, base_payload + 8'h2);
        end
    endtask

    task write_flit(input flit_label_t label,
                    input port_t packet_port,
                    input logic [VC_SIZE-1:0] downstream_vc,
                    input logic [7:0] payload_seed);
        flit_t expected;
        begin
            @(negedge clk);
            read_i = 0;
            vc_valid_i = 0;
            write_i = 1;
            out_port_i = packet_port;
            data_i.flit_label = label;

            expected.flit_label = label;
            expected.vc_id = downstream_vc;

            if(label == HEAD || label == HEADTAIL)
            begin
                data_i.data.head_data.x_dest = payload_seed[DEST_ADDR_SIZE_X-1:0];
                data_i.data.head_data.y_dest = payload_seed[DEST_ADDR_SIZE_Y-1:0];
                data_i.data.head_data.head_pl = payload_seed;
                expected.data.head_data = data_i.data.head_data;
            end
            else
            begin
                data_i.data.bt_pl = payload_seed;
                expected.data.bt_pl = data_i.data.bt_pl;
            end

            expected_queue.push_back(expected);
            @(posedge clk);
            @(negedge clk);
            write_i = 0;
            check_no_error_now();
        end
    endtask

    task allocate_head_packet(input logic [VC_SIZE-1:0] downstream_vc);
        begin
            expect_vc_request(1'b1);
            @(negedge clk);
            vc_new_i = downstream_vc;
            vc_valid_i = 1;
            @(posedge clk);
            @(negedge clk);
            vc_valid_i = 0;
            check_no_error_now();
        end
    endtask

    task read_expected_flit();
        flit_t expected;
        begin
            expected = expected_queue.pop_front();
            expect_switch_request(1'b1);
            @(negedge clk);
            read_i = 1;
            #1;
            if(data_o !== expected)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: expected label=%0d vc=%0d data=%h, got label=%0d vc=%0d data=%h",
                         $time,
                         expected.flit_label,
                         expected.vc_id,
                         expected.data,
                         data_o.flit_label,
                         data_o.vc_id,
                         data_o.data);
                $finish;
            end
            @(posedge clk);
            @(negedge clk);
            read_i = 0;
            check_no_error_now();
        end
    endtask

    task expect_allocatable_pulse();
        begin
            if(vc_allocatable_o !== 1'b1)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: vc_allocatable_o did not pulse", $time);
                $finish;
            end
        end
    endtask

    task expect_head_route(input port_t expected_port,
                           input logic [VC_SIZE-1:0] expected_vc);
        begin
            @(negedge clk);
            if(out_port_o !== expected_port || downstream_vc_o !== expected_vc)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: expected out_port=%0d downstream_vc=%0d, got out_port=%0d downstream_vc=%0d",
                         $time, expected_port, expected_vc, out_port_o, downstream_vc_o);
                $finish;
            end
        end
    endtask

    task expect_vc_request(input logic expected);
        begin
            @(negedge clk);
            if(vc_request_o !== expected)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: expected vc_request_o=%0b, got %0b",
                         $time, expected, vc_request_o);
                $finish;
            end
        end
    endtask

    task expect_switch_request(input logic expected);
        begin
            @(negedge clk);
            if(switch_request_o !== expected)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: expected switch_request_o=%0b, got %0b",
                         $time, expected, switch_request_o);
                $finish;
            end
        end
    endtask

    task expect_is_empty(input logic expected);
        begin
            @(negedge clk);
            if(is_empty_o !== expected)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: expected is_empty_o=%0b, got %0b",
                         $time, expected, is_empty_o);
                $finish;
            end
        end
    endtask

    task expect_no_error();
        begin
            @(negedge clk);
            check_no_error_now();
        end
    endtask

    task check_no_error_now();
        begin
            if(error_o !== 1'b0)
            begin
                $display("[MULTI_PACKET] FAILED at %0t: error_o asserted", $time);
                $finish;
            end
        end
    endtask

endmodule
