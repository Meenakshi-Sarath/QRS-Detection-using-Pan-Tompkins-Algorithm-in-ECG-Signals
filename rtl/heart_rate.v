`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:48:02
// Design Name: 
// Module Name: heart_rate
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

module heart_rate #(
    parameter SAMPLE_RATE = 200
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire        peak,

    output reg  [7:0]  hr,
    output reg  [15:0] rr_interval,
    output reg         hr_valid
);

    reg [15:0] sample_counter;
    reg [15:0] last_rr;
    reg        first_peak_seen;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sample_counter  <= 16'd0;
            rr_interval     <= 16'd0;
            last_rr         <= 16'd0;
            hr              <= 8'd0;
            hr_valid        <= 1'b0;
            first_peak_seen <= 1'b0;
        end
        else if(sample_tick) begin

            sample_counter <= sample_counter + 1'b1;

            if(peak) begin

                if(first_peak_seen) begin

                    last_rr <= rr_interval;

                    // include current sample
                    rr_interval <= sample_counter + 1'b1;

                    if(sample_counter > 0)
                        hr <= (60*SAMPLE_RATE)/(sample_counter+1'b1);

                    hr_valid <= 1'b1;
                end
                else begin
                    first_peak_seen <= 1'b1;
                end

                sample_counter <= 16'd0;
            end
        end
    end

endmodule