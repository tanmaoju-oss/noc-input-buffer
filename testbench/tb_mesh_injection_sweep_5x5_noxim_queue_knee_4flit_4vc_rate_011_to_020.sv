//Modify add independent performance-TB sweep for the 0.11-to-0.20 board comparison, Michael Tan, 20260908
`timescale 1ns / 1ps

import noc_params::*;

module tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_rate_011_to_020 #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 5,//Modify expand injection sweep mesh from 2x3 to 5x5, Michael Tan, 20260629
    parameter MESH_SIZE_Y = 5,//Modify expand injection sweep mesh from 2x3 to 5x5, Michael Tan, 20260629
    parameter RATE_NUM = 10,//Modify scan every 0.01 point from 0.11 through 0.20, Michael Tan, 20260908
    parameter WARMUP_CYCLES_PER_RATE = 200,//Modify use bounded Noxim-style warm-up window for complete Vivado runs, Michael Tan, 20260629
    parameter MEASURE_CYCLES_PER_RATE = 1000,//Modify use bounded Noxim-style measurement window for complete Vivado runs, Michael Tan, 20260629
    parameter DRAIN_CYCLES_PER_RATE = 8000,//Modify allow source queues to drain after measurement, Michael Tan, 20260701
    parameter SOURCE_QUEUE_DEPTH = 2048,//Modify add per-node source queue depth for Noxim-like traffic, Michael Tan, 20260701
    parameter PACKET_FLIT_NUM = 4,//Modify use 4-flit packet: HEAD + BODY + BODY + TAIL, Michael Tan, 20260709
    parameter SEED = 32'h20260622,
    parameter MAX_PACKETS = 262144//Modify allow longer Noxim-style runs, Michael Tan, 20260629
);
    typedef enum logic [0:0] {GEN_IDLE, GEN_SEND_PAYLOAD} gen_state_t;//Modify support multi-flit packet payload sending, Michael Tan, 20260709
    typedef enum logic [1:0] {PHASE_IDLE, PHASE_WARMUP, PHASE_MEASURE, PHASE_DRAIN} sim_phase_t;//Modify track Noxim-style simulation phase, Michael Tan, 20260629
    localparam FLIT_INDEX_SIZE = $clog2(PACKET_FLIT_NUM);//Modify reserve payload bits for per-packet flit index, Michael Tan, 20260723
    localparam PACKET_ID_SIZE = HEAD_PAYLOAD_SIZE;//Modify keep one packet-id width across HEAD/BODY/TAIL, Michael Tan, 20260723

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
    int active_flit_index [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];//Modify track BODY/TAIL flit index for 4-flit packet, Michael Tan, 20260709

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
    int pkt_expected_flit_index [MAX_PACKETS-1:0];//Modify track expected BODY/TAIL index for each packet, Michael Tan, 20260723

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
        if((VC_NUM != 4) || (VC_SIZE != 2))
            $fatal(1, "[TB_INJ_SWEEP_QUEUE_4VC] requires VC_NUM=4 and VC_SIZE=2, got %0d/%0d", VC_NUM, VC_SIZE);//Modify prevent non-four-VC results from using this experiment name, Michael Tan, 20260715
        if(PACKET_FLIT_NUM < 3 || (PACKET_ID_SIZE + FLIT_INDEX_SIZE) > FLIT_DATA_SIZE)
            $fatal(1, "[TB_INJ_SWEEP_QUEUE_4VC] packet_id + flit_index encoding does not fit: packet_flits=%0d payload_bits=%0d required_bits=%0d",
                   PACKET_FLIT_NUM, FLIT_DATA_SIZE, PACKET_ID_SIZE + FLIT_INDEX_SIZE);//Modify validate packet-id plus flit-index payload layout, Michael Tan, 20260723
        if((MESH_SIZE_X * MESH_SIZE_Y * (WARMUP_CYCLES_PER_RATE + MEASURE_CYCLES_PER_RATE)) > (1 << PACKET_ID_SIZE))
            $fatal(1, "[TB_INJ_SWEEP_QUEUE_4VC] one rate can generate more packets than the %0d-bit packet-id range",
                   PACKET_ID_SIZE);//Modify prevent packet-id truncation while allowing a larger backing table, Michael Tan, 20260723
        //dump_output();//Modify suppress the multi-gigabyte VCD because this comparison requires result statistics only, Michael Tan, 20260908
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
        $dumpvars(0, tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit_4vc_rate_011_to_020);//Modify bind the optional dump to the dedicated comparison TB, Michael Tan, 20260908
    endtask

    task initialize_global();
        int dummy_seed_value;

        clk = 0;
        rst = 1;
        cycle_count = 0;
        current_rate_permille = 0;
        current_phase = PHASE_IDLE;//Modify initialize Noxim-style phase state, Michael Tan, 20260629
        dummy_seed_value = $urandom(SEED);

        inj_rates_permille[0] = 110;//Modify add the 0.11 comparison point, Michael Tan, 20260908
        inj_rates_permille[1] = 120;//Modify add the 0.12 comparison point, Michael Tan, 20260908
        inj_rates_permille[2] = 130;//Modify add the 0.13 comparison point, Michael Tan, 20260908
        inj_rates_permille[3] = 140;//Modify add the 0.14 comparison point, Michael Tan, 20260908
        inj_rates_permille[4] = 150;//Modify add the 0.15 comparison point, Michael Tan, 20260908
        inj_rates_permille[5] = 160;//Modify add the 0.16 comparison point, Michael Tan, 20260908
        inj_rates_permille[6] = 170;//Modify add the 0.17 comparison point, Michael Tan, 20260908
        inj_rates_permille[7] = 180;//Modify add the 0.18 comparison point, Michael Tan, 20260908
        inj_rates_permille[8] = 190;//Modify add the 0.19 comparison point, Michael Tan, 20260908
        inj_rates_permille[9] = 200;//Modify add the 0.20 comparison point, Michael Tan, 20260908

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
            pkt_expected_flit_index[pkt] = 0;//Modify reset destination-side flit sequence checker, Michael Tan, 20260723
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
                active_flit_index[x][y] = 0;//Modify reset multi-flit sender index, Michael Tan, 20260709
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

                    GEN_SEND_PAYLOAD:
                    begin
                        if(is_on_off_o[x][y][0])
                        begin
                            send_payload_flit(x, y);//Modify send BODY or TAIL for 4-flit packet, Michael Tan, 20260709
                        end
                    end

                    default:
                    begin
                        gen_state[x][y] = GEN_IDLE;
                        active_packet_id[x][y] = -1;
                        active_flit_index[x][y] = 0;//Modify reset multi-flit sender after unexpected state, Michael Tan, 20260709
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
        data_cmd[src_x][src_y] = make_flit(pkt_id, HEAD, 0);//Modify pass explicit HEAD index into unified flit encoder, Michael Tan, 20260723

        active_packet_id[src_x][src_y] = pkt_id;
        active_flit_index[src_x][src_y] = 1;//Modify next flit after HEAD is payload index 1, Michael Tan, 20260709
        gen_state[src_x][src_y] = GEN_SEND_PAYLOAD;//Modify continue packet after HEAD until TAIL, Michael Tan, 20260709
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

    task send_payload_flit(input int src_x, input int src_y);
        int pkt_id;
        flit_label_t payload_label;

        pkt_id = active_packet_id[src_x][src_y];
        if(active_flit_index[src_x][src_y] == PACKET_FLIT_NUM-1)
            payload_label = TAIL;//Modify terminate 4-flit packet with TAIL, Michael Tan, 20260709
        else
            payload_label = BODY;//Modify send middle payload flits as BODY, Michael Tan, 20260709

        is_valid_cmd[src_x][src_y] = 1'b1;
        data_cmd[src_x][src_y] = make_flit(pkt_id, payload_label, active_flit_index[src_x][src_y]);//Modify encode packet ID and current flit index in BODY/TAIL, Michael Tan, 20260723

        if(payload_label == TAIL)
        begin
            gen_state[src_x][src_y] = GEN_IDLE;
            active_packet_id[src_x][src_y] = -1;
            active_flit_index[src_x][src_y] = 0;
        end
        else
        begin
            active_flit_index[src_x][src_y]++;//Modify advance through BODY flits before TAIL, Michael Tan, 20260709
        end
    endtask

    task choose_destination(input int src_x, input int src_y, output int dst_x, output int dst_y);
        do
        begin
            dst_x = $urandom_range(0, MESH_SIZE_X-1);
            dst_y = $urandom_range(0, MESH_SIZE_Y-1);
        end
        while(dst_x == src_x && dst_y == src_y);
    endtask

    function flit_t make_flit(input int pkt_id, input flit_label_t lab, input int flit_index);//Modify accept explicit flit index for payload encoding, Michael Tan, 20260723
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
            flit.data.bt_pl = '0;
            flit.data.bt_pl[FLIT_INDEX_SIZE-1:0] = flit_index[FLIT_INDEX_SIZE-1:0];//Modify encode flit index in low payload bits, Michael Tan, 20260723
            flit.data.bt_pl[FLIT_INDEX_SIZE +: PACKET_ID_SIZE] = pkt_id[PACKET_ID_SIZE-1:0];//Modify encode packet ID above flit index, Michael Tan, 20260723
        end

        return flit;
    endfunction

    function int decode_packet_id(input logic [FLIT_DATA_SIZE-1:0] payload);
        return payload[FLIT_INDEX_SIZE +: PACKET_ID_SIZE];//Modify decode packet ID from BODY/TAIL payload, Michael Tan, 20260723
    endfunction

    function int decode_flit_index(input logic [FLIT_DATA_SIZE-1:0] payload);
        return payload[FLIT_INDEX_SIZE-1:0];//Modify decode flit index from BODY/TAIL payload, Michael Tan, 20260723
    endfunction

    task monitor_outputs();
        int pkt_id;
        int flit_index;
        bit pkt_id_valid;

        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                if(is_valid_o[x][y])
                begin
                    if(data_o[x][y].flit_label == HEAD)
                    begin
                        pkt_id = data_o[x][y].data.head_data.head_pl;
                        check_packet_id(pkt_id, pkt_id_valid);//Modify guard packet-table access after decoding, Michael Tan, 20260723
                        if(pkt_id_valid && (x != pkt_dst_x[pkt_id] || y != pkt_dst_y[pkt_id]))
                        begin
                            error_seen++;//Modify include destination mismatch in result error count, Michael Tan, 20260723
                            $error("[TB_INJ_SWEEP] HEAD packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
                                   pkt_id, x, y, pkt_dst_x[pkt_id], pkt_dst_y[pkt_id]);
                        end
                        if(pkt_id_valid)
                        begin
                            if(pkt_head_seen[pkt_id])
                            begin
                                error_seen++;
                                $error("[TB_INJ_SWEEP] duplicate HEAD for packet %0d", pkt_id);//Modify detect duplicated packet start, Michael Tan, 20260723
                            end
                            pkt_head_seen[pkt_id] = 1'b1;
                            pkt_expected_flit_index[pkt_id] = 1;//Modify expect first BODY immediately after HEAD, Michael Tan, 20260723
                        end
                    end
                    else if(data_o[x][y].flit_label == TAIL)
                    begin
                        pkt_id = decode_packet_id(data_o[x][y].data.bt_pl);//Modify decode packet ID independently of flit index, Michael Tan, 20260723
                        flit_index = decode_flit_index(data_o[x][y].data.bt_pl);//Modify decode TAIL index for sequence checking, Michael Tan, 20260723
                        check_packet_id(pkt_id, pkt_id_valid);//Modify guard packet-table access after decoding, Michael Tan, 20260723
                        if(pkt_id_valid && (x != pkt_dst_x[pkt_id] || y != pkt_dst_y[pkt_id]))
                        begin
                            error_seen++;
                            $error("[TB_INJ_SWEEP] TAIL packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
                                   pkt_id, x, y, pkt_dst_x[pkt_id], pkt_dst_y[pkt_id]);
                        end
                        if(pkt_id_valid)
                        begin
                            if(!pkt_head_seen[pkt_id])
                            begin
                                error_seen++;
                                $error("[TB_INJ_SWEEP] TAIL packet %0d flit_index=%0d arrived before its HEAD", pkt_id, flit_index);//Modify identify malformed TAIL by packet and flit index, Michael Tan, 20260723
                            end
                            if(pkt_tail_seen[pkt_id])
                            begin
                                error_seen++;
                                $error("[TB_INJ_SWEEP] duplicate TAIL for packet %0d flit_index=%0d", pkt_id, flit_index);//Modify report duplicated TAIL index, Michael Tan, 20260723
                            end
                            if(flit_index != PACKET_FLIT_NUM-1 || flit_index != pkt_expected_flit_index[pkt_id])
                            begin
                                error_seen++;
                                $error("[TB_INJ_SWEEP] TAIL packet %0d has flit_index=%0d, expected=%0d and tail_index=%0d",
                                       pkt_id, flit_index, pkt_expected_flit_index[pkt_id], PACKET_FLIT_NUM-1);//Modify detect missing, duplicated, or reordered payload flits, Michael Tan, 20260723
                            end

                            pkt_tail_seen[pkt_id] = 1'b1;
                            pkt_expected_flit_index[pkt_id] = PACKET_FLIT_NUM;
                            if(pkt_is_measured[pkt_id])
                            begin
                                received_packets++;//Modify count received packets only for measurement-window injections, Michael Tan, 20260629
                                total_latency_cycles += (cycle_count - pkt_inject_cycle[pkt_id]);//Modify latency starts at packet generation time, Michael Tan, 20260701
                            end
                        end
                    end
                    else if(data_o[x][y].flit_label == BODY)
                    begin
                        pkt_id = decode_packet_id(data_o[x][y].data.bt_pl);//Modify decode packet ID independently of flit index, Michael Tan, 20260723
                        flit_index = decode_flit_index(data_o[x][y].data.bt_pl);//Modify decode BODY index for sequence checking, Michael Tan, 20260723
                        check_packet_id(pkt_id, pkt_id_valid);//Modify guard packet-table access after decoding, Michael Tan, 20260723
                        if(pkt_id_valid && (x != pkt_dst_x[pkt_id] || y != pkt_dst_y[pkt_id]))
                        begin
                            error_seen++;
                            $error("[TB_INJ_SWEEP] BODY packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
                                   pkt_id, x, y, pkt_dst_x[pkt_id], pkt_dst_y[pkt_id]);
                        end
                        if(pkt_id_valid)
                        begin
                            if(!pkt_head_seen[pkt_id] || pkt_tail_seen[pkt_id] ||
                               flit_index <= 0 || flit_index >= PACKET_FLIT_NUM-1 ||
                               flit_index != pkt_expected_flit_index[pkt_id])
                            begin
                                error_seen++;
                                $error("[TB_INJ_SWEEP] BODY packet %0d has flit_index=%0d, expected=%0d, head_seen=%0d tail_seen=%0d",
                                       pkt_id, flit_index, pkt_expected_flit_index[pkt_id],
                                       pkt_head_seen[pkt_id], pkt_tail_seen[pkt_id]);//Modify detect missing, duplicated, or reordered BODY flits, Michael Tan, 20260723
                            end
                            pkt_expected_flit_index[pkt_id] = flit_index + 1;//Modify advance sequence checker using decoded index, Michael Tan, 20260723
                        end
                    end
                    else
                    begin
                        error_seen++;
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

    task check_packet_id(input int pkt_id, output bit valid);//Modify return validity before packet-table access, Michael Tan, 20260723
        valid = (pkt_id >= 0 && pkt_id < next_packet_id);
        if(!valid)
        begin
            error_seen++;
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

        $fwrite(result_fd, "%0d %0d.%03d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
                current_rate_permille,
                current_rate_permille / 1000,//Modify print exact decimal injection rate for low-rate points, Michael Tan, 20260709
                current_rate_permille % 1000,//Modify print exact decimal injection rate for low-rate points, Michael Tan, 20260709
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
