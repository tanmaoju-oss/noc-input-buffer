`timescale 1ns / 1ps

//Modify add a simple concurrent four-virtual-channel mesh test, Michael Tan, 20260715
import noc_params::*;

module tb_mesh_4vc_simple #(
    parameter BUFFER_SIZE = 8,
    parameter TB_MESH_SIZE_X = 2,
    parameter TB_MESH_SIZE_Y = 3
);

    localparam PACKET_NUM = 4;
    localparam EXPECTED_FLITS = PACKET_NUM * 2;

    logic clk;
    logic rst;
    logic [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_cmd;
    logic [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_cmd;
    logic [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0] is_valid_cmd;
    flit_t [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0] data_cmd;

    logic [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0] is_valid_o;
    logic [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_o;
    logic [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o;
    logic [VC_NUM-1:0] error_o [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0][PORT_NUM-1:0];
    flit_t [TB_MESH_SIZE_X-1:0][TB_MESH_SIZE_Y-1:0] data_o;

    int src_x;
    int src_y;
    int dst_x;
    int dst_y;
    int received_flits;
    int error_count;
    int result_fd;
    logic [PACKET_NUM-1:0] head_seen;
    logic [PACKET_NUM-1:0] tail_seen;
    logic [VC_NUM-1:0] output_vc_seen;

    mesh #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .MESH_SIZE_X(TB_MESH_SIZE_X),
        .MESH_SIZE_Y(TB_MESH_SIZE_Y)
    ) dut (
        .clk(clk),
        .rst(rst),
        .error_o(error_o),
        .data_o(data_o),
        .is_valid_o(is_valid_o),
        .is_on_off_i(is_on_off_cmd),
        .is_allocatable_i(is_allocatable_cmd),
        .data_i(data_cmd),
        .is_valid_i(is_valid_cmd),
        .is_on_off_o(is_on_off_o),
        .is_allocatable_o(is_allocatable_o)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("out.vcd");
        $dumpvars(0, tb_mesh_4vc_simple);
        initialize();
        reset_dut();
        run_four_vc_traffic();
        wait_for_completion();
        final_checks();
        $finish;
    end

    always @(posedge clk) begin
        if(!rst) begin
            #1 monitor_outputs();
        end
    end

    task initialize();
        clk = 1'b0;
        rst = 1'b1;
        src_x = 0;
        src_y = 0;
        dst_x = 1;
        dst_y = 2;
        received_flits = 0;
        error_count = 0;
        head_seen = '0;
        tail_seen = '0;
        output_vc_seen = '0;
        is_valid_cmd = '0;
        data_cmd = '0;
        is_on_off_cmd = '1;
        is_allocatable_cmd = '1;

        if(VC_NUM != 4) begin
            $fatal(1, "[TB_MESH_4VC] expected VC_NUM=4, got %0d", VC_NUM);
        end
        if(VC_SIZE != 2) begin
            $fatal(1, "[TB_MESH_4VC] expected two-bit VC identifiers, got VC_SIZE=%0d", VC_SIZE);
        end
    endtask

    task reset_dut();
        repeat(3) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
    endtask

    task run_four_vc_traffic();
        // Fill all four source virtual channels before their TAIL flits arrive.
        for(int packet_id = 0; packet_id < PACKET_NUM; packet_id++) begin
            drive_flit(HEAD, packet_id, packet_id);
        end
        for(int packet_id = 0; packet_id < PACKET_NUM; packet_id++) begin
            drive_flit(TAIL, packet_id, packet_id);
        end
        @(negedge clk);
        is_valid_cmd[src_x][src_y] = 1'b0;
        data_cmd[src_x][src_y] = '0;
    endtask

    task drive_flit(input flit_label_t label, input int vc_id, input int packet_id);
        @(negedge clk);
        data_cmd[src_x][src_y] = '0;
        data_cmd[src_x][src_y].flit_label = label;
        data_cmd[src_x][src_y].vc_id = vc_id[VC_SIZE-1:0];
        if(label == HEAD) begin
            data_cmd[src_x][src_y].data.head_data.x_dest = dst_x;
            data_cmd[src_x][src_y].data.head_data.y_dest = dst_y;
            data_cmd[src_x][src_y].data.head_data.head_pl = packet_id;
        end
        else begin
            data_cmd[src_x][src_y].data.bt_pl = packet_id;
        end
        is_valid_cmd[src_x][src_y] = 1'b1;
        $display("[TB_MESH_4VC] inject label=%0d input_vc=%0d packet=%0d time=%0t",
                 label, vc_id, packet_id, $time);
    endtask

    task wait_for_completion();
        int timeout_cycles;
        timeout_cycles = 0;
        while((received_flits < EXPECTED_FLITS) && (timeout_cycles < 300)) begin
            @(posedge clk);
            timeout_cycles++;
        end
        repeat(5) @(posedge clk);
    endtask

    task monitor_outputs();
        int packet_id;
        for(int x = 0; x < TB_MESH_SIZE_X; x++) begin
            for(int y = 0; y < TB_MESH_SIZE_Y; y++) begin
                if(is_valid_o[x][y]) begin
                    received_flits++;
                    output_vc_seen[data_o[x][y].vc_id] = 1'b1;

                    if((x != dst_x) || (y != dst_y)) begin
                        error_count++;
                        $error("[TB_MESH_4VC] flit arrived at (%0d,%0d), expected (%0d,%0d)",
                               x, y, dst_x, dst_y);
                    end

                    if(data_o[x][y].flit_label == HEAD) begin
                        packet_id = data_o[x][y].data.head_data.head_pl;
                        if((packet_id < 0) || (packet_id >= PACKET_NUM) || head_seen[packet_id]) begin
                            error_count++;
                            $error("[TB_MESH_4VC] invalid or duplicate HEAD packet=%0d", packet_id);
                        end
                        else begin
                            head_seen[packet_id] = 1'b1;
                        end
                    end
                    else if(data_o[x][y].flit_label == TAIL) begin
                        packet_id = data_o[x][y].data.bt_pl;
                        if((packet_id < 0) || (packet_id >= PACKET_NUM) || tail_seen[packet_id]) begin
                            error_count++;
                            $error("[TB_MESH_4VC] invalid or duplicate TAIL packet=%0d", packet_id);
                        end
                        else if(!head_seen[packet_id]) begin
                            error_count++;
                            $error("[TB_MESH_4VC] TAIL arrived before HEAD packet=%0d", packet_id);
                        end
                        else begin
                            tail_seen[packet_id] = 1'b1;
                        end
                    end
                    else begin
                        error_count++;
                        $error("[TB_MESH_4VC] unexpected flit label=%0d", data_o[x][y].flit_label);
                    end

                    $display("[TB_MESH_4VC] receive label=%0d output_vc=%0d packet=%0d count=%0d time=%0t",
                             data_o[x][y].flit_label, data_o[x][y].vc_id, packet_id,
                             received_flits, $time);
                end

                for(int port = 0; port < PORT_NUM; port++) begin
                    for(int vc = 0; vc < VC_NUM; vc++) begin
                        if(error_o[x][y][port][vc] === 1'b1) begin
                            error_count++;
                            $error("[TB_MESH_4VC] error_o node=(%0d,%0d) port=%0d vc=%0d time=%0t",
                                   x, y, port, vc, $time);
                        end
                    end
                end
            end
        end
    endtask

    task final_checks();
        result_fd = $fopen("tb_mesh_4vc_simple_results.txt", "w");
        if(received_flits != EXPECTED_FLITS) begin
            error_count++;
            $error("[TB_MESH_4VC] expected %0d flits, received %0d", EXPECTED_FLITS, received_flits);
        end
        if(head_seen != {PACKET_NUM{1'b1}}) begin
            error_count++;
            $error("[TB_MESH_4VC] missing HEAD packets: seen=%b", head_seen);
        end
        if(tail_seen != {PACKET_NUM{1'b1}}) begin
            error_count++;
            $error("[TB_MESH_4VC] missing TAIL packets: seen=%b", tail_seen);
        end
        // Downstream VC identifiers are reallocated at every hop; fewer than four
        // output VC numbers may be sufficient even though all four source VCs worked.
        // Packet IDs 0-3 deliberately map to input VC0-VC3, so complete HEAD/TAIL
        // masks prove that traffic stored in and emerged from every source VC.
        //Modify check all four source VCs by completed packet identity, Michael Tan, 20260715

        $fdisplay(result_fd,
                  "vc_num expected_flits received_flits head_seen tail_seen output_vc_seen error_count");
        $fdisplay(result_fd, "%0d %0d %0d %b %b %b %0d",
                  VC_NUM, EXPECTED_FLITS, received_flits, head_seen, tail_seen,
                  output_vc_seen, error_count);
        $fclose(result_fd);

        if(error_count == 0) begin
            $display("[TB_MESH_4VC] PASSED: input VC0-VC3 carried four complete packets; downstream_vc_seen=%b",
                     output_vc_seen);
        end
        else begin
            $fatal(1, "[TB_MESH_4VC] FAILED with %0d errors", error_count);
        end
    endtask

endmodule
