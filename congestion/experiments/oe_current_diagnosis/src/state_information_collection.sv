// ============================================================================
// 状态信息收集模块（state_information_collection）
// 功能描述：收集所有 Router 模块的原始状态信息，经过统计处理后
//          输出决策参考指标给拥塞判决模块使用。
// 作者：Michael Tan
// 日期：2026-07-29
// ============================================================================
import noc_params::*;

module state_information_collection #(
    parameter BUFFER_SIZE = 8  // 缓冲区深度
)(
    // 输入：25 个路由器的原始状态信息
    input router_state_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] router_state_i,

    // 输出：25 个节点的决策参考指标
    output metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_o
);

    // 容量常量
    localparam DIR_CAPACITY = BUFFER_SIZE * VC_NUM;      // 每个方向容量
    localparam NODE_CAPACITY = DIR_CAPACITY * PORT_NUM;  // 每个节点总容量

    genvar x, y;

    generate
        for (y = 0; y < MESH_SIZE_Y; y++) begin : gen_row
            for (x = 0; x < MESH_SIZE_X; x++) begin : gen_col

                // ---- 信号声明 ----
                // 每个方向的 VC 占用数之和
                logic [DIR_OCCUPANCY_WIDTH-1:0] dir_total [PORT_NUM-1:0];
                // 每个方向的拥塞等级
                logic [CONGESTION_LEVEL_WIDTH-1:0] dir_level [PORT_NUM-1:0];
                // 节点总流量（5 个方向总占用数之和）
                logic [TOTAL_FLOW_WIDTH-1:0] node_total;

                // ---- 计算每个方向的总占用数 ----
                always_comb begin
                    for (int d = 0; d < PORT_NUM; d++) begin
                        dir_total[d] = 0;
                        for (int v = 0; v < VC_NUM; v++) begin
                            dir_total[d] = dir_total[d] +
                                router_state_i[x][y].vc_occupancy[d][v];
                        end
                    end
                end

                // ---- 计算拥塞等级（将占用率映射到等级 1~9）----
                // 占用率 = dir_total / DIR_CAPACITY
                // 映射规则：
                //   ≤10% → 1
                //   10%~20% → 2
                //   20%~30% → 3
                //   30%~40% → 4
                //   40%~50% → 5
                //   50%~60% → 6
                //   60%~70% → 7
                //   70%~80% → 8
                //   >80% → 9
                // 由于不用浮点数，用乘法比较：
                //   dir_total * 100 ≤ 10 * DIR_CAPACITY → level 1
                //   dir_total * 100 ≤ 20 * DIR_CAPACITY → level 2
                //   ...
                always_comb begin
                    for (int d = 0; d < PORT_NUM; d++) begin
                        if (dir_total[d] * 100 <= 10 * DIR_CAPACITY)
                            dir_level[d] = 1;
                        else if (dir_total[d] * 100 <= 20 * DIR_CAPACITY)
                            dir_level[d] = 2;
                        else if (dir_total[d] * 100 <= 30 * DIR_CAPACITY)
                            dir_level[d] = 3;
                        else if (dir_total[d] * 100 <= 40 * DIR_CAPACITY)
                            dir_level[d] = 4;
                        else if (dir_total[d] * 100 <= 50 * DIR_CAPACITY)
                            dir_level[d] = 5;
                        else if (dir_total[d] * 100 <= 60 * DIR_CAPACITY)
                            dir_level[d] = 6;
                        else if (dir_total[d] * 100 <= 70 * DIR_CAPACITY)
                            dir_level[d] = 7;
                        else if (dir_total[d] * 100 <= 80 * DIR_CAPACITY)
                            dir_level[d] = 8;
                        else
                            dir_level[d] = 9;
                    end
                end

                // ---- 计算节点总流量 ----
                always_comb begin
                    node_total = 0;
                    for (int d = 0; d < PORT_NUM; d++) begin
                        node_total = node_total + dir_total[d];
                    end
                end

                // ---- 输出决策参考指标 ----
                always_comb begin
                    metrics_o[x][y].node_total_flow = node_total;
                    for (int d = 0; d < PORT_NUM; d++) begin
                        metrics_o[x][y].per_dir_total_occupancy[d] = dir_total[d];
                        metrics_o[x][y].per_dir_congestion_level[d] = dir_level[d];
                    end
                end

            end
        end
    endgenerate

endmodule