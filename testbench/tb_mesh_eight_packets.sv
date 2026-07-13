`timescale 1ns / 1ps

import noc_params::*;

module tb_mesh_eight_packets #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 2,
    parameter MESH_SIZE_Y = 3,
    parameter PACKET_NUM = 8,
    parameter EXPECTED_FLITS = PACKET_NUM * 2
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

    int x_from, y_from, x_dest, y_dest;
    int dest_flits_seen, error_seen;
    flit_t current_flit;

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
        test_eight_back_to_back_packets();

        #500;
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
        $dumpvars(0, tb_mesh_eight_packets);
    endtask

    task initialize();
        clk = 0;
        rst = 1;
        x_from = 0;
        y_from = 0;
        x_dest = 1;
        y_dest = 2;
        dest_flits_seen = 0;
        error_seen = 0;

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

    task test_eight_back_to_back_packets();
        for(int pkt=0; pkt < PACKET_NUM; pkt++)
        begin
            @(posedge clk);
            write_flit(pkt, HEAD);

            @(posedge clk);
            write_flit(pkt, TAIL);
        end

        @(posedge clk);
        is_valid_cmd[x_from][y_from] = 1'b0;
        data_cmd[x_from][y_from] = '0;
    endtask

    task write_flit(input int pkt_id, input flit_label_t lab);
        current_flit = '0;
        current_flit.flit_label = lab;
        current_flit.vc_id = 0;

        if(lab == HEAD || lab == HEADTAIL)
        begin
            current_flit.data.head_data.x_dest = x_dest;
            current_flit.data.head_data.y_dest = y_dest;
            current_flit.data.head_data.head_pl = pkt_id[HEAD_PAYLOAD_SIZE-1:0];
        end
        else
        begin
            current_flit.data.bt_pl = pkt_id[FLIT_DATA_SIZE-1:0];
        end

        is_valid_cmd[x_from][y_from] = 1'b1;
        data_cmd[x_from][y_from] = current_flit;
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
                            $error("[TB_MESH_EIGHT_PACKETS] error_o asserted at node=(%0d,%0d) port=%0d vc=%0d time=%0t",
                                   x, y, port, vc, $time);
                        end
                    end
                end
            end
        end
    endtask

    task check_output_flit(input int x, input int y);
        int expected_pkt_id;
        flit_label_t expected_label;
        int observed_pkt_id;

        expected_pkt_id = dest_flits_seen / 2;
        expected_label = (dest_flits_seen % 2 == 0) ? HEAD : TAIL;

        $display("[TB_MESH_EIGHT_PACKETS] output flit %0d at (%0d,%0d): label=%0d vc=%0d time=%0t",
                 dest_flits_seen, x, y, data_o[x][y].flit_label, data_o[x][y].vc_id, $time);

        if(x != x_dest || y != y_dest)
        begin
            $error("[TB_MESH_EIGHT_PACKETS] flit arrived at wrong node (%0d,%0d), expected (%0d,%0d)",
                   x, y, x_dest, y_dest);
        end

        if(dest_flits_seen >= EXPECTED_FLITS)
        begin
            $error("[TB_MESH_EIGHT_PACKETS] unexpected extra output flit");
        end
        else if(data_o[x][y].flit_label !== expected_label)
        begin
            $error("[TB_MESH_EIGHT_PACKETS] flit %0d label mismatch: got %0d expected %0d",
                   dest_flits_seen, data_o[x][y].flit_label, expected_label);
        end

        if(data_o[x][y].flit_label == HEAD)
        begin
            observed_pkt_id = data_o[x][y].data.head_data.head_pl;
            if(data_o[x][y].data.head_data.x_dest !== x_dest ||
               data_o[x][y].data.head_data.y_dest !== y_dest ||
               observed_pkt_id != expected_pkt_id)
            begin
                $error("[TB_MESH_EIGHT_PACKETS] HEAD flit %0d fields are wrong, packet_id=%0d expected=%0d",
                       dest_flits_seen, observed_pkt_id, expected_pkt_id);
            end
        end
        else if(data_o[x][y].flit_label == TAIL)
        begin
            observed_pkt_id = data_o[x][y].data.bt_pl;
            if(observed_pkt_id != expected_pkt_id)
            begin
                $error("[TB_MESH_EIGHT_PACKETS] TAIL flit %0d packet_id=%0d expected=%0d",
                       dest_flits_seen, observed_pkt_id, expected_pkt_id);
            end
        end

        dest_flits_seen++;
    endtask

    task final_checks();
        if(dest_flits_seen != EXPECTED_FLITS)
            $error("[TB_MESH_EIGHT_PACKETS] expected %0d output flits at destination, saw %0d",
                   EXPECTED_FLITS, dest_flits_seen);
        if(error_seen != 0)
            $error("[TB_MESH_EIGHT_PACKETS] observed %0d error_o assertions", error_seen);
        if(dest_flits_seen == EXPECTED_FLITS && error_seen == 0)
            $display("[TB_MESH_EIGHT_PACKETS] PASSED");
    endtask

endmodule
