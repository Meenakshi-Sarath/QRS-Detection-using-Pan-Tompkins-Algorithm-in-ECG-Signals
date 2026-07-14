`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:46:25
// Design Name: 
// Module Name: squaring
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


module squaring #(parameter data_width = 16)(
    input wire clk,
    input wire rst,
    input wire sample_tick,
    input wire signed [data_width+7:0] der_in,
    output reg [2*data_width+15:0] sq_out
);

    always @(posedge clk or posedge rst) begin
        if(rst)
            sq_out <= 0;
        else if(sample_tick)
            sq_out <= der_in * der_in;
    end

endmodule
