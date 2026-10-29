`timescale 1ns/1ps
import noc_params::*;
//Modify compare identical deterministic offered packet cohorts with full drain, Michael Tan, 20261028
module tb_congestion_latency_compare;
    parameter ALGORITHM=0, SEED=1234501, WARMUP=300, MEASURE=1200;
    localparam NX=MESH_SIZE_X, NY=MESH_SIZE_Y, NODES=NX*NY, MAX_PACKETS=512, FLITS=4;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    flit_t [NX-1:0][NY-1:0] tx,rx;
    logic [NX-1:0][NY-1:0] tx_valid,rx_valid;
    logic [NX-1:0][NY-1:0][VC_NUM-1:0] sink_on,sink_release,source_on,source_release,release_pending;
    logic [VC_NUM-1:0] errors[NX-1:0][NY-1:0][PORT_NUM-1:0];
    metrics_t [NX-1:0][NY-1:0] metrics;
    int generated[NODES],send_pid[NODES],send_beat[NODES];
    int birth[NODES][MAX_PACKETS],entered[NODES][MAX_PACKETS],destinations[NODES][MAX_PACKETS],received[NODES][MAX_PACKETS];
    int owner[NODES][VC_NUM];
    int total_latencies[$],queue_latencies[$],net_latencies[$];
    int cycle,rate_ppm,tx_flits,rx_flits,tx_heads,completed,offered,cohort;
    int window_heads,window_tails,backlog_stop,network_stop,source_stalls;
    int unsigned trace_hash;
    int csv_fd;
    mesh #(.BUFFER_SIZE(8),.MESH_SIZE_X(NX),.MESH_SIZE_Y(NY),.ALGORITHM(ALGORITHM),.AGGREGATION(0),.DECISION_REFERENCE(0)) dut(
        .clk(clk),.rst(rst),.error_o(errors),.data_o(rx),.is_valid_o(rx_valid),
        .is_on_off_i(sink_on),.is_allocatable_i(sink_release),.data_i(tx),.is_valid_i(tx_valid),
        .is_on_off_o(source_on),.is_allocatable_o(source_release),.metrics_debug_o(metrics));
    function automatic int unsigned mix(input int unsigned value);
        value=(value^(value>>16))*32'h7feb352d;
        value=(value^(value>>15))*32'h846ca68b;
        return value^(value>>16);
    endfunction
    function automatic flit_t make_flit(input int n,pid,beat);
        flit_t f;
        int dest;
        dest=destinations[n][pid];f='0;f.vc_id=pid%VC_NUM;
        if(beat==0) f.flit_label=HEAD;
        else if(beat==FLITS-1) f.flit_label=TAIL;
        else f.flit_label=BODY;
        f.data.head_data.x_source=n%NX;f.data.head_data.y_source=n/NX;
        f.data.head_data.x_dest=dest%NX;f.data.head_data.y_dest=dest/NX;
        f.data.head_data.packet_id=pid;f.data.head_data.backup=beat;
        f.data.head_data.head_pl='1;
        f.data.head_data.head_pl[63:0]={32'(n*MAX_PACKETS+pid),32'(beat)};
        return f;
    endfunction
    task automatic initialize_case;
        @(negedge clk);rst=1;tx='0;tx_valid='0;sink_on='1;sink_release='0;release_pending='0;
        offered=0;cohort=0;tx_flits=0;rx_flits=0;tx_heads=0;completed=0;
        window_heads=0;window_tails=0;source_stalls=0;backlog_stop=0;network_stop=0;
        trace_hash=32'h811c9dc5;
        total_latencies.delete();queue_latencies.delete();net_latencies.delete();
        for(int n=0;n<NODES;n++) begin
            generated[n]=0;send_pid[n]=0;send_beat[n]=0;
            for(int p=0;p<MAX_PACKETS;p++) begin birth[n][p]=-1;entered[n][p]=-1;destinations[n][p]=-1;received[n][p]=0; end
            for(int v=0;v<VC_NUM;v++) owner[n][v]=-1;
        end
        repeat(4) @(negedge clk);rst=0;
    endtask
    task automatic generate_packets;
        int unsigned key;
        int pid,dest;
        for(int n=0;n<NODES;n++) begin
            key=mix(32'(SEED)^32'(n+1)*32'h9e3779b9^32'(cycle+1)*32'h85ebca6b);
            if(key%1000000 < rate_ppm) begin
                pid=generated[n];
                if(pid>=MAX_PACKETS || pid>=(1<<PACKET_ID_SIZE)) $fatal(1,"packet table overflow");
                dest=mix(key^32'ha511e9b3)%(NODES-1);
                if(dest>=n) dest++;
                birth[n][pid]=cycle;destinations[n][pid]=dest;generated[n]++;offered++;
                if(cycle>=WARMUP) cohort++;
                trace_hash=(trace_hash^32'(cycle))*32'd16777619;
                trace_hash=(trace_hash^32'(n*MAX_PACKETS+pid))*32'd16777619;
                trace_hash=(trace_hash^32'(dest))*32'd16777619;
            end
        end
    endtask
    task automatic drive;
        int n,v;
        tx_valid='0;sink_on='1;sink_release=release_pending;release_pending='0;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
            n=y*NX+x;
            if(send_pid[n]<generated[n]) begin
                v=send_pid[n]%VC_NUM;
                if(source_on[x][y][v]===1'b1) begin
                    tx[x][y]=make_flit(n,send_pid[n],send_beat[n]);tx_valid[x][y]=1;
                end else source_stalls++;
            end
        end
    endtask
    task automatic sample;
        int n,src,pid,beat,v,identity;
        flit_t expected;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
            n=y*NX+x;
            for(int p=0;p<PORT_NUM;p++)
                if(errors[x][y][p] !== '0) $fatal(1,"router error alg=%0d rate=%0d cycle=%0d x=%0d y=%0d p=%0d bits=%b",ALGORITHM,rate_ppm,cycle,x,y,p,errors[x][y][p]);
            if(tx_valid[x][y]) begin
                pid=send_pid[n];beat=send_beat[n];tx_flits++;
                if(beat==0) begin
                    entered[n][pid]=cycle;tx_heads++;
                    if(cycle>=WARMUP && cycle<WARMUP+MEASURE) window_heads++;
                end
                send_beat[n]++;
                if(send_beat[n]==FLITS) begin send_pid[n]++;send_beat[n]=0; end
            end
            if(rx_valid[x][y]===1'b1) begin
                if($isunknown(rx[x][y])) $fatal(1,"unknown output data");
                src=int'(rx[x][y].data.head_data.y_source)*NX+int'(rx[x][y].data.head_data.x_source);
                pid=int'(rx[x][y].data.head_data.packet_id);beat=int'(rx[x][y].data.head_data.backup);v=int'(rx[x][y].vc_id);
                if(src>=NODES || pid>=MAX_PACKETS || beat>=FLITS) $fatal(1,"invalid output identity");
                if(pid>=generated[src] || entered[src][pid]<0) $fatal(1,"unknown packet");
                if(destinations[src][pid]!=n || beat!=received[src][pid]) $fatal(1,"wrong destination, duplicate or reordered flit");
                expected=make_flit(src,pid,beat);expected.vc_id=v;
                if(rx[x][y] !== expected) $fatal(1,"content corruption");
                identity=src*MAX_PACKETS+pid;
                if(beat==0) begin
                    if(owner[n][v]!=-1) $fatal(1,"interleaved output VC");
                    owner[n][v]=identity;
                end else if(owner[n][v]!=identity) $fatal(1,"output packet ownership mismatch");
                received[src][pid]++;rx_flits++;
                if(beat==FLITS-1) begin
                    completed++;owner[n][v]=-1;release_pending[x][y][v]=1;
                    if(cycle>=WARMUP && cycle<WARMUP+MEASURE) window_tails++;
                    if(birth[src][pid]>=WARMUP) begin
                        total_latencies.push_back(cycle-birth[src][pid]);
                        queue_latencies.push_back(entered[src][pid]-birth[src][pid]);
                        net_latencies.push_back(cycle-entered[src][pid]);
                    end
                end
            end else if(rx_valid[x][y]!==1'b0) $fatal(1,"unknown output valid");
        end
    endtask
    task automatic report_case;
        longint sum_total,sum_queue,sum_net;
        int p50,p95,p99,maximum;
        real mean_total,mean_queue,mean_net;
        if(total_latencies.size()!=cohort || cohort==0) $fatal(1,"cohort incomplete");
        sum_total=0;sum_queue=0;sum_net=0;
        foreach(total_latencies[i]) begin sum_total+=total_latencies[i];sum_queue+=queue_latencies[i];sum_net+=net_latencies[i]; end
        if(sum_total!=sum_queue+sum_net) $fatal(1,"latency decomposition failed");
        mean_total=real'(sum_total)/cohort;mean_queue=real'(sum_queue)/cohort;mean_net=real'(sum_net)/cohort;
        total_latencies.sort();
        p50=total_latencies[(50*cohort+99)/100-1];p95=total_latencies[(95*cohort+99)/100-1];p99=total_latencies[(99*cohort+99)/100-1];maximum=total_latencies[cohort-1];
        $fdisplay(csv_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.6f,%0.6f,%0.6f,%0.6f,%0.6f,%0.6f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%08x",ALGORITHM,rate_ppm,SEED,WARMUP,MEASURE,offered,cohort,completed,real'(cohort)/(NODES*MEASURE),real'(window_heads)/(NODES*MEASURE),real'(window_tails)/(NODES*MEASURE),mean_total,mean_queue,mean_net,p50,p95,p99,maximum,cycle,backlog_stop,network_stop,trace_hash);
        $fflush(csv_fd);
        $display("[LATENCY_RESULT] alg=%0d rate_ppm=%0d measured_packets=%0d total=%0.3f queue=%0.3f network=%0.3f p95=%0d p99=%0d tail_rate=%0.6f source_backlog_stop=%0d net_outstanding_stop=%0d trace=%08x PASS",ALGORITHM,rate_ppm,cohort,mean_total,mean_queue,mean_net,p95,p99,real'(window_tails)/(NODES*MEASURE),backlog_stop,network_stop,trace_hash);
    endtask
    task automatic run_rate(input int ppm);
        bit done;
        rate_ppm=ppm;initialize_case();done=0;
        for(int c=0;c<WARMUP+MEASURE+30000;c++) begin
            cycle=c;@(negedge clk);
            if(c<WARMUP+MEASURE) generate_packets();
            drive();@(posedge clk);sample();#1;
            if(c==WARMUP+MEASURE-1) begin backlog_stop=offered-tx_heads;network_stop=tx_heads-completed; end
            if(c>=WARMUP+MEASURE && completed==offered) begin done=1;break; end
            if(c>0 && c%5000==0) $display("[LATENCY_PROGRESS] alg=%0d rate_ppm=%0d cycle=%0d offered=%0d arrived=%0d",ALGORITHM,rate_ppm,c,offered,completed);
        end
        if(!done || completed!=offered || rx_flits!=offered*FLITS || tx_flits!=rx_flits) $fatal(1,"drain/conservation failed");
        for(int n=0;n<NODES;n++) begin
            if(send_pid[n]!=generated[n]) $fatal(1,"source queue not empty");
            for(int p=0;p<generated[n];p++) if(received[n][p]!=FLITS) $fatal(1,"missing packet");
            for(int v=0;v<VC_NUM;v++) if(owner[n][v]!=-1) $fatal(1,"sink packet still open");
        end
        repeat(20) begin
            cycle++;@(negedge clk);drive();@(posedge clk);sample();#1;
            for(int x=0;x<NX;x++) for(int y=0;y<NY;y++)
                if(metrics[x][y].node_total_flow !== 0) $fatal(1,"mesh not empty");
        end
        if(completed!=offered || rx_flits!=offered*FLITS) $fatal(1,"extra output after drain");
        report_case();
    endtask
    initial begin
        if(ALGORITHM!=0 && ALGORITHM!=4 || $bits(flit_t)!=258) $fatal(1,"invalid comparison configuration");
        csv_fd=$fopen("latency_summary.csv","w");if(!csv_fd) $fatal(1,"cannot open CSV");
        $fdisplay(csv_fd,"algorithm,rate_ppm,seed,warmup,measure,offered_packets,cohort_packets,completed_packets,actual_offered_ppc,accepted_heads_ppc,arrival_ppc,mean_total,mean_queue,mean_network,p50_total,p95_total,p99_total,max_total,finish_cycle,source_backlog_stop,net_outstanding_stop,trace_hash");
        run_rate(5000);run_rate(10000);run_rate(20000);run_rate(40000);run_rate(60000);run_rate(80000);
        $fclose(csv_fd);
        $display("[TB_CONGESTION_LATENCY_COMPARE] PASSED alg=%0d rates=6 seed=%0d",ALGORITHM,SEED);
        $finish;
    end
endmodule
