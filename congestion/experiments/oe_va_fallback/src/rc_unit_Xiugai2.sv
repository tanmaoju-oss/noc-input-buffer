import noc_params::*;

module rc_unit #(
    parameter X_CURRENT = 0,
    parameter Y_CURRENT = 0,
    parameter DEST_ADDR_SIZE_X = 4,
    parameter DEST_ADDR_SIZE_Y = 4,
    parameter ALGORITHM = 0,        // 【修改】路由算法选择：0=XY, 1=YX, 2=OE, 3=OneAware, 4=TwoAware, 5=ThreeAware
    parameter AGGREGATION = 0,      // 【修改】拥塞感知聚合算法：0=平均, 1=最大, 2=加权
    parameter DECISION_REFERENCE = 1 // 【修改】决策参考指标选择：0=每方向总占用数, 1=每方向拥塞等级, 2=节点总流量
)(
    input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest_i,
    input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest_i,
    input logic [DEST_ADDR_SIZE_X-1 : 0] x_source_i,   // 【新增】源节点 X
    input logic [DEST_ADDR_SIZE_Y-1 : 0] y_source_i,   // 【新增】源节点 Y
    input logic [PACKET_ID_SIZE-1 : 0] packet_id_i,   // 【新增】数据包 ID（OE 随机选择用）

    input flit_label_t flit_label_i,

    output port_t out_port_o,

    // 【修改】添加决策参考指标输入（从状态信息收集模块来）
    input metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_i
);

    wire signed [DEST_ADDR_SIZE_X-1 : 0] x_offset;
    wire signed [DEST_ADDR_SIZE_Y-1 : 0] y_offset;

    assign x_offset = x_dest_i - X_CURRENT;
    assign y_offset = y_dest_i - Y_CURRENT;

    // 【修改】拥塞判决模块的中间信号
    port_t cong_out_port;
    port_t oe_out_port;
    port_t xy_out_port;
    port_t yx_out_port;

    // ========== XY 算法（原始算法） ==========
    always_comb begin
        if (flit_label_i == HEAD || flit_label_i == HEADTAIL) begin
            unique if (x_dest_i < X_CURRENT) begin
                xy_out_port = WEST;
            end else if (x_dest_i > X_CURRENT) begin
                xy_out_port = EAST;
            end else if (x_dest_i == X_CURRENT && y_dest_i < Y_CURRENT) begin
                xy_out_port = NORTH;
            end else if (x_dest_i == X_CURRENT && y_dest_i > Y_CURRENT) begin
                xy_out_port = SOUTH;
            end else begin
                xy_out_port = LOCAL;
            end
        end else begin
            xy_out_port = LOCAL;  // 非头 flit 默认直通
        end
    end

    // ========== YX 算法（先 Y 后 X） ==========
    always_comb begin
        if (flit_label_i == HEAD || flit_label_i == HEADTAIL) begin
            unique if (y_dest_i < Y_CURRENT) begin
                yx_out_port = NORTH;
            end else if (y_dest_i > Y_CURRENT) begin
                yx_out_port = SOUTH;
            end else if (y_dest_i == Y_CURRENT && x_dest_i < X_CURRENT) begin
                yx_out_port = WEST;
            end else if (y_dest_i == Y_CURRENT && x_dest_i > X_CURRENT) begin
                yx_out_port = EAST;
            end else begin
                yx_out_port = LOCAL;
            end
        end else begin
            yx_out_port = LOCAL;
        end
    end

    // OE random bit: derived from packet id and source/dest/current coordinates.
    logic oe_rand_bit;
    always_comb begin
        oe_rand_bit = ^packet_id_i;
        oe_rand_bit = oe_rand_bit ^ X_CURRENT[0] ^ Y_CURRENT[0]
                      ^ x_dest_i[0] ^ y_dest_i[0] ^ x_source_i[0] ^ y_source_i[0];
    end

    // ========== OE routing (moved from congestion_decision) ==========
    // When both X and Y directions are available, choose one randomly.
    always_comb begin
        oe_out_port = LOCAL;
        if (flit_label_i == HEAD || flit_label_i == HEADTAIL) begin
            logic signed [DEST_ADDR_SIZE_X:0] e0;
            logic signed [DEST_ADDR_SIZE_Y:0] e1;
            logic [1:0] nanbei;   // 0=not allowed, 1=north allowed, 2=south allowed
            logic       dongxi;   // 0=east/west not needed, 1=east/west allowed

            e0 = x_dest_i - X_CURRENT;
            e1 = y_dest_i - Y_CURRENT;
            nanbei = 2'b00;
            dongxi = 1'b0;

            if (e0 == 0 && e1 == 0) begin
                oe_out_port = LOCAL;
            end else if (e0 == 0) begin
                if (y_dest_i < Y_CURRENT)
                    oe_out_port = NORTH;
                else
                    oe_out_port = SOUTH;
            end else if (x_dest_i > X_CURRENT) begin
                if (e1 == 0) begin
                    oe_out_port = EAST;
                end else begin
                    if ((X_CURRENT % 2 == 1) || (X_CURRENT == x_source_i)) begin
                        if (y_dest_i < Y_CURRENT)
                            nanbei = 2'b01;
                        else
                            nanbei = 2'b10;
                    end
                    if ((x_dest_i % 2 == 1) || (e0 != 1))
                        dongxi = 1'b1;

                    if (dongxi) begin
                        if (nanbei != 2'b00) begin
                            if (oe_rand_bit)
                                oe_out_port = EAST;
                            else if (nanbei == 2'b01)
                                oe_out_port = NORTH;
                            else
                                oe_out_port = SOUTH;
                        end else begin
                            oe_out_port = EAST;
                        end
                    end else begin
                        if (nanbei == 2'b01)
                            oe_out_port = NORTH;
                        else
                            oe_out_port = SOUTH;
                    end
                end
            end else begin
                if (X_CURRENT % 2 == 0) begin
                    if (y_dest_i < Y_CURRENT)
                        nanbei = 2'b01;
                    if (y_dest_i > Y_CURRENT)
                        nanbei = 2'b10;
                end

                if (nanbei != 2'b00) begin
                    if (oe_rand_bit)
                        oe_out_port = WEST;
                    else if (nanbei == 2'b01)
                        oe_out_port = NORTH;
                    else
                        oe_out_port = SOUTH;
                end else begin
                    oe_out_port = WEST;
                end
            end
        end
    end
    // ========== 拥塞判决模块实例化（用于 OneAware / TwoAware / ThreeAware） ==========
    congestion_decision #(
        .X_CURRENT(X_CURRENT),
        .Y_CURRENT(Y_CURRENT),
        .DEST_ADDR_SIZE_X(DEST_ADDR_SIZE_X),
        .DEST_ADDR_SIZE_Y(DEST_ADDR_SIZE_Y),
        .ALGORITHM(ALGORITHM),          // 【修改】直接传入 ALGORITHM，在模块内部 case 区分
        .AGGREGATION(AGGREGATION),
        .DECISION_REFERENCE(DECISION_REFERENCE) // 【修改】传入决策参考指标选择
    )
    congestion_decision_inst (
        .x_dest_i(x_dest_i),
        .y_dest_i(y_dest_i),
        .x_source_i(x_source_i),        // 【新增】连接源节点坐标
        .y_source_i(y_source_i),        // 【新增】连接源节点坐标
        .flit_label_i(flit_label_i),
        .metrics_i(metrics_i),
        .out_port_o(cong_out_port)
    );

    // ========== 根据 ALGORITHM 选择输出 ==========
    always_comb begin
        unique case (ALGORITHM)
            0: out_port_o = xy_out_port;          // XY 算法
            1: out_port_o = yx_out_port;          // YX 算法
            2: out_port_o = oe_out_port;        // OE 算法（随机选择）
            3: out_port_o = cong_out_port;        // OneAware 算法
            4: out_port_o = cong_out_port;        // TwoAware 算法
            5: out_port_o = cong_out_port;        // ThreeAware 算法
            default: out_port_o = xy_out_port;
        endcase
    end

endmodule
