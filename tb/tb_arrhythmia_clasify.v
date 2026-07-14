`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 15:44:06
// Design Name: 
// Module Name: tb_arrhythmia_clasify
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


// IMPORTANT DESIGN NOTE (confirmed in simulation, not a testbench
// artifact): rhythm_class/alarm are only valid on the clock edge right
// after hr_valid is sampled high. If hr_valid is a single-cycle pulse
// (as heart_rate's hr_valid effectively behaves like once it first goes
// high, combined with how quickly rr_interval/hr change at 100MHz vs a
// 200Hz sample_tick), the classifier reverts to UNKNOWN the very next
// cycle. Any downstream logic (e.g. an FSM or register) that wants to
// "latch" a classification needs to sample rhythm_class on the same
// cycle hr_valid is asserted, not one cycle later. This testbench
// captures results at the correct moment to reflect that.
//
// ALSO NOTE: prev_rr resets to 0, so the very first classified beat
// after reset will always compute rr_diff = rr_interval - 0, which is
// greater than (prev_rr>>2)=0 for any nonzero RR -- meaning the first
// beat after every reset is always classified IRREGULAR regardless of
// its actual heart rate. This is a real characteristic of the design
// (prev_rr's reset value), not a bug in this testbench.
 
module tb_arrhythmia_classify;
    reg clk, rst, hr_valid;
    reg [7:0] hr;
    reg [15:0] rr_interval;
    wire [2:0] rhythm_class;
    wire alarm;
    integer errors;
 
    localparam NORMAL      = 3'd0;
    localparam BRADYCARDIA = 3'd1;
    localparam TACHYCARDIA = 3'd2;
    localparam IRREGULAR   = 3'd3;
    localparam UNKNOWN     = 3'd4;
 
    arrhythmia_classify DUT (
        .clk(clk), .rst(rst), .hr_valid(hr_valid),
        .hr(hr), .rr_interval(rr_interval),
        .rhythm_class(rhythm_class), .alarm(alarm)
    );
 
    always #5 clk = ~clk;
 
    reg [2:0] result_class;
    reg       result_alarm;
 
    task pulse_and_capture(input [7:0] hrv, input [15:0] rrv);
        begin
            @(posedge clk); hr = hrv; rr_interval = rrv; hr_valid = 1;
            @(posedge clk);
            #1;
            result_class = rhythm_class;
            result_alarm = alarm;
            hr_valid = 0;
            @(posedge clk); #1;   // let it settle back to UNKNOWN before next stimulus
        end
    endtask
 
    initial begin
        clk=0; rst=1; hr_valid=0; hr=0; rr_interval=0; errors=0;
        repeat(4) @(posedge clk);
        rst=0; @(posedge clk);
 
        // Beat 1: prev_rr=0 after reset -> always IRREGULAR on first beat
        pulse_and_capture(75, 160);
        $display("Beat1 (hr=75,rr=160): class=%0d alarm=%0d  [expect IRREGULAR=3, prev_rr was 0]", result_class, result_alarm);
        if (result_class !== IRREGULAR) begin errors=errors+1; $display("  FAIL"); end
 
        // Beat 2: same RR as beat 1 -> rr_diff=0, within tolerance -> NORMAL
        pulse_and_capture(75, 160);
        $display("Beat2 (hr=75,rr=160,steady): class=%0d alarm=%0d  [expect NORMAL=0]", result_class, result_alarm);
        if (result_class !== NORMAL || result_alarm !== 1'b0) begin errors=errors+1; $display("  FAIL"); end
 
        // Beat 3: still steady -> still NORMAL
        pulse_and_capture(75, 160);
        $display("Beat3 (steady): class=%0d alarm=%0d  [expect NORMAL=0]", result_class, result_alarm);
        if (result_class !== NORMAL) begin errors=errors+1; $display("  FAIL"); end
 
        // Beat 4: RR jumps 160->240 (50% change) -> IRREGULAR wins over bradycardia
        pulse_and_capture(50, 240);
        $display("Beat4 (hr=50,rr=240, jumped from 160): class=%0d alarm=%0d  [expect IRREGULAR=3]", result_class, result_alarm);
        if (result_class !== IRREGULAR) begin errors=errors+1; $display("  FAIL"); end
 
        // Beat 5: RR settles near 240 (+5 only) -> not irregular; hr=50<60 -> BRADYCARDIA
        pulse_and_capture(50, 245);
        $display("Beat5 (hr=50,rr=245,steady-ish): class=%0d alarm=%0d  [expect BRADYCARDIA=1]", result_class, result_alarm);
        if (result_class !== BRADYCARDIA || result_alarm !== 1'b1) begin errors=errors+1; $display("  FAIL"); end
 
        // Beat 6: RR jumps 245->100 (big change) -> IRREGULAR wins over tachycardia
        pulse_and_capture(120, 100);
        $display("Beat6 (hr=120,rr=100, jumped from 245): class=%0d alarm=%0d  [expect IRREGULAR=3]", result_class, result_alarm);
        if (result_class !== IRREGULAR) begin errors=errors+1; $display("  FAIL"); end
 
        // Beat 7: RR settles near 100 (-2 only) -> not irregular; hr=120>100 -> TACHYCARDIA
        pulse_and_capture(120, 98);
        $display("Beat7 (hr=120,rr=98,steady-ish): class=%0d alarm=%0d  [expect TACHYCARDIA=2]", result_class, result_alarm);
        if (result_class !== TACHYCARDIA || result_alarm !== 1'b1) begin errors=errors+1; $display("  FAIL"); end
 
        // hr_valid low (no new beat) -> classifier reports UNKNOWN
        @(posedge clk); hr_valid=0; @(posedge clk); #1;
        $display("hr_valid=0 (idle): class=%0d alarm=%0d  [expect UNKNOWN=4]", rhythm_class, alarm);
        if (rhythm_class !== UNKNOWN) begin errors=errors+1; $display("  FAIL"); end
 
        // Reset clears to UNKNOWN, alarm low
        rst=1; @(posedge clk); @(posedge clk); rst=0; @(posedge clk); #1;
        if (rhythm_class !== UNKNOWN || alarm !== 1'b0) begin
            errors=errors+1; $display("FAIL: reset did not clear to UNKNOWN/alarm=0");
        end else
            $display("PASS: reset clears to UNKNOWN, alarm=0");
 
        if (errors==0) $display("ALL PASS");
        else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule

