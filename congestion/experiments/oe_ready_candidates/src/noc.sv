package noc_params;
	localparam MESH_SIZE_X = 13;
	localparam MESH_SIZE_Y = 13;

	localparam DEST_ADDR_SIZE_X = $clog2(MESH_SIZE_X);
	localparam DEST_ADDR_SIZE_Y = $clog2(MESH_SIZE_Y);

	localparam VC_NUM = 4;
	localparam VC_SIZE = $clog2(VC_NUM);

	localparam PACKET_ID_SIZE = 12;
	localparam BACKUP_SIZE = 8;
	localparam HEAD_PAYLOAD_SIZE = 218;

	typedef enum logic [2:0] {LOCAL, NORTH, SOUTH, WEST, EAST} port_t;
	localparam PORT_NUM = 5;
	localparam PORT_SIZE = $clog2(PORT_NUM);

	typedef enum logic [1:0] {HEAD, BODY, TAIL, HEADTAIL} flit_label_t;

	typedef struct packed
	{
		logic [DEST_ADDR_SIZE_X-1 : 0] 	x_source;
		logic [DEST_ADDR_SIZE_Y-1 : 0] 	y_source;
		logic [DEST_ADDR_SIZE_X-1 : 0] 	x_dest;
		logic [DEST_ADDR_SIZE_Y-1 : 0] 	y_dest;
		logic [PACKET_ID_SIZE-1 : 0] 	packet_id;
		logic [BACKUP_SIZE-1 : 0] 		backup;
		logic [HEAD_PAYLOAD_SIZE-1: 0] 	head_pl;
	} head_data_t;

	localparam FLIT_DATA_SIZE = $bits(head_data_t);

	typedef struct packed
	{
		flit_label_t			flit_label;
		logic [VC_SIZE-1 : 0] 	vc_id;
		union packed
		{
			head_data_t 		head_data;
			logic [FLIT_DATA_SIZE-1 : 0] bt_pl;
		} data;
	} flit_t;

    typedef struct packed
    {
        flit_label_t flit_label;
        union packed
        {
            head_data_t head_data;
            logic [FLIT_DATA_SIZE-1 : 0] bt_pl;
        } data;
    } flit_novc_t;

    // 默认 BUFFER_SIZE 用于计算位宽常量
    localparam BUFFER_SIZE_DEFAULT = 8;

    // 每个 VC 的占用数位宽（0 到 BUFFER_SIZE）
    localparam OCCUPANCY_WIDTH = $clog2(BUFFER_SIZE_DEFAULT) + 1;

    // 每个方向总占用数位宽（0 到 BUFFER_SIZE * VC_NUM）
    localparam DIR_OCCUPANCY_WIDTH = $clog2(BUFFER_SIZE_DEFAULT * VC_NUM) + 1;

    // 每个节点总流量位宽（0 到 BUFFER_SIZE * VC_NUM * PORT_NUM）
    localparam TOTAL_FLOW_WIDTH = $clog2(BUFFER_SIZE_DEFAULT * VC_NUM * PORT_NUM) + 1;

    // 拥塞等级位宽（等级 1~10（0~9），用 4 bits 表示）
    localparam CONGESTION_LEVEL_WIDTH = 4;

    // 路由器状态信息类型――每个路由器输出到状态信息收集模块
    typedef struct packed {
        logic [PORT_NUM-1:0][VC_NUM-1:0][OCCUPANCY_WIDTH-1:0] vc_occupancy;
        logic [PORT_NUM-1:0][VC_NUM-1:0] is_full;
        logic [PORT_NUM-1:0][VC_NUM-1:0] is_empty;
    } router_state_t;

    // 决策参考指标类型――状态信息收集模块输出给拥塞判决模块
    typedef struct packed {
        logic [PORT_NUM-1:0][DIR_OCCUPANCY_WIDTH-1:0] per_dir_total_occupancy;
        logic [PORT_NUM-1:0][CONGESTION_LEVEL_WIDTH-1:0] per_dir_congestion_level;
        logic [TOTAL_FLOW_WIDTH-1:0] node_total_flow;
    } metrics_t;

    // 拥塞判决模块输出类型
    typedef struct packed {
        port_t out_port;        // 选择的路由方向
        logic valid;            // 输出有效
    } cong_decision_t;

endpackage