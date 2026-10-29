import noc_params::*;

module router #(
    parameter BUFFER_SIZE = 8,
    parameter X_CURRENT = MESH_SIZE_X/2,
    parameter Y_CURRENT = MESH_SIZE_Y/2,
    parameter ALGORITHM = 0,        // 【修改】添加路由算法参数
    parameter AGGREGATION = 0,      // 【修改】添加聚合算法参数
    parameter DECISION_REFERENCE = 1 // 【修改】添加决策参考指标选择
)(
    input clk,
    input rst,
    router2router.upstream router_if_local_up,
    router2router.upstream router_if_north_up,
    router2router.upstream router_if_south_up,
    router2router.upstream router_if_west_up,
    router2router.upstream router_if_east_up,
    router2router.downstream router_if_local_down,
    router2router.downstream router_if_north_down,
    router2router.downstream router_if_south_down,
    router2router.downstream router_if_west_down,
    router2router.downstream router_if_east_down,
    output logic [VC_NUM-1:0] error_o [PORT_NUM-1:0],

    // 【修改】添加路由器状态信息输出（给状态信息收集模块）
    output router_state_t router_state_o,

    // 【修改】添加决策参考指标输入（从状态信息收集模块来）
    input metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_i
);

    //connections from upstream
    flit_t data_out [PORT_NUM-1:0];
    logic  [PORT_NUM-1:0] is_valid_out;
    logic  [PORT_NUM-1:0] [VC_NUM-1:0] is_on_off_in;
    logic  [PORT_NUM-1:0] [VC_NUM-1:0] is_allocatable_in;

    //connections from downstream
    flit_t data_in [PORT_NUM-1:0];
    logic  is_valid_in [PORT_NUM-1:0];
    logic  [VC_NUM-1:0] is_on_off_out [PORT_NUM-1:0];
    logic  [VC_NUM-1:0] is_allocatable_out [PORT_NUM-1:0];

    // 【修改】每个方向每个 VC 的占用数（从 input_block 收集）
    logic [PORT_NUM-1:0][VC_NUM-1:0][$clog2(BUFFER_SIZE):0] state_occupancy;

    // ========== 路由器接口组合逻辑 ==========
    always_comb
    begin
        router_if_local_up.data = data_out[LOCAL];
        router_if_north_up.data = data_out[NORTH];
        router_if_south_up.data = data_out[SOUTH];
        router_if_west_up.data  = data_out[WEST];
        router_if_east_up.data  = data_out[EAST];

        router_if_local_up.is_valid = is_valid_out[LOCAL];
        router_if_north_up.is_valid = is_valid_out[NORTH];
        router_if_south_up.is_valid = is_valid_out[SOUTH];
        router_if_west_up.is_valid  = is_valid_out[WEST];
        router_if_east_up.is_valid  = is_valid_out[EAST];

        is_on_off_in[LOCAL] = router_if_local_up.is_on_off;
        is_on_off_in[NORTH] = router_if_north_up.is_on_off;
        is_on_off_in[SOUTH] = router_if_south_up.is_on_off;
        is_on_off_in[WEST]  = router_if_west_up.is_on_off;
        is_on_off_in[EAST]  = router_if_east_up.is_on_off;

        is_allocatable_in[LOCAL] = router_if_local_up.is_allocatable;
        is_allocatable_in[NORTH] = router_if_north_up.is_allocatable;
        is_allocatable_in[SOUTH] = router_if_south_up.is_allocatable;
        is_allocatable_in[WEST]  = router_if_west_up.is_allocatable;
        is_allocatable_in[EAST]  = router_if_east_up.is_allocatable;

        data_in[LOCAL] = router_if_local_down.data;
        data_in[NORTH] = router_if_north_down.data;
        data_in[SOUTH] = router_if_south_down.data;
        data_in[WEST]  = router_if_west_down.data;
        data_in[EAST]  = router_if_east_down.data;

        is_valid_in[LOCAL] = router_if_local_down.is_valid;
        is_valid_in[NORTH] = router_if_north_down.is_valid;
        is_valid_in[SOUTH] = router_if_south_down.is_valid;
        is_valid_in[WEST]  = router_if_west_down.is_valid;
        is_valid_in[EAST]  = router_if_east_down.is_valid;

        router_if_local_down.is_on_off = is_on_off_out[LOCAL];
        router_if_north_down.is_on_off = is_on_off_out[NORTH];
        router_if_south_down.is_on_off = is_on_off_out[SOUTH];
        router_if_west_down.is_on_off  = is_on_off_out[WEST];
        router_if_east_down.is_on_off  = is_on_off_out[EAST];

        router_if_local_down.is_allocatable = is_allocatable_out[LOCAL];
        router_if_north_down.is_allocatable = is_allocatable_out[NORTH];
        router_if_south_down.is_allocatable = is_allocatable_out[SOUTH];
        router_if_west_down.is_allocatable  = is_allocatable_out[WEST];
        router_if_east_down.is_allocatable  = is_allocatable_out[EAST];
    end

    // ========== 收集路由器状态信息输出 ==========
    // 【修改】从 input_block 收集 full/empty 信息，组合成 router_state_o
    always_comb begin
        for (int p = 0; p < PORT_NUM; p++) begin
            for (int v = 0; v < VC_NUM; v++) begin
                router_state_o.vc_occupancy[p][v] = state_occupancy[p][v];
                router_state_o.is_full[p][v] = (state_occupancy[p][v] == BUFFER_SIZE);
                router_state_o.is_empty[p][v] = (state_occupancy[p][v] == 0);
            end
        end
    end

    input_block2crossbar ib2xbar_if();
    input_block2switch_allocator ib2sa_if();
    input_block2vc_allocator ib2va_if();
    switch_allocator2crossbar sa2xbar_if();

    // ========== 实例化 input_block ==========
    input_block #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .X_CURRENT(X_CURRENT),
        .Y_CURRENT(Y_CURRENT),
        .ALGORITHM(ALGORITHM),
        .AGGREGATION(AGGREGATION),
        .DECISION_REFERENCE(DECISION_REFERENCE)
    )
    input_block (
        .rst(rst),
        .clk(clk),
        .data_i(data_in),
        .valid_flit_i(is_valid_in),
        .crossbar_if(ib2xbar_if),
        .sa_if(ib2sa_if),
        .va_if(ib2va_if),
        .on_off_o(is_on_off_out),
        .vc_allocatable_o(is_allocatable_out),
        .error_o(error_o),
        .state_occupancy_o(state_occupancy),    // 【修改】连接占用数
        .metrics_i(metrics_i)                    // 【修改】连接决策参考指标
    );

    crossbar #(
    )
    crossbar (
        .ib_if(ib2xbar_if),
        .sa_if(sa2xbar_if),
        .data_o(data_out)
    );

    switch_allocator #(
    )
    switch_allocator (
        .rst(rst),
        .clk(clk),
        .on_off_i(is_on_off_in),
        .ib_if(ib2sa_if),
        .xbar_if(sa2xbar_if),
        .valid_flit_o(is_valid_out)
    );
    
    //Modify provide existing neighbor input occupancy only to the isolated mode2 chooser, Michael Tan, 20261029
    logic [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] next_input_occupancy;
    always_comb begin
        next_input_occupancy='0;
        if(Y_CURRENT>0) next_input_occupancy[NORTH]=metrics_i[X_CURRENT][Y_CURRENT-1].per_dir_total_occupancy[SOUTH];
        if(Y_CURRENT<MESH_SIZE_Y-1) next_input_occupancy[SOUTH]=metrics_i[X_CURRENT][Y_CURRENT+1].per_dir_total_occupancy[NORTH];
        if(X_CURRENT>0) next_input_occupancy[WEST]=metrics_i[X_CURRENT-1][Y_CURRENT].per_dir_total_occupancy[EAST];
        if(X_CURRENT<MESH_SIZE_X-1) next_input_occupancy[EAST]=metrics_i[X_CURRENT+1][Y_CURRENT].per_dir_total_occupancy[WEST];
    end
    vc_allocator #(
        .X_CURRENT(X_CURRENT),.Y_CURRENT(Y_CURRENT)//Modify identify local position for legal two-hop scoring, Michael Tan, 20261029
    )
    vc_allocator (
        .rst(rst),
        .clk(clk),
        .idle_downstream_vc_i(is_allocatable_in),
        .downstream_on_off_i(is_on_off_in),//Modify joint availability and receive eligibility, Michael Tan, 20261029
        .metrics_i(metrics_i),//Modify reuse existing registered-occupancy metrics; no new propagation timing assumed, Michael Tan, 20261029
        .next_input_occupancy_i(next_input_occupancy),//Modify same metric for all mode2 candidates, Michael Tan, 20261029
        .ib_if(ib2va_if)
    );

endmodule
