import noc_params::*;

interface input_block2vc_allocator;

    logic [VC_SIZE-1:0] vc_new [PORT_NUM-1:0] [VC_NUM-1:0];
    logic [VC_NUM-1:0] vc_valid [PORT_NUM-1:0];
    logic [VC_NUM-1:0] vc_request [PORT_NUM-1:0];
    port_t [VC_NUM-1:0] out_port [PORT_NUM-1:0];
    //Modify retain legal route mask and return resolved grant direction, Michael Tan, 20261028
    logic [PORT_NUM-1:0] candidates [PORT_NUM-1:0][VC_NUM-1:0];
    port_t [VC_NUM-1:0] granted_port [PORT_NUM-1:0];

    modport input_block (
        input vc_new,
        //input vc_valid,//Original, Michael Tan, 20261028
        input vc_valid,
        input granted_port,//Modify receive chosen port together with VC, Michael Tan, 20261028
        output vc_request,
        //output out_port//Original, Michael Tan, 20261028
        output out_port,
        output candidates//Modify export legal candidates, Michael Tan, 20261028
    );

    modport vc_allocator (
        output vc_new,
        //output vc_valid,//Original, Michael Tan, 20261028
        output vc_valid,
        output granted_port,//Modify return actual allocated port, Michael Tan, 20261028
        input vc_request,
        //input out_port//Original, Michael Tan, 20261028
        input out_port,
        input candidates//Modify read legal candidates, Michael Tan, 20261028
    );

endinterface