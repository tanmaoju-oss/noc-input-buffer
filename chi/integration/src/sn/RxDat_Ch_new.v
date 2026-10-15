`timescale 1ns/1ps
`default_nettype none
/* Write transaction data delivery process
1. receive the write address and transaction information
2. receive 4 flits from the router
3. from step 1, find the right address for aci protocol
4. package the 512 bit data, 64 bit BE, 12 bit transaction ID
5. send the data to mem according to the handshake mechanism
*/

// DWT data is matched using the SN allocated DBID carried in TxnID_NCBWData.
module RxDat_Ch (
    // clk and rst_n signal
    input   wire    clk,
    input   wire    rst_n,
    // req_w data interconnection {ADDR, TxnID}
    input   wire    rw_rd_valid,
    output  wire    rd_rw_ready,
    input   wire [51:0]  rw_rd_data,
    // data router fifo signal control
    input   wire [222:0]    rx_dat_datout,
    input   wire    rx_dat_fifo_empty,
    output  wire    rx_dat_rd_req,
    // AXI master internal write request
    // BEDAT2AXI {512 bit-4flit data, 64 bit BE}
    input   wire    AXI_RxDat_ready,
    output  wire    RxDat_AXI_valid,
    output  wire [575:0]    BE_DATA2AXI,
    output  wire [511:0]    DATA_NCBWData,
    output  wire [63:0]     BE_NCBWData,
    output  wire [39:0]     addr2AXI,
    output  wire [11:0]     TxnID_NCBWData,
    // error type
    output  wire    error_Miss_txnid_And_addr
);
    // internal signal between rd_w_if and rd_w_da
    wire [6:0]      data_txnid;
    wire            data_txnid_valid;
    wire            data_txnid_ready;

    wire            address_result_valid;
    wire            address_result_ready;
    wire [39:0]     address_result;
    // error type
    wire            address_result_error;
    wire            address_match_error;
    wire            flit_txnid_mismatch_error;
    // output the error at top level
    assign error_Miss_txnid_And_addr = address_result_error ||
                    address_match_error || flit_txnid_mismatch_error;
    // instantiation module rd_w_if
    rd_w_if u_rd_w_if(
        .clk                        (clk),
        .rst_n                      (rst_n),

        .rw_rd_valid                (rw_rd_valid),
        .rd_rw_ready                (rd_rw_ready),
        .rw_rd_datout               (rw_rd_data),

        .rd_w_data_txnid            (data_txnid),
        .rd_w_reg_valid             (data_txnid_valid),
        .rw_rd_w_data_ready         (data_txnid_ready),

        .pack_valid                 (address_result_ready),
        .addr2pack                  (address_result),
        .addr2pack_ready            (address_result_valid),
        .addr2pack_error            (address_result_error),
        .error_Miss_txnid_And_addr  (address_match_error)
    );
    // instantiation module rd_w_da
    rd_w_da u_rd_w_da(
        .clk                        (clk),
        .rst_n                      (rst_n),

        .rx_dat_datout              (rx_dat_datout),
        .rx_dat_fifo_empty          (rx_dat_fifo_empty),
        .rx_dat_rd_req              (rx_dat_rd_req),

        .rd_w_data_txnid            (data_txnid),
        .rd_w_data_reg_valid        (data_txnid_valid),
        .reg_rd_w_data_ready        (data_txnid_ready),

        .pack_reg_valid             (address_result_ready),
        .addr2pack_ready            (address_result_valid),
        .addr2pack                  (address_result),
        .addr2pack_error            (address_match_error),

        .AXI_RxDat_ready            (AXI_RxDat_ready),
        .RxDat_AXI_valid            (RxDat_AXI_valid),
        .BE_DATA2AXI                (BE_DATA2AXI),
        .BE_NCBWData                (BE_NCBWData),
        .DATA_NCBWData              (DATA_NCBWData),
        .TxnID_NCBWData             (TxnID_NCBWData),
        .addr2AXI                   (addr2AXI),

        .error_flit_txnid_mismatch  (flit_txnid_mismatch_error)
    );
endmodule

