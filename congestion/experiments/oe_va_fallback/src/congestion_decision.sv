// ============================================================================
// 拥塞判决模块（congestion_decision）
// 功能描述：根据状态信息收集模块输出的决策参考指标、算法和聚合方式，
//          选择拥塞最小的路由方向输出。
//          支持 OneAware（1跳）、TwoAware（2跳）、ThreeAware（3跳，预留）。
// 作者：Michael Tan
// 日期：2026-07-30
// ============================================================================
import noc_params::*;

// NOTE: OE routing moved to rc_unit_Xiugai2.sv; random choice between two directions.

module congestion_decision #(
    parameter X_CURRENT = 0,           // 当前路由器 X 坐标
    parameter Y_CURRENT = 0,           // 当前路由器 Y 坐标
    parameter DEST_ADDR_SIZE_X = 4,    // 目的地址 X 位宽
    parameter DEST_ADDR_SIZE_Y = 4,    // 目的地址 Y 位宽
    parameter ALGORITHM = 3,           // 拥塞感知算法（3=OneAware, 4=TwoAware, 5=ThreeAware）
    parameter AGGREGATION = 0,         // 聚合算法（0=平均, 1=最大, 2=加权）
    parameter DECISION_REFERENCE = 0,  // 决策参考指标（0=每方向总占用数, 1=每方向拥塞等级, 2=节点总流量）
    parameter WEIGHT_HOP1 = 7,         // 加权第一跳权重（代表 0.7）
    parameter WEIGHT_HOP2 = 3,         // 加权第二跳权重（代表 0.3）
    parameter WEIGHT_HOP3 = 0          // 加权第三跳权重（代表 0.0，预留）
)(
    input logic [DEST_ADDR_SIZE_X-1:0] x_dest_i,       // 目的节点 X
    input logic [DEST_ADDR_SIZE_Y-1:0] y_dest_i,       // 目的节点 Y
    input logic [DEST_ADDR_SIZE_X-1:0] x_source_i,     // 源节点 X
    input logic [DEST_ADDR_SIZE_Y-1:0] y_source_i,     // 源节点 Y
    input flit_label_t flit_label_i,                   // flit 标签
    input metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_i,  // 全局决策参考指标
    output port_t out_port_o                           // 选择的路由方向
);

    // 计算相对偏移
    wire signed [DEST_ADDR_SIZE_X-1:0] x_offset;
    wire signed [DEST_ADDR_SIZE_Y-1:0] y_offset;
    assign x_offset = x_dest_i - X_CURRENT;
    assign y_offset = y_dest_i - Y_CURRENT;

    // 候选方向：X 方向和 Y 方向
    port_t x_candidate;  // EAST 或 WEST
    port_t y_candidate;  // NORTH 或 SOUTH





    // ---- 获取候选方向的决策参考指标（x_flits / y_flits 的表征值）----
    // 注：在 Verilog 网格中，Y 坐标越往南越大
    // 按 DECISION_REFERENCE 参数选择指标（0=每方向总占用数, 1=每方向拥塞等级, 2=节点总流量），
    // 分支方式与 agg2 按 AGGREGATION 分支的实现保持一致。
    function automatic logic [15:0] get_decision_metric(
        input int nx, input int ny, input port_t dir
    );
        if (nx < 0 || nx >= MESH_SIZE_X || ny < 0 || ny >= MESH_SIZE_Y)
            return 16'd0;  // 越界返回 0（不拥塞）
        else begin
            if (DECISION_REFERENCE == 0)
                return metrics_i[nx][ny].per_dir_total_occupancy[dir];
            else if (DECISION_REFERENCE == 2)
                return metrics_i[nx][ny].node_total_flow;
            else
                return metrics_i[nx][ny].per_dir_congestion_level[dir];
        end
    endfunction

    // ---- 两跳聚合函数 ----
    // 根据 AGGREGATION 参数（0=平均and求和, 1=最大, 2=加权）合并两跳拥塞值
    function automatic logic [15:0] agg2(
        input logic [15:0] h1,
        input logic [15:0] h2
    );
        if (AGGREGATION == 0)
            return h1 + h2;                      // 平均（和比较）
        else if (AGGREGATION == 1)
            return (h1 > h2) ? h1 : h2;          // 最大
        else
            return h1 * WEIGHT_HOP1 + h2 * WEIGHT_HOP2;  // 加权
    endfunction



    // ---- 判断候选方向并计算拥塞感知路由 ----
    always_comb begin
        // ---- 第一步：确定 X/Y 候选方向 ----
        unique if (x_dest_i < X_CURRENT)
            x_candidate = WEST;
        else if (x_dest_i > X_CURRENT)
            x_candidate = EAST;
        else
            x_candidate = LOCAL;

        unique if (y_dest_i < Y_CURRENT)
            y_candidate = NORTH;
        else if (y_dest_i > Y_CURRENT)
            y_candidate = SOUTH;
        else
            y_candidate = LOCAL;

        out_port_o = LOCAL;

        // ---- 第二步：仅 HEAD/HEADTAIL 时做拥塞感知路由 ----
        if (flit_label_i inside {HEAD, HEADTAIL}) begin
            // 情况1：已经到达（同时在 X 和 Y 方向到达）
            if (x_candidate == LOCAL && y_candidate == LOCAL) begin
                out_port_o = LOCAL;
            end else if (x_candidate == LOCAL) begin
                // 情况2：X 方向已到达，只走 Y 方向
                out_port_o = y_candidate;
            end else if (y_candidate == LOCAL) begin
                // 情况3：Y 方向已到达，只走 X 方向
                out_port_o = x_candidate;
            end else begin
                // 情况4：两个方向都需要走，根据 ALGORITHM 进行拥塞感知决策
                unique case (ALGORITHM)
                    // ========== OneAware：一跳拥塞感知 ==========
                    3: begin
                        logic signed [DEST_ADDR_SIZE_X:0] e0;
                        logic signed [DEST_ADDR_SIZE_Y:0] e1;
                        logic [1:0] nanbei;   // 0=未设置, 1=北候选, 2=南候选
                        logic       dongxi;   // 0=东西向不需要, 1=东西向仍需要
                        logic [15:0] x_flits;
                        logic [15:0] y_flits;

                        // ---- 步骤1：计算相对偏移 ----
                        e0 = x_dest_i - X_CURRENT;
                        e1 = y_dest_i - Y_CURRENT;

                        x_flits = 0;
                        y_flits = 0;
                        nanbei = 2'b00;
                        dongxi = 1'b0;

                        // ---- 步骤2：同一列 -> 直接走 Y 方向 ----
                        if (e0 == 0) begin
                            if (y_dest_i < Y_CURRENT)
                                out_port_o = NORTH;
                            else
                                out_port_o = SOUTH;

                        // ---- 步骤3：目的地在东侧 ----
                        end else if (x_dest_i > X_CURRENT) begin
                            if (e1 == 0) begin
                                out_port_o = EAST;
                            end else begin
                                // OE约束：只能在奇数列或源节点转弯
                                if ((X_CURRENT % 2 == 1) || (X_CURRENT == x_source_i)) begin
                                // if (X_CURRENT % 2 == 1) begin
                                    if (y_dest_i < Y_CURRENT) begin
                                        // 目的地在此节点北侧（nanbei=1）
                                        nanbei = 2'b01;                                         
                                            y_flits = get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH);
                                    end else begin
                                        // 目的地在此节点南侧（nanbei=2）
                                        nanbei = 2'b10;
                                            y_flits = get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH);
                                    end
                                end
                                // 目的地在奇数列或X距离>1 -> 仍需往东
                                if ((x_dest_i % 2 == 1) || (e0 != 1)) begin
                                    dongxi = 1'b1;
                                            x_flits = get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST);                                    
                                end
                                // ---- 方向选择 ----
                                if (dongxi) begin
                                    if (nanbei != 2'b00) begin
                                        if (x_flits < y_flits)
                                            out_port_o = EAST;
                                        else if (nanbei == 2'b01)
                                            out_port_o = NORTH;
                                        else
                                            out_port_o = SOUTH;
                                    end else begin
                                        out_port_o = EAST;
                                    end
                                end else begin
                                    if (nanbei == 2'b01)
                                        out_port_o = NORTH;
                                    else
                                        out_port_o = SOUTH;
                                end
                            end

                        // ---- 步骤4：目的地在西侧 ----
                        end else begin  // e0 < 0
                            x_flits = get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST);   
                            // OE约束：只能在偶数列转弯
                            if (X_CURRENT % 2 == 0) begin
                                if (y_dest_i < Y_CURRENT) begin
                                    // 目的地在此节点北侧（nanbei=1）
                                    nanbei = 2'b01;
                                            y_flits = get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH);
                                end
                                if (y_dest_i > Y_CURRENT) begin
                                    // 目的地在此节点南侧（nanbei=2）
                                    nanbei = 2'b10;
                                            y_flits = get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH);
                                end
                            end

                            // ---- 方向选择 ----
                            if (nanbei != 2'b00) begin
                                if (x_flits < y_flits)
                                    out_port_o = WEST;
                                else if (nanbei == 2'b01)
                                    out_port_o = NORTH;
                                else
                                    out_port_o = SOUTH;
                            end else begin
                                out_port_o = WEST;
                            end
                        end
                    end

                    // ========== TwoAware：两跳拥塞感知 ==========
                    // 基于OE（Odd-Even）感知路由算法：
                    //   - 向东包只能在奇数列或源节点转弯；向西包只能在偶数列转弯
                    //   - 场景 e/f/g/h 按 X/Y 剩余距离细分，跨方向读取拥塞
                    4: begin
                        logic signed [DEST_ADDR_SIZE_X:0] e0;
                        logic signed [DEST_ADDR_SIZE_Y:0] e1;
                        logic [1:0] nanbei;   // 0=未设置, 1=北候选, 2=南候选
                        logic       dongxi;   // 0=东西向不需要, 1=东西向仍需要
                        logic [15:0] x_flits;
                        logic [15:0] y_flits;

                        // ---- 步骤1：计算相对偏移 ----
                        e0 = x_dest_i - X_CURRENT;
                        e1 = y_dest_i - Y_CURRENT;

                        x_flits = 0;
                        y_flits = 0;
                        nanbei = 2'b00;
                        dongxi = 1'b0;

                        // ---- 步骤2：同一列 -> 直接走 Y 方向 ----
                        if (e0 == 0) begin
                            if (y_dest_i < Y_CURRENT)
                                out_port_o = NORTH;
                            else
                                out_port_o = SOUTH;

                        // ---- 步骤3：目的地在东侧 ----
                        end else if (x_dest_i > X_CURRENT) begin
                            if (e1 == 0) begin
                                out_port_o = EAST;
                            end else begin
                                // OE约束：只能在奇数列或源节点转弯
                                if ((X_CURRENT % 2 == 1) || (X_CURRENT == x_source_i)) begin
                                // if (X_CURRENT % 2 == 1) begin
                                    if (y_dest_i < Y_CURRENT) begin
                                        // 目的地在此节点北侧（nanbei=1）
                                        nanbei = 2'b01;
                                        // 场景e dongbei：X>1 && Y>1
                                        if ((X_CURRENT + 1 < x_dest_i) && (y_dest_i + 1 < Y_CURRENT)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 2, Y_CURRENT, WEST));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                                get_decision_metric(X_CURRENT, Y_CURRENT - 2, SOUTH));
                                        end
                                        // 场景f：X>1 && Y==1（第二个Y跳读转向后的WEST方向）
                                        if ((X_CURRENT + 1 < x_dest_i) && (y_dest_i + 1 == Y_CURRENT)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 2, Y_CURRENT, WEST));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT - 1, WEST));
                                        end
                                        //Modify add missing eastbound g/h costs when X has one hop left, Michael Tan, 20261028
                                        if ((X_CURRENT + 1 == x_dest_i) && (y_dest_i + 1 < Y_CURRENT)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT - 1, SOUTH));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                                get_decision_metric(X_CURRENT, Y_CURRENT - 2, SOUTH));
                                        end
                                        if ((X_CURRENT + 1 == x_dest_i) && (y_dest_i + 1 == Y_CURRENT)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT - 1, SOUTH));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT - 1, WEST));
                                        end
                                    end else begin
                                        // 目的地在此节点南侧（nanbei=2）
                                        nanbei = 2'b10;
                                        // 场景e dongnan：X>1 && Y>1
                                        if ((X_CURRENT + 1 < x_dest_i) && (Y_CURRENT + 1 < y_dest_i)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 2, Y_CURRENT, WEST));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                                get_decision_metric(X_CURRENT, Y_CURRENT + 2, NORTH));
                                        end
                                        // 场景f：X>1 && Y==1
                                        if ((X_CURRENT + 1 < x_dest_i) && (Y_CURRENT + 1 == y_dest_i)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 2, Y_CURRENT, WEST));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT + 1, WEST));
                                        end
                                        //Modify add missing eastbound g/h costs when X has one hop left, Michael Tan, 20261028
                                        if ((X_CURRENT + 1 == x_dest_i) && (Y_CURRENT + 1 < y_dest_i)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT + 1, NORTH));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                                get_decision_metric(X_CURRENT, Y_CURRENT + 2, NORTH));
                                        end
                                        if ((X_CURRENT + 1 == x_dest_i) && (Y_CURRENT + 1 == y_dest_i)) begin
                                            x_flits = agg2(
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT + 1, NORTH));
                                            y_flits = agg2(
                                                get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                                get_decision_metric(X_CURRENT + 1, Y_CURRENT + 1, WEST));
                                        end
                                    end
                                end
                                // 目的地在奇数列或X距离>1 -> 仍需往东
                                if ((x_dest_i % 2 == 1) || (e0 != 1))
                                    dongxi = 1'b1;

                                // ---- 方向选择 ----
                                if (dongxi) begin
                                    if (nanbei != 2'b00) begin
                                        if (x_flits < y_flits)
                                            out_port_o = EAST;
                                        else if (nanbei == 2'b01)
                                            out_port_o = NORTH;
                                        else
                                            out_port_o = SOUTH;
                                    end else begin
                                        out_port_o = EAST;
                                    end
                                end else begin
                                    if (nanbei == 2'b01)
                                        out_port_o = NORTH;
                                    else
                                        out_port_o = SOUTH;
                                end
                            end

                        // ---- 步骤4：目的地在西侧 ----
                        end else begin  // e0 < 0
                            // OE约束：只能在偶数列转弯
                            if (X_CURRENT % 2 == 0) begin
                                if (y_dest_i < Y_CURRENT) begin
                                    // 目的地在此节点北侧（nanbei=1）
                                    nanbei = 2'b01;
                                    // 场景e xibei：X>1 && Y>1
                                    if ((x_dest_i + 1 < X_CURRENT) && (y_dest_i + 1 < Y_CURRENT)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 2, Y_CURRENT, EAST));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                            get_decision_metric(X_CURRENT, Y_CURRENT - 2, SOUTH));
                                    end
                                    // 场景f：X>1 && Y==1
                                    if ((x_dest_i + 1 < X_CURRENT) && (y_dest_i + 1 == Y_CURRENT)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 2, Y_CURRENT, EAST));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT - 1, EAST));
                                    end
                                    // 场景g：X==1 && Y>1
                                    if ((x_dest_i + 1 == X_CURRENT) && (y_dest_i + 1 < Y_CURRENT)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT - 1, SOUTH));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                            get_decision_metric(X_CURRENT, Y_CURRENT - 2, SOUTH));
                                    end
                                    // 场景h：X==1 && Y==1
                                    if ((x_dest_i + 1 == X_CURRENT) && (y_dest_i + 1 == Y_CURRENT)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT - 1, SOUTH));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT - 1, EAST));
                                    end
                                end
                                if (y_dest_i > Y_CURRENT) begin
                                    // 目的地在此节点南侧（nanbei=2）
                                    nanbei = 2'b10;
                                    // 场景e xinan：X>1 && Y>1
                                    if ((x_dest_i + 1 < X_CURRENT) && (Y_CURRENT + 1 < y_dest_i)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 2, Y_CURRENT, EAST));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                            get_decision_metric(X_CURRENT, Y_CURRENT + 2, NORTH));
                                    end
                                    // 场景f：X>1 && Y==1
                                    if ((x_dest_i + 1 < X_CURRENT) && (Y_CURRENT + 1 == y_dest_i)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 2, Y_CURRENT, EAST));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT + 1, EAST));
                                    end
                                    // 场景g：X==1 && Y>1
                                    if ((x_dest_i + 1 == X_CURRENT) && (Y_CURRENT + 1 < y_dest_i)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT + 1, NORTH));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                            get_decision_metric(X_CURRENT, Y_CURRENT + 2, NORTH));
                                    end
                                    // 场景h：X==1 && Y==1
                                    if ((x_dest_i + 1 == X_CURRENT) && (Y_CURRENT + 1 == y_dest_i)) begin
                                        x_flits = agg2(
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT + 1, NORTH));
                                        y_flits = agg2(
                                            get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH),
                                            get_decision_metric(X_CURRENT - 1, Y_CURRENT + 1, EAST));
                                    end
                                end
                            end

                            // ---- 方向选择 ----
                            if (nanbei != 2'b00) begin
                                if (x_flits < y_flits)
                                    out_port_o = WEST;
                                else if (nanbei == 2'b01)
                                    out_port_o = NORTH;
                                else
                                    out_port_o = SOUTH;
                            end else begin
                                out_port_o = WEST;
                            end
                        end
                    end


                    // ========== ThreeAware：三跳拥塞感知（预留） ==========
                    5: begin
                        logic [15:0] hop1, hop2, hop3;
                        logic [15:0] x_congestion_agg;
                        logic [15:0] y_congestion_agg;

                        // X 方向三跳拥塞值
                        if (x_candidate == EAST) begin
                            hop1 = get_decision_metric(X_CURRENT + 1, Y_CURRENT, WEST);
                            hop2 = get_decision_metric(X_CURRENT + 2, Y_CURRENT, WEST);
                            hop3 = get_decision_metric(X_CURRENT + 3, Y_CURRENT, WEST);
                        end else begin  // WEST
                            hop1 = get_decision_metric(X_CURRENT - 1, Y_CURRENT, EAST);
                            hop2 = get_decision_metric(X_CURRENT - 2, Y_CURRENT, EAST);
                            hop3 = get_decision_metric(X_CURRENT - 3, Y_CURRENT, EAST);
                        end
                        if (AGGREGATION == 0)           // 平均（和比较）
                            x_congestion_agg = hop1 + hop2 + hop3;
                        else if (AGGREGATION == 1)      // 最大
                            x_congestion_agg = (hop1 > hop2) ? ((hop1 > hop3) ? hop1 : hop3) : ((hop2 > hop3) ? hop2 : hop3);
                        else                            // 加权
                            x_congestion_agg = hop1 * WEIGHT_HOP1 + hop2 * WEIGHT_HOP2 + hop3 * WEIGHT_HOP3;

                        // Y 方向三跳拥塞值
                        if (y_candidate == NORTH) begin
                            hop1 = get_decision_metric(X_CURRENT, Y_CURRENT - 1, SOUTH);
                            hop2 = get_decision_metric(X_CURRENT, Y_CURRENT - 2, SOUTH);
                            hop3 = get_decision_metric(X_CURRENT, Y_CURRENT - 3, SOUTH);
                        end else begin  // SOUTH
                            hop1 = get_decision_metric(X_CURRENT, Y_CURRENT + 1, NORTH);
                            hop2 = get_decision_metric(X_CURRENT, Y_CURRENT + 2, NORTH);
                            hop3 = get_decision_metric(X_CURRENT, Y_CURRENT + 3, NORTH);
                        end
                        if (AGGREGATION == 0)
                            y_congestion_agg = hop1 + hop2 + hop3;
                        else if (AGGREGATION == 1)
                            y_congestion_agg = (hop1 > hop2) ? ((hop1 > hop3) ? hop1 : hop3) : ((hop2 > hop3) ? hop2 : hop3);
                        else
                            y_congestion_agg = hop1 * WEIGHT_HOP1 + hop2 * WEIGHT_HOP2 + hop3 * WEIGHT_HOP3;

                        if (x_congestion_agg <= y_congestion_agg)
                            out_port_o = x_candidate;
                        else
                            out_port_o = y_candidate;
                    end

                    // ========== 默认：按 X 方向优先 ==========
                    default: begin
                        out_port_o = x_candidate;
                    end
                endcase
            end
        end
    end

endmodule
