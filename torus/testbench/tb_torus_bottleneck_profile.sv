`timescale 1ns/1ps
import noc_params::*;
//Modify matched open-loop traffic, complete packet scoreboard and resource audit, Michael Tan, 20261104
module tb_torus_bottleneck_profile;
    localparam NX=5, NY=5, GEN=4000, WARM=1000, MAXP=32768, QSIZE=2048;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    flit_t [NX-1:0][NY-1:0] din,dout;
    logic [NX-1:0][NY-1:0] vin,vout;
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] ready_in,alloc_in,ready_out,alloc_out;
    logic [VC_NUM-1:0] errors [NX-1:0][NY-1:0][PORT_NUM-1:0];
`ifdef PERFORMANCE_MESH
    mesh #(.MESH_SIZE_X(NX),.MESH_SIZE_Y(NY)) dut(
`else
    torus #(.MESH_SIZE_X(NX),.MESH_SIZE_Y(NY)) dut(
`endif
        .clk(clk),.rst(rst),.data_i(din),.data_o(dout),.is_valid_i(vin),.is_valid_o(vout),
        .is_on_off_i(ready_in),.is_allocatable_i(alloc_in),
        .is_on_off_o(ready_out),.is_allocatable_o(alloc_out),.error_o(errors));
    int birth[MAXP], dx[MAXP],dy[MAXP],sx[MAXP],sy[MAXP],seen[MAXP],head_in[MAXP],tail_out[MAXP];
    int queue_id[NX][NY][QSIZE],count[NX][NY],cursor[NX][NY],beat[NX][NY];
    int active[NX][NY][VC_NUM];
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] source_free='1;
    //Modify isolate source-VC selection and observe source stalls, Michael Tan, 20261104
    //Modify nonintrusive per-hop stage counters and reservation events, Michael Tan, 20261104
    int profile_cycle=0, event_fd, profile_fd;
    always @(negedge clk) profile_cycle=cycles+1;
    int vc_stats[NX][NY][PORT_NUM][VC_NUM][16];
    int port_stats[NX][NY][PORT_NUM][6];
    int policy=0, selected_vc[NX][NY];
    int head_busy=0, head_busy_alternative=0, head_onoff=0, body_stall=0;
    int packets=0,completed=0,received=0,cycles=0,link_flits=0,expected_links=0;
    int window_in=0,window_out=0,rate=100,seed=1,traffic=0,fd,tf,sf;
    int unsigned random_state;
    bit audit_empty=0;
    string outdir;
    function automatic int unsigned random_word;
        random_state=random_state^(random_state<<13);
        random_state=random_state^(random_state>>17);
        random_state=random_state^(random_state<<5);
        return random_state;
    endfunction
    //Modify positive-edge receive checks and delayed sink TAIL deallocation pulses, Michael Tan, 20261104
    always @(posedge clk) begin
        alloc_in <= '0;
        if(!rst) begin
            cycles++;
            source_free |= alloc_out;
            for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
                for(int p=0;p<PORT_NUM;p++)
                    if(errors[x][y][p] !== '0) $fatal(1,"router error/X %0d,%0d,%0d",x,y,p);
                if(cycles>WARM && cycles<=GEN && vin[x][y]) window_in++;
                if(vout[x][y] === 1'bx) $fatal(1,"unknown valid");
                if(vout[x][y]) begin
                    int id,v,b;
                    if($isunknown(dout[x][y])) $fatal(1,"unknown flit");
                    v=dout[x][y].vc_id;
                    if(!ready_in[x][y][v]) $fatal(1,"sink backpressure violation");
                    if(dout[x][y].flit_label==HEAD) begin
                        id=dout[x][y].data.head_data.head_pl;
                        if(id<0 || id>=packets) $fatal(1,"unknown packet");
                        if(active[x][y][v]!=-1 || seen[id]!=0) $fatal(1,"duplicate/interleaved HEAD");
                        if(dout[x][y].data.head_data.x_dest!=x || dout[x][y].data.head_data.y_dest!=y)
                            $fatal(1,"corrupt header");
                        active[x][y][v]=id;
                    end else id=active[x][y][v];
                    if(id<0 || id>=packets) $fatal(1,"orphan BODY/TAIL");
                    b=seen[id];
                    if(dx[id]!=x || dy[id]!=y || b>=4) $fatal(1,"wrong destination/duplicate");
                    if(dout[x][y].flit_label!=((b==0)?HEAD:((b==3)?TAIL:BODY))) $fatal(1,"flit order");
                    if(b>0 && dout[x][y].data.bt_pl!=id*8+b) $fatal(1,"payload mismatch");
                    if(head_in[id]<birth[id] || cycles<head_in[id]) $fatal(1,"timestamp order");
                    seen[id]++;received++;
                    if(cycles>WARM && cycles<=GEN) window_out++;
                    if(b==3) begin
                        tail_out[id]=cycles;completed++;active[x][y][v]=-1;
                        alloc_in[x][y][v] <= 1;
                    end
                end
            end
        end
    end
    //Modify inspect actual router resources in either independently compiled design, Michael Tan, 20261104
    for(genvar y=0;y<NY;y++) begin: audit_y
        for(genvar x=0;x<NX;x++) begin: audit_x
            for(genvar p=0;p<PORT_NUM;p++) begin: audit_p
                for(genvar v=0;v<VC_NUM;v++) begin: audit_v
                    always @(posedge clk) if(audit_empty) begin
                        if(dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.is_empty_o !== 1'b1 ||
                           dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.num_packets !== 0 ||
                           dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.write_packet_open !== 1'b0)
                            $fatal(1,"residual FIFO/metadata/open packet");
                    end
                end
                always @(posedge clk) if(!rst && p!=LOCAL && dut.mesh_row[y].mesh_col[x].router.is_valid_out[p]) link_flits++;
            end
            always @(posedge clk) if(audit_empty && dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc !== '1)
                $fatal(1,"unreleased downstream VC");
        end
    end
    //Modify classify VA/SA using queued VA route and separately locked SA route, Michael Tan, 20261104
    for(genvar y=0;y<NY;y++) begin: profile_y
      for(genvar x=0;x<NX;x++) begin: profile_x
        for(genvar p=0;p<PORT_NUM;p++) begin: profile_p
          for(genvar v=0;v<VC_NUM;v++) begin: profile_v
            always @(posedge clk) if(!rst) begin
              if(dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_valid[p][v])
                $fdisplay(event_fd,"A,%0d,%0d,%0d,%0d,%0d,%0d",profile_cycle,x,y,
                  dut.mesh_row[y].mesh_col[x].router.ib2va_if.out_port[p][v],
                  dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_new[p][v],
                  dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.data_o.data.head_data.head_pl);
              if(!dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc[p][v] &&
                  dut.mesh_row[y].mesh_col[x].router.is_allocatable_in[p][v])
                $fdisplay(event_fd,"R,%0d,%0d,%0d,%0d,%0d,-1",profile_cycle,x,y,p,v);
              if(profile_cycle>WARM && profile_cycle<=GEN) begin
                int op,sv,occupancy;
                logic [VC_NUM-1:0] mask,available;
                op=dut.mesh_row[y].mesh_col[x].router.ib2va_if.out_port[p][v];
                mask=dut.mesh_row[y].mesh_col[x].router.ib2va_if.allowed_vcs[p][v];
                available=dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc[op];
                occupancy=dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.circular_buffer.num_flits;
                vc_stats[x][y][p][v][11]+=occupancy;
                if(occupancy>0) vc_stats[x][y][p][v][14]++;
                if(occupancy==8) vc_stats[x][y][p][v][10]++;
                if(dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_request[p][v]) begin
                  vc_stats[x][y][p][v][8]++;
                  if((mask & available)==0) begin
                    vc_stats[x][y][p][v][0]++;
                    if(available!=0) vc_stats[x][y][p][v][1]++;
                  end else if(!dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_valid[p][v]) vc_stats[x][y][p][v][2]++;
                  else vc_stats[x][y][p][v][3]++;
                  if($countones(mask)==1) vc_stats[x][y][p][v][12]++;
                  if($countones(mask)==4) vc_stats[x][y][p][v][13]++;
                  if(occupancy==4) vc_stats[x][y][p][v][15]++;
                end
                if(dut.mesh_row[y].mesh_col[x].router.ib2sa_if.switch_request[p][v]) begin
                  op=dut.mesh_row[y].mesh_col[x].router.ib2sa_if.out_port[p][v];
                  sv=dut.mesh_row[y].mesh_col[x].router.ib2sa_if.downstream_vc[p][v];
                  vc_stats[x][y][p][v][9]++;
                  if(!dut.mesh_row[y].mesh_col[x].router.is_on_off_in[op][sv]) vc_stats[x][y][p][v][4]++;
                  else if(dut.mesh_row[y].mesh_col[x].router.ib2sa_if.valid_sel[p] &&
                     dut.mesh_row[y].mesh_col[x].router.ib2sa_if.vc_sel[p]==v) vc_stats[x][y][p][v][6]++;
                  else vc_stats[x][y][p][v][5]++;
                end
                if(dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.accept_read) vc_stats[x][y][p][v][7]++;
              end
            end
          end
          always @(posedge clk) if(!rst) begin
            if(p!=LOCAL && dut.mesh_row[y].mesh_col[x].router.is_valid_out[p]) begin
              flit_t f;
              f=dut.mesh_row[y].mesh_col[x].router.data_out[p];
              if(f.flit_label==HEAD) $fdisplay(event_fd,"H,%0d,%0d,%0d,%0d,%0d,%0d",profile_cycle,x,y,p,f.vc_id,f.data.head_data.head_pl);
              if(f.flit_label==TAIL) $fdisplay(event_fd,"T,%0d,%0d,%0d,%0d,%0d,%0d",profile_cycle,x,y,p,f.vc_id,int'(f.data.bt_pl)/8);
            end
            if(profile_cycle>WARM && profile_cycle<=GEN) begin
              bit pending,none_eligible;
              pending=0;none_eligible=0;
              for(int ip=0;ip<PORT_NUM;ip++) for(int iv=0;iv<VC_NUM;iv++)
                if(dut.mesh_row[y].mesh_col[x].router.ib2va_if.vc_request[ip][iv] &&
                   dut.mesh_row[y].mesh_col[x].router.ib2va_if.out_port[ip][iv]==p) begin
                  pending=1;
                  if((dut.mesh_row[y].mesh_col[x].router.ib2va_if.allowed_vcs[ip][iv] &
                      dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc[p])==0) none_eligible=1;
                end
              if(dut.mesh_row[y].mesh_col[x].router.is_valid_out[p]) port_stats[x][y][p][0]++;
              if(pending) port_stats[x][y][p][1]++;
              if(pending && !dut.mesh_row[y].mesh_col[x].router.is_valid_out[p]) port_stats[x][y][p][2]++;
              if(none_eligible && !dut.mesh_row[y].mesh_col[x].router.is_valid_out[p]) port_stats[x][y][p][3]++;
              port_stats[x][y][p][4]+=VC_NUM-$countones(dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc[p]);
              port_stats[x][y][p][5]++;
            end
          end
        end
      end
    end
    initial begin
        int unused;
        unused=$value$plusargs("POLICY=%d",policy);
        if(policy<0 || policy>1) $fatal(1,"invalid policy");
        unused=$value$plusargs("RATE=%d",rate);
        unused=$value$plusargs("SEED=%d",seed);
        unused=$value$plusargs("TRAFFIC=%d",traffic);
        if(!$value$plusargs("OUT=%s",outdir)) outdir=".";
        if(rate<=0 || rate>1200 || seed==0 || traffic<0 || traffic>1) $fatal(1,"invalid campaign parameters");
        random_state=seed;
        tf=$fopen({outdir,"/trace.csv"},"w");
        if(tf==0) $fatal(1,"trace file open");
        $fdisplay(tf,"id,birth,sx,sy,dx,dy");
        // Pre-generate all births independently of any DUT backpressure.
        for(int c=1;c<=GEN;c++) for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
            int unsigned choice;
            choice=random_word();
            if(choice%10000<rate) begin
                int id,target,source,hx,hy;
                id=packets++;source=x*NY+y;
                if(id>=MAXP || count[x][y]>=QSIZE) $fatal(1,"traffic storage overflow");
                choice=random_word();target=(source+1+choice%(NX*NY-1))%(NX*NY);
                sx[id]=x;sy[id]=y;birth[id]=c;head_in[id]=-1;
                dx[id]=(traffic==0)?target/NY:(x+NX-1)%NX;
                dy[id]=(traffic==0)?target%NY:(y+NY-1)%NY;
                queue_id[x][y][count[x][y]++]=id;
                hx=(dx[id]>x)?dx[id]-x:x-dx[id];hy=(dy[id]>y)?dy[id]-y:y-dy[id];
`ifndef PERFORMANCE_MESH
                hx=(hx<NX-hx)?hx:NX-hx;hy=(hy<NY-hy)?hy:NY-hy;
`endif
                expected_links+=4*(hx+hy);
                $fdisplay(tf,"%0d,%0d,%0d,%0d,%0d,%0d",id,c,x,y,dx[id],dy[id]);
            end
        end
        $fclose(tf);
        event_fd=$fopen({outdir,"/events.csv"},"w");
        if(event_fd==0) $fatal(1,"event file open");
        $fdisplay(event_fd,"kind,cycle,x,y,port,vc,id");
        ready_in='1;vin='0;din='0;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) for(int v=0;v<VC_NUM;v++) active[x][y][v]=-1;
        repeat(5) @(negedge clk);
        rst=0;
        // Drive before the next positive edge; one ordered packet cursor per source.
        while(cycles<GEN || completed<packets) begin
            vin='0;
            for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
                if(cursor[x][y]<count[x][y]) begin
                    int id,b,v;
                    id=queue_id[x][y][cursor[x][y]];b=beat[x][y];v=id%VC_NUM;
                    //Modify choose only HEAD admission VC; preserve the entire packet lock, Michael Tan, 20261104
                    if(b!=0 && policy==1) v=selected_vc[x][y];
                    if(b==0 && policy==1) begin
                        bit found;
                        found=0;
                        for(int k=0;k<VC_NUM;k++) begin
                            int candidate;
                            candidate=(id+k)%VC_NUM;
                            if(!found && source_free[x][y][candidate] && ready_out[x][y][candidate]) begin
                                v=candidate;found=1;
                            end
                        end
                    end
                    if(birth[id]<=cycles+1) begin
                        if(b==0 && !source_free[x][y][v]) begin
                            bit alternative;
                            alternative=0;head_busy++;
                            for(int k=0;k<VC_NUM;k++)
                                if(source_free[x][y][k] && ready_out[x][y][k]) alternative=1;
                            if(alternative) head_busy_alternative++;
                        end else if(b==0 && !ready_out[x][y][v]) head_onoff++;
                        else if(b!=0 && !ready_out[x][y][v]) body_stall++;
                    end
                    if(birth[id]<=cycles+1 && ready_out[x][y][v] && (b!=0 || source_free[x][y][v])) begin
                        din[x][y]='0;din[x][y].vc_id=v;
                        din[x][y].flit_label=(b==0)?HEAD:((b==3)?TAIL:BODY);
                        if(b==0) begin
                            din[x][y].data.head_data.x_dest=dx[id];
                            din[x][y].data.head_data.y_dest=dy[id];
                            din[x][y].data.head_data.head_pl=id;
                            selected_vc[x][y]=v;
                            head_in[id]=cycles+1;source_free[x][y][v]=0;
                        end else din[x][y].data.bt_pl=id*8+b;
                        vin[x][y]=1;
                        if(b==3) begin cursor[x][y]++;beat[x][y]=0;end
                        else beat[x][y]++;
                    end
                end
            end
            if(cycles>GEN+100000) $fatal(1,"drain timeout packets=%0d completed=%0d",packets,completed);
            @(negedge clk);
        end
        vin='0;
        sf=$fopen({outdir,"/summary.csv"},"w");
        if(sf==0) $fatal(1,"summary file open");
        $fdisplay(sf,"rate,seed,traffic,generated,completed,flits,window_in,window_out,last_cycle,link_flits");
        $fdisplay(sf,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",rate,seed,traffic,packets,completed,received,window_in,window_out,cycles,link_flits);
        $fclose(sf);
        sf=$fopen({outdir,"/stalls.csv"},"w");
        if(sf==0) $fatal(1,"stalls file open");
        $fdisplay(sf,"policy,head_busy,head_busy_alternative,head_onoff,body_stall");
        $fdisplay(sf,"%0d,%0d,%0d,%0d,%0d",policy,head_busy,head_busy_alternative,head_onoff,body_stall);
        $fclose(sf);
        repeat(40) @(negedge clk);
        audit_empty=1;
        @(posedge clk);#2;
        if(completed!=packets || received!=4*packets || link_flits!=expected_links || source_free !== '1) $fatal(1,"conservation/hops/source VC release");
        fd=$fopen({outdir,"/packets.csv"},"w");
        if(fd==0) $fatal(1,"packet file open");
        $fdisplay(fd,"id,birth,head_in,tail_out");
        for(int id=0;id<packets;id++) begin
            if(seen[id]!=4) $fatal(1,"missing packet");
            $fdisplay(fd,"%0d,%0d,%0d,%0d",id,birth[id],head_in[id],tail_out[id]);
        end
        $fclose(fd);
        $fclose(event_fd);
        profile_fd=$fopen({outdir,"/vc_profile.csv"},"w");
        if(profile_fd==0) $fatal(1,"profile file open");
        $fdisplay(profile_fd,"x,y,port,vc,va_no_eligible,va_other_free,va_arb,va_grant,sa_onoff,sa_arb,sa_grant,reads,va_requests,sa_requests,full_cycles,occupancy_sum,mask_one,mask_four,nonempty,va_full_packet");
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
          $fwrite(profile_fd,"%0d,%0d,%0d,%0d",x,y,p,v);
          for(int m=0;m<16;m++) $fwrite(profile_fd,",%0d",vc_stats[x][y][p][v][m]);
          $fwrite(profile_fd,"\n");
        end
        $fclose(profile_fd);
        profile_fd=$fopen({outdir,"/port_profile.csv"},"w");
        if(profile_fd==0) $fatal(1,"port profile file open");
        $fdisplay(profile_fd,"x,y,port,transfers,pending_va,idle_pending_va,idle_blocked_va,reserved_sum,window_cycles");
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) for(int p=0;p<PORT_NUM;p++) begin
          $fwrite(profile_fd,"%0d,%0d,%0d",x,y,p);
          for(int m=0;m<6;m++) $fwrite(profile_fd,",%0d",port_stats[x][y][p][m]);
          $fwrite(profile_fd,"\n");
        end
        $fclose(profile_fd);
        $display("[TB_TORUS_BOTTLENECK_PROFILE] PASSED rate=%0d seed=%0d traffic=%0d packets=%0d completed=%0d link_flits=%0d",rate,seed,traffic,packets,completed,link_flits);
        $finish;
    end
endmodule
