import noc_params::*;

module vc_allocator #(
    parameter X_CURRENT=2,Y_CURRENT=1//Modify fixed local coordinates for optional two-hop policy, Michael Tan, 20261029
)(
    input metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_i,//Modify reuse existing global metric source in experiment only, Michael Tan, 20261029
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i,
    input [PORT_NUM-1:0][VC_NUM-1:0] downstream_on_off_i,//Modify joint output/VC eligibility, Michael Tan, 20261029
    input [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] next_input_occupancy_i,//Modify fixed mode2 neighbor-input cost, Michael Tan, 20261029
    input_block2vc_allocator.vc_allocator ib_if
);

    logic [PORT_NUM-1:0][VC_NUM-1:0] request_cmd;
    logic [PORT_NUM-1:0][VC_NUM-1:0] grant;
    //Modify isolate maximum-cardinality joint input-VC/output matching from the previous separable control, Michael Tan, 20261029
    logic [PORT_NUM-1:0][VC_NUM-1:0] legacy_grant,matching_grant;
    //Modify bounded eligible-wait protection is ON by default for matching candidates; explicit OFF is diagnostic only, Michael Tan, 20261029
`ifdef READY_AGE_GUARD_DISABLED
    localparam AGE_ENABLED=0;
`else
    localparam AGE_ENABLED=1;
