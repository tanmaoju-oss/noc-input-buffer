// Module RxReq_CH
// Designer XX
`timescale 1ns/1ps
`default_nettype none

// DMT/DWT attributes are captured by SN_Top_new alongside this request parser.
module RxReq_Ch (
    input   wire    clk,
    input   wire    rst_n,
    // Router Data
    input   wire    [127 : 0]   rx_req_datout,
    // FIFO Response
    input   wire    rx_req_fifo_empty,
    output  wire    rx_req_rd_req,
    output  wire    opcode_error,
    // Trans data to rr_Txn_Ch with handshake mechanism
    input   wire    td_rr_ready,
    output  wire    rr_td_valid,
    output  wire    [44 : 0]    rr_td_datout,
    // Trans data to AXI_master with handshake mechanism
    input   wire    axi_rr_ready,
    output  wire    rr_axi_valid,
    output  wire    [51 : 0]    rr_axi_datout,
    // Trans req_w to Txn channel
    input   wire    tr_rw_ready,
    output  wire    rw_tr_valid,
    output  wire    [37 : 0]    rw_tr_datout,
    // Trans req_w to RxDat channel
    input   wire    rd_rw_ready,
    output  wire    rw_rd_valid,
    output  wire    [51 : 0]    rw_rd_datout,
    // Feedback from rw Channel
    input   wire    [7 : 0]     AXItoRxReq_b_resp,
    // Modify by Michael Tan，20261015: release malformed/timed-out write without AXI B.
    input wire [7:0] write_abort_i
);

    // internal interface from req_if to req_r
    wire if_rr_valid;
    wire rr_if_ready;
    wire [91 : 0]   if_rr_datout;
    // internal interface from req_if to req_w
    wire if_rw_valid;
    wire rw_if_ready;
    wire [91 : 0]   if_rw_datout;
    // instantiate the top-level module
    req_if  u_req_if(
        // clock and rst signal
        .clk    (clk),
        .rst_n  (rst_n),
        // rx fifo signal
        .rx_req_datout  (rx_req_datout),
        .rx_req_fifo_empty  (rx_req_fifo_empty),
        .rx_req_rd_req  (rx_req_rd_req),
        // verify the opcode
        .opcode_error   (opcode_error),
        // interface for read request operation
        .if_rr_valid    (if_rr_valid),
        .rr_if_ready    (rr_if_ready),
        .if_rr_datout   (if_rr_datout),
        // interface for request write operation
        .if_rw_valid    (if_rw_valid),
        .rw_if_ready    (rw_if_ready),
        .if_rw_datout   (if_rw_datout),
        //b response for AXI write
        .AXItoRxReq_b_resp  (AXItoRxReq_b_resp),
        // Modify by Michael Tan，20261015: independent abort/B release.
        .write_abort_i (write_abort_i)
    );

    req_r u_req_r(
        // clock and rst signal
        .clk    (clk),
        .rst_n  (rst_n),
        // interface for rr handshake mechanism
        .if_rr_valid    (if_rr_valid),
        .rr_if_ready    (rr_if_ready),
        .if_rr_datout   (if_rr_datout),
        // interface from rr to transaction data channel
        .rr_td_valid    (rr_td_valid),
        .td_rr_ready    (td_rr_ready),
        .rr_td_datout   (rr_td_datout),
        // interface from rr to axi output port
        .rr_axi_valid   (rr_axi_valid),
        .axi_rr_ready   (axi_rr_ready),
        .rr_axi_datout   (rr_axi_datout)
    );

    req_w   u_req_w(
        // clk and rst signal
        .clk    (clk),
        .rst_n  (rst_n),
        // interface for rw handshake mechanism
        .if_rw_valid    (if_rw_valid),
        .rw_if_ready    (rw_if_ready),
        .if_rw_datout    (if_rw_datout),
        // interface from rw to transaction response channel
        .rw_tr_valid    (rw_tr_valid),
        .tr_rw_ready    (tr_rw_ready),
        .rw_tr_datout   (rw_tr_datout),
        // interface from rw to request data channel
        .rd_rw_ready    (rd_rw_ready),
        .rw_rd_valid    (rw_rd_valid),
        .rw_rd_datout   (rw_rd_datout)
    );
endmodule

