`timescale 1ns/1ps
import noc_params::*;
//Modify directly verify ready-only joint allocation, legal alternatives, round-robin and ownership masks, Michael Tan, 20261029
module tb_oe_ready_directed;
    parameter POLICY_MODE=1,FAST_REOPEN=0;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] returned,ready;
    logic [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] cost;
    input_block2vc_allocator ib();
    vc_allocator dut(.clk(clk),.rst(rst),.idle_downstream_vc_i(returned),
        .downstream_on_off_i(ready),.next_input_occupancy_i(cost),.ib_if(ib));
    int checks=0;
    task automatic check(input bit ok,input string message);
        checks++;
        if(!ok) $fatal(1,"[READY_DIRECTED] %s",message);
    endtask
    task automatic clear_requests;
        for(int p=0;p<PORT_NUM;p++) begin
            ib.vc_request[p]='0;
            for(int v=0;v<VC_NUM;v++) begin ib.out_port[p][v]=EAST;ib.candidates[p][v]='0;end
        end
    endtask
    task automatic reset_case;
        @(negedge clk);rst=1;returned='0;ready='0;cost='0;clear_requests();
        repeat(3) @(negedge clk);rst=0;
    endtask
    task automatic issue(input logic [PORT_NUM-1:0] mask,input port_t expected,input int expected_vc=-1);
        int chosen,count;
        @(negedge clk);ib.vc_request[LOCAL][0]=1;ib.candidates[LOCAL][0]=mask;
        #1;count=0;
        for(int p=0;p<PORT_NUM;p++) count+=$countones(ib.vc_valid[p]);
        check(count==1 && ib.vc_valid[LOCAL][0]===1,"one request must produce exactly one grant");
        check(ib.granted_port[LOCAL][0]===expected,"wrong candidate output");
        chosen=int'(ib.vc_new[LOCAL][0]);
        check(mask[expected] && ready[expected][chosen] && dut.is_available_vc[expected][chosen],"grant must be legal, writable and unowned");
        if(expected_vc>=0) check(chosen==expected_vc,"wrong ready VC");
        @(posedge clk);#1;check(!dut.is_available_vc[expected][chosen],"grant did not reserve resource");
        @(negedge clk);clear_requests();
    endtask
    initial begin
        logic [PORT_NUM-1:0] pair,south_only;
        check(POLICY_MODE==dut.SELECTION_MODE && POLICY_MODE!=0,"active test mode mismatch");
        pair='0;pair[EAST]=1;pair[SOUTH]=1;south_only='0;south_only[SOUTH]=1;
        reset_case();ready[SOUTH]='1;
        issue(pair,SOUTH,0); // Original EAST preference is closed; SOUTH must be used.
        @(negedge clk);ready='0;ib.vc_request[LOCAL][0]=1;ib.candidates[LOCAL][0]=pair;
        repeat(6) begin
            @(posedge clk);#1;
            for(int p=0;p<PORT_NUM;p++) check(ib.vc_valid[p]==='0,"no eligible output may reserve no VC");
        end
        @(negedge clk);clear_requests();ready[EAST]='1;ready[SOUTH]='1;cost[EAST]=8;cost[SOUTH]=1;
        issue(pair,POLICY_MODE==2?SOUTH:EAST); // Mode1 rotates; mode2 takes the lower-cost eligible candidate.
        @(negedge clk);ready='0;ready[SOUTH][3]=1;
        issue(south_only,SOUTH,3);
        reset_case();ready[EAST]='1;
        for(int v=0;v<VC_NUM;v++) issue(5'b10000,EAST,v);
        @(negedge clk);ib.vc_request[LOCAL][0]=1;ib.candidates[LOCAL][0]='1;
        #1;check(ib.vc_valid[LOCAL][0]===0,"writable but already owned VCs cannot be reused");
        @(negedge clk);returned[EAST][2]=1;
        @(posedge clk);#1;
        check(ib.vc_valid[LOCAL][0]===1 && ib.vc_new[LOCAL][0]==2,"explicit ownership return did not restore only VC2");
        @(negedge clk);returned='0;clear_requests();
        $display("[TB_OE_READY_DIRECTED] PASSED policy=%0d checks=%0d",POLICY_MODE,checks);
        $finish;
    end
    initial begin #10000;$fatal(1,"ready directed timeout");end
endmodule
