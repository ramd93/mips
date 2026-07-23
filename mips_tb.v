`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.05.2026 16:55:46
// Design Name: 
// Module Name: mips_tb
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


`timescale 1ns / 1ps

module mips_tb();
    
    
    reg clk;
    reg reset;

    
    mips_top uut (
        .clk(clk),
        .reset(reset)
    );

    
    always #5 clk = ~clk;

    
    initial begin
       
        clk = 0;
        reset = 1;
        
        
        #20; 
        
        
        reset = 0;

        
        #500; 
        
        // 5. Stop the simulation
        $finish;
    end

endmodule
