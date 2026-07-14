`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.04.2026 22:47:29
// Design Name: 
// Module Name: peak_detect
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


module peak_detect #(
    parameter data_width     = 48,    // matches mwi output width
    parameter REFRACTORY     = 60,    // 300ms at 200Hz sample rate.
                                       // NOTE: originally 200ms (40 samples,
                                       // the standard Pan-Tompkins textbook
                                       // value), but integration testing
                                       // against real ECG data showed
                                       // double-detection on single beats
                                       // (a genuine detect, then a spurious
                                       // re-trigger the instant refractory
                                       // cleared, since the tail of that
                                       // same beat's MWI energy was still
                                       // above threshold). Widening to 300ms
                                       // resolved it cleanly on the tested
                                       // data (~35-50bpm). If you retune
                                       // this, re-run tb_ecg_top.v and check
                                       // min_spacing stays above REFRACTORY.
    parameter WARMUP_SAMPLES = 256    // ~1.28s @ 200Hz calibration window
                                       // (must be a power of 2 -- used as
                                       // a shift for the running average)
)(
    input  wire clk,
    input  wire rst,
    input  wire sample_tick,
    input  wire [data_width-1:0] mwi_in,
    output reg  peak
);
    // ---- Original adaptive-threshold state (unchanged) ----
    reg [data_width:0]   SPKI, NPKI;
    reg [data_width:0]   TH1;
    reg [$clog2(REFRACTORY)-1:0] ref_cnt;
    reg in_refractory;
 
    // ---- NEW: warm-up / calibration state ----
    // Root cause being fixed: SPKI/NPKI/TH1 all started at 0, so the very
    // first nonzero mwi_in sample always satisfied "mwi_in > TH1", which
    // routes into the SPKI (peak) branch and NEVER the NPKI (noise)
    // branch. Once that happens, NPKI can never get real data to learn
    // from (mwi_in almost never drops below a TH1 that's chasing SPKI
    // upward), so NPKI stays stuck at 0 and TH1 becomes an ungrounded
    // fraction of SPKI rather than a real noise floor -- confirmed on
    // real ecg.mem data, where this caused peak_detect to fire at a
    // fixed REFRACTORY-driven cadence instead of tracking real R-waves.
    //
    // Fix: during the first WARMUP_SAMPLES sample_ticks after reset, make
    // NO peak decisions. Instead track the max and mean of mwi_in. At the
    // end of the window, seed SPKI from the observed max (a rough signal
    // amplitude estimate) and NPKI from the observed mean (a rough noise
    // floor estimate) -- this mirrors the explicit learning/calibration
    // phase used in real Pan-Tompkins implementations, instead of
    // starting both estimators at 0.
    localparam WARMUP_CNT_W = $clog2(WARMUP_SAMPLES);
    localparam SUM_W        = data_width + WARMUP_CNT_W;
 
    reg [WARMUP_CNT_W-1:0]  warmup_cnt;
    reg                     warmup_done;
    reg [data_width-1:0]    max_seen;
    reg [SUM_W-1:0]         sum_seen;
 
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            SPKI          <= 0;
            NPKI          <= 0;
            TH1           <= 0;
            peak          <= 0;
            ref_cnt       <= 0;
            in_refractory <= 0;
            warmup_cnt    <= 0;
            warmup_done   <= 0;
            max_seen      <= 0;
            sum_seen      <= 0;
        end
        else if(sample_tick) begin
 
            if (!warmup_done) begin
                // ---- Calibration phase: observe only, decide nothing ----
                peak <= 0;
                if (mwi_in > max_seen)
                    max_seen <= mwi_in;
                sum_seen <= sum_seen + mwi_in;
 
                if (warmup_cnt == WARMUP_SAMPLES-1) begin
                    warmup_done <= 1;
                    // Seed the adaptive thresholds from real observed
                    // statistics instead of 0. Mean (sum>>WARMUP_CNT_W)
                    // becomes the initial noise-floor estimate; the
                    // observed max becomes the initial signal estimate.
                    NPKI <= (sum_seen + mwi_in) >> WARMUP_CNT_W;
                    SPKI <= max_seen;
                    TH1  <= ((sum_seen + mwi_in) >> WARMUP_CNT_W)
                            + ((max_seen - ((sum_seen + mwi_in) >> WARMUP_CNT_W)) >> 2);
                end
                else
                    warmup_cnt <= warmup_cnt + 1;
            end
 
            else begin
                // ---- Original Pan-Tompkins adaptive detection, unchanged ----
                if(in_refractory) begin
                    if(ref_cnt == REFRACTORY - 1) begin
                        in_refractory <= 0;
                        ref_cnt       <= 0;
                    end
                    else
                        ref_cnt <= ref_cnt + 1;
                end
                if(!in_refractory) begin
                    if(mwi_in > TH1) begin
                        peak          <= 1;
                        in_refractory <= 1;
                        ref_cnt       <= 0;
                        SPKI <= (SPKI * 7 + mwi_in) >> 3;
                    end
                    else begin
                        peak <= 0;
                        NPKI <= (NPKI * 7 + mwi_in) >> 3;
                    end
                end
                else begin
                    peak <= 0;
                end
                TH1 <= NPKI + ((SPKI - NPKI) >> 2);
            end
        end
    end
endmodule
