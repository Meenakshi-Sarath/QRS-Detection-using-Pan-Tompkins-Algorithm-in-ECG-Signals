`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12.05.2026 15:55:09
// Design Name: 
// Module Name: arrhythmia_classify
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

module arrhythmia_classify #(
    parameter SAMPLE_RATE = 200
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        hr_valid,
    input  wire [7:0]  hr,
    input  wire [15:0] rr_interval,
    output reg  [2:0]  rhythm_class,
    output reg         alarm
);

    // Classification codes
    localparam NORMAL     = 3'd0;  // 60-100 BPM, regular
    localparam BRADYCARDIA= 3'd1;  // < 60 BPM
    localparam TACHYCARDIA= 3'd2;  // > 100 BPM
    localparam IRREGULAR  = 3'd3;  // RR varies > 20%
    localparam UNKNOWN    = 3'd4;  // not enough data yet

    reg [15:0] prev_rr;
    reg [15:0] rr_diff;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            rhythm_class <= UNKNOWN;
            alarm        <= 0;
            prev_rr      <= 0;
        end
        else if(hr_valid) begin

            // Compute RR difference (absolute)
            rr_diff <= (rr_interval > prev_rr) ?
                       (rr_interval - prev_rr) :
                       (prev_rr - rr_interval);

            prev_rr <= rr_interval;

            // Irregularity check: variation > 20% of prev_rr
            // 20% of prev_rr = prev_rr >> 2 (approx 25%, close enough)
            if(rr_diff > (prev_rr >> 2)) begin
                rhythm_class <= IRREGULAR;
                alarm        <= 1;
            end
            else if(hr < 60) begin
                rhythm_class <= BRADYCARDIA;
                alarm        <= 1;
            end
            else if(hr > 100) begin
                rhythm_class <= TACHYCARDIA;
                alarm        <= 1;
            end
            else begin
                rhythm_class <= NORMAL;
                alarm        <= 0;
            end
        end
        else begin
            rhythm_class <= UNKNOWN;
            alarm        <= 0;
        end
    end

endmodule
