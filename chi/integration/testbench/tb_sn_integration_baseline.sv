// Modify by Michael Tan，20261015: import comprehensive SN self-check from chi/new/CHI-SN/sim_new/tb_SN_Top_new.v; rename top for isolated integration regression.
`timescale 1ns/1ps
`default_nettype none

// Comprehensive, self-checking verification for SN_Top_new.
//
// scenario_id_o is intentionally kept as a testbench signal so that a single
// WLF can be divided into readable functional windows:
//   0 reset                  5 illegal DMT-on-write
//   1 ordinary read          6 illegal DWT-on-read
//   2 DMT read/backpressure  7 illegal DMT+DWT
//   3 ordinary full write    8 unsupported opcode
//   4 DWT partial write      9 completed
module tb_sn_integration_baseline;
    localparam [6:0] REQUESTER_NID = 7'h21;
    localparam [6:0] SN_NID        = 7'h12;

    localparam integer SC_RESET             = 0;
    localparam integer SC_ORDINARY_READ     = 1;
    localparam integer SC_DMT_READ_BP       = 2;
    localparam integer SC_ORDINARY_WRITE    = 3;
    localparam integer SC_DWT_PARTIAL_BP    = 4;
    localparam integer SC_BAD_DMT_WRITE     = 5;
    localparam integer SC_BAD_DWT_READ      = 6;
    localparam integer SC_BAD_DUAL_DIRECT   = 7;
    localparam integer SC_BAD_OPCODE        = 8;
    localparam integer SC_DONE              = 9;

    reg         clk_i = 1'b0;
    reg         rst_ni = 1'b0;

    reg         req_dmt_enable_i = 1'b0;
    reg         req_dwt_enable_i = 1'b0;
    reg  [6:0]  req_return_nid_i = 7'b0;
    reg  [11:0] req_return_txnid_i = 12'b0;
    wire        dmt_active_o;
    wire        dwt_active_o;
    wire        direct_transfer_error_o;

    reg  [127:0] chi_rx_req_flit_i = 128'b0;
    reg          chi_rx_req_empty_i = 1'b1;
    wire         chi_rx_req_read_o;
    wire         chi_rx_req_opcode_error_o;

    reg  [222:0] chi_rx_dat_flit_i = 223'b0;
    reg          chi_rx_dat_empty_i = 1'b1;
    wire         chi_rx_dat_read_o;
    wire         chi_rx_dat_error_o;

    reg          chi_tx_rsp_full_i = 1'b0;
    wire         chi_tx_rsp_write_o;
    wire [64:0]  chi_tx_rsp_flit_o;

    reg          chi_tx_dat_full_i = 1'b0;
    wire         chi_tx_dat_write_o;
    wire [222:0] chi_tx_dat_flit_o;
    wire [9:0]   chi_tx_dat_packet_count_o;

    wire [11:0] m_axi_arid_o;
    wire [39:0] m_axi_araddr_o;
    wire [7:0]  m_axi_arlen_o;
    wire [2:0]  m_axi_arsize_o;
    wire [1:0]  m_axi_arburst_o;
    wire        m_axi_arlock_o;
    wire [3:0]  m_axi_arcache_o;
    wire [2:0]  m_axi_arprot_o;
    wire [3:0]  m_axi_arqos_o;
    wire [3:0]  m_axi_arregion_o;
    wire [0:0]  m_axi_aruser_o;
    wire        m_axi_arvalid_o;
    reg         m_axi_arready_i = 1'b1;

    reg  [11:0] m_axi_rid_i = 12'b0;
    reg  [127:0] m_axi_rdata_i = 128'b0;
    reg  [1:0]  m_axi_rresp_i = 2'b0;
    reg         m_axi_rlast_i = 1'b0;
    reg  [0:0]  m_axi_ruser_i = 1'b0;
    reg         m_axi_rvalid_i = 1'b0;
    wire        m_axi_rready_o;

    wire [11:0] m_axi_awid_o;
    wire [39:0] m_axi_awaddr_o;
    wire [7:0]  m_axi_awlen_o;
    wire [2:0]  m_axi_awsize_o;
    wire [1:0]  m_axi_awburst_o;
    wire        m_axi_awlock_o;
    wire [3:0]  m_axi_awcache_o;
    wire [2:0]  m_axi_awprot_o;
    wire [3:0]  m_axi_awqos_o;
    wire [3:0]  m_axi_awregion_o;
    wire [0:0]  m_axi_awuser_o;
    wire        m_axi_awvalid_o;
    reg         m_axi_awready_i = 1'b1;

    wire [127:0] m_axi_wdata_o;
    wire [15:0]  m_axi_wstrb_o;
    wire         m_axi_wlast_o;
    wire [0:0]   m_axi_wuser_o;
    wire         m_axi_wvalid_o;
    reg          m_axi_wready_i = 1'b1;

    reg  [6:0]  m_axi_bid_i = 7'b0;
    reg  [1:0]  m_axi_bresp_i = 2'b0;
    reg  [0:0]  m_axi_buser_i = 1'b0;
    reg         m_axi_bvalid_i = 1'b0;
    wire        m_axi_bready_o;

    // Waveform marker and human-readable scenario label.
    integer scenario_id_o;
    reg [8*40-1:0] scenario_name_o;

    integer error_count;
    integer direct_error_count;
    integer opcode_error_count;
    integer allow_direct_error;
    integer allow_opcode_error;
    integer dmt_seen;
    integer dwt_seen;

    integer total_ar_count;
    integer total_r_count;
    integer total_txdat_count;
    integer total_txrsp_count;
    integer total_aw_count;
    integer total_w_count;
    integer total_b_count;

    integer txdat_check_active;
    integer txdat_beat_index;
    reg [11:0] expected_txdat_txnid;
    reg [11:0] expected_txdat_dbid;
    reg [6:0]  expected_txdat_srcid;
    reg [6:0]  expected_txdat_tgtid;
    reg [6:0]  expected_txdat_home_nid;
    reg [127:0] expected_read_base;

    integer txrsp_check_active;
    reg [11:0] expected_txrsp_txnid;
    reg [11:0] expected_txrsp_dbid;
    reg [6:0]  expected_txrsp_srcid;
    reg [6:0]  expected_txrsp_tgtid;

    integer write_feed_enable;
    integer write_supplied;
    reg [11:0] write_feed_txnid;
    reg [127:0] write_feed_base;
    reg [15:0] write_feed_strb0;
    reg [15:0] write_feed_strb1;
    reg [15:0] write_feed_strb2;
    reg [15:0] write_feed_strb3;

    integer write_check_active;
    integer write_beat_index;
    reg [127:0] expected_write_base;
    reg [15:0] expected_write_strb0;
    reg [15:0] expected_write_strb1;
    reg [15:0] expected_write_strb2;
    reg [15:0] expected_write_strb3;

    reg ar_stalled_q;
    reg [11:0] held_arid_q;
    reg [39:0] held_araddr_q;
    reg [7:0]  held_arlen_q;
    reg [2:0]  held_arsize_q;
    reg [1:0]  held_arburst_q;

    reg aw_stalled_q;
    reg [11:0] held_awid_q;
    reg [39:0] held_awaddr_q;
    reg [7:0]  held_awlen_q;
    reg [2:0]  held_awsize_q;
    reg [1:0]  held_awburst_q;

    reg w_stalled_q;
    reg [127:0] held_wdata_q;
    reg [15:0]  held_wstrb_q;
    reg         held_wlast_q;

    integer beat;
    integer error_before;
    integer packet_before;

    always #5 clk_i = ~clk_i;

    SN_Top_new dut (.*);
    // Modify by Michael Tan，20261015: connect newly exported AXI failure diagnostics.
    wire axi_error_o, axi_error_write_o;
    wire [11:0] axi_error_txnid_o;
    // Modify by Michael Tan，20261015: connect independent read/write error diagnostics.
    wire axi_read_error_o, axi_write_error_o;
    wire [11:0] axi_read_error_txnid_o, axi_write_error_txnid_o;
    // Modify by Michael Tan，20261015: upstream recovery notification must stay idle for baseline.
    wire write_abort_valid_o;
    wire [11:0] write_abort_txnid_o;

    function [15:0] selected_write_strb;
        input [1:0] index;
        begin
            case (index)
                2'd0: selected_write_strb = expected_write_strb0;
                2'd1: selected_write_strb = expected_write_strb1;
                2'd2: selected_write_strb = expected_write_strb2;
                2'd3: selected_write_strb = expected_write_strb3;
                default: selected_write_strb = 16'bx;
            endcase
        end
    endfunction

    function [15:0] selected_feed_strb;
        input [1:0] index;
        begin
            case (index)
                2'd0: selected_feed_strb = write_feed_strb0;
                2'd1: selected_feed_strb = write_feed_strb1;
                2'd2: selected_feed_strb = write_feed_strb2;
                2'd3: selected_feed_strb = write_feed_strb3;
                default: selected_feed_strb = 16'bx;
            endcase
        end
    endfunction

    task report_error;
        input [8*160-1:0] message;
        begin
            error_count = error_count + 1;
            $display("CHECK_ERROR t=%0t scenario=%0d: %0s", $time, scenario_id_o, message);
        end
    endtask

    task set_scenario;
        input integer scenario;
        input [8*40-1:0] name;
        begin
            scenario_id_o = scenario;
            scenario_name_o = name;
            $display("SCENARIO_START t=%0t id=%0d name=%0s", $time, scenario, name);
        end
    endtask

    // Protocol scoreboard and error/status observation.
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            if (chi_rx_req_read_o || chi_rx_dat_read_o ||
                chi_tx_rsp_write_o || chi_tx_dat_write_o ||
                m_axi_arvalid_o || m_axi_rready_o ||
                m_axi_awvalid_o || m_axi_wvalid_o || m_axi_bready_o)
                report_error("transaction output asserted during reset");
            if (dmt_active_o || dwt_active_o || direct_transfer_error_o)
                report_error("direct-transfer status asserted during reset");
            if (chi_tx_dat_packet_count_o !== 10'b0)
                report_error("TxDat packet counter did not reset to zero");
        end
        else begin
            if (direct_transfer_error_o) begin
                direct_error_count = direct_error_count + 1;
                if (!allow_direct_error)
                    report_error("unexpected direct_transfer_error_o");
            end

            if (chi_rx_req_opcode_error_o) begin
                opcode_error_count = opcode_error_count + 1;
                if (!allow_opcode_error)
                    report_error("unexpected chi_rx_req_opcode_error_o");
            end

            if (chi_rx_dat_error_o)
                report_error("unexpected chi_rx_dat_error_o");
            // Modify by Michael Tan，20261015: ordinary traffic must not produce AXI failure notifications.
            if (axi_error_o || axi_read_error_o || axi_write_error_o)
                report_error("unexpected AXI failure diagnostic");
            if (write_abort_valid_o)
                report_error("unexpected write abort");

            if (dmt_active_o)
                dmt_seen = 1;
            if (dwt_active_o)
                dwt_seen = 1;

            if (m_axi_arvalid_o && m_axi_arready_i)
                total_ar_count = total_ar_count + 1;
            if (m_axi_rvalid_i && m_axi_rready_o)
                total_r_count = total_r_count + 1;
            if (m_axi_awvalid_o && m_axi_awready_i)
                total_aw_count = total_aw_count + 1;
            if (m_axi_bvalid_i && m_axi_bready_o)
                total_b_count = total_b_count + 1;

            if (chi_tx_dat_write_o) begin
                total_txdat_count = total_txdat_count + 1;
                if (!txdat_check_active) begin
                    report_error("unexpected TxDat flit");
                end
                else begin
                    if (chi_tx_dat_flit_o[222:95] !==
                        (expected_read_base + txdat_beat_index))
                        report_error("TxDat data ordering mismatch");
                    if (chi_tx_dat_flit_o[94:79] !== 16'hffff)
                        report_error("TxDat byte enable mismatch");
                    if (chi_tx_dat_flit_o[78:70] !== 9'b0 ||
                        chi_tx_dat_flit_o[67:66] !== 2'b0)
                        report_error("TxDat response/reserved field mismatch");
                    if (chi_tx_dat_flit_o[69:68] !== txdat_beat_index[1:0])
                        report_error("TxDat DataID is not 0,1,2,3");
                    if (chi_tx_dat_flit_o[65:54] !== expected_txdat_dbid)
                        report_error("TxDat DBID mismatch");
                    if (chi_tx_dat_flit_o[40:37] !== 4'h4)
                        report_error("TxDat opcode is not CompData");
                    if (chi_tx_dat_flit_o[36:30] !== expected_txdat_home_nid)
                        report_error("TxDat HomeNID mismatch");
                    if (chi_tx_dat_flit_o[29:18] !== expected_txdat_txnid)
                        report_error("TxDat TxnID routing mismatch");
                    if (chi_tx_dat_flit_o[17:11] !== expected_txdat_srcid)
                        report_error("TxDat SrcID mismatch");
                    if (chi_tx_dat_flit_o[10:4] !== expected_txdat_tgtid)
                        report_error("TxDat TgtID routing mismatch");

                    txdat_beat_index = txdat_beat_index + 1;
                    if (txdat_beat_index == 4)
                        txdat_check_active = 0;
                end
            end

            if (chi_tx_rsp_write_o) begin
                total_txrsp_count = total_txrsp_count + 1;
                if (!txrsp_check_active) begin
                    report_error("unexpected TxRsp flit");
                end
                else begin
                    if (chi_tx_rsp_flit_o[57:46] !== expected_txrsp_dbid)
                        report_error("TxRsp DBID mismatch");
                    if (chi_tx_rsp_flit_o[39:35] !== 5'b0)
                        report_error("TxRsp Resp/RespErr mismatch");
                    if (chi_tx_rsp_flit_o[34:30] !== 5'h05)
                        report_error("TxRsp opcode is not CompDBIDResp");
                    if (chi_tx_rsp_flit_o[29:18] !== expected_txrsp_txnid)
                        report_error("TxRsp TxnID mismatch");
                    if (chi_tx_rsp_flit_o[17:11] !== expected_txrsp_srcid)
                        report_error("TxRsp SrcID mismatch");
                    if (chi_tx_rsp_flit_o[10:4] !== expected_txrsp_tgtid)
                        report_error("TxRsp TgtID routing mismatch");
                    txrsp_check_active = 0;
                end
            end

            if (m_axi_wvalid_o && m_axi_wready_i) begin
                total_w_count = total_w_count + 1;
                if (!write_check_active) begin
                    report_error("unexpected AXI W beat");
                end
                else begin
                    if (m_axi_wdata_o !==
                        (expected_write_base + write_beat_index))
                        report_error("AXI W data ordering mismatch");
                    if (m_axi_wstrb_o !==
                        selected_write_strb(write_beat_index[1:0]))
                        report_error("AXI WSTRB mismatch");
                    if (m_axi_wlast_o !== (write_beat_index == 3))
                        report_error("AXI WLAST sequencing mismatch");
                    write_beat_index = write_beat_index + 1;
                    if (write_beat_index == 4)
                        write_check_active = 0;
                end
            end
        end
    end

    // AXI requires address/data payloads to remain stable while VALID is held
    // and READY is low. These checks make the backpressure behavior explicit.
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ar_stalled_q <= 1'b0;
            aw_stalled_q <= 1'b0;
            w_stalled_q  <= 1'b0;
        end
        else begin
            if (ar_stalled_q) begin
                if (!m_axi_arvalid_o)
                    report_error("ARVALID dropped while ARREADY was low");
                if (m_axi_arid_o !== held_arid_q ||
                    m_axi_araddr_o !== held_araddr_q ||
                    m_axi_arlen_o !== held_arlen_q ||
                    m_axi_arsize_o !== held_arsize_q ||
                    m_axi_arburst_o !== held_arburst_q)
                    report_error("AXI AR payload changed under backpressure");
            end
            ar_stalled_q <= m_axi_arvalid_o && !m_axi_arready_i;
            if (m_axi_arvalid_o && !m_axi_arready_i) begin
                held_arid_q    <= m_axi_arid_o;
                held_araddr_q  <= m_axi_araddr_o;
                held_arlen_q   <= m_axi_arlen_o;
                held_arsize_q  <= m_axi_arsize_o;
                held_arburst_q <= m_axi_arburst_o;
            end

            if (aw_stalled_q) begin
                if (!m_axi_awvalid_o)
                    report_error("AWVALID dropped while AWREADY was low");
                if (m_axi_awid_o !== held_awid_q ||
                    m_axi_awaddr_o !== held_awaddr_q ||
                    m_axi_awlen_o !== held_awlen_q ||
                    m_axi_awsize_o !== held_awsize_q ||
                    m_axi_awburst_o !== held_awburst_q)
                    report_error("AXI AW payload changed under backpressure");
            end
            aw_stalled_q <= m_axi_awvalid_o && !m_axi_awready_i;
            if (m_axi_awvalid_o && !m_axi_awready_i) begin
                held_awid_q    <= m_axi_awid_o;
                held_awaddr_q  <= m_axi_awaddr_o;
                held_awlen_q   <= m_axi_awlen_o;
                held_awsize_q  <= m_axi_awsize_o;
                held_awburst_q <= m_axi_awburst_o;
            end

            if (w_stalled_q) begin
                if (!m_axi_wvalid_o)
                    report_error("WVALID dropped while WREADY was low");
                if (m_axi_wdata_o !== held_wdata_q ||
                    m_axi_wstrb_o !== held_wstrb_q ||
                    m_axi_wlast_o !== held_wlast_q)
                    report_error("AXI W payload changed under backpressure");
            end
            w_stalled_q <= m_axi_wvalid_o && !m_axi_wready_i;
            if (m_axi_wvalid_o && !m_axi_wready_i) begin
                held_wdata_q <= m_axi_wdata_o;
                held_wstrb_q <= m_axi_wstrb_o;
                held_wlast_q <= m_axi_wlast_o;
            end
        end
    end

    // FIFO model for the CHI RxDat channel. Data is changed only after the
    // DUT requests the next flit, matching the legacy FIFO interface contract.
    always @(negedge clk_i) begin
        if (write_feed_enable && chi_rx_dat_read_o) begin
            chi_rx_dat_flit_i = 223'b0;
            chi_rx_dat_flit_i[222:95] = write_feed_base + write_supplied;
            chi_rx_dat_flit_i[94:79] = selected_feed_strb(write_supplied[1:0]);
            chi_rx_dat_flit_i[29:18] = write_feed_txnid;
            // Modify by Michael Tan，20261015: generate legal ordered NCBWrData instead of zero opcode/DataID fixtures.
            chi_rx_dat_flit_i[40:37] = 4'h3;
            chi_rx_dat_flit_i[69:68] = write_supplied[1:0];
            write_supplied = write_supplied + 1;
            if (write_supplied == 4)
                chi_rx_dat_empty_i = 1'b1;
        end
    end

    task issue_request;
        input [6:0]  opcode;
        input [11:0] txnid;
        input [39:0] address;
        input        dmt_enable;
        input        dwt_enable;
        input [6:0]  return_nid;
        input [11:0] return_txnid;
        begin
            req_dmt_enable_i = dmt_enable;
            req_dwt_enable_i = dwt_enable;
            req_return_nid_i = return_nid;
            req_return_txnid_i = return_txnid;

            @(negedge clk_i);
            chi_rx_req_flit_i = 128'b0;
            chi_rx_req_flit_i[99:60] = address;
            chi_rx_req_flit_i[56:50] = opcode;
            chi_rx_req_flit_i[29:18] = txnid;
            chi_rx_req_flit_i[17:11] = REQUESTER_NID;
            chi_rx_req_flit_i[10:4] = SN_NID;
            chi_rx_req_empty_i = 1'b0;
            wait (chi_rx_req_read_o);
            @(negedge clk_i);
            chi_rx_req_empty_i = 1'b1;
        end
    endtask

    task run_read_case;
        input        enable_dmt;
        input        enable_dwt;
        input        expect_direct_error;
        input        use_backpressure;
        input [11:0] request_txnid;
        input [39:0] request_addr;
        input [6:0]  return_nid;
        input [11:0] return_txnid;
        input [127:0] data_base;
        reg [11:0] expected_response_txnid;
        reg [6:0]  expected_response_tgtid;
        begin
            dmt_seen = 0;
            dwt_seen = 0;
            error_before = direct_error_count;
            allow_direct_error = expect_direct_error;

            expected_response_txnid =
                (enable_dmt && !enable_dwt) ? return_txnid : request_txnid;
            expected_response_tgtid =
                (enable_dmt && !enable_dwt) ? return_nid : REQUESTER_NID;

            expected_txdat_txnid = expected_response_txnid;
            expected_txdat_dbid = request_txnid;
            expected_txdat_srcid = SN_NID;
            expected_txdat_tgtid = expected_response_tgtid;
            expected_txdat_home_nid = REQUESTER_NID;
            expected_read_base = data_base;
            txdat_beat_index = 0;
            txdat_check_active = 1;
            packet_before = chi_tx_dat_packet_count_o;

            m_axi_arready_i = use_backpressure ? 1'b0 : 1'b1;
            chi_tx_dat_full_i = use_backpressure ? 1'b1 : 1'b0;

            issue_request(7'h04, request_txnid, request_addr,
                          enable_dmt, enable_dwt, return_nid, return_txnid);

            wait (m_axi_arvalid_o);
            #1;
            if (m_axi_arid_o !== request_txnid ||
                m_axi_araddr_o !== request_addr ||
                m_axi_arlen_o !== 8'd3 ||
                m_axi_arsize_o !== 3'd4 ||
                m_axi_arburst_o !== 2'b01 ||
                m_axi_arlock_o !== 1'b0)
                report_error("AXI AR request field mismatch");

            if (use_backpressure) begin
                repeat (3) @(posedge clk_i);
                @(negedge clk_i);
                m_axi_arready_i = 1'b1;
            end
            wait (m_axi_arvalid_o && m_axi_arready_i);
            @(posedge clk_i);

            for (beat = 0; beat < 4; beat = beat + 1) begin
                @(negedge clk_i);
                m_axi_rid_i = request_txnid;
                m_axi_rdata_i = data_base + beat;
                m_axi_rresp_i = 2'b00;
                m_axi_rlast_i = (beat == 3);
                m_axi_rvalid_i = 1'b1;
                @(posedge clk_i);
                while (!m_axi_rready_o)
                    @(posedge clk_i);
                @(negedge clk_i);
                m_axi_rvalid_i = 1'b0;
                if (use_backpressure && beat == 1)
                    repeat (2) @(posedge clk_i);
            end
            m_axi_rlast_i = 1'b0;

            if (use_backpressure) begin
                repeat (3) @(posedge clk_i);
                if (txdat_beat_index != 0)
                    report_error("TxDat advanced while chi_tx_dat_full_i was high");
                @(negedge clk_i);
                chi_tx_dat_full_i = 1'b0;
            end

            wait (!txdat_check_active);
            wait (chi_tx_dat_packet_count_o == packet_before + 1'b1);
            repeat (2) @(posedge clk_i);

            if (txdat_beat_index != 4)
                report_error("read did not produce four TxDat flits");
            if (expect_direct_error) begin
                if (direct_error_count != error_before + 1)
                    report_error("illegal direct-read mode did not raise one error pulse");
                if (dmt_seen || dwt_seen)
                    report_error("illegal direct-read mode became active");
            end
            else begin
                if (direct_error_count != error_before)
                    report_error("legal read unexpectedly raised direct-transfer error");
                if (enable_dmt && !dmt_seen)
                    report_error("DMT read never asserted dmt_active_o");
                if (!enable_dmt && dmt_seen)
                    report_error("ordinary read asserted dmt_active_o");
                if (dwt_seen)
                    report_error("read asserted dwt_active_o");
            end

            allow_direct_error = 0;
            m_axi_arready_i = 1'b1;
            chi_tx_dat_full_i = 1'b0;
        end
    endtask

    task run_write_case;
        input [6:0]  opcode;
        input        enable_dmt;
        input        enable_dwt;
        input        expect_direct_error;
        input        use_backpressure;
        input [11:0] request_txnid;
        input [39:0] request_addr;
        input [6:0]  return_nid;
        input [127:0] data_base;
        input [15:0] strb0;
        input [15:0] strb1;
        input [15:0] strb2;
        input [15:0] strb3;
        reg [6:0] expected_response_tgtid;
        begin
            dmt_seen = 0;
            dwt_seen = 0;
            error_before = direct_error_count;
            allow_direct_error = expect_direct_error;

            expected_response_tgtid =
                (enable_dwt && !enable_dmt) ? return_nid : REQUESTER_NID;
            expected_txrsp_txnid = request_txnid;
            expected_txrsp_dbid = request_txnid;
            expected_txrsp_srcid = SN_NID;
            expected_txrsp_tgtid = expected_response_tgtid;
            txrsp_check_active = 1;

            expected_write_base = data_base;
            expected_write_strb0 = strb0;
            expected_write_strb1 = strb1;
            expected_write_strb2 = strb2;
            expected_write_strb3 = strb3;
            write_beat_index = 0;
            write_check_active = 1;

            chi_tx_rsp_full_i = use_backpressure ? 1'b1 : 1'b0;
            m_axi_awready_i = use_backpressure ? 1'b0 : 1'b1;
            m_axi_wready_i = use_backpressure ? 1'b0 : 1'b1;

            issue_request(opcode, request_txnid, request_addr,
                          enable_dmt, enable_dwt, return_nid, 12'b0);

            if (use_backpressure) begin
                repeat (6) @(posedge clk_i);
                if (!txrsp_check_active || chi_tx_rsp_write_o)
                    report_error("TxRsp was not held by chi_tx_rsp_full_i");
                @(negedge clk_i);
                chi_tx_rsp_full_i = 1'b0;
            end
            wait (!txrsp_check_active);

            write_feed_txnid = request_txnid;
            write_feed_base = data_base;
            write_feed_strb0 = strb0;
            write_feed_strb1 = strb1;
            write_feed_strb2 = strb2;
            write_feed_strb3 = strb3;
            write_supplied = 0;
            write_feed_enable = 1;
            chi_rx_dat_empty_i = 1'b0;
            wait (write_supplied == 4);
            write_feed_enable = 0;

            wait (m_axi_awvalid_o);
            #1;
            if (m_axi_awid_o !== request_txnid ||
                m_axi_awaddr_o !== request_addr ||
                m_axi_awlen_o !== 8'd3 ||
                m_axi_awsize_o !== 3'd4 ||
                m_axi_awburst_o !== 2'b01 ||
                m_axi_awlock_o !== 1'b0)
                report_error("AXI AW request field mismatch");

            if (use_backpressure) begin
                wait (m_axi_wvalid_o);
                repeat (3) @(posedge clk_i);

                // Accept AW first while W remains stalled.
                @(negedge clk_i);
                m_axi_awready_i = 1'b1;
                @(posedge clk_i);
                @(negedge clk_i);

                // Accept one W beat at a time with a visible idle cycle between
                // beats. The scoreboard verifies data, strobe and WLAST.
                for (beat = 0; beat < 4; beat = beat + 1) begin
                    // Modify by Michael Tan，20261015: drive READY on falling edges to avoid races with DUT and scoreboard sampling.
                    @(negedge clk_i);
                    m_axi_wready_i = 1'b1;
                    @(posedge clk_i);
                    while (!m_axi_wvalid_o)
                        @(posedge clk_i);
                    @(negedge clk_i);
                    m_axi_wready_i = 1'b0;
                    if (beat != 3)
                        repeat (1) @(posedge clk_i);
                end
                m_axi_wready_i = 1'b1;
            end

            wait (!write_check_active);
            if (write_beat_index != 4)
                report_error("write did not produce four AXI W beats");

            wait (m_axi_bready_o);
            @(negedge clk_i);
            m_axi_bid_i = request_txnid[6:0];
            m_axi_bresp_i = 2'b00;
            m_axi_bvalid_i = 1'b1;
            @(posedge clk_i);
            while (!m_axi_bready_o)
                @(posedge clk_i);
            @(negedge clk_i);
            m_axi_bvalid_i = 1'b0;
            repeat (3) @(posedge clk_i);

            if (dut.u_axi_master.u_legacy_core.legacy_write_response_protocol_error)
                report_error("high TxnID BID reconstruction failed");

            if (expect_direct_error) begin
                if (direct_error_count != error_before + 1)
                    report_error("illegal direct-write mode did not raise one error pulse");
                if (dmt_seen || dwt_seen)
                    report_error("illegal direct-write mode became active");
            end
            else begin
                if (direct_error_count != error_before)
                    report_error("legal write unexpectedly raised direct-transfer error");
                if (enable_dwt && !dwt_seen)
                    report_error("DWT write never asserted dwt_active_o");
                if (!enable_dwt && dwt_seen)
                    report_error("ordinary write asserted dwt_active_o");
                if (dmt_seen)
                    report_error("write asserted dmt_active_o");
            end

            allow_direct_error = 0;
            chi_tx_rsp_full_i = 1'b0;
            m_axi_awready_i = 1'b1;
            m_axi_wready_i = 1'b1;
        end
    endtask

    task run_bad_opcode_case;
        integer opcode_before;
        integer ar_before;
        integer aw_before;
        integer txdat_before;
        integer txrsp_before;
        begin
            opcode_before = opcode_error_count;
            ar_before = total_ar_count;
            aw_before = total_aw_count;
            txdat_before = total_txdat_count;
            txrsp_before = total_txrsp_count;
            allow_opcode_error = 1;

            issue_request(7'h7f, 12'h01f, 40'h3c0,
                          1'b0, 1'b0, 7'b0, 12'b0);
            wait (opcode_error_count == opcode_before + 1);
            wait (!chi_rx_req_opcode_error_o);
            repeat (5) @(posedge clk_i);

            if (total_ar_count != ar_before || total_aw_count != aw_before ||
                total_txdat_count != txdat_before ||
                total_txrsp_count != txrsp_before)
                report_error("unsupported opcode incorrectly launched a transaction");

            // An unsupported request has no read/write context that could later
            // release a DMT/DWT table entry. It therefore must not allocate one.
            if (dut.direct_attr_valid_q[6'h3f] !== 1'b0)
                report_error("unsupported opcode leaked a direct-attribute entry");

            allow_opcode_error = 0;
        end
    endtask

    initial begin
        scenario_id_o = SC_RESET;
        scenario_name_o = "RESET";
        error_count = 0;
        direct_error_count = 0;
        opcode_error_count = 0;
        allow_direct_error = 0;
        allow_opcode_error = 0;
        dmt_seen = 0;
        dwt_seen = 0;

        total_ar_count = 0;
        total_r_count = 0;
        total_txdat_count = 0;
        total_txrsp_count = 0;
        total_aw_count = 0;
        total_w_count = 0;
        total_b_count = 0;

        txdat_check_active = 0;
        txdat_beat_index = 0;
        txrsp_check_active = 0;
        write_feed_enable = 0;
        write_supplied = 0;
        write_check_active = 0;
        write_beat_index = 0;

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_ni = 1'b1;
        repeat (2) @(posedge clk_i);

        set_scenario(SC_ORDINARY_READ, "ORDINARY_READ_HIGH_TXNID");
        run_read_case(1'b0, 1'b0, 1'b0, 1'b0,
                      12'h102, 40'h100, 7'h00, 12'h000, 128'h1000);

        set_scenario(SC_DMT_READ_BP, "DMT_READ_WITH_BACKPRESSURE");
        run_read_case(1'b1, 1'b0, 1'b0, 1'b1,
                      12'h206, 40'h180, 7'h33, 12'h355, 128'h2000);

        set_scenario(SC_ORDINARY_WRITE, "ORDINARY_WRITE_FULL_HIGH_TXNID");
        run_write_case(7'h1d, 1'b0, 1'b0, 1'b0, 1'b0,
                       12'h40a, 40'h240, 7'h00, 128'h3000,
                       16'hffff, 16'hffff, 16'hffff, 16'hffff);

        set_scenario(SC_DWT_PARTIAL_BP, "DWT_PARTIAL_WRITE_BACKPRESSURE");
        run_write_case(7'h1c, 1'b0, 1'b1, 1'b0, 1'b1,
                       12'h80e, 40'h280, 7'h44, 128'h4000,
                       16'hf0f0, 16'h0ff0, 16'haaaa, 16'h5555);

        set_scenario(SC_BAD_DMT_WRITE, "ILLEGAL_DMT_ON_WRITE_FALLBACK");
        run_write_case(7'h1d, 1'b1, 1'b0, 1'b1, 1'b0,
                       12'h42a, 40'h300, 7'h35, 128'h5000,
                       16'hffff, 16'hffff, 16'hffff, 16'hffff);

        set_scenario(SC_BAD_DWT_READ, "ILLEGAL_DWT_ON_READ_FALLBACK");
        run_read_case(1'b0, 1'b1, 1'b1, 1'b0,
                      12'h60c, 40'h340, 7'h45, 12'h555, 128'h6000);

        set_scenario(SC_BAD_DUAL_DIRECT, "ILLEGAL_DMT_AND_DWT_FALLBACK");
        run_read_case(1'b1, 1'b1, 1'b1, 1'b0,
                      12'h62e, 40'h380, 7'h46, 12'h666, 128'h7000);

        set_scenario(SC_BAD_OPCODE, "UNSUPPORTED_OPCODE_NO_DISPATCH");
        run_bad_opcode_case();

        set_scenario(SC_DONE, "ALL_SCENARIOS_COMPLETE");
        repeat (3) @(posedge clk_i);

        if (total_ar_count != 4 || total_r_count != 16 ||
            total_txdat_count != 16 || chi_tx_dat_packet_count_o != 4)
            report_error("final read-path transaction count mismatch");
        if (total_txrsp_count != 3 || total_aw_count != 3 ||
            total_w_count != 12 || total_b_count != 3)
            report_error("final write-path transaction count mismatch");
        if (direct_error_count != 3)
            report_error("final direct-transfer error count mismatch");
        if (opcode_error_count != 1)
            report_error("final opcode error count mismatch");
        if (chi_rx_dat_error_o)
            report_error("RxDat error asserted at end of valid scenarios");

        if (error_count == 0) begin
            // Modify by Michael Tan，20261015: export machine-readable fresh regression totals.
            $display("[SN_BASELINE] reads=%0d read_beats=%0d txdat=%0d writes=%0d write_beats=%0d responses=%0d completions=%0d direct_errors=%0d opcode_errors=%0d errors=%0d", total_ar_count, total_r_count, total_txdat_count, total_aw_count, total_w_count, total_txrsp_count, total_b_count, direct_error_count, opcode_error_count, error_count);
            $display("PASS tb_sn_integration_baseline comprehensive SN/DMT/DWT/backpressure/error coverage");
            $finish;
        end
        else begin
            $fatal(1, "FAIL tb_sn_integration_baseline errors=%0d", error_count);
        end
    end

    initial begin
        #50000;
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
