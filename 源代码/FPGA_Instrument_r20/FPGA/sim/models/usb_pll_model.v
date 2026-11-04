`timescale 1ns/1ps
// Functional clock only; not a PLL/electrical USB enumeration simulation.
module usb_pll_50_to_60(input wire clkin,output reg clkout=0,output reg lock=0);
    always #8.333333 clkout=~clkout;
    initial begin repeat(8)@(posedge clkin);lock=1;end
endmodule
