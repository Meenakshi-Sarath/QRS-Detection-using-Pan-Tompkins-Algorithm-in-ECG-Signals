`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:14:13
// Design Name: 
// Module Name: derivative_tb
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


module tb_derivative;
    parameter data_width = 16;
    reg clk, rst, sample_tick;
    reg signed [data_width+7:0] hpf_in;
    wire signed [data_width+7:0] der_out;
    integer errors, i;
    reg signed [data_width+7:0] expected;
 
    derivative #(.data_width(data_width)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .hpf_in(hpf_in), .der_out(der_out)
    );
 
    always #5 clk = ~clk;
 
    task apply(input signed [data_width+7:0] val);
        begin
            @(posedge clk); hpf_in = val; sample_tick = 1;
            @(posedge clk); sample_tick = 0;
            #1;
        end
    endtask
 
    // Reference model for randomized regression: same equation, written independently
    reg signed [data_width+7:0] rx [0:4];
    reg signed [data_width+7:0] ref_out;
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ref_out <= 0;
            for (k=0;k<=4;k=k+1) rx[k] <= 0;
        end else if (sample_tick) begin
            for (k=4;k>0;k=k-1) rx[k] <= rx[k-1];
            rx[0] <= hpf_in;
            ref_out <= (rx[0] + (rx[1]<<1) - (rx[3]<<1) - rx[4]) >>> 3;
        end
    end
 
    initial begin
        clk=0; rst=1; sample_tick=0; hpf_in=0; errors=0;
        repeat(4) @(posedge clk);
        rst=0; @(posedge clk);
 
        // Impulse response: y[n] = (x0 + 2x1 - 2x3 - x4)/8
        // NOTE: because x_delay[0] is read BEFORE being updated (non-blocking
        // assignment ordering), der_out on a given apply() reflects the
        // PREVIOUS sample's delay-line state, i.e. the response appears
        // starting one apply() call AFTER the impulse is applied.
        apply(800);  expected = 0;                                     // impulse not yet in delay line
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n0: got %0d want %0d", der_out, expected); end
        else $display("PASS n0: %0d", der_out);
 
        apply(0);    expected = (800 + 0 - 0 - 0) >>> 3;                // x0=800
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n1: got %0d want %0d", der_out, expected); end
        else $display("PASS n1: %0d", der_out);
 
        apply(0);    expected = (0 + 2*800 - 0 - 0) >>> 3;              // x1=800
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n2: got %0d want %0d", der_out, expected); end
        else $display("PASS n2: %0d", der_out);
 
        apply(0);    expected = 0;                                      // x2 term unused
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n3: got %0d want %0d", der_out, expected); end
        else $display("PASS n3: %0d", der_out);
 
        apply(0);    expected = (0 - 2*800 - 0) >>> 3;                  // x3=800
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n4: got %0d want %0d", der_out, expected); end
        else $display("PASS n4: %0d", der_out);
 
        apply(0);    expected = (0 - 0 - 800) >>> 3;                    // x4=800
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n5: got %0d want %0d", der_out, expected); end
        else $display("PASS n5: %0d", der_out);
 
        apply(0);    expected = 0;
        if (der_out !== expected) begin errors=errors+1; $display("FAIL n6: got %0d want %0d", der_out, expected); end
        else $display("PASS n6: %0d", der_out);
 
        // Randomized regression against the independent reference model above
        for (i=0;i<300;i=i+1) begin
            apply($random % (1<<20));
        end
 
        if (errors==0) $display("ALL PASS");
        else $display("%0d FAILURES", errors);
        $finish;
    end
 
    // Continuous check against reference model (covers the randomized section)
    always @(negedge clk) begin
        if (!rst && $time > 100) begin
            if (der_out !== ref_out) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH @ t=%0t: DUT=%0d REF=%0d", $time, der_out, ref_out);
            end
        end
    end
endmodule
