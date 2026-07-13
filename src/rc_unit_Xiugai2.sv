import noc_params::*;

module rc_unit #(
    parameter X_CURRENT = 0,
    parameter Y_CURRENT = 0,
    parameter DEST_ADDR_SIZE_X = 4,
    parameter DEST_ADDR_SIZE_Y = 4
)(
    input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest_i,
    input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest_i,

    input flit_label_t flit_label_i, //add
    
    output port_t out_port_o
);

    wire signed [DEST_ADDR_SIZE_X-1 : 0] x_offset;
    wire signed [DEST_ADDR_SIZE_Y-1 : 0] y_offset;

    assign x_offset = x_dest_i - X_CURRENT;
    assign y_offset = y_dest_i - Y_CURRENT;

    always_comb
    begin
        if (flit_label_i == HEAD | flit_label_i == HEADTAIL) //add by Michael Tan, 20260528, for flit body by rc_unit all port output
        begin //add by Michael Tan, 20260528, for flit body by rc_unit all port output
            unique if (x_dest_i < X_CURRENT)
            begin
                out_port_o = WEST;
            end
            else if (x_dest_i > X_CURRENT)
            begin
                out_port_o = EAST;
            end
            else if (x_dest_i == X_CURRENT & y_dest_i < Y_CURRENT)
            begin
                out_port_o = NORTH;
            end
            else if (x_dest_i == X_CURRENT & y_dest_i > Y_CURRENT)
            begin
                out_port_o = SOUTH;
            end
            else
            begin
                out_port_o = LOCAL;
            end
        end //add by Michael Tan, 20260528, for flit body by rc_unit all port output
    end
endmodule