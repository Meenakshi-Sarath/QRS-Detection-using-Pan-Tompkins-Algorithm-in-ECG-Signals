`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.12.2025 20:02:23
// Design Name: 
// Module Name: tb_ecg_rom
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

//When running this make sure u run for 50ms not 1000ns(1ms)
//because it takes 5ms to sample each signal itself.
module tb_ecg_rom;

    // PARAMETERS (match your design)
    parameter clk_freq   = 100_000_000;
    parameter addr_width = 12;
    parameter data_width = 16;
    parameter sample_rate = 200;

    // SIGNALS
    reg clk;
    reg rst;
    wire signed [data_width-1:0] ecg_sample;

    // DUT INSTANCE
    ecg_rom #(
        .clk_freq(clk_freq),
        .addr_width(addr_width),
        .data_width(data_width),
        .sample_rate(sample_rate)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .ecg_sample(ecg_sample)
    );

    // CLOCK GENERATION (100 MHz)
    always #5 clk = ~clk;   // 10 ns period

    // TEST SEQUENCE
    initial begin
        clk = 0;
        rst = 1;

        // hold reset for some cycles
        #100;
        rst = 0;

        // run long enough to see waveform
        #50_000_000;   // 50 ms simulation

        $stop;
    end

    // MONITOR SAMPLES
    initial begin
        $display("Time\tECG Sample");
        $monitor("%t\t%d", $time, ecg_sample);
    end

endmodule