/* module design rd_w_if
    1. receive the address and transaction ID from req_w
    2. put the address in the 64 items table
    3. receive the data from rd_w_da
    4. find the right address according to transaction ID
    5. reserve the address to rd_w_da by handshake mechanism
    6. check the illegal SrcID, repeatble TxnID and address no hit
 */
module rd_w_if (
    // clk and rst_n
    input   wire            clk,
    input   wire            rst_n,
    // req_w address if {Addr, TxnID}
    input   wire            rw_rd_valid,
    output  wire            rd_rw_ready,
    input   wire [51:0]     rw_rd_datout,
    // rd_w_da interconnection if
    input   wire [6:0]      rd_w_data_txnid,
    input   wire            rd_w_reg_valid,
    output  wire            rw_rd_w_data_ready,
    // output for address lut if
    input   wire            pack_valid,
    output  wire [39:0]     addr2pack,
    output  wire            addr2pack_ready,
    output  wire            addr2pack_error,
    // mismatch of address
    output  wire            error_Miss_txnid_And_addr
);
    // construction of address table and enabling signal
    reg [39:0]  addr_table  [0:63];
    reg [63:0]  addr_valid_q;
    // address buffer by handshake mechanism
    reg [39:0]  address_output_q;
    reg         address_output_valid_q;
    reg         address_output_error_q;
    // error state register
    reg         match_error_q;
    // reg_w feild splitting
    wire [11:0] request_txnid;
    wire [6:0]  request_txnid_low7;
    wire [2:0]  request_srcid;
    wire [3:0]  request_local_txnid;
    wire [39:0] request_address;
    assign request_txnid = rw_rd_datout[11:0];
    assign request_txnid_low7 = request_txnid[6:0];
    assign request_srcid = request_txnid_low7[6:4];
    assign request_local_txnid = request_txnid_low7[3:0];
    assign request_address = rw_rd_datout[51:12];
    // srcid coding mapping
    wire        request_srcid_supported;
    wire [1:0]  request_srcid_group;
    wire [5:0]  request_table_index;
    assign request_srcid_supported = (
        request_srcid == 3'b000 ||
        request_srcid == 3'b010 ||
        request_srcid == 3'b110
    );
    assign request_srcid_group = (
        (request_srcid == 3'b000) ? 2'b00 :
        (request_srcid == 3'b010) ? 2'b01 :
        (request_srcid == 3'b110) ? 2'b10 :
                                    2'b11
    );
    assign request_table_index = {request_srcid_group, request_local_txnid};
    // data txnid distribute
    wire        [2:0]       data_srcid;
    wire        [3:0]       data_local_txnid;
    wire                    data_srcid_supported;
    wire        [1:0]       data_srcid_group;
    wire        [5:0]       data_table_index;
    assign data_srcid = rd_w_data_txnid[6:4];
    assign data_local_txnid = rd_w_data_txnid[3:0];
    assign data_srcid_supported = 
            (data_srcid == 3'b000)  ||
            (data_srcid == 3'b010)  ||
            (data_srcid == 3'b110);
    assign data_srcid_group = 
            (data_srcid == 3'b000)  ?   2'b00   :
            (data_srcid == 3'b010)  ?   2'b01   :
            (data_srcid == 3'b110)  ?   2'b10   :
            2'b11;
    assign data_table_index = {data_srcid_group, data_local_txnid};
    wire        request_fire;
    wire        data_txnid_fire;
    wire        address_result_fire;
    assign request_fire = rw_rd_valid && rd_rw_ready;
    assign data_txnid_fire = rw_rd_w_data_ready && rd_w_reg_valid;
    assign address_result_fire = addr2pack_ready && pack_valid;
    assign rd_rw_ready = rst_n &&
                         (!request_srcid_supported ||
                          !addr_valid_q[request_table_index]);
    assign rw_rd_w_data_ready = rst_n && !address_output_valid_q;
    assign addr2pack = address_output_q;
    assign addr2pack_ready = address_output_valid_q;
    assign addr2pack_error = address_output_error_q;
    assign error_Miss_txnid_And_addr = match_error_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_valid_q    <=      64'b0;
            address_output_q    <=  40'b0;
            address_output_valid_q  <=      1'b0;
            address_output_error_q  <=      1'b0;
            match_error_q           <=      1'b0;
        end
        else begin
            if (request_fire) begin
                if (request_srcid_supported) begin
                    addr_table[request_table_index]     <=      request_address;
                    addr_valid_q[request_table_index]   <=      1'b1;
                end
                else begin
                    match_error_q           <=      1'b1;
                end
            end
            if(data_txnid_fire) begin
                address_output_valid_q  <=      1'b1;
                if (data_srcid_supported &&
                addr_valid_q[data_table_index]) begin
                    address_output_q            <=          addr_table[data_table_index];
                    address_output_error_q      <=          1'b0;
                    addr_valid_q[data_table_index]  <=      1'b0;
                end
                else begin
                    address_output_q            <=          40'b0;
                    address_output_error_q      <=          1'b1;
                    match_error_q               <=          1'b1;
                end
            end
            if (address_result_fire) begin
                address_output_valid_q          <=          1'b0;
                address_output_error_q          <=          1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && request_fire && !request_srcid_supported) begin
            $display ("ERROR(rd_w_if):unsupported request srcid. time=%0t txnID=%h",
            $time, request_txnid);
        end
        if(rst_n && data_txnid_fire && !data_srcid_supported)   begin
            $display("ERROR(rd_w_if):unsupported data srcid. time=%0t txnID[6:0]=%h",
            $time, rd_w_data_txnid);
        end
        if (rst_n && data_txnid_fire && data_srcid_supported &&!addr_valid_q[data_table_index])
        begin
            $display("ERROR(rd_w_if):address context not found, time=%0t txnID[6:0]=%h",
            $time, rd_w_data_txnid);
        end
    end
`endif
endmodule

/* module design rd_w_da
    1. receive data from FIFO
    2. read the data and BE signal
    3. merge 4 beats data into one
    4. from the first bead record the 12 bit txnID
    5. check the sequent txnID coherence with the forward beat
    6. send the TxnID to rd_w_if and acquire the address
    7. keep the sufficient data in AXI master and complete the shakehand mechanism
 */
module rd_w_da (
    // clock and rst_n signal
    input       wire    clk,
    input       wire    rst_n,
    // fifo control signal
    input       wire [222:0]    rx_dat_datout,
    input       wire            rx_dat_fifo_empty,
    output      reg             rx_dat_rd_req,
    // address LUT request if
    input       wire            reg_rd_w_data_ready,
    output      wire            rd_w_data_reg_valid,
    output      wire [6:0]      rd_w_data_txnid,
    // address result receive if
    output      wire            pack_reg_valid,
    input       wire            addr2pack_ready,
    input       wire [39:0]     addr2pack,
    output      wire            addr2pack_error,
    // AXI master if
    input       wire            AXI_RxDat_ready,
    output      wire            RxDat_AXI_valid,
    output      wire [575:0]    BE_DATA2AXI,
    output      wire [511:0]    DATA_NCBWData,
    output      wire [63:0]     BE_NCBWData,
    output      wire [39:0]     addr2AXI,
    output      wire [11:0]     TxnID_NCBWData,
    // judge for coherence of flit ID
    output      wire            error_flit_txnid_mismatch
);
    // FSM definition
    localparam  [2:0] ST_IDLE = 3'b000;
    localparam  [2:0] ST_RECEIVE_FLIT = 3'b001;
    localparam  [2:0] ST_REQUEST_ADDR = 3'b010;
    localparam  [2:0] ST_WAIT_ADDR = 3'b011;
    localparam  [2:0] ST_SEND_AXI = 3'b100;
    reg [2:0] state_q;
    // data joint setup
    reg [1:0]   flit_count_q;
    reg [511:0] data_q ;
    reg [63:0]  byte_enable_q;
    reg [39:0]  address_q;
    reg [11:0]  txnid_q;
    reg         flit_txnid_mismatch_q;
    // handshake mechanism
    wire        txnid_request_fire;
    wire        address_result_fire;
    wire        axi_request_fire;

    assign txnid_request_fire = rd_w_data_reg_valid && reg_rd_w_data_ready;
    assign address_result_fire = pack_reg_valid && addr2pack_ready;
    assign axi_request_fire = AXI_RxDat_ready && RxDat_AXI_valid;
    // output signal
    assign rd_w_data_reg_valid = (state_q == ST_REQUEST_ADDR);
    assign rd_w_data_txnid = txnid_q[6:0];
    assign pack_reg_valid = (state_q == ST_WAIT_ADDR);
    assign RxDat_AXI_valid = (state_q == ST_SEND_AXI);
    assign BE_DATA2AXI = {data_q, byte_enable_q};
    assign DATA_NCBWData = data_q;
    assign BE_NCBWData = byte_enable_q;
    assign addr2AXI = address_q;
    assign TxnID_NCBWData = txnid_q;
    assign error_flit_txnid_mismatch = flit_txnid_mismatch_q;
    // main FSM and data channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            flit_count_q <= 2'b00;
            rx_dat_rd_req <= 1'b0;
            data_q <= 512'b0;
            byte_enable_q <= 64'b0;
            address_q <= 40'b0;
            txnid_q <= 12'b0;
            flit_txnid_mismatch_q <= 1'b0;
        end
        else begin
            case (state_q)
                ST_IDLE: begin
                    rx_dat_rd_req <= 1'b0;
                    if(!rx_dat_fifo_empty) begin
                        flit_count_q <= 2'b00;
                        data_q <= 512'b0;
                        byte_enable_q <= 64'b0;
                        address_q <= 40'b0;
                        txnid_q <= 12'b0;
                        flit_txnid_mismatch_q <= 1'b0;
                        state_q <= ST_RECEIVE_FLIT;
                    end
                end
                ST_RECEIVE_FLIT: begin
                    if(!rx_dat_rd_req) begin
                        if(!rx_dat_fifo_empty)
                            rx_dat_rd_req <= 1'b1;
                    end
                    else begin
                        rx_dat_rd_req <= 1'b0;
                        case (flit_count_q)
                            2'b00: begin
                                data_q[127:0] <= rx_dat_datout[222:95];
                                byte_enable_q[15:0] <= rx_dat_datout[94:79];
                                txnid_q[11:0] <= rx_dat_datout[29:18];
                            end
                            2'b01: begin
                                data_q[255:128] <= rx_dat_datout[222:95];
                                byte_enable_q[31:16] <= rx_dat_datout[94:79];
                                if(rx_dat_datout[29:18] != txnid_q)
                                    flit_txnid_mismatch_q <= 1'b1;
                            end
                            2'b10: begin
                                data_q[383:256] <= rx_dat_datout[222:95];
                                byte_enable_q[47:32] <= rx_dat_datout[94:79];
                                if (rx_dat_datout[29:18] != txnid_q) begin
                                    flit_txnid_mismatch_q <= 1'b1;
                                end
                            end
                            2'b11: begin
                                data_q[511:384] <= rx_dat_datout[222:95];
                                byte_enable_q[63:48] <= rx_dat_datout[94:79];
                                if (rx_dat_datout[29:18] != txnid_q) begin
                                    flit_txnid_mismatch_q <= 1'b1;
                                end
                            end
                            default: begin
                                end
                        endcase
                        if (flit_count_q == 2'b11) begin
                            flit_count_q <= 2'b0;
                            state_q <= ST_REQUEST_ADDR;
                        end
                        else begin
                            flit_count_q <= flit_count_q + 1'b1;
                        end
                    end
                end
                ST_REQUEST_ADDR : begin
                    if(txnid_request_fire) begin
                        state_q <= ST_WAIT_ADDR;
                    end
                end
                ST_WAIT_ADDR : begin
                    if (address_result_fire) begin
                        address_q <= addr2pack;
                        if (addr2pack_error || flit_txnid_mismatch_q) begin
                            state_q <= ST_IDLE;
                        end
                        else begin
                            state_q <= ST_SEND_AXI;
                        end
                    end
                end
                ST_SEND_AXI : begin
                    if (axi_request_fire) begin
                        state_q <= ST_IDLE;
                    end
                end
                default: begin
                    state_q <= ST_IDLE;
                    flit_count_q <= 2'b00;
                    rx_dat_rd_req <= 1'b0;
                    flit_txnid_mismatch_q <= 1'b1;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
         if (rst_n &&
            state_q == ST_RECEIVE_FLIT &&
            rx_dat_rd_req &&
            flit_count_q != 2'd0 &&
            rx_dat_datout[29:18] != txnid_q) begin
            $display("ERROR(rd_w_da): TxnID mismatch between data flits, time=%0t first=%h current=%h",
                     $time, txnid_q, rx_dat_datout[29:18]);
        end
    end
`endif
 
endmodule
`default_nettype wire

// Integration wrapper with direction-qualified, protocol-oriented port names.
`default_nettype none
// Modify by Michael Tan，20261015: recoverable ordered-four-beat write collector.
// Contract: no interleaving; late flits after timeout must be flushed upstream.
// DATA_TIMEOUT_CYCLES bounds missing-data contexts, not AXI backpressure.
module RxDat_Ch_new #(
    parameter integer DATA_TIMEOUT_CYCLES = 256
)(
    input wire clk_i, rst_ni,
    input wire write_context_valid_i,
    output wire write_context_ready_o,
    input wire [51:0] write_context_i,
    input wire [222:0] chi_rx_dat_flit_i,
    input wire chi_rx_dat_empty_i,
    output wire chi_rx_dat_read_o,
    input wire axi_write_ready_i,
    output wire axi_write_valid_o,
    output wire [511:0] axi_write_data_o,
    output wire [63:0] axi_write_strb_o,
    output wire [39:0] axi_write_addr_o,
    output wire [11:0] axi_write_id_o,
    output reg rx_data_error_o,
    output reg [7:0] write_abort_o,
    // Modify by Michael Tan，20261015: start deadline only after DBID response is enqueued toward requester.
    input wire [7:0] response_sent_i
);
    reg [127:0] valid_q;
    reg [127:0] armed_q;
    reg [11:0] id_q [0:127];
    reg [39:0] addr_q [0:127];
    // Modify by Michael Tan，20261015: size timeout counters to the configured deadline.
    localparam integer TIMEOUT_WIDTH = DATA_TIMEOUT_CYCLES < 2 ? 1 : $clog2(DATA_TIMEOUT_CYCLES+1);
    reg [TIMEOUT_WIDTH-1:0] age_q [0:127];
    localparam IDLE=0, COLLECT=1, SEND=2;
    reg [1:0] state_q;
    reg fetch_q;
    reg [1:0] beat_q;
    reg [11:0] active_id_q;
    reg [39:0] active_addr_q;
    reg [511:0] data_q;
    reg [63:0] strb_q;
    reg bad_q;
    // Modify by Michael Tan，20261015: bound orphan/partial packets even without an address context.
    reg [TIMEOUT_WIDTH-1:0] collect_age_q;
    wire [6:0] incoming_index = chi_rx_dat_flit_i[24:18];
    wire [11:0] incoming_id = chi_rx_dat_flit_i[29:18];
    wire [6:0] context_index = write_context_i[6:0];
    wire context_fire = write_context_valid_i && write_context_ready_o;
    wire bad_flit = chi_rx_dat_flit_i[40:37] != 4'h3 ||
                    chi_rx_dat_flit_i[69:68] != beat_q ||
                    incoming_id != active_id_q;
    integer i;
    integer expired_index;
    always @(*) begin
        expired_index = -1;
        for (integer j=0; j<128; j=j+1)
            if (valid_q[j] && armed_q[j] && age_q[j] >= DATA_TIMEOUT_CYCLES &&
                // Modify by Michael Tan，20261015: unrelated expiry must not consume another packet's read handshake.
                ((state_q == IDLE && !fetch_q) || (state_q == COLLECT && active_id_q[6:0] == j)) &&
                expired_index == -1)
                expired_index = j;
    end
    assign write_context_ready_o = rst_ni && !valid_q[context_index];
    assign chi_rx_dat_read_o = fetch_q;
    assign axi_write_valid_o = state_q == SEND;
    assign axi_write_data_o = data_q;
    assign axi_write_strb_o = strb_q;
    assign axi_write_addr_o = active_addr_q;
    assign axi_write_id_o = active_id_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= 0;
            armed_q <= 0;
            state_q <= IDLE;
            fetch_q <= 0;
            beat_q <= 0;
            active_id_q <= 0;
            active_addr_q <= 0;
            data_q <= 0;
            strb_q <= 0;
            bad_q <= 0;
            collect_age_q <= 0;
            rx_data_error_o <= 0;
            write_abort_o <= 0;
            for (i=0; i<128; i=i+1) age_q[i] <= 0;
        end else begin
            rx_data_error_o <= 0;
            write_abort_o <= 0;
            if (state_q == COLLECT && collect_age_q < DATA_TIMEOUT_CYCLES) collect_age_q <= collect_age_q+1;
            else collect_age_q <= 0;
            for (i=0; i<128; i=i+1)
                if (valid_q[i] && armed_q[i] && age_q[i] < DATA_TIMEOUT_CYCLES)
                    age_q[i] <= age_q[i]+1;
            if (response_sent_i[7]) begin
                armed_q[response_sent_i[6:0]] <= 1;
                age_q[response_sent_i[6:0]] <= 0;
            end
            if (context_fire) begin
                valid_q[context_index] <= 1;
                armed_q[context_index] <= 0;
                id_q[context_index] <= write_context_i[11:0];
                addr_q[context_index] <= write_context_i[51:12];
                age_q[context_index] <= 0;
            end

            // Timeout has priority over reception; do not sample a popped late
            // flit into another context. Upstream must stop/flush expired data.
            if (expired_index != -1) begin
                valid_q[expired_index] <= 0;
                rx_data_error_o <= 1;
                write_abort_o <= {1'b1, expired_index[6:0]};
                if (state_q == COLLECT && active_id_q[6:0] == expired_index[6:0]) begin
                    state_q <= IDLE;
                    fetch_q <= 0;
                    beat_q <= 0;
                end
            end else if (state_q == COLLECT && collect_age_q >= DATA_TIMEOUT_CYCLES) begin
                // Modify by Michael Tan，20261015: recover from missing orphan beats.
                rx_data_error_o <= 1;
                fetch_q <= 0;
                state_q <= IDLE;
                if (valid_q[active_id_q[6:0]] && id_q[active_id_q[6:0]] == active_id_q) begin
                    valid_q[active_id_q[6:0]] <= 0;
                    write_abort_o <= {1'b1,active_id_q[6:0]};
                end
            end else begin
                case (state_q)
                    IDLE: begin
                        beat_q <= 0;
                        bad_q <= 0;
                        if (!fetch_q && !chi_rx_dat_empty_i)
                            fetch_q <= 1;
                        else if (fetch_q) begin
                            fetch_q <= 0;
                            active_id_q <= incoming_id;
                            active_addr_q <= addr_q[incoming_index];
                            data_q <= {384'b0, chi_rx_dat_flit_i[222:95]};
                            strb_q <= {48'b0, chi_rx_dat_flit_i[94:79]};
                            bad_q <= !valid_q[incoming_index] ||
                                id_q[incoming_index] != incoming_id ||
                                chi_rx_dat_flit_i[40:37] != 4'h3 ||
                                chi_rx_dat_flit_i[69:68] != 0;
                            beat_q <= 1;
                            state_q <= COLLECT;
                        end
                    end
                    COLLECT: begin
                        if (!fetch_q && !chi_rx_dat_empty_i)
                            fetch_q <= 1;
                        else if (fetch_q) begin
                            fetch_q <= 0;
                            data_q[beat_q*128+:128] <= chi_rx_dat_flit_i[222:95];
                            strb_q[beat_q*16+:16] <= chi_rx_dat_flit_i[94:79];
                            bad_q <= bad_q || bad_flit;
                            if (beat_q == 3) begin
                                // Full-ID match before clearing prevents a bad
                                // high ID from cancelling another valid slot.
                                if (bad_q || bad_flit) begin
                                    rx_data_error_o <= 1;
                                    if (valid_q[active_id_q[6:0]] &&
                                        id_q[active_id_q[6:0]] == active_id_q) begin
                                        valid_q[active_id_q[6:0]] <= 0;
                                        write_abort_o <= {1'b1,active_id_q[6:0]};
                                    end
                                    state_q <= IDLE;
                                end else begin
                                    valid_q[active_id_q[6:0]] <= 0;
                                    state_q <= SEND;
                                end
                            end else beat_q <= beat_q+1'b1;
                        end
                    end
                    SEND: if (axi_write_ready_i) state_q <= IDLE;
                    default: state_q <= IDLE;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
