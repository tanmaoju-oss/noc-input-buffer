`timescale 1ns/1ps
import noc_params::*;
//Modify check bounded RTL matching against independent exhaustive assignment enumeration, Michael Tan, 20261029
module tb_oe_matching_unit;
    parameter POLICY_MODE=3,FAST_REOPEN=0;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] returned='0,ready='1;
    logic [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] cost='0;
    logic [PORT_NUM-1:0] edges[PORT_NUM];
    input_block2vc_allocator ib();
    vc_allocator dut(.clk(clk),.rst(rst),.idle_downstream_vc_i(returned),
        .downstream_on_off_i(ready),.next_input_occupancy_i(cost),.ib_if(ib));
    int cases=0;
    function automatic int optimum(input int p,input logic [PORT_NUM-1:0] occupied);
        int best,trial;
        logic [PORT_NUM-1:0] used;
        if(p==PORT_NUM) return 0;
        best=optimum(p+1,occupied);
        for(int d=0;d<PORT_NUM;d++) if(edges[p][d] && !occupied[d]) begin
            used=occupied;used[d]=1;
            trial=1+optimum(p+1,used);if(trial>best) best=trial;
        end
        return best;
    endfunction
    task automatic run_case(input int code,kind);
        int actual,expected,per_input,vc,outp;
        int used_outputs;
        int unsigned key;
        @(negedge clk);rst=1;returned='0;ready='1;cost='0;
        for(int p=0;p<PORT_NUM;p++) begin
            edges[p]='0;ib.vc_request[p]='0;
            for(int v=0;v<VC_NUM;v++) begin ib.out_port[p][v]=EAST;ib.candidates[p][v]='0;end
        end
        repeat(3) @(negedge clk);rst=0;
        @(negedge clk);
        for(int p=0;p<PORT_NUM;p++) begin
            if(kind==0 && p<3) for(int d=0;d<3;d++) edges[p][d]=(code>>(p*3+d))&1;
            if(kind==1) begin
                key=32'(code+1)*32'h9e3779b9^32'(p+1)*32'h85ebca6b;
                edges[p]=(key^(key>>7)^(key>>15));
            end
            if(kind==2) begin
                if(p==0) begin edges[p][SOUTH]=1;edges[p][EAST]=1;end
                if(p==1) edges[p][SOUTH]=1;
                cost[EAST]=8;cost[SOUTH]=1;
            end
            vc=(p+code)%VC_NUM;
            ib.vc_request[p][vc]=|edges[p];ib.candidates[p][vc]=edges[p];
        end
        #1;expected=optimum(0,'0);actual=0;used_outputs=0;
        for(int p=0;p<PORT_NUM;p++) begin
            per_input=0;
            for(int v=0;v<VC_NUM;v++) if(ib.vc_valid[p][v]) begin
                actual++;per_input++;outp=int'(ib.granted_port[p][v]);
                if(!ib.vc_request[p][v] || !ib.candidates[p][v][outp] || !ready[outp][ib.vc_new[p][v]]) $fatal(1,"illegal match");
                if((used_outputs>>outp)&1) $fatal(1,"duplicate output match");
                used_outputs|=1<<outp;
            end
            if(per_input>1) $fatal(1,"duplicate input match");
        end
        if(actual!=expected) $fatal(1,"nonmaximum matching kind=%0d code=%0d actual=%0d expected=%0d",kind,code,actual,expected);
        if(kind==2 && actual!=2) $fatal(1,"augmenting path not exercised");
        @(posedge clk);#1;cases++;
    endtask
    initial begin
        if(POLICY_MODE!=3 || dut.SELECTION_MODE!=3) $fatal(1,"matching mode required");
        for(int g=0;g<512;g++) run_case(g,0);
        for(int g=0;g<64;g++) run_case(g,1);
        run_case(0,2);
        $display("[TB_OE_MATCHING_UNIT] PASSED graphs=%0d exhaustive_3x3=512 random_5x5=64 augmenting=1",cases);
        $finish;
    end
    initial begin #100000;$fatal(1,"matching unit timeout");end
endmodule
