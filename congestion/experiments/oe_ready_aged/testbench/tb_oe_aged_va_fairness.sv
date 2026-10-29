`timescale 1ns/1ps
import noc_params::*;
//Modify require head-VC progress under sustained competing allocation streams and explicit delayed returns, Michael Tan, 20261029
module tb_oe_aged_va_fairness;
    parameter POLICY_MODE=5,FAST_REOPEN=1,SA_FULL=1,AGE_GUARD=1;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] returned='0,ready='1,stage0='0,stage1='0,stage2='0;
    logic [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] cost='0;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    input_block2vc_allocator ib();
    vc_allocator #(.X_CURRENT(2),.Y_CURRENT(1)) dut(.clk(clk),.rst(rst),.idle_downstream_vc_i(returned),
        .downstream_on_off_i(ready),.next_input_occupancy_i(cost),.metrics_i(metrics),.ib_if(ib));
    int waited=0,target=0;
    always @(negedge clk) returned=stage2;
    initial begin
        for(int p=0;p<PORT_NUM;p++) begin
            ib.vc_request[p]='0;
            for(int v=0;v<VC_NUM;v++) begin
                ib.candidates[p][v]='0;ib.out_port[p][v]=EAST;
                ib.head_source_x[p][v]=2;ib.head_dest_x[p][v]=5;ib.head_dest_y[p][v]=4;
            end
        end
        repeat(4) @(negedge clk);rst=0;
        @(negedge clk);
        ib.vc_request[LOCAL]='1;ib.vc_request[NORTH]='1;
        ib.candidates[LOCAL][0][EAST]=1;
        for(int v=1;v<VC_NUM;v++) ib.candidates[LOCAL][v][SOUTH]=1;
        for(int v=0;v<VC_NUM;v++) ib.candidates[NORTH][v][EAST]=1;
        for(int cycle=0;cycle<128;cycle++) begin
            @(posedge clk);
            if(ib.vc_valid[LOCAL][0]) begin target++;waited=0;end else waited++;
            stage2=stage1;stage1=stage0;stage0='0;
            for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) if(ib.vc_valid[p][v])
                stage0[ib.granted_port[p][v]][ib.vc_new[p][v]]=1;
            if(waited>PORT_NUM*VC_NUM*2) $fatal(1,"continuously eligible VA head starved");
            #1;
        end
        if(target==0) $fatal(1,"no head progress");
        $display("[TB_OE_AGED_VA_FAIRNESS] PASSED target_grants=%0d",target);
        $finish;
    end
    initial begin #10000;$fatal(1,"VA fairness timeout");end
endmodule
