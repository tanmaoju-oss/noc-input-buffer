`timescale 1ns/1ps
import noc_params::*;
//Modify independently verify replicated dateline phase resources, Michael Tan, 20261104
//Modify directed allocator eligibility and queued-packet metadata regression, Michael Tan, 20261102
module tb_torus_phase_vc_allocator;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic [PORT_NUM-1:0][VC_NUM-1:0] idle;
    input_block2vc_allocator ib();
    vc_allocator dut(.clk(clk),.rst(rst),.idle_downstream_vc_i(idle),.ib_if(ib));
    flit_novc_t data;
    flit_t out_data;
    logic rd,wr,valid;
    logic [VC_SIZE-1:0] new_vc;
    logic [VC_NUM-1:0] mask_in,mask_out;
    port_t out_port;
    logic req,sw,free_vc,err,full,empty,onoff;
    logic [VC_SIZE-1:0] down_vc;
    input_buffer buffer_dut(.clk(clk),.rst(rst),.data_i(data),.read_i(rd),.write_i(wr),
        .vc_new_i(new_vc),.vc_valid_i(valid),.out_port_i(EAST),
        .allowed_vcs_i(mask_in),.allowed_vcs_o(mask_out),.data_o(out_data),
        .is_full_o(full),.is_empty_o(empty),.on_off_o(onoff),.out_port_o(out_port),
        .vc_request_o(req),.switch_request_o(sw),.vc_allocatable_o(free_vc),
        .downstream_vc_o(down_vc),.error_o(err));
    int grants=0;
    always @(posedge clk) if(!rst) begin
        if(err) $fatal(1,"buffer error");
        for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++)
            if(ib.vc_valid[p][v]) begin
                if(!ib.allowed_vcs[p][v][ib.vc_new[p][v]]) $fatal(1,"illegal allocator grant");
                grants++;
            end
    end
    task automatic clear_requests;
        for(int p=0;p<PORT_NUM;p++) begin
            ib.vc_request[p]=0;
            for(int v=0;v<VC_NUM;v++) begin ib.allowed_vcs[p][v]=0; ib.out_port[p][v]=EAST; end
        end
    endtask
    task automatic allocate_once(input int port_id, source_vc, target_vc);
        @(negedge clk);
        ib.vc_request[port_id][source_vc]=1;
        ib.allowed_vcs[port_id][source_vc]=1<<target_vc;
        #1;
        if(!ib.vc_valid[port_id][source_vc] || ib.vc_new[port_id][source_vc]!=target_vc)
            $fatal(1,"eligible allocation missing");
        @(posedge clk); @(negedge clk); clear_requests();
    endtask
    initial begin
        idle=0; rd=0;wr=0;valid=0;data='0;mask_in=0;new_vc=0;clear_requests();
        repeat(3) @(negedge clk); rst=0;
        allocate_once(LOCAL,0,1);
        @(negedge clk); ib.vc_request[LOCAL][0]=1;ib.allowed_vcs[LOCAL][0]=4'b0010;
        repeat(4) begin @(posedge clk); #1;
            if(ib.vc_valid[LOCAL][0]) $fatal(1,"allocated illegal free VC while legal VC busy");
        end
        @(negedge clk); idle[EAST][1]=1;
        @(posedge clk); @(negedge clk); idle=0; #1;
        if(!ib.vc_valid[LOCAL][0] || ib.vc_new[LOCAL][0]!=1) $fatal(1,"release/reallocate failed");
        @(posedge clk); @(negedge clk); clear_requests();
        ib.vc_request[NORTH][0]=1;ib.allowed_vcs[NORTH][0]=0;
        repeat(3) begin @(posedge clk); #1; if(ib.vc_valid[NORTH][0]) $fatal(1,"zero mask granted"); end
        @(negedge clk); clear_requests();
        // Queue headers with different classes before granting the first packet.
        data.flit_label=HEADTAIL;data.data.bt_pl=11;mask_in=VC_BEFORE_MASK;wr=1;
        @(negedge clk);data.data.bt_pl=22;mask_in=VC_AFTER_MASK;
        @(negedge clk);wr=0;mask_in=4'b0100;
        #1; if(mask_out!=VC_BEFORE_MASK || !req) $fatal(1,"first queued mask corrupted");
        valid=1;new_vc=1;
        @(negedge clk);valid=0;rd=1;
        #1;if(out_data.data.bt_pl!=11 || out_data.vc_id!=1) $fatal(1,"first packet metadata");
        @(negedge clk);rd=0;
        #1;if(mask_out!=VC_AFTER_MASK || !req || out_data.data.bt_pl!=22) $fatal(1,"second queued mask lost");
        valid=1;new_vc=VC_NUM-1;
        @(negedge clk);valid=0;rd=1;
        #1;if(out_data.vc_id!=VC_NUM-1) $fatal(1,"second downstream VC");
        @(negedge clk);rd=0;
        #1;if(!empty || req || sw) $fatal(1,"buffer failed drain");
        //Modify exhaust every before-phase replica while after-phase replicas remain free, Michael Tan, 20261104
        @(negedge clk);rst=1;clear_requests();idle=0;
        repeat(3) @(negedge clk);rst=0;
        for(int replica=0;replica<TORUS_VCS_PER_PHASE;replica++) begin
            @(negedge clk);ib.vc_request[LOCAL][0]=1;ib.allowed_vcs[LOCAL][0]=VC_BEFORE_MASK;
            #1;if(!ib.vc_valid[LOCAL][0] || int'(ib.vc_new[LOCAL][0])!=replica) $fatal(1,"phase replica not used");
            @(posedge clk);@(negedge clk);clear_requests();
        end
        @(negedge clk);ib.vc_request[LOCAL][0]=1;ib.allowed_vcs[LOCAL][0]=VC_BEFORE_MASK;
        repeat(3) begin @(posedge clk);#1;if(ib.vc_valid[LOCAL][0]) $fatal(1,"cross-phase illegal fallback");end
        @(negedge clk);idle[EAST][TORUS_VCS_PER_PHASE-1]=1;
        @(posedge clk);@(negedge clk);idle=0;#1;
        if(!ib.vc_valid[LOCAL][0] || int'(ib.vc_new[LOCAL][0])!=TORUS_VCS_PER_PHASE-1) $fatal(1,"replica release/reuse failed");
        @(posedge clk);@(negedge clk);clear_requests();
        $display("[TB_TORUS_PHASE_VC_ALLOCATOR] PASSED grants=%0d metadata_packets=2",grants);
        $finish;
    end
    initial begin #10000; $fatal(1,"VA timeout"); end
endmodule
