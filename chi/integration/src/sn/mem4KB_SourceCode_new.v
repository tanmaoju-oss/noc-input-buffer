`timescale 1ns/1ps
`default_nettype none

// 4 KiB AXI4 memory model for SN_Top_new simulation.
// - 128-bit AXI data bus (16 bytes per beat)
// - 64-byte cache lines, four beats per full-line transfer
// - one outstanding read and one outstanding write transaction
// - byte write enable support through WSTRB
// - low seven BID bits match the legacy memory interface of SN_Top_new
module mem4KB_new #(
    parameter integer AXI_ADDR_WIDTH   = 40,
    parameter integer AXI_ID_WIDTH     = 12,
    parameter integer AXI_DATA_WIDTH   = 128,
    parameter integer AXI_AWUSER_WIDTH = 1,
    parameter integer AXI_WUSER_WIDTH  = 1,
    parameter integer AXI_BUSER_WIDTH  = 1,
    parameter integer AXI_ARUSER_WIDTH = 1,
    parameter integer AXI_RUSER_WIDTH  = 1
)(
    input  wire                            clk_i,
    input  wire                            rst_ni,

    input  wire [AXI_ID_WIDTH-1:0]         s_axi_awid_i,
    input  wire [AXI_ADDR_WIDTH-1:0]       s_axi_awaddr_i,
    input  wire [7:0]                      s_axi_awlen_i,
    input  wire [2:0]                      s_axi_awsize_i,
    input  wire [1:0]                      s_axi_awburst_i,
    input  wire                            s_axi_awlock_i,
    input  wire [3:0]                      s_axi_awcache_i,
    input  wire [2:0]                      s_axi_awprot_i,
    input  wire [3:0]                      s_axi_awqos_i,
    input  wire [3:0]                      s_axi_awregion_i,
    input  wire [AXI_AWUSER_WIDTH-1:0]     s_axi_awuser_i,
    input  wire                            s_axi_awvalid_i,
    output wire                            s_axi_awready_o,

    input  wire [AXI_DATA_WIDTH-1:0]       s_axi_wdata_i,
    input  wire [(AXI_DATA_WIDTH/8)-1:0]   s_axi_wstrb_i,
    input  wire                            s_axi_wlast_i,
    input  wire [AXI_WUSER_WIDTH-1:0]      s_axi_wuser_i,
    input  wire                            s_axi_wvalid_i,
    output wire                            s_axi_wready_o,

    output wire [6:0]                      s_axi_bid_o,
    output wire [1:0]                      s_axi_bresp_o,
    output wire [AXI_BUSER_WIDTH-1:0]      s_axi_buser_o,
    output wire                            s_axi_bvalid_o,
    input  wire                            s_axi_bready_i,

    input  wire [AXI_ID_WIDTH-1:0]         s_axi_arid_i,
    input  wire [AXI_ADDR_WIDTH-1:0]       s_axi_araddr_i,
    input  wire [7:0]                      s_axi_arlen_i,
    input  wire [2:0]                      s_axi_arsize_i,
    input  wire [1:0]                      s_axi_arburst_i,
    input  wire                            s_axi_arlock_i,
    input  wire [3:0]                      s_axi_arcache_i,
    input  wire [2:0]                      s_axi_arprot_i,
    input  wire [3:0]                      s_axi_arqos_i,
    input  wire [3:0]                      s_axi_arregion_i,
    input  wire [AXI_ARUSER_WIDTH-1:0]     s_axi_aruser_i,
    input  wire                            s_axi_arvalid_i,
    output wire                            s_axi_arready_o,

    output wire [AXI_ID_WIDTH-1:0]         s_axi_rid_o,
    output wire [AXI_DATA_WIDTH-1:0]       s_axi_rdata_o,
    output wire [1:0]                      s_axi_rresp_o,
    output wire                            s_axi_rlast_o,
    output wire [AXI_RUSER_WIDTH-1:0]      s_axi_ruser_o,
    output wire                            s_axi_rvalid_o,
    input  wire                            s_axi_rready_i
);
    localparam integer AXI_BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam [2:0] AXI_SIZE_16_BYTES = 3'd4;
    localparam [1:0] AXI_BURST_INCR = 2'b01;
    localparam [1:0] AXI_RESP_OKAY = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;

    reg [511:0] memory_q [0:63];
    integer reset_index;
    integer byte_index;

    reg         write_active_q;
    reg [5:0]   write_line_index_q;
    reg [AXI_ID_WIDTH-1:0] write_id_q;
    reg [7:0]   write_len_q;
    reg [7:0]   write_beat_q;
    reg         write_error_q;
    reg         write_response_valid_q;
    reg [1:0]   write_response_q;

    wire write_address_fire = s_axi_awvalid_i && s_axi_awready_o;
    wire write_data_fire = s_axi_wvalid_i && s_axi_wready_o;
    wire write_response_fire = s_axi_bvalid_o && s_axi_bready_i;
    wire write_last_expected = (write_beat_q == write_len_q);

    assign s_axi_awready_o = rst_ni && !write_active_q && !write_response_valid_q;
    assign s_axi_wready_o  = rst_ni && write_active_q;
    assign s_axi_bid_o     = write_id_q[6:0];
    assign s_axi_bresp_o   = write_response_q;
    assign s_axi_buser_o   = {AXI_BUSER_WIDTH{1'b0}};
    assign s_axi_bvalid_o  = write_response_valid_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            write_active_q         <= 1'b0;
            write_line_index_q     <= 6'b0;
            write_id_q             <= {AXI_ID_WIDTH{1'b0}};
            write_len_q            <= 8'b0;
            write_beat_q           <= 8'b0;
            write_error_q          <= 1'b0;
            write_response_valid_q <= 1'b0;
            write_response_q       <= AXI_RESP_OKAY;
            for (reset_index = 0; reset_index < 64; reset_index = reset_index + 1)
                memory_q[reset_index] <= 512'b0;
        end else begin
            if (write_response_fire)
                write_response_valid_q <= 1'b0;

            if (write_address_fire) begin
                write_active_q     <= 1'b1;
                write_line_index_q <= s_axi_awaddr_i[11:6];
                write_id_q         <= s_axi_awid_i;
                write_len_q        <= s_axi_awlen_i;
                write_beat_q       <= 8'b0;
                write_error_q      <= (s_axi_awsize_i != AXI_SIZE_16_BYTES) ||
                                      (s_axi_awburst_i != AXI_BURST_INCR) ||
                                      (s_axi_awlen_i > 8'd3) ||
                                      (s_axi_awaddr_i[5:0] != 6'b0);
            end

            if (write_data_fire) begin
                if (!write_error_q && (write_beat_q < 8'd4)) begin
                    for (byte_index = 0; byte_index < AXI_BYTES_PER_BEAT;
                         byte_index = byte_index + 1) begin
                        if (s_axi_wstrb_i[byte_index])
                            memory_q[write_line_index_q]
                                [(write_beat_q*AXI_DATA_WIDTH)+(byte_index*8)+:8]
                                <= s_axi_wdata_i[(byte_index*8)+:8];
                    end
                end

                if (s_axi_wlast_i || write_last_expected) begin
                    write_active_q         <= 1'b0;
                    write_response_valid_q <= 1'b1;
                    write_response_q       <=
                        (write_error_q || (s_axi_wlast_i != write_last_expected)) ?
                        AXI_RESP_SLVERR : AXI_RESP_OKAY;
                    write_beat_q <= 8'b0;
                end else begin
                    write_beat_q <= write_beat_q + 8'd1;
                end
            end
        end
    end

    reg                            read_active_q;
    reg [5:0]                      read_line_index_q;
    reg [AXI_ID_WIDTH-1:0]         read_id_q;
    reg [7:0]                      read_len_q;
    reg [7:0]                      read_beat_q;
    reg [1:0]                      read_response_q;
    reg [AXI_RUSER_WIDTH-1:0]      read_user_q;

    wire read_address_fire = s_axi_arvalid_i && s_axi_arready_o;
    wire read_data_fire = s_axi_rvalid_o && s_axi_rready_i;

    assign s_axi_arready_o = rst_ni && !read_active_q;
    assign s_axi_rid_o     = read_id_q;
    assign s_axi_rdata_o   = memory_q[read_line_index_q]
                                      [(read_beat_q*AXI_DATA_WIDTH)+:AXI_DATA_WIDTH];
    assign s_axi_rresp_o   = read_response_q;
    assign s_axi_rlast_o   = read_active_q && (read_beat_q == read_len_q);
    assign s_axi_ruser_o   = read_user_q;
    assign s_axi_rvalid_o  = read_active_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            read_active_q     <= 1'b0;
            read_line_index_q <= 6'b0;
            read_id_q         <= {AXI_ID_WIDTH{1'b0}};
            read_len_q        <= 8'b0;
            read_beat_q       <= 8'b0;
            read_response_q   <= AXI_RESP_OKAY;
            read_user_q       <= {AXI_RUSER_WIDTH{1'b0}};
        end else begin
            if (read_address_fire) begin
                read_active_q     <= 1'b1;
                read_line_index_q <= s_axi_araddr_i[11:6];
                read_id_q         <= s_axi_arid_i;
                read_len_q        <= (s_axi_arlen_i > 8'd3) ? 8'd3 : s_axi_arlen_i;
                read_beat_q       <= 8'b0;
                read_user_q       <= s_axi_aruser_i;
                read_response_q   <=
                    ((s_axi_arsize_i != AXI_SIZE_16_BYTES) ||
                     (s_axi_arburst_i != AXI_BURST_INCR) ||
                     (s_axi_arlen_i > 8'd3) ||
                     (s_axi_araddr_i[5:0] != 6'b0)) ?
                    AXI_RESP_SLVERR : AXI_RESP_OKAY;
            end else if (read_data_fire) begin
                if (s_axi_rlast_o) begin
                    read_active_q <= 1'b0;
                    read_beat_q   <= 8'b0;
                end else begin
                    read_beat_q <= read_beat_q + 8'd1;
                end
            end
        end
    end

    // Attributes accepted for AXI compatibility but not used by this RAM.
    wire unused_attributes = s_axi_awlock_i ^ (^s_axi_awcache_i) ^
        (^s_axi_awprot_i) ^ (^s_axi_awqos_i) ^ (^s_axi_awregion_i) ^
        (^s_axi_awuser_i) ^ (^s_axi_wuser_i) ^ s_axi_arlock_i ^
        (^s_axi_arcache_i) ^ (^s_axi_arprot_i) ^ (^s_axi_arqos_i) ^
        (^s_axi_arregion_i);

endmodule

`default_nettype wire