module req_if (
    // clock and rst signal
    input   wire clk,
    input   wire rst_n,
    // rx fifo signal
    input   wire [127 : 0]  rx_req_datout,
    input   wire rx_req_fifo_empty,
    output  wire rx_req_rd_req,
    // verify the opcode
    output  reg  opcode_error,
    // interface for read request operation
    output  wire if_rr_valid,
    input   wire rr_if_ready,
    output  wire [91 : 0]   if_rr_datout,
    // interface for request write operation
    output  wire if_rw_valid,
    input   wire rw_if_ready,
    output  wire [91:0]     if_rw_datout,
    // AXI write response channel b
    input   wire [7 : 0]    AXItoRxReq_b_resp,
    // Modify by Michael Tan，20261015: error recovery sideband.
    input wire [7:0] write_abort_i
);
    // opcode classification definition
    localparam [6:0]    OPCODE_READ_NO_SNP = 7'h04;
    localparam [6:0]    OPCODE_WRITE_NO_SNP_PTL = 7'h1C;
    localparam [6:0]    OPCODE_WRITE_NO_SNP_FULL = 7'h1d;
    // opcode encoding according to the write and read
    localparam [1:0]    REQ_TYPE_NONE = 2'b00;
    localparam [1:0]    REQ_TYPE_READ = 2'b01;
    localparam [1:0]    REQ_TYPE_WRITE = 2'b10;
    // Transaction ID to 6 bit 64 table index
    function [5:0] txnid_to_table_index;
        input   [6:0]   txnid_low7;
        begin
            case (txnid_low7[6:4])
                3'b000  :   txnid_to_table_index    =   {2'b00, txnid_low7[3:0]};
                3'b010  :   txnid_to_table_index    =   {2'b01, txnid_low7[3:0]};
                3'b110  :   txnid_to_table_index    =   {2'b10, txnid_low7[3:0]};
                default:    txnid_to_table_index    =   {2'b11, txnid_low7[3:0]};
            endcase
        end
    endfunction
    // Router flit resolution
    function txnid_node_supported;
        input [6:0] txnid_low7;
        begin
        txnid_node_supported    =   (txnid_low7[6:4] == 3'b000)  ||  (txnid_low7[6:4] == 3'b010)
                                    ||  (txnid_low7[6:4] == 3'b110);
        end
    endfunction
    // generation of dbid for data buffer identifier
    wire [11:0] incoming_dbid;
    wire [6:0]  incoming_home_nid;
    wire [39:0] incoming_addr;
    wire [6:0]  incoming_opcode;
    wire [11:0] incoming_txnid;
    wire [13:0] incoming_srcid_tgtid;
    wire [91:0] incoming_payload;
    //information translation
    assign incoming_dbid = incoming_txnid;
    assign incoming_home_nid = rx_req_datout[17:11];
    assign incoming_addr = rx_req_datout[99:60];
    assign incoming_opcode = rx_req_datout[56:50];
    assign incoming_txnid = rx_req_datout[29:18];
    assign incoming_srcid_tgtid = rx_req_datout[17:4];
    assign incoming_payload = {incoming_dbid,   incoming_home_nid,    incoming_addr,
                               incoming_opcode,    incoming_txnid, incoming_srcid_tgtid};
    // register reserve the data from fifo
    reg [91:0]  request_payload_q;
    reg [1:0]   request_type_q;
    reg         request_valid_q;
    // the state for whether send request to fifo
    reg fetch_pending_q;
    // the 64 addr register
    reg [39:0]  write_addr_q  [0:63];
    reg [63:0]  write_valid_q;
    // txnid_low7 buffer
    wire [6:0]  buffered_txnid_low7;
    // write table data buffer
    wire [5:0]  buffered_write_index;
    // buffer write supported node sign
    wire        buffered_write_node_supported;
    // present write buffer valid sign
    wire        buffered_write_slot_busy;
    // buffer mapping relation
    assign buffered_txnid_low7 = request_payload_q[20:14];
    assign buffered_write_index = txnid_to_table_index(buffered_txnid_low7);
    assign buffered_write_node_supported = txnid_node_supported(buffered_txnid_low7);
    assign buffered_write_slot_busy = write_valid_q[buffered_write_index];
    // AXI b response channel
    wire        b_response_valid;
    wire [6:0]  b_response_txnid_low7;
    wire [5:0]  b_response_table_index;
    wire        b_response_node_supported;
    // b channel mapping relation
    assign b_response_valid = AXItoRxReq_b_resp[7];
    assign b_response_txnid_low7 = AXItoRxReq_b_resp[6:0];
    assign b_response_table_index = txnid_to_table_index(b_response_txnid_low7);
    assign b_response_node_supported = txnid_node_supported(b_response_txnid_low7);
    // AR channel conflict scanning
    reg         read_address_hazard;
    integer     hazard_index;
    always @(*) begin
        read_address_hazard = 1'b0;
        if (request_valid_q && request_type_q == REQ_TYPE_READ) begin
            for (hazard_index = 0; hazard_index < 64; hazard_index = hazard_index + 1) begin
                if (write_valid_q[hazard_index] && write_addr_q[hazard_index][39:6] ==
                request_payload_q[72:39]) begin
                    read_address_hazard = 1'b1;
                end
            end
        end
    end
    // from fifo to rr handshake mechanism
    wire read_dispatch_fire;
    // from fifo to rw handshake mechanism
    wire write_dispatch_fire;
    assign read_dispatch_fire = if_rr_valid && rr_if_ready;
    assign write_dispatch_fire = if_rw_valid && rw_if_ready;
    // one period for keeping the data
    assign rx_req_rd_req = fetch_pending_q;
    // the demands for read request
    assign if_rr_valid = request_valid_q && (request_type_q == REQ_TYPE_READ) &&
                         !read_address_hazard;
    // the demands for write request
    assign if_rw_valid = request_valid_q && (request_type_q == REQ_TYPE_WRITE) &&
    buffered_write_node_supported && !buffered_write_slot_busy;
    // rr and rw datout
    assign if_rr_datout = request_payload_q;
    assign if_rw_datout = request_payload_q;
    // request for receive message, decode, address table maintainance and request for release
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_payload_q <= 92'b0;
            request_type_q <= REQ_TYPE_NONE;
            request_valid_q <= 1'b0;
            fetch_pending_q <= 1'b0;
            write_valid_q <= 64'b0;
            opcode_error <= 1'b0;
        end
        else begin
            opcode_error <= 1'b0;
            // w channel b response complete, the table reset from occupation to idle
            if(b_response_valid && b_response_node_supported
            && write_valid_q[b_response_table_index]) begin
                write_valid_q[b_response_table_index] <= 1'b0;
            end
            // Modify by Michael Tan，20261015: clear hazards on abort independently of B.
            if (write_abort_i[7])
                write_valid_q[txnid_to_table_index(write_abort_i[6:0])] <= 1'b0;
            if(fetch_pending_q) begin
                fetch_pending_q <= 1'b0;
                case (incoming_opcode)
                    OPCODE_READ_NO_SNP : begin
                        request_payload_q <= incoming_payload;
                        request_type_q <= REQ_TYPE_READ;
                        request_valid_q <= 1'b1;
                    end
                    OPCODE_WRITE_NO_SNP_PTL,
                    OPCODE_WRITE_NO_SNP_FULL : begin
                        if (txnid_node_supported(incoming_txnid[6:0])) begin
                            request_payload_q <= incoming_payload;
                            request_type_q <= REQ_TYPE_WRITE;
                            request_valid_q <= 1'b1;
                        end
                        else begin
                            request_payload_q <= 92'b0;
                            request_type_q <= REQ_TYPE_NONE;
                            request_valid_q <= 1'b0;
                            opcode_error <= 1'b1;
                        end
                    end
                    default: begin
                        request_payload_q <= 92'b0;
                        request_type_q <= REQ_TYPE_NONE;
                        request_valid_q <= 1'b0;
                        opcode_error <= 1'b1;
                    end
                endcase
            end
            else if (!request_valid_q && !rx_req_fifo_empty) begin
                fetch_pending_q <= 1'b1;
            end
            if (read_dispatch_fire) begin
                request_valid_q <= 1'b0;
                request_type_q <= REQ_TYPE_NONE;
            end
            if (write_dispatch_fire) begin
                write_addr_q[buffered_write_index] <= request_payload_q[72:33];
                write_valid_q[buffered_write_index] <= 1'b1;
                request_valid_q <= 1'b0;
                request_type_q <= REQ_TYPE_NONE;
            end
        end
    end

`ifndef SYNTHESIS
    // simulation error warning
    always @(posedge clk) begin
        if (rst_n && fetch_pending_q &&
        incoming_opcode != OPCODE_READ_NO_SNP &&
        incoming_opcode != OPCODE_WRITE_NO_SNP_PTL &&
        incoming_opcode != OPCODE_WRITE_NO_SNP_FULL) begin
            $display("ERROR(req_if) : unsupported opcode, time=%0t  opcode=%h",
            $time, incoming_opcode);
        end
        if (rst_n && fetch_pending_q &&
        (incoming_opcode == OPCODE_WRITE_NO_SNP_PTL ||
        incoming_opcode == OPCODE_WRITE_NO_SNP_FULL) &&
        !txnid_node_supported(incoming_txnid[6:0])) begin
            $display("ERROR(req_if):unsupported TxnID node encoding, time=%0t TXNID=%h",
             $time, incoming_txnid);
        end
        if (rst_n && b_response_valid &&
        (!b_response_node_supported || !write_valid_q[b_response_table_index])) begin
            $display("ERROR(req_if):AXI B channel can not find Pending write, t=%0t id=%h",
            $time, b_response_txnid_low7);
        end
    end
`endif
endmodule

/* req_r : two channel(Transaction Channel and Data Channel)
    1.Txn Channel
    reserve the data for Chi protocol(DBID, HomeNID, TxnID, SrcID and TgtID)
    2.AXI Channel
    acqure the data of Addr and TxnID and generate the AR channel data
*/
module req_r (
    // clk and reset signal
    input   wire    clk,
    input   wire    rst_n,
    // input signal
    input   wire    if_rr_valid,
    output  wire    rr_if_ready,
    input   wire [91:0]     if_rr_datout,
    // internal Txn channel if
    input   wire    td_rr_ready,
    output  wire    rr_td_valid,
    output  wire [44:0]     rr_td_datout,
    // internal AXI R channel if
    input   wire    axi_rr_ready,
    output  wire    rr_axi_valid,
    output  wire [51:0]     rr_axi_datout
);
    // internal reg and wire naming
    reg [91:0]  payload_q;
    reg         active_q;
    reg         txdat_pending_q;
    reg         axi_pending_q;
    // handshake mechanism sign
    wire        input_fire;
    wire        txdat_fire;
    wire        axi_fire;
    wire        txdat_complete_now;
    wire        axi_complete_now;
    assign input_fire = if_rr_valid && rr_if_ready;
    assign txdat_fire = rr_td_valid && td_rr_ready;
    assign axi_fire = rr_axi_valid && axi_rr_ready;
    assign txdat_complete_now = !txdat_pending_q || txdat_fire;
    assign axi_complete_now = !axi_pending_q || axi_fire;
    // buffer receive message condition
    assign rr_if_ready = !active_q;
    // output valid condition
    assign rr_td_valid = active_q && txdat_pending_q;
    assign rr_axi_valid = active_q && axi_pending_q;
    // txn load distribution {DBID, retureNID, TxnID, SrcID, TgtID}
    assign rr_td_datout = {payload_q[91:73], payload_q[25:0]};
    // axi load distribution {ADDR, TxnID}
    assign rr_axi_datout = {payload_q[72:33], payload_q[25:14]};
    // read txn distribution control
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            payload_q <= 92'b0;
            active_q <= 1'b0;
            txdat_pending_q <= 1'b0;
            axi_pending_q <= 1'b0;
        end
        else begin
            if (input_fire) begin
                payload_q <= if_rr_datout;
                active_q <= 1'b1;
                txdat_pending_q <= 1'b1;
                axi_pending_q <= 1'b1;
            end
            else if (active_q) begin
                if (txdat_fire) begin
                    txdat_pending_q <= 1'b0;
                end
                if (axi_fire) begin
                    axi_pending_q <= 1'b0;
                end
                if (txdat_complete_now && axi_complete_now) begin
                    active_q <= 1'b0;
                    txdat_pending_q <= 1'b0;
                    axi_pending_q <= 1'b0;
                end
            end
        end
    end
endmodule

module req_w (
    // clock and signal
    input   wire    clk,
    input   wire    rst_n,
    // input signal
    input   wire [91:0]     if_rw_datout,
    input   wire    if_rw_valid,
    output  wire    rw_if_ready,
    // Txn_Resp if {DBID, TxnID, TgtID, SrcID}
    input   wire    tr_rw_ready,
    output  wire    rw_tr_valid,
    output  wire [37:0]     rw_tr_datout,
    // Receive Data if {ADDR, TxnID}
    input   wire    rd_rw_ready,
    output  wire    rw_rd_valid,
    output  wire [51:0]     rw_rd_datout
);
    // send receive data and txn response data
    localparam [1:0] ST_IDLE  = 2'b00;
    localparam [1:0] ST_SEND_RXDAT = 2'b01;
    localparam [1:0] ST_SEND_TXRSP = 2'b10;
    // register state sign
    reg [1:0]   state_q;
    reg [91:0]  payload_q ;
    // handshake incidents
    wire    input_fire;
    wire    rxdat_fire;
    wire    txrsp_fire;
    // handshake incidents conditions
    assign input_fire = if_rw_valid && rw_if_ready;
    assign rxdat_fire = rw_rd_valid && rd_rw_ready;
    assign txrsp_fire = rw_tr_valid && tr_rw_ready;
    assign rw_if_ready = (state_q == ST_IDLE);
    assign rw_rd_valid = (state_q == ST_SEND_RXDAT);
    assign rw_tr_valid = (state_q == ST_SEND_TXRSP);
    // Rx_data channel load, {ADDR, TxnID}; Tx_RSP Channel load, {DBID, TxnID, SrcID, TgtID}
    assign rw_rd_datout = {payload_q[72:33], payload_q[25:14]};
    assign rw_tr_datout = {payload_q[91:80], payload_q[25:14], payload_q[13:7], payload_q[6:0]};
    // wr distribute the FSM state sequentially
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_q <= ST_IDLE;
            payload_q <= 92'b0;
        end
        else begin
            case (state_q)
                ST_IDLE : begin
                    if (input_fire) begin
                        payload_q <= if_rw_datout;
                        state_q <= ST_SEND_RXDAT;
                    end
                end
                ST_SEND_RXDAT : begin
                    if (rxdat_fire) begin
                        state_q <= ST_SEND_TXRSP;
                    end
                end
                ST_SEND_TXRSP : begin
                    if (txrsp_fire) begin
                        state_q <= ST_IDLE;
                    end
                end
                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
`default_nettype wire

// Integration wrapper with direction-qualified, protocol-oriented port names.
// The legacy RxReq_Ch core is retained to preserve the verified datapath.
`default_nettype none
module RxReq_Ch_new (
    input  wire         clk_i,
    input  wire         rst_ni,

    input  wire [127:0] chi_rx_req_flit_i,
    input  wire         chi_rx_req_empty_i,
    output wire         chi_rx_req_read_o,
    output wire         chi_rx_req_opcode_error_o,

    input  wire         read_context_ready_i,
    output wire         read_context_valid_o,
    output wire [44:0]  read_context_o,

    input  wire         axi_read_request_ready_i,
    output wire         axi_read_request_valid_o,
    output wire [51:0]  axi_read_request_o,

    input  wire         write_response_context_ready_i,
    output wire         write_response_context_valid_o,
    output wire [37:0]  write_response_context_o,

    input  wire         write_data_context_ready_i,
    output wire         write_data_context_valid_o,
    output wire [51:0]  write_data_context_o,

    input  wire [7:0]   axi_write_completion_i,
    // Modify by Michael Tan，20261015: write-abort notification.
    input wire [7:0] write_abort_i
);
    RxReq_Ch u_legacy_core (
        .clk                 (clk_i),
        .rst_n               (rst_ni),
        .rx_req_datout       (chi_rx_req_flit_i),
        .rx_req_fifo_empty   (chi_rx_req_empty_i),
        .rx_req_rd_req       (chi_rx_req_read_o),
        .opcode_error        (chi_rx_req_opcode_error_o),
        .td_rr_ready         (read_context_ready_i),
        .rr_td_valid         (read_context_valid_o),
        .rr_td_datout        (read_context_o),
        .axi_rr_ready        (axi_read_request_ready_i),
        .rr_axi_valid        (axi_read_request_valid_o),
        .rr_axi_datout       (axi_read_request_o),
        .tr_rw_ready         (write_response_context_ready_i),
        .rw_tr_valid         (write_response_context_valid_o),
        .rw_tr_datout        (write_response_context_o),
        .rd_rw_ready         (write_data_context_ready_i),
        .rw_rd_valid         (write_data_context_valid_o),
        .rw_rd_datout        (write_data_context_o),
        .AXItoRxReq_b_resp   (axi_write_completion_i),
        // Modify by Michael Tan，20261015: release aborted write contexts.
        .write_abort_i (write_abort_i)
    );
endmodule
`default_nettype wire
