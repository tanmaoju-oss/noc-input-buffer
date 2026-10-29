import noc_params::*;

module mesh #(
    parameter BUFFER_SIZE = 8,
    parameter MESH_SIZE_X = 13,
    parameter MESH_SIZE_Y = 13,
    parameter ALGORITHM = 0,        // 【修改】路由算法选择
    parameter AGGREGATION = 0,      // 【修改】拥塞感知聚合算法
    parameter DECISION_REFERENCE = 0 // 【修改】决策参考指标选择
)(
    input clk,
    input rst,
    output logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0],
    //connections to all local Router interfaces
    output flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o,
    input [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_i,
    input [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_i,
    input flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_i,
    input [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_i,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_on_off_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o,

    // 【修改】添加决策参考指标输出（可选，供外部监控用）
    output metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_debug_o
);

    // 【修改】路由器状态收集信号（所有路由器的原始状态）
    wire router_state_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] router_state_w;

    // 【修改】决策参考指标信号（从状态收集模块输出）
    wire metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_w;

    genvar row, col;
    generate
        for(row=0; row<MESH_SIZE_Y; row++)
        begin: mesh_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: mesh_col
                //interfaces instantiation
                router2router local_up();
                router2router north_up();
                router2router south_up();
                router2router west_up();
                router2router east_up();
                router2router local_down();
                router2router north_down();
                router2router south_down();
                router2router west_down();
                router2router east_down();
                //router instantiation
                router #(
                    .BUFFER_SIZE(BUFFER_SIZE),
                    .X_CURRENT(col),
                    .Y_CURRENT(row),
                    .ALGORITHM(ALGORITHM),      // 【修改】传入路由算法参数
                    .AGGREGATION(AGGREGATION),  // 【修改】传入聚合算法参数
                    .DECISION_REFERENCE(DECISION_REFERENCE) // 【修改】传入决策参考指标选择
                )
                router (
                    .clk(clk),
                    .rst(rst),
                    //upstream interfaces connections 
                    .router_if_local_up(local_up),
                    .router_if_north_up(north_up),
                    .router_if_south_up(south_up),
                    .router_if_west_up(west_up),
                    .router_if_east_up(east_up),
                    //downstream interfaces connections
                    .router_if_local_down(local_down),
                    .router_if_north_down(north_down),
                    .router_if_south_down(south_down),
                    .router_if_west_down(west_down),
                    .router_if_east_down(east_down),
                    .error_o(error_o[col][row]),

                    // 【修改】状态信息输出到收集模块
                    .router_state_o(router_state_w[col][row]),

                    // 【修改】决策参考指标输入
                    .metrics_i(metrics_w)
                );
            end
        end

        // ========== 垂直连接 ==========
        for(row=0; row<MESH_SIZE_Y-1; row++)
        begin: vertical_links_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: vertical_links_col
                router_link link_one (
                    .router_if_up(mesh_row[row].mesh_col[col].south_down),
                    .router_if_down(mesh_row[row+1].mesh_col[col].north_up)
                );

                router_link link_two (
                    .router_if_up(mesh_row[row+1].mesh_col[col].north_down),
                    .router_if_down(mesh_row[row].mesh_col[col].south_up)
                );
                
            end
        end

        // ========== 水平连接 ==========
        for(row=0; row<MESH_SIZE_Y; row++)
        begin: horizontal_links_row
            for(col=0; col<MESH_SIZE_X-1; col++)
            begin: horizontal_links_col
                router_link link_one (
                    .router_if_up(mesh_row[row].mesh_col[col].east_down),
                    .router_if_down(mesh_row[row].mesh_col[col+1].west_up)
                );

                router_link link_two (
                    .router_if_up(mesh_row[row].mesh_col[col+1].west_down),
                    .router_if_down(mesh_row[row].mesh_col[col].east_up)
                );

            end
        end

        // ========== 节点连接（到本地 PE） ==========
        for(row=0; row<MESH_SIZE_Y; row++)
        begin: node_connection_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: node_connection_col
                node_link node_link (
                    .router_if_up(mesh_row[row].mesh_col[col].local_down),
                    .router_if_down(mesh_row[row].mesh_col[col].local_up),
                    .data_i(data_i[col][row]),
                    .is_valid_i(is_valid_i[col][row]),
                    .is_on_off_o(is_on_off_o[col][row]),
                    .is_allocatable_o(is_allocatable_o[col][row]),
                    .data_o(data_o[col][row]),
                    .is_valid_o(is_valid_o[col][row]),
                    .is_on_off_i(is_on_off_i[col][row]),
                    .is_allocatable_i(is_allocatable_i[col][row])
                );
            end
        end

    endgenerate

    // ========== 【修改】实例化状态信息收集模块 ==========
    state_information_collection #(
        .BUFFER_SIZE(BUFFER_SIZE)
    )
    state_information_collection_inst (
        .router_state_i(router_state_w),
        .metrics_o(metrics_w)
    );

    // 【修改】输出 metrics 供调试
    assign metrics_debug_o = metrics_w;

endmodule
