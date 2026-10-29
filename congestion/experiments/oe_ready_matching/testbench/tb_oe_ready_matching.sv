`timescale 1ns/1ps
import noc_params::*;
//Modify compare identical deterministic offered packet cohorts with full drain, Michael Tan, 20261028
//Modify retain the original cohort scoreboard for a dedicated admission-protocol stress test, Michael Tan, 20261029
//Modify compare existing legal-OE policies using unchanged official RTL and identical workload, Michael Tan, 20261029
//Modify isolate late legal-candidate/ready-VC selection with complete existing scoreboard, Michael Tan, 20261029
//Modify controlled joint matching derivative of checkpoint806fc4f, Michael Tan, 20261029
module tb_oe_ready_matching;
    parameter POLICY_MODE=0,FAST_REOPEN=0;
    parameter RATE_PPM=60000;
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
    //Modify observe actual network FIFO use without altering offered traffic or admission, Michael Tan, 20261029
    wire [PORT_NUM-1:0][VC_NUM-1:0][3:0] occupancy[NX][NY];
    int max_network_occupancy;
    longint network_above_four;
    for(genvar x=0;x<NX;x++) begin: observe_x
        for(genvar y=0;y<NY;y++) begin: observe_y
            assign occupancy[x][y]=dut.mesh_row[y].mesh_col[x].router.state_occupancy;
        end
    end
    task automatic observe_storage;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) for(int p=1;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
            if(occupancy[x][y][p][v]>8 || $isunknown(occupancy[x][y][p][v])) $fatal(1,"invalid network occupancy");
            if(occupancy[x][y][p][v]>max_network_occupancy) max_network_occupancy=occupancy[x][y][p][v];
            if(cycle>=WARMUP && cycle<WARMUP+MEASURE && occupancy[x][y][p][v]>4) network_above_four++;
        end
    endtask
    //Modify profile current-protocol resource losses without influencing grants or traffic, Michael Tan, 20261029
    localparam NK=14;
    //Modify independently check every granted route against OE legal candidates, Michael Tan, 20261029
    longint legal_checks[NX][NY];
    logic [PORT_NUM*VC_NUM-1:0] flags[NX][NY][NK];
    wire [PORT_NUM-1:0] links[NX][NY];
    logic [VC_NUM-1:0] grant_vcs[NX][NY][PORT_NUM];
    longint counts[NK][2],vc_grants[VC_NUM],link_counts[NX][NY][PORT_NUM];
    function automatic logic [PORT_NUM-1:0] oe_candidates(input int x,y,sx,dx,dy);
        logic [PORT_NUM-1:0] c;
        c='0;
        if(dx==x && dy==y) c[LOCAL]=1;
        else if(dx==x) c[dy<y?NORTH:SOUTH]=1;
        else if(dx>x) begin
            if(dy==y) c[EAST]=1;
            else begin
                if(x%2==1 || x==sx) c[dy<y?NORTH:SOUTH]=1;
                if(dx%2==1 || dx-x!=1) c[EAST]=1;
            end
        end else begin
            c[WEST]=1;
            if(x%2==0 && dy!=y) c[dy<y?NORTH:SOUTH]=1;
        end
        return c;
    endfunction
    for(genvar px=0;px<NX;px++) begin: current_x
        for(genvar py=0;py<NY;py++) begin: current_y
            wire [PORT_NUM-1:0][VC_NUM-1:0] avail=dut.mesh_row[py].mesh_col[px].router.vc_allocator.is_available_vc;
            wire [PORT_NUM-1:0][VC_NUM-1:0] ready=dut.mesh_row[py].mesh_col[px].router.is_on_off_in;
            wire flit_t head[PORT_NUM][VC_NUM];
            for(genvar ip=0;ip<PORT_NUM;ip++) begin: port_head
                for(genvar iv=0;iv<VC_NUM;iv++) begin: vc_head
                    assign head[ip][iv]=dut.mesh_row[py].mesh_col[px].router.input_block.generate_input_ports[ip].input_port.data_out[iv];
                end
            end
            //Modify audit real runtime decisions rather than infer legality from algorithm names, Michael Tan, 20261029
            always @(posedge clk) begin: audit_legal_grants
                int number,used_output[PORT_NUM],used_input[PORT_NUM];//Modify reject duplicate matcher grants, Michael Tan, 20261029
                logic [PORT_NUM-1:0] c;
                number=0;
                for(int k=0;k<PORT_NUM;k++) begin used_output[k]=0;used_input[k]=0;end
                if(rst) legal_checks[px][py]<=0;
                else begin
                    for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++)
                        if(dut.mesh_row[py].mesh_col[px].router.ib2va_if.vc_valid[p][v]) begin
                            c=oe_candidates(px,py,int'(head[p][v].data.head_data.x_source),int'(head[p][v].data.head_data.x_dest),int'(head[p][v].data.head_data.y_dest));
                            if(ALGORITHM!=0 && c[dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]]!==1'b1)
                                $fatal(1,"runtime route violates OE candidate constraints");
                            //Modify verify each live grant is legal, unowned, and writable under active policies, Michael Tan, 20261029
                            if(!dut.mesh_row[py].mesh_col[px].router.ib2va_if.candidates[p][v][dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]]) $fatal(1,"grant outside stored candidates");
                            if(!avail[dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]][dut.mesh_row[py].mesh_col[px].router.ib2va_if.vc_new[p][v]]) $fatal(1,"grant reserved VC");
                            if(POLICY_MODE!=0 && !ready[dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]][dut.mesh_row[py].mesh_col[px].router.ib2va_if.vc_new[p][v]]) $fatal(1,"active grant to closed VC");
                            //Modify assert one granted VC per input port and one winner per output, Michael Tan, 20261029
                            used_input[p]++;used_output[dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]]++;
                            if(used_input[p]>1 || used_output[dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]]>1) $fatal(1,"duplicate input/output grant");
                            number++;
                        end
                    legal_checks[px][py]<=legal_checks[px][py]+number;
                end
            end
            assign links[px][py]=dut.mesh_row[py].mesh_col[px].router.is_valid_out;
            always_comb begin: classify
                int outp,assigned,chosen;
                bit granted,alt_free,alt_ready;
                logic [PORT_NUM-1:0] candidates,raw_sa,raw_va;
                raw_sa='0;raw_va='0;
                for(int k=0;k<NK;k++) flags[px][py][k]='0;
                for(int p=0;p<PORT_NUM;p++) grant_vcs[px][py][p]='0;
                for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++) begin
                    outp=int'(dut.mesh_row[py].mesh_col[px].router.ib2va_if.granted_port[p][v]);
                    candidates=oe_candidates(px,py,int'(head[p][v].data.head_data.x_source),int'(head[p][v].data.head_data.x_dest),int'(head[p][v].data.head_data.y_dest));
                    if(ALGORITHM==0) begin candidates='0;candidates[outp]=1;end
                    alt_free=0;alt_ready=0;
                    for(int d=0;d<PORT_NUM;d++) if(d!=outp && candidates[d]) begin
                        if(|avail[d]) alt_free=1;
                        if(|(avail[d]&ready[d])) alt_ready=1;
                    end
                    if(dut.mesh_row[py].mesh_col[px].router.ib2va_if.vc_request[p][v]) begin
                        if(|avail[outp]) raw_va[outp]=1;
                        if(dut.mesh_row[py].mesh_col[px].router.ib2va_if.vc_valid[p][v]) begin
                            flags[px][py][2][p*VC_NUM+v]=1;
                            chosen=int'(dut.mesh_row[py].mesh_col[px].router.ib2va_if.vc_new[p][v]);
                            grant_vcs[px][py][outp][chosen]=1;
                            if(!ready[outp][chosen]) begin
                                flags[px][py][8][p*VC_NUM+v]=1;
                                if(|(avail[outp]&ready[outp])) flags[px][py][9][p*VC_NUM+v]=1;
                            end
                        end else if(|avail[outp]) flags[px][py][1][p*VC_NUM+v]=1;
                        else begin
                            flags[px][py][0][p*VC_NUM+v]=1;
                            if(alt_free) flags[px][py][6][p*VC_NUM+v]=1;
                            if(alt_ready) flags[px][py][7][p*VC_NUM+v]=1;
                        end
                    end
                    if(dut.mesh_row[py].mesh_col[px].router.ib2sa_if.switch_request[p][v]) begin
                        assigned=int'(dut.mesh_row[py].mesh_col[px].router.ib2sa_if.downstream_vc[p][v]);
                        granted=dut.mesh_row[py].mesh_col[px].router.ib2sa_if.valid_sel[p] && dut.mesh_row[py].mesh_col[px].router.ib2sa_if.vc_sel[p]==v;
                        if(ready[outp][assigned]) raw_sa[outp]=1;
                        if(granted) flags[px][py][5][p*VC_NUM+v]=1;
                        else if(!ready[outp][assigned]) begin
                            flags[px][py][3][p*VC_NUM+v]=1;
                            if(|(avail[outp]&ready[outp])) flags[px][py][10][p*VC_NUM+v]=1;
                            if(alt_ready) flags[px][py][11][p*VC_NUM+v]=1;
                        end else flags[px][py][4][p*VC_NUM+v]=1;
                    end
                end
                for(int d=0;d<PORT_NUM;d++) begin
                    if(raw_sa[d] && !links[px][py][d]) flags[px][py][12][d*VC_NUM]=1;
                    if(raw_va[d] && !(|grant_vcs[px][py][d])) flags[px][py][13][d*VC_NUM]=1;
                end
            end
        end
    end
    task automatic current_sample;
        if(cycle>=WARMUP && cycle<WARMUP+MEASURE) begin
            for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) begin
                for(int k=0;k<NK;k++) for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++)
                    if(flags[x][y][k][p*VC_NUM+v]) counts[k][p==LOCAL?0:1]++;
                for(int p=0;p<PORT_NUM;p++) begin
                    if(links[x][y][p]) link_counts[x][y][p]++;
                    for(int v=0;v<VC_NUM;v++) if(grant_vcs[x][y][p][v]) vc_grants[v]++;
                end
            end
        end
    endtask
    task automatic current_report;
        int fd;
        longint checked;
        //Modify expose complete runtime legality coverage for the report, Michael Tan, 20261029
        checked=0;for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) checked+=legal_checks[x][y];
        $display("[OE_LEGALITY] runtime_grants=%0d",checked);
        fd=$fopen("current_waits.csv","w");if(!fd) $fatal(1,"wait CSV error");
        $fdisplay(fd,"kind,local_cycles,network_cycles");
        for(int k=0;k<NK;k++) $fdisplay(fd,"%0d,%0d,%0d",k,counts[k][0],counts[k][1]);
        $fclose(fd);
        fd=$fopen("current_vcs.csv","w");if(!fd) $fatal(1,"VC CSV error");
        $fdisplay(fd,"vc,grants");for(int v=0;v<VC_NUM;v++) $fdisplay(fd,"%0d,%0d",v,vc_grants[v]);$fclose(fd);
        fd=$fopen("current_links.csv","w");if(!fd) $fatal(1,"link CSV error");
        $fdisplay(fd,"x,y,port,flits");
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) for(int p=1;p<PORT_NUM;p++)
            if((p==NORTH&&y>0)||(p==SOUTH&&y<NY-1)||(p==WEST&&x>0)||(p==EAST&&x<NX-1))
                $fdisplay(fd,"%0d,%0d,%0d,%0d",x,y,p,link_counts[x][y][p]);
        $fclose(fd);
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
            drive();@(posedge clk);sample();observe_storage();current_sample();#1;//Modify sample occupancy without driving DUT, Michael Tan, 20261029
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
            cycle++;@(negedge clk);drive();@(posedge clk);sample();observe_storage();current_sample();#1;//Modify sample occupancy without driving DUT, Michael Tan, 20261029
            for(int x=0;x<NX;x++) for(int y=0;y<NY;y++)
                if(metrics[x][y].node_total_flow !== 0) $fatal(1,"mesh not empty");
        end
        if(completed!=offered || rx_flits!=offered*FLITS) $fatal(1,"extra output after drain");
        report_case();
    endtask
    initial begin
        //Modify validate compile switches before accepting a recorded result, Michael Tan, 20261029
        if(dut.mesh_row[0].mesh_col[0].router.vc_allocator.SELECTION_MODE!=POLICY_MODE) $fatal(1,"policy mismatch");
        if(dut.mesh_row[0].mesh_col[0].router.input_block.generate_input_ports[0].input_port.generate_virtual_channels[0].input_buffer.circular_buffer.REOPEN_THRESHOLD!=(FAST_REOPEN?7:2)) $fatal(1,"flow mismatch");
        if((ALGORITHM!=0 && ALGORITHM!=2 && ALGORITHM!=3 && ALGORITHM!=4) || $bits(flit_t)!=258)//Modify permit existing OneAware/TwoAware under the same OE turn rules, Michael Tan, 20261029
            $fatal(1,"invalid comparison configuration");
        csv_fd=$fopen("latency_summary.csv","w");if(!csv_fd) $fatal(1,"cannot open CSV");
        $fdisplay(csv_fd,"algorithm,rate_ppm,seed,warmup,measure,offered_packets,cohort_packets,completed_packets,actual_offered_ppc,accepted_heads_ppc,arrival_ppc,mean_total,mean_queue,mean_network,p50_total,p95_total,p99_total,max_total,finish_cycle,source_backlog_stop,net_outstanding_stop,trace_hash");
        //Modify change only the tested rate selection, retaining generated traffic and sample cohort, Michael Tan, 20261029
        max_network_occupancy=0;network_above_four=0;
        //Modify initialize passive current-protocol counters once for the single-rate run, Michael Tan, 20261029
        for(int k=0;k<NK;k++) for(int g=0;g<2;g++) counts[k][g]=0;
        for(int v=0;v<VC_NUM;v++) vc_grants[v]=0;
        for(int x=0;x<NX;x++) for(int y=0;y<NY;y++) for(int p=0;p<PORT_NUM;p++) link_counts[x][y][p]=0;
        run_rate(RATE_PPM);
        current_report();
        $display("[ADMISSION_OCCUPANCY] max_network_flits=%0d above_four_vc_cycles=%0d",max_network_occupancy,network_above_four);
        $fclose(csv_fd);
        $display("[TB_OE_READY_MATCHING] PASSED alg=%0d rates=1 seed=%0d",ALGORITHM,SEED);
        $finish;
    end
endmodule
