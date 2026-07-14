`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 12:57:28
// Design Name: 
// Module Name: tb_heart_rate
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


module tb_heart_rate;
    parameter SAMPLE_RATE = 200;
 
    reg clk, rst, sample_tick, peak;
    wire [7:0]  hr;
    wire [15:0] rr_interval;
    wire        hr_valid;
 
    integer errors;
 
    heart_rate #(.SAMPLE_RATE(SAMPLE_RATE)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .peak(peak),
        .hr(hr), .rr_interval(rr_interval), .hr_valid(hr_valid)
    );
 
    always #5 clk = ~clk;
 
    // Runs n_ticks sample_tick pulses; asserts peak high on the LAST tick
    // of the interval (i.e. two consecutive calls place peaks n_ticks
    // samples apart).
    task run_interval(input integer n_ticks);
        integer k;
        begin
            for (k = 0; k < n_ticks - 1; k = k + 1) begin
                @(posedge clk); sample_tick = 1; peak = 0;
                @(posedge clk); sample_tick = 0;
            end
            @(posedge clk); sample_tick = 1; peak = 1;
            @(posedge clk); sample_tick = 0; peak = 0;
            #1;
        end
    endtask
 
    task check(input [127:0] label, input integer exp_hr, input integer exp_rr);
        begin
            if (hr !== exp_hr[7:0]) begin
                errors = errors+1; $display("FAIL %0s: hr=%0d expected=%0d", label, hr, exp_hr);
            end else
                $display("PASS %0s: hr=%0d as expected", label, hr);
            if (rr_interval !== exp_rr[15:0]) begin
                errors = errors+1; $display("FAIL %0s: rr_interval=%0d expected=%0d", label, rr_interval, exp_rr);
            end
        end
    endtask
 
    initial begin
        clk = 0; rst = 1; sample_tick = 0; peak = 0; errors = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);
 
        // First peak only starts the timer -- hr_valid must stay low
        // (module correctly requires two peaks before it can report a
        // real RR interval / HR)
        run_interval(200);
        if (hr_valid !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: hr_valid asserted after only ONE peak (should need two)");
        end else
            $display("PASS: hr_valid correctly low after first peak only");
 
        // 200 samples between peaks (1s @ 200Hz) => 60 bpm
        run_interval(200);
        check("60bpm_case", 60, 200);
        if (hr_valid !== 1'b1) begin errors=errors+1; $display("FAIL: hr_valid not set after 2nd peak"); end
 
        // 100 samples between peaks (0.5s) => 120 bpm
        run_interval(100);
        check("120bpm_case", 120, 100);
 
        // 267 samples between peaks => 60*200/267 = 44 bpm (bradycardia range)
        run_interval(267);
        check("44bpm_case", 44, 267);
 
        // 133 samples between peaks => 60*200/133 = 90 bpm (normal range)
        run_interval(133);
        check("90bpm_case", 90, 133);
 
        // Reset mid-stream should clear everything
        rst = 1;
        @(posedge clk); @(posedge clk);
        rst = 0;
        @(posedge clk);
        if (hr_valid !== 1'b0 || hr !== 8'd0) begin
            errors = errors + 1;
            $display("FAIL: reset did not clear hr/hr_valid");
        end else
            $display("PASS: reset correctly clears state");
 
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule

