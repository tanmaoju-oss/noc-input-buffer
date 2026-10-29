import noc_params::*;

module vc_allocator #(
)(
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i,
    input [PORT_NUM-1:0][VC_NUM-1:0] downstream_on_off_i,//Modify joint output/VC eligibility, Michael Tan, 20261029
    input [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] next_input_occupancy_i,//Modify fixed mode2 neighbor-input cost, Michael Tan, 20261029
    input_block2vc_allocator.vc_allocator ib_if
);

    logic [PORT_NUM-1:0][VC_NUM-1:0] request_cmd;
    logic [PORT_NUM-1:0][VC_NUM-1:0] grant;

    logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc, is_available_vc_next;

    //Modify isolated baseline, fair ready-aware choice and occupancy-aware choice; no ownership changes, Michael Tan, 20261029
`ifndef OE_READY_SELECTION_MODE
`define OE_READY_SELECTION_MODE 0
`endif
    localparam SELECTION_MODE=`OE_READY_SELECTION_MODE;
    port_t [VC_NUM-1:0] chosen_port[PORT_NUM-1:0];
    logic [PORT_NUM-1:0][VC_NUM-1:0] eligible_vc;
    int direction_cursor[PORT_NUM][VC_NUM],vc_cursor[PORT_NUM];
    always_comb begin: choose_ready_candidates
        int d,cost,best_cost;
        for(int port=0;port<PORT_NUM;port++)
            eligible_vc[port]=SELECTION_MODE==0?is_available_vc[port]:(is_available_vc[port]&downstream_on_off_i[port]);
        for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            chosen_port[p][v]=ib_if.out_port[p][v];
            best_cost=32'h7fffffff;
            if(SELECTION_MODE!=0) begin
                for(int k=0;k<PORT_NUM;k++) begin
                    d=(direction_cursor[p][v]+k)%PORT_NUM;
                    cost=SELECTION_MODE==2?int'(next_input_occupancy_i[d]):0;
                    if(ib_if.candidates[p][v][d] && (|eligible_vc[d]) && cost<best_cost) begin
                        chosen_port[p][v]=port_t'(d);best_cost=cost;
                    end
                end
            end
        end
    end
    //Modify rotate only after actual successful grants; a failed attempt never changes packet metadata, Michael Tan, 20261029
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            for(int p=0;p<PORT_NUM;p++) begin
                vc_cursor[p]<=0;
                for(int v=0;v<VC_NUM;v++) direction_cursor[p][v]<=0;
            end
        end else if(SELECTION_MODE!=0) begin
            for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) if(grant[p][v]) begin
                direction_cursor[p][v]<=(int'(chosen_port[p][v])+1)%PORT_NUM;
                vc_cursor[chosen_port[p][v]]<=(int'(ib_if.vc_new[p][v])+1)%VC_NUM;
            end
        end
    end

    separable_input_first_allocator #(
        .VC_NUM(VC_NUM)
    )
    separable_input_first_allocator (
        .rst(rst),
        .clk(clk),
        .request_i(request_cmd),
        //.out_port_i(ib_if.out_port),//Original, Michael Tan, 20261029
        .out_port_i(chosen_port),//Modify arbitrate chosen candidate, Michael Tan, 20261029
        .grant_o(grant)
    );

    /*
    Sequential logic:
    - reset on the rising edge of the rst input;
    - update the availability of downstream Virtual Channels.
    */
    always_ff@(posedge clk, posedge rst)
    begin
        if(rst)
        begin
            is_available_vc <= {PORT_NUM*VC_NUM{1'b1}};
        end
        else
        begin
            is_available_vc <= is_available_vc_next;
        end
    end

    /*
    Combinational logic:
    - compute the request matrix for the internal Separable Input-First
      Allocator, by setting to 1 the upstream Virtual Channels which are
      requesting for the allocation of a downstream Virtual Channel and
      whose associated downstream Input Port has at least one available
      Virtual Channel;
    - compute the outputs of the module from the grants matrix obtained
      from the Separable Input-First allocator and update the next
      value for the availability of downstream Virtual Channels if
      they have just been allocated;
    - update the next value for the availability of downstream Virtual
      Channels after their eventual deallocations.
    */
    always_comb
    begin
        is_available_vc_next = is_available_vc;
        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                request_cmd[up_port][up_vc] = 1'b0;
                ib_if.vc_valid[up_port][up_vc] = 1'b0;
                ib_if.granted_port[up_port][up_vc]=chosen_port[up_port][up_vc];//Modify lock successful output together with allocated VC, Michael Tan, 20261029
                ib_if.vc_new[up_port][up_vc] = {VC_SIZE{1'bx}};
            end
        end

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                //if(ib_if.vc_request[up_port][up_vc] & |is_available_vc[ib_if.out_port[up_port][up_vc]])//Original, Michael Tan, 20261029
                if(ib_if.vc_request[up_port][up_vc] & |eligible_vc[chosen_port[up_port][up_vc]])//Modify no active-policy grant to a closed downstream VC, Michael Tan, 20261029
                begin
                    request_cmd[up_port][up_vc] = 1'b1;
                end
            end
        end

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                if(grant[up_port][up_vc])
                begin
                    //ib_if.vc_new[up_port][up_vc] = assign_downstream_vc(ib_if.out_port[up_port][up_vc]);//Original, Michael Tan, 20261029
                    ib_if.vc_new[up_port][up_vc] = assign_downstream_vc(chosen_port[up_port][up_vc]);//Modify select ready VC on chosen output, Michael Tan, 20261029
                    ib_if.vc_valid[up_port][up_vc] = 1'b1;
                    //is_available_vc_next[ib_if.out_port[up_port][up_vc]][ib_if.vc_new[up_port][up_vc]] = 1'b0;//Original, Michael Tan, 20261029
                    is_available_vc_next[chosen_port[up_port][up_vc]][ib_if.vc_new[up_port][up_vc]] = 1'b0;//Modify reserve exactly the granted output/VC, Michael Tan, 20261029
                end
            end
        end

        for(int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1)
        begin
            for(int down_vc = 0; down_vc < VC_NUM; down_vc = down_vc + 1)
            begin
                if(~is_available_vc[down_port][down_vc] & idle_downstream_vc_i[down_port][down_vc])
                begin
                    is_available_vc_next[down_port][down_vc] = 1'b1;
                end
            end
        end
        
    end

    /*
    Returns the first (starting from 0, without any Round-Robin
    mechanism) Virtual Channel available for allocation from
    the downstream Input Port specified as a parameter.
    */
    function logic [VC_SIZE-1:0] assign_downstream_vc (input port_t port);
        int index;//Modify round-robin VC index for ready-aware modes, Michael Tan, 20261029
        assign_downstream_vc = {VC_SIZE{1'bx}};
        for(int vc = 0; vc < VC_NUM; vc = vc + 1)
        begin
            index=SELECTION_MODE==0?vc:(vc_cursor[port]+vc)%VC_NUM;
            //if(is_available_vc[port][vc])//Original, Michael Tan, 20261029
            if(eligible_vc[port][index])//Modify retain exact original order only in OFF control, Michael Tan, 20261029
            begin
                assign_downstream_vc = VC_SIZE'(index);//Modify grant the selected eligible VC, Michael Tan, 20261029
                break;
            end
        end
    endfunction

endmodule