import noc_params::*;

module input_block #(
    parameter PORT_NUM = 5,
    parameter BUFFER_SIZE = 8,
    parameter X_CURRENT = MESH_SIZE_X/2,
    parameter Y_CURRENT = MESH_SIZE_Y/2,
    parameter ALGORITHM = 0,        // 【修改】添加路由算法参数
    parameter AGGREGATION = 0,      // 【修改】添加聚合算法参数
    parameter DECISION_REFERENCE = 1 // 【修改】添加决策参考指标选择
)(
    input flit_t data_i [PORT_NUM-1:0],
    input valid_flit_i [PORT_NUM-1:0],
    input rst,
    input clk,
    input_block2crossbar.input_block crossbar_if,
    input_block2switch_allocator.input_block sa_if,
    input_block2vc_allocator.input_block va_if,
    output logic [VC_NUM-1:0] on_off_o [PORT_NUM-1:0],
    output logic [VC_NUM-1:0] vc_allocatable_o [PORT_NUM-1:0],
    output logic [VC_NUM-1:0] error_o [PORT_NUM-1:0],

    // 【修改】添加每个方向、每个 VC 的占用数输出
    output logic [PORT_NUM-1:0][VC_NUM-1:0][$clog2(BUFFER_SIZE):0] state_occupancy_o,

    // 【修改】添加决策参考指标输入（从状态信息收集模块来，向下传递给 rc_unit）
    input metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_i
);

    logic [VC_NUM-1:0] is_full [PORT_NUM-1:0];
    logic [VC_NUM-1:0] is_empty [PORT_NUM-1:0];

    port_t [VC_NUM-1:0] out_port [PORT_NUM-1:0];

    assign va_if.out_port = out_port;
    assign sa_if.out_port = out_port;

    genvar ip;
    generate
        for(ip=0; ip<PORT_NUM; ip++)
        begin: generate_input_ports
            input_port #(
                .BUFFER_SIZE(BUFFER_SIZE),
                .X_CURRENT(X_CURRENT),
                .Y_CURRENT(Y_CURRENT),
                .ALGORITHM(ALGORITHM),      // 【修改】传入路由算法参数
                .AGGREGATION(AGGREGATION),  // 【修改】传入聚合算法参数
                .DECISION_REFERENCE(DECISION_REFERENCE) // 【修改】传入决策参考指标选择
            )
            input_port (
                .data_i(data_i[ip]),
                .valid_flit_i(valid_flit_i[ip]),
                .rst(rst),
                .clk(clk),
                .sa_sel_vc_i(sa_if.vc_sel[ip]),
                .va_new_vc_i(va_if.vc_new[ip]),
                .va_valid_i(va_if.vc_valid[ip]),
                .sa_valid_i(sa_if.valid_sel[ip]),
                .xb_flit_o(crossbar_if.flit[ip]),
                .is_on_off_o(on_off_o[ip]),
                .is_allocatable_vc_o(vc_allocatable_o[ip]),
                .va_request_o(va_if.vc_request[ip]),
                .sa_request_o(sa_if.switch_request[ip]),
                .sa_downstream_vc_o(sa_if.downstream_vc[ip]),
                .out_port_o(out_port[ip]),
                .is_full_o(is_full[ip]),
                .is_empty_o(is_empty[ip]),
                .error_o(error_o[ip]),
                .vc_occupancy_o(state_occupancy_o[ip]),   // 【修改】连接 VC 占用数
                .metrics_i(metrics_i)                      // 【修改】连接决策参考指标
            );
        end
    endgenerate

endmodule
