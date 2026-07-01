`timescale 1ns / 1ps

import noc_params::*;

module tb_mesh_injection_sweep_5x5_noxim_queue #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 5,//Modify expand injection sweep mesh from 2x3 to 5x5, Michael Tan, 20260629
    parameter MESH_SIZE_Y = 5,//Modify expand injection sweep mesh from 2x3 to 5x5, Michael Tan, 20260629
    parameter RATE_NUM = 5,
    parameter WARMUP_CYCLES_PER_RATE = 200,//Modify use bounded Noxim-style warm-up window for complete Vivado runs, Michael Tan, 20260629
    parameter MEASURE_CYCLES_PER_RATE = 1000,//Modify use bounded Noxim-style measurement window for complete Vivado runs, Michael Tan, 20260629
    parameter DRAIN_CYCLES_PER_RATE = 8000,//Modify allow source queues to drain after measurement, Michael Tan, 20260701
    parameter SOURCE_QUEUE_DEPTH = 2048,//Modify add per-node source queue depth for Noxim-like traffic, Michael Tan, 20260701
    parameter SEED = 32'h20260622,
    parameter MAX_PACKETS = 262144//Modify allow longer Noxim-style runs, Michael Tan, 20260629
);
    typedef enum logic [0:0] {GEN_IDLE, GEN_SEND_TAIL} gen_state_t;
    typedef enum logic [1:0] {PHASE_IDLE, PHASE_WARMUP, PHASE_MEASURE, PHASE_DRAIN} sim_phase_t;//Modify track Noxim-style simulation phase, Michael Tan, 20260629

    logic clk;
    logic rst;

    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_cmd;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_cmd;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_cmd;
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_cmd;

    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_o;
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o;
    logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0];
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o;

    gen_state_t gen_state [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    int active_packet_id [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];

    int inj_rates_permille [RATE_NUM];
    int result_fd;
    int cycle_count;
    int current_rate_permille;
    sim_phase_t current_phase;//Modify separate warm-up, measurement, and drain statistics, Michael Tan, 20260629
    int next_packet_id;
    int attempted_packets;
    int enqueued_packets;//Modify count measurement packets accepted into source queues, Michael Tan, 20260701
    int injected_packets;
    int blocked_packets;
    int received_packets;
    int error_seen;
    longint total_latency_cycles;//Modify avoid latency accumulation overflow in queue-based sweep, Michael Tan, 20260701
    int drain_cycles_used;//Modify record actual drain time for queue-based run, Michael Tan, 20260701
    int max_source_queue_occupancy;//Modify track maximum per-node source queue occupancy, Michael Tan, 20260701

    int source_queue [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][SOURCE_QUEUE_DEPTH-1:0];//Modify add tb-side source queues, Michael Tan, 20260701
    int source_q_head [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];//Modify add source queue head pointers, Michael Tan, 20260701
    int source_q_tail [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];//Modify add source queue tail pointers, Michael Tan, 20260701
    int source_q_count [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];//Modify add source queue occupancy counters, Michael Tan, 20260701

    int pkt_dst_x [MAX_PACKETS-1:0];
    int pkt_dst_y [MAX_PACKETS-1:0];
    int pkt_inject_cycle [MAX_PACKETS-1:0];
    bit pkt_is_measured [MAX_PACKETS-1:0];//Modify count latency only for measurement-window packets, Michael Tan, 20260629
    bit pkt_head_seen [MAX_PACKETS-1:0];
    bit pkt_tail_seen [MAX_PACKETS-1:0];

    mesh #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .MESH_SIZE_X(MESH_SIZE_X),
        .MESH_SIZE_Y(MESH_SIZE_Y)
    )
    mesh (
        .clk(clk),
        .rst(rst),
        .is_on_off_i(is_on_off_cmd),
        .is_allocatable_i(is_allocatable_cmd),
        .data_i(data_cmd),
        .is_valid_i(is_valid_cmd),
        .data_o(data_o),
        .is_valid_o(is_valid_o),
        .is_on_off_o(is_on_off_o),
        .is_allocatable_o(is_allocatable_o),
        .error_o(error_o)
    );

    initial
    begin
        dump_output();
        initialize_global();
        open_result_file();

        for(int rate_idx=0; rate_idx < RATE_NUM; rate_idx++)
        begin
            run_one_rate(inj_rates_permille[rate_idx]);
        end

        $fclose(result_fd);
        $display("[TB_INJ_SWEEP_QUEUE] results written to injection_latency_results.txt");//Modify identify queue-based Noxim-style sweep log, Michael Tan, 20260701
        $finish;
    end

    always #5 clk = ~clk;

    always @(posedge clk)
    begin
        if(!rst)
        begin
            #1 monitor_outputs();
        end
    end

    task dump_output();
        $dumpfile("out.vcd");
        $dumpvars(0, tb_mesh_injection_sweep_5x5_noxim_queue);//Modify use independent queue-based Noxim-style 5x5 sweep top, Michael Tan, 20260701
    endtask

    task initialize_global();
        int dummy_seed_value;

        clk = 0;
        rst = 1;
        cycle_count = 0;
        current_rate_permille = 0;
        current_phase = PHASE_IDLE;//Modify initialize Noxim-style phase state, Michael Tan, 20260629
        dummy_seed_value = $urandom(SEED);

        inj_rates_permille[0] = 100;
        inj_rates_permille[1] = 200;
        inj_rates_permille[2] = 300;
        inj_rates_permille[3] = 400;
        inj_rates_permille[4] = 500;

        clear_all_inputs();
    endtask

    task open_result_file();
        result_fd = $fopen("injection_latency_results.txt", "w");
        if(result_fd == 0)
        begin
            $fatal(1, "[TB_INJ_SWEEP_QUEUE] cannot open injection_latency_results.txt");//Modify identify queue-based Noxim-style sweep fatal, Michael Tan, 20260701
        end

        $fwrite(result_fd, "injection_rate_permille injection_rate warmup_cycles measure_cycles drain_limit_cycles drain_used_cycles measure_generated measure_enqueued measure_queue_full measure_injected measure_received max_source_queue avg_latency_cycles_x1000 error_count\n");//Modify output queue-based Noxim-style statistics, Michael Tan, 20260701
    endtask

    task run_one_rate(input int rate_permille);
        reset_for_rate(rate_permille);
        release_reset();

        current_phase = PHASE_WARMUP;//Modify run warm-up traffic without latency statistics, Michael Tan, 20260629
        for(int cycle=0; cycle < WARMUP_CYCLES_PER_RATE; cycle++)
        begin
            @(posedge clk);
            cycle_count = cycle;
            drive_generators(1'b1);//Modify generate traffic during warm-up, Michael Tan, 20260629
        end

        current_phase = PHASE_MEASURE;//Modify count only packets injected in this measurement window, Michael Tan, 20260629
        for(int cycle=0; cycle < MEASURE_CYCLES_PER_RATE; cycle++)
        begin
            @(posedge clk);
            cycle_count = WARMUP_CYCLES_PER_RATE + cycle;
            drive_generators(1'b1);//Modify continue traffic during Noxim-style measurement window, Michael Tan, 20260629
        end

        current_phase = PHASE_DRAIN;//Modify stop new packet generation and drain source queues, Michael Tan, 20260701
        drain_queued_traffic();//Modify drain queued measurement packets before statistics, Michael Tan, 20260701

        write_one_rate_result();
    endtask

    task reset_for_rate(input int rate_permille);
        current_rate_permille = rate_permille;
        next_packet_id = 0;
        attempted_packets = 0;
        enqueued_packets = 0;//Modify reset measurement enqueue count, Michael Tan, 20260701
        injected_packets = 0;
        blocked_packets = 0;
        received_packets = 0;
        error_seen = 0;
        total_latency_cycles = 0;
        drain_cycles_used = 0;//Modify reset actual drain count, Michael Tan, 20260701
        max_source_queue_occupancy = 0;//Modify reset queue occupancy peak, Michael Tan, 20260701
        cycle_count = 0;
        current_phase = PHASE_IDLE;//Modify reset Noxim-style phase state per rate, Michael Tan, 20260629

        for(int pkt=0; pkt < MAX_PACKETS; pkt++)
        begin
            pkt_dst_x[pkt] = -1;
            pkt_dst_y[pkt] = -1;
            pkt_inject_cycle[pkt] = -1;
            pkt_is_measured[pkt] = 1'b0;//Modify clear measurement packet marker, Michael Tan, 20260629
            pkt_head_seen[pkt] = 1'b0;
            pkt_tail_seen[pkt] = 1'b0;
        end

        clear_all_inputs();

        rst <= 1'b1;
        repeat(3) @(posedge clk);
    endtask

    task release_reset();
        @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
    endtask

    task clear_all_inputs();
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                is_on_off_cmd[x][y] = {VC_NUM{1'b1}};
                is_allocatable_cmd[x][y] = {VC_NUM{1'b1}};
                is_valid_cmd[x][y] = 1'b0;
                data_cmd[x][y] = '0;
                gen_state[x][y] = GEN_IDLE;
                active_packet_id[x][y] = -1;
                source_q_head[x][y] = 0;//Modify reset source queue state, Michael Tan, 20260701
                source_q_tail[x][y] = 0;//Modify reset source queue state, Michael Tan, 20260701
                source_q_count[x][y] = 0;//Modify reset source queue state, Michael Tan, 20260701
            end
        end
    endtask

    task clear_all_injection_inputs();
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                is_valid_cmd[x][y] = 1'b0;
                data_cmd[x][y] = '0;
            end
        end
    endtask

    task has_pending_traffic(output bit active);
        active = 1'b0;
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                if(gen_state[x][y] != GEN_IDLE || source_q_count[x][y] != 0 || received_packets != injected_packets)//Modify also wait for in-flight measured packets in network, Michael Tan, 20260701
                    active = 1'b1;
            end
        end
    endtask

    task drain_queued_traffic();
        bit active;

        has_pending_traffic(active);
        while(active && drain_cycles_used < DRAIN_CYCLES_PER_RATE)//Modify bound source queue drain time, Michael Tan, 20260701
        begin
            @(posedge clk);
            cycle_count++;
            drain_cycles_used++;
            drive_generators(1'b0);//Modify inject queued packets without generating new packets, Michael Tan, 20260701
            has_pending_traffic(active);
        end

        @(posedge clk);
        cycle_count++;
        clear_all_injection_inputs();
    endtask

    task drive_generators(input bit allow_new_packet);
        int queued_pkt_id;

        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                is_valid_cmd[x][y] = 1'b0;
                data_cmd[x][y] = '0;

                if(allow_new_packet && $urandom_range(0, 999) < current_rate_permille)//Modify generate packets into source queues, Michael Tan, 20260701
                begin
                    create_packet(x, y);
                end

                unique case(gen_state[x][y])
                    GEN_IDLE:
                    begin
                        if(source_q_count[x][y] > 0 && is_on_off_o[x][y][0])//Modify inject oldest queued packet when router can accept it, Michael Tan, 20260701
                        begin
                            pop_source_queue(x, y, queued_pkt_id);
                            start_packet(x, y, queued_pkt_id);
                        end
                    end

                    GEN_SEND_TAIL:
                    begin
                        if(is_on_off_o[x][y][0])
                        begin
                            send_tail(x, y);
                            gen_state[x][y] = GEN_IDLE;
                            active_packet_id[x][y] = -1;
                        end
                    end

                    default:
                    begin
                        gen_state[x][y] = GEN_IDLE;
                        active_packet_id[x][y] = -1;
                    end
                endcase
            end
        end
    endtask

    task create_packet(input int src_x, input int src_y);
        int pkt_id;
        int dst_x;
        int dst_y;

        if(current_phase == PHASE_MEASURE)
            attempted_packets++;//Modify count measurement packets at generation time, Michael Tan, 20260701

        if(next_packet_id >= MAX_PACKETS)
        begin
            if(current_phase == PHASE_MEASURE)
                blocked_packets++;//Modify count packet table exhaustion as queue-full style loss, Michael Tan, 20260701
            return;
        end

        pkt_id = next_packet_id;
        choose_destination(src_x, src_y, dst_x, dst_y);

        pkt_dst_x[pkt_id] = dst_x;
        pkt_dst_y[pkt_id] = dst_y;
        pkt_inject_cycle[pkt_id] = cycle_count;
        pkt_is_measured[pkt_id] = (current_phase == PHASE_MEASURE);//Modify mark packets generated during measurement window, Michael Tan, 20260701
        next_packet_id++;

        push_source_queue(src_x, src_y, pkt_id);
    endtask

    task start_packet(input int src_x, input int src_y, input int pkt_id);
        is_valid_cmd[src_x][src_y] = 1'b1;
        data_cmd[src_x][src_y] = make_flit(pkt_id, HEAD);

        active_packet_id[src_x][src_y] = pkt_id;
        gen_state[src_x][src_y] = GEN_SEND_TAIL;
        if(pkt_is_measured[pkt_id])
            injected_packets++;//Modify count queue-departed measurement packets, Michael Tan, 20260701
    endtask

    task push_source_queue(input int src_x, input int src_y, input int pkt_id);
        if(source_q_count[src_x][src_y] < SOURCE_QUEUE_DEPTH)
        begin
            source_queue[src_x][src_y][source_q_tail[src_x][src_y]] = pkt_id;
            source_q_tail[src_x][src_y] = (source_q_tail[src_x][src_y] + 1) % SOURCE_QUEUE_DEPTH;
            source_q_count[src_x][src_y]++;
            if(source_q_count[src_x][src_y] > max_source_queue_occupancy)
                max_source_queue_occupancy = source_q_count[src_x][src_y];//Modify track queue pressure, Michael Tan, 20260701
            if(pkt_is_measured[pkt_id])
                enqueued_packets++;//Modify count measurement packets accepted into source queue, Michael Tan, 20260701
        end
        else
        begin
            if(pkt_is_measured[pkt_id])
                blocked_packets++;//Modify count measurement packet source queue overflow, Michael Tan, 20260701
        end
    endtask

    task pop_source_queue(input int src_x, input int src_y, output int pkt_id);
        pkt_id = source_queue[src_x][src_y][source_q_head[src_x][src_y]];
        source_q_head[src_x][src_y] = (source_q_head[src_x][src_y] + 1) % SOURCE_QUEUE_DEPTH;
        source_q_count[src_x][src_y]--;
    endtask

    task send_tail(input int src_x, input int src_y);
        int pkt_id;

        pkt_id = active_packet_id[src_x][src_y];
        is_valid_cmd[src_x][src_y] = 1'b1;
        data_cmd[src_x][src_y] = make_flit(pkt_id, TAIL);
    endtask

    task choose_destination(input int src_x, input int src_y, output int dst_x, output int dst_y);
        do
        begin
            dst_x = $urandom_range(0, MESH_SIZE_X-1);
            dst_y = $urandom_range(0, MESH_SIZE_Y-1);
        end
        while(dst_x == src_x && dst_y == src_y);
    endtask

    function flit_t make_flit(input int pkt_id, input flit_label_t lab);
        flit_t flit;

        flit = '0;
        flit.flit_label = lab;
        flit.vc_id = 0;

        if(lab == HEAD || lab == HEADTAIL)
        begin
            flit.data.head_data.x_dest = pkt_dst_x[pkt_id];
            flit.data.head_data.y_dest = pkt_dst_y[pkt_id];
            flit.data.head_data.head_pl = pkt_id[HEAD_PAYLOAD_SIZE-1:0];
        end
        else
        begin
            flit.data.bt_pl = pkt_id[FLIT_DATA_SIZE-1:0];
        end

        return flit;
    endfunction

    task monitor_outputs();
        int pkt_id;

        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                if(is_valid_o[x][y])
                begin
                    if(data_o[x][y].flit_label == HEAD)
                    begin
                        pkt_id = data_o[x][y].data.head_data.head_pl;
                        check_packet_id(pkt_id);
                        if(x != pkt_dst_x[pkt_id] || y != pkt_dst_y[pkt_id])
                        begin
                            $error("[TB_INJ_SWEEP] HEAD packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
                                   pkt_id, x, y, pkt_dst_x[pkt_id], pkt_dst_y[pkt_id]);
                        end
                        pkt_head_seen[pkt_id] = 1'b1;
                    end
                    else if(data_o[x][y].flit_label == TAIL)
                    begin
                        pkt_id = data_o[x][y].data.bt_pl;
                        check_packet_id(pkt_id);
                        if(x != pkt_dst_x[pkt_id] || y != pkt_dst_y[pkt_id])
                        begin
                            $error("[TB_INJ_SWEEP] TAIL packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
                                   pkt_id, x, y, pkt_dst_x[pkt_id], pkt_dst_y[pkt_id]);
                        end
                        if(!pkt_head_seen[pkt_id])
                            $error("[TB_INJ_SWEEP] TAIL packet %0d arrived before its HEAD", pkt_id);
                        if(pkt_tail_seen[pkt_id])
                            $error("[TB_INJ_SWEEP] duplicate TAIL for packet %0d", pkt_id);

                        pkt_tail_seen[pkt_id] = 1'b1;
                        if(pkt_is_measured[pkt_id])
                        begin
                            received_packets++;//Modify count received packets only for measurement-window injections, Michael Tan, 20260629
                            total_latency_cycles += (cycle_count - pkt_inject_cycle[pkt_id]);//Modify latency starts at packet generation time, Michael Tan, 20260701
                        end
                    end
                    else
                    begin
                        $error("[TB_INJ_SWEEP] unexpected output flit label %0d at (%0d,%0d)",
                               data_o[x][y].flit_label, x, y);
                    end
                end

                for(int port=0; port < PORT_NUM; port++)
                begin
                    for(int vc=0; vc < VC_NUM; vc++)
                    begin
                        if(error_o[x][y][port][vc] === 1'b1)
                        begin
                            error_seen++;
                            $error("[TB_INJ_SWEEP] error_o asserted at node=(%0d,%0d) port=%0d vc=%0d time=%0t",
                                   x, y, port, vc, $time);
                        end
                    end
                end
            end
        end
    endtask

    task check_packet_id(input int pkt_id);
        if(pkt_id < 0 || pkt_id >= next_packet_id)
        begin
            $error("[TB_INJ_SWEEP] observed invalid packet id %0d", pkt_id);
        end
    endtask

    task write_one_rate_result();
        longint average_latency_x1000;//Modify avoid average latency overflow after queueing, Michael Tan, 20260701

        average_latency_x1000 = 0;
        if(received_packets > 0)
        begin
            average_latency_x1000 = (total_latency_cycles * 1000) / received_packets;
        end

        $fwrite(result_fd, "%0d 0.%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
                current_rate_permille,
                current_rate_permille,
                WARMUP_CYCLES_PER_RATE,
                MEASURE_CYCLES_PER_RATE,
                DRAIN_CYCLES_PER_RATE,
                drain_cycles_used,
                attempted_packets,
                enqueued_packets,
                blocked_packets,
                injected_packets,
                received_packets,
                max_source_queue_occupancy,
                average_latency_x1000,
                error_seen);

        $display("[TB_INJ_SWEEP_QUEUE] rate=%0d warmup=%0d measure=%0d drain_limit=%0d drain_used=%0d generated=%0d enqueued=%0d queue_full=%0d injected=%0d received=%0d max_q=%0d avg_latency_x1000=%0d errors=%0d",
                 current_rate_permille, WARMUP_CYCLES_PER_RATE, MEASURE_CYCLES_PER_RATE, DRAIN_CYCLES_PER_RATE,
                 drain_cycles_used, attempted_packets, enqueued_packets, blocked_packets, injected_packets, received_packets, max_source_queue_occupancy,
                 average_latency_x1000, error_seen);//Modify log Noxim-style window settings, Michael Tan, 20260629

        if(error_seen != 0)
            $error("[TB_INJ_SWEEP_QUEUE] rate=%0d observed %0d error_o assertions", current_rate_permille, error_seen);//Modify identify queue-based Noxim-style sweep error, Michael Tan, 20260701
        if(received_packets != injected_packets)
            $error("[TB_INJ_SWEEP_QUEUE] rate=%0d injected_packets=%0d but received_packets=%0d",
                   current_rate_permille, injected_packets, received_packets);
    endtask

endmodule
