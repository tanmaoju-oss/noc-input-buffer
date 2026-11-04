`timescale 1ns/1ps
import noc_params::*;
//Modify independently verify replicated dateline phase resources, Michael Tan, 20261104
//Modify exhaustive coordinates, input classes, labels and invalid addresses, Michael Tan, 20261102
module torus_phase_rc_case #(parameter NX=5, NY=5)(output bit done);
    logic [DEST_ADDR_SIZE_X-1:0] dx;
    logic [DEST_ADDR_SIZE_Y-1:0] dy;
    logic [VC_SIZE-1:0] vc;
    flit_label_t label;
    port_t ports[NX][NY][PORT_NUM];
    logic [VC_NUM-1:0] masks[NX][NY][PORT_NUM];
    logic errors[NX][NY][PORT_NUM];
    for (genvar x=0;x<NX;x++) for (genvar y=0;y<NY;y++) for (genvar p=0;p<PORT_NUM;p++) begin: units
        rc_unit #(.X_CURRENT(x),.Y_CURRENT(y),.DEST_ADDR_SIZE_X(DEST_ADDR_SIZE_X),
            .DEST_ADDR_SIZE_Y(DEST_ADDR_SIZE_Y),.TORUS_MODE(1),.NETWORK_SIZE_X(NX),
            .NETWORK_SIZE_Y(NY),.INPUT_PORT(p)) dut(
            .x_dest_i(dx),.y_dest_i(dy),.flit_label_i(label),.input_vc_i(vc),
            .out_port_o(ports[x][y][p]),.allowed_vcs_o(masks[x][y][p]),.route_error_o(errors[x][y][p]));
    end
    int checks=0;
    initial begin
        done=0;
        for (int lab=0;lab<4;lab++) for (int v=0;v<VC_NUM;v++)
            for (int tx=0;tx<(1<<DEST_ADDR_SIZE_X);tx++) for (int ty=0;ty<(1<<DEST_ADDR_SIZE_Y);ty++) begin
                dx=tx; dy=ty; vc=v; label=flit_label_t'(lab); #1;
                for (int x=0;x<NX;x++) for (int y=0;y<NY;y++) for (int p=0;p<PORT_NUM;p++) begin
                    port_t want;
                    logic [VC_NUM-1:0] mask;
                    bit bad, past;
                    int fwd, rev, cls;
                    want=LOCAL; mask='1; bad=0; past=0; cls=0;
                    if (lab==HEAD || lab==HEADTAIL) begin
                        if(tx>=NX || ty>=NY) begin bad=1; mask=0; end
                        else begin
                            if (tx!=x) begin
                                fwd=(tx-x+NX)%NX; rev=(x-tx+NX)%NX;
                                want=(fwd<=rev)?EAST:WEST;
                                past=(p==EAST || p==WEST) && v>=VC_NUM/2;
                                past|=(want==EAST && x==NX-1)||(want==WEST && x==0);
                                mask=past?VC_AFTER_MASK:VC_BEFORE_MASK;
                                bad=(p==NORTH || p==SOUTH);
                            end else if (ty!=y) begin
                                fwd=(ty-y+NY)%NY; rev=(y-ty+NY)%NY;
                                want=(fwd<=rev)?SOUTH:NORTH;
                                past=(p==NORTH || p==SOUTH) && v>=VC_NUM/2;
                                past|=(want==SOUTH && y==NY-1)||(want==NORTH && y==0);
                                mask=past?VC_AFTER_MASK:VC_BEFORE_MASK;
                                bad=0;
                            end
                            if(want==LOCAL) mask=VC_LOCAL_MASK;
                            if(bad) mask=0;
                        end
                    end
                    if (ports[x][y][p]!==want || masks[x][y][p]!==mask || errors[x][y][p]!==bad)
                        $fatal(1,"RC mismatch %0dx%0d current=%0d,%0d dest=%0d,%0d port=%0d vc=%0d label=%0d",NX,NY,x,y,tx,ty,p,v,lab);
                    checks++;
                end
            end
        $display("RC case %0dx%0d checks=%0d",NX,NY,checks);
        done=1;
    end
endmodule
module tb_torus_phase_rc;
    wire [3:0] done;
    torus_phase_rc_case #(5,5) odd_size(done[0]);
    torus_phase_rc_case #(4,4) even_size(done[1]);
    torus_phase_rc_case #(2,3) small_size(done[2]);
    torus_phase_rc_case #(2,2) double_links(done[3]);
    initial begin wait (&done); $display("[TB_TORUS_PHASE_RC] PASSED"); $finish; end
    initial begin #100000; $fatal(1,"RC timeout"); end
endmodule
