`timescale 1ns / 1ps

import noc_params::*;

module tb_mesh_two_distinct_packets #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 2,
    parameter MESH_SIZE_Y = 3,
    parameter PACKET_NUM = 2
);
    logic clk;
    logic rst;

    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_cmd;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_cmd;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_cmd;
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_cmd;

    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o;
    logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0];
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o;

    int src_x [PACKET_NUM];
    int src_y [PACKET_NUM];
    int dst_x [PACKET_NUM];
    int dst_y [PACKET_NUM];
    int packet_payload [PACKET_NUM];
    int dest_flits_seen [PACKET_NUM];
    int total_flits_seen;
    int error_seen;

    mesh #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .MESH_SIZE_X(MESH_SIZE_X),
        .MESH_SIZE_Y(MESH_SIZE_Y)
    )
    mesh (
        .clk(clk),
        .rst(rst),
        .is_on_off_i(is_on_off_cmd),
        .is_allocatable_i(is_allocatable_cmd),
        .data_i(data_cmd),
        .is_valid_i(is_valid_cmd),
        .data_o(data_o),
        .is_valid_o(is_valid_o),
        .is_on_off_o(is_on_off_o),
        .is_allocatable_o(is_allocatable_o),
        .error_o(error_o)
    );

    initial
    begin
        dump_output();
        initialize();
        clr_rst();
        test_two_distinct_packets();

        #180;
        final_checks();
        $finish;
    end

    always #5 clk = ~clk;

    always @(posedge clk)
    begin
        if(!rst)
        begin
            #1 monitor_outputs();
        end
    end

    task dump_output();
        $dumpfile("out.vcd");
        $dumpvars(0, tb_mesh_two_distinct_packets);
    endtask

    task initialize();
        clk = 0;
        rst = 1;
        total_flits_seen = 0;
        error_seen = 0;

        src_x[0] = 0;
        src_y[0] = 0;
        dst_x[0] = 1;
        dst_y[0] = 2;
        packet_payload[0] = 16'h00a0;
        dest_flits_seen[0] = 0;

        src_x[1] = 1;
        src_y[1] = 0;
        dst_x[1] = 0;
        dst_y[1] = 2;
        packet_payload[1] = 16'h00b1;
        dest_flits_seen[1] = 0;

        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                is_on_off_cmd[x][y] = {VC_NUM{1'b1}};
                is_allocatable_cmd[x][y] = {VC_NUM{1'b1}};
                is_valid_cmd[x][y] = 1'b0;
                data_cmd[x][y] = '0;
            end
        end
    endtask

    task clr_rst();
        @(posedge clk);
        rst <= 0;
    endtask

    task test_two_distinct_packets();
        @(posedge clk);
        write_packet_flit(0, HEAD);
        write_packet_flit(1, HEAD);

        @(posedge clk);
        write_packet_flit(0, TAIL);
        write_packet_flit(1, TAIL);

        @(posedge clk);
        for(int pkt=0; pkt < PACKET_NUM; pkt++)
        begin
            is_valid_cmd[src_x[pkt]][src_y[pkt]] = 1'b0;
            data_cmd[src_x[pkt]][src_y[pkt]] = '0;
        end
    endtask

    task monitor_outputs();
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                if(is_valid_o[x][y])
                begin
                    check_output_flit(x, y);
                end

                for(int port=0; port < PORT_NUM; port++)
                begin
                    for(int vc=0; vc < VC_NUM; vc++)
                    begin
                        if(error_o[x][y][port][vc] === 1'b1)
                        begin
                            error_seen++;
                            $error("[TB_MESH_TWO_DISTINCT] error_o asserted at node=(%0d,%0d) port=%0d vc=%0d time=%0t",
                                   x, y, port, vc, $time);
                        end
                    end
                end
            end
        end
    endtask

    task check_output_flit(input int x, input int y);
        int pkt_id;
        flit_label_t expected_label;

        pkt_id = find_packet_by_destination(x, y);
        if(pkt_id < 0)
        begin
            $error("[TB_MESH_TWO_DISTINCT] flit arrived at unexpected node (%0d,%0d)", x, y);
        end
        else
        begin
            expected_label = (dest_flits_seen[pkt_id] == 0) ? HEAD : TAIL;
            $display("[TB_MESH_TWO_DISTINCT] packet %0d output flit %0d at (%0d,%0d): label=%0d vc=%0d time=%0t",
                     pkt_id, dest_flits_seen[pkt_id], x, y, data_o[x][y].flit_label, data_o[x][y].vc_id, $time);

            if(dest_flits_seen[pkt_id] >= 2)
            begin
                $error("[TB_MESH_TWO_DISTINCT] packet %0d has unexpected extra output flit", pkt_id);
            end
            else if(data_o[x][y].flit_label !== expected_label)
            begin
                $error("[TB_MESH_TWO_DISTINCT] packet %0d label mismatch: got %0d expected %0d",
                       pkt_id, data_o[x][y].flit_label, expected_label);
            end

            if(data_o[x][y].flit_label == HEAD)
            begin
                if(data_o[x][y].data.head_data.x_dest !== dst_x[pkt_id] ||
                   data_o[x][y].data.head_data.y_dest !== dst_y[pkt_id] ||
                   data_o[x][y].data.head_data.head_pl !== packet_payload[pkt_id][HEAD_PAYLOAD_SIZE-1:0])
                begin
                    $error("[TB_MESH_TWO_DISTINCT] packet %0d HEAD fields are wrong", pkt_id);
                end
            end
            else if(data_o[x][y].flit_label == TAIL)
            begin
                if(data_o[x][y].data.bt_pl !== packet_payload[pkt_id][FLIT_DATA_SIZE-1:0])
                begin
                    $error("[TB_MESH_TWO_DISTINCT] packet %0d TAIL payload is wrong", pkt_id);
                end
            end

            dest_flits_seen[pkt_id]++;
            total_flits_seen++;
        end
    endtask

    task final_checks();
        for(int pkt=0; pkt < PACKET_NUM; pkt++)
        begin
            if(dest_flits_seen[pkt] != 2)
            begin
                $error("[TB_MESH_TWO_DISTINCT] packet %0d expected 2 output flits, saw %0d",
                       pkt, dest_flits_seen[pkt]);
            end
        end

        if(total_flits_seen != PACKET_NUM * 2)
            $error("[TB_MESH_TWO_DISTINCT] expected %0d total output flits, saw %0d", PACKET_NUM * 2, total_flits_seen);
        if(error_seen != 0)
            $error("[TB_MESH_TWO_DISTINCT] observed %0d error_o assertions", error_seen);
        if(total_flits_seen == PACKET_NUM * 2 && error_seen == 0)
            $display("[TB_MESH_TWO_DISTINCT] PASSED");
    endtask

    task write_packet_flit(input int pkt_id, input flit_label_t lab);
        flit_t flit;

        flit = '0;
        flit.flit_label = lab;
        flit.vc_id = 0;

        if(lab == HEAD || lab == HEADTAIL)
        begin
            flit.data.head_data.x_dest = dst_x[pkt_id];
            flit.data.head_data.y_dest = dst_y[pkt_id];
            flit.data.head_data.head_pl = packet_payload[pkt_id][HEAD_PAYLOAD_SIZE-1:0];
        end
        else
        begin
            flit.data.bt_pl = packet_payload[pkt_id][FLIT_DATA_SIZE-1:0];
        end

        is_valid_cmd[src_x[pkt_id]][src_y[pkt_id]] = 1'b1;
        data_cmd[src_x[pkt_id]][src_y[pkt_id]] = flit;
    endtask

    function int find_packet_by_destination(input int x, input int y);
        find_packet_by_destination = -1;
        for(int pkt=0; pkt < PACKET_NUM; pkt++)
        begin
            if(x == dst_x[pkt] && y == dst_y[pkt])
            begin
                find_packet_by_destination = pkt;
                break;
            end
        end
    endfunction

endmodule
