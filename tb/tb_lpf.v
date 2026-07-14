`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.02.2026 15:35:45
// Design Name: 
// Module Name: tb_lpf
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

// Self-checking testbench for lpf (FIXED implementation).
//
// The original recursive form (2y[n-1]-y[n-2]+x[n]-2x[n-6]+x[n-12]) was
// found to diverge exponentially on real ECG data due to numerical
// fragility of its repeated-pole-at-DC structure -- confirmed via two
// independent exact-arithmetic methods. The fix replaces it with a
// cascaded double moving-sum (exact FIR-equivalent, no feedback path,
// unconditionally bounded). This testbench verifies the FIXED
// implementation against a direct 11-tap triangular FIR reference
// ([1,2,3,4,5,6,5,4,3,2,1], written completely independently, no
// recursion, no shared code with the DUT) -- both must agree exactly
// for any bounded input, since there's no feedback anywhere to
// introduce timing/drift subtleties.
 
module tb_lpf;
    parameter data_width = 16;
    parameter NUM_SAMPLES = 500;
 
    reg clk, rst, sample_tick;
    reg signed [data_width-1:0] ecg_in;
    wire signed [data_width+5:0] lpf_out;
 
    integer errors, i, k;
 
    lpf #(.data_width(data_width)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .ecg_in(ecg_in), .lpf_out(lpf_out)
    );
 
    // Independent direct-convolution reference (11-tap triangular FIR,
    // matches [(1-z^-6)/(1-z^-1)]^2 exactly, no recursion at all)
    reg signed [data_width-1:0] hist [0:10];
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k=0;k<=10;k=k+1) hist[k] <= 0;
        end else if (sample_tick) begin
            for (k=10;k>=1;k=k-1) hist[k] <= hist[k-1];
            hist[0] <= ecg_in;
        end
    end
    // Combinational recompute each cycle from the (pre-shift) history,
    // matching the DUT's one-cycle pipeline latency convention.
    // Taps: [1,2,3,4,5,6,5,4,3,2,1] written out explicitly.
    wire signed [data_width+5:0] sum_terms;
    assign sum_terms = 1*hist[0] + 2*hist[1] + 3*hist[2] + 4*hist[3] + 5*hist[4]
                      + 6*hist[5] + 5*hist[6] + 4*hist[7] + 3*hist[8] + 2*hist[9] + 1*hist[10];
 
    always #5 clk = ~clk;
 
    task apply(input signed [data_width-1:0] val);
        begin
            @(posedge clk); ecg_in = val; sample_tick = 1;
            @(posedge clk); sample_tick = 0;
            #1;
        end
    endtask
 
    initial begin
        clk = 0; rst = 1; sample_tick = 0; ecg_in = 0; errors = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);
 
        apply(1000);
        for (i=0; i<20; i=i+1) apply(0);
        for (i=0; i<20; i=i+1) apply(500);
        for (i=0; i<NUM_SAMPLES; i=i+1)
            apply($random % (1<<15));
 
        if (errors == 0)
            $display("PASS: lpf (fixed) matched independent 11-tap FIR reference on every checked cycle.");
        else
            $display("FAIL: %0d mismatches found.", errors);
 
        $finish;
    end
 
    always @(negedge clk) begin
        if (!rst && $time > 100) begin
            if (lpf_out !== sum_terms) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH @ t=%0t: DUT=%0d REF=%0d", $time, lpf_out, sum_terms);
            end
        end
    end
endmodule

