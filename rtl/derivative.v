`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:44:58
// Design Name: 
// Module Name: derivative
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module derivative #(parameter data_width = 16)(
    input  wire clk,
    input  wire rst,
    input  wire sample_tick,
    input  wire signed [data_width+7:0] hpf_in,
    output reg  signed [data_width+7:0] der_out
);

    integer i;
    reg signed [data_width+7:0] x_delay [0:4];

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            der_out <= 0;
            for(i=0; i<=4; i=i+1)
                x_delay[i] <= 0;
        end
        else if(sample_tick) begin

            // Shift delay line
            for(i=4; i>0; i=i-1)
                x_delay[i] <= x_delay[i-1];
            x_delay[0] <= hpf_in;

            // Pan-Tompkins derivative:
            // Y[n] = (1/8)(X[n] + 2X[n-1] - 2X[n-3] - X[n-4])
            der_out <= ( x_delay[0]
                        +  (x_delay[1] << 1)
                        -  (x_delay[3] << 1)
                        -  x_delay[4] ) >>> 3;
        end
    end

endmodule