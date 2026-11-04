import noc_params::*;

//Modify deterministic minimal XY with per-hop dateline eligibility, Michael Tan, 20261102
module rc_unit #(
    parameter X_CURRENT = 0,
    parameter Y_CURRENT = 0,
    parameter DEST_ADDR_SIZE_X = 4,
    parameter DEST_ADDR_SIZE_Y = 4,
    parameter TORUS_MODE = 0,
    parameter NETWORK_SIZE_X = MESH_SIZE_X,
    parameter NETWORK_SIZE_Y = MESH_SIZE_Y,
    parameter INPUT_PORT = LOCAL
)(
    input logic [DEST_ADDR_SIZE_X-1:0] x_dest_i,
    input logic [DEST_ADDR_SIZE_Y-1:0] y_dest_i,
    input flit_label_t flit_label_i,
    input logic [VC_SIZE-1:0] input_vc_i,
    output port_t out_port_o,
    output logic [VC_NUM-1:0] allowed_vcs_o,
    output logic route_error_o
);
    int east_distance, west_distance, south_distance, north_distance;
    logic crossing, after_line;
    always_comb begin
        out_port_o = LOCAL;
        allowed_vcs_o = '1;
        route_error_o = 0;
        crossing = 0;
        after_line = 0;
        east_distance = 0; west_distance = 0;
        south_distance = 0; north_distance = 0;
        if (flit_label_i == HEAD || flit_label_i == HEADTAIL) begin
            if (!TORUS_MODE) begin
                if (x_dest_i < X_CURRENT) out_port_o = WEST;
                else if (x_dest_i > X_CURRENT) out_port_o = EAST;
                else if (y_dest_i < Y_CURRENT) out_port_o = NORTH;
                else if (y_dest_i > Y_CURRENT) out_port_o = SOUTH;
            end else if (x_dest_i >= NETWORK_SIZE_X || y_dest_i >= NETWORK_SIZE_Y) begin
                // Invalid headers are rejected by the input port and diagnosed.
                allowed_vcs_o = '0;
                route_error_o = 1;
            end else begin
                east_distance = (int'(x_dest_i) - X_CURRENT + NETWORK_SIZE_X);
                if (east_distance >= NETWORK_SIZE_X) east_distance -= NETWORK_SIZE_X;
                west_distance = (X_CURRENT - int'(x_dest_i) + NETWORK_SIZE_X);
                if (west_distance >= NETWORK_SIZE_X) west_distance -= NETWORK_SIZE_X;
                south_distance = (int'(y_dest_i) - Y_CURRENT + NETWORK_SIZE_Y);
                if (south_distance >= NETWORK_SIZE_Y) south_distance -= NETWORK_SIZE_Y;
                north_distance = (Y_CURRENT - int'(y_dest_i) + NETWORK_SIZE_Y);
                if (north_distance >= NETWORK_SIZE_Y) north_distance -= NETWORK_SIZE_Y;
                if (x_dest_i != X_CURRENT)
                    out_port_o = (east_distance <= west_distance) ? EAST : WEST;
                else if (y_dest_i != Y_CURRENT)
                    out_port_o = (south_distance <= north_distance) ? SOUTH : NORTH;
                if (out_port_o == EAST || out_port_o == WEST) begin
                    crossing = (out_port_o == EAST && X_CURRENT == NETWORK_SIZE_X-1) ||
                               (out_port_o == WEST && X_CURRENT == 0);
                    //allowed_vcs_o = 1 << next_class;//Original, Michael Tan, 20261104
                    //Modify retain dateline phase across either same-dimension replica, Michael Tan, 20261104
                    after_line = ((INPUT_PORT == EAST || INPUT_PORT == WEST) &&
                                  int'(input_vc_i) >= TORUS_VCS_PER_PHASE);
                    allowed_vcs_o = (after_line || crossing) ? VC_AFTER_MASK : VC_BEFORE_MASK;
                    //Modify dimension comes from the physical port; only Y-to-X is forbidden, Michael Tan, 20261104
                    if (INPUT_PORT == NORTH || INPUT_PORT == SOUTH)
                        route_error_o = 1;
                end else if (out_port_o == NORTH || out_port_o == SOUTH) begin
                    crossing = (out_port_o == SOUTH && Y_CURRENT == NETWORK_SIZE_Y-1) ||
                               (out_port_o == NORTH && Y_CURRENT == 0);
                    //Modify initialize Y phase on X-to-Y turn and ignore LOCAL injection VC phase, Michael Tan, 20261104
                    after_line = ((INPUT_PORT == NORTH || INPUT_PORT == SOUTH) &&
                                  int'(input_vc_i) >= TORUS_VCS_PER_PHASE);
                    allowed_vcs_o = (after_line || crossing) ? VC_AFTER_MASK : VC_BEFORE_MASK;
                end
                //Modify preserve four endpoint resources while network VC count is varied, Michael Tan, 20261104
                if (out_port_o == LOCAL) allowed_vcs_o = VC_LOCAL_MASK;
                if (route_error_o) allowed_vcs_o = '0;
            end
        end
    end
endmodule
