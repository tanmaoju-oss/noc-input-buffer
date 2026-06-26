`timescale 1ns / 1ps

import noc_params::*;

module tb_mesh_injection_rate #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 2,
    parameter MESH_SIZE_Y = 3,
    parameter SIM_CYCLES = 500,
    parameter INJ_RATE_PERMILLE = 100,
    parameter SEED = 32'h20260617,
    parameter MAX_PACKETS = 65536
);
    typedef enum logic [0:0] {GEN_IDLE, GEN_SEND_TAIL} gen_state_t;

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

    int cycle_count;
    int runtime_inj_rate_permille;
    int next_packet_id;
    int attempted_packets;
    int injected_packets;
    int blocked_packets;
    int received_packets;
    int error_seen;
    int total_latency_cycles;

    int pkt_src_x [MAX_PACKETS-1:0];
    int pkt_src_y [MAX_PACKETS-1:0];
    int pkt_dst_x [MAX_PACKETS-1:0];
    int pkt_dst_y [MAX_PACKETS-1:0];
    int pkt_inject_cycle [MAX_PACKETS-1:0];
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
        initialize();
        clr_rst();
        run_injection_rate_test();
        final_checks();
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
        $dumpvars(0, tb_mesh_injection_rate);
    endtask

    task initialize();
        int dummy_seed_value;

        clk = 0;
        rst = 1;
        cycle_count = 0;
        runtime_inj_rate_permille = INJ_RATE_PERMILLE;
        next_packet_id = 0;
        attempted_packets = 0;
        injected_packets = 0;
        blocked_packets = 0;
        received_packets = 0;
        error_seen = 0;
        total_latency_cycles = 0;

        if($value$plusargs("INJ_RATE_PERMILLE=%d", runtime_inj_rate_permille))
        begin
            $display("[TB_INJ_RATE] plusarg INJ_RATE_PERMILLE=%0d", runtime_inj_rate_permille);
        end

        dummy_seed_value = $urandom(SEED);

        for(int pkt=0; pkt < MAX_PACKETS; pkt++)
        begin
            pkt_src_x[pkt] = -1;
            pkt_src_y[pkt] = -1;
            pkt_dst_x[pkt] = -1;
            pkt_dst_y[pkt] = -1;
            pkt_inject_cycle[pkt] = -1;
            pkt_head_seen[pkt] = 1'b0;
            pkt_tail_seen[pkt] = 1'b0;
        end

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
            end
        end
    endtask

    task clr_rst();
        repeat(2) @(posedge clk);
        rst <= 0;
    endtask

    task run_injection_rate_test();
        for(int cycle=0; cycle < SIM_CYCLES; cycle++)
        begin
            @(posedge clk);
            cycle_count = cycle;
            drive_generators();
        end

        @(posedge clk);
        //cycle_count keeps its last injection-cycle value here;//Original, Michael Tan, 20260617
        cycle_count = SIM_CYCLES;//Modify to keep latency accounting valid during drain cycles, Michael Tan, 20260617
        clear_all_injection_inputs();

        repeat(200)
        begin
            @(posedge clk);
            //cycle_count was not advanced in the drain window;//Original, Michael Tan, 20260617
            cycle_count++;//Modify to account packets received after injection stops, Michael Tan, 20260617
        end
    endtask

    task drive_generators();
        for(int x=0; x < MESH_SIZE_X; x++)
        begin
            for(int y=0; y < MESH_SIZE_Y; y++)
            begin
                is_valid_cmd[x][y] = 1'b0;
                data_cmd[x][y] = '0;

                unique case(gen_state[x][y])
                    GEN_IDLE:
                    begin
                        if($urandom_range(0, 999) < runtime_inj_rate_permille)
                        begin
                            attempted_packets++;
                            if(is_on_off_o[x][y][0] && next_packet_id < MAX_PACKETS)
                            begin
                                start_packet(x, y);
                            end
                            else
                            begin
                                blocked_packets++;
                            end
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

    task start_packet(input int src_x, input int src_y);
        int pkt_id;
        int dst_x;
        int dst_y;

        pkt_id = next_packet_id;
        choose_destination(src_x, src_y, dst_x, dst_y);

        pkt_src_x[pkt_id] = src_x;
        pkt_src_y[pkt_id] = src_y;
        pkt_dst_x[pkt_id] = dst_x;
        pkt_dst_y[pkt_id] = dst_y;
        pkt_inject_cycle[pkt_id] = cycle_count;

        is_valid_cmd[src_x][src_y] = 1'b1;
        data_cmd[src_x][src_y] = make_flit(pkt_id, HEAD);

        active_packet_id[src_x][src_y] = pkt_id;
        gen_state[src_x][src_y] = GEN_SEND_TAIL;
        next_packet_id++;
        injected_packets++;
    endtask

    task send_tail(input int src_x, input int src_y);
        int pkt_id;

        pkt_id = active_packet_id[src_x][src_y];
        is_valid_cmd[src_x][src_y] = 1'b1;
        data_cmd[src_x][src_y] = make_flit(pkt_id, TAIL);
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
                            $error("[TB_INJ_RATE] HEAD packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
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
                            $error("[TB_INJ_RATE] TAIL packet %0d arrived at (%0d,%0d), expected (%0d,%0d)",
                                   pkt_id, x, y, pkt_dst_x[pkt_id], pkt_dst_y[pkt_id]);
                        end
                        if(!pkt_head_seen[pkt_id])
                        begin
                            $error("[TB_INJ_RATE] TAIL packet %0d arrived before its HEAD", pkt_id);
                        end
                        if(pkt_tail_seen[pkt_id])
                        begin
                            $error("[TB_INJ_RATE] duplicate TAIL for packet %0d", pkt_id);
                        end
                        pkt_tail_seen[pkt_id] = 1'b1;
                        received_packets++;
                        total_latency_cycles += (cycle_count - pkt_inject_cycle[pkt_id]);
                    end
                    else
                    begin
                        $error("[TB_INJ_RATE] unexpected output flit label %0d at (%0d,%0d)",
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
                            $error("[TB_INJ_RATE] error_o asserted at node=(%0d,%0d) port=%0d vc=%0d time=%0t",
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
            $error("[TB_INJ_RATE] observed invalid packet id %0d", pkt_id);
        end
    endtask

    task final_checks();
        int average_latency_x1000;

        average_latency_x1000 = 0;
        if(received_packets > 0)
        begin
            average_latency_x1000 = (total_latency_cycles * 1000) / received_packets;
        end

        $display("[TB_INJ_RATE] SIM_CYCLES=%0d INJ_RATE_PERMILLE=%0d", SIM_CYCLES, runtime_inj_rate_permille);
        $display("[TB_INJ_RATE] attempted_packets=%0d injected_packets=%0d blocked_packets=%0d received_packets=%0d",
                 attempted_packets, injected_packets, blocked_packets, received_packets);
        $display("[TB_INJ_RATE] offered_rate_x1000=%0d accepted_rate_x1000=%0d avg_latency_cycles_x1000=%0d",
                 (attempted_packets * 1000) / (SIM_CYCLES * MESH_SIZE_X * MESH_SIZE_Y),
                 (injected_packets * 1000) / (SIM_CYCLES * MESH_SIZE_X * MESH_SIZE_Y),
                 average_latency_x1000);

        if(error_seen != 0)
            $error("[TB_INJ_RATE] observed %0d error_o assertions", error_seen);
        if(received_packets != injected_packets)
            $error("[TB_INJ_RATE] injected_packets=%0d but received_packets=%0d", injected_packets, received_packets);
        if(error_seen == 0 && received_packets == injected_packets)
            $display("[TB_INJ_RATE] PASSED");
    endtask

endmodule
