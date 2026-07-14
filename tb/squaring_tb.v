`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:23:49
// Design Name: 
// Module Name: squaring_tb
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


module tb_squaring;
    parameter data_width = 16;
    reg clk, rst, sample_tick;
    reg signed [data_width+7:0] der_in;
    wire [2*data_width+15:0] sq_out;
    integer errors, i;
    reg signed [data_width+7:0] test_vals [0:6];
    reg [2*data_width+15:0] expected;
 
    squaring #(.data_width(data_width)) DUT (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .der_in(der_in), .sq_out(sq_out)
    );
 
    always #5 clk = ~clk;
 
    task apply(input signed [data_width+7:0] val);
        begin
            @(posedge clk); der_in = val; sample_tick = 1;
            @(posedge clk); sample_tick = 0;
            #1;
        end
    endtask
 
    initial begin
        clk=0; rst=1; sample_tick=0; der_in=0; errors=0;
        repeat(4) @(posedge clk);
        rst=0; @(posedge clk);
 
        // Directed corner cases: zero, +1, -1, max positive, max negative, typical values
        test_vals[0]=0;
        test_vals[1]=1;
        test_vals[2]=-1;
        test_vals[3]=(1<<(data_width+7))-1;     // max positive for 24-bit signed
        test_vals[4]=-(1<<(data_width+7));      // max negative for 24-bit signed
        test_vals[5]=12345;
        test_vals[6]=-12345;
 
        for (i=0;i<7;i=i+1) begin
            apply(test_vals[i]);
            expected = test_vals[i] * test_vals[i];
            if (sq_out !== expected) begin
                errors=errors+1;
                $display("FAIL case %0d: in=%0d DUT=%0d want=%0d", i, test_vals[i], sq_out, expected);
            end else
                $display("PASS case %0d: in=%0d out=%0d", i, test_vals[i], sq_out);
        end
 
        // Randomized regression
        for (i=0;i<300;i=i+1) begin
            apply($random % (1<<20));
            expected = der_in * der_in;
            if (sq_out !== expected) begin
                errors=errors+1;
                if (errors<=10) $display("FAIL rand %0d: in=%0d DUT=%0d want=%0d", i, der_in, sq_out, expected);
            end
        end
 
        if (errors==0) $display("ALL PASS");
        else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule

