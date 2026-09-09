import noc_params::*;

//Modify add synthesizable source-queue-entry to TAIL-arrival latency monitor for board step 3, Michael Tan, 20260817
module noc_board_latency_monitor #(
    parameter MESH_SIZE_X = noc_params::MESH_SIZE_X,
    parameter MESH_SIZE_Y = noc_params::MESH_SIZE_Y,
    parameter PACKET_FLIT_NUM = 4,
    parameter COUNTER_WIDTH = 32,
    parameter integer TRACK_TABLE_DEPTH = 256//Modify make the board timestamp capacity explicit and synthesis-bounded while retaining collision evidence, Michael Tan, 20260909
) (
    input logic clk,
    input logic rst,
    input logic measurement_enable_i,//Modify accept the board-top measurement-window qualifier, Michael Tan, 20260827
    input logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_enqueued_i,
    input logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_queue_full_i,//Modify receive source-queue rejection events for comparable statistics, Michael Tan, 20260827
    input logic [HEAD_PAYLOAD_SIZE-1:0] enqueued_packet_id_i [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0],
    input flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_data_i,
    input logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_valid_i,
    output logic [COUNTER_WIDTH-1:0] packets_enqueued_o,
    output logic [COUNTER_WIDTH-1:0] queue_full_o,//Modify expose measurement-window source-queue-full count, Michael Tan, 20260827
    output logic [COUNTER_WIDTH-1:0] tails_received_o,
    output logic [COUNTER_WIDTH-1:0] unmatched_tails_o,
    output logic [COUNTER_WIDTH-1:0] timestamp_overwrites_o,
    output logic [2*COUNTER_WIDTH-1:0] total_latency_cycles_o,
    output logic debug_tail_event_o,
    output logic [HEAD_PAYLOAD_SIZE-1:0] debug_tail_packet_id_o,
    output logic [$clog2(MESH_SIZE_X * MESH_SIZE_Y)-1:0] debug_tail_source_id_o,
    output logic [HEAD_PAYLOAD_SIZE-$clog2(MESH_SIZE_X * MESH_SIZE_Y)-1:0] debug_tail_sequence_o,
    output logic [COUNTER_WIDTH-1:0] debug_enqueue_cycle_o,
    output logic [COUNTER_WIDTH-1:0] debug_current_cycle_o,
    output logic [COUNTER_WIDTH-1:0] debug_last_packet_latency_o
);

    localparam SOURCE_COUNT = MESH_SIZE_X * MESH_SIZE_Y;
    localparam SOURCE_ID_WIDTH = $clog2(SOURCE_COUNT);
    localparam PACKET_SEQUENCE_WIDTH = HEAD_PAYLOAD_SIZE - SOURCE_ID_WIDTH;
    localparam TRACK_INDEX_WIDTH = $clog2(TRACK_TABLE_DEPTH);
    localparam FLIT_INDEX_WIDTH = $clog2(PACKET_FLIT_NUM);

    logic [COUNTER_WIDTH-1:0] cycle_counter;
    logic [SOURCE_COUNT-1:0][TRACK_TABLE_DEPTH-1:0][COUNTER_WIDTH-1:0] enqueue_cycle;//Modify use a compact 25-by-256 board timestamp table to bound Windows RTL elaboration cost, Michael Tan, 20260909
    logic [TRACK_TABLE_DEPTH-1:0] entry_valid [SOURCE_COUNT-1:0];//Modify retain per-source validity and report compact-table collisions through timestamp_overwrites, Michael Tan, 20260909
    logic [TRACK_TABLE_DEPTH-1:0] entry_is_measured [SOURCE_COUNT-1:0];//Modify retain measurement qualification for every compact timestamp slot, Michael Tan, 20260909

    always_ff @(posedge clk) begin : latency_measurement
        integer enqueue_increment;
        integer queue_full_increment;
        integer tail_increment;
        integer unmatched_increment;
        integer overwrite_increment;
        logic [2*COUNTER_WIDTH-1:0] latency_increment;
        logic [HEAD_PAYLOAD_SIZE-1:0] tail_packet_id;
        logic [SOURCE_ID_WIDTH-1:0] tail_source_id;
        logic [PACKET_SEQUENCE_WIDTH-1:0] tail_sequence;
        logic [TRACK_INDEX_WIDTH-1:0] tail_tracking_index;
        logic [COUNTER_WIDTH-1:0] matched_enqueue_cycle;

        if (rst) begin
            cycle_counter <= '0;
            packets_enqueued_o <= '0;
            queue_full_o <= '0;
            tails_received_o <= '0;
            unmatched_tails_o <= '0;
            timestamp_overwrites_o <= '0;
            total_latency_cycles_o <= '0;
            debug_tail_event_o <= 1'b0;//Modify clear the one-cycle matched-TAIL debug event during reset, Michael Tan, 20260820
            debug_tail_packet_id_o <= '0;
            debug_tail_source_id_o <= '0;
            debug_tail_sequence_o <= '0;
            debug_enqueue_cycle_o <= '0;
            debug_current_cycle_o <= '0;
            debug_last_packet_latency_o <= '0;
            for (int source = 0; source < SOURCE_COUNT; source++) begin
                for (int sequence_index = 0; sequence_index < TRACK_TABLE_DEPTH; sequence_index++) begin
                    entry_valid[source][sequence_index] <= 1'b0;//Modify invalidate all timestamp slots during board reset, Michael Tan, 20260817
                    entry_is_measured[source][sequence_index] <= 1'b0;//Modify clear per-packet measurement-window qualification during board reset, Michael Tan, 20260827
                end
            end
        end else begin
            cycle_counter <= cycle_counter + 1'b1;
            enqueue_increment = 0;
            queue_full_increment = 0;
            tail_increment = 0;
            unmatched_increment = 0;
            overwrite_increment = 0;
            latency_increment = '0;
            debug_tail_event_o <= 1'b0;//Modify make every matched-TAIL indication a one-cycle waveform/ILA pulse, Michael Tan, 20260820
            debug_current_cycle_o <= cycle_counter;//Modify retain the cycle value used by this clock edge's latency calculation, Michael Tan, 20260820

            for (int x = 0; x < MESH_SIZE_X; x++) begin
                for (int y = 0; y < MESH_SIZE_Y; y++) begin
                    if (measurement_enable_i && packet_queue_full_i[x][y])
                        queue_full_increment = queue_full_increment + 1;//Modify count only measurement-window offers rejected by the bounded source queue, Michael Tan, 20260827
                    if (packet_enqueued_i[x][y]) begin
                        if (entry_valid[enqueued_packet_id_i[x][y][HEAD_PAYLOAD_SIZE-1 -: SOURCE_ID_WIDTH]][enqueued_packet_id_i[x][y][TRACK_INDEX_WIDTH-1:0]])
                            overwrite_increment = overwrite_increment + 1;//Modify flag timestamp-table reuse before an older same-ID packet reached TAIL, Michael Tan, 20260817
                        entry_valid[enqueued_packet_id_i[x][y][HEAD_PAYLOAD_SIZE-1 -: SOURCE_ID_WIDTH]][enqueued_packet_id_i[x][y][TRACK_INDEX_WIDTH-1:0]] <= 1'b1;//Modify index the compact board table with the low eight packet-sequence bits, Michael Tan, 20260909
                        entry_is_measured[enqueued_packet_id_i[x][y][HEAD_PAYLOAD_SIZE-1 -: SOURCE_ID_WIDTH]][enqueued_packet_id_i[x][y][TRACK_INDEX_WIDTH-1:0]] <= measurement_enable_i;//Modify retain whether this accepted packet belongs to the measurement window, Michael Tan, 20260827
                        enqueue_cycle[enqueued_packet_id_i[x][y][HEAD_PAYLOAD_SIZE-1 -: SOURCE_ID_WIDTH]][enqueued_packet_id_i[x][y][TRACK_INDEX_WIDTH-1:0]] <= cycle_counter;//Modify store the enqueue timestamp in the compact board table, Michael Tan, 20260909
                        if (measurement_enable_i)
                            enqueue_increment = enqueue_increment + 1;//Modify count only accepted source-queue entries created during the measurement window, Michael Tan, 20260827
                    end

                    if (local_valid_i[x][y] && (local_data_i[x][y].flit_label == TAIL)) begin
                        tail_packet_id = local_data_i[x][y].data.bt_pl[FLIT_INDEX_WIDTH +: HEAD_PAYLOAD_SIZE];
                        tail_source_id = tail_packet_id[HEAD_PAYLOAD_SIZE-1 -: SOURCE_ID_WIDTH];
                        tail_sequence = tail_packet_id[PACKET_SEQUENCE_WIDTH-1:0];
                        tail_tracking_index = tail_sequence[TRACK_INDEX_WIDTH-1:0];//Modify map the full packet sequence to the compact board-table index, Michael Tan, 20260909
                        if ((tail_source_id < SOURCE_COUNT) && entry_valid[tail_source_id][tail_tracking_index]) begin
                            matched_enqueue_cycle = enqueue_cycle[tail_source_id][tail_tracking_index];//Modify read the compact-table timestamp for matched TAIL latency calculation, Michael Tan, 20260909
                            entry_valid[tail_source_id][tail_tracking_index] <= 1'b0;
                            entry_is_measured[tail_source_id][tail_tracking_index] <= 1'b0;//Modify clear the qualification bit together with every matched timestamp entry, Michael Tan, 20260827
                            if (entry_is_measured[tail_source_id][tail_tracking_index]) begin
                                latency_increment = latency_increment + (cycle_counter - matched_enqueue_cycle);
                                tail_increment = tail_increment + 1;//Modify accumulate only TAILs whose accepted source-queue entry was in the measurement window, Michael Tan, 20260827
                            end
                            debug_tail_event_o <= 1'b1;//Modify expose a matched TAIL event for direct latency waveform correlation, Michael Tan, 20260820
                            debug_tail_packet_id_o <= tail_packet_id;
                            debug_tail_source_id_o <= tail_source_id;
                            debug_tail_sequence_o <= tail_sequence;
                            debug_enqueue_cycle_o <= matched_enqueue_cycle;
                            debug_last_packet_latency_o <= cycle_counter - matched_enqueue_cycle;//Modify retain the exact per-packet latency added to the aggregate counter, Michael Tan, 20260908
                        end else begin
                            unmatched_increment = unmatched_increment + 1;//Modify retain unmatched-Tail evidence instead of silently corrupting latency statistics, Michael Tan, 20260817
                        end
                    end
                end
            end

            packets_enqueued_o <= packets_enqueued_o + enqueue_increment;
            queue_full_o <= queue_full_o + queue_full_increment;
            tails_received_o <= tails_received_o + tail_increment;
            unmatched_tails_o <= unmatched_tails_o + unmatched_increment;
            timestamp_overwrites_o <= timestamp_overwrites_o + overwrite_increment;
            total_latency_cycles_o <= total_latency_cycles_o + latency_increment;
        end
    end

endmodule
