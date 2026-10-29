`timescale 1ns/1ps
import noc_params::*;
//Modify require progress for a continuously writable VC under a legal persistent switch-request graph, Michael Tan, 20261029
module tb_oe_aged_sa_fairness;
    parameter POLICY_MODE=5,FAST_REOPEN=1,SA_FULL=1,AGE_GUARD=1;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] ready='1;
    wire [PORT_NUM-1:0] valid;
    input_block2switch_allocator ib();switch_allocator2crossbar xb();
    switch_allocator dut(.clk(clk),.rst(rst),.on_off_i(ready),.ib_if(ib),.xbar_if(xb),.valid_flit_o(valid));
    int waited=0,target_transfers=0,other_transfers=0;
    initial begin
        for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            ib.switch_request[p][v]=0;ib.out_port[p][v]=LOCAL;ib.downstream_vc[p][v]=VC_SIZE'(v);
        end
        repeat(4) @(negedge clk);rst=0;
        @(negedge clk);
        ib.switch_request[LOCAL][0]=1;ib.out_port[LOCAL][0]=EAST;
        ib.switch_request[LOCAL][1]=1;ib.out_port[LOCAL][1]=SOUTH;
        ib.switch_request[NORTH][0]=1;ib.out_port[NORTH][0]=EAST;
        // Maximum cardinality is two only if LOCAL/VC0 is skipped; fairness must sometimes sacrifice one grant.
        for(int cycle=0;cycle<128;cycle++) begin
            @(posedge clk);
            if(ib.valid_sel[LOCAL] && ib.vc_sel[LOCAL]==0) begin target_transfers++;waited=0;end
            else waited++;
            other_transfers+=$countones(valid)-(ib.valid_sel[LOCAL] && ib.vc_sel[LOCAL]==0);
            if(waited>PORT_NUM*VC_NUM*2) begin
                $display("[FAIRNESS_COUNTEREXAMPLE] target=%0d others=%0d waited=%0d",target_transfers,other_transfers,waited);
                $fatal(1,"continuously writable VC starved behind maximum-cardinality matching");
            end
            #1;
        end
        if(target_transfers==0) $fatal(1,"no target progress");
        $display("[TB_OE_AGED_SA_FAIRNESS] PASSED target_transfers=%0d other_transfers=%0d",target_transfers,other_transfers);
        $finish;
    end
    initial begin #10000;$fatal(1,"fairness timeout");end
endmodule
