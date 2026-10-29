`timescale 1ns/1ps
import noc_params::*;
//Modify verify switch matching cardinality against independent exhaustive assignments with real four-VC edge limits, Michael Tan, 20261029
module tb_oe_sa_matching_unit;
    parameter POLICY_MODE=5,FAST_REOPEN=1,SA_FULL=1;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] ready='1;
    logic [PORT_NUM-1:0] edges[PORT_NUM];
    wire [PORT_NUM-1:0] transferred;
    input_block2switch_allocator ib();
    switch_allocator2crossbar xb();
    switch_allocator dut(.clk(clk),.rst(rst),.on_off_i(ready),.ib_if(ib),.xbar_if(xb),.valid_flit_o(transferred));
    int cases=0;
    function automatic int optimum(input int p,input logic [PORT_NUM-1:0] occupied);
        int best,trial;
        logic [PORT_NUM-1:0] used;
        if(p==PORT_NUM) return 0;
        best=optimum(p+1,occupied);
        for(int d=0;d<PORT_NUM;d++) if(edges[p][d] && !occupied[d]) begin
            used=occupied;used[d]=1;trial=1+optimum(p+1,used);if(trial>best) best=trial;
        end
        return best;
    endfunction
    task automatic run_case(input int code,kind);
        int actual,expected,outp,vin,n,used_outputs;
        int unsigned key;
        logic [PORT_NUM-1:0] mask;
        @(negedge clk);rst=1;ready='1;
        for(int p=0;p<PORT_NUM;p++) begin
            edges[p]='0;
            for(int v=0;v<VC_NUM;v++) begin ib.switch_request[p][v]=0;ib.out_port[p][v]=LOCAL;ib.downstream_vc[p][v]=VC_SIZE'(v);end
        end
        repeat(3) @(negedge clk);rst=0;
        @(negedge clk);
        if(kind==3) ready[code%PORT_NUM][code%VC_NUM]=0;
        for(int p=0;p<PORT_NUM;p++) begin
            mask='0;
            if(kind==0 && p<3) for(int d=0;d<3;d++) mask[d]=(code>>(p*3+d))&1;
            if(kind==1 || kind==3) begin
                key=32'(code+1)*32'h9e3779b9^32'(p+1)*32'h85ebca6b;
                mask=(key^(key>>7)^(key>>15));
                if($countones(mask)>VC_NUM) mask[(p+code)%PORT_NUM]=0;
            end
            if(kind==2) begin
                if(p==0) begin mask[SOUTH]=1;mask[EAST]=1;end
                if(p==1) mask[SOUTH]=1;
            end
            n=0;
            for(int d=0;d<PORT_NUM;d++) if(mask[d]) begin
                vin=(n+p+code)%VC_NUM;n++;
                ib.switch_request[p][vin]=1;ib.out_port[p][vin]=port_t'(d);
                if(ready[d][vin]) edges[p][d]=1;
            end
        end
        #1;expected=optimum(0,'0);actual=0;used_outputs=0;
        for(int p=0;p<PORT_NUM;p++) if(ib.valid_sel[p]) begin
            vin=int'(ib.vc_sel[p]);outp=int'(ib.out_port[p][vin]);actual++;
            if(!ib.switch_request[p][vin] || !ready[outp][ib.downstream_vc[p][vin]] || !transferred[outp] || xb.input_vc_sel[outp]!=p) $fatal(1,"invalid switch/crossbar grant");
            if((used_outputs>>outp)&1) $fatal(1,"duplicate switch output");used_outputs|=1<<outp;
        end
        if(actual!=expected || $countones(transferred)!=actual) $fatal(1,"SA nonmaximum kind=%0d code=%0d got=%0d expected=%0d",kind,code,actual,expected);
        @(posedge clk);#1;cases++;
    endtask
    initial begin
        if(!SA_FULL || !dut.FULL_MATCHING) $fatal(1,"full SA matching required");
        for(int g=0;g<512;g++) run_case(g,0);
        for(int g=0;g<64;g++) run_case(g,1);
        run_case(0,2);
        for(int g=0;g<16;g++) run_case(g,3);
        $display("[TB_OE_SA_MATCHING_UNIT] PASSED graphs=%0d exhaustive_3x3=512 random_5x5=64 fork=1 backpressure=16",cases);
        $finish;
    end
    initial begin #100000;$fatal(1,"SA oracle timeout");end
endmodule
