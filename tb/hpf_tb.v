`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:12:37
// Design Name: 
// Module Name: hpf_tb
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


// Self-checking testbench for hpf (FIXED implementation).
//
// The original recursive form was found to accumulate unbounded drift
// over time on real ECG data due to truncation bias in an undamped
// feedback loop -- confirmed via a 64-bit shadow-accumulator comparison
// showing the true value drifting to ~-86,000,000 within 1650 samples.
// The fix replaces it with the exact FIR-equivalent form:
//   y[n] = x[n-16] - (1/32)*sum_{k=0}^{31} x[n-k]
// (center tap minus the moving average of a 32-sample window), which
// has no feedback path and is unconditionally bounded. This testbench
// verifies the FIXED implementation against that same formula computed
// completely independently (own delay line, own sum, no shared code
// with the DUT).
 
module tb_hpf;
    parameter data_width = 16;
    parameter NUM_SAMPLES = 500;
 
    reg clk, rst, sample_tick;
    reg signed [data_width+5:0] lpf_in;
    wire signed [data_width+7:0] hpf_out;
 
    integer errors, i, k;
 
    hpf #(.data_width(data_width)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .lpf_in(lpf_in), .hpf_out(hpf_out)
    );
 
    // Independent reference: same "center tap minus moving average"
    // formula, own state, no shared code with the DUT.
    reg signed [data_width+5:0] rhist [0:31];
    reg signed [data_width+10:0] rsum;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rsum <= 0;
            for (k=0;k<32;k=k+1) rhist[k] <= 0;
        end else if (sample_tick) begin
            rsum <= rsum - rhist[31] + lpf_in;
            for (k=31;k>=1;k=k-1) rhist[k] <= rhist[k-1];
            rhist[0] <= lpf_in;
        end
    end
    //reg signed [data_width-1:0]  dummy; // placeholder not used
    reg signed [data_width+7:0]  ref_out;
    always @(posedge clk or posedge rst) begin
        if (rst)
            ref_out <= 0;
        else if (sample_tick)
            ref_out <= rhist[15] - ((rsum - rhist[31] + lpf_in) >>> 5);
    end
 
    always #5 clk = ~clk;
 
    task apply(input signed [data_width+5:0] val);
        begin
            @(posedge clk); lpf_in = val; sample_tick = 1;
            @(posedge clk); sample_tick = 0;
            #1;
        end
    endtask
 
    initial begin
        clk=0; rst=1; sample_tick=0; lpf_in=0; errors=0;
        repeat(4) @(posedge clk);
        rst=0; @(posedge clk);
 
        apply(1000);
        for (i=0;i<40;i=i+1) apply(0);
        for (i=0;i<40;i=i+1) apply(500);
        for (i=0;i<NUM_SAMPLES;i=i+1)
            apply($random % (1<<21));
 
        if (errors==0)
            $display("PASS: hpf (fixed) matched independent reference on every checked cycle.");
        else
            $display("FAIL: %0d mismatches found.", errors);
        $finish;
    end
 
    always @(negedge clk) begin
        if (!rst && $time > 100)
            if (hpf_out !== ref_out) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH @ t=%0t: DUT=%0d REF=%0d", $time, hpf_out, ref_out);
            end
    end
endmodule


