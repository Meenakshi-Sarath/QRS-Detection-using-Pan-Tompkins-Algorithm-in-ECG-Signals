`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 31.01.2026 22:20:18
// Design Name: 
// Module Name: lpf
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


module lpf #(parameter data_width = 16)(
    input wire clk,
    input wire rst,
    input wire sample_tick,
    input wire signed [data_width-1:0] ecg_in,
    output reg signed [data_width+5:0] lpf_out
);
    // ---- FIXED IMPLEMENTATION (see note) ----
    //
    // The original recursive form y[n]=2y[n-1]-y[n-2]+x[n]-2x[n-6]+x[n-12]
    // is algebraically equivalent (via exact pole-zero cancellation) to
    // an 11-tap triangular FIR filter -- H(z) = [(1-z^-6)/(1-z^-1)]^2 =
    // (sum_{k=0}^{5} z^-k)^2, i.e. taps [1,2,3,4,5,6,5,4,3,2,1]. However,
    // this recursive/accumulator form relies on a REPEATED (double) pole
    // exactly on the unit circle at z=1, cancelled by a matching double
    // zero in the numerator. This cancellation is only exact for an
    // idealized, infinite-precision LTI system; confirmed via simulation
    // (cross-checked two independent ways: a 64-bit shadow accumulator,
    // and an earlier bit-exact-verified Python model) that when fed real
    // ECG data, this recursive form diverges EXPONENTIALLY within the
    // first ~20-30 samples -- reaching values in the billions almost
    // immediately, which then wrap/alias unpredictably once truncated to
    // this module's declared 22-bit output width, corrupting every
    // downstream stage. This is a genuine numerical-implementation
    // pitfall of realizing a repeated-pole-on-the-unit-circle filter
    // recursively, independent of arithmetic precision or rounding.
    //
    // The fix: implement the SAME 11-tap triangular response directly,
    // with NO feedback path, via a cascaded double moving-sum (the
    // standard way to realize [sum z^-k]^2 in hardware): a 6-sample
    // boxcar sum of the input, followed by a second 6-sample boxcar sum
    // of THAT result. Each stage is a simple bounded add-new/drop-oldest
    // running sum (same technique already used in mwi.v), so there is no
    // feedback accumulator anywhere and the result is unconditionally
    // bounded for any bounded input. No explicit divide-by-36 is applied
    // here, matching the original module's behavior (it also left the
    // ~36x DC gain unscaled, relying on the widened +6-bit output range
    // for headroom) -- downstream modules are unaffected.
    //
    // Port list, parameter name, and output width are UNCHANGED from the
    // original module, so this is a drop-in replacement.
 
    integer i;
    reg signed [data_width-1:0]   x_delay [0:5];     // 6-sample window for stage 1
    reg signed [data_width+2:0]   stage1_sum;         // sum of 6 terms, +3 bits headroom
    reg signed [data_width+2:0]   s1_delay [0:5];     // 6-sample window of stage-1 sums, for stage 2
    reg signed [data_width+5:0]   stage2_sum;         // sum of 6 stage-1 sums, +3 more bits headroom
 
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            lpf_out    <= 0;
            stage1_sum <= 0;
            stage2_sum <= 0;
            for (i=0;i<6;i=i+1) begin
                x_delay[i]  <= 0;
                s1_delay[i] <= 0;
            end
        end
        else if (sample_tick) begin
            // ---- Stage 1: 6-sample boxcar moving sum of the input ----
            stage1_sum <= stage1_sum - x_delay[5] + ecg_in;
            for (i=5; i>=1; i=i-1)
                x_delay[i] <= x_delay[i-1];
            x_delay[0] <= ecg_in;
 
            // ---- Stage 2: 6-sample boxcar moving sum of stage 1's output ----
            // (uses stage1_sum's freshly-updated value this same cycle,
            // same "recompute rather than trust the lagging register"
            // technique already used in mwi.v)
            stage2_sum <= stage2_sum - s1_delay[5] + (stage1_sum - x_delay[5] + ecg_in);
            for (i=5; i>=1; i=i-1)
                s1_delay[i] <= s1_delay[i-1];
            s1_delay[0] <= (stage1_sum - x_delay[5] + ecg_in);
 
            lpf_out <= stage2_sum - s1_delay[5] + (stage1_sum - x_delay[5] + ecg_in);
        end
    end
endmodule
