import noc_params::*;

//Modify add synthesizable queued random traffic generator for the DDR-free board top, Michael Tan, 20260805
module noc_board_traffic_generator #(
    parameter MESH_SIZE_X = noc_params::MESH_SIZE_X,
    parameter MESH_SIZE_Y = noc_params::MESH_SIZE_Y,
    parameter SOURCE_QUEUE_DEPTH = 64,
    parameter PACKET_FLIT_NUM = 4,
    parameter LFSR_WIDTH = 16,
    parameter INJECTION_LFSR_STEPS = 16,
    parameter INJECTION_THRESHOLD = 16'd6554
) (
    input  logic clk,
    input  logic rst,
    input  logic generate_enable_i,//Modify accept the board-top warm-up/measurement generation gate, Michael Tan, 20260827
    input  logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] local_on_off_i,
    output flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_data_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] local_valid_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_enqueued_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] packet_queue_full_o,//Modify expose offered packets rejected by a full source queue, Michael Tan, 20260827
    output logic [HEAD_PAYLOAD_SIZE-1:0] enqueued_packet_id_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0]
);

    localparam QUEUE_PTR_WIDTH = $clog2(SOURCE_QUEUE_DEPTH);
    localparam FLIT_INDEX_WIDTH = $clog2(PACKET_FLIT_NUM);
    localparam SOURCE_COUNT = MESH_SIZE_X * MESH_SIZE_Y;
    localparam SOURCE_ID_WIDTH = $clog2(SOURCE_COUNT);
    localparam PACKET_SEQUENCE_WIDTH = HEAD_PAYLOAD_SIZE - SOURCE_ID_WIDTH;

    logic [LFSR_WIDTH-1:0] traffic_lfsr [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [PACKET_SEQUENCE_WIDTH-1:0] next_packet_sequence [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [QUEUE_PTR_WIDTH-1:0] queue_head [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [QUEUE_PTR_WIDTH-1:0] queue_tail [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [QUEUE_PTR_WIDTH:0] queue_count [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [DEST_ADDR_SIZE_X-1:0] queue_dst_x [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][SOURCE_QUEUE_DEPTH-1:0];
    logic [DEST_ADDR_SIZE_Y-1:0] queue_dst_y [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][SOURCE_QUEUE_DEPTH-1:0];
    logic [HEAD_PAYLOAD_SIZE-1:0] queue_packet_id [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][SOURCE_QUEUE_DEPTH-1:0];
    logic packet_active [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [FLIT_INDEX_WIDTH-1:0] active_flit_index [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [DEST_ADDR_SIZE_X-1:0] active_dst_x [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [DEST_ADDR_SIZE_Y-1:0] active_dst_y [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];
    logic [HEAD_PAYLOAD_SIZE-1:0] active_packet_id [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0];

    function automatic logic [LFSR_WIDTH-1:0] next_lfsr(input logic [LFSR_WIDTH-1:0] value);
        next_lfsr = {value[LFSR_WIDTH-2:0], value[LFSR_WIDTH-1] ^ value[LFSR_WIDTH-3] ^ value[LFSR_WIDTH-4] ^ value[LFSR_WIDTH-6]};//Modify use a maximal-length 16-bit LFSR step for synthesizable traffic randomness, Michael Tan, 20260805
    endfunction

    function automatic logic [LFSR_WIDTH-1:0] advance_injection_lfsr(input logic [LFSR_WIDTH-1:0] value);
        logic [LFSR_WIDTH-1:0] advanced_value;

        advanced_value = value;
        for (int step = 0; step < INJECTION_LFSR_STEPS; step++) begin
            advanced_value = next_lfsr(advanced_value);
        end
        advance_injection_lfsr = advanced_value;//Modify decimate consecutive LFSR states before injection sampling to avoid deterministic burst runs, Michael Tan, 20260827
    endfunction

    function automatic logic [LFSR_WIDTH-1:0] initial_lfsr_seed(input integer x, input integer y);
        initial_lfsr_seed = 16'h9e37 * (1 + x * MESH_SIZE_Y + y);//Modify disperse deterministic nonzero source seeds around the LFSR period instead of using adjacent states, Michael Tan, 20260827
        if (initial_lfsr_seed == '0)
            initial_lfsr_seed = 'h1;//Modify retain the nonzero LFSR-state invariant for every source, Michael Tan, 20260827
    endfunction

    function automatic logic [QUEUE_PTR_WIDTH-1:0] next_queue_ptr(input logic [QUEUE_PTR_WIDTH-1:0] value);
        if (value == SOURCE_QUEUE_DEPTH-1)
            next_queue_ptr = '0;
        else
            next_queue_ptr = value + 1'b1;
    endfunction

    function automatic logic [SOURCE_ID_WIDTH-1:0] source_node_id(input integer x, input integer y);
        source_node_id = x * MESH_SIZE_Y + y;//Modify encode the 5x5 source index into every packet ID for board latency matching, Michael Tan, 20260817
    endfunction

    function automatic flit_t make_flit(
        input logic [DEST_ADDR_SIZE_X-1:0] dst_x,
        input logic [DEST_ADDR_SIZE_Y-1:0] dst_y,
        input logic [HEAD_PAYLOAD_SIZE-1:0] packet_id,
        input logic [FLIT_INDEX_WIDTH-1:0] flit_index
    );
        flit_t flit;

        flit = '0;
        flit.vc_id = '0;//Modify inject source traffic through VC0 while retaining the four-VC NoC fabric, Michael Tan, 20260805
        if (flit_index == '0) begin
            flit.flit_label = HEAD;
            flit.data.head_data.x_dest = dst_x;
            flit.data.head_data.y_dest = dst_y;
            flit.data.head_data.head_pl = packet_id;
        end else begin
            flit.flit_label = (flit_index == PACKET_FLIT_NUM-1) ? TAIL : BODY;
            flit.data.bt_pl = '0;
            flit.data.bt_pl[FLIT_INDEX_WIDTH-1:0] = flit_index;
            flit.data.bt_pl[FLIT_INDEX_WIDTH +: HEAD_PAYLOAD_SIZE] = packet_id;
        end
        return flit;
    endfunction

    always_ff @(posedge clk) begin : traffic_generation
        logic [LFSR_WIDTH-1:0] advanced_lfsr;
        logic [DEST_ADDR_SIZE_X-1:0] generated_dst_x;
        logic [DEST_ADDR_SIZE_Y-1:0] generated_dst_y;
        logic [SOURCE_ID_WIDTH-1:0] generated_destination_node;
        logic enqueue_packet;
        logic start_queued_packet;

        if (rst) begin
            local_valid_o <= '0;
            local_data_o <= '0;
            packet_enqueued_o <= '0;
            packet_queue_full_o <= '0;
            for (int x = 0; x < MESH_SIZE_X; x++) begin
                for (int y = 0; y < MESH_SIZE_Y; y++) begin
                    traffic_lfsr[x][y] <= initial_lfsr_seed(x, y);//Modify initialize each source at a dispersed deterministic nonzero LFSR state, Michael Tan, 20260827
                    next_packet_sequence[x][y] <= '0;//Modify reset the per-source packet sequence while source bits remain fixed in the packet ID, Michael Tan, 20260817
                    queue_head[x][y] <= '0;
                    queue_tail[x][y] <= '0;
                    queue_count[x][y] <= '0;
                    packet_active[x][y] <= 1'b0;
                    active_flit_index[x][y] <= '0;
                    active_dst_x[x][y] <= '0;
                    active_dst_y[x][y] <= '0;
                    active_packet_id[x][y] <= '0;
                end
            end
        end else begin
            local_valid_o <= '0;
            packet_enqueued_o <= '0;//Modify emit one-cycle enqueue event pulses for the board latency monitor, Michael Tan, 20260817
            packet_queue_full_o <= '0;//Modify emit one-cycle source-queue-full events for measurement-window loss accounting, Michael Tan, 20260827
            for (int x = 0; x < MESH_SIZE_X; x++) begin
                for (int y = 0; y < MESH_SIZE_Y; y++) begin
                    advanced_lfsr = advance_injection_lfsr(traffic_lfsr[x][y]);
                    if (generate_enable_i)
                        traffic_lfsr[x][y] <= advanced_lfsr;//Modify advance random injection state only while the warm-up or measurement window generates packets, Michael Tan, 20260827

                    //generated_dst_x = advanced_lfsr[2:0] % MESH_SIZE_X;//Original biased 3-bit modulo coordinate mapping, Michael Tan, 20260827
                    //generated_dst_y = advanced_lfsr[5:3] % MESH_SIZE_Y;//Original biased 3-bit modulo coordinate mapping, Michael Tan, 20260827
                    //Modify select a non-self destination from the complete node-index range, avoiding 3-bit modulo and self-correction spatial bias, Michael Tan, 20260827
                    generated_destination_node = advanced_lfsr % (SOURCE_COUNT - 1);
                    if (generated_destination_node >= source_node_id(x, y))
                        generated_destination_node = generated_destination_node + 1'b1;
                    generated_dst_x = generated_destination_node / MESH_SIZE_Y;
                    generated_dst_y = generated_destination_node % MESH_SIZE_Y;

                    //Modify enqueue one offered packet per source at the 0.1 LFSR probability when space is available, Michael Tan, 20260805
                    enqueue_packet = generate_enable_i && (advanced_lfsr < INJECTION_THRESHOLD) && (queue_count[x][y] < SOURCE_QUEUE_DEPTH);//Modify stop new packet creation during the drain window while retaining queued-packet transmission, Michael Tan, 20260827
                    if (generate_enable_i && (advanced_lfsr < INJECTION_THRESHOLD) && (queue_count[x][y] >= SOURCE_QUEUE_DEPTH))
                        packet_queue_full_o[x][y] <= 1'b1;//Modify expose offered packets rejected because the bounded board source queue is full, Michael Tan, 20260827
                    start_queued_packet = !packet_active[x][y] && (queue_count[x][y] != 0) && local_on_off_i[x][y][0];
                    if (enqueue_packet) begin
                        queue_dst_x[x][y][queue_tail[x][y]] <= generated_dst_x;
                        queue_dst_y[x][y][queue_tail[x][y]] <= generated_dst_y;
                        queue_packet_id[x][y][queue_tail[x][y]] <= {source_node_id(x, y), next_packet_sequence[x][y]};//Modify make packet IDs unique across all 25 sources for monitor correlation, Michael Tan, 20260817
                        queue_tail[x][y] <= next_queue_ptr(queue_tail[x][y]);
                        next_packet_sequence[x][y] <= next_packet_sequence[x][y] + 1'b1;
                        packet_enqueued_o[x][y] <= 1'b1;//Modify report the accepted source-queue entry to the latency monitor, Michael Tan, 20260817
                        enqueued_packet_id_o[x][y] <= {source_node_id(x, y), next_packet_sequence[x][y]};//Modify report the unique packet ID with the enqueue event, Michael Tan, 20260817
                    end

                    if (start_queued_packet) begin
                        local_valid_o[x][y] <= 1'b1;
                        local_data_o[x][y] <= make_flit(queue_dst_x[x][y][queue_head[x][y]], queue_dst_y[x][y][queue_head[x][y]], queue_packet_id[x][y][queue_head[x][y]], '0);
                        active_dst_x[x][y] <= queue_dst_x[x][y][queue_head[x][y]];
                        active_dst_y[x][y] <= queue_dst_y[x][y][queue_head[x][y]];
                        active_packet_id[x][y] <= queue_packet_id[x][y][queue_head[x][y]];
                        active_flit_index[x][y] <= 1;
                        packet_active[x][y] <= 1'b1;
                        queue_head[x][y] <= next_queue_ptr(queue_head[x][y]);
                    end else if (packet_active[x][y] && local_on_off_i[x][y][0]) begin
                        local_valid_o[x][y] <= 1'b1;
                        local_data_o[x][y] <= make_flit(active_dst_x[x][y], active_dst_y[x][y], active_packet_id[x][y], active_flit_index[x][y]);
                        if (active_flit_index[x][y] == PACKET_FLIT_NUM-1) begin
                            packet_active[x][y] <= 1'b0;
                            active_flit_index[x][y] <= '0;
                        end else begin
                            active_flit_index[x][y] <= active_flit_index[x][y] + 1'b1;
                        end
                    end

                    //Modify preserve FIFO occupancy when an enqueue and a HEAD dequeue occur in the same cycle, Michael Tan, 20260805
                    unique case ({enqueue_packet, start_queued_packet})
                        2'b10: queue_count[x][y] <= queue_count[x][y] + 1'b1;
                        2'b01: queue_count[x][y] <= queue_count[x][y] - 1'b1;
                        default: queue_count[x][y] <= queue_count[x][y];
                    endcase
                end
            end
        end
    end

endmodule
