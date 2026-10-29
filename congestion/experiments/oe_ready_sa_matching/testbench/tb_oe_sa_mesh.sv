//Modify isolate fixed legal three-hop continuation from checked two-hop parent, Michael Tan, 20261029
`timescale 1ns/1ps
import noc_params::*;
//Modify self-check real 13x13 congestion mesh with deterministic content and full drain, Michael Tan, 20261028
//Modify exercise isolated ready/matching policies with original long-packet and backpressure regression, Michael Tan, 20261029
//Modify isolate flit scheduling while all allocated routes/VCs remain unchanged, Michael Tan, 20261029
module tb_oe_sa_mesh;
    parameter SA_FULL=0;
    parameter POLICY_MODE=4,FAST_REOPEN=1;
    parameter ALGORITHM=4, REFERENCE=0, AGG=0, PACKETS=6;
    localparam NX=MESH_SIZE_X, NY=MESH_SIZE_Y, NODES=NX*NY;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    flit_t [NX-1:0][NY-1:0] tx,rx;
    logic [NX-1:0][NY-1:0] tx_valid,rx_valid;
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] sink_on,sink_release,source_on,source_release;
    logic [VC_NUM-1:0] error_o[NX-1:0][NY-1:0][PORT_NUM-1:0];
    metrics_t [NX-1:0][NY-1:0] metrics;
    int send_pid[NODES],send_beat[NODES],received_beats[NODES][PACKETS];
    int active_source[NODES][VC_NUM],active_pid[NODES][VC_NUM];
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] release_pending;
    int cycle,phase,total_tx,total_rx,complete,source_stalls,sink_stalls;
    mesh #(.BUFFER_SIZE(8),.MESH_SIZE_X(NX),.MESH_SIZE_Y(NY),.ALGORITHM(ALGORITHM),.AGGREGATION(AGG),.DECISION_REFERENCE(REFERENCE)) dut(
        .clk(clk),.rst(rst),.error_o(error_o),.data_o(rx),.is_valid_o(rx_valid),
        .is_on_off_i(sink_on),.is_allocatable_i(sink_release),.data_i(tx),.is_valid_i(tx_valid),
        .is_on_off_o(source_on),.is_allocatable_o(source_release),.metrics_debug_o(metrics));
    function automatic int length(input int pid);
        case(pid%5) 0:return 1; 1:return 2; 2:return 4; 3:return 8; default:return 12; endcase
    endfunction
    function automatic int destination(input int source,pid);
        int x,y;
        case(phase)
            0:return NODES-1-source; // mirror, with all four directional quadrants
            1:begin x=(source*7+pid*3+1)%NX; y=(source*11+pid*5+2)%NY; return y*NX+x; end
            default:return (NY/2)*NX+NX/2; // converging hotspot
        endcase
    endfunction
    function automatic flit_t packet_flit(input int source,pid,beat);
        flit_t f;
        int dest;
        dest=destination(source,pid); f='0;
        f.vc_id=pid%VC_NUM;
        if(length(pid)==1) f.flit_label=HEADTAIL;
        else if(beat==0) f.flit_label=HEAD;
        else if(beat==length(pid)-1) f.flit_label=TAIL;
        else f.flit_label=BODY;
        f.data.head_data.x_source=source%NX; f.data.head_data.y_source=source/NX;
        f.data.head_data.x_dest=dest%NX; f.data.head_data.y_dest=dest/NX;
        f.data.head_data.packet_id=pid;
        f.data.head_data.backup=beat;
        // Exercise both high and low bits of the temporarily retained wide payload.
        for(int b=0;b<HEAD_PAYLOAD_SIZE;b++)
            f.data.head_data.head_pl[b]=((b*13+source*7+pid*3+beat+phase) % 11)<5;
        return f;
    endfunction
    task automatic reset_phase;
        @(negedge clk); rst=1; tx='0;tx_valid='0;sink_on='0;sink_release='0;release_pending='0;
        total_tx=0;total_rx=0;complete=0;source_stalls=0;sink_stalls=0;cycle=0;
        for(int n=0;n<NODES;n++) begin
            send_pid[n]=0;send_beat[n]=0;
            for(int p=0;p<PACKETS;p++) received_beats[n][p]=0;
            for(int v=0;v<VC_NUM;v++) begin active_source[n][v]=-1;active_pid[n][v]=-1; end
        end
        repeat(4) @(negedge clk);
        rst=0;
    endtask
    task automatic drive;
        int n,v;
        tx_valid='0;sink_on='0;
        sink_release=release_pending;release_pending='0;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
            n=y*NX+x;
            for(int k=0;k<VC_NUM;k++)
                sink_on[x][y][k]=(cycle>=80 && (cycle+n*3+k*5)%19>=5);
            if(send_pid[n]<PACKETS) begin
                v=send_pid[n]%VC_NUM;
                if(source_on[x][y][v]===1'b1) begin
                    tx[x][y]=packet_flit(n,send_pid[n],send_beat[n]);tx_valid[x][y]=1;
                end else source_stalls++;
            end
        end
    endtask
    task automatic sample;
        int n,source,pid,beat,v,dest;
        flit_t expected;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
            n=y*NX+x;
            for(int p=0;p<PORT_NUM;p++)
                if(error_o[x][y][p] !== '0)
                    $fatal(1,"router error phase=%0d cycle=%0d node=(%0d,%0d) port=%0d bits=%b",phase,cycle,x,y,p,error_o[x][y][p]);
            if(tx_valid[x][y]) begin
                total_tx++;
                send_beat[n]++;
                if(send_beat[n]==length(send_pid[n])) begin send_pid[n]++;send_beat[n]=0; end
            end
            if(rx_valid[x][y] === 1'b1) begin
                if($isunknown(rx[x][y])) $fatal(1,"unknown ejection flit");
                source=int'(rx[x][y].data.head_data.y_source)*NX+int'(rx[x][y].data.head_data.x_source);
                pid=int'(rx[x][y].data.head_data.packet_id);beat=int'(rx[x][y].data.head_data.backup);v=int'(rx[x][y].vc_id);
                if(source<0 || source>=NODES || pid<0 || pid>=PACKETS || beat>=length(pid)) $fatal(1,"invalid packet identity");
                dest=destination(source,pid);
                if(n!=dest) $fatal(1,"wrong destination source=%0d pid=%0d got=%0d expected=%0d",source,pid,n,dest);
                if(sink_on[x][y][v] !== 1'b1) $fatal(1,"ejection ignored sink backpressure");
                if(beat!=received_beats[source][pid]) $fatal(1,"duplicate or reordered beat source=%0d pid=%0d got=%0d expected=%0d",source,pid,beat,received_beats[source][pid]);
                expected=packet_flit(source,pid,beat);expected.vc_id=v;
                if(rx[x][y] !== expected) $fatal(1,"payload or label corruption source=%0d pid=%0d beat=%0d",source,pid,beat);
                if(beat==0) begin
                    if(active_source[n][v]!=-1) $fatal(1,"interleaved packet header on output VC");
                    active_source[n][v]=source;active_pid[n][v]=pid;
                end else if(active_source[n][v]!=source || active_pid[n][v]!=pid) $fatal(1,"output VC packet ownership mismatch");
                received_beats[source][pid]++;total_rx++;
                if(beat==length(pid)-1) begin
                    active_source[n][v]=-1;active_pid[n][v]=-1;release_pending[x][y][v]=1;complete++;
                end
            end else if(rx_valid[x][y] !== 1'b0) $fatal(1,"unknown ejection valid");
            for(int v2=0;v2<VC_NUM;v2++) if(!sink_on[x][y][v2]) sink_stalls++;
        end
    endtask
    task automatic run_phase;
        bit done;
        int expected_flits;
        reset_phase();done=0;
        for(int c=0;c<30000;c++) begin
            cycle=c;@(negedge clk);drive();@(posedge clk);sample();#1;
            if(complete==NODES*PACKETS) begin done=1;break; end
            if(c>0 && c%2000==0) $display("[MESH_PROGRESS] alg=%0d phase=%0d cycle=%0d tx=%0d rx=%0d complete=%0d",ALGORITHM,phase,c,total_tx,total_rx,complete);
        end
        if(!done) $fatal(1,"drain timeout alg=%0d phase=%0d tx=%0d rx=%0d complete=%0d",ALGORITHM,phase,total_tx,total_rx,complete);
        expected_flits=0;for(int p=0;p<PACKETS;p++) expected_flits+=NODES*length(p);
        if(total_tx!=expected_flits || total_rx!=expected_flits) $fatal(1,"flit conservation failed");
        for(int n=0;n<NODES;n++) begin
            if(send_pid[n]!=PACKETS) $fatal(1,"source queue not drained");
            for(int p=0;p<PACKETS;p++) if(received_beats[n][p]!=length(p)) $fatal(1,"missing packet flits");
            for(int v=0;v<VC_NUM;v++) if(active_source[n][v]!=-1) $fatal(1,"consumer packet still open");
        end
        repeat(20) begin
            cycle++;@(negedge clk);drive();@(posedge clk);sample();#1;
            for(int x=0;x<NX;x++) for(int y=0;y<NY;y++)
                if(metrics[x][y].node_total_flow !== 0) $fatal(1,"router storage not empty after drain");
        end
        if(total_rx!=expected_flits || complete!=NODES*PACKETS) $fatal(1,"extra flit after completion");
        if(source_stalls==0) $fatal(1,"source backpressure coverage missing");
        $display("[MESH_PHASE] PASSED alg=%0d reference=%0d aggregation=%0d phase=%0d packets=%0d flits=%0d cycles=%0d source_stalls=%0d sink_stalls=%0d",ALGORITHM,REFERENCE,AGG,phase,complete,total_rx,cycle,source_stalls,sink_stalls);
    endtask
    initial begin
        if(dut.mesh_row[0].mesh_col[0].router.switch_allocator.FULL_MATCHING!=SA_FULL) $fatal(1,"SA mode mismatch");//Modify reject unrecorded scheduler changes, Michael Tan, 20261029
        if(dut.mesh_row[0].mesh_col[0].router.vc_allocator.SELECTION_MODE!=POLICY_MODE) $fatal(1,"mesh policy mismatch");//Modify reject mode mismatch, Michael Tan, 20261029
        if($bits(flit_t)!=258) $fatal(1,"temporary received flit format changed");
        for(phase=0;phase<3;phase++) run_phase();
        $display("[TB_OE_SA_MESH] PASSED alg=%0d reference=%0d aggregation=%0d phases=3 packets_per_phase=%0d",ALGORITHM,REFERENCE,AGG,NODES*PACKETS);
        $finish;
    end
endmodule
