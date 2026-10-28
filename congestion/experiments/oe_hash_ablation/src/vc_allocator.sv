import noc_params::*;

module vc_allocator #(
)(
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i,
    input_block2vc_allocator.vc_allocator ib_if
);

    logic [PORT_NUM-1:0][VC_NUM-1:0] request_cmd;
    logic [PORT_NUM-1:0][VC_NUM-1:0] grant;

    logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc, is_available_vc_next;
    //Modify isolate fallback availability mechanism with compile-time OFF control, Michael Tan, 20261028
`ifdef OE_VA_FALLBACK_DISABLED
    localparam ENABLE_FALLBACK=0;
`else
    localparam ENABLE_FALLBACK=1;
`endif
    port_t [VC_NUM-1:0] chosen_port [PORT_NUM-1:0];
    logic [PORT_NUM-1:0][VC_NUM-1:0] fallback_possible_debug, fallback_grant_debug;
    always_comb begin
        fallback_possible_debug='0;
        fallback_grant_debug='0;
        for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            chosen_port[p][v]=ib_if.out_port[p][v];
            if(ib_if.vc_request[p][v] && !(|is_available_vc[ib_if.out_port[p][v]])) begin
                for(int alt=0;alt<PORT_NUM;alt++) begin
                    if(ib_if.candidates[p][v][alt] && (|is_available_vc[alt])) begin
                        fallback_possible_debug[p][v]=1'b1;
                        if(ENABLE_FALLBACK) chosen_port[p][v]=port_t'(alt);
                        break;
                    end
                end
            end
            fallback_grant_debug[p][v]=grant[p][v] && (chosen_port[p][v]!=ib_if.out_port[p][v]);
        end
    end

    separable_input_first_allocator #(
        .VC_NUM(VC_NUM)
    )
    separable_input_first_allocator (
        .rst(rst),
        .clk(clk),
        .request_i(request_cmd),
        //.out_port_i(ib_if.out_port),//Original, Michael Tan, 20261028
        .out_port_i(chosen_port),//Modify arbitrate actual selected direction, Michael Tan, 20261028
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
                //ib_if.vc_new[up_port][up_vc] = {VC_SIZE{1'bx}};//Original, Michael Tan, 20261028
                ib_if.vc_new[up_port][up_vc] = {VC_SIZE{1'bx}};
                ib_if.granted_port[up_port][up_vc] = chosen_port[up_port][up_vc];//Modify return selected port, Michael Tan, 20261028
            end
        end

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                //if(ib_if.vc_request[up_port][up_vc] & |is_available_vc[ib_if.out_port[up_port][up_vc]])//Original, Michael Tan, 20261028
                if(ib_if.vc_request[up_port][up_vc] & |is_available_vc[chosen_port[up_port][up_vc]])//Modify request available chosen direction, Michael Tan, 20261028
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
                    //ib_if.vc_new[up_port][up_vc] = assign_downstream_vc(ib_if.out_port[up_port][up_vc]);//Original, Michael Tan, 20261028
                    ib_if.vc_new[up_port][up_vc] = assign_downstream_vc(chosen_port[up_port][up_vc]);//Modify allocate VC on selected direction, Michael Tan, 20261028
                    ib_if.vc_valid[up_port][up_vc] = 1'b1;
                    //is_available_vc_next[ib_if.out_port[up_port][up_vc]][ib_if.vc_new[up_port][up_vc]] = 1'b0;//Original, Michael Tan, 20261028
                    is_available_vc_next[chosen_port[up_port][up_vc]][ib_if.vc_new[up_port][up_vc]] = 1'b0;//Modify reserve selected output VC, Michael Tan, 20261028
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
        assign_downstream_vc = {VC_SIZE{1'bx}};
        for(int vc = 0; vc < VC_NUM; vc = vc + 1)
        begin
            if(is_available_vc[port][vc])
            begin
                assign_downstream_vc = vc;
                break;
            end
        end
    endfunction

endmodule