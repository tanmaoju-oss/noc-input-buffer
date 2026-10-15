`timescale 1ns/1ps
`default_nettype none

// The context supplied by SN_Top_new already selects normal or DMT return IDs.
module TxDat_Ch #(
    parameter   [3:0]       TXDAT_OPCODE    =   4'h4
)(
    // clki and rst_ni
    input                   wire                clk_i,
    input                   wire                rst_n_i,
    // read request to transimit data
    input                   wire                rr_td_valid_i,
    output                  wire                td_rr_ready_o,
    input                   wire [44:0]         rr_td_context_i,
    input                   wire                dmt_enable_i,
    input                   wire [6:0]          dmt_return_nid_i,
    input                   wire [11:0]         dmt_return_txnid_i,
    // transimit data txn
    input                   wire                tx_dat_valid_i,
    output                  wire                tx_dat_ready_o,
    input                   wire [511:0]        axi2td_data_i,
    input                   wire [11:0]         axi2td_id_i,
    // Modify by Michael Tan，20261015: capture AXI status with data.
    input wire [1:0] axi_read_status_i,
    // transit data fifo control signal
    input                   wire                tx_dat_fifo_full_i, 
    output                  wire                tx_dat_fifo_write_o,
    output                  wire [222:0]        tx_dat_fifo_data_o,
    output wire [9:0]   packet_counter_o
);
    // Read to TSP state
    localparam [1:0]        ST_IDLE         = 2'b00; 
    localparam [1:0]        ST_WAIT_CONTEXT = 2'b01; 
    localparam [1:0]        ST_SEND_DATA    = 2'b10; 
    reg [1:0] state_q;
    // field name assignment
    wire [11:0] request_dbid;
    wire [6:0]  request_home_nid;
    wire [11:0] request_txnid;
    wire [6:0]  request_srcid;
    wire [6:0]  request_tgtid;

    assign request_dbid     = rr_td_context_i[44:33];
    assign request_home_nid = rr_td_context_i[32:26];
    assign request_txnid    = rr_td_context_i[25:14];
    assign request_srcid    = rr_td_context_i[13:7];
    assign request_tgtid    = rr_td_context_i[6:0];
    // 64-item transaction context table
    reg [44:0] context_table [0:63];
    reg        context_dmt_table [0:63];
    reg [6:0]  context_return_nid_table [0:63];
    reg [11:0] context_return_txnid_table [0:63];
    reg [63:0] context_valid_q;

    wire [2:0]  request_srcid_code;
    wire [3:0]  request_local_txnid;
    wire        request_srcid_supported;
    wire [1:0]  request_srcid_group;
    wire [5:0]  request_context_index;
    wire [44:0] response_context_data;

    assign request_srcid_code  = request_txnid[6:4];
    assign request_local_txnid = request_txnid[3:0];

    assign request_srcid_supported =
        (request_srcid_code == 3'b000) ||
        (request_srcid_code == 3'b010) ||
        (request_srcid_code == 3'b110);

    assign request_srcid_group =
        (request_srcid_code == 3'b000) ? 2'b00 :
        (request_srcid_code == 3'b010) ? 2'b01 :
        (request_srcid_code == 3'b110) ? 2'b10 :
                                         2'b11;

    assign request_context_index = {
        request_srcid_group,
        request_local_txnid
    };
    // Request ID to Response ID
    assign response_context_data = {
        request_dbid,
        request_home_nid,
        request_txnid,
        request_tgtid,
        request_srcid
    };
    // Axi data return
    reg [511:0] axi_data_q;
    reg [11:0]  axi_id_q;
    // Modify by Michael Tan，20261015: retain NDERR through output backpressure.
    reg [1:0] read_resp_err_q;
    // Buffered ID transfer to axi
    wire [2:0] axi_srcid_code;
    wire [3:0] axi_local_txnid;
    wire       axi_srcid_supported;
    wire [1:0] axi_srcid_group;
    wire [5:0] axi_context_index;

    assign axi_srcid_code  = axi_id_q[6:4];
    assign axi_local_txnid = axi_id_q[3:0];

    assign axi_srcid_supported =
        (axi_srcid_code == 3'b000) ||
        (axi_srcid_code == 3'b010) ||
        (axi_srcid_code == 3'b110);

    assign axi_srcid_group =
        (axi_srcid_code == 3'b000) ? 2'b00 :
        (axi_srcid_code == 3'b010) ? 2'b01 :
        (axi_srcid_code == 3'b110) ? 2'b10 :
                                     2'b11;

    assign axi_context_index = {
        axi_srcid_group,
        axi_local_txnid
    };
    // axi illegal check
    wire incoming_axi_id_supported;

    assign incoming_axi_id_supported =
        (axi2td_id_i[6:4] == 3'b000) ||
        (axi2td_id_i[6:4] == 3'b010) ||
        (axi2td_id_i[6:4] == 3'b110);
    // current package context
    reg [44:0] active_context_q;
    reg        active_dmt_q;
    reg [6:0]  active_return_nid_q;
    reg [11:0] active_return_txnid_q;
    reg [5:0]  active_context_index_q;
    reg [1:0]  beat_index_q;
    // package concatenation
    wire [11:0] active_dbid;
    wire [6:0]  active_home_nid;
    wire [11:0] active_txnid;
    wire [6:0]  active_response_srcid;
    wire [6:0]  active_response_tgtid;

    assign active_dbid            = active_context_q[44:33];
    assign active_home_nid        = active_context_q[32:26];
    assign active_txnid           = active_dmt_q ? active_return_txnid_q : active_context_q[25:14];
    assign active_response_srcid  = active_context_q[13:7];
    assign active_response_tgtid  = active_dmt_q ? active_return_nid_q : active_context_q[6:0];
    // data package statistic register
    reg [9:0] packet_counter_q;
    // handshake incidence and completion incidence
    wire context_input_fire;
    wire axi_input_fire;
    wire router_write_fire;
    wire packet_complete_fire;
    wire request_context_slot_available;

    assign context_input_fire =
        rr_td_valid_i && td_rr_ready_o;

    assign axi_input_fire =
        tx_dat_valid_i && tx_dat_ready_o;

    assign router_write_fire =
        tx_dat_fifo_write_o && !tx_dat_fifo_full_i;

    assign packet_complete_fire =
        router_write_fire &&
        (beat_index_q == 2'd3);
    // according to the tale to decide whether receive the new context
    assign request_context_slot_available =
        !context_valid_q[request_context_index] ||
        (
            packet_complete_fire &&
            (active_context_index_q == request_context_index)
        );
    // rx_req_channel validity judgement
    assign td_rr_ready_o =
        rst_n_i &&
        (
            !rr_td_valid_i ||
            !request_srcid_supported ||
            request_context_slot_available
        );
    // context data from axi ready signal
    assign tx_dat_ready_o =
        rst_n_i &&
        (
            (state_q == ST_IDLE) ||
            packet_complete_fire
        );
    // Router Txdat FIFO write enable signal
    assign tx_dat_fifo_write_o =
        (state_q == ST_SEND_DATA) &&
        !tx_dat_fifo_full_i;
    // flit packet concatenation
    reg [127:0] current_data_beat;

    always @(*) begin
        case (beat_index_q)
            2'd0:    current_data_beat = axi_data_q[127:0];
            2'd1:    current_data_beat = axi_data_q[255:128];
            2'd2:    current_data_beat = axi_data_q[383:256];
            2'd3:    current_data_beat = axi_data_q[511:384];
            default: current_data_beat = 128'b0;
        endcase
    end
    
    // FIFO data concatenation
    assign tx_dat_fifo_data_o = {
        current_data_beat,          // [222:95]
        16'hFFFF,                   // [94:79]
        9'b0,                       // [78:70]
        beat_index_q,               // [69:68]
        2'b0,                       // [67:66]
        active_dbid,                // [65:54]
        11'b0, read_resp_err_q,      // [53:41], RespErr [42:41]
        TXDAT_OPCODE,               // [40:37]
        active_home_nid,            // [36:30]
        active_txnid,               // [29:18]
        active_response_srcid,      // [17:11]
        active_response_tgtid,      // [10:4]
        4'b0                        // [3:0]
    };
    // output statistic
    assign packet_counter_o = packet_counter_q;
    // context table write and release
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            context_valid_q <= 64'b0;
        end
        else begin
            if (packet_complete_fire) begin
                context_valid_q[active_context_index_q] <= 1'b0;
            end
            if (context_input_fire && request_srcid_supported) begin
                context_table[request_context_index] <= response_context_data;
                context_dmt_table[request_context_index] <= dmt_enable_i;
                context_return_nid_table[request_context_index] <= dmt_return_nid_i;
                context_return_txnid_table[request_context_index] <= dmt_return_txnid_i;
                context_valid_q[request_context_index] <= 1'b1;
            end
        end
    end
    // major register and data register
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_q                <= ST_IDLE;
            axi_data_q             <= 512'b0;
            axi_id_q               <= 12'b0;
            read_resp_err_q <= 2'b00;
            active_context_q       <= 45'b0;
            active_dmt_q           <= 1'b0;
            active_return_nid_q    <= 7'b0;
            active_return_txnid_q  <= 12'b0;
            active_context_index_q <= 6'b0;
            beat_index_q           <= 2'b0;
            packet_counter_q       <= 10'b0;
        end
        else begin
            case (state_q)
                ST_IDLE: begin
                    beat_index_q <= 2'd0;

                    if (axi_input_fire) begin
                        if (incoming_axi_id_supported) begin
                            axi_data_q <= axi2td_data_i;
                            axi_id_q   <= axi2td_id_i;
                            // Modify by Michael Tan，20261015: map AXI failure to CHI RespErr.
                            read_resp_err_q <= axi_read_status_i[1] ? 2'b10 : 2'b00;
                            state_q    <= ST_WAIT_CONTEXT;
                        end
                        else begin
                            state_q <= ST_IDLE;
                        end
                    end
                end
                ST_WAIT_CONTEXT: begin
                    if (!axi_srcid_supported) begin
                        state_q <= ST_IDLE;
                    end
                    else if (context_valid_q[axi_context_index]) begin
                        if (context_table[axi_context_index][25:14] == axi_id_q) begin
                            active_context_q       <= context_table[axi_context_index];
                            active_dmt_q           <= context_dmt_table[axi_context_index];
                            active_return_nid_q    <= context_return_nid_table[axi_context_index];
                            active_return_txnid_q  <= context_return_txnid_table[axi_context_index];
                            active_context_index_q <= axi_context_index;
                            beat_index_q           <= 2'd0;
                            state_q                <= ST_SEND_DATA;
                        end
                        else begin
                            state_q <= ST_IDLE;
                        end
                    end
                end
                ST_SEND_DATA: begin
                    if (router_write_fire) begin
                        if (beat_index_q == 2'd3) begin
                            beat_index_q     <= 2'd0;
                            packet_counter_q <= packet_counter_q + 10'd1;
                            if (axi_input_fire) begin
                                if (incoming_axi_id_supported) begin
                                    axi_data_q <= axi2td_data_i;
                                    axi_id_q   <= axi2td_id_i;
                            // Modify by Michael Tan，20261015: map AXI failure to CHI RespErr.
                            read_resp_err_q <= axi_read_status_i[1] ? 2'b10 : 2'b00;
                                    state_q    <= ST_WAIT_CONTEXT;
                                end
                                else begin
                                    state_q <= ST_IDLE;
                                end
                            end
                            else begin
                                state_q <= ST_IDLE;
                            end
                        end
                        else begin
                            beat_index_q <= beat_index_q + 2'd1;
                        end
                    end
                end
                default: begin
                    state_q      <= ST_IDLE;
                    beat_index_q <= 2'd0;
                end
            endcase
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk_i) begin
        if (rst_n_i &&
            context_input_fire &&
            !request_srcid_supported) begin
            $display(
                "ERROR(TxDat_Ch): unsupported request TxnID encoding, time=%0t, TxnID=%h",
                $time,
                request_txnid
            );
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i &&
            axi_input_fire &&
            !incoming_axi_id_supported) begin
            $display(
                "ERROR(TxDat_Ch): unsupported AXI ID encoding, time=%0t, AXI_ID=%h",
                $time,
                axi2td_id_i
            );
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i &&
            (state_q == ST_WAIT_CONTEXT) &&
            axi_srcid_supported &&
            context_valid_q[axi_context_index] &&
            (context_table[axi_context_index][25:14] != axi_id_q)) begin
            $display(
                "ERROR(TxDat_Ch): full TxnID mismatch, time=%0t, context=%h, AXI_ID=%h",
                $time,
                context_table[axi_context_index][25:14],
                axi_id_q
            );
        end
    end
`endif

endmodule

`default_nettype wire

// Integration wrapper with direction-qualified, protocol-oriented port names.
`default_nettype none
module TxDat_Ch_new #(
    parameter [3:0] TXDAT_OPCODE = 4'h4
)(
    input  wire         clk_i,
    input  wire         rst_ni,

    input  wire         read_context_valid_i,
    output wire         read_context_ready_o,
    input  wire [44:0]  read_context_i,
    input  wire         dmt_enable_i,
    input  wire [6:0]   dmt_return_nid_i,
    input  wire [11:0]  dmt_return_txnid_i,

    input  wire         axi_read_data_valid_i,
    output wire         axi_read_data_ready_o,
    input  wire [511:0] axi_read_data_i,
    input  wire [11:0]  axi_read_id_i,
    // Modify by Michael Tan，20261015: response status accompanies valid/data.
    input wire [1:0] axi_read_status_i,

    input  wire         chi_tx_dat_full_i,
    output wire         chi_tx_dat_write_o,
    output wire [222:0] chi_tx_dat_flit_o,
    output wire [9:0]   transmitted_packet_count_o
);
    TxDat_Ch #(
        .TXDAT_OPCODE (TXDAT_OPCODE)
    ) u_legacy_core (
        .clk_i                 (clk_i),
        .rst_n_i               (rst_ni),
        .rr_td_valid_i         (read_context_valid_i),
        .td_rr_ready_o         (read_context_ready_o),
        .rr_td_context_i       (read_context_i),
        .dmt_enable_i          (dmt_enable_i),
        .dmt_return_nid_i      (dmt_return_nid_i),
        .dmt_return_txnid_i    (dmt_return_txnid_i),
        .tx_dat_valid_i        (axi_read_data_valid_i),
        .tx_dat_ready_o        (axi_read_data_ready_o),
        .axi2td_data_i         (axi_read_data_i),
        .axi2td_id_i           (axi_read_id_i),
        // Modify by Michael Tan，20261015: propagate read error.
        .axi_read_status_i (axi_read_status_i),
        .tx_dat_fifo_full_i    (chi_tx_dat_full_i),
        .tx_dat_fifo_write_o   (chi_tx_dat_write_o),
        .tx_dat_fifo_data_o    (chi_tx_dat_flit_o),
        .packet_counter_o      (transmitted_packet_count_o)
    );
endmodule
`default_nettype wire
