`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:27:19
// Design Name: 
// Module Name: mwi_tb
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

module tb_mwi;
    parameter sq_width = 48;
    parameter N = 32;
    reg clk, rst, sample_tick;
    reg [sq_width-1:0] sq_in;
    wire [sq_width-1:0] mwi_out;
    integer errors, i;
 
    // ---- DUT ----
    mwi #(.sq_width(sq_width), .N(N)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .sq_in(sq_in), .mwi_out(mwi_out)
    );
 
    // ---- Independent reference model ----
    reg [sq_width-1:0] rbuf [0:N-1];
    reg [sq_width+4:0] rsum;
    reg [sq_width-1:0] ref_out;
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rsum <= 0;
            ref_out <= 0;
            for (k=0;k<N;k=k+1) rbuf[k] <= 0;
        end else if (sample_tick) begin
            rsum <= rsum - rbuf[N-1] + sq_in;
            for (k=N-1;k>0;k=k-1) rbuf[k] <= rbuf[k-1];
            rbuf[0] <= sq_in;
            ref_out <= (rsum - rbuf[N-1] + sq_in) >> 5;
        end
    end
 
    always #5 clk = ~clk;
 
    task apply(input [sq_width-1:0] val);
        begin
            @(posedge clk); sq_in = val; sample_tick = 1;
            @(posedge clk); sample_tick = 0;
            #1;
        end
    endtask
 
    initial begin
        clk=0; rst=1; sample_tick=0; sq_in=0; errors=0;
        repeat(4) @(posedge clk);
        rst=0; @(posedge clk);
 
        // Test 1: constant input for > N samples => output should CONVERGE to that constant
        for (i=0;i<40;i=i+1) apply(64'd1000);
        if (mwi_out !== 1000) begin
            errors=errors+1;
            $display("FAIL: constant-input convergence. Got %0d, want 1000", mwi_out);
        end else
            $display("PASS: constant input converges to 1000 (got %0d)", mwi_out);
 
        // Test 2: reset, then impulse -> rectangular pulse of height impulse/32
        // lasting exactly N samples, then back to 0
        rst=1; @(posedge clk); @(posedge clk); rst=0; @(posedge clk);
        apply(64'd3200);          // impulse: 3200/32 = 100
        for (i=0;i<N-1;i=i+1) begin
            apply(64'd0);
            if (mwi_out !== 100) begin
                errors=errors+1;
                if (errors<=5) $display("FAIL: impulse response @ step %0d, got %0d want 100", i, mwi_out);
            end
        end
        apply(64'd0);
        if (mwi_out !== 0) begin
            errors=errors+1;
            $display("FAIL: impulse should have left the window, got %0d want 0", mwi_out);
        end else
            $display("PASS: impulse response returns to 0 exactly after N samples");
 
        // Test 3: randomized regression against independent reference model
        rst=1; @(posedge clk); @(posedge clk); rst=0; @(posedge clk);
        for (i=0;i<400;i=i+1)
            apply({$random} % (1<<20));   // sq_out is always non-negative in real use (it's a square)
 
        if (errors==0) $display("ALL PASS");
        else $display("%0d FAILURES", errors);
        $finish;
    end
 
    // Continuous check against reference model
    always @(negedge clk) begin
        if (!rst && $time > 100) begin
            if (mwi_out !== ref_out) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH @ t=%0t: DUT=%0d REF=%0d", $time, mwi_out, ref_out);
            end
        end
    end
endmodule

