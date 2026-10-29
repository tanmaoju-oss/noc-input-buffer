`timescale 1ns/1ps
import noc_params::*;
//Modify audit actual OE paths, turn rules and hash correlation at every coordinate, Michael Tan, 20261028
module tb_congestion_oe_audit;
    logic [3:0] sx,sy,dx,dy;
    logic [11:0] pid;
    flit_label_t label;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    wire port_t route[169];
    wire choice_bit[169];
    port_t parity_route[2][169];
    longint paths=0, hops=0, source_checks=0, flip_checks=0, turn_checks=0;
    int link_count[169][PORT_NUM];
    int fd;
    for(genvar y=0;y<13;y++) begin: row
        for(genvar x=0;x<13;x++) begin: col
            rc_unit #(.X_CURRENT(x),.Y_CURRENT(y),.ALGORITHM(2)) dut(
                .x_dest_i(dx),.y_dest_i(dy),.x_source_i(sx),.y_source_i(sy),.packet_id_i(pid),
                .flit_label_i(label),.metrics_i(metrics),.out_port_o(route[y*13+x]));
            assign choice_bit[y*13+x]=dut.oe_rand_bit;
        end
    end
    task automatic verify_path;
        int x,y,prior_distance,steps,index;
        port_t previous,next;
        logic previous_bit;
        x=int'(sx);y=int'(sy);previous=LOCAL;steps=0;previous_bit=0;paths++;
        if(choice_bit[y*13+x] !== ((^pid)^dx[0]^dy[0])) $fatal(1,"source parity cancellation mismatch");
        source_checks++;
        //while(x!=int'(dx) || y!=int'(dy)) begin//Original, Michael Tan, 20261028
        for(int hop_index=0;hop_index<25;hop_index++) begin//Modify bound zero-time route walk explicitly, Michael Tan, 20261028
            if(x==int'(dx) && y==int'(dy)) break;
            index=y*13+x;next=route[index];
            prior_distance=((x>int'(dx))?x-int'(dx):int'(dx)-x)+((y>int'(dy))?y-int'(dy):int'(dy)-y);
            if(previous==EAST && x%2==0 && (next inside {NORTH,SOUTH})) $fatal(1,"forbidden E-to-Y at even column");
            if((previous inside {NORTH,SOUTH}) && x%2==1 && next==WEST) $fatal(1,"forbidden Y-to-W at odd column");
            if(steps>0) begin
                turn_checks++;
                if(choice_bit[index] !== !previous_bit) $fatal(1,"hop bit flip mismatch");
                flip_checks++;
            end
            previous_bit=choice_bit[index];previous=next;link_count[index][next]++;
            case(next)
                EAST:x=x+1;
                WEST:x=x-1;
                NORTH:y=y-1;
                SOUTH:y=y+1;
                default:$fatal(1,"LOCAL/unknown before destination");
            endcase
            if(x<0 || x>=13 || y<0 || y>=13) $fatal(1,"route exits mesh");
            if(((x>int'(dx)?x-int'(dx):int'(dx)-x)+(y>int'(dy)?y-int'(dy):int'(dy)-y)) != prior_distance-1)
                $fatal(1,"nonminimal path");
            steps++;hops++;
            if(steps>24) $fatal(1,"route loop");
        end
        if(route[y*13+x] !== LOCAL) $fatal(1,"destination not local source=(%0d,%0d) dest=(%0d,%0d) node=(%0d,%0d) got=%0d direct1=%0d",sx,sy,dx,dy,x,y,route[y*13+x],route[1]);
    endtask
    initial begin
        int source,dest,peak;
        for(int n=0;n<169;n++) for(int p=0;p<PORT_NUM;p++) link_count[n][p]=0;
        label=HEAD;
        for(source=0;source<169;source++) begin
            sx=source%13;sy=source/13;
            for(dest=0;dest<169;dest++) begin
                dx=dest%13;dy=dest/13;
                for(int bit_value=0;bit_value<2;bit_value++) begin
                    pid=bit_value;#1;verify_path();
                end
            end
        end
        // All 4096 IDs reduce to only two route maps for a fixed header.
        sx=2;sy=3;dx=10;dy=11;label=HEAD;
        for(int bit_value=0;bit_value<2;bit_value++) begin
            pid=bit_value;#1;
            for(int n=0;n<169;n++) parity_route[bit_value][n]=route[n];
        end
        for(int id=0;id<4096;id++) begin
            pid=id;#1;
            for(int n=0;n<169;n++)
                if(route[n] !== parity_route[(^pid)][n]) $fatal(1,"ID depends on more than parity");
        end
        for(int l=1;l<4;l++) begin
            label=flit_label_t'(l);#1;
            for(int n=0;n<169;n++) begin
                if(l==3) begin
                    if(route[n] !== parity_route[(^pid)][n]) $fatal(1,"HEADTAIL differs from HEAD");
                end else if(route[n] !== LOCAL) $fatal(1,"non-head RC must be LOCAL");
            end
        end
        fd=$fopen("oe_static_rtl_links.csv","w");if(!fd) $fatal(1,"cannot open route counts");
        $fdisplay(fd,"x,y,port,route_count_two_parities");peak=0;
        for(int n=0;n<169;n++) for(int p=1;p<PORT_NUM;p++) if(link_count[n][p]>0) begin
            $fdisplay(fd,"%0d,%0d,%0d,%0d",n%13,n/13,p,link_count[n][p]);
            if(link_count[n][p]>peak) peak=link_count[n][p];
        end
        $fclose(fd);
        if(paths!=57122 || hops!=492128 || peak!=1842) $fatal(1,"audit totals differ paths=%0d hops=%0d peak=%0d",paths,hops,peak);
        $display("[TB_CONGESTION_OE_AUDIT] PASSED paths=%0d hops=%0d source_checks=%0d flip_checks=%0d turn_checks=%0d ids=4096 peak_routes_two_parities=%0d",paths,hops,source_checks,flip_checks,turn_checks,peak);
        $finish;
    end
endmodule
