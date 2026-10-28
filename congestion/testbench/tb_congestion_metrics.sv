`timescale 1ns/1ps
import noc_params::*;
//Modify independently check occupancy aggregation and all level thresholds, Michael Tan, 20261028
module tb_congestion_metrics;
    router_state_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] states;
    metrics_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] metrics;
    int checks=0;
    state_information_collection #(.BUFFER_SIZE(8)) dut(.router_state_i(states),.metrics_o(metrics));
    task automatic verify;
        int sum, node_sum, level;
        for(int x=0;x<MESH_SIZE_X;x++) for(int y=0;y<MESH_SIZE_Y;y++) begin
            node_sum=0;
            for(int p=0;p<PORT_NUM;p++) begin
                sum=0;
                for(int v=0;v<VC_NUM;v++) sum+=int'(states[x][y].vc_occupancy[p][v]);
                level=(sum*10+31)/32;
                if(level<1) level=1;
                if(level>9) level=9;
                if(metrics[x][y].per_dir_total_occupancy[p] !== sum ||
                   metrics[x][y].per_dir_congestion_level[p] !== level)
                    $fatal(1,"metric mismatch x=%0d y=%0d p=%0d sum=%0d level=%0d",x,y,p,sum,level);
                node_sum+=sum; checks++;
            end
            if(metrics[x][y].node_total_flow !== node_sum) $fatal(1,"node sum mismatch");
            checks++;
        end
    endtask
    initial begin
        states='0; #1; verify();
        for(int n=0;n<=32;n++) begin
            for(int x=0;x<MESH_SIZE_X;x++) for(int y=0;y<MESH_SIZE_Y;y++)
                for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++)
                    states[x][y].vc_occupancy[p][v]=(n>8*(v+1)) ? 8 : ((n>8*v) ? n-8*v : 0);
            #1; verify();
        end
        // Spatially distinct values detect transposed coordinates, ports and VCs.
        for(int n=0;n<19;n++) begin
            for(int x=0;x<MESH_SIZE_X;x++) for(int y=0;y<MESH_SIZE_Y;y++) begin
                states[x][y].is_full='1; states[x][y].is_empty='1;
                for(int p=0;p<PORT_NUM;p++) for(int v=0;v<VC_NUM;v++)
                    states[x][y].vc_occupancy[p][v]=(x*7+y*3+p*2+v+n)%9;
            end
            #1; verify();
        end
        states='0; #1; verify();
        $display("[TB_CONGESTION_METRICS] PASSED checks=%0d snapshots=54 nodes=169 thresholds=0_to_32",checks);
        $finish;
    end
endmodule
