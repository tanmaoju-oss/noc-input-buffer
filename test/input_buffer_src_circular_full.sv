import noc_params::*;

module input_buffer #(
    parameter BUFFER_SIZE = 8
)(
    input flit_novc_t data_i,
    input read_i,
    input write_i,
    input [VC_SIZE-1:0] vc_new_i,
    input vc_valid_i,
    input port_t out_port_i,
    input rst,
    input clk,
    output flit_t data_o,
    output logic is_full_o,
    output logic is_empty_o,
    output logic on_off_o,
    output port_t out_port_o,
    output logic vc_request_o,
    output logic switch_request_o,
    output logic vc_allocatable_o,
    output logic [VC_SIZE-1:0] downstream_vc_o,
    output logic error_o
);

    // Original single-packet FSM kept for reference; replaced by packet metadata FIFO.
    // enum logic [1:0] {IDLE, VA, SA} ss, ss_next;

    // New: packet metadata stored per packet so one VC FIFO can hold multiple packets.
    typedef struct packed {
        port_t out_port;
        logic [VC_SIZE-1:0] downstream_vc;
        logic vc_allocated;
    } packet_meta_t;

    // New: reuse BUFFER_SIZE as the metadata queue depth for the minimal implementation.
    localparam [31:0] META_POINTER_SIZE = $clog2(BUFFER_SIZE);

    //add, Michael Tan, 20260528
    flit_novc_t first_flit_novc; //add by Michael Tan, 20260528, no VCs
    // logic head_valid;//add by Michael Tan, 20260602, test

    // Original single-packet downstream VC next-state kept for reference.
    // logic [VC_SIZE-1:0] downstream_vc_next;

    logic read_cmd, write_cmd;
    // Original single-packet end marker kept for reference.
    // logic end_packet, end_packet_next;
    // logic vc_allocatable_next;
    // logic error_next;

    // New: packet metadata circular queue.
    packet_meta_t meta_mem[BUFFER_SIZE-1:0];
    logic [META_POINTER_SIZE-1:0] meta_rd_ptr;
    logic [META_POINTER_SIZE-1:0] meta_wr_ptr;
    logic [META_POINTER_SIZE:0] num_packets;

    // New: command wires for metadata FIFO updates.
    logic meta_push_cmd;
    logic meta_pop_cmd;
    logic meta_alloc_cmd;
    logic meta_full;
    logic meta_space_available;
    logic has_packet;
    logic head_allocated;
    logic accept_write;
    logic accept_read;
    logic write_packet_open;
    logic write_order_ok;
    logic is_head_flit;
    logic is_headtail_flit;
    logic is_body_flit;
    logic is_tail_input_flit;
    logic is_tail_flit;
    packet_meta_t meta_head;

    flit_novc_t read_flit;

    // Original single-packet output port next-state kept for reference.
    // port_t out_port_next; 

    circular_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE)
    )
    circular_buffer (
        .data_i(data_i),
        .read_i(read_cmd),
        .write_i(write_cmd),
        .rst(rst),
        .clk(clk),

        // .first_flit_o(first_flit_novc),//

        .data_o(read_flit),
        .is_full_o(is_full_o),
        .is_empty_o(is_empty_o),
        .on_off_o(on_off_o)
    );
  
    /*
    Sequential logic:
    - on the rising edge of the reset input signal, reset the state of the
      finite state machine, the next hop destination and the downstream virtual
      channel identifier;
    - on the rising edge of the clock input signal, update the state,
      the next hop destination and the downstream virtual channel identifier.
    */
    // Original single-packet state register block kept for reference.
    /*
    always_ff @(posedge clk, posedge rst)
    begin
        if(rst)
        begin
            ss                  <= IDLE;
            out_port_o          <= LOCAL;
            downstream_vc_o     <= 0;
            end_packet          <= 0;
            vc_allocatable_o    <= 0;
            error_o             <= 0;
        end
        else
        begin
            ss                  <= ss_next;
            out_port_o          <= out_port_next;
            downstream_vc_o     <= downstream_vc_next;
            end_packet          <= end_packet_next;
            vc_allocatable_o    <= vc_allocatable_next;
            error_o             <= error_next;
        end
    end
    */

    /*
    Combinational logic:
    - in Idle state, when the input flit is an Head one, the write command is
      asserted and the buffer is empty, then the next hop destination received
      in input and associated to the flit is stored, and the next state is set
      to be Virtual Channel Allocation;
    - in Virtual Channel Allocation state, when the virtual channel for the
      downstream router is valid, i.e., the corresponding validity signal is
      asserted, then the virtual channel identifier is stored and the next
      state is set to be Switch Allocation;
    - in Switch Allocation state, when the last flit to read is the Tail one
      and the read command is asserted, then the next state is set to be Idle.
    */
    // Original single-packet control block kept for reference.
    /*
    always_comb
    begin
        data_o.flit_label = read_flit.flit_label;
		data_o.vc_id = downstream_vc_o;
		data_o.data = read_flit.data;

        ss_next = ss;
        out_port_next = out_port_o;
        downstream_vc_next = downstream_vc_o;

        read_cmd = 0;
        write_cmd = 0;

        end_packet_next = end_packet;
        error_next = 0;

        vc_request_o = 0;
        switch_request_o = 0;
        vc_allocatable_next = 0;

        unique case(ss)
            IDLE:
            begin
                // if((data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL) & write_i & is_empty_o)
                if((data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL) & write_i) //Modify by Michael Tan, 20260604
                begin
                    ss_next = VA;
                    out_port_next = out_port_i;
                    // head_valid = 0;//add by Michael Tan, 20260602
                    write_cmd = 1;//remove by Michael Tan, 20260602
                end

                //if(vc_valid_i | read_i | ((data_i.flit_label == BODY | data_i.flit_label == TAIL) & write_i) | ~is_empty_o)
                if(vc_valid_i | read_i | ((data_i.flit_label == BODY | data_i.flit_label == TAIL) & write_i)) //Modify by Michael Tan, 20260609
                begin
                    error_next = 1;
                end
                if(write_i & data_i.flit_label == HEADTAIL)
                begin
                    end_packet_next = 1;
                end
            end

            VA:
            begin
                if(vc_valid_i)
                begin
                    ss_next = SA;
                    downstream_vc_next = vc_new_i;
                end

                vc_request_o = 1;
                if(write_i & (data_i.flit_label == BODY | data_i.flit_label == TAIL) & ~end_packet)
                begin
                    write_cmd = 1;
                end

                if((write_i & (end_packet | data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL)) | read_i)
                begin
                    error_next = 1;
                end
                if(write_i & data_i.flit_label == TAIL)
                begin
                    end_packet_next = 1;
                end
            end

            SA:
            begin
                if(read_i & (data_o.flit_label == TAIL | data_o.flit_label == HEADTAIL))
                begin
                    ss_next = IDLE;
                    vc_allocatable_next = 1;
                    end_packet_next = 0;
                end

                if(~is_empty_o)
                begin
                    switch_request_o = 1;
                end
                    
                read_cmd = read_i;
                if(write_i & (data_i.flit_label == BODY | data_i.flit_label == TAIL) & ~end_packet)
                begin
                    write_cmd = 1;
                end

                if((write_i & (end_packet | data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL)) | vc_valid_i)
                begin
                    error_next = 1;
                end
                if(write_i & data_i.flit_label == TAIL)
                begin
                    end_packet_next = 1;
                end
            end

            default:
            begin
                ss_next = IDLE;
                vc_allocatable_next = 1;
                error_next = 1;
                end_packet_next = 0;
            end

        endcase
    end
    */

    // New: metadata FIFO helpers for the multi-packet-per-VC minimal implementation.
    // New: metadata queue is full when every metadata entry is occupied.
    assign meta_full = (num_packets == BUFFER_SIZE);
    // New: a simultaneous packet pop makes room for a new packet header.
    assign meta_space_available = ~meta_full | meta_pop_cmd;
    assign has_packet = (num_packets != 0);
    assign meta_head = meta_mem[meta_rd_ptr];
    assign head_allocated = has_packet & meta_head.vc_allocated;
    assign is_head_flit = (data_i.flit_label == HEAD) | is_headtail_flit;
    assign is_headtail_flit = (data_i.flit_label == HEADTAIL);
    assign is_body_flit = (data_i.flit_label == BODY);
    assign is_tail_input_flit = (data_i.flit_label == TAIL);
    assign is_tail_flit = (read_flit.flit_label == TAIL) | (read_flit.flit_label == HEADTAIL);
    // New: reads are accepted only for an allocated head packet and non-empty flit FIFO.
    assign accept_read = read_i & head_allocated & ~is_empty_o;
    // New: the write stream may hold many packets, but packet flits must not be interleaved.
    assign write_order_ok = ((data_i.flit_label == HEAD) & ~write_packet_open & meta_space_available) |
                            (is_headtail_flit & ~write_packet_open & meta_space_available) |
                            (is_body_flit & write_packet_open) |
                            (is_tail_input_flit & write_packet_open);
    // New: HEAD/HEADTAIL need a free metadata slot; BODY/TAIL need an existing packet.
    assign accept_write = write_i & (~is_full_o | accept_read) & write_order_ok;
    assign meta_push_cmd = accept_write & is_head_flit;
    assign meta_pop_cmd = accept_read & is_tail_flit;
    assign meta_alloc_cmd = vc_valid_i & has_packet & ~meta_head.vc_allocated;

    // New: packet metadata FIFO state. Only the head packet is allocated/transmitted.
    always_ff @(posedge clk, posedge rst)
    begin
        if(rst)
        begin
            meta_rd_ptr <= 0;
            meta_wr_ptr <= 0;
            num_packets <= 0;
            write_packet_open <= 0;
            vc_allocatable_o <= 0;
            error_o <= 0;
        end
        else
        begin
            vc_allocatable_o <= meta_pop_cmd;
            error_o <= (write_i & ~accept_write) |
                       (read_i & (~head_allocated | is_empty_o)) |
                       (vc_valid_i & (~has_packet | meta_head.vc_allocated));

            if(meta_alloc_cmd)
            begin
                meta_mem[meta_rd_ptr].downstream_vc <= vc_new_i;
                meta_mem[meta_rd_ptr].vc_allocated <= 1'b1;
            end

            if(meta_push_cmd)
            begin
                meta_mem[meta_wr_ptr].out_port <= out_port_i;
                meta_mem[meta_wr_ptr].downstream_vc <= {VC_SIZE{1'b0}};
                meta_mem[meta_wr_ptr].vc_allocated <= 1'b0;
            end

            if(accept_write)
            begin
                if(data_i.flit_label == HEAD)
                    write_packet_open <= 1'b1;
                else if(is_tail_input_flit | is_headtail_flit)
                    write_packet_open <= 1'b0;
            end

            unique case({meta_push_cmd, meta_pop_cmd})
                2'b10:
                begin
                    meta_wr_ptr <= increase_meta_ptr(meta_wr_ptr);
                    num_packets <= num_packets + 1;
                end
                2'b01:
                begin
                    meta_rd_ptr <= increase_meta_ptr(meta_rd_ptr);
                    num_packets <= num_packets - 1;
                end
                2'b11:
                begin
                    meta_wr_ptr <= increase_meta_ptr(meta_wr_ptr);
                    meta_rd_ptr <= increase_meta_ptr(meta_rd_ptr);
                    num_packets <= num_packets;
                end
                default:
                begin
                    meta_wr_ptr <= meta_wr_ptr;
                    meta_rd_ptr <= meta_rd_ptr;
                    num_packets <= num_packets;
                end
            endcase
        end
    end

    // New: combinational outputs are driven by the head metadata entry.
    always_comb
    begin
        data_o.flit_label = read_flit.flit_label;
        data_o.vc_id = head_allocated ? meta_head.downstream_vc : {VC_SIZE{1'b0}};
        data_o.data = read_flit.data;

        out_port_o = has_packet ? meta_head.out_port : LOCAL;
        downstream_vc_o = head_allocated ? meta_head.downstream_vc : {VC_SIZE{1'b0}};

        vc_request_o = has_packet & ~meta_head.vc_allocated;
        switch_request_o = head_allocated & ~is_empty_o;

        read_cmd = accept_read;
        write_cmd = accept_write;
    end

    // New: metadata queue pointer increment.
    function logic [META_POINTER_SIZE-1:0] increase_meta_ptr (input logic [META_POINTER_SIZE-1:0] ptr);
        if(ptr == BUFFER_SIZE-1)
            increase_meta_ptr = 0;
        else
            increase_meta_ptr = ptr + 1;
    endfunction

endmodule
