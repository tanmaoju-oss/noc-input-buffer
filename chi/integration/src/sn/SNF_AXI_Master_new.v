`timescale 1ns/1ps
`default_nettype none

/* Design rules
1.SN-F request to AR/R Channel
2.SN-F request to AW/W/B Channel
3.joint the response from AXI write/read to SN-f
module hierachical structure
    i.SNF-AXI master bridge
        -snf-axi-read-engine
        -snf-axi-write-engine
    ii.AXI master
        -snf-axi-master-bridge
 */

module snf_axi_master #(
    parameter   integer         AXI_ADDR_WIDTH  =   40,
    parameter   integer         AXI_ID_WIDTH    =   12,
    parameter   integer         AXI_DATA_WIDTH  =   128,
    parameter   integer         SNF_DATA_BLOCK_WIDTH    =   512,
    parameter   integer         AXI_ARUSER_WIDTH        =   1,
    parameter   integer         AXI_RUSER_WIDTH         =   1,
    parameter   integer         AXI_AWUSER_WIDTH        =   1,
    parameter   integer         AXI_WUSER_WIDTH         =   1,
    parameter   integer         AXI_BUSER_WIDTH         =   1,
    // system ram attribute and safety attribute set
    parameter [3:0] AXI_CACHE_VALUE     = 4'b0010,
    parameter [2:0] AXI_PROT_VALUE      = 3'b000,
    parameter [3:0] AXI_QOS_VALUE       = 4'b0000,
    parameter [3:0] AXI_REGION_VALUE    = 4'b000
)(
    // clk and rst_n
    input   wire    clk_i,
    input   wire    rst_ni,
    // SN-F Read if design
    input       wire                            read_request_valid_i,
    output      wire                            read_request_ready_o,
    input       wire [AXI_ID_WIDTH-1:0]         read_request_txn_id_i,
    input       wire [AXI_ADDR_WIDTH-1:0]       read_request_addr_i,
    // SN-F Read Rsp
    output      wire                            read_response_valid_o,
    input       wire                            read_response_ready_i,
    output      wire [AXI_ID_WIDTH-1:0]         read_response_txn_id_o,
    output      wire [SNF_DATA_BLOCK_WIDTH-1:0] read_response_data_o,
    output      wire [1:0]                      read_response_code_o,
    output      wire                            read_response_protocol_error_o,
    // SN-F Write if design
    input       wire                            write_request_valid_i,
    output      wire                            write_request_ready_o,
    input       wire [AXI_ID_WIDTH-1:0]         write_request_txn_id_i,
    input       wire [AXI_ADDR_WIDTH-1:0]       write_request_addr_i,
    input       wire [SNF_DATA_BLOCK_WIDTH-1:0] write_request_data_i,
    input       wire [(SNF_DATA_BLOCK_WIDTH/8)-1:0] write_request_byte_enable_i,
    // SN-F response if
    output      wire                            write_response_valid_o,
    input       wire                            write_response_ready_i,
    output      wire [AXI_ID_WIDTH-1:0]         write_response_txn_id_o,
    output      wire [1:0]                      write_response_code_o,
    output      wire                            write_response_protocol_error_o,
    // AXI master AR channel
    output      wire [AXI_ID_WIDTH-1:0]         m_axi_ar_id_o,
    output      wire [AXI_ADDR_WIDTH-1:0]       m_axi_ar_addr_o,
    output      wire [7:0]                      m_axi_ar_len_o,
    output      wire [2:0]                      m_axi_ar_size_o,
    output      wire [1:0]                      m_axi_ar_burst_o,
    output      wire                            m_axi_ar_lock_o,
    output      wire [3:0]                      m_axi_ar_cache_o,
    output      wire [2:0]                      m_axi_ar_prot_o,
    output      wire [3:0]                      m_axi_ar_qos_o,
    output      wire [3:0]                      m_axi_ar_region_o,
    output      wire [AXI_ARUSER_WIDTH-1:0]     m_axi_ar_user_o,
    output      wire                            m_axi_ar_valid_o,
    input       wire                            m_axi_ar_ready_i,
    // AXI master R channel
    input       wire [AXI_ID_WIDTH-1:0]         m_axi_r_id_i,
    input       wire [AXI_DATA_WIDTH-1:0]       m_axi_r_data_i,
    input       wire [1:0]                      m_axi_r_resp_i,
    input       wire                            m_axi_r_last_i,
    input       wire [AXI_RUSER_WIDTH-1:0]      m_axi_r_user_i,
    input       wire                            m_axi_r_valid_i,
    output      wire                            m_axi_r_ready_o,
    //--------------------------------------------------------------------------
    // AXI4 Master写地址通道AW
    //--------------------------------------------------------------------------
    output wire [AXI_ID_WIDTH-1:0]           m_axi_aw_id_o,
    output wire [AXI_ADDR_WIDTH-1:0]         m_axi_aw_addr_o,
    output wire [7:0]                        m_axi_aw_len_o,
    output wire [2:0]                        m_axi_aw_size_o,
    output wire [1:0]                        m_axi_aw_burst_o,
    output wire                              m_axi_aw_lock_o,
    output wire [3:0]                        m_axi_aw_cache_o,
    output wire [2:0]                        m_axi_aw_prot_o,
    output wire [3:0]                        m_axi_aw_qos_o,
    output wire [3:0]                        m_axi_aw_region_o,
    output wire [AXI_AWUSER_WIDTH-1:0]       m_axi_aw_user_o,
    output wire                              m_axi_aw_valid_o,
    input  wire                              m_axi_aw_ready_i,

    //--------------------------------------------------------------------------
    // AXI4 Master写数据通道W
    //--------------------------------------------------------------------------
    output wire [AXI_DATA_WIDTH-1:0]         m_axi_w_data_o,
    output wire [(AXI_DATA_WIDTH/8)-1:0]     m_axi_w_strb_o,
    output wire                              m_axi_w_last_o,
    output wire [AXI_WUSER_WIDTH-1:0]        m_axi_w_user_o,
    output wire                              m_axi_w_valid_o,
    input  wire                              m_axi_w_ready_i,

    //--------------------------------------------------------------------------
    // AXI4 Master写响应通道B
    // 标准AXI要求BID与AWID位宽一致。
    //--------------------------------------------------------------------------
    input  wire [AXI_ID_WIDTH-1:0]           m_axi_b_id_i,
    input  wire [1:0]                        m_axi_b_resp_i,
    input  wire [AXI_BUSER_WIDTH-1:0]        m_axi_b_user_i,
    input  wire                              m_axi_b_valid_i,
    output wire                              m_axi_b_ready_o
);
    snf_axi_read_burst_engine #(
            .AXI_ADDR_WIDTH      (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH        (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH      (AXI_DATA_WIDTH),
        .SNF_DATA_BLOCK_WIDTH    (SNF_DATA_BLOCK_WIDTH),
        .AXI_ARUSER_WIDTH    (AXI_ARUSER_WIDTH),
        .AXI_RUSER_WIDTH     (AXI_RUSER_WIDTH),
        .AXI_CACHE_VALUE     (AXI_CACHE_VALUE),
        .AXI_PROT_VALUE      (AXI_PROT_VALUE),
        .AXI_QOS_VALUE       (AXI_QOS_VALUE),
        .AXI_REGION_VALUE    (AXI_REGION_VALUE)
    ) u_read_burst_engine (
        .clk_i                   (clk_i),
        .rst_ni                 (rst_ni),

        .read_request_valid_i          (read_request_valid_i),
        .read_request_ready_o          (read_request_ready_o),
        .read_request_txn_id_i             (read_request_txn_id_i),
        .read_request_addr_i           (read_request_addr_i),

        .read_response_valid_o          (read_response_valid_o),
        .read_response_ready_i          (read_response_ready_i),
        .read_response_txn_id_o             (read_response_txn_id_o),
        .read_response_data_o           (read_response_data_o),
        .read_response_code_o           (read_response_code_o),
        .read_response_protocol_error_o (read_response_protocol_error_o),

        .m_axi_ar_id_o            (m_axi_ar_id_o),
        .m_axi_ar_addr_o          (m_axi_ar_addr_o),
        .m_axi_ar_len_o           (m_axi_ar_len_o),
        .m_axi_ar_size_o          (m_axi_ar_size_o),
        .m_axi_ar_burst_o         (m_axi_ar_burst_o),
        .m_axi_ar_lock_o          (m_axi_ar_lock_o),
        .m_axi_ar_cache_o         (m_axi_ar_cache_o),
        .m_axi_ar_prot_o          (m_axi_ar_prot_o),
        .m_axi_ar_qos_o           (m_axi_ar_qos_o),
        .m_axi_ar_region_o        (m_axi_ar_region_o),
        .m_axi_ar_user_o          (m_axi_ar_user_o),
        .m_axi_ar_valid_o         (m_axi_ar_valid_o),
        .m_axi_ar_ready_i         (m_axi_ar_ready_i),

        .m_axi_r_id_i             (m_axi_r_id_i),
        .m_axi_r_data_i           (m_axi_r_data_i),
        .m_axi_r_resp_i           (m_axi_r_resp_i),
        .m_axi_r_last_i           (m_axi_r_last_i),
        .m_axi_r_user_i           (m_axi_r_user_i),
        .m_axi_r_valid_i          (m_axi_r_valid_i),
        .m_axi_r_ready_o          (m_axi_r_ready_o)
    );
    
    snf_axi_write_burst_engine #(
        .AXI_ADDR_WIDTH      (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH        (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH      (AXI_DATA_WIDTH),
        .SNF_DATA_BLOCK_WIDTH    (SNF_DATA_BLOCK_WIDTH),
        .AXI_AWUSER_WIDTH    (AXI_AWUSER_WIDTH),
        .AXI_WUSER_WIDTH     (AXI_WUSER_WIDTH),
        .AXI_BUSER_WIDTH     (AXI_BUSER_WIDTH),
        .AXI_CACHE_VALUE     (AXI_CACHE_VALUE),
        .AXI_PROT_VALUE      (AXI_PROT_VALUE),
        .AXI_QOS_VALUE       (AXI_QOS_VALUE),
        .AXI_REGION_VALUE    (AXI_REGION_VALUE)
    ) u_write_burst_engine (
        .clk_i                   (clk_i),
        .rst_ni                 (rst_ni),

        .write_request_valid_i          (write_request_valid_i),
        .write_request_ready_o          (write_request_ready_o),
        .write_request_txn_id_i             (write_request_txn_id_i),
        .write_request_addr_i           (write_request_addr_i),
        .write_request_data_i           (write_request_data_i),
        .write_request_byte_enable_i           (write_request_byte_enable_i),

        .write_response_valid_o          (write_response_valid_o),
        .write_response_ready_i          (write_response_ready_i),
        .write_response_txn_id_o             (write_response_txn_id_o),
        .write_response_code_o           (write_response_code_o),
        .write_response_protocol_error_o (write_response_protocol_error_o),

        .m_axi_aw_id_o            (m_axi_aw_id_o),
        .m_axi_aw_addr_o          (m_axi_aw_addr_o),
        .m_axi_aw_len_o           (m_axi_aw_len_o),
        .m_axi_aw_size_o          (m_axi_aw_size_o),
        .m_axi_aw_burst_o         (m_axi_aw_burst_o),
        .m_axi_aw_lock_o          (m_axi_aw_lock_o),
        .m_axi_aw_cache_o         (m_axi_aw_cache_o),
        .m_axi_aw_prot_o          (m_axi_aw_prot_o),
        .m_axi_aw_qos_o           (m_axi_aw_qos_o),
        .m_axi_aw_region_o        (m_axi_aw_region_o),
        .m_axi_aw_user_o          (m_axi_aw_user_o),
        .m_axi_aw_valid_o         (m_axi_aw_valid_o),
        .m_axi_aw_ready_i         (m_axi_aw_ready_i),

        .m_axi_w_data_o           (m_axi_w_data_o),
        .m_axi_w_strb_o           (m_axi_w_strb_o),
        .m_axi_w_last_o           (m_axi_w_last_o),
        .m_axi_w_user_o           (m_axi_w_user_o),
        .m_axi_w_valid_o          (m_axi_w_valid_o),
        .m_axi_w_ready_i          (m_axi_w_ready_i),

        .m_axi_b_id_i             (m_axi_b_id_i),
        .m_axi_b_resp_i           (m_axi_b_resp_i),
        .m_axi_b_user_i           (m_axi_b_user_i),
        .m_axi_b_valid_i          (m_axi_b_valid_i),
        .m_axi_b_ready_o          (m_axi_b_ready_o)
    );

endmodule

module snf_axi_read_burst_engine #(
    parameter integer           AXI_ADDR_WIDTH          = 40,
    parameter integer           AXI_ID_WIDTH            = 12,
    parameter integer           AXI_DATA_WIDTH          = 128,
    parameter integer           SNF_DATA_BLOCK_WIDTH    = 512,
    parameter integer           AXI_ARUSER_WIDTH        = 1,
    parameter integer           AXI_RUSER_WIDTH         = 1,
    parameter integer           SNF_RUSER_WIDTH         = 1,
    parameter   [3:0]           AXI_CACHE_VALUE         = 4'b0010,
    parameter   [2:0]           AXI_PROT_VALUE          = 3'b000,
    parameter   [3:0]           AXI_QOS_VALUE           = 4'b0000,
    parameter   [3:0]           AXI_REGION_VALUE        = 4'b0000
)(
    input           wire                        clk_i,
    input           wire                        rst_ni,
    // SN read inner request handshake
    input  wire                              read_request_valid_i,
    output wire                              read_request_ready_o,
    input  wire [AXI_ID_WIDTH-1:0]           read_request_txn_id_i,
    input  wire [AXI_ADDR_WIDTH-1:0]         read_request_addr_i,
    // SN read response handshake
    output wire                              read_response_valid_o,
    input  wire                              read_response_ready_i,
    output wire [AXI_ID_WIDTH-1:0]           read_response_txn_id_o,
    output wire [SNF_DATA_BLOCK_WIDTH-1:0]       read_response_data_o,
    output wire [1:0]                        read_response_code_o,
    output wire                              read_response_protocol_error_o,
    // AXI AR channel
    output wire [AXI_ID_WIDTH-1:0]           m_axi_ar_id_o,
    output wire [AXI_ADDR_WIDTH-1:0]         m_axi_ar_addr_o,
    output wire [7:0]                        m_axi_ar_len_o,
    output wire [2:0]                        m_axi_ar_size_o,
    output wire [1:0]                        m_axi_ar_burst_o,
    output wire                              m_axi_ar_lock_o,
    output wire [3:0]                        m_axi_ar_cache_o,
    output wire [2:0]                        m_axi_ar_prot_o,
    output wire [3:0]                        m_axi_ar_qos_o,
    output wire [3:0]                        m_axi_ar_region_o,
    output wire [AXI_ARUSER_WIDTH-1:0]       m_axi_ar_user_o,
    output wire                              m_axi_ar_valid_o,
    input  wire                              m_axi_ar_ready_i,
    // AXI R channel
    input  wire [AXI_ID_WIDTH-1:0]           m_axi_r_id_i,
    input  wire [AXI_DATA_WIDTH-1:0]         m_axi_r_data_i,
    input  wire [1:0]                        m_axi_r_resp_i,
    input  wire                              m_axi_r_last_i,
    input  wire [AXI_RUSER_WIDTH-1:0]        m_axi_r_user_i,
    input  wire                              m_axi_r_valid_i,
    output wire                              m_axi_r_ready_o
);
    function integer calc_clog;
        input   integer     value;
        integer temp;
        begin
            temp = value - 1;
            calc_clog = 0;
            while (temp > 0) begin
                calc_clog = calc_clog + 1;
                temp = temp >> 1;
            end
        end
    endfunction
    // parameter assignment and burst specification calculation
    localparam integer AXI_BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam integer AXI_BEATS_PER_SNF_BLOCK     = SNF_DATA_BLOCK_WIDTH / AXI_DATA_WIDTH;
    localparam integer AXI_BEAT_INDEX_WIDTH    =
        (AXI_BEATS_PER_SNF_BLOCK <= 1) ? 1 : calc_clog(AXI_BEATS_PER_SNF_BLOCK);
    // AXI len field
    localparam [7:0]    AXI_LEN_VALUE = AXI_BEATS_PER_SNF_BLOCK - 1;
    // AXI size field
    localparam [2:0]    AXI_SIZE_VALUE = calc_clog(AXI_BYTES_PER_BEAT);
    localparam [1:0]    AXI_BURST_INCR  = 2'b01;
    localparam [1:0]    AXI_RESP_OKAY   = 2'b00;
    localparam [1:0]    AXI_RESP_EXOKAY = 2'b01;
    localparam [1:0]    AXI_RESP_SLVERR = 2'b10;
    localparam [1:0]    AXI_RESP_DECERR = 2'b11;
    localparam [AXI_BEAT_INDEX_WIDTH-1:0] LAST_AXI_BEAT_INDEX =
        AXI_BEATS_PER_SNF_BLOCK - 1;
    // Read FSM state definition
    localparam [1:0]     READ_STATE_IDLE = 2'b00;
    localparam [1:0]     READ_STATE_SEND_ADDRESS = 2'b01;
    localparam [1:0]     READ_STATE_RECEIVE_DATA = 2'b10;
    localparam [1:0]     READ_STATE_SEND_RESPONSE = 2'b11;
    // timing register
    reg [1:0]                            read_state_q;
    reg [AXI_ID_WIDTH-1:0]               active_read_txn_id_q;
    reg [AXI_ADDR_WIDTH-1:0]             active_read_addr_q;
    reg [AXI_BEAT_INDEX_WIDTH-1:0]           read_beat_index_q;
    reg [SNF_DATA_BLOCK_WIDTH-1:0]           read_data_buffer_q;
    reg [1:0]                            read_response_code_q;
    reg                                  read_protocol_error_q;
    // handshake mechanism
    wire read_request_fire;
    wire axi_ar_fire;
    wire axi_r_fire;
    wire read_response_fire;
    wire expected_read_last_beat;
    assign read_request_fire = read_request_ready_o && read_request_valid_i;
    assign axi_ar_fire = m_axi_ar_ready_i && m_axi_ar_valid_o;
    assign axi_r_fire = m_axi_r_ready_o && m_axi_r_valid_i;
    assign read_response_fire = read_response_ready_i && read_response_valid_o;
    assign expected_read_last_beat = (read_beat_index_q == LAST_AXI_BEAT_INDEX);
    // response of AXI to merge function
    function [1:0] merge_axi_read_response;
        input [1:0] accumulated_resp;
        input [1:0] incoming_resp;
        begin
            if (incoming_resp == AXI_RESP_DECERR)
                merge_axi_read_response = AXI_RESP_DECERR;
            else if ((incoming_resp == AXI_RESP_SLVERR) &&
                     (accumulated_resp != AXI_RESP_DECERR))
                merge_axi_read_response = AXI_RESP_SLVERR;
            else if ((incoming_resp == AXI_RESP_EXOKAY) &&
                     (accumulated_resp == AXI_RESP_OKAY))
                merge_axi_read_response = AXI_RESP_EXOKAY;
            else
                merge_axi_read_response = accumulated_resp;
        end
    endfunction
    // combinitional logic
    assign read_request_ready_o = (read_state_q == READ_STATE_IDLE);

    assign m_axi_ar_id_o     = active_read_txn_id_q;
    assign m_axi_ar_addr_o   = active_read_addr_q;
    assign m_axi_ar_len_o    = AXI_LEN_VALUE;
    assign m_axi_ar_size_o   = AXI_SIZE_VALUE;
    assign m_axi_ar_burst_o  = AXI_BURST_INCR;
    assign m_axi_ar_lock_o   = 1'b0;
    assign m_axi_ar_cache_o  = AXI_CACHE_VALUE;
    assign m_axi_ar_prot_o   = AXI_PROT_VALUE;
    assign m_axi_ar_qos_o    = AXI_QOS_VALUE;
    assign m_axi_ar_region_o = AXI_REGION_VALUE;
    assign m_axi_ar_user_o   = {AXI_ARUSER_WIDTH{1'b0}};
    assign m_axi_ar_valid_o  = (read_state_q == READ_STATE_SEND_ADDRESS);

    assign m_axi_r_ready_o   = (read_state_q == READ_STATE_RECEIVE_DATA);

    assign read_response_valid_o   = (read_state_q == READ_STATE_SEND_RESPONSE);
    assign read_response_txn_id_o = active_read_txn_id_q;
    assign read_response_data_o    = read_data_buffer_q;
    // error recognition
    assign read_response_code_o =
        read_protocol_error_q
        ? ((read_response_code_q == AXI_RESP_DECERR) ? AXI_RESP_DECERR
                                                   : AXI_RESP_SLVERR)
        : read_response_code_q;

    assign read_response_protocol_error_o = read_protocol_error_q;
    // read txnid fsm control
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            read_state_q          <= READ_STATE_IDLE;
            active_read_txn_id_q   <= 0;
            active_read_addr_q     <= 0;
            read_beat_index_q     <= 0;
            read_data_buffer_q    <= 0;
            read_response_code_q   <= AXI_RESP_OKAY;
            read_protocol_error_q <= 1'b0;
        end
        else begin
            case (read_state_q)
                //------------------------------------------------------------------
                // IDLE state -> SEND ADDR
                //------------------------------------------------------------------
                READ_STATE_IDLE: begin
                    if (read_request_fire) begin
                        active_read_txn_id_q   <= read_request_txn_id_i;
                        active_read_addr_q     <= read_request_addr_i;
                        read_beat_index_q     <= 0;
                        read_data_buffer_q    <= 0;
                        read_response_code_q   <= AXI_RESP_OKAY;
                        read_protocol_error_q <= 1'b0;
                        read_state_q          <= READ_STATE_SEND_ADDRESS;
                    end
                end

                //------------------------------------------------------------------
                // SEND ADDR -> READ DATA
                //------------------------------------------------------------------
                READ_STATE_SEND_ADDRESS: begin
                    if (axi_ar_fire) begin
                        read_beat_index_q <= 0;
                        read_state_q      <= READ_STATE_RECEIVE_DATA;
                    end
                end

                //------------------------------------------------------------------
                // RECEIVE DATA
                //------------------------------------------------------------------
                READ_STATE_RECEIVE_DATA: begin
                    if (axi_r_fire) begin
                        read_data_buffer_q[
                            read_beat_index_q * AXI_DATA_WIDTH +: AXI_DATA_WIDTH
                        ] <= m_axi_r_data_i;

                        read_response_code_q <= merge_axi_read_response(
                            read_response_code_q,
                            m_axi_r_resp_i
                        );

                        // RID coherent with ARID
                        if (m_axi_r_id_i != active_read_txn_id_q)
                            read_protocol_error_q <= 1'b1;

                        // last beat set as 1
                        if (m_axi_r_last_i != expected_read_last_beat)
                            read_protocol_error_q <= 1'b1;

                        // according to the RLAST terminate the process
                        if (expected_read_last_beat || m_axi_r_last_i) begin
                            read_state_q <= READ_STATE_SEND_RESPONSE;
                        end
                        else begin
                            read_beat_index_q <= read_beat_index_q + 1'b1;
                        end
                    end
                end

                //------------------------------------------------------------------
                // SN-F inner transform of transit of data
                //------------------------------------------------------------------
                READ_STATE_SEND_RESPONSE: begin
                    if (read_response_fire)
                        read_state_q <= READ_STATE_IDLE;
                end

                default: begin
                    read_state_q          <= READ_STATE_IDLE;
                    read_beat_index_q     <= 0;
                    read_response_code_q   <= AXI_RESP_OKAY;
                    read_protocol_error_q <= 1'b1;
                end
            endcase
        end
    end
`ifndef SYNTHESIS
    //--------------------------------------------------------------------------
    // error check out
    //--------------------------------------------------------------------------
    initial begin
        if ((AXI_DATA_WIDTH % 8) != 0)
            $display("snf_axi_read_burst_engine: AXI_DATA_WIDTH must be byte aligned.");

        if ((SNF_DATA_BLOCK_WIDTH % AXI_DATA_WIDTH) != 0)
            $display("snf_axi_read_burst_engine: SNF_DATA_BLOCK_WIDTH must be divisible by AXI_DATA_WIDTH.");

        if ((AXI_BEATS_PER_SNF_BLOCK < 1) || (AXI_BEATS_PER_SNF_BLOCK > 256))
            $display("snf_axi_read_burst_engine: AXI burst beat count must be 1 to 256.");

        if ((AXI_BYTES_PER_BEAT & (AXI_BYTES_PER_BEAT - 1)) != 0)
            $display("snf_axi_read_burst_engine: AXI bytes per beat must be a power of two.");

        if (AXI_ARUSER_WIDTH < 1)
            $display("snf_axi_read_burst_engine: AXI_ARUSER_WIDTH must be at least 1.");

        if (AXI_RUSER_WIDTH < 1)
            $display("snf_axi_read_burst_engine: AXI_RUSER_WIDTH must be at least 1.");
    end

    // output error
    always @(posedge clk_i) begin
        if (rst_ni && axi_r_fire) begin
            if (m_axi_r_id_i != active_read_txn_id_q)
                $display("snf_axi_read_burst_engine: RID mismatch at time %0t.", $time);

            if (m_axi_r_last_i != expected_read_last_beat)
                $display("snf_axi_read_burst_engine: RLAST position error at time %0t.", $time);
        end
    end
`endif

    // complete axi if
    wire unused_axi_r_user;
    assign unused_axi_r_user = m_axi_r_user_i;
endmodule

module snf_axi_write_burst_engine #(
    parameter integer AXI_ADDR_WIDTH = 40,
    parameter integer AXI_ID_WIDTH = 12,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer SNF_DATA_BLOCK_WIDTH = 512,
    parameter integer AXI_AWUSER_WIDTH = 1,
    parameter integer AXI_WUSER_WIDTH = 1,
    parameter integer AXI_BUSER_WIDTH = 1,
    parameter [3:0] AXI_CACHE_VALUE = 4'b0010,
    parameter [2:0] AXI_PROT_VALUE = 3'b000,
    parameter [3:0] AXI_QOS_VALUE = 4'b0000,
    parameter [3:0] AXI_REGION_VALUE = 4'b0000
)(
    // clk and rst_n
    input       wire        clk_i,
    input       wire        rst_ni,
    // SN-F inner request
    input       wire        write_request_valid_i,
    output      wire        write_request_ready_o,
    input       wire [AXI_ID_WIDTH-1:0]                     write_request_txn_id_i,
    input       wire [AXI_ADDR_WIDTH-1:0]                   write_request_addr_i,
    input       wire [SNF_DATA_BLOCK_WIDTH-1:0]             write_request_data_i,
    input       wire [(SNF_DATA_BLOCK_WIDTH/8)-1:0]         write_request_byte_enable_i,
    // SN inner write response
    output wire                              write_response_valid_o,
    input  wire                              write_response_ready_i,
    output wire [AXI_ID_WIDTH-1:0]           write_response_txn_id_o,
    output wire [1:0]                        write_response_code_o,
    output wire                              write_response_protocol_error_o,
    // AXI AW Channel
    output wire [AXI_ID_WIDTH-1:0]           m_axi_aw_id_o,
    output wire [AXI_ADDR_WIDTH-1:0]         m_axi_aw_addr_o,
    output wire [7:0]                        m_axi_aw_len_o,
    output wire [2:0]                        m_axi_aw_size_o,
    output wire [1:0]                        m_axi_aw_burst_o,
    output wire                              m_axi_aw_lock_o,
    output wire [3:0]                        m_axi_aw_cache_o,
    output wire [2:0]                        m_axi_aw_prot_o,
    output wire [3:0]                        m_axi_aw_qos_o,
    output wire [3:0]                        m_axi_aw_region_o,
    output wire [AXI_AWUSER_WIDTH-1:0]       m_axi_aw_user_o,
    output wire                              m_axi_aw_valid_o,
    input  wire                              m_axi_aw_ready_i,
    // AXI W Channel
    output wire [AXI_DATA_WIDTH-1:0]         m_axi_w_data_o,
    output wire [(AXI_DATA_WIDTH/8)-1:0]     m_axi_w_strb_o,
    output wire                              m_axi_w_last_o,
    output wire [AXI_WUSER_WIDTH-1:0]        m_axi_w_user_o,
    output wire                              m_axi_w_valid_o,
    input  wire                              m_axi_w_ready_i,
    // AXI B Channel
    input  wire [AXI_ID_WIDTH-1:0]           m_axi_b_id_i,
    input  wire [1:0]                        m_axi_b_resp_i,
    input  wire [AXI_BUSER_WIDTH-1:0]        m_axi_b_user_i,
    input  wire                              m_axi_b_valid_i,
    output wire                              m_axi_b_ready_o
);
    function integer calc_clog2;
        input integer value;
        integer temp;
        begin
            temp = value - 1;
            calc_clog2 = 0;
            while (temp > 0) begin
                calc_clog2 = calc_clog2 + 1;
                temp = temp >> 1;
            end
        end
    endfunction
    // inner wire and reg definition
    localparam integer AXI_BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam integer SNF_BYTE_ENABLE_WIDTH    = SNF_DATA_BLOCK_WIDTH / 8;
    localparam integer AXI_BEATS_PER_SNF_BLOCK     = SNF_DATA_BLOCK_WIDTH / AXI_DATA_WIDTH;
    localparam integer AXI_BEAT_INDEX_WIDTH    =
        (AXI_BEATS_PER_SNF_BLOCK <= 1) ? 1 : calc_clog2(AXI_BEATS_PER_SNF_BLOCK);

    localparam [7:0] AXI_LEN_VALUE =
        AXI_BEATS_PER_SNF_BLOCK - 1;

    localparam [2:0] AXI_SIZE_VALUE =
        calc_clog2(AXI_BYTES_PER_BEAT);

    localparam [1:0] AXI_BURST_INCR  = 2'b01;
    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

    localparam [AXI_BEAT_INDEX_WIDTH-1:0] LAST_AXI_BEAT_INDEX =
        AXI_BEATS_PER_SNF_BLOCK - 1;
    // write state definition
    localparam [1:0] WRITE_STATE_IDLE  = 2'b00;
    localparam [1:0] WRITE_STATE_SEND_ADDRESS_DATA  = 2'b01;
    localparam [1:0] WRITE_STATE_WAIT_B_RESPONSE = 2'b10;
    localparam [1:0] WRITE_STATE_SEND_RESPONSE  = 2'b11;
    // timing register
    reg [1:0]                               write_state_q;

    reg [AXI_ID_WIDTH-1:0]                active_write_txn_id_q;
    reg [AXI_ADDR_WIDTH-1:0]              active_write_addr_q;
    reg [SNF_DATA_BLOCK_WIDTH-1:0]            active_write_data_q;
    reg [SNF_BYTE_ENABLE_WIDTH-1:0]          active_write_byte_enable_q;

    reg [AXI_BEAT_INDEX_WIDTH-1:0]            write_beat_index_q;
    reg                                   axi_aw_pending_q;
    reg                                   axi_w_pending_q;

    reg [1:0]                             write_response_code_q;
    reg                                   write_protocol_error_q;
    // Handshake Event and Completion Judgment
    wire write_request_fire;
    wire axi_aw_fire;
    wire axi_w_fire;
    wire axi_b_fire;
    wire write_response_fire;
    wire current_axi_w_is_last;
    wire axi_aw_complete_now;
    wire axi_w_complete_now;
    assign write_request_fire   = write_request_valid_i && write_request_ready_o;
    assign axi_aw_fire           = m_axi_aw_valid_o && m_axi_aw_ready_i;
    assign axi_w_fire            = m_axi_w_valid_o && m_axi_w_ready_i;
    assign axi_b_fire            = m_axi_b_valid_i && m_axi_b_ready_o;
    assign write_response_fire = write_response_valid_o && write_response_ready_i;
    assign current_axi_w_is_last = (write_beat_index_q == LAST_AXI_BEAT_INDEX);
    // the completion of axi_aw_complete_i and axi_w_complete_i
    assign axi_aw_complete_now =
        (write_state_q == WRITE_STATE_SEND_ADDRESS_DATA) &&
        ((!axi_aw_pending_q) || axi_aw_fire);
    assign axi_w_complete_now =
        (write_state_q == WRITE_STATE_SEND_ADDRESS_DATA) &&
        ((!axi_w_pending_q) || (axi_w_fire && current_axi_w_is_last));
    // Permutations output
    assign write_request_ready_o = (write_state_q == WRITE_STATE_IDLE);

    assign m_axi_aw_id_o     = active_write_txn_id_q;
    assign m_axi_aw_addr_o   = active_write_addr_q;
    assign m_axi_aw_len_o    = AXI_LEN_VALUE;
    assign m_axi_aw_size_o   = AXI_SIZE_VALUE;
    assign m_axi_aw_burst_o  = AXI_BURST_INCR;
    assign m_axi_aw_lock_o   = 1'b0;
    assign m_axi_aw_cache_o  = AXI_CACHE_VALUE;
    assign m_axi_aw_prot_o   = AXI_PROT_VALUE;
    assign m_axi_aw_qos_o    = AXI_QOS_VALUE;
    assign m_axi_aw_region_o = AXI_REGION_VALUE;
    assign m_axi_aw_user_o   = {AXI_AWUSER_WIDTH{1'b0}};
    assign m_axi_aw_valid_o  =
        (write_state_q == WRITE_STATE_SEND_ADDRESS_DATA) && axi_aw_pending_q;
    assign m_axi_w_data_o =
        active_write_data_q[
            write_beat_index_q * AXI_DATA_WIDTH +: AXI_DATA_WIDTH
        ];

    assign m_axi_w_strb_o =
        active_write_byte_enable_q[
            write_beat_index_q * AXI_BYTES_PER_BEAT +: AXI_BYTES_PER_BEAT
        ];

    assign m_axi_w_last_o  = current_axi_w_is_last;
    assign m_axi_w_user_o  = {AXI_WUSER_WIDTH{1'b0}};
    assign m_axi_w_valid_o =
        (write_state_q == WRITE_STATE_SEND_ADDRESS_DATA) && axi_w_pending_q;

    assign m_axi_b_ready_o = (write_state_q == WRITE_STATE_WAIT_B_RESPONSE);

    assign write_response_valid_o = (write_state_q == WRITE_STATE_SEND_RESPONSE);
    assign write_response_txn_id_o = active_write_txn_id_q;
    assign write_response_code_o =
        write_protocol_error_q
        ? ((write_response_code_q == AXI_RESP_DECERR) ? AXI_RESP_DECERR
                                                   : AXI_RESP_SLVERR)
        : write_response_code_q;

    assign write_response_protocol_error_o = write_protocol_error_q;
    // write txn assign
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // initiallization
            write_state_q          <= WRITE_STATE_IDLE;
            active_write_txn_id_q       <= 0;
            active_write_addr_q         <= 0;
            active_write_data_q         <= 0;
            active_write_byte_enable_q  <= 0;
            write_beat_index_q           <= 0;
            axi_aw_pending_q            <= 1'b0;
            axi_w_pending_q             <= 1'b0;
            write_response_code_q  <= AXI_RESP_OKAY;
            write_protocol_error_q      <= 1'b0;
        end
        else begin
            case (write_state_q)
                //------------------------------------------------------------------
                // IDLE STATE
                //------------------------------------------------------------------
                WRITE_STATE_IDLE: begin
                    if (write_request_fire) begin
                        active_write_txn_id_q      <= write_request_txn_id_i;
                        active_write_addr_q        <= write_request_addr_i;
                        active_write_data_q        <= write_request_data_i;
                        active_write_byte_enable_q <= write_request_byte_enable_i;
                        write_beat_index_q           <= 0;
                        axi_aw_pending_q           <= 1'b1;
                        axi_w_pending_q            <= 1'b1;
                        write_response_code_q  <= AXI_RESP_OKAY;
                        write_protocol_error_q      <= 1'b0;
                        write_state_q          <= WRITE_STATE_SEND_ADDRESS_DATA;
                    end
                end

                //------------------------------------------------------------------
                // SEND_ADDRESS_DATA STATE
                //------------------------------------------------------------------
                WRITE_STATE_SEND_ADDRESS_DATA: begin
                    if (axi_aw_fire)
                        axi_aw_pending_q <= 1'b0;

                    if (axi_w_fire) begin
                        if (current_axi_w_is_last) begin
                            axi_w_pending_q <= 1'b0;
                        end
                        else begin
                            write_beat_index_q <= write_beat_index_q + 1'b1;
                        end
                    end

                    // AW and W channel parallel run and wait the r channel response
                    if (axi_aw_complete_now && axi_w_complete_now)
                        write_state_q <= WRITE_STATE_WAIT_B_RESPONSE;
                end

                //------------------------------------------------------------------
                // B RESPONSE CHANNEL
                //------------------------------------------------------------------
                WRITE_STATE_WAIT_B_RESPONSE: begin
                    if (axi_b_fire) begin
                        write_response_code_q    <= m_axi_b_resp_i;

                        if (m_axi_b_id_i != active_write_txn_id_q)
                            write_protocol_error_q <= 1'b1;

                        write_state_q <= WRITE_STATE_SEND_RESPONSE;
                    end
                end

                //------------------------------------------------------------------
                // SEND_RESPONSE STATE
                //------------------------------------------------------------------
                WRITE_STATE_SEND_RESPONSE: begin
                    if (write_response_fire)
                        write_state_q <= WRITE_STATE_IDLE;
                end

                default: begin
                    write_state_q          <= WRITE_STATE_IDLE;
                    axi_aw_pending_q            <= 1'b0;
                    axi_w_pending_q             <= 1'b0;
                    write_beat_index_q           <= 0;
                    write_protocol_error_q <= 1'b1;
                end
            endcase
        end
    end
// error output
`ifndef SYNTHESIS
    //--------------------------------------------------------------------------
    // $display the error kinds
    //--------------------------------------------------------------------------
    initial begin
        if ((AXI_DATA_WIDTH % 8) != 0)
            $display("snf_axi_write_burst_engine: AXI_DATA_WIDTH must be byte aligned.");

        if ((SNF_DATA_BLOCK_WIDTH % AXI_DATA_WIDTH) != 0)
            $display("snf_axi_write_burst_engine: SNF_DATA_BLOCK_WIDTH must be divisible by AXI_DATA_WIDTH.");

        if ((AXI_BEATS_PER_SNF_BLOCK < 1) || (AXI_BEATS_PER_SNF_BLOCK > 256))
            $display("snf_axi_write_burst_engine: AXI burst beat count must be 1 to 256.");

        if ((AXI_BYTES_PER_BEAT & (AXI_BYTES_PER_BEAT - 1)) != 0)
            $display("snf_axi_write_burst_engine: AXI bytes per beat must be a power of two.");

        if (AXI_AWUSER_WIDTH < 1)
            $display("snf_axi_write_burst_engine: AXI_AWUSER_WIDTH must be at least 1.");

        if (AXI_WUSER_WIDTH < 1)
            $display("snf_axi_write_burst_engine: AXI_WUSER_WIDTH must be at least 1.");

        if (AXI_BUSER_WIDTH < 1)
            $display("snf_axi_write_burst_engine: AXI_BUSER_WIDTH must be at least 1.");
    end

    // accordence the aw with w
    always @(posedge clk_i) begin
        if (rst_ni && axi_b_fire) begin
            if (m_axi_b_id_i != active_write_txn_id_q)
                $display("snf_axi_write_burst_engine: BID mismatch at time %0t.", $time);
        end
    end
`endif

    // BUSER PORT RETAIN
    wire unused_axi_b_user;
    assign unused_axi_b_user = ^m_axi_b_user_i;
endmodule

module AXI_Master #(
    parameter integer AXI_ARUSER_WIDTH = 1,
    parameter integer AXI_RUSER_WIDTH  = 1,
    parameter integer AXI_AWUSER_WIDTH = 1,
    parameter integer AXI_WUSER_WIDTH  = 1,
    parameter integer AXI_BUSER_WIDTH  = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         rr_axi_valid,
    output wire                         axi_rr_ready,
    input  wire [51:0]                  rr_axi_datout,

    // old data return port
    output wire                         tx_dat_valid,
    input  wire                         tx_dat_ready,
    output wire [511:0]                 AXI2TD_Data,
    output wire [11:0]                  AXI2TD_id,

    // wr request port
    output wire                         AXI_RxDat_ready,
    input  wire                         RxDat_AXI_valid,
    input  wire [63:0]                  BE_NCBWData,
    input  wire [511:0]                 DATA_NCBWData,
    input  wire [39:0]                  addr2AXI,
    input  wire [11:0]                  TxnID_NCBWData,

    // AXI AR channel
    output wire                         ar_valid,
    input  wire                         ar_ready,
    output wire [11:0]                  ar_id,
    output wire [39:0]                  ar_addr,
    output wire [7:0]                   ar_len,
    output wire [2:0]                   ar_size,
    output wire [1:0]                   ar_burst,
    output wire                         ar_lock,
    output wire [3:0]                   ar_cache,
    output wire [2:0]                   ar_prot,
    output wire [3:0]                   ar_qos,
    output wire [3:0]                   ar_region,
    output wire [AXI_ARUSER_WIDTH-1:0] ar_user,

    // AXI R channel
    input  wire [11:0]                  r_id,
    input  wire [127:0]                 r_data,
    input  wire [1:0]                   r_resp,
    input  wire                         r_last,
    input  wire [AXI_RUSER_WIDTH-1:0]  r_user,
    input  wire                         r_valid,
    output wire                         r_ready,

    // AXI AW channel
    output wire [11:0]                  aw_id,
    output wire [39:0]                  aw_addr,
    output wire [7:0]                   aw_len,
    output wire [2:0]                   aw_size,
    output wire [1:0]                   aw_burst,
    output wire                         aw_lock,
    output wire [3:0]                   aw_cache,
    output wire [2:0]                   aw_prot,
    output wire [3:0]                   aw_qos,
    output wire [3:0]                   aw_region,
    output wire [AXI_AWUSER_WIDTH-1:0] aw_user,
    output wire                         aw_valid,
    input  wire                         aw_ready,

    // AXI W channel
    output wire [127:0]                 w_data,
    output wire [15:0]                  w_strb,
    output wire                         w_last,
    output wire [AXI_WUSER_WIDTH-1:0]  w_user,
    output wire                         w_valid,
    input  wire                         w_ready,

    // AXI B channel，BID width 7 bit
    // Legacy memory model returns only the low seven BID bits.  The wrapper
    // restores the upper bits from the single outstanding write context.
    input  wire [6:0]                   b_id,
    input  wire [1:0]                   b_resp,
    input  wire [AXI_BUSER_WIDTH-1:0]  b_user,
    input  wire                         b_valid,
    output wire                         b_ready,

    // reback of r
    output wire [7:0]                   AXItoRxReq_b_resp,
    output wire [15:0]                  TxnID_valid_bCh,
    // Modify by Michael Tan，20261015: expose AXI response status across compatibility wrapper.
    output wire [1:0] read_status_o,
    output wire write_error_o,
    // Modify by Michael Tan，20261015: report completed write ID, independent of next collector payload.
    output wire [11:0] write_error_id_o
);

    //--------------------------------------------------------------------------
    // 旧接口到新接口的读请求字段拆分
    //--------------------------------------------------------------------------
    wire [11:0] legacy_read_request_txn_id;
    wire [39:0] legacy_read_request_addr;

    assign legacy_read_request_txn_id = rr_axi_datout[11:0];
    assign legacy_read_request_addr = rr_axi_datout[51:12];

    //--------------------------------------------------------------------------
    // 新版响应接口内部信号
    //--------------------------------------------------------------------------
    wire [1:0]  legacy_read_response_code;
    wire        legacy_read_response_protocol_error;

    wire        legacy_write_response_valid;
    wire [11:0] legacy_write_response_txn_id;
    wire [1:0]  legacy_write_response_code;
    wire        legacy_write_response_protocol_error;

    // 旧接口没有write response ready，始终允许新版响应被接收。
    wire legacy_write_response_ready;
    assign legacy_write_response_ready = 1'b1;

    //--------------------------------------------------------------------------
    // 旧BID重建
    //
    // 由于每次仅允许一笔未完成写事务，可安全使用当前写事务ID的高5位。
    // 低7位仍来自外部BID，以保留低位不匹配检查能力。
    //--------------------------------------------------------------------------
    reg [11:0] legacy_active_write_txn_id_q;
    wire [11:0] legacy_full_write_response_id;
    wire        legacy_write_request_fire;
    wire        legacy_write_response_fire;

    assign legacy_full_write_response_id = {legacy_active_write_txn_id_q[11:7], b_id};
    assign legacy_write_request_fire = RxDat_AXI_valid && AXI_RxDat_ready;
    assign legacy_write_response_fire = legacy_write_response_valid && legacy_write_response_ready;

    //--------------------------------------------------------------------------
    // 旧版等待B响应表
    //
    // 原设计只输出16项状态，因此仍使用TxnID低4位作为索引。
    // 该状态表仅用于兼容旧上层逻辑，不参与新版写引擎的事务控制。
    //--------------------------------------------------------------------------
    // legacy_write_txn_pending_q：兼容旧接口的16项写事务等待状态。
    reg [15:0] legacy_write_txn_pending_q;

    assign TxnID_valid_bCh = legacy_write_txn_pending_q;

    // 旧响应格式为{单周期有效位, 7 bit事务ID}。
    assign AXItoRxReq_b_resp = {
        legacy_write_response_valid,
        legacy_write_response_txn_id[6:0]
    };

    //--------------------------------------------------------------------------
    // 兼容层状态寄存器
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            legacy_active_write_txn_id_q <= 0;
            legacy_write_txn_pending_q    <= 0;
        end
        else begin
            if (legacy_write_request_fire) begin
                legacy_active_write_txn_id_q <= TxnID_NCBWData;
                legacy_write_txn_pending_q[TxnID_NCBWData[3:0]] <= 1'b1;
            end

            if (legacy_write_response_fire)
                legacy_write_txn_pending_q[legacy_write_response_txn_id[3:0]] <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // 实例化重构后的标准顶层模块
    //--------------------------------------------------------------------------
    snf_axi_master #(
        .AXI_ADDR_WIDTH      (40),
        .AXI_ID_WIDTH        (12),
        .AXI_DATA_WIDTH      (128),
        .SNF_DATA_BLOCK_WIDTH    (512),
        .AXI_ARUSER_WIDTH    (AXI_ARUSER_WIDTH),
        .AXI_RUSER_WIDTH     (AXI_RUSER_WIDTH),
        .AXI_AWUSER_WIDTH    (AXI_AWUSER_WIDTH),
        .AXI_WUSER_WIDTH     (AXI_WUSER_WIDTH),
        .AXI_BUSER_WIDTH     (AXI_BUSER_WIDTH)
    ) u_snf_axi_master (
        .clk_i                   (clk),
        .rst_ni                 (rst_n),

        .read_request_valid_i          (rr_axi_valid),
        .read_request_ready_o          (axi_rr_ready),
        .read_request_txn_id_i             (legacy_read_request_txn_id),
        .read_request_addr_i           (legacy_read_request_addr),

        .read_response_valid_o          (tx_dat_valid),
        .read_response_ready_i          (tx_dat_ready),
        .read_response_txn_id_o             (AXI2TD_id),
        .read_response_data_o           (AXI2TD_Data),
        .read_response_code_o           (legacy_read_response_code),
        .read_response_protocol_error_o (legacy_read_response_protocol_error),

        .write_request_valid_i          (RxDat_AXI_valid),
        .write_request_ready_o          (AXI_RxDat_ready),
        .write_request_txn_id_i             (TxnID_NCBWData),
        .write_request_addr_i           (addr2AXI),
        .write_request_data_i           (DATA_NCBWData),
        .write_request_byte_enable_i           (BE_NCBWData),

        .write_response_valid_o          (legacy_write_response_valid),
        .write_response_ready_i          (legacy_write_response_ready),
        .write_response_txn_id_o             (legacy_write_response_txn_id),
        .write_response_code_o           (legacy_write_response_code),
        .write_response_protocol_error_o (legacy_write_response_protocol_error),

        .m_axi_ar_id_o            (ar_id),
        .m_axi_ar_addr_o          (ar_addr),
        .m_axi_ar_len_o           (ar_len),
        .m_axi_ar_size_o          (ar_size),
        .m_axi_ar_burst_o         (ar_burst),
        .m_axi_ar_lock_o          (ar_lock),
        .m_axi_ar_cache_o         (ar_cache),
        .m_axi_ar_prot_o          (ar_prot),
        .m_axi_ar_qos_o           (ar_qos),
        .m_axi_ar_region_o        (ar_region),
        .m_axi_ar_user_o          (ar_user),
        .m_axi_ar_valid_o         (ar_valid),
        .m_axi_ar_ready_i         (ar_ready),

        .m_axi_r_id_i             (r_id),
        .m_axi_r_data_i           (r_data),
        .m_axi_r_resp_i           (r_resp),
        .m_axi_r_last_i           (r_last),
        .m_axi_r_user_i           (r_user),
        .m_axi_r_valid_i          (r_valid),
        .m_axi_r_ready_o          (r_ready),

        .m_axi_aw_id_o            (aw_id),
        .m_axi_aw_addr_o          (aw_addr),
        .m_axi_aw_len_o           (aw_len),
        .m_axi_aw_size_o          (aw_size),
        .m_axi_aw_burst_o         (aw_burst),
        .m_axi_aw_lock_o          (aw_lock),
        .m_axi_aw_cache_o         (aw_cache),
        .m_axi_aw_prot_o          (aw_prot),
        .m_axi_aw_qos_o           (aw_qos),
        .m_axi_aw_region_o        (aw_region),
        .m_axi_aw_user_o          (aw_user),
        .m_axi_aw_valid_o         (aw_valid),
        .m_axi_aw_ready_i         (aw_ready),

        .m_axi_w_data_o           (w_data),
        .m_axi_w_strb_o           (w_strb),
        .m_axi_w_last_o           (w_last),
        .m_axi_w_user_o           (w_user),
        .m_axi_w_valid_o          (w_valid),
        .m_axi_w_ready_i          (w_ready),

        .m_axi_b_id_i             (legacy_full_write_response_id),
        .m_axi_b_resp_i           (b_resp),
        .m_axi_b_user_i           (b_user),
        .m_axi_b_valid_i          (b_valid),
        .m_axi_b_ready_o          (b_ready)
    );

    //--------------------------------------------------------------------------
    // 旧接口未输出的新版错误信息在此做归约，避免部分工具报告未使用。
    //--------------------------------------------------------------------------
    assign read_status_o = legacy_read_response_code;
    assign write_error_id_o = legacy_write_response_txn_id;
    assign write_error_o = legacy_write_response_valid &&
        (legacy_write_response_protocol_error || legacy_write_response_code[1]);
    wire unused_new_status;
    assign unused_new_status =
        (^legacy_read_response_code)           ^
        legacy_read_response_protocol_error    ^
        (^legacy_write_response_code)           ^
        legacy_write_response_protocol_error;

endmodule

`default_nettype wire

// Compatibility integration wrapper.  Its public interface follows the same
// *_i/*_o direction rule used by SN_Top_new and the CHI channel wrappers.
`default_nettype none
module SNF_AXI_Master_new #(
    parameter integer AXI_ARUSER_WIDTH = 1,
    parameter integer AXI_RUSER_WIDTH  = 1,
    parameter integer AXI_AWUSER_WIDTH = 1,
    parameter integer AXI_WUSER_WIDTH  = 1,
    parameter integer AXI_BUSER_WIDTH  = 1
)(
    input  wire                         clk_i,
    input  wire                         rst_ni,

    input  wire                         read_request_valid_i,
    output wire                         read_request_ready_o,
    input  wire [51:0]                  read_request_i,
    output wire                         read_data_valid_o,
    input  wire                         read_data_ready_i,
    output wire [511:0]                 read_data_o,
    output wire [11:0]                  read_id_o,

    output wire                         write_request_ready_o,
    input  wire                         write_request_valid_i,
    input  wire [63:0]                  write_strb_i,
    input  wire [511:0]                 write_data_i,
    input  wire [39:0]                  write_addr_i,
    input  wire [11:0]                  write_id_i,

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
    output wire [AXI_ARUSER_WIDTH-1:0]  m_axi_aruser_o,
    output wire                         m_axi_arvalid_o,
    input  wire                         m_axi_arready_i,

    input  wire [11:0]                  m_axi_rid_i,
    input  wire [127:0]                 m_axi_rdata_i,
    input  wire [1:0]                   m_axi_rresp_i,
    input  wire                         m_axi_rlast_i,
    input  wire [AXI_RUSER_WIDTH-1:0]   m_axi_ruser_i,
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
    output wire [AXI_AWUSER_WIDTH-1:0]  m_axi_awuser_o,
    output wire                         m_axi_awvalid_o,
    input  wire                         m_axi_awready_i,

    output wire [127:0]                 m_axi_wdata_o,
    output wire [15:0]                  m_axi_wstrb_o,
    output wire                         m_axi_wlast_o,
    output wire [AXI_WUSER_WIDTH-1:0]   m_axi_wuser_o,
    output wire                         m_axi_wvalid_o,
    input  wire                         m_axi_wready_i,

    input  wire [6:0]                   m_axi_bid_i,
    input  wire [1:0]                   m_axi_bresp_i,
    input  wire [AXI_BUSER_WIDTH-1:0]   m_axi_buser_i,
    input  wire                         m_axi_bvalid_i,
    output wire                         m_axi_bready_o,

    output wire [7:0]                   write_completion_o,
    output wire [15:0]                  write_pending_o,
    // Modify by Michael Tan，20261015: exported transaction status for SN error reporting.
    output wire [1:0] read_status_o,
    output wire write_error_o,
    // Modify by Michael Tan，20261015: expose stable completion identity.
    output wire [11:0] write_error_id_o
);
    AXI_Master #(
        .AXI_ARUSER_WIDTH (AXI_ARUSER_WIDTH),
        .AXI_RUSER_WIDTH  (AXI_RUSER_WIDTH),
        .AXI_AWUSER_WIDTH (AXI_AWUSER_WIDTH),
        .AXI_WUSER_WIDTH  (AXI_WUSER_WIDTH),
        .AXI_BUSER_WIDTH  (AXI_BUSER_WIDTH)
    ) u_legacy_core (
        .clk                 (clk_i),
        .rst_n               (rst_ni),
        .rr_axi_valid        (read_request_valid_i),
        .axi_rr_ready        (read_request_ready_o),
        .rr_axi_datout       (read_request_i),
        .tx_dat_valid        (read_data_valid_o),
        .tx_dat_ready        (read_data_ready_i),
        .AXI2TD_Data         (read_data_o),
        .AXI2TD_id           (read_id_o),
        .AXI_RxDat_ready     (write_request_ready_o),
        .RxDat_AXI_valid     (write_request_valid_i),
        .BE_NCBWData         (write_strb_i),
        .DATA_NCBWData       (write_data_i),
        .addr2AXI            (write_addr_i),
        .TxnID_NCBWData      (write_id_i),
        .ar_valid            (m_axi_arvalid_o),
        .ar_ready            (m_axi_arready_i),
        .ar_id               (m_axi_arid_o),
        .ar_addr             (m_axi_araddr_o),
        .ar_len              (m_axi_arlen_o),
        .ar_size             (m_axi_arsize_o),
        .ar_burst            (m_axi_arburst_o),
        .ar_lock             (m_axi_arlock_o),
        .ar_cache            (m_axi_arcache_o),
        .ar_prot             (m_axi_arprot_o),
        .ar_qos              (m_axi_arqos_o),
        .ar_region           (m_axi_arregion_o),
        .ar_user             (m_axi_aruser_o),
        .r_id                (m_axi_rid_i),
        .r_data              (m_axi_rdata_i),
        .r_resp              (m_axi_rresp_i),
        .r_last              (m_axi_rlast_i),
        .r_user              (m_axi_ruser_i),
        .r_valid             (m_axi_rvalid_i),
        .r_ready             (m_axi_rready_o),
        .aw_id               (m_axi_awid_o),
        .aw_addr             (m_axi_awaddr_o),
        .aw_len              (m_axi_awlen_o),
        .aw_size             (m_axi_awsize_o),
        .aw_burst            (m_axi_awburst_o),
        .aw_lock             (m_axi_awlock_o),
        .aw_cache            (m_axi_awcache_o),
        .aw_prot             (m_axi_awprot_o),
        .aw_qos              (m_axi_awqos_o),
        .aw_region           (m_axi_awregion_o),
        .aw_user             (m_axi_awuser_o),
        .aw_valid            (m_axi_awvalid_o),
        .aw_ready            (m_axi_awready_i),
        .w_data              (m_axi_wdata_o),
        .w_strb              (m_axi_wstrb_o),
        .w_last              (m_axi_wlast_o),
        .w_user              (m_axi_wuser_o),
        .w_valid             (m_axi_wvalid_o),
        .w_ready             (m_axi_wready_i),
        .b_id                (m_axi_bid_i),
        .b_resp              (m_axi_bresp_i),
        .b_user              (m_axi_buser_i),
        .b_valid             (m_axi_bvalid_i),
        .b_ready             (m_axi_bready_o),
        .AXItoRxReq_b_resp   (write_completion_o),
        .TxnID_valid_bCh     (write_pending_o),
        // Modify by Michael Tan，20261015: retain status rather than discard it.
        .read_status_o (read_status_o),
        .write_error_o (write_error_o),
        .write_error_id_o (write_error_id_o)
    );
endmodule
`default_nettype wire
