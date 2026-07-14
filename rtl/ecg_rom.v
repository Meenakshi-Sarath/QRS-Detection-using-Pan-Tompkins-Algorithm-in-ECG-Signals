`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.12.2025 12:31:04
// Design Name: 
// Module Name: ecg_rom
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


module ecg_rom #(parameter clk_freq=100_000_000, //fpga clock
                 parameter addr_width = 12, //4096 samples max can be stored
                 parameter data_width = 16, //accuracy of each sample
                 parameter sample_rate = 200 //ecg sample rate
                 )( input wire clk,
                    input wire rst,
                    output reg signed [data_width-1:0] ecg_sample,
                    output wire sample_tick);
                    
    // CLOCK DIVIDER LOGIC

    localparam integer sample_div = clk_freq / sample_rate;//need to wait for this long before one high to achieve 200hz rate
    
    //Now we need to essentially make a counter that will count till sample_div (for delay purposes)
    reg [$clog2(sample_div)-1:0] sample_cnt;
    
    //Combinational logic for sample_tick to go high 
    assign sample_tick = (sample_cnt == sample_div-1); //made output just for simulation purposes
    
    //Counter part
    always @ (posedge clk) begin
       if(rst)
            sample_cnt <= 0;
       else
            sample_cnt <= sample_tick ? 0 : sample_cnt+1; 
    end
    
    //ROM DECLARATION

    //We defined as localparam to not allow changes in constant and add 'integer' keyword to ensure its a constant
    //because for registers or arrays the sizes mentioned or bounded by should be constant values
    localparam integer rom_size = 1<<addr_width; // 2^12 logic 
    reg signed [data_width-1:0] rom [0: rom_size-1]; 
    
    //Declare data in rom
    initial $readmemh("ecg.mem",rom);
    reg [addr_width-1:0] rom_addr;
    
    always @ (posedge clk or posedge rst) begin
        if(rst)begin
            rom_addr <= 0;
            ecg_sample <= 0;
        end
        else if (sample_tick) begin
            ecg_sample <= rom[rom_addr];
            rom_addr <= (rom_addr == rom_size-1) ? 0: rom_addr + 1;
        end    
            
    end 
endmodule
