`timescale 1ns/1ps
`default_nettype none

// SN_Top_new selects the normal Home target or the DWT ReturnNID target.
module TxRsp_Ch #(
    parameter [4:0]     COMP_DBID_RESP_OPCODE = 5'h05,
    parameter           USE_TXNID_AS_DBID = 1'b0
)(
    input   wire        clk_i,
    input   wire        rst_ni,
    // write handshake
    output wire        tr_rw_ready_o,
    input  wire        rw_tr_valid_i,
    input  wire [37:0] rw_tr_datout_i,
    // Router TxRsp port
    input  wire        tx_rsp_fifo_full_i,
    output wire        tx_rsp_wr_req_o,
    output wire [64:0] tx_rsp_datin_o
);
    // Tx data to FIFO
    reg        pending_q;
    reg [37:0] request_q;
    // request field name match
    wire [11:0] request_dbid;
    wire [11:0] request_txnid;
    wire [6:0]  request_srcid;
    wire [6:0]  request_tgtid;

    assign request_dbid  = request_q[37:26];
    assign request_txnid = request_q[25:14];
    assign request_srcid = request_q[13:7];
    assign request_tgtid = request_q[6:0];
    // response field name generation
    wire [11:0] response_dbid;

    assign response_dbid =
        USE_TXNID_AS_DBID ? request_txnid : request_dbid;

    wire [6:0] response_srcid;
    wire [6:0] response_tgtid;

    assign response_srcid = request_tgtid;
    assign response_tgtid = request_srcid;
    wire response_send_fire;

    assign response_send_fire =
        pending_q &&
        !tx_rsp_fifo_full_i;
    wire request_accept_fire;

    assign request_accept_fire =
        rw_tr_valid_i &&
        tr_rw_ready_o;
    assign tr_rw_ready_o =
        rst_ni &&
        (
            !pending_q ||
            response_send_fire
        );
    assign tx_rsp_wr_req_o =
        response_send_fire;
    assign tx_rsp_datin_o = {
        1'b0,                       // TraceTag
        2'b00,                      // TagOp
        4'b0000,                    // PCrdType
        response_dbid,              // DBID
        3'b000,                     // CBusy
        3'b000,                     // FwdState
        3'b000,                     // Resp
        2'b00,                      // RespErr
        COMP_DBID_RESP_OPCODE,      // Opcode
        request_txnid,              // TxnID
        response_srcid,             // 响应SrcID = 请求TgtID
        response_tgtid,             // 响应TgtID = 请求SrcID
        4'b0000                     // QoS
    };
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pending_q <= 1'b0;
            request_q <= 38'b0;
        end
        else begin
            case ({
                request_accept_fire,
                response_send_fire
            })
                2'b00: begin
                    // IDLE
                    pending_q <= pending_q;
                    request_q <= request_q;
                end

                2'b01: begin
                    // Buffer release
                    pending_q <= 1'b0;
                    request_q <= 38'b0;
                end

                2'b10: begin
                    // Buffer is empty, accept new request
                    pending_q <= 1'b1;
                    request_q <= rw_tr_datout_i;
                end

                2'b11: begin
                    // Old request send successfully
                    // New request substitute the old buffer
                    pending_q <= 1'b1;
                    request_q <= rw_tr_datout_i;
                end

                default: begin
                    pending_q <= 1'b0;
                    request_q <= 38'b0;
                end
            endcase
        end
    end
`ifndef SYNTHESIS
    reg [64:0] held_rsp_q;
    reg        held_pending_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            held_rsp_q     <= 65'b0;
            held_pending_q <= 1'b0;
        end
        else begin
            if (pending_q && tx_rsp_fifo_full_i) begin
                if (held_pending_q && tx_rsp_datin_o !== held_rsp_q) begin
                    $display("ERROR(TxRsp_Ch): response changed while TxRsp FIFO was full, time=%0t",
                             $time);
                end

                held_rsp_q     <= tx_rsp_datin_o;
                held_pending_q <= 1'b1;
            end
            else begin
                held_rsp_q     <= tx_rsp_datin_o;
                held_pending_q <= 1'b0;
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_ni &&
            tx_rsp_wr_req_o &&
            (!pending_q || tx_rsp_fifo_full_i)) begin
            $display("ERROR(TxRsp_Ch): illegal Router FIFO write request, time=%0t",
                     $time);
        end
    end
`endif

endmodule

// Integration wrapper with direction-qualified, protocol-oriented port names.
`default_nettype none
module TxRsp_Ch_new #(
    parameter [4:0] COMP_DBID_RESP_OPCODE = 5'h05,
    parameter       USE_TXNID_AS_DBID     = 1'b0
)(
    input  wire        clk_i,
    input  wire        rst_ni,

    output wire        response_context_ready_o,
    input  wire        response_context_valid_i,
    input  wire [37:0] response_context_i,

    input  wire        chi_tx_rsp_full_i,
    output wire        chi_tx_rsp_write_o,
    output wire [64:0] chi_tx_rsp_flit_o
);
    TxRsp_Ch #(
        .COMP_DBID_RESP_OPCODE (COMP_DBID_RESP_OPCODE),
        .USE_TXNID_AS_DBID     (USE_TXNID_AS_DBID)
    ) u_legacy_core (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .tr_rw_ready_o      (response_context_ready_o),
        .rw_tr_valid_i      (response_context_valid_i),
        .rw_tr_datout_i     (response_context_i),
        .tx_rsp_fifo_full_i (chi_tx_rsp_full_i),
        .tx_rsp_wr_req_o    (chi_tx_rsp_write_o),
        .tx_rsp_datin_o     (chi_tx_rsp_flit_o)
    );
endmodule
`default_nettype wire
