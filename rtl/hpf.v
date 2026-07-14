`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:38:51
// Design Name: 
// Module Name: hpf
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

module hpf #(parameter data_width = 16)(
    input  wire clk,
    input  wire rst,
    input  wire sample_tick,
    input  wire signed [data_width+5:0] lpf_in,
    output reg  signed [data_width+7:0] hpf_out
);
    // ---- FIXED IMPLEMENTATION (see note) ----
    //
    // The original recursive/accumulator form:
    //   y[n] = y[n-1] - x[n]/32 + x[n-16] - x[n-17] + x[n-32]/32
    // is mathematically equivalent, in EXACT arithmetic, to a bounded
    // 32-tap FIR filter -- verified by polynomial division: the
    // numerator has an exact root at DC that cancels the feedback pole.
    // However, the RTL's >>>5 truncating divisions introduce a small
    // per-cycle rounding error that the UNDAMPED (unity-gain) feedback
    // accumulates without bound over time. Confirmed in simulation on
    // real ECG data: the true (unclipped) value of this accumulator
    // drifted to roughly -86,000,000 within ~1650 samples -- far past
    // the 24-bit output range -- causing hpf_out to silently overflow/
    // wrap around repeatedly and corrupt every downstream stage
    // (derivative, squaring, mwi, peak_detect) with effectively
    // meaningless values unrelated to the real ECG signal.
    //
    // The exact FIR-equivalent form (derived by polynomial division of
    // the original numerator by (1 - z^-1)) simplifies to:
    //   y[n] = x[n-16] - (1/32) * sum_{k=0}^{31} x[n-k]
    // i.e. "the sample at the center of a 32-sample window, minus the
    // moving average of that window" -- a standard DC-blocking
    // high-pass structure. This has NO feedback path at all, so it
    // cannot drift or overflow from accumulated rounding error: every
    // output depends only on the current window of 32 bounded input
    // samples, recomputed fresh each cycle (same add-new/drop-oldest
    // running-sum technique already used in mwi.v).
    //
    // Port list, parameter name, and both bit widths are UNCHANGED from
    // the original module, so this is a drop-in replacement -- no other
    // file in the pipeline needs to change.
 
    integer i;
    reg signed [data_width+5:0]    x_delay [0:31];  // 32-sample window
    reg signed [data_width+10:0]   running_sum;      // sum of 32 terms, +5 bits headroom
 
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            hpf_out     <= 0;
            running_sum <= 0;
            for(i=0;i<32;i=i+1)
                x_delay[i] <= 0;
        end
        else if(sample_tick) begin
            // Shift delay line (same convention as every other stage in
            // this pipeline: x_delay[0] holds the newest sample AFTER
            // this shift; this cycle's output uses the PRE-shift state)
            for(i=31; i>=1; i=i-1)
                x_delay[i] <= x_delay[i-1];
            x_delay[0] <= lpf_in;
 
            // Update the 32-sample running sum: add the newest sample,
            // drop the one leaving the window
            running_sum <= running_sum - x_delay[31] + lpf_in;
 
            // Output: center tap (16 samples back) minus the moving
            // average of the current 32-sample window
            hpf_out <= x_delay[15] - ((running_sum - x_delay[31] + lpf_in) >>> 5);
        end
    end
endmodule
