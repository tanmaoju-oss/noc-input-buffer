`timescale 1ns/1ps
import noc_params::*;
//Modify independently verify replicated dateline phase resources, Michael Tan, 20261104
//Modify self-check all pairs, concurrent traffic, backpressure and drain, Michael Tan, 20261102
module tb_torus_phase_integration #(
    parameter NX=5, NY=5
);
    logic clk=0, rst=1;
    always #5 clk=~clk;
    flit_t [NX-1:0][NY-1:0] din, dout;
    logic [NX-1:0][NY-1:0] vin, vout;
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] ready_in, alloc_in, ready_out, alloc_out;
    logic [VC_NUM-1:0] errors [NX-1:0][NY-1:0][PORT_NUM-1:0];
    torus #(.MESH_SIZE_X(NX), .MESH_SIZE_Y(NY)) dut(
        .clk(clk), .rst(rst), .data_i(din), .data_o(dout), .is_valid_i(vin), .is_valid_o(vout),
        .is_on_off_i(ready_in), .is_allocatable_i(alloc_in),
        .is_on_off_o(ready_out), .is_allocatable_o(alloc_out), .error_o(errors));
    localparam MAX_PACKETS=4096;
    int dest_x[MAX_PACKETS], dest_y[MAX_PACKETS], lengths[MAX_PACKETS], seen[MAX_PACKETS];
    int active_packet[NX][NY][VC_NUM];
    int packets=0, completed=0, received=0, cycles=0;
    int link_flits=0, expected_link_flits=0, seam_e=0, seam_w=0, seam_s=0, seam_n=0;
    bit stall=0;
    //Modify audit VC release and FIFO drain after traffic completion, Michael Tan, 20261102
    bit audit_empty=0;

    function automatic port_t direction(input int x,y,dx,dy);
        if (x!=dx) return ((dx-x+NX)%NX <= (x-dx+NX)%NX) ? EAST : WEST;
        if (y!=dy) return ((dy-y+NY)%NY <= (y-dy+NY)%NY) ? SOUTH : NORTH;
        return LOCAL;
    endfunction

    //Modify model downstream deallocation as a TAIL pulse, not a constant idle level, Michael Tan, 20261102
    always @(posedge clk) begin
        alloc_in <= '0;
        if (!rst) for (int x=0;x<NX;x++) for (int y=0;y<NY;y++)
            if (vout[x][y] && (dout[x][y].flit_label==TAIL || dout[x][y].flit_label==HEADTAIL))
                alloc_in[x][y][dout[x][y].vc_id] <= 1'b1;
    end

    // Outputs are transfers on the upcoming rising edge, sampled before NBA.
    always @(posedge clk) if (!rst) begin
        cycles++;
        for (int x=0;x<NX;x++) for (int y=0;y<NY;y++) begin
            for (int p=0;p<PORT_NUM;p++)
                if (errors[x][y][p] !== '0) $fatal(1,"error/X node=%0d,%0d port=%0d",x,y,p);
            if (vout[x][y] === 1'bx) $fatal(1,"unknown local valid");
            if (vout[x][y]) begin
                int id, vc, beat;
                vc=dout[x][y].vc_id;
                if ($isunknown(dout[x][y])) $fatal(1,"unknown output flit");
                if (!ready_in[x][y][vc]) $fatal(1,"output ignored backpressure");
                if (dout[x][y].flit_label==HEAD || dout[x][y].flit_label==HEADTAIL) begin
                    id=dout[x][y].data.head_data.head_pl;
                    if (active_packet[x][y][vc]!=-1) $fatal(1,"packet interleaving");
                    if (id>=packets || seen[id]!=0) $fatal(1,"duplicate/unknown header %0d",id);
                    if (dout[x][y].data.head_data.x_dest!=x || dout[x][y].data.head_data.y_dest!=y)
                        $fatal(1,"header destination corrupted");
                    active_packet[x][y][vc]=id;
                end else id=active_packet[x][y][vc];
                if (id<0 || id>=packets) $fatal(1,"body without header");
                if (dest_x[id]!=x || dest_y[id]!=y) $fatal(1,"wrong destination packet=%0d",id);
                beat=seen[id];
                if (lengths[id]==1) begin
                    if (dout[x][y].flit_label!=HEADTAIL) $fatal(1,"HEADTAIL label");
                end else begin
                    if (dout[x][y].flit_label != ((beat==0)?HEAD:((beat==lengths[id]-1)?TAIL:BODY)))
                        $fatal(1,"label/order packet=%0d beat=%0d",id,beat);
                    if (beat>0 && dout[x][y].data.bt_pl != id*8+beat) $fatal(1,"payload/order mismatch");
                end
                seen[id]++;
                received++;
                if (seen[id]==lengths[id]) begin
                    completed++;
                    active_packet[x][y][vc]=-1;
                end
            end
        end
    end

    // Inspect actual physical transfers and allocator grants at every router.
    for (genvar y=0;y<NY;y++) begin: check_y
        for (genvar x=0;x<NX;x++) begin: check_x
            for (genvar ip=0;ip<PORT_NUM;ip++) begin: drain_port
                for (genvar iv=0;iv<VC_NUM;iv++) begin: drain_vc
                    always @(posedge clk) if (audit_empty) begin
                        if (!dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[ip].input_port.generate_virtual_channels[iv].input_buffer.is_empty_o ||
                            dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[ip].input_port.generate_virtual_channels[iv].input_buffer.num_packets!=0 ||
                            dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[ip].input_port.generate_virtual_channels[iv].input_buffer.write_packet_open)
                            $fatal(1,"residual input resources");
                    end
                end
            end
            always @(posedge clk) if (!rst) begin
                if (audit_empty && dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc !== '1)
                    $fatal(1,"downstream VC not released");
                for (int p=0;p<PORT_NUM;p++) begin
                    for (int v=0;v<VC_NUM;v++)
                        if (dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_valid[p][v]) begin
                            if (!dut.mesh_row[y].mesh_col[x].router.ib2va_if.allowed_vcs[p][v]
                                [dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_new[p][v]])
                                $fatal(1,"illegal VC grant");
                        end
                    if (p!=LOCAL && dut.mesh_row[y].mesh_col[x].router.is_valid_out[p]) begin
                        flit_t f;
                        f=dut.mesh_row[y].mesh_col[x].router.data_out[p];
                        link_flits++;
                        if (p==EAST && x==NX-1) seam_e++;
                        if (p==WEST && x==0) seam_w++;
                        if (p==SOUTH && y==NY-1) seam_s++;
                        if (p==NORTH && y==0) seam_n++;
                        if (f.flit_label==HEAD || f.flit_label==HEADTAIL) begin
                            if (direction(x,y,f.data.head_data.x_dest,f.data.head_data.y_dest)!=p)
                                $fatal(1,"nonminimal/wrong routing");
                            //Modify require after-phase replicas on seams; queued-mask assertion covers all other hops, Michael Tan, 20261104
                            if (((p==EAST && x==NX-1)||(p==WEST && x==0)||
                                 (p==SOUTH && y==NY-1)||(p==NORTH && y==0)) && int'(f.vc_id)<VC_NUM/2)
                                $fatal(1,"seam used before-phase replica");
                        end
                    end
                end
            end
        end
    end

    // Deterministic local backpressure, guaranteed eventual service for every VC.
    always @(negedge clk) begin
        for (int x=0;x<NX;x++) for (int y=0;y<NY;y++)
            for (int v=0;v<VC_NUM;v++)
                ready_in[x][y][v]=!stall || ((cycles+x*3+y+v)%13>=5);
    end

    task automatic reset_network;
        @(negedge clk); rst=1; vin='0; din='0; stall=0;
        repeat(4) @(negedge clk);
        for (int x=0;x<NX;x++) for (int y=0;y<NY;y++)
            for (int v=0;v<VC_NUM;v++) active_packet[x][y][v]=-1;
        rst=0;
    endtask

    // One packet or all sources concurrently; hold source VC for the entire packet.
    task automatic batch(input int sx,sy,dx,dy,round_id, input bit concurrent, input int len);
        int ids[NX][NY], sent[NX][NY], total, target, age;
        total=0; age=0;
        for (int x=0;x<NX;x++) for (int y=0;y<NY;y++) begin
            ids[x][y]=-1; sent[x][y]=0;
            if (concurrent || (x==sx && y==sy)) begin
                int id, ex, ey;
                id=packets++;
                if (id>=MAX_PACKETS) $fatal(1,"TB packet storage");
                ex=concurrent ? ((NX-1-x+round_id)%NX) : dx;
                ey=concurrent ? ((NY-1-y+round_id*2)%NY) : dy;
                ids[x][y]=id; dest_x[id]=ex; dest_y[id]=ey; lengths[id]=len; seen[id]=0;
                expected_link_flits+=len*( ((ex>x?ex-x:x-ex)<(NX-(ex>x?ex-x:x-ex))) ?
                    (ex>x?ex-x:x-ex):(NX-(ex>x?ex-x:x-ex)) );
                expected_link_flits+=len*( ((ey>y?ey-y:y-ey)<(NY-(ey>y?ey-y:y-ey))) ?
                    (ey>y?ey-y:y-ey):(NY-(ey>y?ey-y:y-ey)) );
                total++;
            end
        end
        target=packets;
        while (completed<target) begin
            @(negedge clk);
            vin='0;
            for (int x=0;x<NX;x++) for (int y=0;y<NY;y++) begin
                int id, b, vc;
                id=ids[x][y]; b=sent[x][y]; vc=(round_id+x+y)%4;
                if (id>=0 && b<len && ready_out[x][y][vc]) begin
                    din[x][y]='0; din[x][y].vc_id=vc;
                    din[x][y].flit_label=(len==1)?HEADTAIL:((b==0)?HEAD:((b==len-1)?TAIL:BODY));
                    if (b==0) begin
                        din[x][y].data.head_data.x_dest=dest_x[id];
                        din[x][y].data.head_data.y_dest=dest_y[id];
                        din[x][y].data.head_data.head_pl=id;
                    end else din[x][y].data.bt_pl=id*8+b;
                    vin[x][y]=1; sent[x][y]++;
                end
            end
            if (age++>4000) $fatal(1,"drain timeout completed=%0d target=%0d",completed,target);
        end
        @(negedge clk); vin='0;
        repeat(4) @(negedge clk);
    endtask

    initial begin
        ready_in='1;
        reset_network();
        for (int sx=0;sx<NX;sx++) for (int sy=0;sy<NY;sy++)
            for (int dx=0;dx<NX;dx++) for (int dy=0;dy<NY;dy++)
                batch(sx,sy,dx,dy,0,0,((sx+sy+dx+dy)%2)?1:4);
        stall=1;
        for (int r=0;r<12;r++) batch(0,0,0,0,r,1,(r%2)?1:4);
        reset_network();
        stall=1;
        batch(0,0,0,0,3,1,4);
        repeat(40) @(negedge clk);
        audit_empty=1;
        @(posedge clk); #2;
        if (packets!=completed) $fatal(1,"packet conservation");
        if (expected_link_flits!=link_flits) $fatal(1,"hop count got=%0d expected=%0d",link_flits,expected_link_flits);
        if (seam_e==0 || seam_s==0 || (NX>2 && seam_w==0) || (NY>2 && seam_n==0)) $fatal(1,"seam coverage");
        for (int id=0;id<packets;id++) if(seen[id]!=lengths[id]) $fatal(1,"missing flits");
        $display("[TB_TORUS_PHASE_INTEGRATION] PASSED size=%0dx%0d packets=%0d completed=%0d flits=%0d link_flits=%0d seams=%0d/%0d/%0d/%0d",
            NX,NY,packets,completed,received,link_flits,seam_e,seam_w,seam_s,seam_n);
        $finish;
    end
    initial begin #20000000; $fatal(1,"global timeout"); end
endmodule
