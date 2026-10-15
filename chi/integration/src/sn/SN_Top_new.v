`timescale 1ns/1ps
`default_nettype none

// CHI SN to AXI bridge with DMT and DWT direct-transfer support.
//
// Functional summary
// ------------------
// * ReadNoSnp (Opcode 0x04): RxReq creates both a CHI read-response context
//   and an AXI read request. The AXI side always issues a four-beat, 128-bit
//   INCR burst and TxDat returns four CompData flits with DataID 0,1,2,3.
// * DMT read: the AXI transaction keeps the original request TxnID, while the
//   CHI CompData TgtID/TxnID are replaced by ReturnNID/ReturnTxnID.
// * WriteNoSnpPtl/WriteNoSnpFull (Opcode 0x1c/0x1d): TxRsp emits one
//   CompDBIDResp, RxDat collects four 128-bit data flits and the AXI master
//   sends one four-beat INCR write burst. Per-flit byte enables become WSTRB.
// * DWT write: CompDBIDResp is routed to ReturnNID. Write-data matching and the
//   AXI AW/B transaction continue to use the original SN-allocated DBID/TxnID.
// * Backpressure is preserved on CHI TxRsp/TxDat and on every AXI VALID/READY
//   channel. Payloads remain stable until their handshake completes.
// * Illegal DMT/DWT combinations produce a one-cycle
//   direct_transfer_error_o pulse and fall back to ordinary routing. Unsupported
//   CHI request opcodes produce chi_rx_req_opcode_error_o and are not dispatched.
//
// Integration constraints
// -----------------------
// * The compatibility memory interface returns BID[6:0]. The AXI wrapper
//   restores BID[11:7] from its single outstanding write context.
// * The legacy context tables encode supported requester groups in TxnID[6:4]
//   (000, 010 or 110) and use TxnID[3:0] as the local transaction index.
// Modify by Michael Tan，20261015: hardening interface contract.
// * AXI read failures return CompData RespErr=NDERR and a diagnostic event.
// * Write failures after CompDBIDResp use independent full-ID diagnostics.
// * Duplicate low-7 IDs are serialized until read-last/B/abort; invalid groups
//   are consumed with an opcode/ID error and never dispatched to AXI.
// * Ordered four-flit NCBWrData is validated; missing/malformed transactions
//   abort with a full-ID notification. DATA_TIMEOUT_CYCLES starts when the
//   DBID response is enqueued, so choose a deadline covering network latency.
// * Upstream must flush late data after abort before reusing the same ID.
// * The aggregate AXI diagnostic gives writes priority on simultaneous errors;
//   use the independent read/write diagnostic channels to retain both IDs.
//
// All external inputs use the *_i suffix and all external outputs use *_o.
module SN_Top_new #(
    // Modify by Michael Tan，20261015: bounded missing write-data recovery.
    parameter integer DATA_TIMEOUT_CYCLES = 256,
    parameter integer AXI_ARUSER_WIDTH = 1,
    parameter integer AXI_RUSER_WIDTH  = 1,
    parameter integer AXI_AWUSER_WIDTH = 1,
    parameter integer AXI_WUSER_WIDTH  = 1,
    parameter integer AXI_BUSER_WIDTH  = 1
)(
    // Modify by Michael Tan，20261015: AXI errors include original full transaction ID; writes already sent CompDBIDResp.
    output wire axi_error_o,
    output wire [11:0] axi_error_txnid_o,
    output wire axi_error_write_o,
    // Modify by Michael Tan，20261015: independent channels preserve simultaneous read/write failures.
    output wire axi_read_error_o,
    output wire [11:0] axi_read_error_txnid_o,
    output wire axi_write_error_o,
    output wire [11:0] axi_write_error_txnid_o,
    // Modify by Michael Tan，20261015: upstream can flush expired/malformed transaction data by full ID.
    output wire write_abort_valid_o,
    output wire [11:0] write_abort_txnid_o,
    input  wire                         clk_i,
    input  wire                         rst_ni,

    // Per-request CHI direct-transfer attributes.  These sidebands must be
    // valid with chi_rx_req_flit_i when chi_rx_req_read_o is asserted.
    input  wire                         req_dmt_enable_i,
    input  wire [6:0]                   req_return_nid_i,
    input  wire [11:0]                  req_return_txnid_i,
    input  wire                         req_dwt_enable_i,
    output wire                         dmt_active_o,
    output wire                         dwt_active_o,
    output wire                         direct_transfer_error_o,

    input  wire [127:0]                 chi_rx_req_flit_i,
    input  wire                         chi_rx_req_empty_i,
    output wire                         chi_rx_req_read_o,
    output wire                         chi_rx_req_opcode_error_o,

    input  wire [222:0]                 chi_rx_dat_flit_i,
    input  wire                         chi_rx_dat_empty_i,
    output wire                         chi_rx_dat_read_o,
    output wire                         chi_rx_dat_error_o,

    input  wire                         chi_tx_rsp_full_i,
    output wire                         chi_tx_rsp_write_o,
    output wire [64:0]                  chi_tx_rsp_flit_o,

    input  wire                         chi_tx_dat_full_i,
    output wire                         chi_tx_dat_write_o,
    output wire [222:0]                 chi_tx_dat_flit_o,
    output wire [9:0]                   chi_tx_dat_packet_count_o,

    output wire [11:0]                  m_axi_arid_o,
    output wire [39:0]                  m_axi_araddr_o,
    output wire [7:0]                   m_axi_arlen_o,
    output wire [2:0]                   m_axi_arsize_o,
    output wire [1:0]                   m_axi_arburst_o,
    output wire                         m_axi_arlock_o,
    output wire [3:0]                   m_axi_arcache_o,
    output wire [2:0]                   m_axi_arprot_o,
    output wire [3:0]                   m_axi_arqos_o,
    output wire [3:0]                   m_axi_arregion_o,
    output wire [AXI_ARUSER_WIDTH-1:0] m_axi_aruser_o,
    output wire                         m_axi_arvalid_o,
    input  wire                         m_axi_arready_i,

    input  wire [11:0]                  m_axi_rid_i,
    input  wire [127:0]                 m_axi_rdata_i,
    input  wire [1:0]                   m_axi_rresp_i,
    input  wire                         m_axi_rlast_i,
    input  wire [AXI_RUSER_WIDTH-1:0]  m_axi_ruser_i,
    input  wire                         m_axi_rvalid_i,
    output wire                         m_axi_rready_o,

    output wire [11:0]                  m_axi_awid_o,
    output wire [39:0]                  m_axi_awaddr_o,
    output wire [7:0]                   m_axi_awlen_o,
    output wire [2:0]                   m_axi_awsize_o,
    output wire [1:0]                   m_axi_awburst_o,
    output wire                         m_axi_awlock_o,
    output wire [3:0]                   m_axi_awcache_o,
    output wire [2:0]                   m_axi_awprot_o,
    output wire [3:0]                   m_axi_awqos_o,
    output wire [3:0]                   m_axi_awregion_o,
    output wire [AXI_AWUSER_WIDTH-1:0] m_axi_awuser_o,
    output wire                         m_axi_awvalid_o,
    input  wire                         m_axi_awready_i,

    output wire [127:0]                 m_axi_wdata_o,
    output wire [15:0]                  m_axi_wstrb_o,
    output wire                         m_axi_wlast_o,
    output wire [AXI_WUSER_WIDTH-1:0]  m_axi_wuser_o,
    output wire                         m_axi_wvalid_o,
    input  wire                         m_axi_wready_i,

    // Compatibility with mem4KB_new: this memory model returns BID[6:0].
    input  wire [6:0]                   m_axi_bid_i,
    input  wire [1:0]                   m_axi_bresp_i,
    input  wire [AXI_BUSER_WIDTH-1:0]  m_axi_buser_i,
    input  wire                         m_axi_bvalid_i,
    output wire                         m_axi_bready_o
);
    wire        read_context_valid;
    wire        read_context_ready;
    wire [44:0] read_context_raw;
    wire [44:0] read_context;
    wire        axi_read_request_valid;
    wire        axi_read_request_ready;
    wire [51:0] axi_read_request;
    wire        response_context_valid;
    wire        response_context_ready;
    wire [37:0] response_context_raw;
    wire [37:0] response_context;
    wire        write_context_valid;
    wire        write_context_ready;
    wire [51:0] write_context;
    wire [7:0]  axi_write_completion;

    wire         axi_read_data_valid;
    wire         axi_read_data_ready;
    wire [511:0] axi_read_data;
    wire [11:0]  axi_read_id;
    wire         axi_write_data_valid;
    wire         axi_write_data_ready;
    wire [511:0] axi_write_data;
    wire [63:0]  axi_write_strb;
    wire [39:0]  axi_write_addr;
    wire [11:0]  axi_write_id;
    wire [15:0]  unused_write_pending;
    // Modify by Michael Tan，20261015: reserve low-7 ID until actual completion, protecting shared direct attributes.
    wire core_req_read, core_opcode_error;
    reg reject_pending_q;
    reg [127:0] busy_q;
    reg [11:0] busy_id_q [0:127];
    wire [6:0] request_low7 = chi_rx_req_flit_i[24:18];
    wire supported_group = request_low7[6:4] == 3'b000 || request_low7[6:4] == 3'b010 || request_low7[6:4] == 3'b110;
    wire [7:0] write_abort;
    assign write_abort_valid_o = write_abort[7];
    assign write_abort_txnid_o = busy_id_q[write_abort[6:0]];
    wire [1:0] axi_read_status;
    wire axi_write_error;
    // Modify by Michael Tan，20261015: use completion ID rather than possibly newer collector ID.
    wire [11:0] axi_write_error_id;
    wire read_done = chi_tx_dat_write_o && chi_tx_dat_flit_o[69:68] == 2'd3;
    wire read_error_fire = axi_read_data_valid && axi_read_data_ready && axi_read_status[1];
    assign axi_error_o = read_error_fire || axi_write_error;
    assign axi_read_error_o = read_error_fire;
    assign axi_read_error_txnid_o = axi_read_id;
    assign axi_write_error_o = axi_write_error;
    assign axi_write_error_txnid_o = axi_write_error_id;
    assign axi_error_write_o = axi_write_error;
    assign axi_error_txnid_o = axi_write_error ? axi_write_error_id : axi_read_id;
    assign chi_rx_req_read_o = core_req_read || reject_pending_q;
    assign chi_rx_req_opcode_error_o = core_opcode_error || reject_pending_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 0;
            reject_pending_q <= 0;
        end else begin
            reject_pending_q <= !reject_pending_q && !chi_rx_req_empty_i && !supported_group && !core_req_read;
            if (read_done) busy_q[chi_tx_dat_flit_o[60:54]] <= 0; // original DBID, including DMT
            if (axi_write_completion[7]) busy_q[axi_write_completion[6:0]] <= 0;
            if (write_abort[7]) busy_q[write_abort[6:0]] <= 0;
            // Modify by Michael Tan，20261015: reserve only supported operations.
            if (core_req_read && (chi_rx_req_flit_i[56:50] == 7'h04 ||
                chi_rx_req_flit_i[56:50] == 7'h1c || chi_rx_req_flit_i[56:50] == 7'h1d))
            begin
                busy_q[request_low7] <= 1;
                busy_id_q[request_low7] <= chi_rx_req_flit_i[29:18];
            end
        end
    end

    reg [63:0] direct_attr_valid_q;
    reg [63:0] request_dmt_table_q;
    reg [63:0] request_dwt_table_q;
    reg [6:0]  return_nid_table_q [0:63];
    reg [11:0] return_txnid_table_q [0:63];
    reg        direct_transfer_error_q;

    function [5:0] txnid_to_index;
        input [6:0] txnid_low7;
        begin
            case (txnid_low7[6:4])
                3'b000: txnid_to_index = {2'b00, txnid_low7[3:0]};
                3'b010: txnid_to_index = {2'b01, txnid_low7[3:0]};
                3'b110: txnid_to_index = {2'b10, txnid_low7[3:0]};
                default: txnid_to_index = {2'b11, txnid_low7[3:0]};
            endcase
        end
    endfunction

    wire [11:0] incoming_request_txnid = chi_rx_req_flit_i[29:18];
    wire [6:0]  incoming_request_opcode = chi_rx_req_flit_i[56:50];
    wire [5:0]  incoming_attr_index = txnid_to_index(incoming_request_txnid[6:0]);
    wire        incoming_is_read = (incoming_request_opcode == 7'h04);
    wire        incoming_is_write = (incoming_request_opcode == 7'h1c) ||
                                    (incoming_request_opcode == 7'h1d);

    wire [5:0] read_attr_index = txnid_to_index(read_context_raw[20:14]);
    wire [5:0] response_attr_index = txnid_to_index(response_context_raw[20:14]);
    wire read_dmt_active = direct_attr_valid_q[read_attr_index] &&
                           request_dmt_table_q[read_attr_index];
    wire response_dwt_active = direct_attr_valid_q[response_attr_index] &&
                               request_dwt_table_q[response_attr_index];

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            direct_attr_valid_q      <= 64'b0;
            request_dmt_table_q      <= 64'b0;
            request_dwt_table_q      <= 64'b0;
            direct_transfer_error_q  <= 1'b0;
        end else begin
            direct_transfer_error_q <= 1'b0;

            // Release completed contexts first.  A new request captured below
            // has priority when allocation and release use the same index.
            if (read_context_valid && read_context_ready)
                direct_attr_valid_q[read_attr_index] <= 1'b0;
            if (response_context_valid && response_context_ready)
                direct_attr_valid_q[response_attr_index] <= 1'b0;

            // Modify by Michael Tan，20261015: only allocate attributes for accepted supported-group requests.
            if (core_req_read) begin
                direct_transfer_error_q <=
                    (req_dmt_enable_i && req_dwt_enable_i) ||
                    (req_dmt_enable_i && !incoming_is_read) ||
                    (req_dwt_enable_i && !incoming_is_write);

                // Allocate direct-transfer attributes only for a request that
                // RxReq can dispatch. An unsupported opcode has no downstream
                // context to release this entry and must therefore leave the
                // table unchanged.
                if (incoming_is_read || incoming_is_write) begin
                    direct_attr_valid_q[incoming_attr_index] <= 1'b1;
                    request_dmt_table_q[incoming_attr_index] <=
                        req_dmt_enable_i && !req_dwt_enable_i && incoming_is_read;
                    request_dwt_table_q[incoming_attr_index] <=
                        req_dwt_enable_i && !req_dmt_enable_i && incoming_is_write;
                    return_nid_table_q[incoming_attr_index] <= req_return_nid_i;
                    return_txnid_table_q[incoming_attr_index] <= req_return_txnid_i;
                end
            end
        end
    end

    // DMT: the SN sends CompData directly to ReturnNID using ReturnTxnID.
    // The DBID, HomeNID and SN source NodeID remain unchanged.
    assign read_context = read_context_raw;

    // DWT: direct the DBID response to the requesting RN.  The write data
    // continues to be matched by the SN allocated DBID (TxnID in this design).
    assign response_context = response_dwt_active ?
        {response_context_raw[37:14], return_nid_table_q[response_attr_index],
         response_context_raw[6:0]} :
        response_context_raw;

    assign dmt_active_o = read_dmt_active;
    assign dwt_active_o = response_dwt_active;
    assign direct_transfer_error_o = direct_transfer_error_q;

    RxReq_Ch_new u_rx_req (
        .clk_i                           (clk_i),
        .rst_ni                          (rst_ni),
        .chi_rx_req_flit_i               (chi_rx_req_flit_i),
        .chi_rx_req_empty_i              (chi_rx_req_empty_i || !supported_group || busy_q[request_low7]),
        .chi_rx_req_read_o               (core_req_read),
        .chi_rx_req_opcode_error_o       (core_opcode_error),
        .read_context_ready_i            (read_context_ready),
        .read_context_valid_o            (read_context_valid),
        .read_context_o                  (read_context_raw),
        .axi_read_request_ready_i        (axi_read_request_ready),
        .axi_read_request_valid_o        (axi_read_request_valid),
        .axi_read_request_o              (axi_read_request),
        .write_response_context_ready_i  (response_context_ready),
        .write_response_context_valid_o  (response_context_valid),
        .write_response_context_o        (response_context_raw),
        .write_data_context_ready_i      (write_context_ready),
        .write_data_context_valid_o      (write_context_valid),
        .write_data_context_o            (write_context),
        .axi_write_completion_i          (axi_write_completion),
        // Modify by Michael Tan，20261015: abort clears read-after-write hazard.
        .write_abort_i (write_abort)
    );

    TxRsp_Ch_new u_tx_rsp (
        .clk_i                     (clk_i),
        .rst_ni                    (rst_ni),
        .response_context_ready_o  (response_context_ready),
        .response_context_valid_i  (response_context_valid),
        .response_context_i        (response_context),
        .chi_tx_rsp_full_i         (chi_tx_rsp_full_i),
        .chi_tx_rsp_write_o        (chi_tx_rsp_write_o),
        .chi_tx_rsp_flit_o         (chi_tx_rsp_flit_o)
    );

    TxDat_Ch_new u_tx_dat (
        .clk_i                       (clk_i),
        .rst_ni                      (rst_ni),
        .read_context_valid_i        (read_context_valid),
        .read_context_ready_o        (read_context_ready),
        .read_context_i              (read_context),
        .dmt_enable_i                (read_dmt_active),
        .dmt_return_nid_i            (return_nid_table_q[read_attr_index]),
        .dmt_return_txnid_i          (return_txnid_table_q[read_attr_index]),
        .axi_read_data_valid_i       (axi_read_data_valid),
        .axi_read_data_ready_o       (axi_read_data_ready),
        .axi_read_data_i             (axi_read_data),
        .axi_read_id_i               (axi_read_id),
        // Modify by Michael Tan，20261015: propagate read failure into all returned DAT beats.
        .axi_read_status_i (axi_read_status),
        .chi_tx_dat_full_i           (chi_tx_dat_full_i),
        .chi_tx_dat_write_o          (chi_tx_dat_write_o),
        .chi_tx_dat_flit_o           (chi_tx_dat_flit_o),
        .transmitted_packet_count_o  (chi_tx_dat_packet_count_o)
    );

    // Modify by Michael Tan，20261015: collector timeout is configurable, default 256 cycles.
    RxDat_Ch_new #(.DATA_TIMEOUT_CYCLES(DATA_TIMEOUT_CYCLES)) u_rx_dat (
        .clk_i                  (clk_i),
        .rst_ni                 (rst_ni),
        .write_context_valid_i  (write_context_valid),
        .write_context_ready_o  (write_context_ready),
        .write_context_i        (write_context),
        .chi_rx_dat_flit_i      (chi_rx_dat_flit_i),
        .chi_rx_dat_empty_i     (chi_rx_dat_empty_i),
        .chi_rx_dat_read_o      (chi_rx_dat_read_o),
        .axi_write_ready_i      (axi_write_data_ready),
        .axi_write_valid_o      (axi_write_data_valid),
        .axi_write_data_o       (axi_write_data),
        .axi_write_strb_o       (axi_write_strb),
        .axi_write_addr_o       (axi_write_addr),
        .axi_write_id_o         (axi_write_id),
        .rx_data_error_o        (chi_rx_dat_error_o),
        .write_abort_o (write_abort),
        // Modify by Michael Tan，20261015: FIFO response backpressure must not start missing-data timeout early.
        .response_sent_i ({chi_tx_rsp_write_o,chi_tx_rsp_flit_o[52:46]})
    );

    SNF_AXI_Master_new #(
        .AXI_ARUSER_WIDTH (AXI_ARUSER_WIDTH),
        .AXI_RUSER_WIDTH  (AXI_RUSER_WIDTH),
        .AXI_AWUSER_WIDTH (AXI_AWUSER_WIDTH),
        .AXI_WUSER_WIDTH  (AXI_WUSER_WIDTH),
        .AXI_BUSER_WIDTH  (AXI_BUSER_WIDTH)
    ) u_axi_master (
        .clk_i                   (clk_i),
        .rst_ni                  (rst_ni),
        .read_request_valid_i    (axi_read_request_valid),
        .read_request_ready_o    (axi_read_request_ready),
        .read_request_i          (axi_read_request),
        .read_data_valid_o       (axi_read_data_valid),
        .read_data_ready_i       (axi_read_data_ready),
        .read_data_o             (axi_read_data),
        .read_id_o               (axi_read_id),
        .write_request_ready_o   (axi_write_data_ready),
        .write_request_valid_i   (axi_write_data_valid),
        .write_strb_i            (axi_write_strb),
        .write_data_i            (axi_write_data),
        .write_addr_i            (axi_write_addr),
        .write_id_i              (axi_write_id),
        .m_axi_arid_o            (m_axi_arid_o),
        .m_axi_araddr_o          (m_axi_araddr_o),
        .m_axi_arlen_o           (m_axi_arlen_o),
        .m_axi_arsize_o          (m_axi_arsize_o),
        .m_axi_arburst_o         (m_axi_arburst_o),
        .m_axi_arlock_o          (m_axi_arlock_o),
        .m_axi_arcache_o         (m_axi_arcache_o),
        .m_axi_arprot_o          (m_axi_arprot_o),
        .m_axi_arqos_o           (m_axi_arqos_o),
        .m_axi_arregion_o        (m_axi_arregion_o),
        .m_axi_aruser_o          (m_axi_aruser_o),
        .m_axi_arvalid_o         (m_axi_arvalid_o),
        .m_axi_arready_i         (m_axi_arready_i),
        .m_axi_rid_i             (m_axi_rid_i),
        .m_axi_rdata_i           (m_axi_rdata_i),
        .m_axi_rresp_i           (m_axi_rresp_i),
        .m_axi_rlast_i           (m_axi_rlast_i),
        .m_axi_ruser_i           (m_axi_ruser_i),
        .m_axi_rvalid_i          (m_axi_rvalid_i),
        .m_axi_rready_o          (m_axi_rready_o),
        .m_axi_awid_o            (m_axi_awid_o),
        .m_axi_awaddr_o          (m_axi_awaddr_o),
        .m_axi_awlen_o           (m_axi_awlen_o),
        .m_axi_awsize_o          (m_axi_awsize_o),
        .m_axi_awburst_o         (m_axi_awburst_o),
        .m_axi_awlock_o          (m_axi_awlock_o),
        .m_axi_awcache_o         (m_axi_awcache_o),
        .m_axi_awprot_o          (m_axi_awprot_o),
        .m_axi_awqos_o           (m_axi_awqos_o),
        .m_axi_awregion_o        (m_axi_awregion_o),
        .m_axi_awuser_o          (m_axi_awuser_o),
        .m_axi_awvalid_o         (m_axi_awvalid_o),
        .m_axi_awready_i         (m_axi_awready_i),
        .m_axi_wdata_o           (m_axi_wdata_o),
        .m_axi_wstrb_o           (m_axi_wstrb_o),
        .m_axi_wlast_o           (m_axi_wlast_o),
        .m_axi_wuser_o           (m_axi_wuser_o),
        .m_axi_wvalid_o          (m_axi_wvalid_o),
        .m_axi_wready_i          (m_axi_wready_i),
        .m_axi_bid_i             (m_axi_bid_i),
        .m_axi_bresp_i           (m_axi_bresp_i),
        .m_axi_buser_i           (m_axi_buser_i),
        .m_axi_bvalid_i          (m_axi_bvalid_i),
        .m_axi_bready_o          (m_axi_bready_o),
        .write_completion_o      (axi_write_completion),
        .write_pending_o         (unused_write_pending),
        // Modify by Michael Tan，20261015: expose status formerly discarded by compatibility layer.
        .read_status_o (axi_read_status),
        .write_error_o (axi_write_error),
        .write_error_id_o (axi_write_error_id)
    );
endmodule

`default_nettype wire
