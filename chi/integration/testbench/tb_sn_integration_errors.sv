// Modify by Michael Tan，20261015: independent SN error/recovery regression; declarations derived from baseline TB.
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
module tb_sn_integration_errors;
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

    SN_Top_new #(.DATA_TIMEOUT_CYCLES(80)) dut (.*);
    // Modify by Michael Tan，20261015: connect newly exported AXI failure diagnostics.
    wire axi_error_o, axi_error_write_o;
    wire [11:0] axi_error_txnid_o;
    // Modify by Michael Tan，20261015: independent diagnostics retain simultaneous failures.
    wire axi_read_error_o, axi_write_error_o;
    wire [11:0] axi_read_error_txnid_o, axi_write_error_txnid_o;
    // Modify by Michael Tan，20261015: verify exact upstream abort ID.
    wire write_abort_valid_o;
    wire [11:0] write_abort_txnid_o;


    // Modify by Michael Tan，20261015: all stimulus changes on falling edges; sample handshakes on rising edges.
    integer errors=0, ar_count=0, aw_count=0, w_count=0, rsp_count=0, dat_count=0;
    integer rx_errors=0, req_errors=0, axi_errors=0;
    reg [1:0] expect_resp_err=0;
    reg [11:0] expected_read_id=0, expected_error_id=0;
    reg expect_error_write=0;
    // Modify by Michael Tan，20261015: verify simultaneous diagnostics independently.
    integer simultaneous_errors=0;
    reg expect_simultaneous=0;
    task check(input bit condition, input string label);
        if (!condition) begin errors++; $display("CHECK_ERROR %0t %s",$time,label); end
    endtask
    always @(posedge clk_i) if (rst_ni) begin
        // Modify by Michael Tan，20261015: fail on unknown handshake/error control, not just mismatched counts.
        check(!$isunknown({chi_rx_req_read_o,chi_rx_dat_read_o,chi_tx_rsp_write_o,
            chi_tx_dat_write_o,axi_error_o,axi_read_error_o,axi_write_error_o,
            write_abort_valid_o,m_axi_arvalid_o,m_axi_awvalid_o,m_axi_wvalid_o}),"unknown control outputs");
        if (m_axi_arvalid_o && m_axi_arready_i) ar_count++;
        if (m_axi_awvalid_o && m_axi_awready_i) aw_count++;
        if (m_axi_wvalid_o && m_axi_wready_i) w_count++;
        if (chi_tx_rsp_write_o) rsp_count++;
        if (chi_rx_dat_error_o) rx_errors++;
        if (chi_rx_req_opcode_error_o) req_errors++;
        if (write_abort_valid_o)
            check(write_abort_txnid_o === 12'h60b,"aborted full TxnID notification");
        if (axi_read_error_o && axi_write_error_o) begin
            simultaneous_errors++;
            check(expect_simultaneous,"unexpected simultaneous error pair");
            check(axi_read_error_txnid_o === 12'h60e && axi_write_error_txnid_o === 12'h60d,"simultaneous full IDs");
        end
        if (axi_error_o) begin
            axi_errors++;
            if (!expect_simultaneous) begin
                check(axi_error_txnid_o === expected_error_id,"AXI error full TxnID");
                check(axi_error_write_o === expect_error_write,"AXI error direction");
            end
        end
        if (chi_tx_dat_write_o) begin
            dat_count++;
            check(chi_tx_dat_flit_o[42:41] === expect_resp_err,"read RespErr");
            check(chi_tx_dat_flit_o[29:18] === expected_read_id,"read return TxnID");
        end
    end

    task request(input [6:0] op,input [11:0] id,input [39:0] addr,input bit direct_mode);
        @(negedge clk_i);
        chi_rx_req_flit_i=0;
        chi_rx_req_flit_i[56:50]=op;
        chi_rx_req_flit_i[29:18]=id;
        chi_rx_req_flit_i[99:60]=addr;
        chi_rx_req_flit_i[17:11]=REQUESTER_NID;
        chi_rx_req_flit_i[10:4]=SN_NID;
        req_dmt_enable_i=direct_mode;
        req_return_nid_i=7'h45;
        req_return_txnid_i=12'habc;
        chi_rx_req_empty_i=0;
        wait(chi_rx_req_read_o);
        @(posedge clk_i);
        @(negedge clk_i);
        chi_rx_req_empty_i=1;
    endtask

    task respond_read(input [11:0] id,input [1:0] resp,input bit bad_id,input integer beats,input bit last_present);
        wait(m_axi_rready_o);
        for(integer k=0;k<beats;k++) begin
            @(negedge clk_i);
            m_axi_rvalid_i=1;
            m_axi_rid_i=bad_id ? id^12'h080 : id;
            m_axi_rdata_i=128'h1000+k;
            m_axi_rresp_i=resp;
            m_axi_rlast_i=last_present && k==beats-1;
            @(posedge clk_i);
            while(!m_axi_rready_o) @(posedge clk_i);
        end
        @(negedge clk_i);
        m_axi_rvalid_i=0; m_axi_rlast_i=0;
    endtask

    task read_case(input [11:0] id,input [1:0] resp,input bit bad_id,input integer beats,input bit last_present);
        integer dc,ec;
        dc=dat_count;ec=axi_errors;
        expect_resp_err=(resp[1] || bad_id || beats!=4 || !last_present)?2'b10:0;
        expected_read_id=id;expected_error_id=id;expect_error_write=0;
        // Modify by Michael Tan，20261015: errors must survive TxDat FIFO backpressure.
        chi_tx_dat_full_i=1;
        request(7'h04,id,40'h400,0);
        respond_read(id,resp,bad_id,beats,last_present);
        repeat(5) @(negedge clk_i);
        check(dat_count==dc,"TxDat blocked while full");
        chi_tx_dat_full_i=0;
        wait(dat_count==dc+4);
        repeat(3) @(negedge clk_i);
        check(axi_errors==ec+(expect_resp_err!=0),"read error count");
        check(!dut.busy_q[id[6:0]],"read slot released");
    endtask

    task write_start(input [11:0] id);
        integer rc;
        rc=rsp_count;
        request(7'h1d,id,40'h400,0);
        wait(rsp_count==rc+1);
        @(negedge clk_i);
    endtask

    task data_packet(input [11:0] id,input integer count,input integer corruption);
        for(integer k=0;k<count;k++) begin
            @(negedge clk_i);
            chi_rx_dat_empty_i=0;
            wait(chi_rx_dat_read_o);
            @(negedge clk_i);
            chi_rx_dat_flit_i=0;
            chi_rx_dat_flit_i[29:18]=(corruption==1 && k==1)?id^12'h080:id;
            chi_rx_dat_flit_i[40:37]=(corruption==2 && k==1)?4'h4:4'h3;
            chi_rx_dat_flit_i[69:68]=(corruption==3 && k==1)?2'd0:k[1:0];
            chi_rx_dat_flit_i[94:79]=16'hffff;
            chi_rx_dat_flit_i[222:95]=128'h2000+k;
            chi_rx_dat_empty_i=1;
            @(posedge clk_i);
        end
        @(negedge clk_i);
    endtask

    task complete_write(input [11:0] id,input [1:0] resp,input bit bad_bid);
        wait(m_axi_bready_o);
        @(negedge clk_i);
        m_axi_bid_i=bad_bid ? id[6:0]^7'h1 : id[6:0];
        m_axi_bresp_i=resp;m_axi_bvalid_i=1;
        @(posedge clk_i);
        @(negedge clk_i);
        m_axi_bvalid_i=0;
        repeat(4) @(negedge clk_i);
        check(!dut.busy_q[id[6:0]],"write slot released");
    endtask

    task write_case(input [11:0] id,input [1:0] resp,input bit bad_bid);
        integer ec,wc;
        ec=axi_errors;wc=w_count;
        expected_error_id=id;expect_error_write=1;
        write_start(id);
        data_packet(id,4,0);
        complete_write(id,resp,bad_bid);
        check(axi_errors==ec+(resp[1] || bad_bid),"write AXI error count");
        check(w_count==wc+4,"exact four write beats");
    endtask

    initial begin
        repeat(4) @(negedge clk_i);rst_ni=1;
        $display("CASE AXI_READ_ERRORS_AND_RECOVERY");
        read_case(12'h601,2'b10,0,4,1);
        read_case(12'h602,2'b11,0,4,1);
        read_case(12'h603,0,1,4,1);
        read_case(12'h604,0,0,2,1);
        read_case(12'h605,0,0,4,0);
        read_case(12'h606,0,0,4,1);
        read_case(12'h606,2'b01,0,4,1); // EXOKAY is not an AXI failure

        $display("CASE AXI_WRITE_ERRORS_AND_RECOVERY");
        write_case(12'h607,2'b10,0);
        write_case(12'h608,2'b11,0);
        write_case(12'h609,0,1);
        write_case(12'h60a,0,0);

        $display("CASE MALFORMED_DATA_AND_MISSING_BEATS_RECOVERY");
        for(integer c=1;c<=5;c++) begin
            automatic integer ec=rx_errors;
            automatic integer wc=w_count;
            write_start(12'h60b);
            if(c<=3) data_packet(12'h60b,4,c);
            if(c==4) data_packet(12'h60b,2,0);
            // c=5: no data at all.
            wait(rx_errors>ec);
            repeat(4) @(negedge clk_i);
            check(w_count==wc,"malformed/partial write never reached AXI");
            check(!dut.busy_q[7'h0b],"aborted slot released");
            read_case(12'h60b,0,0,4,1); // same line and exact ID reuse without reset
        end

        $display("CASE UNSUPPORTED_READ_WRITE_ID");
        begin
            integer ac,ec;
            ac=ar_count;ec=req_errors;
            request(7'h04,12'h010,40'h500,0);
            repeat(8) @(negedge clk_i);
            check(req_errors==ec+1 && ar_count==ac,"unsupported read rejected");
            ec=req_errors;ac=aw_count;
            request(7'h1d,12'h010,40'h500,0);
            repeat(8) @(negedge clk_i);
            check(req_errors==ec+1 && aw_count==ac,"unsupported write rejected");
        end

        $display("CASE LOW7_COLLISION_AND_DMT_ATTRIBUTES");
        // Modify by Michael Tan，20261015: cover exact duplicate and high-bit aliases.
        for(integer duplicate_mode=0;duplicate_mode<2;duplicate_mode++) begin
            integer dc;
            dc=dat_count;
            expected_read_id=12'habc;expect_resp_err=0;
            request(7'h04,12'h60c,40'h600,1);
            // A second request has identical low7 but different high5 and DMT.
            // Keep it at FIFO head until the first full response completes.
            fork
                begin
                    request(7'h04,duplicate_mode ? 12'h68c : 12'h60c,40'h640,0);
                end
                begin
                    repeat(6) @(negedge clk_i);
                    check(!chi_rx_req_read_o,"busy low7 request stalled");
                    respond_read(12'h60c,0,0,4,1);
                    wait(dat_count==dc+4);
                    @(negedge clk_i);expected_read_id=duplicate_mode ? 12'h68c : 12'h60c;
                end
            join
            respond_read(duplicate_mode ? 12'h68c : 12'h60c,0,0,4,1);
            wait(dat_count==dc+8);
            repeat(3) @(negedge clk_i);
            check(!dut.busy_q[7'h0c],"collision slot released");
        end
        $display("CASE ORPHAN_FULL_AND_PARTIAL_PACKETS");
        begin
            integer ec,wc;
            ec=rx_errors;wc=w_count;
            data_packet(12'h60f,4,0);
            wait(rx_errors==ec+1);
            data_packet(12'h60f,1,0);
            wait(rx_errors==ec+2);
            repeat(4) @(negedge clk_i);
            check(w_count==wc,"orphan data never reaches AXI");
            read_case(12'h60f,0,0,4,1);
        end
        // Modify by Michael Tan，20261015: response FIFO stalls must not consume write-data deadline.
        $display("CASE DBID_RESPONSE_BACKPRESSURE_TIMEOUT_ARMING");
        begin
            integer rc,ec;
            rc=rsp_count;ec=rx_errors;
            chi_tx_rsp_full_i=1;
            request(7'h1d,12'h60d,40'h400,0);
            repeat(100) @(negedge clk_i);
            check(rx_errors==ec && dut.busy_q[7'h0d],"no timeout before DBID is sent");
            chi_tx_rsp_full_i=0;
            wait(rsp_count==rc+1);
            data_packet(12'h60d,4,0);
            complete_write(12'h60d,0,0);
        end

        $display("CASE CROSS_READ_WRITE_SAME_LOW7_SERIALIZATION");
        begin
            integer dc;
            dc=dat_count;
            expected_read_id=12'h68d;expect_resp_err=0;
            write_start(12'h60d);
            data_packet(12'h60d,4,0);
            fork
                request(7'h04,12'h68d,40'h400,0);
                begin
                    repeat(6) @(negedge clk_i);
                    check(!chi_rx_req_read_o,"read/write low7 alias held until B");
                    // Modify by Michael Tan，20261015: slot is intentionally reallocated to the queued read after B.
                    wait(m_axi_bready_o);
                    @(negedge clk_i);m_axi_bid_i=7'h0d;m_axi_bresp_i=0;m_axi_bvalid_i=1;
                    @(posedge clk_i);@(negedge clk_i);m_axi_bvalid_i=0;
                end
            join
            respond_read(12'h68d,0,0,4,1);
            wait(dat_count==dc+4);
            repeat(4) @(negedge clk_i);
        end

        $display("CASE SIMULTANEOUS_AXI_READ_WRITE_ERRORS");
        // Modify by Michael Tan，20261015: a distinct ID on the same cache line must wait for pending B.
        $display("CASE_READ_AFTER_WRITE_SAME_LINE_DISTINCT_ID");
        begin
            integer dc,ac;
            dc=dat_count;
            write_start(12'h60d);data_packet(12'h60d,4,0);
            wait(m_axi_bready_o);ac=ar_count;
            expected_read_id=12'h60e;expect_resp_err=0;
            request(7'h04,12'h60e,40'h400,0);
            repeat(6) @(negedge clk_i);
            check(ar_count==ac,"same-line read held until write B");
            complete_write(12'h60d,0,0);
            respond_read(12'h60e,0,0,4,1);
            wait(dat_count==dc+4);repeat(4) @(negedge clk_i);
        end

        $display("CASE_EXPIRED_CONTEXT_DURING_OTHER_PACKET");
        begin
            integer ec,wc;
            ec=rx_errors;wc=w_count;
            write_start(12'h60b);
            repeat(65) @(negedge clk_i);
            write_start(12'h60d);data_packet(12'h60d,4,0);
            complete_write(12'h60d,0,0);
            wait(rx_errors==ec+1);
            check(w_count==wc+4,"unrelated expiration preserves valid write beats");
            read_case(12'h60b,0,0,4,1);
        end

        $display("CASE SIMULTANEOUS_AXI_READ_WRITE_ERRORS_ACTUAL");
        begin
            integer dc,sc;
            dc=dat_count;sc=simultaneous_errors;
            write_start(12'h60d);
            data_packet(12'h60d,4,0);
            wait(m_axi_bready_o);
            expected_read_id=12'h60e;expect_resp_err=2'b10;
            expect_simultaneous=1;
            request(7'h04,12'h60e,40'h800,0);
            fork
                respond_read(12'h60e,2'b10,0,4,1);
                begin
                    wait(m_axi_rlast_i && m_axi_rvalid_i);
                    m_axi_bid_i=7'h0d;m_axi_bresp_i=2'b10;m_axi_bvalid_i=1;
                    @(posedge clk_i);@(negedge clk_i);m_axi_bvalid_i=0;
                end
            join
            wait(dat_count==dc+4);
            repeat(4) @(negedge clk_i);
            check(simultaneous_errors==sc+1,"both AXI errors retained in one cycle");
            expect_simultaneous=0;
        end
        check(errors==0,"final errors zero");
        if(errors) $fatal(1,"SN error regression failed errors=%0d",errors);
        $display("[SN_ERRORS] reads=%0d writes=%0d rx_errors=%0d req_errors=%0d axi_errors=%0d errors=0",ar_count,aw_count,rx_errors,req_errors,axi_errors);
        $display("PASS tb_sn_integration_errors");
        $finish;
    end
    initial begin #200000; $fatal(1,"timeout in SN error regression"); end
endmodule
`default_nettype wire
