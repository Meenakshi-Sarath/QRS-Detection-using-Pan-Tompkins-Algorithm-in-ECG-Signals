`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:48:33
// Design Name: 
// Module Name: ecg_top
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


// Top-level integration module. Wires the full Pan-Tompkins pipeline
// together in order:
//   ecg_rom -> lpf -> hpf -> derivative -> squaring -> mwi -> peak_detect
//            -> heart_rate -> arrhythmia_classify
//
// All bit widths are derived automatically from the single base
// parameter data_width, matching exactly how each individual module
// grows its own internal widths (data_width+6 out of lpf, +8 out of
// hpf/derivative, 2*data_width+16 out of squaring/mwi, etc.) -- so if
// you change data_width, everything downstream stays consistent
// automatically, same as it does inside each individual module.
//
// Debug outputs (sample_tick, peak, ecg_sample, mwi_out) are exposed at
// the top level purely so they're easy to probe on a waveform without
// digging into the hierarchy -- they don't affect functionality.
//
// Note: top-level output ports are connected directly to submodule
// ports (a single wire can fan out to multiple readers), so there's no
// need for separate internal aliases + assign statements for signals
// that are simply passed through unchanged.
 
module ecg_top #(
    parameter clk_freq    = 100_000_000,
    parameter addr_width  = 12,
    parameter data_width  = 16,
    parameter sample_rate = 200,
    parameter REFRACTORY  = 40,
    parameter MWI_N       = 32
)(
    input  wire        clk,
    input  wire        rst,
 
    // Final results
    output wire [7:0]  hr,
    output wire [15:0] rr_interval,
    output wire        hr_valid,
    output wire [2:0]  rhythm_class,
    output wire        alarm,
 
    // Debug / probe signals (handy for waveform viewing)
    output wire                          sample_tick,
    output wire signed [data_width-1:0]  ecg_sample,
    output wire                          peak,
    output wire [2*data_width+15:0]      mwi_out_dbg
);
 
    // ---- Derived widths, matching each module's own internal formulas ----
    localparam LPF_W = data_width+6;    // lpf_out width
    localparam HPF_W = data_width+8;    // hpf_out / der_out width
    localparam SQ_W  = 2*data_width+16; // sq_out / mwi_out width
 
    // ---- Internal-only wires (not exposed as top-level ports) ----
    wire signed [LPF_W-1:0] lpf_out;
    wire signed [HPF_W-1:0] hpf_out;
    wire signed [HPF_W-1:0] der_out;
    wire        [SQ_W-1:0]  sq_out;
 
    // ---- Stage 1: ROM / sample source ----
    ecg_rom #(
        .clk_freq(clk_freq),
        .addr_width(addr_width),
        .data_width(data_width),
        .sample_rate(sample_rate)
    ) u_rom (
        .clk(clk),
        .rst(rst),
        .ecg_sample(ecg_sample),
        .sample_tick(sample_tick)
    );
 
    // ---- Stage 2: Low pass filter ----
    lpf #(
        .data_width(data_width)
    ) u_lpf (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .ecg_in(ecg_sample),
        .lpf_out(lpf_out)
    );
 
    // ---- Stage 3: High pass filter ----
    hpf #(
        .data_width(data_width)
    ) u_hpf (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .lpf_in(lpf_out),
        .hpf_out(hpf_out)
    );
 
    // ---- Stage 4: Derivative ----
    derivative #(
        .data_width(data_width)
    ) u_der (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .hpf_in(hpf_out),
        .der_out(der_out)
    );
 
    // ---- Stage 5: Squaring ----
    squaring #(
        .data_width(data_width)
    ) u_sq (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .der_in(der_out),
        .sq_out(sq_out)
    );
 
    // ---- Stage 6: Moving window integration ----
    mwi #(
        .sq_width(SQ_W),
        .N(MWI_N)
    ) u_mwi (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .sq_in(sq_out),
        .mwi_out(mwi_out_dbg)
    );
 
    // ---- Stage 7: Peak detection ----
    peak_detect #(
        .data_width(SQ_W),
        .REFRACTORY(REFRACTORY)
    ) u_pk (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .mwi_in(mwi_out_dbg),
        .peak(peak)
    );
 
    // ---- Stage 8: Heart rate calculation ----
    heart_rate #(
        .SAMPLE_RATE(sample_rate)
    ) u_hr (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .peak(peak),
        .hr(hr),
        .rr_interval(rr_interval),
        .hr_valid(hr_valid)
    );
 
    // ---- Stage 9: Arrhythmia classification ----
    arrhythmia_classify #(
        .SAMPLE_RATE(sample_rate)
    ) u_arr (
        .clk(clk),
        .rst(rst),
        .hr_valid(hr_valid),
        .hr(hr),
        .rr_interval(rr_interval),
        .rhythm_class(rhythm_class),
        .alarm(alarm)
    );
 
endmodule
