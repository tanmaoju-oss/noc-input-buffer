`timescale 1ns / 1ps

import noc_params::*;

module tb_mesh #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 2,
    parameter MESH_SIZE_Y = 3
);
    /*
    Input signals
    */
    logic clk;
    logic rst;
    /*
    Connections to all local Router interfaces
    */
    //Selected inputs
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_cmd; //downstream
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_cmd; //downstream
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_cmd;//upstream
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_cmd;//upstream 
    //Observable outputs
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o;
    logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0];
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o;
    //Testbench values
    flit_t flit_queue[MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][$];
    int x_from, y_from, x_dest, y_dest, num_op;
    int dest_flits_seen, error_seen;
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0]flits_written;

    //DUT Instantiation
    mesh #(
        .BUFFER_SIZE(8),
        .MESH_SIZE_X(2),
        .MESH_SIZE_Y(3)
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
        test();
        
        #100;
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
        $dumpvars(0, tb_mesh);
    endtask

    /*
    Initialize signals we interact with the upstream and downstream router
    */
    task initialize();
        clk             <= 0;
        rst             = 1;
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
            is_on_off_cmd[x][y] = {VC_NUM{1'b1}};
            is_allocatable_cmd[x][y] = {VC_NUM{1'b0}};
            is_valid_cmd[x][y] = 1'b0;
            end
        end
        num_op = 0;
        dest_flits_seen = 0;
        error_seen = 0;
    endtask
    
    /*
    Clear the reset signal
    */
    task clr_rst();
        @(posedge clk);
            rst <= 0;
    endtask

    task test();
        /*
        2 flit packet
        */
        x_from = 0;
        y_from = 0;
        x_dest = 1;
        y_dest = 2;
        @(posedge clk)
        //set upstream values
        write_flit(x_from, y_from, HEAD,0);
        //set downstream values
        is_allocatable_cmd[x_dest][y_dest] = {VC_NUM{1'b1}};
        is_on_off_cmd[x_dest][y_dest] ={VC_NUM{1'b1}};
        @(posedge clk)
        //write_flit(1,0,TAIL,0);
        write_flit(x_from, y_from, TAIL, 0);
        is_allocatable_cmd[x_dest][y_dest] ={VC_NUM{1'b1}};
        is_on_off_cmd[x_dest][y_dest] = {VC_NUM{1'b1}};
        @(posedge clk)
            is_valid_cmd[x_from][y_from]  = 1'b0;

    endtask

    task monitor_outputs();
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                if(is_valid_o[x][y])
                begin
                    $display("[TB_MESH] output flit %0d at (%0d,%0d): label=%0d vc=%0d time=%0t",
                             dest_flits_seen, x, y, data_o[x][y].flit_label, data_o[x][y].vc_id, $time);

                    if(x != x_dest || y != y_dest)
                    begin
                        $error("[TB_MESH] flit arrived at wrong node (%0d,%0d), expected (%0d,%0d)",
                               x, y, x_dest, y_dest);
                    end

                    if(dest_flits_seen == 0)
                    begin
                        if(data_o[x][y].flit_label !== HEAD)
                            $error("[TB_MESH] first output flit is not HEAD");
                        if(data_o[x][y].data.head_data.x_dest !== x_dest ||
                           data_o[x][y].data.head_data.y_dest !== y_dest)
                            $error("[TB_MESH] HEAD destination fields are wrong");
                    end
                    else if(dest_flits_seen == 1)
                    begin
                        if(data_o[x][y].flit_label !== TAIL)
                            $error("[TB_MESH] second output flit is not TAIL");
                    end
                    else
                    begin
                        $error("[TB_MESH] unexpected extra output flit");
                    end

                    dest_flits_seen++;
                end

                for(int port=0; port < PORT_NUM; port++)
                begin
                    for(int vc=0; vc < VC_NUM; vc++)
                    begin
                        if(error_o[x][y][port][vc] === 1'b1)
                        begin
                            error_seen++;
                            $error("[TB_MESH] error_o asserted at node=(%0d,%0d) port=%0d vc=%0d time=%0t",
                                   x, y, port, vc, $time);
                        end
                    end
                end
            end
        end
    endtask

    task final_checks();
        if(dest_flits_seen != 2)
            $error("[TB_MESH] expected 2 output flits at destination, saw %0d", dest_flits_seen);
        if(error_seen != 0)
            $error("[TB_MESH] observed %0d error_o assertions", error_seen);
        if(dest_flits_seen == 2 && error_seen == 0)
            $display("[TB_MESH] PASSED");
    endtask

    task create_flit(input int x, input int y,input flit_label_t lab, input vc_num);
        flits_written[x][y].flit_label = lab;
        flits_written[x][y].vc_id      = vc_num;
        if(lab == HEAD | lab == HEADTAIL)
            begin
                flits_written[x][y].data.head_data.x_dest  = x_dest;
                flits_written[x][y].data.head_data.y_dest  = y_dest;
                flits_written[x][y].data.head_data.head_pl = {HEAD_PAYLOAD_SIZE{num_op}};
            end
        else
            flits_written[x][y].data.bt_pl = {FLIT_DATA_SIZE{num_op}};
    endtask
    
    
    
    task write_flit(input int x, input int y, input flit_label_t lab, input vc_num);
        begin
            create_flit(x,y,lab, vc_num);
            is_valid_cmd[x][y]  = 1'b1;
            data_cmd[x][y]      = flits_written[x][y];
            flit_queue[x][y].push_back(flits_written[x][y]);
        end
        num_op++;
    endtask

endmodule
