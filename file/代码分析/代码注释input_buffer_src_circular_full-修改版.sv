// 导入NoC参数包（包含VC_SIZE、PORT_NUM等全局参数）
// 上游将flit压入缓存区中，缓存区加上标签，SA确定时刻发送，VA
//上游packet，一个packet等于一个meta，压入meta 缓存区
//上层input_port_Xiugai2.sv
import noc_params::*;

/*
 * 模块名称：input_buffer
 * 功能描述：NoC路由器输入缓冲区模块
 * 主要功能：
 *   1. 存储到达的flit数据（使用循环缓冲区）
 *   2. 支持多个数据包在同一VC中排队（通过元数据FIFO保存各包输出端口），按到达FIFO顺序传输 //Modify by Michael Tan，20260908
 *   3. 处理虚拟通道分配（VA）和开关分配（SA）
 *   4. 管理数据包的头部/体部/尾部flit的顺序
 */
module input_buffer #(
    parameter BUFFER_SIZE = 8  // 缓冲区深度（flit数量）
)(
    // ========== 输入信号 ==========
    input flit_novc_t data_i,        // 输入数据（不含VC ID）
    input read_i,                    // 读使能信号（来自开关分配器）
    input write_i,                   // 写使能信号（来自上一级路由器）
    input [VC_SIZE-1:0] vc_new_i,    // 新分配的VC ID
    input vc_valid_i,                // VC分配有效信号
    input port_t out_port_i,         // 输出端口（来自路由计算）
    input rst,                       // 复位信号（高有效）
    input clk,                       // 时钟信号
    
    // ========== 输出信号 ==========
    output flit_t data_o,            // 输出数据（含VC ID）
    output logic is_full_o,          // 缓冲区满标志
    output logic is_empty_o,         // 缓冲区空标志
    output logic on_off_o,           // 流控开关信号（来自循环缓冲区） //Modify by Michael Tan，20260908
    output port_t out_port_o,        // 输出端口
    output logic vc_request_o,       // VC请求信号（用于VA阶段）
    output logic switch_request_o,   // 开关请求信号（用于SA阶段）
    output logic vc_allocatable_o,   // 队首包尾flit成功读出时的脉冲，表示已分配下游VC可释放 //Modify by Michael Tan，20260908
    output logic [VC_SIZE-1:0] downstream_vc_o,  // 下游VC ID
    output logic error_o             // 非法写、读或VC分配的本周期错误标志，经上层汇集输出 //Modify by Michael Tan，20260908
);

    // ========== 类型定义 ==========
    /*
     * 数据包元数据结构
     * 每个数据包在元数据FIFO中占一个条目
     * 用于支持多数据包在同一VC中排队
     */
    typedef struct packed {
        port_t out_port;                      // 数据包的目的输出端口
        logic [VC_SIZE-1:0] downstream_vc;    // 下游分配的VC ID
        logic vc_allocated;                   // VC是否已分配标志
    } packet_meta_t;                          // 目的是在Meta Fifo中存packet标签，使环形缓冲区能够存放多个Packet的flit //Modify by Michael Tan，20260908

    // 元数据指针位宽计算
    localparam [31:0] META_POINTER_SIZE = $clog2(BUFFER_SIZE);

    // ========== 信号声明 ==========
    flit_novc_t first_flit_novc;  // 当前实现未使用的遗留声明，删除前需全工程检查 //Modify by Michael Tan，20260908

    logic read_cmd;               // 内部读命令
    logic write_cmd;              // 内部写命令

    // ========== 元数据FIFO信号 ==========
    packet_meta_t meta_mem[BUFFER_SIZE-1:0];  // 元数据存储阵列，根据buffer尺寸确定
    logic [META_POINTER_SIZE-1:0] meta_rd_ptr;  // 元数据读指针
    logic [META_POINTER_SIZE-1:0] meta_wr_ptr;  // 元数据写指针
    logic [META_POINTER_SIZE:0] num_packets;    // 当前排队的数据包数量

    // 元数据FIFO控制信号
    logic meta_push_cmd;          // 元数据入队命令（新数据包到达）
    logic meta_pop_cmd;           // 元数据出队命令（数据包完成）
    logic meta_alloc_cmd;         // VC分配命令
    logic meta_full;              // 元数据FIFO满
    logic meta_space_available;   // 元数据FIFO有空间
    logic has_packet;             // 是否有排队的数据包
    logic head_allocated;         // 队首数据包是否已分配VC
    logic accept_write;           // 是否接受写操作
    logic accept_read;            // 是否接受读操作
    logic write_packet_open;      // 是否有正在写入的数据包
    logic write_order_ok;         // 写顺序是否正确
    logic is_head_flit;           // 是否为HEAD flit
    logic is_headtail_flit;       // 是否为HEADTAIL flit
    logic is_body_flit;           // 是否为BODY flit
    logic is_tail_input_flit;     // 输入是否为TAIL flit
    logic is_tail_flit;           // 输出是否为TAIL flit
    packet_meta_t meta_head;      // 队首元数据



    // ========== 实例化循环缓冲区 ==========
    /*
     * 循环缓冲区：存储实际的flit数据
     * 深度为BUFFER_SIZE
     */
    circular_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE)
    )
    circular_buffer (
        .data_i(data_i),
        .read_i(read_cmd),
        .write_i(write_cmd),
        .rst(rst),
        .clk(clk),
        .data_o(read_flit),
        .is_full_o(is_full_o),
        .is_empty_o(is_empty_o),
        .on_off_o(on_off_o)
    );
	
    flit_novc_t read_flit;        // 从循环缓冲区读出的flit（类型定义来自noc_params） //Modify by Michael Tan，20260908
  
    // ========================================
    // 原始单数据包FSM代码已被注释掉
    // 保留作为参考，但不再使用
    // 新实现使用元数据FIFO支持多数据包
    // ========================================

    // ========== 组合逻辑：元数据FIFO状态判断 ==========
    
    // 元数据FIFO满标志
    assign meta_full = (num_packets == BUFFER_SIZE);
    
    // 元数据FIFO有空间（同时出队可以为入队腾出空间）
    assign meta_space_available = ~meta_full | meta_pop_cmd;
    
    // 是否有排队的数据包
    assign has_packet = (num_packets != 0);
    
    // 队首元数据
    assign meta_head = meta_mem[meta_rd_ptr];
    
    // 队首数据包是否已分配VC
    assign head_allocated = has_packet & meta_head.vc_allocated;
    
    // ========== Flit类型判断 ==========
    assign is_head_flit = (data_i.flit_label == HEAD) | is_headtail_flit;
    assign is_headtail_flit = (data_i.flit_label == HEADTAIL);
    assign is_body_flit = (data_i.flit_label == BODY);
    assign is_tail_input_flit = (data_i.flit_label == TAIL);
    assign is_tail_flit = (read_flit.flit_label == TAIL) | (read_flit.flit_label == HEADTAIL);
    
    // ========== 读/写接受条件 ==========
    /*
     * 读操作接受条件：
     * 1. 有读使能
     * 2. 队首数据包已分配VC
     * 3. 循环缓冲区非空
     */
    assign accept_read = read_i & head_allocated & ~is_empty_o;
    
    /*
     * 写操作顺序检查：
     * 确保flit按正确顺序到达（HEAD -> BODY -> TAIL）
     * 不允许数据包交错
     */
    assign write_order_ok = ((data_i.flit_label == HEAD) & ~write_packet_open & meta_space_available) |
                            (is_headtail_flit & ~write_packet_open & meta_space_available) |
                            (is_body_flit & write_packet_open) |
                            (is_tail_input_flit & write_packet_open);
    
    /*
     * 写操作接受条件：
     * 1. 有写使能
     * 2. 循环缓冲区未满（或同时有读操作腾出空间）
     * 3. 写顺序正确
     */
    assign accept_write = write_i & (~is_full_o | accept_read) & write_order_ok;
    
    // ========== 元数据FIFO控制命令 ==========
    assign meta_push_cmd = accept_write & is_head_flit;    // 新数据包开始时入队
    assign meta_pop_cmd = accept_read & is_tail_flit;      // 数据包结束时出队
    assign meta_alloc_cmd = vc_valid_i & has_packet & ~meta_head.vc_allocated;  // VC分配

    // ========== 时序逻辑：元数据FIFO状态更新 ==========
    /*
     * 在复位或时钟上升沿更新：
     * 1. 元数据指针
     * 2. 数据包计数
     * 3. 数据包打开状态
     * 4. VC可分配标志
     * 5. 错误标志
     */
    always_ff @(posedge clk, posedge rst)
    begin
        if(rst)
        begin
            // 复位：清零所有状态
            meta_rd_ptr <= 0;
            meta_wr_ptr <= 0;
            num_packets <= 0;
            write_packet_open <= 0;
            vc_allocatable_o <= 0;
            error_o <= 0;
        end
        else
        begin
            // 输出信号更新
            vc_allocatable_o <= meta_pop_cmd;  // 数据包完成时释放VC
            
            // 错误检测
            error_o <= (write_i & ~accept_write) |           // 写操作被拒绝
                       (read_i & (~head_allocated | is_empty_o)) |  // 读操作无效
                       (vc_valid_i & (~has_packet | meta_head.vc_allocated));  // VC分配无效
            
            // VC分配：更新队首数据包的VC信息
            if(meta_alloc_cmd) // VA确定之后 //Modify by Michael Tan，20260908
            begin
                meta_mem[meta_rd_ptr].downstream_vc <= vc_new_i;
                meta_mem[meta_rd_ptr].vc_allocated <= 1'b1;
            end
            
            // 新数据包入队：存储元数据
            if(meta_push_cmd)
            begin
                meta_mem[meta_wr_ptr].out_port <= out_port_i;
                meta_mem[meta_wr_ptr].downstream_vc <= {VC_SIZE{1'b0}};  // 初始未分配
                meta_mem[meta_wr_ptr].vc_allocated <= 1'b0;
            end
            
            // 更新数据包打开状态（跟踪当前正在写入的数据包）
            if(accept_write)
            begin
                if(data_i.flit_label == HEAD)
                    write_packet_open <= 1'b1;      // HEAD开始新数据包
                else if(is_tail_input_flit | is_headtail_flit)
                    write_packet_open <= 1'b0;      // TAIL结束数据包
            end
            
            // ===== 元数据指针更新 =====
            unique case({meta_push_cmd, meta_pop_cmd})
                2'b10:  // 仅入队
                begin
                    meta_wr_ptr <= increase_meta_ptr(meta_wr_ptr);
                    num_packets <= num_packets + 1;
                end
                2'b01:  // 仅出队
                begin
                    meta_rd_ptr <= increase_meta_ptr(meta_rd_ptr);
                    num_packets <= num_packets - 1;
                end
                2'b11:  // 同时入队和出队
                begin
                    meta_wr_ptr <= increase_meta_ptr(meta_wr_ptr);
                    meta_rd_ptr <= increase_meta_ptr(meta_rd_ptr);
                    num_packets <= num_packets;  // 数量不变
                end
                default:  // 无操作
                begin
                    meta_wr_ptr <= meta_wr_ptr;
                    meta_rd_ptr <= meta_rd_ptr;
                    num_packets <= num_packets;
                end
            endcase
        end
    end

    // ========== 组合逻辑：输出信号驱动 ==========
    /*
     * 根据队首数据包的元数据和循环缓冲区数据生成输出
     */
    always_comb
    begin
        // 输出数据组合：flit标签+VC ID+数据负载
        data_o.flit_label = read_flit.flit_label; //Modify by Michael Tan，20260908
        data_o.vc_id = head_allocated ? meta_head.downstream_vc : {VC_SIZE{1'b0}};
        data_o.data = read_flit.data;

        // 输出端口：使用队首数据包的输出端口
        out_port_o = has_packet ? meta_head.out_port : LOCAL;
        
        // 下游VC ID
        downstream_vc_o = head_allocated ? meta_head.downstream_vc : {VC_SIZE{1'b0}};

        // 控制信号
        vc_request_o = has_packet & ~meta_head.vc_allocated;  // 需要VC分配
        switch_request_o = head_allocated & ~is_empty_o;      // 需要开关分配

        // 内部读写命令
        read_cmd = accept_read;
        write_cmd = accept_write;
    end

    // ========== 函数定义 ==========
    /*
     * 函数：increase_meta_ptr
     * 功能：循环递增元数据指针
     * 参数：ptr - 当前指针值
     * 返回：递增后的指针值（回绕到0当达到BUFFER_SIZE-1）
     */
    function logic [META_POINTER_SIZE-1:0] increase_meta_ptr (input logic [META_POINTER_SIZE-1:0] ptr);
        if(ptr == BUFFER_SIZE-1)
            increase_meta_ptr = 0;  // 回绕
        else
            increase_meta_ptr = ptr + 1;
    endfunction

endmodule










// import noc_params::*;
// module input_buffer #(
//     parameter BUFFER_SIZE = 8
// )(
//     input flit_novc_t data_i,
//     input read_i,
//     input write_i,
//     input [VC_SIZE-1:0] vc_new_i,
//     input vc_valid_i,
//     input port_t out_port_i,
//     input rst,
//     input clk,
//     output flit_t data_o,
//     output logic is_full_o,
//     output logic is_empty_o,
//     output logic on_off_o,
//     output port_t out_port_o,
//     output logic vc_request_o,
//     output logic switch_request_o,
//     output logic vc_allocatable_o,
//     output logic [VC_SIZE-1:0] downstream_vc_o,
//     output logic error_o
// );

//     // Original single-packet FSM kept for reference; replaced by packet metadata FIFO.
//     // enum logic [1:0] {IDLE, VA, SA} ss, ss_next;

//     // New: packet metadata stored per packet so one VC FIFO can hold multiple packets.
//     typedef struct packed {
//         port_t out_port;
//         logic [VC_SIZE-1:0] downstream_vc;
//         logic vc_allocated;
//     } packet_meta_t;

//     // New: reuse BUFFER_SIZE as the metadata queue depth for the minimal implementation.
//     localparam [31:0] META_POINTER_SIZE = $clog2(BUFFER_SIZE);

//     //add, Michael Tan, 20260528
//     flit_novc_t first_flit_novc; //add by Michael Tan, 20260528, no VCs
//     // logic head_valid;//add by Michael Tan, 20260602, test

//     // Original single-packet downstream VC next-state kept for reference.
//     // logic [VC_SIZE-1:0] downstream_vc_next;

//     logic read_cmd, write_cmd;
//     // Original single-packet end marker kept for reference.
//     // logic end_packet, end_packet_next;
//     // logic vc_allocatable_next;
//     // logic error_next;

//     // New: packet metadata circular queue.
//     packet_meta_t meta_mem[BUFFER_SIZE-1:0];
//     logic [META_POINTER_SIZE-1:0] meta_rd_ptr;
//     logic [META_POINTER_SIZE-1:0] meta_wr_ptr;
//     logic [META_POINTER_SIZE:0] num_packets;

//     // New: command wires for metadata FIFO updates.
//     logic meta_push_cmd;
//     logic meta_pop_cmd;
//     logic meta_alloc_cmd;
//     logic meta_full;
//     logic meta_space_available;
//     logic has_packet;
//     logic head_allocated;
//     logic accept_write;
//     logic accept_read;
//     logic write_packet_open;
//     logic write_order_ok;
//     logic is_head_flit;
//     logic is_headtail_flit;
//     logic is_body_flit;
//     logic is_tail_input_flit;
//     logic is_tail_flit;
//     packet_meta_t meta_head;

//     flit_novc_t read_flit;

//     // Original single-packet output port next-state kept for reference.
//     // port_t out_port_next; 

//     circular_buffer #(
//         .BUFFER_SIZE(BUFFER_SIZE)
//     )
//     circular_buffer (
//         .data_i(data_i),
//         .read_i(read_cmd),
//         .write_i(write_cmd),
//         .rst(rst),
//         .clk(clk),

//         // .first_flit_o(first_flit_novc),//

//         .data_o(read_flit),
//         .is_full_o(is_full_o),
//         .is_empty_o(is_empty_o),
//         .on_off_o(on_off_o)
//     );
  
//     /*
//     Sequential logic:
//     - on the rising edge of the reset input signal, reset the state of the
//       finite state machine, the next hop destination and the downstream virtual
//       channel identifier;
//     - on the rising edge of the clock input signal, update the state,
//       the next hop destination and the downstream virtual channel identifier.
//     */
//     // Original single-packet state register block kept for reference.
//     /*
//     always_ff @(posedge clk, posedge rst)
//     begin
//         if(rst)
//         begin
//             ss                  <= IDLE;
//             out_port_o          <= LOCAL;
//             downstream_vc_o     <= 0;
//             end_packet          <= 0;
//             vc_allocatable_o    <= 0;
//             error_o             <= 0;
//         end
//         else
//         begin
//             ss                  <= ss_next;
//             out_port_o          <= out_port_next;
//             downstream_vc_o     <= downstream_vc_next;
//             end_packet          <= end_packet_next;
//             vc_allocatable_o    <= vc_allocatable_next;
//             error_o             <= error_next;
//         end
//     end
//     */

//     /*
//     Combinational logic:
//     - in Idle state, when the input flit is an Head one, the write command is
//       asserted and the buffer is empty, then the next hop destination received
//       in input and associated to the flit is stored, and the next state is set
//       to be Virtual Channel Allocation;
//     - in Virtual Channel Allocation state, when the virtual channel for the
//       downstream router is valid, i.e., the corresponding validity signal is
//       asserted, then the virtual channel identifier is stored and the next
//       state is set to be Switch Allocation;
//     - in Switch Allocation state, when the last flit to read is the Tail one
//       and the read command is asserted, then the next state is set to be Idle.
//     */
//     // Original single-packet control block kept for reference.
//     /*
//     always_comb
//     begin
//         data_o.flit_label = read_flit.flit_label;
// 		data_o.vc_id = downstream_vc_o;
// 		data_o.data = read_flit.data;

//         ss_next = ss;
//         out_port_next = out_port_o;
//         downstream_vc_next = downstream_vc_o;

//         read_cmd = 0;
//         write_cmd = 0;

//         end_packet_next = end_packet;
//         error_next = 0;

//         vc_request_o = 0;
//         switch_request_o = 0;
//         vc_allocatable_next = 0;

//         unique case(ss)
//             IDLE:
//             begin
//                 // if((data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL) & write_i & is_empty_o)
//                 if((data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL) & write_i) //Modify by Michael Tan, 20260604
//                 begin
//                     ss_next = VA;
//                     out_port_next = out_port_i;
//                     // head_valid = 0;//add by Michael Tan, 20260602
//                     write_cmd = 1;//remove by Michael Tan, 20260602
//                 end

//                 //if(vc_valid_i | read_i | ((data_i.flit_label == BODY | data_i.flit_label == TAIL) & write_i) | ~is_empty_o)
//                 if(vc_valid_i | read_i | ((data_i.flit_label == BODY | data_i.flit_label == TAIL) & write_i)) //Modify by Michael Tan, 20260609
//                 begin
//                     error_next = 1;
//                 end
//                 if(write_i & data_i.flit_label == HEADTAIL)
//                 begin
//                     end_packet_next = 1;
//                 end
//             end

//             VA:
//             begin
//                 if(vc_valid_i)
//                 begin
//                     ss_next = SA;
//                     downstream_vc_next = vc_new_i;
//                 end

//                 vc_request_o = 1;
//                 if(write_i & (data_i.flit_label == BODY | data_i.flit_label == TAIL) & ~end_packet)
//                 begin
//                     write_cmd = 1;
//                 end

//                 if((write_i & (end_packet | data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL)) | read_i)
//                 begin
//                     error_next = 1;
//                 end
//                 if(write_i & data_i.flit_label == TAIL)
//                 begin
//                     end_packet_next = 1;
//                 end
//             end

//             SA:
//             begin
//                 if(read_i & (data_o.flit_label == TAIL | data_o.flit_label == HEADTAIL))
//                 begin
//                     ss_next = IDLE;
//                     vc_allocatable_next = 1;
//                     end_packet_next = 0;
//                 end

//                 if(~is_empty_o)
//                 begin
//                     switch_request_o = 1;
//                 end
                    
//                 read_cmd = read_i;
//                 if(write_i & (data_i.flit_label == BODY | data_i.flit_label == TAIL) & ~end_packet)
//                 begin
//                     write_cmd = 1;
//                 end

//                 if((write_i & (end_packet | data_i.flit_label == HEAD | data_i.flit_label == HEADTAIL)) | vc_valid_i)
//                 begin
//                     error_next = 1;
//                 end
//                 if(write_i & data_i.flit_label == TAIL)
//                 begin
//                     end_packet_next = 1;
//                 end
//             end

//             default:
//             begin
//                 ss_next = IDLE;
//                 vc_allocatable_next = 1;
//                 error_next = 1;
//                 end_packet_next = 0;
//             end

//         endcase
//     end
//     */

//     // New: metadata FIFO helpers for the multi-packet-per-VC minimal implementation.
//     // New: metadata queue is full when every metadata entry is occupied.
//     assign meta_full = (num_packets == BUFFER_SIZE);
//     // New: a simultaneous packet pop makes room for a new packet header.
//     assign meta_space_available = ~meta_full | meta_pop_cmd;
//     assign has_packet = (num_packets != 0);
//     assign meta_head = meta_mem[meta_rd_ptr];
//     assign head_allocated = has_packet & meta_head.vc_allocated;
//     assign is_head_flit = (data_i.flit_label == HEAD) | is_headtail_flit;
//     assign is_headtail_flit = (data_i.flit_label == HEADTAIL);
//     assign is_body_flit = (data_i.flit_label == BODY);
//     assign is_tail_input_flit = (data_i.flit_label == TAIL);
//     assign is_tail_flit = (read_flit.flit_label == TAIL) | (read_flit.flit_label == HEADTAIL);
//     // New: reads are accepted only for an allocated head packet and non-empty flit FIFO.
//     assign accept_read = read_i & head_allocated & ~is_empty_o;
//     // New: the write stream may hold many packets, but packet flits must not be interleaved.
//     assign write_order_ok = ((data_i.flit_label == HEAD) & ~write_packet_open & meta_space_available) |
//                             (is_headtail_flit & ~write_packet_open & meta_space_available) |
//                             (is_body_flit & write_packet_open) |
//                             (is_tail_input_flit & write_packet_open);
//     // New: HEAD/HEADTAIL need a free metadata slot; BODY/TAIL need an existing packet.
//     assign accept_write = write_i & (~is_full_o | accept_read) & write_order_ok;
//     assign meta_push_cmd = accept_write & is_head_flit;
//     assign meta_pop_cmd = accept_read & is_tail_flit;
//     assign meta_alloc_cmd = vc_valid_i & has_packet & ~meta_head.vc_allocated;

//     // New: packet metadata FIFO state. Only the head packet is allocated/transmitted.
//     always_ff @(posedge clk, posedge rst)
//     begin
//         if(rst)
//         begin
//             meta_rd_ptr <= 0;
//             meta_wr_ptr <= 0;
//             num_packets <= 0;
//             write_packet_open <= 0;
//             vc_allocatable_o <= 0;
//             error_o <= 0;
//         end
//         else
//         begin
//             vc_allocatable_o <= meta_pop_cmd;
//             error_o <= (write_i & ~accept_write) |
//                        (read_i & (~head_allocated | is_empty_o)) |
//                        (vc_valid_i & (~has_packet | meta_head.vc_allocated));

//             if(meta_alloc_cmd)
//             begin
//                 meta_mem[meta_rd_ptr].downstream_vc <= vc_new_i;
//                 meta_mem[meta_rd_ptr].vc_allocated <= 1'b1;
//             end

//             if(meta_push_cmd)
//             begin
//                 meta_mem[meta_wr_ptr].out_port <= out_port_i;
//                 meta_mem[meta_wr_ptr].downstream_vc <= {VC_SIZE{1'b0}};
//                 meta_mem[meta_wr_ptr].vc_allocated <= 1'b0;
//             end

//             if(accept_write)
//             begin
//                 if(data_i.flit_label == HEAD)
//                     write_packet_open <= 1'b1;
//                 else if(is_tail_input_flit | is_headtail_flit)
//                     write_packet_open <= 1'b0;
//             end

//             unique case({meta_push_cmd, meta_pop_cmd})
//                 2'b10:
//                 begin
//                     meta_wr_ptr <= increase_meta_ptr(meta_wr_ptr);
//                     num_packets <= num_packets + 1;
//                 end
//                 2'b01:
//                 begin
//                     meta_rd_ptr <= increase_meta_ptr(meta_rd_ptr);
//                     num_packets <= num_packets - 1;
//                 end
//                 2'b11:
//                 begin
//                     meta_wr_ptr <= increase_meta_ptr(meta_wr_ptr);
//                     meta_rd_ptr <= increase_meta_ptr(meta_rd_ptr);
//                     num_packets <= num_packets;
//                 end
//                 default:
//                 begin
//                     meta_wr_ptr <= meta_wr_ptr;
//                     meta_rd_ptr <= meta_rd_ptr;
//                     num_packets <= num_packets;
//                 end
//             endcase
//         end
//     end

//     // New: combinational outputs are driven by the head metadata entry.
//     always_comb
//     begin
//         data_o.flit_label = read_flit.flit_label;
//         data_o.vc_id = head_allocated ? meta_head.downstream_vc : {VC_SIZE{1'b0}};
//         data_o.data = read_flit.data;

//         out_port_o = has_packet ? meta_head.out_port : LOCAL;
//         downstream_vc_o = head_allocated ? meta_head.downstream_vc : {VC_SIZE{1'b0}};

//         vc_request_o = has_packet & ~meta_head.vc_allocated;
//         switch_request_o = head_allocated & ~is_empty_o;

//         read_cmd = accept_read;
//         write_cmd = accept_write;
//     end

//     // New: metadata queue pointer increment.
//     function logic [META_POINTER_SIZE-1:0] increase_meta_ptr (input logic [META_POINTER_SIZE-1:0] ptr);
//         if(ptr == BUFFER_SIZE-1)
//             increase_meta_ptr = 0;
//         else
//             increase_meta_ptr = ptr + 1;
//     endfunction

// endmodule
