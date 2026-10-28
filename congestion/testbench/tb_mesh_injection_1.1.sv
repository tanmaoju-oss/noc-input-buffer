//===================================================================================
// 模块: tb_mesh_injection 2.0
// 功能: 基于 Mesh 拓扑结构的 NoC（片上网络）注入测试平台
//       用于评估不同注入率下的网络性能（延迟，吞吐量等）
//       支持多种路由算法 (XY, YX, OneAware, TwoAware 等)
//       支持多种流量模式 (Random, Transpose1, Hotspot)
//===================================================================================

`timescale 1ns / 1ps

// 导入 NoC 参数包，包含 VC 数量，端口数量，flit 类型等定义
import noc_params::*;

//===================================================================================
// 测试平台模块定义
//===================================================================================
module tb_mesh #(
    //---------- 缓冲区参数 ----------
    parameter BUFFER_SIZE = 8,          // 每个 VC（虚拟通道）的缓冲区深度（以 flit 为单位）
    //---------- Mesh 网络尺寸 ----------
    parameter MESH_SIZE_X = 13,          // Mesh 网络 X 方向节点数
    parameter MESH_SIZE_Y = 13,          // Mesh 网络 Y 方向节点数，总节点数=MESH_SIZE_X*MESH_SIZE_Y
    //---------- 路由算法参数 ----------
    parameter ALGORITHM = 4,            // 路由算法：0=XY,1=YX,2=OE,3=OneAware,4=TwoAware,5=ThreeAware
    parameter AGGREGATION = 0,         // 拥塞感知聚合算法：0=平均1=最大2=加权
    parameter int DECISION_REFERENCE = 0, // 决策参考指标：0=每方向总占用数 1=每方向拥塞等级 2=节点总流量  
    //---------- 测试模块参数 ---------- 
    //---------- 数据包长度 ----------
    parameter FLIT_LEN = 4,             // 每个数据包的 flit 数量：1 HEAD+(FLIT_LEN-2) BODY+1 TAIL
    //---------- 流量模式配置 ----------
    parameter string TRAFFIC_MODEL = "Random",  // 流量模式：“转置”/“随机”/“热点”
    parameter int    HOT_X = 2,         // Hotspot 模式的目标节点 X 坐标 (0~MESH_SIZE_X-1)
    parameter int    HOT_Y = 2,         // Hotspot 模式的目标节点 Y 坐标 (0~MESH_SIZE_Y-1)
    parameter int    HOTSPOT_PER = 20,  // Hotspot 模式中发往热点结点的概率百分比 (0~100)
    //---------- 测试参数 ----------
    parameter real   INJECTION_RATE = 0.11,  // 单次测试的注入率（数据包/节点/周期）
    parameter int    SIM_CYCLE = 4000,      // 单次测试的仿真周期数
    parameter int    RAND_SEED = 1234501,   // 随机数种子：0=使用默认种子，!=0=使用指定种子
    //---------- 多速率测试参数 ----------
    parameter string INJECTION_RATES = ""         //  "0.02,0.04,0.06,0.08,0.1,0.12,0.14,0.16,0.18,0.2,0.22,0.24"
);

    //==================================================================
    // 信号定义
    //==================================================================
    // 时钟信号（周期10ns）和复位信号（高电平有效）
    logic clk, rst;

    //---------- 测试平台 -> DUT 信号 ----------
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_cmd;          // VC 开关控制：1=VC 开启可用0=VC 关闭
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_cmd;    // VC 可分配标：1=VC 可分配0=不可分配
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_cmd;                      // 数据有效标：1=data_cmd 有效0=无效
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_cmd;                         // 注入到 DUT 的 flit 数据
    //---------- DUT -> 测试平台信号 ----------
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o;                        // 输出数据有效标
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_o;           // 输出 VC 状态（ DUT 反馈）
    logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o;      // 输出 VC 可分配状态
    logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0]; // 错误指示信号
    flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o;                           //  DUT 输出的 flit 数据
    //==================================================================
    // 测试变量和数据结构
    //==================================================================
    int packet_cnt[MESH_SIZE_X][MESH_SIZE_Y];           // 每个节点已生成的数据包计数器（用于生成packet_id和VC分配）
    int body_len = (FLIT_LEN - 2 > 0) ? FLIT_LEN - 2 : 0;  // BODY flit 数量=FLIT_LEN-2
    flit_t injection_fifo[MESH_SIZE_X][MESH_SIZE_Y][$]; // FIFO 队列，存储待注入的flit
    int pkt_enqueue_cycle[MESH_SIZE_X][MESH_SIZE_Y][int]; // 记录数据包HEAD入队时（用于计算延迟）
    int one_packet_cycle[$];            // 存储成功到达的延迟数据
    //---------- 计变量 ----------
    int cycle_cnt;                      // 当前仿真周期计数器
    int injection_packet;              // 总生成的数据包数
    int injection_packet_valid_num;    // 成功到达目的的数据包数
    int total_arrived_packets;         // total packets arrived at destination
    int injection_packet_invalid_num;  // 到达目的的数据包数（丢包数）
    int total_possible_packets;        // 理论最大可能数据包数
    real injection_packet_theory;      // 理论注入数据包数
    int sum_packet_cycle;              // 有成功到达数据包的延迟总和
    real average_packet_cycle;         // 平均延迟=sum/valid_num
    real injection_rate;               // 当前测试的注入率
    int sim_cycle;                     // 当前测试的仿真周期数
    real rate_results[string];         // 注入率->平均延迟映射
    int  rate_valid_packets[string];   // 注入率->到达包数映射
    int unsigned rand_state = 0;        // LCG 随机数状态

    //==================================================================
    // 实例化待测设计 DUT
    //==================================================================
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_debug;
    mesh #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .MESH_SIZE_X(MESH_SIZE_X),
        .MESH_SIZE_Y(MESH_SIZE_Y),
        .ALGORITHM(ALGORITHM),
        .AGGREGATION(AGGREGATION),
        .DECISION_REFERENCE(DECISION_REFERENCE)
    ) dut_mesh (
        .clk(clk), .rst(rst),
        .is_on_off_i(is_on_off_cmd),
        .is_allocatable_i(is_allocatable_cmd),
        .data_i(data_cmd), .is_valid_i(is_valid_cmd),
        .data_o(data_o), .is_valid_o(is_valid_o),
        .is_on_off_o(is_on_off_o),
        .is_allocatable_o(is_allocatable_o),
        .error_o(error_o),
        .metrics_debug_o(metrics_debug)
    );

    //==================================================================
    // 时钟生成：周期10ns，100MHz
    //==================================================================
    always #5 clk = ~clk;

    //==================================================================
    // 仿真初始化流程
    //==================================================================
    initial begin
        $dumpfile("out.vcd");
        $dumpvars(0, tb_mesh);
        // 初始化所有信号和数据结构
        initialize();
        // 释放复位信号
        clr_rst();
        // 执行测试
        test();
        #200 $finish;
    end

    //==============================================================================
// 任务: initialize（初始化）
// 功能：将所有信号和数据结构恢复为初始状态，准备开始新一轮测试。
//   1) 时钟初始化为低电平，复位信号置为有效
//   2) 遍历所有节点，将VC开关/可分配/数据信号置为初值
//   3) 清空FIFO队列，将每个节点的数据包计数器清零
//   4) 重置全局统计变量（cycle_cnt, injection_packet等）
//==============================================================================
    task initialize();
        // 时钟初始化为低电平
        clk <= 0;
        // 复位信号置为高电平有效
        rst = 1;
        // 遍历所有节点，逐行初始化
        for (int x = 0; x < MESH_SIZE_X; x++) begin
            for (int y = 0; y < MESH_SIZE_Y; y++) begin
                is_on_off_cmd[x][y]   <= {VC_NUM{1'b1}};      // 全部开启
                is_allocatable_cmd[x][y] <= {VC_NUM{1'b1}};    // 全部可分配
                is_valid_cmd[x][y]    <= 1'b0;                 // 无有效数据
                data_cmd[x][y]        <= 'x;                   // 未知态
                injection_fifo[x][y].delete();                 // 清空FIFO
                packet_cnt[x][y]      <= 0;                    // 计数器清零
            end
        end
        // 重置全局计数器与统计变量
        cycle_cnt = 0;
        injection_packet = 0;
        sum_packet_cycle = 0;
        average_packet_cycle = 0.0;
        one_packet_cycle.delete();
    endtask

    //==============================================================================
// 任务: clr_rst（释放复位）
// 功能：在时钟上升沿将复位信号置为无效，使DUT开始正常工作。
//   1) 等待时钟上升沿
//   2) 将rst信号置为0，释放复位
//==============================================================================
    task clr_rst();
        @(posedge clk);
        rst <= 0;
    endtask

    //==============================================================================
// 函数: parse_rates_string（解析注入率字符串）
// 功能：将逗号分隔的注入率字符串解析为实数数组，例如"0.02,0.04"→[0.02,0.04]。
//   1) 逐个提取逗号分隔的token
//   2) 去除token前后空格
//   3) 将token转换为实数并存入数组
// 输入：s - 待解析的字符串
// 输出：arr - 存储解析结果的实数数组
// 返回：实际解析出的速率数量
//==============================================================================
    function automatic int parse_rates_string(string s, ref real arr[32]);
        int count = 0;
        string token, remaining = s;
        int comma_pos;
        // 循环解析每个逗号分隔的token
        while (remaining.len() > 0) begin
        // 查找逗号位置
            comma_pos = -1;
            for (int i = 0; i < remaining.len(); i++) begin
                if (remaining[i] == ",") begin comma_pos = i; break; end
            end
            if (comma_pos >= 0) begin
        // 提取逗号前的token
                token = remaining.substr(0, comma_pos);
                remaining = remaining.substr(comma_pos+1, remaining.len()-1);
            end else begin
                token = remaining; remaining = "";
            end
            if (token.len() > 0) begin
        // 去除前后空格
                while (token.len() > 0 && token[0] == " ") token = token.substr(1, token.len()-1);
                while (token.len() > 0 && token[token.len()-1] == " ") token = token.substr(0, token.len()-1);
        // 转换为实数并存入数组
                if (token.len() > 0) begin arr[count] = token.atoreal(); count++; end
            end
        end
        return count;
    endfunction

    //==============================================================================
// 任务: clear_test_stats（清空统计）
// 功能：在每次新速率测试前，重置所有统计数据结构和FIFO队列。
//   1) 清空所有节点的FIFO队列和数据包计数器
//   2) 重置全局统计变量为0
//   3) 清空数据包入队时间记录表
//==============================================================================
    task clear_test_stats();
        // 遍历所有节点，根据注入率决定是否生成数据包
        for (int x = 0; x < MESH_SIZE_X; x++) begin
            for (int y = 0; y < MESH_SIZE_Y; y++) begin
                injection_fifo[x][y].delete();
                packet_cnt[x][y]      <= 0;
                is_valid_cmd[x][y]    <= 1'b0;
            end
        end
        cycle_cnt = 0;
        injection_packet = 0;
        sum_packet_cycle = 0;
        average_packet_cycle = 0.0;
        one_packet_cycle.delete();
        for (int x = 0; x < MESH_SIZE_X; x++) begin
            for (int y = 0; y < MESH_SIZE_Y; y++) begin
                pkt_enqueue_cycle[x][y].delete();
            end
        end
    endtask

    //==============================================================================
// 任务: test（主测试）
// 功能：根据INJECTION_RATES参数，决定执行单速率或多速率测试。
//   1) 若INJECTION_RATES为空，执行单次速率测试（使用INJECTION_RATE）
//   2) 否则解析INJECTION_RATES字符串，依次执行每个速率的测试
//   3) 所有速率测试完成后调用display_summary显示汇总结果
//==============================================================================
    task test();
        if (INJECTION_RATES == "") begin
            sim_cycle = SIM_CYCLE;
            run_single_rate(INJECTION_RATE);
        end else begin
            automatic real rates[32];
            automatic int num_rates;
            sim_cycle = SIM_CYCLE;
            num_rates = parse_rates_string(INJECTION_RATES, rates);
            $display("=== tb_mesh_injection 2.0 - Multi-Rate Test ===");
            $display("Mesh size: %0d x %0d", MESH_SIZE_X, MESH_SIZE_Y);
            $display("Traffic Model: %s", TRAFFIC_MODEL);
            $display("Routing Algorithm: %0d (0=XY,1=YX,2=OE,3=OneAware,4=TwoAware,5=ThreeAware)", ALGORITHM);
            $display("Aggregation: %0d (0=avg,1=max,2=weighted)", AGGREGATION);
            $display("sim_cycle = %0d cycles per rate", SIM_CYCLE);
            $display("Number of rates: %0d", num_rates);
            $display("");
            for (int i = 0; i < num_rates; i++) begin
                run_single_rate(rates[i]);
            end
            display_summary();
        end
    endtask

    //==============================================================================
// 任务: run_single_rate（单速率测试）
// 功能：在指定注入率下执行完整测试流程。
//   1) 初始化统计数据和随机数种子
//   2) 循环sim_cycle个周期：随机生成数据包并注入到NoC
//   3) 停止注入，再等待500个周期排空网络
//   4) 调用compute_results计算并显示统计结果
//==============================================================================
    task run_single_rate(real rate);
        injection_rate = rate;
        if (RAND_SEED != 0) rand_state = RAND_SEED;
        clear_test_stats();
        total_possible_packets = MESH_SIZE_X * MESH_SIZE_Y * sim_cycle / FLIT_LEN;
        injection_packet_theory = MESH_SIZE_X * MESH_SIZE_Y * sim_cycle * injection_rate;
        body_len = (FLIT_LEN - 2 > 0) ? FLIT_LEN - 2 : 0;
        $display("--- rate=%0.3f --- (Algorithm=%0d)", injection_rate, ALGORITHM);

        //---- 数据包生成阶段：循环sim_cycle个周期 ----
        for (cycle_cnt = 0; cycle_cnt < sim_cycle; cycle_cnt++) begin
            @(posedge clk);
            monitor_outputs();
            for (int x = 0; x < MESH_SIZE_X; x++) begin
                for (int y = 0; y < MESH_SIZE_Y; y++) begin
                    if ((my_rand() / 4294967296.0) < injection_rate)
                        enqueue_packet(x, y);
                end
            end
            inject_from_fifo();
        end

        @(posedge clk);
        for (int x = 0; x < MESH_SIZE_X; x++)
            for (int y = 0; y < MESH_SIZE_Y; y++)
        //---- 排空阶段：停止注入，等待网络排空 ----
                is_valid_cmd[x][y] <= 1'b0;
        // 等待500个周期，确保所有数据包都能到达目的地
        repeat (500) begin
            @(posedge clk);
            cycle_cnt++;
            monitor_outputs();
        end
        // 计算并显示统计结果
        compute_results();
    endtask

    //==============================================================================
// 任务: enqueue_packet（生成数据包）
// 功能：在指定节点生成一个完整的数据包（HEAD+BODY+TAIL）并存入FIFO队列。
//   1) 分配数据包ID和VC ID（使用轮询方式保证负载均衡）
//   2) 根据流量模式（Transpose1/Random/Hotspot）计算目标节点坐标
//   3) 生成HEAD flit并压入FIFO（携带源地址/目标地址/包ID等信息）
//   4) 生成BODY flit并压入FIFO
//   5) 生成TAIL flit并压入FIFO
//==============================================================================
    task enqueue_packet(input int x, input int y);
        int pid, vc_id, x_dest, y_dest;
        // 分配数据包ID（基于该节点已生成的包数量）
        pid = packet_cnt[x][y];
        packet_cnt[x][y] = pid + 1;
        // 使用轮询方式分配VC，保证负载均衡
        vc_id = pid % VC_NUM;
        pkt_enqueue_cycle[x][y][pid] = cycle_cnt;

        // 根据流量模式计算目标节点坐标
        if (TRAFFIC_MODEL == "Transpose1") begin
            x_dest = MESH_SIZE_X - 1 - y;
            y_dest = MESH_SIZE_Y - 1 - x;
        end else if (TRAFFIC_MODEL == "Random") begin
            do begin x_dest = my_rand() % MESH_SIZE_X; y_dest = my_rand() % MESH_SIZE_Y; end
            while (x_dest == x && y_dest == y);
        end else if (TRAFFIC_MODEL == "Hotspot") begin
            if ((my_rand() % 100) < HOTSPOT_PER) begin
                x_dest = HOT_X; y_dest = HOT_Y;
            end else begin
                do begin x_dest = my_rand() % MESH_SIZE_X; y_dest = my_rand() % MESH_SIZE_Y; end
                while ((x_dest == x && y_dest == y) || (x_dest == HOT_X && y_dest == HOT_Y));
            end
        end else begin
            x_dest = MESH_SIZE_X - 1 - y;
            y_dest = MESH_SIZE_Y - 1 - x;
        end

        begin
        //---- 生成HEAD flit并压入FIFO ----
            flit_t head_flit;
            head_flit.flit_label = HEAD;
            head_flit.vc_id = vc_id;
            head_flit.data.head_data = '{x, y, x_dest, y_dest, pid, 0, {HEAD_PAYLOAD_SIZE{1'b0}}};
            injection_fifo[x][y].push_back(head_flit);
        end
        injection_packet++;

        for (int b = 0; b < body_len; b++) begin
        //---- 生成BODY flits并压入FIFO ----
            flit_t body_flit;
            body_flit.flit_label = BODY;
            body_flit.vc_id = vc_id;
            body_flit.data.bt_pl = b;
            injection_fifo[x][y].push_back(body_flit);
        end

        begin
        //---- 生成TAIL flit并压入FIFO ----
            flit_t tail_flit;
            tail_flit.flit_label = TAIL;
            tail_flit.vc_id = vc_id;
            tail_flit.data.head_data = '{x, y, x_dest, y_dest, pid, 0, {HEAD_PAYLOAD_SIZE{1'b0}}};
            injection_fifo[x][y].push_back(tail_flit);
        end
    endtask

    //==============================================================================
// 任务: inject_from_fifo（FIFO注入）
// 功能：从每个节点的FIFO队列取出flit注入到NoC中。
//   1) 检查FIFO是否非空
//   2) 检查对应VC是否处于开启状态（由DUT的流控反馈决定）
//   3) 若条件满足，将FIFO队首的flit注入到data_cmd并弹出
//   4) 若VC未开启，等待下一个周期再尝试
//==============================================================================
    task inject_from_fifo();
        for (int x = 0; x < MESH_SIZE_X; x++) begin
            for (int y = 0; y < MESH_SIZE_Y; y++) begin
        // 检查FIFO是否非空
                if (injection_fifo[x][y].size() > 0) begin
                    automatic int vcid = injection_fifo[x][y][0].vc_id;
        // 检查VC是否开启（由DUT反馈）
                    if (is_on_off_o[x][y][vcid]) begin
                        data_cmd[x][y] <= injection_fifo[x][y][0];
                        is_valid_cmd[x][y] <= 1'b1;
        // 弹出已注入的flit
                        void'(injection_fifo[x][y].pop_front());
                    end else begin
                        is_valid_cmd[x][y] <= 1'b0;
                    end
                end else begin
                    is_valid_cmd[x][y] <= 1'b0;
                end
            end
        end
    endtask

    //==============================================================================
// 任务: monitor_outputs（监测输出）
// 功能：监测DUT的输出端口，当收到TAIL或HEADTAIL flit时计算数据包延迟。
//   1) 遍历所有输出端口，检查is_valid_o是否有效
//   2) 若为TAIL/HEADTAIL，提取源节点坐标和数据包ID
//   3) 计算延迟 = 当前周期数 - 入队周期数
//   4) 将延迟数据加入one_packet_cycle列表并删除入队记录
//==============================================================================
    task monitor_outputs();
        for (int xd = 0; xd < MESH_SIZE_X; xd++) begin
            for (int yd = 0; yd < MESH_SIZE_Y; yd++) begin
                if (is_valid_o[xd][yd]) begin
        // 当收到TAIL或HEADTAIL flit时，表示数据包已完成传输
                    if (data_o[xd][yd].flit_label == TAIL || data_o[xd][yd].flit_label == HEADTAIL) begin
                        int xs = data_o[xd][yd].data.head_data.x_source;
                        int ys = data_o[xd][yd].data.head_data.y_source;
                        int pid = data_o[xd][yd].data.head_data.packet_id;
                        if (pkt_enqueue_cycle[xs][ys].exists(pid)) begin
        // 计算延迟 = 到达周期 - 入队周期
                            int latency = cycle_cnt - pkt_enqueue_cycle[xs][ys][pid];
        // 删除该数据包的入队记录，避免重复统计
                            pkt_enqueue_cycle[xs][ys].delete(pid);
        // 将延迟数据加入统计列表
                            one_packet_cycle.push_back(latency);
                        end
                    end
                end
            end
        end
    endtask

    //==============================================================================
// 任务: compute_results（计算结果）
// 功能：在当前注入率测试结束后，根据 one_packet_cycle 数组计算统计结果。
//   1) 计算有效数据包数（valid）和无效数据包数（invalid）
//   2) 求和所有延迟并计算平均延迟（average_packet_cycle）
//   3) 将本次测试的结果存入 rate_results 和 rate_valid_packets（用于多注入率汇总）
//==============================================================================
    task compute_results();
        automatic int num_latency = one_packet_cycle.size();
        injection_packet_valid_num = num_latency;
        total_arrived_packets = num_latency;
        injection_packet_invalid_num = total_possible_packets - injection_packet_valid_num;
        $display("");
        $display("==========================================");
        $display("Injection Results:");
        $display("Routing Algorithm: %0d (0=XY,1=YX,2=OE,3=OneAware,4=TwoAware,5=ThreeAware)", ALGORITHM);
        $display("Mesh size: %0d x %0d", MESH_SIZE_X, MESH_SIZE_Y);                
        $display("  total_possible_packets       = %0d", total_possible_packets);
        $display("  injection_packet_theory      = %0.3f", injection_packet_theory);
        $display("  total_arrived_packets        = %0d", total_arrived_packets);
        $display("  injection_packet_valid_num   = %0d", injection_packet_valid_num);
        $display("  injection_packet_invalid_num = %0d", injection_packet_invalid_num);
        if (num_latency > 0) begin
            sum_packet_cycle = 0;
            foreach (one_packet_cycle[i]) sum_packet_cycle += one_packet_cycle[i];
            average_packet_cycle = real'(sum_packet_cycle) / real'(num_latency);
            $display("");            
            $display("When injection_rate = %0.3f packet/node/cycle:  average_packet_cycle = %0.3f cycles",
                     injection_rate, average_packet_cycle);
            rate_valid_packets[$sformatf("%0.3f", injection_rate)] = num_latency;
            rate_results[$sformatf("%0.3f", injection_rate)] = average_packet_cycle;
        end else begin
            $display("  No packets arrived at destination.");
        end
        $display("==========================================");
    endtask

    //==============================================================================
// 任务: display_summary（显示汇总）
// 功能：在所有速率测试完成后，显示注入率与平均延迟的汇总结果。
//   1) 遍历rate_results映射表
//   2) 打印每个注入率对应的平均延迟
//==============================================================================
    task display_summary();
        $display("");
        $display("============================================================================");
        $display("         Result Summary");
        $display("============================================================================");
        $display("  injection_rate : average_packet_cycle");
        $display("  --------------   --------------------");
        foreach (rate_results[s]) begin
            // $display("  %s : %0.3f cycles  (valid=%0d)", s, rate_results[s], rate_valid_packets[s]);
            $display("  %s : %0.3f cycles", s, rate_results[s]);            
        end
        $display("============================================================================");
    endtask


    //==============================================================================
// 函数: my_rand（随机数生成）
// 功能：使用线性同余算法（LCG）生成32位伪随机数。
//   公式：X_{n+1} = (a * X_n + c) mod 2^32
//   参数：a=1103515245, c=12345
//   可根据RAND_SEED参数控制随机序列的初始值
//==============================================================================
    function int unsigned my_rand();
        rand_state = (rand_state * 1103515245 + 12345);
        return rand_state;
    endfunction

endmodule
