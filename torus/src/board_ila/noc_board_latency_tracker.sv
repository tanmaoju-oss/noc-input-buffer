//Modify add a per-source BRAM-backed timestamp tracker to avoid a monolithic three-dimensional register table, Michael Tan, 20260909
module noc_board_latency_tracker #(
    parameter integer PACKET_SEQUENCE_WIDTH = 11,
    parameter integer TRACK_TABLE_DEPTH = 2048,
    parameter integer COUNTER_WIDTH = 32,
    parameter integer MAX_TAIL_REQUESTS = 25
) (
    input logic clk,
    input logic rst,
    input logic enqueue_event_i,
    input logic [PACKET_SEQUENCE_WIDTH-1:0] enqueue_sequence_i,
    input logic enqueue_is_measured_i,
    input logic [COUNTER_WIDTH-1:0] enqueue_cycle_i,
    input logic [$clog2(MAX_TAIL_REQUESTS+1)-1:0] tail_request_count_i,
    input logic [PACKET_SEQUENCE_WIDTH-1:0] tail_sequence_i [MAX_TAIL_REQUESTS-1:0],
    input logic [COUNTER_WIDTH-1:0] tail_arrival_cycle_i,
    output logic enqueue_overwrite_o,
    output logic tail_complete_o,//Modify distinguish a completed BRAM lookup from a matched lookup, Michael Tan, 20260909
    output logic tail_match_o,
    output logic tail_is_measured_o,
    output logic [PACKET_SEQUENCE_WIDTH-1:0] tail_sequence_o,
    output logic [COUNTER_WIDTH-1:0] tail_enqueue_cycle_o,
    output logic [COUNTER_WIDTH-1:0] tail_cycle_o,
    output logic tail_request_overflow_o//Modify retain explicit evidence if the small request FIFO cannot absorb a burst, Michael Tan, 20260909
);
    localparam integer TRACK_INDEX_WIDTH = $clog2(TRACK_TABLE_DEPTH);
    localparam integer TAIL_FIFO_DEPTH = 64;
    localparam integer TAIL_FIFO_POINTER_WIDTH = $clog2(TAIL_FIFO_DEPTH);
    localparam integer TAIL_FIFO_COUNT_WIDTH = $clog2(TAIL_FIFO_DEPTH + 1);

    logic [TRACK_TABLE_DEPTH-1:0] entry_valid;
    logic [TRACK_TABLE_DEPTH-1:0] entry_is_measured;
    logic [PACKET_SEQUENCE_WIDTH-1:0] tail_fifo_sequence [0:TAIL_FIFO_DEPTH-1];//Modify queue every same-source TAIL request before issuing one synchronous BRAM read per cycle, Michael Tan, 20260909
    logic [COUNTER_WIDTH-1:0] tail_fifo_cycle [0:TAIL_FIFO_DEPTH-1];
    logic [TAIL_FIFO_POINTER_WIDTH-1:0] tail_fifo_head_q;
    logic [TAIL_FIFO_POINTER_WIDTH-1:0] tail_fifo_tail_q;
    logic [TAIL_FIFO_COUNT_WIDTH-1:0] tail_fifo_count_q;
    logic tail_lookup_pending_q;
    logic tail_valid_q;
    logic tail_is_measured_q;
    logic [TRACK_INDEX_WIDTH-1:0] tail_index_q;
    logic [PACKET_SEQUENCE_WIDTH-1:0] tail_sequence_q;
    logic [COUNTER_WIDTH-1:0] tail_enqueue_cycle_bram;//Modify receive the explicit one-cycle XPM BRAM read result, Michael Tan, 20260909
    logic [COUNTER_WIDTH-1:0] tail_cycle_q;

    //Modify use an explicit common-clock 2048-by-32 block RAM and one-cycle synchronous read, Michael Tan, 20260909
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(TRACK_INDEX_WIDTH),
        .ADDR_WIDTH_B(TRACK_INDEX_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(COUNTER_WIDTH),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(TRACK_TABLE_DEPTH * COUNTER_WIDTH),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(COUNTER_WIDTH),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(COUNTER_WIDTH),
        .WRITE_MODE_B("read_first")
    ) u_enqueue_cycle_bram (
        .clka(clk),
        .ena(enqueue_event_i),
        .wea(enqueue_event_i),
        .addra(enqueue_sequence_i[TRACK_INDEX_WIDTH-1:0]),
        .dina(enqueue_cycle_i),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .clkb(clk),
        .rstb(rst),
        .enb(tail_fifo_count_q != 0),
        .regceb(1'b1),
        .addrb(tail_fifo_sequence[tail_fifo_head_q][TRACK_INDEX_WIDTH-1:0]),
        .doutb(tail_enqueue_cycle_bram),
        .sbiterrb(),
        .dbiterrb(),
        .sleep(1'b0)
    );

    function automatic logic [TAIL_FIFO_POINTER_WIDTH-1:0] fifo_pointer_add(
        input logic [TAIL_FIFO_POINTER_WIDTH-1:0] pointer,
        input integer offset
    );
        fifo_pointer_add = pointer + offset;//Modify TAIL_FIFO_DEPTH is a power of two, so pointer truncation implements wraparound, Michael Tan, 20260909
    endfunction

    assign enqueue_overwrite_o = enqueue_event_i && entry_valid[enqueue_sequence_i[TRACK_INDEX_WIDTH-1:0]];//Modify retain explicit evidence of a live compact-address collision, Michael Tan, 20260909
    assign tail_complete_o = tail_lookup_pending_q;//Modify complete a queued lookup one clock after it is launched, Michael Tan, 20260909
    assign tail_match_o = tail_valid_q;
    assign tail_is_measured_o = tail_is_measured_q;
    assign tail_sequence_o = tail_sequence_q;
    assign tail_enqueue_cycle_o = tail_enqueue_cycle_bram;//Modify align XPM one-cycle doutb with the registered TAIL request metadata, Michael Tan, 20260909
    assign tail_cycle_o = tail_cycle_q;

    always_ff @(posedge clk) begin : per_source_tracker
        integer accepted_tail_requests;
        integer tail_fifo_free_entries;

        if (rst) begin
            tail_fifo_head_q <= '0;
            tail_fifo_tail_q <= '0;
            tail_fifo_count_q <= '0;
            tail_lookup_pending_q <= 1'b0;
            tail_valid_q <= 1'b0;
            tail_is_measured_q <= 1'b0;
            tail_index_q <= '0;
            tail_sequence_q <= '0;
            tail_cycle_q <= '0;
            tail_request_overflow_o <= 1'b0;
            for (int index = 0; index < TRACK_TABLE_DEPTH; index++) begin
                entry_valid[index] <= 1'b0;//Modify reset only small validity state; BRAM contents are ignored while invalid, Michael Tan, 20260909
                entry_is_measured[index] <= 1'b0;
            end
        end else begin
            tail_request_overflow_o <= 1'b0;

            if (tail_lookup_pending_q && tail_valid_q) begin
                entry_valid[tail_index_q] <= 1'b0;//Modify retire a matched packet after its pipelined BRAM lookup completes, Michael Tan, 20260909
                entry_is_measured[tail_index_q] <= 1'b0;
            end
            if (enqueue_event_i) begin
                entry_valid[enqueue_sequence_i[TRACK_INDEX_WIDTH-1:0]] <= 1'b1;
                entry_is_measured[enqueue_sequence_i[TRACK_INDEX_WIDTH-1:0]] <= enqueue_is_measured_i;
            end

            if (tail_fifo_count_q != 0) begin
                tail_lookup_pending_q <= 1'b1;
                tail_index_q <= tail_fifo_sequence[tail_fifo_head_q][TRACK_INDEX_WIDTH-1:0];
                tail_sequence_q <= tail_fifo_sequence[tail_fifo_head_q];
                tail_valid_q <= entry_valid[tail_fifo_sequence[tail_fifo_head_q][TRACK_INDEX_WIDTH-1:0]];
                tail_is_measured_q <= entry_is_measured[tail_fifo_sequence[tail_fifo_head_q][TRACK_INDEX_WIDTH-1:0]];
                tail_cycle_q <= tail_fifo_cycle[tail_fifo_head_q];
                tail_fifo_head_q <= fifo_pointer_add(tail_fifo_head_q, 1);
            end else begin
                tail_lookup_pending_q <= 1'b0;
                tail_valid_q <= 1'b0;
                tail_is_measured_q <= 1'b0;
            end

            tail_fifo_free_entries = TAIL_FIFO_DEPTH - tail_fifo_count_q;
            if (tail_fifo_count_q != 0)
                tail_fifo_free_entries = tail_fifo_free_entries + 1;
            accepted_tail_requests = tail_request_count_i;
            if (accepted_tail_requests > tail_fifo_free_entries) begin
                accepted_tail_requests = tail_fifo_free_entries;
                tail_request_overflow_o <= 1'b1;//Modify flag loss only if a source receives more than the 64-entry request FIFO can absorb, Michael Tan, 20260909
            end
            for (int request = 0; request < MAX_TAIL_REQUESTS; request++) begin
                if (request < accepted_tail_requests) begin
                    tail_fifo_sequence[fifo_pointer_add(tail_fifo_tail_q, request)] <= tail_sequence_i[request];
                    tail_fifo_cycle[fifo_pointer_add(tail_fifo_tail_q, request)] <= tail_arrival_cycle_i;
                end
            end
            tail_fifo_tail_q <= fifo_pointer_add(tail_fifo_tail_q, accepted_tail_requests);
            tail_fifo_count_q <= tail_fifo_count_q - ((tail_fifo_count_q != 0) ? 1 : 0) + accepted_tail_requests;
        end
    end
endmodule
