`timescale 1ns/1ps
import noc_params::*;
//Modify validate OFF wait and ON legal alternative VC allocation, Michael Tan, 20261028
module tb_oe_va_fallback_directed;
    parameter FALLBACK_MODE=1;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    flit_t incoming[PORT_NUM-1:0],observed[PORT_NUM-1:0];
    logic [PORT_NUM-1:0] valid_in,valid_out;
    logic [PORT_NUM-1:0][VC_NUM-1:0] sink_on,sink_release;
    logic [VC_NUM-1:0] errors[PORT_NUM-1:0];
    router_state_t state;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    router2router local_up(),local_down();
    router2router north_up(),north_down();
    router2router south_up(),south_down();
    router2router west_up(),west_down();
    router2router east_up(),east_down();
    always_comb begin
        local_down.data=incoming[LOCAL];local_down.is_valid=valid_in[LOCAL];
        local_up.is_on_off=sink_on[LOCAL];local_up.is_allocatable=sink_release[LOCAL];
        observed[LOCAL]=local_up.data;valid_out[LOCAL]=local_up.is_valid;
        north_down.data=incoming[NORTH];north_down.is_valid=valid_in[NORTH];
        north_up.is_on_off=sink_on[NORTH];north_up.is_allocatable=sink_release[NORTH];
        observed[NORTH]=north_up.data;valid_out[NORTH]=north_up.is_valid;
        south_down.data=incoming[SOUTH];south_down.is_valid=valid_in[SOUTH];
        south_up.is_on_off=sink_on[SOUTH];south_up.is_allocatable=sink_release[SOUTH];
        observed[SOUTH]=south_up.data;valid_out[SOUTH]=south_up.is_valid;
        west_down.data=incoming[WEST];west_down.is_valid=valid_in[WEST];
        west_up.is_on_off=sink_on[WEST];west_up.is_allocatable=sink_release[WEST];
        observed[WEST]=west_up.data;valid_out[WEST]=west_up.is_valid;
        east_down.data=incoming[EAST];east_down.is_valid=valid_in[EAST];
        east_up.is_on_off=sink_on[EAST];east_up.is_allocatable=sink_release[EAST];
        observed[EAST]=east_up.data;valid_out[EAST]=east_up.is_valid;
    end
    router #(.X_CURRENT(1),.Y_CURRENT(1),.ALGORITHM(2)) dut(.clk(clk),.rst(rst),
        .router_if_local_up(local_up),.router_if_local_down(local_down),
        .router_if_north_up(north_up),.router_if_north_down(north_down),
        .router_if_south_up(south_up),.router_if_south_down(south_down),
        .router_if_west_up(west_up),.router_if_west_down(west_down),
        .router_if_east_up(east_up),.router_if_east_down(east_down),
        .error_o(errors),.router_state_o(state),.metrics_i(metrics));
    wire [VC_NUM-1:0] east_available=dut.vc_allocator.is_available_vc[EAST];
    wire [VC_NUM-1:0] south_available=dut.vc_allocator.is_available_vc[SOUTH];
    wire target_request=dut.ib2va_if.vc_request[NORTH][0];
    wire target_grant=dut.ib2va_if.vc_valid[NORTH][0];
    wire port_t target_route=dut.ib2va_if.out_port[NORTH][0];
    task automatic check(input bit condition,input string message);
        if(!condition) $fatal(1,"[OE_AVAILABILITY] %s",message);
    endtask
    task automatic no_errors;
        for(int p=0;p<PORT_NUM;p++) check(errors[p] === '0,"router error");
    endtask
    task automatic send(input int port,vc,id,dest_y);
        flit_t f;
        f='0;f.flit_label=HEADTAIL;f.vc_id=vc;
        f.data.head_data.x_source=1;f.data.head_data.y_source=(port==LOCAL)?1:0;
        f.data.head_data.x_dest=3;f.data.head_data.y_dest=dest_y;f.data.head_data.packet_id=id;
        @(negedge clk);incoming[port]=f;valid_in[port]=1;
        @(posedge clk);#1;no_errors();
        @(negedge clk);valid_in[port]=0;
    endtask
    initial begin
        logic [VC_NUM-1:0] pending;
        bit seen[5];
        int arrived,id;
        valid_in='0;sink_on='1;sink_on[EAST]='0;sink_release='0;
        for(int p=0;p<PORT_NUM;p++) incoming[p]='0;
        for(int k=0;k<5;k++) seen[k]=0;
        repeat(4) @(negedge clk);rst=0;
        for(int v=0;v<VC_NUM;v++) send(LOCAL,v,100+v,1);
        repeat(6) @(negedge clk);
        check(east_available === '0,"did not reserve all EAST VCs");
        check(south_available === '1,"SOUTH should remain free");
        // Target at (1,1), source (1,0), destination (3,3), ID0:
        // both E/S legal, XOR bit1 selects E despite all EAST VCs busy.
        send(NORTH,0,0,3);
        arrived=0;
        check(dut.vc_allocator.ENABLE_FALLBACK==FALLBACK_MODE,"mode mismatch");
        for(int c=0;c<30;c++) begin
            @(posedge clk);
            if(FALLBACK_MODE) begin
                if(valid_out[SOUTH]) begin
                    check(observed[SOUTH].data.head_data.packet_id==0,"wrong fallback packet");
                    check(!seen[4],"duplicate target");seen[4]=1;arrived++;
                end
            end
            #1;no_errors();
            if(!FALLBACK_MODE) begin
                check(target_route === EAST,"OFF preferred changed");
                check(target_request && !target_grant,"OFF target not blocked");
                check(south_available==='1,"OFF SOUTH allocation changed");
            end
            check(east_available==='0,"EAST resources changed before drain");
        end
        if(FALLBACK_MODE) begin
            check(arrived==1,"ON did not use free SOUTH");
            $display("[FALLBACK_DIRECTED] ON target delivered SOUTH while EAST remains unavailable");
        end else $display("[FALLBACK_DIRECTED] OFF reproduced 30-cycle EAST wait");
        pending='0;
        for(int c=0;c<80;c++) begin
            @(negedge clk);sink_on[EAST]='1;sink_release='0;sink_release[EAST]=pending;pending='0;
            @(posedge clk);
            for(int p=0;p<PORT_NUM;p++) if(valid_out[p]) begin
                check(p==EAST,"unexpected egress during EAST drain");
                check(observed[p].flit_label===HEADTAIL,"wrong packet label");
                id=int'(observed[p].data.head_data.packet_id);
                if(id==0) id=4;
                else id-=100;
                check(id>=0 && id<5,"unknown packet");
                check(!seen[id],"duplicate packet");seen[id]=1;arrived++;
                pending[observed[p].vc_id]=1;
            end
            #1;no_errors();
        end
        check(arrived==5,"missing packets after EAST release");
        check(state.vc_occupancy === '0,"router not empty");
        $display("[TB_OE_VA_FALLBACK_DIRECTED] PASSED mode=%0d drained_packets=5",FALLBACK_MODE);

        $finish;
    end
    initial begin #10000;$fatal(1,"availability test timeout");end
endmodule
