// 导入NoC参数包（包含VC_SIZE、PORT_NUM等全局参数）
import noc_params::*;

/*
 * 模块名称：input_buffer
 * 功能描述：NoC路由器输入缓冲区模块
 * 主要功能：
 *   1. 存储到达的flit数据（使用循环缓冲区）
 *   2. 支持多个数据包在同一VC中排队（通过元数据FIFO）
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
    //Modify store candidates until allocation and lock granted direction, Michael Tan, 20261028
    input logic [PORT_NUM-1:0] candidates_i,
    input port_t granted_port_i,
    output logic [PORT_NUM-1:0] candidates_o,
    input rst,                       // 复位信号（高有效）
    input clk,                       // 时钟信号
    
    // ========== 输出信号 ==========
    output flit_t data_o,            // 输出数据（含VC ID）
    output logic is_full_o,          // 缓冲区满标志
    output logic is_empty_o,         // 缓冲区空标志
    output logic on_off_o,           // 开关控制信号（流控）
    output port_t out_port_o,        // 输出端口
    output logic vc_request_o,       // VC请求信号（用于VA阶段）
    output logic switch_request_o,   // 开关请求信号（用于SA阶段）
    output logic vc_allocatable_o,   // VC可分配信号（释放VC）
    output logic [VC_SIZE-1:0] downstream_vc_o,  // 下游VC ID
    output logic error_o,            // 错误标志
    output logic [$clog2(BUFFER_SIZE):0] priority_usage_o  // 【修改】添加占用数输出，用于拥塞信息收集
);

    // ========== 类型定义 ==========
    /*
     * 数据包元数据结构
     * 每个数据包在元数据FIFO中占一个条目
     * 用于支持多数据包在同一VC中排队
     */
    typedef struct packed {
        port_t out_port;                      // 数据包的目的输出端口
        logic [PORT_NUM-1:0] candidates;//Modify per-packet legal candidates, Michael Tan, 20261028
        logic [VC_SIZE-1:0] downstream_vc;    // 下游分配的VC ID
        logic vc_allocated;                   // VC是否已分配标记
    } packet_meta_t;

    // 元数据指定位宽计算
    localparam [31:0] META_POINTER_SIZE = $clog2(BUFFER_SIZE);

    // ========== 信号声明 ==========
    flit_novc_t first_flit_novc;  // 第一个flit（未使用VC，由Michael Tan添加，20260528）
    logic read_cmd;               // 内部读命令
    logic write_cmd;              // 内部写命令
    // ========== 元数据FIFO信号 ==========
    packet_meta_t meta_mem[BUFFER_SIZE-1:0];  // 元数据存储阵列
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
    flit_novc_t read_flit;        // 从循环缓冲区读出的flit

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
        .on_off_o(on_off_o),
        .num_flits_o(priority_usage_o)  // 【修改】连接占用数输出
    );
  
    // ========================================
    // 原始单数据包FSM代码已被注释掉
    // 保留作为参考，但不再使用
    // 新实现使用元数据FIFO支持多数据包
    // ========================================

    // ========== 组合逻辑：元数据FIFO状态判断 ==========
    
    // 元数据FIFO满标记
    assign meta_full = (num_packets == BUFFER_SIZE);
    
    // 元数据FIFO有空间（同时出队可以为入队腾出空间）
    assign meta_space_available = ~meta_full | meta_pop_cmd;
    
    // 是否有排队的数据包
    assign has_packet = (num_packets != 0);
    
    // 队首元数据
    assign meta_head = meta_mem[meta_rd_ptr];
    assign candidates_o = has_packet ? meta_head.candidates : '0;//Modify export head candidate mask, Michael Tan, 20261028
    
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
     * 4. VC可分配标记
     * 5. 错误标记
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
            //vc_allocatable_o <= ~is_full_o;//Original, Michael Tan, 20261028
            vc_allocatable_o <= meta_pop_cmd;//Modify release VC only after packet-tail dequeue, Michael Tan, 20261028
            
            // 错误检测
            error_o <= (write_i & ~accept_write) |           // 写操作被拒绝
                       (read_i & (~head_allocated | is_empty_o)) |  // 读操作无效
                       (vc_valid_i & (~has_packet | meta_head.vc_allocated));  // VC分配无效
            
            // VC分配：更新队首数据包的VC信息
            if(meta_alloc_cmd)
            begin
                meta_mem[meta_rd_ptr].downstream_vc <= vc_new_i;
                meta_mem[meta_rd_ptr].vc_allocated <= 1'b1;
                meta_mem[meta_rd_ptr].out_port <= granted_port_i;//Modify lock port with successful VC grant, Michael Tan, 20261028
            end
            
            // 新数据包入队：存储元数据
            if(meta_push_cmd)
            begin
                meta_mem[meta_wr_ptr].out_port <= out_port_i;
                meta_mem[meta_wr_ptr].candidates <= candidates_i;//Modify preserve legal alternatives while queued, Michael Tan, 20261028
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
        data_o.flit_label = read_flit.flit_label;
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