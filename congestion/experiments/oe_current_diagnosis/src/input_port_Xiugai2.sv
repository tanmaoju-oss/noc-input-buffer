import noc_params::*;

module input_port #(
    parameter BUFFER_SIZE = 8,
    parameter X_CURRENT = MESH_SIZE_X/2,
    parameter Y_CURRENT = MESH_SIZE_Y/2,
    parameter ALGORITHM = 0,        // 【修改】添加路由算法参数
    parameter AGGREGATION = 0,      // 【修改】添加聚合算法参数（0=平均 1=最大 2=加权）
    parameter DECISION_REFERENCE = 0 // 【修改】添加决策参考指标选择
)(
    input flit_t data_i,
    input valid_flit_i,

    input rst,
    input clk,

    input [VC_SIZE-1:0] sa_sel_vc_i,
    input [VC_SIZE-1:0] va_new_vc_i [VC_NUM-1:0],
    input [VC_NUM-1:0] va_valid_i,
    input sa_valid_i,

    output flit_t xb_flit_o,

    output logic [VC_NUM-1:0] is_on_off_o,
    output logic [VC_NUM-1:0] is_allocatable_vc_o,

    output logic [VC_NUM-1:0] va_request_o,
    output logic sa_request_o [VC_NUM-1:0],
    output logic [VC_SIZE-1:0] sa_downstream_vc_o [VC_NUM-1:0],

    output port_t [VC_NUM-1:0] out_port_o,
    output logic [VC_NUM-1:0] is_full_o,
    output logic [VC_NUM-1:0] is_empty_o,
    output logic [VC_NUM-1:0] error_o,

    // 【修改】添加 VC 占用数输出，用于拥塞信息收集
    output logic [VC_NUM-1:0][$clog2(BUFFER_SIZE):0] vc_occupancy_o,

    // 【修改】添加决策参考指标输入（从状态信息收集模块来）
    input metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics_i
);

    flit_novc_t data_cmd [VC_NUM-1:0];
    flit_t [VC_NUM-1:0] data_out;
    port_t out_port_cmd;

    logic [VC_NUM-1:0] read_cmd;
    logic [VC_NUM-1:0] write_cmd;

    logic [VC_SIZE-1:0] sa_sel_vc_reg;
    logic sa_valid_reg;

    genvar vc;
    generate
        for(vc=0; vc<VC_NUM; vc++)
        begin: generate_virtual_channels
            input_buffer #(
                .BUFFER_SIZE(BUFFER_SIZE)
            )
            input_buffer (
                .data_i(data_cmd[vc]),
                .read_i(read_cmd[vc]),
                .write_i(write_cmd[vc]),
                .vc_new_i(va_new_vc_i[vc]),
                .vc_valid_i(va_valid_i[vc]),
                .out_port_i(out_port_cmd),
                .rst(rst),
                .clk(clk),
                .data_o(data_out[vc]),
                .is_full_o(is_full_o[vc]), 
                .is_empty_o(is_empty_o[vc]),
                .on_off_o(is_on_off_o[vc]),
                .out_port_o(out_port_o[vc]),
                .vc_request_o(va_request_o[vc]),
                .switch_request_o(sa_request_o[vc]),
                .vc_allocatable_o(is_allocatable_vc_o[vc]),
                .downstream_vc_o(sa_downstream_vc_o[vc]),
                .error_o(error_o[vc]),
                .priority_usage_o(vc_occupancy_o[vc])  // 【修改】连接占用数输出
            );
        end
    endgenerate

    // 【修改】实例化路由计算单元，支持多种算法
    rc_unit #(
        .X_CURRENT(X_CURRENT),
        .Y_CURRENT(Y_CURRENT),
        .DEST_ADDR_SIZE_X(DEST_ADDR_SIZE_X),
        .DEST_ADDR_SIZE_Y(DEST_ADDR_SIZE_Y),
        .ALGORITHM(ALGORITHM),      // 传入路由算法参数
        .AGGREGATION(AGGREGATION),  // 传入聚合算法参数
        .DECISION_REFERENCE(DECISION_REFERENCE) // 传入决策参考指标选择
    )
    rc_unit (
        .x_dest_i(data_i.data.head_data.x_dest),
        .y_dest_i(data_i.data.head_data.y_dest),
        .x_source_i(data_i.data.head_data.x_source),
        .y_source_i(data_i.data.head_data.y_source),
        .packet_id_i(data_i.data.head_data.packet_id),  // 【新增】连接数据包 ID（OE 随机选择用）

        .flit_label_i(data_i.flit_label),

        .out_port_o(out_port_cmd),

        .metrics_i(metrics_i)       // 【修改】传入决策参考指标
    );

    always_ff @(posedge clk or posedge rst)
    begin
        if(rst)
        begin
            sa_sel_vc_reg       <= {VC_SIZE{1'b0}};
            sa_valid_reg        <= 1'b0;
        end
        else
        begin
            sa_sel_vc_reg       <= sa_sel_vc_i;
            sa_valid_reg        <= sa_valid_i;
        end
    end

    always_comb
    begin

        data_cmd[data_i.vc_id].flit_label = data_i.flit_label;
        data_cmd[data_i.vc_id].data = data_i.data;
        
        write_cmd = {VC_NUM{1'b0}};
        if(valid_flit_i)    
            write_cmd[data_i.vc_id] = 1;

        read_cmd = {VC_NUM{1'b0}};
        if(sa_valid_i)
            read_cmd[sa_sel_vc_i] = 1;

        xb_flit_o = data_out[sa_sel_vc_i];
    end

endmodule
