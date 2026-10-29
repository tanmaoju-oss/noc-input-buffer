import noc_params::*;

module switch_allocator #(
)(
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] on_off_i,
    input_block2switch_allocator.switch_allocator ib_if,
    switch_allocator2crossbar.switch_allocator xbar_if,
    output logic [PORT_NUM-1:0] valid_flit_o
);

    logic [PORT_NUM-1:0][VC_NUM-1:0] request_cmd;
    logic [PORT_NUM-1:0][VC_NUM-1:0] grant;
    //Modify optional work-conserving switch matching preserves locked routes and allocated downstream VCs, Michael Tan, 20261029
`ifdef READY_FULL_SA
    localparam FULL_MATCHING=1;
`else
    localparam FULL_MATCHING=0;
`endif
    logic [PORT_NUM-1:0][VC_NUM-1:0] legacy_grant,matching_grant;
    int start_port,vc_cursor[PORT_NUM],dir_cursor[PORT_NUM];
    assign grant=FULL_MATCHING?matching_grant:legacy_grant;
    always_comb begin: choose_switch_matching
        int edge_vc[PORT_NUM][PORT_NUM],owner[PORT_NUM],matched[PORT_NUM];
        int queue[PORT_NUM],parent_out[PORT_NUM];
        logic [PORT_NUM-1:0] seen_out,seen_in;
        int pidx,v,d,root_input,inode,qsize,terminal,previous,walk;
        matching_grant='0;
        for(int p=0;p<PORT_NUM;p++) begin
            owner[p]=-1;matched[p]=-1;queue[p]=-1;parent_out[p]=-1;
            for(int outp=0;outp<PORT_NUM;outp++) edge_vc[p][outp]=-1;
        end
        if(FULL_MATCHING) begin
            for(int p=0;p<PORT_NUM;p++) for(int outp=0;outp<PORT_NUM;outp++) begin
                for(int k=0;k<VC_NUM;k++) begin
                    v=(vc_cursor[p]+k)%VC_NUM;
                    if(ib_if.switch_request[p][v] && ib_if.out_port[p][v]==outp && on_off_i[outp][ib_if.downstream_vc[p][v]]) begin
                        edge_vc[p][outp]=v;break;
                    end
                end
            end
            for(int r=0;r<PORT_NUM;r++) begin
                root_input=(start_port+r)%PORT_NUM;seen_out='0;seen_in='0;seen_in[root_input]=1;
                terminal=-1;qsize=1;
                for(int k=0;k<PORT_NUM;k++) begin queue[k]=-1;parent_out[k]=-1;end
                queue[0]=root_input;
                for(int bfs=0;bfs<PORT_NUM;bfs++) if(bfs<qsize && terminal<0) begin
                    inode=queue[bfs];
                    for(int k=0;k<PORT_NUM;k++) if(terminal<0) begin
                        d=(dir_cursor[inode]+k)%PORT_NUM;
                        if(edge_vc[inode][d]>=0 && !seen_out[d]) begin
                            seen_out[d]=1;parent_out[d]=inode;
                            if(owner[d]<0) terminal=d;
                            else if(!seen_in[owner[d]]) begin seen_in[owner[d]]=1;queue[qsize]=owner[d];qsize++;end
                        end
                    end
                end
                walk=terminal;
                for(int k=0;k<PORT_NUM;k++) if(walk>=0) begin
                    pidx=parent_out[walk];previous=matched[pidx];matched[pidx]=walk;owner[walk]=pidx;walk=previous;
                end
            end
            for(int p=0;p<PORT_NUM;p++) if(matched[p]>=0) matching_grant[p][edge_vc[p][matched[p]]]=1;
        end
    end
    //Modify update fairness only on actual flit transfers, with no packet/VC ownership changes, Michael Tan, 20261029
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin start_port<=0;for(int p=0;p<PORT_NUM;p++) begin vc_cursor[p]<=0;dir_cursor[p]<=0;end end
        else if(FULL_MATCHING) begin
            if(|grant) start_port<=(start_port+1)%PORT_NUM;
            for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) if(grant[p][v]) begin
                vc_cursor[p]<=(v+1)%VC_NUM;dir_cursor[p]<=(int'(ib_if.out_port[p][v])+1)%PORT_NUM;
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
        .out_port_i(ib_if.out_port),
        //.grant_o(grant)//Original, Michael Tan, 20261029
        .grant_o(legacy_grant)//Modify exact legacy SA control when switch matching is disabled, Michael Tan, 20261029
    );

    /*
    Combinational logic:
    - compute the request matrix for the internal Separable Input-First
      Allocator, by setting to 1 the upstream Virtual Channels which are
      requesting for the allocation of a downstream Virtual Channel and
      whose associated downstream Virtual Channel is available from
      the on/off flow control point of view;
    - compute the outputs of the module from the grants matrix obtained
      from the Separable Input-First allocator.
    */
    always_comb
    begin
        for(int port = 0; port < PORT_NUM ; port = port + 1)
        begin
            ib_if.valid_sel[port] = 1'b0;
            valid_flit_o[port] = 1'b0;
            ib_if.vc_sel[port] = {VC_SIZE{1'b0}};
            //xbar_if.input_vc_sel[port] = {PORT_SIZE{1'b0}};//Modify by Michael Tan. Src here.
            xbar_if.input_vc_sel[port] = {PORT_SIZE{1'bx}};//Modify by Michael Tan.
            request_cmd[port]={VC_NUM{1'b0}};
        end

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                if(ib_if.switch_request[up_port][up_vc] & on_off_i[ib_if.out_port[up_port][up_vc]][ib_if.downstream_vc[up_port][up_vc]])
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
                    ib_if.vc_sel[up_port] = up_vc;
                    ib_if.valid_sel[up_port] = 1'b1;
                    valid_flit_o[ib_if.out_port[up_port][up_vc]] = 1'b1;
                    xbar_if.input_vc_sel[ib_if.out_port[up_port][up_vc]] = up_port;
                end
            end
        end
        
    end

endmodule