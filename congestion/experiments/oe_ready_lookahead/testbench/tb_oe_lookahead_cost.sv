`timescale 1ns/1ps
import noc_params::*;
//Modify test a fixed legal two-hop ranking counterexample and exact destination truncation, Michael Tan, 20261029
module tb_oe_lookahead_cost;
    parameter POLICY_MODE=4,FAST_REOPEN=0;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] returned='0,ready='1;
    logic [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] cost='0;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    input_block2vc_allocator ib();
    vc_allocator #(.X_CURRENT(2),.Y_CURRENT(1)) dut(.clk(clk),.rst(rst),.idle_downstream_vc_i(returned),
        .downstream_on_off_i(ready),.next_input_occupancy_i(cost),.metrics_i(metrics),.ib_if(ib));
    task automatic initialize_case;
        @(negedge clk);rst=1;metrics='0;cost='0;
        for(int p=0;p<PORT_NUM;p++) begin
            ib.vc_request[p]='0;
            for(int v=0;v<VC_NUM;v++) begin
                ib.candidates[p][v]='0;ib.out_port[p][v]=EAST;
                ib.head_source_x[p][v]=2;ib.head_dest_x[p][v]=5;ib.head_dest_y[p][v]=3;
            end
        end
        repeat(3) @(negedge clk);rst=0;
    endtask
    task automatic request_pair(input port_t expected);
        @(negedge clk);ib.vc_request[LOCAL][0]=1;ib.candidates[LOCAL][0]='0;
        ib.candidates[LOCAL][0][EAST]=1;ib.candidates[LOCAL][0][SOUTH]=1;
        #1;
        if(ib.vc_valid[LOCAL][0]!==1 || ib.granted_port[LOCAL][0]!==expected) $fatal(1,"wrong two-hop choice");
        @(negedge clk);ib.vc_request[LOCAL]='0;
    endtask
    initial begin
        if(POLICY_MODE!=4 || dut.SELECTION_MODE!=4) $fatal(1,"two-hop mode required");
        initialize_case();
        metrics[3][1].per_dir_total_occupancy[WEST]=0;
        metrics[2][2].per_dir_total_occupancy[NORTH]=1;
        metrics[4][1].per_dir_total_occupancy[WEST]=10;
        metrics[3][2].per_dir_total_occupancy[NORTH]=10;
        #1;
        if(dut.route_cost(LOCAL,0,EAST)!=10 || dut.route_cost(LOCAL,0,SOUTH)!=1) $fatal(1,"two-hop costs incorrect");
        request_pair(SOUTH); // One-hop-only would select EAST; legal continuation makes SOUTH cheaper.
        initialize_case();metrics[2][2].per_dir_total_occupancy[NORTH]=1;
        request_pair(EAST);
        initialize_case();ib.head_dest_x[LOCAL][0]=3;ib.head_dest_y[LOCAL][0]=1;
        metrics[3][1].per_dir_total_occupancy[WEST]=2;
        metrics[4][1].per_dir_total_occupancy[WEST]=31;
        #1;if(dut.route_cost(LOCAL,0,EAST)!=2 || dut.route_cost(LOCAL,0,LOCAL)!=0) $fatal(1,"destination truncation incorrect");
        $display("[TB_OE_LOOKAHEAD_COST] PASSED first_vs_second_hop/destination/local");
        $finish;
    end
    initial begin #10000;$fatal(1,"lookahead unit timeout");end
endmodule
