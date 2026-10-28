`timescale 1ns/1ps
import noc_params::*;
//Modify verify mixed-hash OE legality independently of packet latency results, Michael Tan, 20261028
module tb_oe_hash_routes;
    parameter FALLBACK_MODE=0;
    logic [3:0] sx,sy,dx,dy;
    logic [11:0] pid;
    flit_label_t label=HEAD;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics='0;
    wire port_t route[169];
    longint paths=0,hops=0,turn_checks=0;
    int link_count[169][PORT_NUM];
    bit signatures[string];
    port_t head_reference[169];//Modify keep label check separate from path-load counters, Michael Tan, 20261028
    int fd;
    for(genvar gy=0;gy<13;gy++) begin: row
        for(genvar gx=0;gx<13;gx++) begin: col
            rc_unit #(.X_CURRENT(gx),.Y_CURRENT(gy),.ALGORITHM(2)) dut(
                .x_dest_i(dx),.y_dest_i(dy),.x_source_i(sx),.y_source_i(sy),.packet_id_i(pid),
                .flit_label_i(label),.metrics_i(metrics),.out_port_o(route[gy*13+gx]));
        end
    end
    task automatic verify_path;
        int x,y,distance,index,steps;
        port_t previous,next;
        x=int'(sx);y=int'(sy);previous=LOCAL;steps=0;paths++;
        for(int h=0;h<25;h++) begin
            if(x==int'(dx) && y==int'(dy)) break;
            index=y*13+x;next=route[index];
            if(previous==EAST && x%2==0 && (next inside {NORTH,SOUTH})) $fatal(1,"forbidden E-to-Y");
            if((previous inside {NORTH,SOUTH}) && x%2==1 && next==WEST) $fatal(1,"forbidden Y-to-W");
            if(steps) turn_checks++;
            previous=next;link_count[index][next]++;
            distance=(x>int'(dx)?x-int'(dx):int'(dx)-x)+(y>int'(dy)?y-int'(dy):int'(dy)-y);
            case(next)
                EAST:x=x+1;
                WEST:x=x-1;
                NORTH:y=y-1;
                SOUTH:y=y+1;
                default:$fatal(1,"not a directional hop");
            endcase
            if(x<0 || x>=13 || y<0 || y>=13) $fatal(1,"outside mesh");
            if((x>int'(dx)?x-int'(dx):int'(dx)-x)+(y>int'(dy)?y-int'(dy):int'(dy)-y)!=distance-1) $fatal(1,"nonminimal");
            steps++;hops++;
        end
        if(x!=int'(dx) || y!=int'(dy) || route[y*13+x]!==LOCAL) $fatal(1,"destination check failed");
    endtask
    initial begin
        string signature;
        int x,y,index,peak;
        port_t next;
        if(row[0].col[0].dut.HASH_MIXED_MODE!=1) $fatal(1,"mixed hash not enabled");
        for(int n=0;n<169;n++) for(int p=0;p<PORT_NUM;p++) link_count[n][p]=0;
        for(int src=0;src<169;src++) begin
            sx=src%13;sy=src/13;
            for(int dst=0;dst<169;dst++) begin
                dx=dst%13;dy=dst/13;
                for(int id=0;id<8;id++) begin pid=id;#1;verify_path();end
            end
        end
        sx=0;sy=0;dx=12;dy=12;
        for(int id=0;id<4096;id++) begin
            pid=id;#1;x=0;y=0;signature="";
            for(int h=0;h<24;h++) begin
                index=y*13+x;next=route[index];signature=$sformatf("%s%0d",signature,next);
                case(next)
                    EAST:x=x+1;
                    SOUTH:y=y+1;
                    default:$fatal(1,"unexpected diagonal direction");
                endcase
            end
            if(x!=12 || y!=12) $fatal(1,"diagonal route incomplete");
            signatures[signature]=1;
        end
        if(signatures.num()<=2) $fatal(1,"hash did not break two-route ID collapse");
        for(int n=0;n<169;n++) head_reference[n]=route[n];
        for(int l=1;l<4;l++) begin
            label=flit_label_t'(l);#1;
            if(l<3) begin
                for(int n=0;n<169;n++) if(route[n]!==LOCAL) $fatal(1,"non-head output");
            end else begin
                for(int n=0;n<169;n++) if(route[n]!==head_reference[n]) $fatal(1,"HEADTAIL differs from HEAD");
            end
        end
        if(paths!=228488 || hops!=1968512 || turn_checks!=1741376) $fatal(1,"audit totals mismatch");
        fd=$fopen("mixed_hash_routes.csv","w");if(!fd) $fatal(1,"cannot open CSV");
        $fdisplay(fd,"x,y,port,routes_eight_ids");peak=0;
        for(int n=0;n<169;n++) for(int p=1;p<PORT_NUM;p++) if(link_count[n][p]>0) begin
            $fdisplay(fd,"%0d,%0d,%0d,%0d",n%13,n/13,p,link_count[n][p]);
            if(link_count[n][p]>peak) peak=link_count[n][p];
        end
        $fclose(fd);
        $display("[TB_OE_HASH_ROUTES] PASSED paths=%0d hops=%0d turns=%0d diagonal_distinct_routes=%0d peak_eight_ids=%0d",paths,hops,turn_checks,signatures.num(),peak);
        $finish;
    end
endmodule