`endif
    localparam AGE_LIMIT=PORT_NUM*VC_NUM;
    logic [7:0] wait_age[PORT_NUM][VC_NUM];
    logic [PORT_NUM-1:0][VC_NUM-1:0] ready_heads;//Modify legal receive eligibility for head-age accounting, Michael Tan, 20261029
    int match_port_cursor,input_vc_cursor[PORT_NUM],input_dir_cursor[PORT_NUM];
    assign grant=SELECTION_MODE>=3?matching_grant:legacy_grant;

    logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc, is_available_vc_next;

    //Modify isolated baseline, fair ready-aware choice and occupancy-aware choice; no ownership changes, Michael Tan, 20261029
`ifndef OE_READY_SELECTION_MODE
`define OE_READY_SELECTION_MODE 0
`endif
    localparam SELECTION_MODE=`OE_READY_SELECTION_MODE;
    port_t [VC_NUM-1:0] chosen_port[PORT_NUM-1:0];
    logic [PORT_NUM-1:0][VC_NUM-1:0] eligible_vc;
    int direction_cursor[PORT_NUM][VC_NUM],vc_cursor[PORT_NUM];
    //Modify mode4 uses an unweighted sum of first-hop and best legal second-hop input occupancy, Michael Tan, 20261029
    function automatic int reverse_port(input int d);
        case(d) NORTH:return SOUTH;SOUTH:return NORTH;WEST:return EAST;EAST:return WEST;default:return LOCAL;endcase
    endfunction
    //Modify a single additional legal hop with fixed unit weights, not the unfinished original ThreeAware, Michael Tan, 20261029
    function automatic logic [PORT_NUM-1:0] legal_next(input int x,y,sx,dx,dy);
        logic [PORT_NUM-1:0] m;
        m='0;
        if(x==dx && y==dy) m[LOCAL]=1;
        else if(x==dx) m[dy<y?NORTH:SOUTH]=1;
        else if(y==dy) m[dx<x?WEST:EAST]=1;
        else if(dx>x) begin
            if(x%2==1 || x==sx) m[dy<y?NORTH:SOUTH]=1;
            if(dx%2==1 || dx-x!=1) m[EAST]=1;
        end else begin m[WEST]=1;if(x%2==0) m[dy<y?NORTH:SOUTH]=1;end
        return m;
    endfunction
    function automatic int route_cost(input int p,v,dir);
        int nx,ny,dx,dy,sx,tx,ty,best,first,ttx,tty,second,third_best;//Modify bounded third-hop scratch state, Michael Tan, 20261029
        logic [PORT_NUM-1:0] mask,third_mask;
        if(dir==LOCAL) return 0;
        nx=X_CURRENT+(dir==EAST)-(dir==WEST);ny=Y_CURRENT+(dir==SOUTH)-(dir==NORTH);
        if(nx<0 || nx>=MESH_SIZE_X || ny<0 || ny>=MESH_SIZE_Y) return 1000000;
        dx=int'(ib_if.head_dest_x[p][v]);dy=int'(ib_if.head_dest_y[p][v]);sx=int'(ib_if.head_source_x[p][v]);
        first=int'(metrics_i[nx][ny].per_dir_total_occupancy[reverse_port(dir)]);
        if(nx==dx && ny==dy) return first;
        mask='0;
        if(nx==dx) mask[dy<ny?NORTH:SOUTH]=1;
        else if(ny==dy) mask[dx<nx?WEST:EAST]=1;
        else if(dx>nx) begin
            if(nx%2==1 || nx==sx) mask[dy<ny?NORTH:SOUTH]=1;
            if(dx%2==1 || dx-nx!=1) mask[EAST]=1;
        end else begin
            mask[WEST]=1;if(nx%2==0) mask[dy<ny?NORTH:SOUTH]=1;
        end
        best=1000000;
        for(int d=1;d<PORT_NUM;d++) if(mask[d]) begin
            tx=nx+(d==EAST)-(d==WEST);ty=ny+(d==SOUTH)-(d==NORTH);
            if(tx>=0 && tx<MESH_SIZE_X && ty>=0 && ty<MESH_SIZE_Y) begin
                second=int'(metrics_i[tx][ty].per_dir_total_occupancy[reverse_port(d)]);
                if(SELECTION_MODE>=5 && !(tx==dx && ty==dy)) begin
                    third_mask=legal_next(tx,ty,sx,dx,dy);third_best=1000000;
                    for(int td=1;td<PORT_NUM;td++) if(third_mask[td]) begin
                        ttx=tx+(td==EAST)-(td==WEST);tty=ty+(td==SOUTH)-(td==NORTH);
                        if(ttx>=0 && ttx<MESH_SIZE_X && tty>=0 && tty<MESH_SIZE_Y)
                            if(int'(metrics_i[ttx][tty].per_dir_total_occupancy[reverse_port(td)])<third_best)
                                third_best=int'(metrics_i[ttx][tty].per_dir_total_occupancy[reverse_port(td)]);
                    end
                    second+=third_best;
                end
                if(second<best) best=second;
            end
        end
        return first+best;
    endfunction
    always_comb begin: choose_ready_candidates
        int d,cost,best_cost;
        //Modify bounded augmenting-path matcher; input ports and outputs each participate at most once, Michael Tan, 20261029
        int edge_vc[PORT_NUM][PORT_NUM],owner[PORT_NUM],matched[PORT_NUM];
        int queue[PORT_NUM],parent_out[PORT_NUM];
        logic [PORT_NUM-1:0] seen_out,seen_in,ordered;
        int pidx,vidx,root_input,inode,qsize,terminal,best_dir,previous,walk;
        int fair_vc[PORT_NUM],fair_age[PORT_NUM],root_order[PORT_NUM],best_root,best_age;
        logic [PORT_NUM-1:0] roots_taken;
        matching_grant='0;ready_heads='0;
        for(int p=0;p<PORT_NUM;p++) begin
            owner[p]=-1;matched[p]=-1;queue[p]=-1;parent_out[p]=-1;fair_vc[p]=-1;fair_age[p]=-1;root_order[p]=p;
            for(int outp=0;outp<PORT_NUM;outp++) edge_vc[p][outp]=-1;
        end
        for(int port=0;port<PORT_NUM;port++)
            eligible_vc[port]=SELECTION_MODE==0?is_available_vc[port]:(is_available_vc[port]&downstream_on_off_i[port]);
        for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            chosen_port[p][v]=ib_if.out_port[p][v];
            best_cost=32'h7fffffff;
            if(SELECTION_MODE!=0) begin
                for(int k=0;k<PORT_NUM;k++) begin
                    d=(direction_cursor[p][v]+k)%PORT_NUM;
                    cost=SELECTION_MODE>=2?int'(next_input_occupancy_i[d]):0;
                    if(SELECTION_MODE>=4 && ib_if.vc_request[p][v]) cost=route_cost(p,v,d);//Modify fixed two-hop policy only, Michael Tan, 20261029
                    if(ib_if.candidates[p][v][d] && (|eligible_vc[d]) && cost<best_cost) begin
                        chosen_port[p][v]=port_t'(d);best_cost=cost;
                    end
                end
            end
        end
        if(SELECTION_MODE>=3) begin
            //Modify protect oldest eligible VC before maximizing the remaining fair input/output graph, Michael Tan, 20261029
            for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) for(int d=0;d<PORT_NUM;d++)
                if(ib_if.vc_request[p][v] && ib_if.candidates[p][v][d] && (|eligible_vc[d])) ready_heads[p][v]=1;
            if(AGE_ENABLED) for(int p=0;p<PORT_NUM;p++) for(int k=0;k<VC_NUM;k++) begin
                vidx=(input_vc_cursor[p]+k)%VC_NUM;
                if(ready_heads[p][vidx] && wait_age[p][vidx]>=AGE_LIMIT && int'(wait_age[p][vidx])>fair_age[p]) begin
                    fair_vc[p]=vidx;fair_age[p]=int'(wait_age[p][vidx]);
                end
            end
            roots_taken='0;
            for(int rank=0;rank<PORT_NUM;rank++) begin
                best_root=-1;best_age=-2;
                for(int k=0;k<PORT_NUM;k++) begin
                    pidx=(match_port_cursor+k)%PORT_NUM;
                    if(!roots_taken[pidx] && fair_age[pidx]>best_age) begin best_root=pidx;best_age=fair_age[pidx];end
                end
                root_order[rank]=best_root;roots_taken[best_root]=1;
            end
            // Build one edge per input/output pair, preserving round-robin choice among eligible head VCs.
            for(int p=0;p<PORT_NUM;p++) for(int outp=0;outp<PORT_NUM;outp++) begin
                for(int k=0;k<VC_NUM;k++) begin
                    vidx=(input_vc_cursor[p]+k)%VC_NUM;
                    if((fair_vc[p]<0 || fair_vc[p]==vidx) && ib_if.vc_request[p][vidx] && ib_if.candidates[p][vidx][outp] && (|eligible_vc[outp])) begin
                        edge_vc[p][outp]=vidx;break;
                    end
                end
            end
            // At most five breadth-first searches, five input expansions and five path repairs each.
            for(int root_step=0;root_step<PORT_NUM;root_step++) begin
                root_input=root_order[root_step];
                seen_out='0;seen_in='0;seen_in[root_input]=1;terminal=-1;
                for(int k=0;k<PORT_NUM;k++) begin queue[k]=-1;parent_out[k]=-1;end
                queue[0]=root_input;qsize=1;
                for(int bfs=0;bfs<PORT_NUM;bfs++) if(bfs<qsize && terminal<0) begin
                    inode=queue[bfs];ordered='0;
                    for(int rank=0;rank<PORT_NUM;rank++) if(terminal<0) begin
                        best_cost=32'h7fffffff;best_dir=-1;
                        for(int k=0;k<PORT_NUM;k++) begin
                            d=(input_dir_cursor[inode]+k)%PORT_NUM;
                            cost=int'(next_input_occupancy_i[d]);
                            if(SELECTION_MODE>=4 && edge_vc[inode][d]>=0) cost=route_cost(inode,edge_vc[inode][d],d);//Modify rank actual matched queue's legal continuation, Michael Tan, 20261029
                            if(edge_vc[inode][d]>=0 && !ordered[d] && cost<best_cost) begin
                                best_dir=d;best_cost=cost;
                            end
                        end
                        if(best_dir>=0) begin
                            ordered[best_dir]=1;
                            if(!seen_out[best_dir]) begin
                                seen_out[best_dir]=1;parent_out[best_dir]=inode;
                                if(owner[best_dir]<0) terminal=best_dir;
                                else if(!seen_in[owner[best_dir]]) begin
                                    seen_in[owner[best_dir]]=1;queue[qsize]=owner[best_dir];qsize++;
                                end
                            end
                        end
                    end
                end
                walk=terminal;
                for(int k=0;k<PORT_NUM;k++) if(walk>=0) begin
                    pidx=parent_out[walk];previous=matched[pidx];
                    matched[pidx]=walk;owner[walk]=pidx;walk=previous;
                end
            end
            for(int p=0;p<PORT_NUM;p++) if(matched[p]>=0) begin
                d=matched[p];vidx=edge_vc[p][d];
                matching_grant[p][vidx]=1;chosen_port[p][vidx]=port_t'(d);
            end
        end
    end
    //Modify rotate only after actual successful grants; a failed attempt never changes packet metadata, Michael Tan, 20261029
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            match_port_cursor<=0;//Modify deterministic matching priority reset, Michael Tan, 20261029
            for(int p=0;p<PORT_NUM;p++) begin
                vc_cursor[p]<=0;input_vc_cursor[p]<=0;input_dir_cursor[p]<=0;//Modify independent matching fairness state, Michael Tan, 20261029
                for(int v=0;v<VC_NUM;v++) begin direction_cursor[p][v]<=0;wait_age[p][v]<=0;end
            end
        end else if(SELECTION_MODE!=0) begin
            //Modify retain ownership/capacity rules; age changes only arbitration preference, Michael Tan, 20261029
            if(AGE_ENABLED && SELECTION_MODE>=3) for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
                if(!ib_if.vc_request[p][v] || grant[p][v]) wait_age[p][v]<=0;
                else if(ready_heads[p][v] && wait_age[p][v]!=8'hff) wait_age[p][v]<=wait_age[p][v]+1;
            end
            if(SELECTION_MODE>=3 && |grant) match_port_cursor<=(match_port_cursor+1)%PORT_NUM;//Modify rotate successful matching rounds, Michael Tan, 20261029
            for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) if(grant[p][v]) begin
                if(SELECTION_MODE>=3) begin
                    input_vc_cursor[p]<=(v+1)%VC_NUM;input_dir_cursor[p]<=(int'(chosen_port[p][v])+1)%PORT_NUM;
                end
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
        .grant_o(legacy_grant)//Modify preserve separable mode0/1/2 control verbatim, Michael Tan, 20261029
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