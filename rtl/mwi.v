`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:46:53
// Design Name: 
// Module Name: mwi
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


module mwi #(
    parameter sq_width = 48,   // must match 2*data_width+16 from squaring
    parameter N        = 32    // window size - power of 2 for shift division
)(
    input  wire clk,
    input  wire rst,
    input  wire sample_tick,
    input  wire [sq_width-1:0]   sq_in,
    output reg  [sq_width-1:0]   mwi_out
);

    integer i;

    // Buffer to hold last N samples
    reg [sq_width-1:0]   buffer [0:N-1];

    // Sum needs extra bits: sq_width + log2(N)
    // N=32 → log2(32)=5, so sq_width+5 bits
    reg [sq_width+4:0]   sum;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sum     <= 0;
            mwi_out <= 0;
            for(i=0; i<N; i=i+1)
                buffer[i] <= 0;
        end
        else if(sample_tick) begin
            // Update running sum:
            // add new sample, remove oldest (buffer[N-1])
            sum <= sum - buffer[N-1] + sq_in;

            // Shift buffer
            for(i=N-1; i>0; i=i-1)
                buffer[i] <= buffer[i-1];
            buffer[0] <= sq_in;

            // Divide by N=32 using right shift
            //notice how it recomputes sum, because of non blocking statements
            mwi_out <= (sum - buffer[N-1] + sq_in) >> 5;
        end
    end

endmodule