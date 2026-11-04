`timescale 1ns/1ps
import noc_params::*;
//Modify isolate saturated nonwrapping single-hop VC recycle timing without changing RTL, Michael Tan, 20261104
module tb_torus_singlehop_service;
    localparam NX=5,NY=5,PACKETS=256;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    flit_t [NX-1:0][NY-1:0] din,dout;
    logic [NX-1:0][NY-1:0] vin,vout;
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] ready_in='1,alloc_in='0,ready_out,alloc_out;
    logic [VC_NUM-1:0] errors [NX-1:0][NY-1:0][PORT_NUM-1:0];
`ifdef PERFORMANCE_MESH
    mesh #(.MESH_SIZE_X(NX),.MESH_SIZE_Y(NY)) dut(
`else
    torus #(.MESH_SIZE_X(NX),.MESH_SIZE_Y(NY)) dut(
`endif
      .clk(clk),.rst(rst),.data_i(din),.data_o(dout),.is_valid_i(vin),.is_valid_o(vout),
      .is_on_off_i(ready_in),.is_allocatable_i(alloc_in),.is_on_off_o(ready_out),.is_allocatable_o(alloc_out),.error_o(errors));
    logic [VC_NUM-1:0] source_free='1;
    int length=4,cycle=0,seen[PACKETS],active[VC_NUM],completed=0,received=0,link_count=0;
    int fd,sf;bit audit_empty=0;
    string outdir;
    //Modify count cycles at positive edge; observe events at stable negative edge after transfers via precomputed cycle, Michael Tan, 20261104
    int edge_cycle=0;
    always @(negedge clk) edge_cycle=cycle+1;
    always @(posedge clk) begin
      alloc_in<='0;
      if(!rst) begin
        cycle++;
        source_free|=alloc_out[1][1];
        if(vin[1][1]) $fdisplay(fd,"I,%0d,%0d,-1,-1",edge_cycle,din[1][1].vc_id);
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
          for(int p=0;p<PORT_NUM;p++) if(errors[x][y][p] !== '0) $fatal(1,"router error/X");
          if(vout[x][y] === 1'bx) $fatal(1,"unknown output valid");
          if(vout[x][y]) begin
            int id,b,v;
            if(x!=2 || y!=1 || $isunknown(dout[x][y])) $fatal(1,"wrong sink/unknown data");
            v=dout[x][y].vc_id;
            if(dout[x][y].flit_label==HEAD) begin
              id=dout[x][y].data.head_data.head_pl;
              if(id>=PACKETS || active[v]!=-1 || seen[id]!=0 || dout[x][y].data.head_data.x_dest!=2 || dout[x][y].data.head_data.y_dest!=1) $fatal(1,"bad header");
              active[v]=id;
            end else id=active[v];
            if(id<0 || id>=PACKETS) $fatal(1,"orphan body");
            b=seen[id];
            if(b>=length || dout[x][y].flit_label!=((b==0)?HEAD:((b==length-1)?TAIL:BODY))) $fatal(1,"duplicate/order");
            if(b>0 && dout[x][y].data.bt_pl!=id*32+b) $fatal(1,"payload mismatch");
            seen[id]++;received++;
            $fdisplay(fd,"S,%0d,%0d,%0d,%0d",edge_cycle,v,id,b);
            if(b==length-1) begin
              completed++;active[v]=-1;alloc_in[x][y][v]<=1;
            end
          end
        end
      end
    end
    always @(posedge clk) if(!rst) begin
      if(dut.mesh_row[1].mesh_col[1].router.is_valid_out[EAST]) begin
        flit_t f;int id,b;
        f=dut.mesh_row[1].mesh_col[1].router.data_out[EAST];
        if(f.flit_label==HEAD) begin id=f.data.head_data.head_pl;b=0;end
        else begin id=int'(f.data.bt_pl)/32;b=int'(f.data.bt_pl)%32;end
        $fdisplay(fd,"L,%0d,%0d,%0d,%0d",edge_cycle,f.vc_id,id,b);link_count++;
      end
      for(int v=0;v<VC_NUM;v++)
        if(!dut.mesh_row[1].mesh_col[1].router.vc_allocator.is_available_vc[EAST][v] && dut.mesh_row[1].mesh_col[1].router.is_allocatable_in[EAST][v])
          $fdisplay(fd,"R,%0d,%0d,-1,-1",edge_cycle,v);
    end
    for(genvar v=0;v<VC_NUM;v++) begin: grants
      always @(posedge clk) if(!rst && dut.mesh_row[1].mesh_col[1].router.ib2va_if.vc_valid[LOCAL][v])
        $fdisplay(fd,"A,%0d,%0d,%0d,-1",edge_cycle,dut.mesh_row[1].mesh_col[1].router.ib2va_if.vc_new[LOCAL][v],
          dut.mesh_row[1].mesh_col[1].router.input_block.generate_input_ports[LOCAL].input_port.generate_virtual_channels[v].input_buffer.data_o.data.head_data.head_pl);
    end
    for(genvar y=0;y<NY;y++) begin: check_y
      for(genvar x=0;x<NX;x++) begin: check_x
        for(genvar p=0;p<PORT_NUM;p++) begin: check_p
          for(genvar v=0;v<VC_NUM;v++) begin: check_v
            always @(posedge clk) if(audit_empty) begin
              if(dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.is_empty_o !== 1'b1 ||
                 dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.num_packets !== 0 ||
                 dut.mesh_row[y].mesh_col[x].router.input_block.generate_input_ports[p].input_port.generate_virtual_channels[v].input_buffer.write_packet_open !== 1'b0) $fatal(1,"residual input resources");
            end
          end
        end
        always @(posedge clk) if(audit_empty && dut.mesh_row[y].mesh_col[x].router.vc_allocator.is_available_vc !== '1) $fatal(1,"VC not released");
      end
    end
    initial begin
      int unused,id,b,vc,locked;
      unused=$value$plusargs("LENGTH=%d",length);
      if(length!=4 && length!=16) $fatal(1,"invalid length");
      if(!$value$plusargs("OUT=%s",outdir)) outdir=".";
      fd=$fopen({outdir,"/events.csv"},"w");if(fd==0) $fatal(1,"event file open");
      $fdisplay(fd,"kind,cycle,vc,packet,beat");
      for(int v=0;v<VC_NUM;v++) active[v]=-1;
      vin='0;din='0;id=0;b=0;locked=0;
      repeat(5) @(negedge clk);rst=0;
      while(completed<PACKETS) begin
        vin='0;
        vc=locked;
        if(id<PACKETS) begin
          if(b==0) begin
            bit found;
            found=0;vc=id%VC_NUM;
            for(int k=0;k<VC_NUM;k++)
              if(!found && source_free[(id+k)%VC_NUM] && ready_out[1][1][(id+k)%VC_NUM]) begin vc=(id+k)%VC_NUM;found=1;end
          end
          if(ready_out[1][1][vc] && (b!=0 || source_free[vc])) begin
            din[1][1]='0;din[1][1].vc_id=vc;
            din[1][1].flit_label=(b==0)?HEAD:((b==length-1)?TAIL:BODY);
            if(b==0) begin
              din[1][1].data.head_data.x_dest=2;din[1][1].data.head_data.y_dest=1;din[1][1].data.head_data.head_pl=id;
              source_free[vc]=0;locked=vc;
            end else din[1][1].data.bt_pl=id*32+b;
            vin[1][1]=1;
            if(b==length-1) begin id++;b=0;end else b++;
          end
        end
        if(cycle>30000) $fatal(1,"timeout");
        @(negedge clk);
      end
      vin='0;repeat(40) @(negedge clk);audit_empty=1;
      @(posedge clk);#2;
      if(received!=PACKETS*length || link_count!=received || source_free !== '1) $fatal(1,"conservation/source release");
      for(int k=0;k<PACKETS;k++) if(seen[k]!=length) $fatal(1,"missing packet");
      $fclose(fd);
      $display("[TB_TORUS_SINGLEHOP_SERVICE] PASSED length=%0d packets=%0d flits=%0d",length,PACKETS,received);
      $finish;
    end
endmodule
