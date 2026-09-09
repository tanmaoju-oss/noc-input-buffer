import noc_params::*;

//Modify replace the monolithic 3D tracker with generated per-source BRAM trackers, Michael Tan, 20260909
module noc_board_latency_monitor #(
    parameter MESH_SIZE_X = noc_params::MESH_SIZE_X,
    parameter MESH_SIZE_Y = noc_params::MESH_SIZE_Y,
    parameter PACKET_FLIT_NUM = 4,
    parameter COUNTER_WIDTH = 32,
    parameter integer TRACK_TABLE_DEPTH = 2048
) (
    input logic clk,
    input logic rst,
    input logic measurement_enable_i,
    input logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_enqueued_i,
    input logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_queue_full_i,
    input logic [HEAD_PAYLOAD_SIZE-1:0] enqueued_packet_id_i [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0],
    input flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_data_i,
    input logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_valid_i,
    output logic [COUNTER_WIDTH-1:0] packets_enqueued_o,
    output logic [COUNTER_WIDTH-1:0] queue_full_o,
    output logic [COUNTER_WIDTH-1:0] tails_received_o,
    output logic [COUNTER_WIDTH-1:0] unmatched_tails_o,
    output logic [COUNTER_WIDTH-1:0] timestamp_overwrites_o,
    output logic [2*COUNTER_WIDTH-1:0] total_latency_cycles_o,
    output logic debug_tail_event_o,
    output logic [HEAD_PAYLOAD_SIZE-1:0] debug_tail_packet_id_o,
    output logic [$clog2(MESH_SIZE_X*MESH_SIZE_Y)-1:0] debug_tail_source_id_o,
    output logic [HEAD_PAYLOAD_SIZE-$clog2(MESH_SIZE_X*MESH_SIZE_Y)-1:0] debug_tail_sequence_o,
    output logic [COUNTER_WIDTH-1:0] debug_enqueue_cycle_o,
    output logic [COUNTER_WIDTH-1:0] debug_current_cycle_o,
    output logic [COUNTER_WIDTH-1:0] debug_last_packet_latency_o
);

    localparam integer SC = MESH_SIZE_X * MESH_SIZE_Y;
    localparam integer SW = $clog2(SC);
    localparam integer PW = HEAD_PAYLOAD_SIZE - SW;
    localparam integer FW = $clog2(PACKET_FLIT_NUM);
    localparam integer MAX_TAIL_REQUESTS = SC;

    logic [COUNTER_WIDTH-1:0] cycle_counter;
    logic [SC-1:0] overwrite;
    logic [SC-1:0] tail_complete;
    logic [SC-1:0] tail_match;
    logic [SC-1:0] tail_measured;
    logic [SC-1:0] tail_request_overflow;
    logic [SW-1:0] tail_request_count [SC-1:0];//Modify match the 0-to-25 same-cycle TAIL request count to the tracker port width, Michael Tan, 20260909
    logic [PW-1:0] tail_request_sequence [SC-1:0][MAX_TAIL_REQUESTS-1:0];
    logic [COUNTER_WIDTH-1:0] tail_enqueue [SC-1:0];
    logic [COUNTER_WIDTH-1:0] tail_cycle [SC-1:0];
    always_comb begin
        for (int s = 0; s < SC; s++) begin
            tail_request_count[s] = '0;
            for (int request = 0; request < MAX_TAIL_REQUESTS; request++) begin
                tail_request_sequence[s][request] = '0;
            end
        end
        for (int x = 0; x < MESH_SIZE_X; x++) begin
            for (int y = 0; y < MESH_SIZE_Y; y++) begin
                if (local_valid_i[x][y] && local_data_i[x][y].flit_label == TAIL) begin
                    if (local_data_i[x][y].data.bt_pl[FW+HEAD_PAYLOAD_SIZE-1 -: SW] < SC) begin
                        tail_request_sequence[local_data_i[x][y].data.bt_pl[FW+HEAD_PAYLOAD_SIZE-1 -: SW]][tail_request_count[local_data_i[x][y].data.bt_pl[FW+HEAD_PAYLOAD_SIZE-1 -: SW]]] = local_data_i[x][y].data.bt_pl[FW +: PW];//Modify retain every same-source TAIL observed across the 25 destination ports, Michael Tan, 20260909
                        tail_request_count[local_data_i[x][y].data.bt_pl[FW+HEAD_PAYLOAD_SIZE-1 -: SW]]++;
                    end
                end
            end
        end
    end

    generate
        for (genvar s = 0; s < SC; s++) begin : g_tracker
            localparam integer SX = s / MESH_SIZE_Y;
            localparam integer SY = s % MESH_SIZE_Y;

            noc_board_latency_tracker #(
                .PACKET_SEQUENCE_WIDTH(PW),
                .TRACK_TABLE_DEPTH(TRACK_TABLE_DEPTH),
                .COUNTER_WIDTH(COUNTER_WIDTH)
            ) u_tracker (
                .clk(clk),
                .rst(rst),
                .enqueue_event_i(packet_enqueued_i[SX][SY]),
                .enqueue_sequence_i(enqueued_packet_id_i[SX][SY][PW-1:0]),
                .enqueue_is_measured_i(measurement_enable_i),
                .enqueue_cycle_i(cycle_counter),
                .tail_request_count_i(tail_request_count[s]),
                .tail_sequence_i(tail_request_sequence[s]),
                .tail_arrival_cycle_i(cycle_counter),
                .enqueue_overwrite_o(overwrite[s]),
                .tail_complete_o(tail_complete[s]),
                .tail_match_o(tail_match[s]),
                .tail_is_measured_o(tail_measured[s]),
                .tail_sequence_o(),
                .tail_enqueue_cycle_o(tail_enqueue[s]),
                .tail_cycle_o(tail_cycle[s]),
                .tail_request_overflow_o(tail_request_overflow[s])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        integer enq;
        integer qfull;
        integer tails;
        integer unmatched;
        integer ow;
        logic [2*COUNTER_WIDTH-1:0] lat;

        if (rst) begin
            cycle_counter <= '0;
            packets_enqueued_o <= '0;
            queue_full_o <= '0;
            tails_received_o <= '0;
            unmatched_tails_o <= '0;
            timestamp_overwrites_o <= '0;
            total_latency_cycles_o <= '0;
            debug_tail_event_o <= 1'b0;
            debug_tail_packet_id_o <= '0;
            debug_tail_source_id_o <= '0;
            debug_tail_sequence_o <= '0;
            debug_enqueue_cycle_o <= '0;
            debug_current_cycle_o <= '0;
            debug_last_packet_latency_o <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1'b1;
            enq = 0;
            qfull = 0;
            tails = 0;
            unmatched = 0;
            ow = 0;
            lat = '0;
            debug_tail_event_o <= 1'b0;
            debug_current_cycle_o <= cycle_counter;

            for (int x = 0; x < MESH_SIZE_X; x++) begin
                for (int y = 0; y < MESH_SIZE_Y; y++) begin
                    if (measurement_enable_i && packet_enqueued_i[x][y])
                        enq++;
                    if (measurement_enable_i && packet_queue_full_i[x][y])
                        qfull++;
                end
            end
            for (int s = 0; s < SC; s++) begin
                if (overwrite[s])
                    ow++;
                if (tail_complete[s] && tail_match[s]) begin
                    if (tail_measured[s]) begin
                        tails++;
                        lat = lat + (tail_cycle[s] - tail_enqueue[s]);
                    end
                    if (tail_measured[s]) begin
                        debug_tail_event_o <= 1'b1;
                        debug_tail_packet_id_o <= {s[SW-1:0], tail_request_sequence[s][0]};
                        debug_tail_source_id_o <= s[SW-1:0];
                        debug_tail_sequence_o <= tail_request_sequence[s][0];
                        debug_enqueue_cycle_o <= tail_enqueue[s];
                        debug_current_cycle_o <= tail_cycle[s];
                        debug_last_packet_latency_o <= tail_cycle[s] - tail_enqueue[s];
                    end
                end else if (tail_complete[s]) begin
                    unmatched++;
                end
                if (tail_request_overflow[s])
                    unmatched++;
            end

            packets_enqueued_o <= packets_enqueued_o + enq;
            queue_full_o <= queue_full_o + qfull;
            tails_received_o <= tails_received_o + tails;
            unmatched_tails_o <= unmatched_tails_o + unmatched;
            timestamp_overwrites_o <= timestamp_overwrites_o + ow;
            total_latency_cycles_o <= total_latency_cycles_o + lat;
        end
    end
endmodule
