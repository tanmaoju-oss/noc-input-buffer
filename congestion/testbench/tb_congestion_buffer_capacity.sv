`timescale 1ns/1ps
import noc_params::*;
//Modify verify congestion buffer capacity, tail release and restored flow control, Michael Tan, 20261028
module tb_congestion_buffer_capacity;
    localparam DEPTH=8;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    flit_t data_i[PORT_NUM-1:0];
    logic valid_i[PORT_NUM-1:0];
    logic [VC_NUM-1:0] on_off[PORT_NUM-1:0], allocatable[PORT_NUM-1:0], errors[PORT_NUM-1:0];
    wire [3:0] occupancy[PORT_NUM][VC_NUM], packets[PORT_NUM][VC_NUM];
    wire full_flag[PORT_NUM][VC_NUM], empty_flag[PORT_NUM][VC_NUM];
    input_block2crossbar xb();
    input_block2switch_allocator sa();
    input_block2vc_allocator va();
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    input_block #(.BUFFER_SIZE(DEPTH),.X_CURRENT(2),.Y_CURRENT(2)) dut(
        .data_i(data_i),.valid_flit_i(valid_i),.rst(rst),.clk(clk),
        .crossbar_if(xb),.sa_if(sa),.va_if(va),.on_off_o(on_off),
        .vc_allocatable_o(allocatable),.error_o(errors),.metrics_i(metrics));
    for(genvar p=0;p<PORT_NUM;p++) begin: observe_port
        for(genvar v=0;v<VC_NUM;v++) begin: observe_vc
            assign occupancy[p][v]=dut.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.circular_buffer.num_flits;
            assign packets[p][v]=dut.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.num_packets;
            assign full_flag[p][v]=dut.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.is_full_o;
            assign empty_flag[p][v]=dut.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.is_empty_o;
        end
    end
    function automatic flit_t make_flit(input int p,v,k,length);
        flit_t f;
        f='0; f.vc_id=v;
        f.data.head_data.head_pl='1;
        f.data.head_data.x_source=2; f.data.head_data.y_source=2;
        f.data.head_data.packet_id=k/length; f.data.head_data.backup=8'ha5;
        if(length==1) f.flit_label=HEADTAIL;
        else if(k%length==0) f.flit_label=HEAD;
        else if(k%length==length-1) f.flit_label=TAIL;
        else f.flit_label=BODY;
        f.data.head_data.x_dest=3; f.data.head_data.y_dest=2;
        f.data.head_data.head_pl[31:0]=p*1024+v*128+k;
        return f;
    endfunction
    task automatic check(input bit ok,input string message);
        if(!ok) $fatal(1,"[CAPACITY] %s",message);
    endtask
    task automatic check_errors(input bit expected);
        for(int p=1;p<PORT_NUM;p++)
            check(errors[p] === (expected ? {VC_NUM{1'b1}} : {VC_NUM{1'b0}}),
                  $sformatf("port=%0d errors=%b expected_all=%b",p,errors[p],expected));
    endtask
    task automatic reset_case;
        @(negedge clk); rst=1;
        for(int p=0;p<PORT_NUM;p++) begin
            data_i[p]='0; valid_i[p]=0; sa.vc_sel[p]=0; sa.valid_sel[p]=0;
            va.vc_valid[p]='0;
            for(int v=0;v<VC_NUM;v++) va.vc_new[p][v]=v;
        end
        repeat(3) @(negedge clk);
        rst=0;
        @(posedge clk); #1;
    endtask
    task automatic test_length(input int length);
        flit_t expected;
        reset_case();
        // Fill all four directional ports and every VC; deliberately bypass
        // on_off to measure physical storage rather than upstream flow policy.
        for(int v=0;v<VC_NUM;v++) begin
            for(int k=0;k<DEPTH;k++) begin
                @(negedge clk);
                for(int p=1;p<PORT_NUM;p++) begin
                    data_i[p]=make_flit(p,v,k,length); valid_i[p]=1;
                end
                @(posedge clk); #1;
                check_errors(0);
                for(int p=1;p<PORT_NUM;p++) begin
                    check(occupancy[p][v] == k+1,$sformatf("occupancy after fill p=%0d v=%0d k=%0d actual=%0d data=%h valid=%b",p,v,k,occupancy[p][v],data_i[p],valid_i[p]));
                    check(packets[p][v] == k/length+1,"packet metadata after fill");
                    check(on_off[p][v] === (k+1 < 7),"flow control must close at seven flits");
                end
            end
        end
        @(negedge clk);
        for(int p=1;p<PORT_NUM;p++) valid_i[p]=0;
        for(int p=1;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            check(full_flag[p][v] === 1'b1,"full flag at depth");
            check(on_off[p][v] === 1'b0,"on_off closed at capacity");
            check(packets[p][v] == DEPTH/length,"full packet capacity");
        end
        // Each full VC must reject an additional complete packet header.
        for(int v=0;v<VC_NUM;v++) begin
            @(negedge clk);
            for(int p=1;p<PORT_NUM;p++) begin
                data_i[p]=make_flit(p,v,DEPTH,length); valid_i[p]=1;
            end
            @(posedge clk); #1;
            for(int p=1;p<PORT_NUM;p++) begin
                check(errors[p] === (1 << v),"overflow must report only selected VC");
                check(occupancy[p][v] == DEPTH,"overflow changed occupancy");
                check(packets[p][v] == DEPTH/length,"overflow changed packet count");
            end
        end
        @(negedge clk);
        for(int p=1;p<PORT_NUM;p++) valid_i[p]=0;
        @(posedge clk); #1; check_errors(0);
        // Allocate then drain each queued packet, checking all flit bits,
        // route metadata, remapped VC and exact packet-tail release pulses.
        for(int v=0;v<VC_NUM;v++) begin
            for(int k=0;k<DEPTH;k++) begin
                if(k%length==0) begin
                    @(negedge clk);
                    for(int p=1;p<PORT_NUM;p++) begin
                        check(va.vc_request[p][v] === 1'b1,"missing VA request");
                        va.vc_new[p][v]=(v+1)%VC_NUM; va.vc_valid[p][v]=1;
                    end
                    @(posedge clk); #1; check_errors(0);
                    @(negedge clk);
                    for(int p=1;p<PORT_NUM;p++) va.vc_valid[p][v]=0;
                end
                @(negedge clk);
                for(int p=1;p<PORT_NUM;p++) begin
                    sa.vc_sel[p]=v; sa.valid_sel[p]=1;
                end
                #1;
                for(int p=1;p<PORT_NUM;p++) begin
                    expected=make_flit(p,v,k,length); expected.vc_id=(v+1)%VC_NUM;
                    check(sa.switch_request[p][v] === 1'b1,"missing switch request");
                    check(sa.out_port[p][v] === EAST,"route metadata corrupted");
                    check(xb.flit[p] === expected,$sformatf("readback p=%0d v=%0d k=%0d",p,v,k));
                end
                @(posedge clk); #1; check_errors(0);
                for(int p=1;p<PORT_NUM;p++) begin
                    check(occupancy[p][v] == DEPTH-k-1,"drain occupancy");
                    check(allocatable[p][v] === (k%length==length-1),"tail release pulse");
                end
                @(negedge clk);
                for(int p=1;p<PORT_NUM;p++) sa.valid_sel[p]=0;
            end
        end
        for(int p=1;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            check(empty_flag[p][v] === 1'b1 && packets[p][v]==0,"not fully empty");
            $display("[CAPACITY] port=%0d vc=%0d flits_per_packet=%0d max_complete_packets=%0d storage_flits=%0d PASS",p,v,length,DEPTH/length,DEPTH);
        end
    endtask
    initial begin
        check($bits(flit_t)==258,"temporary received flit width");
        test_length(1); test_length(2); test_length(4); test_length(8);
        $display("[TB_CONGESTION_BUFFER_CAPACITY] PASSED cases=64 directions=NORTH,SOUTH,WEST,EAST vcs=4 depth=8 overflow_checks=64");
        $finish;
    end
    initial begin #100000; $fatal(1,"capacity test timeout"); end
endmodule
