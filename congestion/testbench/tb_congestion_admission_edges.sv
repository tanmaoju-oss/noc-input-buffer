`timescale 1ns/1ps
import noc_params::*;
//Modify check rejected tails, simultaneous ingress/egress, metadata wrap and reset ownership, Michael Tan, 20261029
module tb_congestion_admission_edges;
    logic clk=0,rst=1,wr=0,rd=0,allocate=0;
    always #5 clk=~clk;
    flit_novc_t din;
    flit_t dout;
    wire full_flag,empty_flag,on_off,release_vc,error_flag,va_request,sa_request;
    wire port_t route;
    wire [VC_SIZE-1:0] downstream;
    wire [3:0] occupancy;
    int steps=0;
    input_buffer #(.BUFFER_SIZE(8)) dut(.clk(clk),.rst(rst),.data_i(din),.write_i(wr),.read_i(rd),
        .vc_new_i(VC_SIZE'(2)),.vc_valid_i(allocate),.out_port_i(EAST),.data_o(dout),
        .is_full_o(full_flag),.is_empty_o(empty_flag),.on_off_o(on_off),.out_port_o(route),
        .vc_request_o(va_request),.switch_request_o(sa_request),.vc_allocatable_o(release_vc),
        .downstream_vc_o(downstream),.error_o(error_flag),.priority_usage_o(occupancy));
    task automatic check(input bit condition,input string message);
        if(!condition) $fatal(1,"[ADMISSION_EDGES] step=%0d %s",steps,message);
    endtask
    task automatic reset_case;
        @(negedge clk);rst=1;wr=0;rd=0;allocate=0;din='0;
        repeat(3) @(negedge clk);rst=0;
        @(posedge clk);#1;
        check(occupancy==0 && release_vc===0 && error_flag===0,"reset state");
    endtask
    task automatic step(input bit w,input flit_label_t lab,input bit r,a,err,returned,
                        input int count,packets,input flit_label_t read_label=HEAD);
        @(negedge clk);wr=w;rd=r;allocate=a;din='0;din.flit_label=lab;din.data='1;
        #1;
        if(r) check(dout.flit_label===read_label && sa_request,"output head/sequence before transfer");
        @(posedge clk);#1;steps++;
        check(error_flag===err,"unexpected error status");
        check(release_vc===returned,"incorrect ownership return");
        check(occupancy==count && dut.num_packets==packets,"flit/metadata count");
    endtask
    initial begin
        reset_case();
        step(1,HEAD,0,0,0,0,1,1);
        step(1,HEAD,0,0,1,0,1,1); // Illegal interleaved HEAD cannot return ownership.
        step(1,BODY,0,0,0,0,2,1);
        step(1,TAIL,0,0,0,1,3,1);
        step(0,BODY,0,0,0,0,3,1);
        step(1,TAIL,0,0,1,0,3,1);
        step(1,HEADTAIL,0,0,0,1,4,2);
        step(0,BODY,0,1,0,0,4,2);
        step(0,BODY,1,0,0,0,3,2,HEAD);
        step(0,BODY,1,0,0,0,2,2,BODY);
        step(1,HEAD,1,0,0,0,2,2,TAIL); // Push and pop different packets together.
        step(1,TAIL,0,1,0,1,3,2);
        step(0,BODY,1,0,0,0,2,1,HEADTAIL);
        step(0,BODY,0,1,0,0,2,1);
        step(0,BODY,1,0,0,0,1,1,HEAD);
        step(0,BODY,1,0,0,0,0,0,TAIL);
        step(1,TAIL,0,0,1,0,0,0);
        // Drive beyond on_off deliberately to verify a full FIFO rejects TAIL without freeing ownership.
        reset_case();step(1,HEAD,0,0,0,0,1,1);
        for(int k=2;k<=8;k++) step(1,BODY,0,0,0,0,k,1);
        step(1,TAIL,0,0,1,0,8,1);
        step(0,BODY,0,1,0,0,8,1);
        step(0,BODY,1,0,0,0,7,1,HEAD);
        step(1,TAIL,1,0,0,1,7,1,BODY);
        for(int k=6;k>=1;k--) step(0,BODY,1,0,0,0,k,1,BODY);
        step(0,BODY,1,0,0,0,0,0,TAIL);
        // Repeated HEADTAIL push/pop wraps both metadata pointers and never double-returns on read.
        for(int k=0;k<20;k++) begin
            step(1,HEADTAIL,0,0,0,1,1,1);
            step(0,BODY,0,1,0,0,1,1);
            step(0,BODY,1,0,0,0,0,0,HEADTAIL);
        end
        step(1,HEAD,0,0,0,0,1,1);reset_case();
        step(1,HEADTAIL,0,0,0,1,1,1);
        step(0,BODY,0,1,0,0,1,1);
        step(0,BODY,1,0,0,0,0,0,HEADTAIL);
        $display("[TB_CONGESTION_ADMISSION_EDGES] PASSED steps=%0d rejects/simultaneous/full_tail/wrap/reset",steps);
        $finish;
    end
    initial begin #100000;$fatal(1,"edge regression timeout");end
endmodule
