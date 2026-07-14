`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 12:34:41
// Design Name: 
// Module Name: tb_peak_detect
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

// DESIGN NOTE (not a bug, just how this module behaves): SPKI/NPKI/TH1
// all reset to 0, so the very first nonzero sample above 0 will
// immediately register as a peak, before any adaptive threshold has
// "learned" anything. Real Pan-Tompkins implementations often have an
// explicit ~2s warm-up/learning phase before trusting detections. This
// testbench documents that startup behavior explicitly rather than
// treating it as a surprise.

module tb_peak_detect;
    parameter data_width = 48;
    parameter REFRACTORY = 40;
    parameter WARMUP_SAMPLES = 8;   // small for fast unit-testing
    reg clk, rst, sample_tick;
    reg [data_width-1:0] mwi_in;
    wire peak;
    integer errors, i;
 
    peak_detect #(.data_width(data_width), .REFRACTORY(REFRACTORY), .WARMUP_SAMPLES(WARMUP_SAMPLES)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .mwi_in(mwi_in), .peak(peak)
    );
 
    always #5 clk = ~clk;
 
    task apply(input [data_width-1:0] val);
        begin
            @(posedge clk); mwi_in = val; sample_tick = 1;
            @(posedge clk); sample_tick = 0;
            #1;
        end
    endtask
 
    initial begin
        clk=0; rst=1; sample_tick=0; mwi_in=0; errors=0;
        repeat(4) @(posedge clk);
        rst=0; @(posedge clk);
 
        // During warm-up (first WARMUP_SAMPLES ticks), peak must NEVER assert,
        // even for very large mwi_in values.
        for (i=0;i<WARMUP_SAMPLES;i=i+1) begin
            apply(64'd90000);
            if (peak !== 1'b0) begin
                errors=errors+1;
                $display("FAIL: peak asserted during warm-up at step %0d", i);
            end
        end
        $display("Warm-up check done: peak stayed 0 for %0d samples", WARMUP_SAMPLES);
 
        // After warm-up, SPKI/NPKI should be seeded (nonzero) rather than 0
        if (DUT.SPKI == 0 || DUT.warmup_done !== 1'b1) begin
            errors=errors+1;
            $display("FAIL: warm-up did not complete / SPKI not seeded. SPKI=%0d warmup_done=%0d", DUT.SPKI, DUT.warmup_done);
        end else
            $display("PASS: warm-up completed, SPKI seeded to %0d, NPKI seeded to %0d, TH1=%0d", DUT.SPKI, DUT.NPKI, DUT.TH1);
 
        // Now normal detection should work: strong sample should be a peak
        apply(64'd200000);
        if (peak !== 1'b1) begin
            errors=errors+1;
            $display("FAIL: expected peak=1 on strong post-warmup sample, got %0d", peak);
        end else
            $display("PASS: peak correctly detected after warm-up");
 
        // Refractory lockout still works post-warmup
        for (i=0;i<REFRACTORY;i=i+1) begin
            apply(64'd200000);
            if (peak !== 1'b0) begin
                errors=errors+1;
                $display("FAIL: peak asserted during refractory period at step %0d", i);
            end
        end
        apply(64'd200000);
        if (peak !== 1'b1) begin
            errors=errors+1;
            $display("FAIL: expected peak=1 again after refractory ended");
        end else
            $display("PASS: peak correctly re-triggered after refractory ended");
 
        // Reset clears warm-up state too
        rst=1; @(posedge clk); @(posedge clk); rst=0; @(posedge clk);
        if (DUT.warmup_done !== 1'b0 || DUT.SPKI !== 0 || DUT.NPKI !== 0) begin
            errors=errors+1;
            $display("FAIL: reset did not clear warm-up/threshold state");
        end else
            $display("PASS: reset clears warm-up and threshold state");
 
        if (errors==0) $display("ALL PASS");
        else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule

