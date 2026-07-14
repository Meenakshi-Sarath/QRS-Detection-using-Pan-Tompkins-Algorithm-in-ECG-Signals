`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.07.2026 20:44:15
// Design Name: 
// Module Name: tb_ecg_top
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


// tb_ecg_top.v
//
// Full-pipeline integration test against the CORRECTED design:
//   ecg_rom -> lpf(fixed) -> hpf(fixed) -> derivative -> squaring -> mwi
//            -> peak_detect(fixed, with warm-up) -> heart_rate
//            -> arrhythmia_classify
//
// This replaces the earlier structural-only version. Since lpf, hpf, and
// peak_detect were all found and fixed during integration testing
// against real ecg.mem (see design notes in lpf.v/hpf.v/peak_detect.v),
// this testbench now checks MEANINGFUL signal-tracking behavior instead
// of just "the pipeline is alive":
//   - peaks must NOT all be spaced identically (that was the symptom of
//     the original bugs -- peak_detect locking onto a fixed
//     REFRACTORY-driven cadence instead of tracking the real signal)
//   - peak spacing must fall in a broad physiologically-plausible band
//   - no X/Z propagation, rhythm_class must leave UNKNOWN
//
// IMPORTANT: clk_freq is overridden to a small value (2000, not your
// real 100_000_000) purely to make SIMULATION fast -- see earlier notes.
// Use clk_freq=100_000_000 for synthesis; only override it here.
 
module tb_ecg_top;
    parameter clk_freq    = 2000;
    parameter addr_width  = 12;
    parameter data_width  = 16;
    parameter sample_rate = 200;
    parameter REFRACTORY  = 60;   // matches peak_detect's updated default (see peak_detect.v notes)
    parameter MWI_N       = 32;
    parameter RUN_SAMPLES = 4000;   // covers essentially the whole 4096-sample ecg.mem
 
    reg clk, rst;
    wire [7:0]  hr;
    wire [15:0] rr_interval;
    wire        hr_valid;
    wire [2:0]  rhythm_class;
    wire        alarm;
    wire        sample_tick;
    wire signed [data_width-1:0] ecg_sample;
    wire        peak;
    wire [2*data_width+15:0] mwi_out_dbg;
 
    integer errors;
    integer sample_count;
    integer peak_count;
    integer last_peak_sample;
    integer spacing;
    integer min_spacing, max_spacing;
    integer distinct_spacings_seen;
    integer last_spacing;
    reg     saw_varying_spacing;
    reg     saw_nonunknown_class;
    integer last_hr_seen;
 
    localparam UNKNOWN = 3'd4;
 
    ecg_top #(
        .clk_freq(clk_freq), .addr_width(addr_width), .data_width(data_width),
        .sample_rate(sample_rate), .REFRACTORY(REFRACTORY), .MWI_N(MWI_N)
    ) DUT (
        .clk(clk), .rst(rst), .hr(hr), .rr_interval(rr_interval), .hr_valid(hr_valid),
        .rhythm_class(rhythm_class), .alarm(alarm), .sample_tick(sample_tick),
        .ecg_sample(ecg_sample), .peak(peak), .mwi_out_dbg(mwi_out_dbg)
    );
 
    always #5 clk = ~clk;
 
    always @(posedge clk) begin
        if (!rst) begin
            if (sample_tick) begin
                sample_count <= sample_count + 1;
                if (peak) begin
                    peak_count <= peak_count + 1;
                    last_hr_seen <= hr;
                    if (last_peak_sample != -1) begin
                        spacing = sample_count - last_peak_sample;
                        if (min_spacing == -1 || spacing < min_spacing) min_spacing <= spacing;
                        if (spacing > max_spacing) max_spacing <= spacing;
                        if (last_spacing != -1 && spacing != last_spacing)
                            saw_varying_spacing <= 1'b1;
                        last_spacing <= spacing;
                    end
                    last_peak_sample <= sample_count;
                end
            end
            if (rhythm_class !== UNKNOWN)
                saw_nonunknown_class <= 1'b1;
        end
    end
 
    initial begin
        clk = 0; rst = 1;
        errors = 0; sample_count = 0; peak_count = 0;
        last_peak_sample = -1; min_spacing = -1; max_spacing = 0;
        last_spacing = -1; saw_varying_spacing = 0; saw_nonunknown_class = 0;
        last_hr_seen = 0;
 
        repeat(4) @(posedge clk);
        rst = 0;
 
        wait (sample_count >= RUN_SAMPLES);
        #100;
 
        $display("---- Integration run summary (fixed pipeline, real ecg.mem) ----");
        $display("Samples processed   : %0d", sample_count);
        $display("Peaks detected       : %0d", peak_count);
        $display("Min peak spacing     : %0d samples (%.2fs)", min_spacing, min_spacing/200.0);
        $display("Max peak spacing     : %0d samples (%.2fs)", max_spacing, max_spacing/200.0);
        $display("Last hr at a peak    : %0d bpm", last_hr_seen);
        $display("Final rhythm_class   : %0d  alarm: %0d", rhythm_class, alarm);
 
        // ---- Checks ----
        if (^hr === 1'bx || ^rr_interval === 1'bx || ^rhythm_class === 1'bx) begin
            errors = errors + 1;
            $display("FAIL: X/Z detected on a top-level output");
        end else
            $display("PASS: no X/Z on top-level outputs");
 
        if (peak_count < 3) begin
            errors = errors + 1;
            $display("FAIL: too few peaks detected (%0d) to evaluate spacing", peak_count);
        end else
            $display("PASS: %0d peaks detected", peak_count);
 
        // This is the key regression check: the ORIGINAL bugs caused
        // peak_detect to lock onto a single fixed REFRACTORY-driven
        // cadence, i.e. min_spacing == max_spacing (always exactly
        // REFRACTORY+1). Real signal tracking must show spacing that
        // varies with the actual data.
        if (!saw_varying_spacing) begin
            errors = errors + 1;
            $display("FAIL: peak spacing never varied -- looks locked to a fixed cadence again");
        end else
            $display("PASS: peak spacing varies (not locked to a fixed cadence)");
 
        if (min_spacing <= REFRACTORY) begin
            errors = errors + 1;
            $display("FAIL: minimum peak spacing (%0d) is at/below REFRACTORY (%0d) -- possible double-detection on the same beat", min_spacing, REFRACTORY);
        end
 
        // Loose physiological plausibility band (20-250 bpm equivalent spacing)
        if (max_spacing > 0 && (60.0*sample_rate/max_spacing < 20)) begin
            errors = errors + 1;
            $display("FAIL: max spacing implies implausibly low HR");
        end
        if (min_spacing > REFRACTORY && (60.0*sample_rate/min_spacing > 250)) begin
            errors = errors + 1;
            $display("FAIL: min spacing (excluding refractory-limited ones) implies implausibly high HR");
        end
 
        if (!saw_nonunknown_class) begin
            errors = errors + 1;
            $display("FAIL: rhythm_class never left UNKNOWN despite peaks being detected");
        end else
            $display("PASS: rhythm_class produced a real classification at some point");
 
        if (errors == 0)
            $display("ALL INTEGRATION CHECKS PASSED");
        else
            $display("%0d INTEGRATION CHECK(S) FAILED", errors);
 
        $finish;
    end
 
    initial begin
        #4_000_000;
        $display("TIMEOUT: sample_tick likely never fired -- check clk_freq/sample_rate override");
        $finish;
    end
endmodule

