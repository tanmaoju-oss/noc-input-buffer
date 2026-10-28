`timescale 1ns/1ps
import noc_params::*;
//Modify compare RC legality and one/two-hop cost against independent geometry model, Michael Tan, 20261028
module tb_congestion_routing;
    parameter REFERENCE=0, AGG=0;
    logic [3:0] dx,dy,sx,sy;
    logic [11:0] pid;
    flit_label_t label;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics;
    wire port_t result[13][6];
    int errors[6], checks[6];
    for(genvar c=0;c<13;c++) begin: current_node
        for(genvar a=0;a<6;a++) begin: algorithm
            rc_unit #(.X_CURRENT(c),.Y_CURRENT(c),.ALGORITHM(a),.AGGREGATION(AGG),.DECISION_REFERENCE(REFERENCE)) dut(
                .x_dest_i(dx),.y_dest_i(dy),.x_source_i(sx),.y_source_i(sy),.packet_id_i(pid),
                .flit_label_i(label),.metrics_i(metrics),.out_port_o(result[c][a]));
        end
    end
    function automatic int metric(input int x,y,input port_t port);
        if(x<0 || x>=13 || y<0 || y>=13) return 0;
        case(REFERENCE)
            0:return int'(metrics[x][y].per_dir_total_occupancy[port]);
            1:return int'(metrics[x][y].per_dir_congestion_level[port]);
            default:return int'(metrics[x][y].node_total_flow);
        endcase
    endfunction
    function automatic int aggregate(input int first,second);
        case(AGG)
            0:return first+second;
            1:return (first>second)?first:second;
            default:return 7*first+3*second;
        endcase
    endfunction
    function automatic port_t xdir(input int c); return (int'(dx)>c)?EAST:WEST; endfunction
    function automatic port_t ydir(input int c); return (int'(dy)>c)?SOUTH:NORTH; endfunction
    // Route cost is the input queue reached on hop one, then the next
    // minimal hop: continue same dimension if necessary, otherwise turn.
    function automatic int cost(input int c,input port_t first,input bit two_hops);
        int x,y,x2,y2,one,two;
        port_t incoming, incoming2;
        x=c; y=c;
        case(first)
            EAST:begin x++; incoming=WEST; end
            WEST:begin x--; incoming=EAST; end
            NORTH:begin y--; incoming=SOUTH; end
            default:begin y++; incoming=NORTH; end
        endcase
        one=metric(x,y,incoming);
        if(!two_hops) return one;
        x2=x; y2=y;
        if(first inside {EAST,WEST}) begin
            if(x!=int'(dx)) begin
                if(int'(dx)>x) begin x2++; incoming2=WEST; end
                else begin x2--; incoming2=EAST; end
            end else begin
                if(int'(dy)>y) begin y2++; incoming2=NORTH; end
                else begin y2--; incoming2=SOUTH; end
            end
        end else begin
            if(y!=int'(dy)) begin
                if(int'(dy)>y) begin y2++; incoming2=NORTH; end
                else begin y2--; incoming2=SOUTH; end
            end else begin
                if(int'(dx)>x) begin x2++; incoming2=WEST; end
                else begin x2--; incoming2=EAST; end
            end
        end
        two=metric(x2,y2,incoming2);
        return aggregate(one,two);
    endfunction
    task automatic fail(input int a,c,input string why);
        errors[a]++;
        if(errors[a]<=5) $display("[ROUTE_MISMATCH] alg=%0d c=(%0d,%0d) dest=(%0d,%0d) source_x=%0d label=%0d got=%0d %s",a,c,c,dx,dy,sx,label,result[c][a],why);
    endtask
    task automatic verify;
        bit allow_x,allow_y,legal;
        port_t expected,xx,yy;
        int next_x,next_y;
        for(int c=0;c<13;c++) for(int a=0;a<6;a++) begin
            checks[a]++;
            if(label inside {BODY,TAIL}) begin
                if(result[c][a] !== LOCAL) fail(a,c,"non-head must report LOCAL");
                continue;
            end
            if(int'(dx)==c && int'(dy)==c) begin
                if(result[c][a] !== LOCAL) fail(a,c,"destination must report LOCAL");
                continue;
            end
            xx=xdir(c); yy=ydir(c);
            next_x=c; next_y=c; legal=1;
            case(result[c][a])
                EAST:next_x++;
                WEST:next_x--;
                NORTH:next_y--;
                SOUTH:next_y++;
                default:legal=0;
            endcase
            if(next_x<0 || next_x>=13 || next_y<0 || next_y>=13 ||
               ((next_x>int'(dx)?next_x-int'(dx):int'(dx)-next_x)+(next_y>int'(dy)?next_y-int'(dy):int'(dy)-next_y)) !=
               ((c>int'(dx)?c-int'(dx):int'(dx)-c)+(c>int'(dy)?c-int'(dy):int'(dy)-c))-1) legal=0;
            if(!legal) begin fail(a,c,"not a valid minimal in-mesh hop"); continue; end
            if(a==0 || a==1 || int'(dx)==c || int'(dy)==c) begin
                if(int'(dx)==c) expected=yy;
                else if(int'(dy)==c) expected=xx;
                else expected=(a==1)?yy:xx;
                if(result[c][a] !== expected) fail(a,c,"dimension-order or single-axis mismatch");
                continue;
            end
            if(a==5) continue; // Only minimality, no deadlock claim for reserved ThreeAware.
            if(int'(dx)>c) begin
                allow_y=(c%2==1 || c==int'(sx));
                allow_x=(int'(dx)%2==1 || int'(dx)-c!=1);
            end else begin allow_x=1; allow_y=(c%2==0); end
            if((result[c][a]==xx && !allow_x) || (result[c][a]==yy && !allow_y))
                fail(a,c,"violates OE candidate restriction");
            if(a>=3 && (allow_x || allow_y)) begin
                if(!allow_y) expected=xx;
                else if(!allow_x) expected=yy;
                else expected=(cost(c,xx,a==4)<cost(c,yy,a==4))?xx:yy;
                if(result[c][a] !== expected)
                    fail(a,c,$sformatf("cost mismatch x=%0d y=%0d expected=%0d",cost(c,xx,a==4),cost(c,yy,a==4),expected));
            end
        end
    endtask
    initial begin
        int total_errors;
        for(int a=0;a<6;a++) begin errors[a]=0; checks[a]=0; end
        metrics='0; pid=12'h129; sx=0;sy=0;dx=0;dy=0;label=HEAD;
        // Three asymmetric maps plus zero map; all valid destinations, two
        // source-X choices (current/source-column coverage) and all flit labels.
        for(int pattern=0;pattern<4;pattern++) begin
            for(int x=0;x<13;x++) for(int y=0;y<13;y++) begin
                metrics[x][y].node_total_flow=(pattern==0)?0:(x*17+y*11+pattern*23)%161;
                for(int p=0;p<PORT_NUM;p++) begin
                    metrics[x][y].per_dir_total_occupancy[p]=(pattern==0)?0:(x*7+y*13+p*5+pattern*11)%33;
                    metrics[x][y].per_dir_congestion_level[p]=(pattern==0)?1:1+(x*3+y*5+p*7+pattern)%9;
                end
            end
            for(int source=0;source<13;source+=2) begin
                sx=source; sy=source;
                for(int x=0;x<13;x++) for(int y=0;y<13;y++) begin
                    dx=x; dy=y;
                    for(int l=0;l<4;l++) begin label=flit_label_t'(l); #1; verify(); end
                end
            end
        end
        total_errors=0;
        for(int a=0;a<6;a++) begin
            $display("[ROUTE_RESULT] algorithm=%0d checks=%0d errors=%0d reference=%0d aggregation=%0d",a,checks[a],errors[a],REFERENCE,AGG);
            total_errors+=errors[a];
        end
        if(total_errors) $fatal(1,"[TB_CONGESTION_ROUTING] FAILED errors=%0d",total_errors);
        $display("[TB_CONGESTION_ROUTING] PASSED reference=%0d aggregation=%0d",REFERENCE,AGG);
        $finish;
    end
endmodule
