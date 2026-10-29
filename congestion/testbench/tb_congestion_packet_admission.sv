`timescale 1ns/1ps
import noc_params::*;
//Modify verify packet-boundary VC reuse through two real routers and distinct metadata, Michael Tan, 20261029
module tb_congestion_packet_admission;
    parameter ALGORITHM=0;
    logic clk=0,rst=1,unblock=0;
    always #5 clk=~clk;
    router2router au[PORT_NUM](),ad[PORT_NUM](),bu[PORT_NUM](),bd[PORT_NUM]();
    flit_t incoming[PORT_NUM];
    logic [PORT_NUM-1:0] valid_in;
    wire [VC_NUM-1:0] source_on[PORT_NUM];
    wire [VC_NUM-1:0] aerror[PORT_NUM],berror[PORT_NUM];
    router_state_t ast,bstate;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    wire [PORT_NUM-1:0] bvalid,avalid;//Modify flatten interface signals for portable scoreboard indexing, Michael Tan, 20261029
    wire [PORT_NUM-1:0][$bits(flit_t)-1:0] bdata;
    logic [VC_NUM-1:0] pending[PORT_NUM],sink_return[PORT_NUM];
    int link_owner[VC_NUM],link_beat[8],sink_beat[8],expected_len[8],expected_port[8];
    int link_vc[8],received,ingress_returns,expected_returns,phase;
    wire [3:0] target_occupancy=b.input_block.generate_input_ports[WEST].input_port.generate_virtual_channels[0].input_buffer.priority_usage_o;
    wire [3:0] target_packets=b.input_block.generate_input_ports[WEST].input_port.generate_virtual_channels[0].input_buffer.num_packets;
    for(genvar p=0;p<PORT_NUM;p++) begin: connect
        assign source_on[p]=ad[p].is_on_off;
        assign bvalid[p]=bu[p].is_valid;
        assign avalid[p]=au[p].is_valid;//Modify constant interface selection, Michael Tan, 20261029
        assign bdata[p]=bu[p].data;
        if(p==EAST) begin
            assign ad[p].data=bu[WEST].data;
            assign ad[p].is_valid=bu[WEST].is_valid;
            assign bu[WEST].is_on_off=ad[p].is_on_off;
            assign bu[WEST].is_allocatable=ad[p].is_allocatable;
        end else begin
            assign ad[p].data=incoming[p];
            assign ad[p].is_valid=valid_in[p];
        end
        if(p==WEST) begin
            assign bd[p].data=au[EAST].data;
            assign bd[p].is_valid=au[EAST].is_valid;
            assign au[EAST].is_on_off=bd[p].is_on_off;
            assign au[EAST].is_allocatable=bd[p].is_allocatable;
        end else begin
            assign bd[p].data='0;
            assign bd[p].is_valid=0;
        end
        if(p!=EAST) begin
            assign au[p].is_on_off='1;
            assign au[p].is_allocatable='0;
        end
        if(p!=WEST) begin
            assign bu[p].is_on_off={VC_NUM{unblock}};
            assign bu[p].is_allocatable=sink_return[p];
        end
    end
    router #(.X_CURRENT(2),.Y_CURRENT(1),.ALGORITHM(ALGORITHM)) a(
        .clk(clk),.rst(rst),
        .router_if_local_up(au[LOCAL]),.router_if_local_down(ad[LOCAL]),
        .router_if_north_up(au[NORTH]),.router_if_north_down(ad[NORTH]),
        .router_if_south_up(au[SOUTH]),.router_if_south_down(ad[SOUTH]),
        .router_if_west_up(au[WEST]),.router_if_west_down(ad[WEST]),
        .router_if_east_up(au[EAST]),.router_if_east_down(ad[EAST]),
        .error_o(aerror),.router_state_o(ast),.metrics_i(metrics));
    router #(.X_CURRENT(3),.Y_CURRENT(1),.ALGORITHM(ALGORITHM)) b(
        .clk(clk),.rst(rst),
        .router_if_local_up(bu[LOCAL]),.router_if_local_down(bd[LOCAL]),
        .router_if_north_up(bu[NORTH]),.router_if_north_down(bd[NORTH]),
        .router_if_south_up(bu[SOUTH]),.router_if_south_down(bd[SOUTH]),
        .router_if_west_up(bu[WEST]),.router_if_west_down(bd[WEST]),
        .router_if_east_up(bu[EAST]),.router_if_east_down(bd[EAST]),
        .error_o(berror),.router_state_o(bstate),.metrics_i(metrics));
    task automatic check(input bit ok,input string message);
        if(!ok) $fatal(1,"[ADMISSION] phase=%0d %s",phase,message);
    endtask
    function automatic flit_t make_flit(input int id,beat);
        flit_t f;
        f='0;f.vc_id=0;
        f.flit_label=expected_len[id]==1?HEADTAIL:(beat==0?HEAD:(beat==expected_len[id]-1?TAIL:BODY));
        //Modify choose geometry allowing the same E-then-S path in XY and legal OE, Michael Tan, 20261029
        f.data.head_data.x_source=2;f.data.head_data.y_source=(id==1?0:1);
        f.data.head_data.x_dest=expected_port[id]==SOUTH?3:4;
        f.data.head_data.y_dest=expected_port[id]==SOUTH?2:1;
        f.data.head_data.packet_id=id;f.data.head_data.backup=beat;
        f.data.head_data.head_pl='1;f.data.head_data.head_pl[31:0]=id*256+beat;
        return f;
    endfunction
    always @(negedge clk) begin
        for(int p=0;p<PORT_NUM;p++) begin sink_return[p]=pending[p];pending[p]='0;end
    end
    always @(posedge clk) if(!rst) begin: scoreboard
        flit_t f,expected;
        int id,beat,vc;
        expected_returns=0;
        // Every A allocation must target an input VC whose preceding ingress packet ended.
        for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++)
            if(a.ib2va_if.vc_valid[p][v] && a.ib2va_if.out_port[p][v]==EAST)
                check(link_owner[a.ib2va_if.vc_new[p][v]]==-1,"VA reused VC before previous input TAIL");
        if(au[EAST].is_valid) begin
            f=au[EAST].data;id=int'(f.data.head_data.packet_id);beat=int'(f.data.head_data.backup);vc=int'(f.vc_id);
            check(id>=0 && id<8,"unknown link packet");
            expected=make_flit(id,beat);expected.vc_id=vc;
            check(f===expected && beat==link_beat[id],"link corruption or sequence error");
            if(beat==0) begin
                check(link_owner[vc]==-1,"interleaved HEAD on link");link_owner[vc]=id;link_vc[id]=vc;
            end else check(link_owner[vc]==id,"interleaved BODY/TAIL on link");
            link_beat[id]++;
            if(beat==expected_len[id]-1) begin link_owner[vc]=-1;expected_returns=1<<vc;end
        end
        for(int p=0;p<PORT_NUM;p++) if(bvalid[p]) begin
            f=flit_t'(bdata[p]);id=int'(f.data.head_data.packet_id);beat=int'(f.data.head_data.backup);
            check(id>=0 && id<8,"unknown sink packet");
            expected=make_flit(id,beat);expected.vc_id=f.vc_id;
            check(p==expected_port[id] && f===expected && beat==sink_beat[id],"sink route/content/order error");
            sink_beat[id]++;
            if(beat==expected_len[id]-1) begin received++;pending[p][f.vc_id]=1;end
        end
        #1;
        check(bd[WEST].is_allocatable===VC_NUM'(expected_returns),"return must match accepted ingress TAIL, never output pop");
        ingress_returns+=$countones(bd[WEST].is_allocatable);
        for(int p=0;p<PORT_NUM;p++) begin
            check(aerror[p]==='0 && berror[p]==='0,"router error");
            if(p!=EAST) check(avalid[p]===0,"unexpected route from A");
        end
    end
    task automatic reset_case(input int number);
        @(negedge clk);rst=1;phase=number;unblock=0;valid_in='0;
        received=0;ingress_returns=0;expected_returns=0;
        for(int p=0;p<PORT_NUM;p++) begin incoming[p]='0;pending[p]='0;sink_return[p]='0;end
        for(int id=0;id<8;id++) begin link_beat[id]=0;sink_beat[id]=0;link_vc[id]=-1;expected_len[id]=4;expected_port[id]=EAST;end
        for(int vc=0;vc<VC_NUM;vc++) link_owner[vc]=-1;
        repeat(4) @(negedge clk);rst=0;
    endtask
    task automatic send_beat(input int p,id,beat);
        bit accepted;
        accepted=0;
        for(int c=0;c<100;c++) begin
            @(negedge clk);
            if(source_on[p][0]) begin
                incoming[p]=make_flit(id,beat);valid_in[p]=1;accepted=1;break;
            end
        end
        check(accepted,"source blocked unexpectedly");
        @(negedge clk);valid_in[p]=0;
    endtask
    task automatic send_packet(input int p,id);
        for(int beat=0;beat<expected_len[id];beat++) send_beat(p,id,beat);
    endtask
    task automatic drain(input int count);
        bit done;
        done=0;@(negedge clk);unblock=1;
        for(int c=0;c<500;c++) begin @(negedge clk);if(received==count) begin done=1;break;end end
        check(done,"drain timeout");
        repeat(20) @(negedge clk);
        check(received==count && ingress_returns==count,"packet/return count mismatch");
        check(ast.vc_occupancy==='0 && bstate.vc_occupancy==='0,"routers not empty");
    endtask
    initial begin
        check(ALGORITHM==0 || ALGORITHM==2,"test supports XY/OE");
        reset_case(1);expected_port[1]=SOUTH;
        send_packet(LOCAL,0);
        repeat(12) @(negedge clk);
        check(target_occupancy==4 && target_packets==1,"first packet not retained");
        check(a.vc_allocator.is_available_vc[EAST][0]===1,"VC not returned after accepted input tail");
        send_packet(NORTH,1);
        repeat(15) @(negedge clk);
        check(link_vc[0]==0 && link_vc[1]==0,"second packet did not reuse actual downstream VC0");
        check(target_occupancy==7 && target_packets==2,"two queued packets or seven-flit backpressure missing");
        check(bd[WEST].is_on_off[0]===0 && link_beat[1]==3,"flow control must retain second TAIL upstream");
        check(received==0,"blocked sink unexpectedly received");
        $display("[ADMISSION] two_router_same_vc packets=2 occupancy=7 first_packet_retained=1 distinct_routes=EAST/SOUTH PASS");
        drain(2);
        reset_case(2);
        send_beat(LOCAL,0,0);repeat(8) @(negedge clk);
        check(a.vc_allocator.is_available_vc[EAST][0]===0,"open packet must retain ownership even though not full");
        send_packet(NORTH,1);repeat(8) @(negedge clk);
        check(link_vc[0]==0 && link_vc[1]==1,"competitor must use different VC while first packet open");
        for(int beat=1;beat<4;beat++) send_beat(LOCAL,0,beat);
        drain(2);
        reset_case(3);expected_len[0]=1;expected_len[1]=12;
        send_packet(LOCAL,0);repeat(8) @(negedge clk);unblock=1;
        send_packet(NORTH,1);drain(2);
        $display("[TB_CONGESTION_PACKET_ADMISSION] PASSED algorithm=%0d cases=3 same_vc_queue/open_packet_competition/headtail_long_packet",ALGORITHM);
        $finish;
    end
    initial begin #100000;$fatal(1,"admission timeout");end
endmodule
