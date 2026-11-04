`timescale 1ns/1ps
module tb_folded_sine;
reg clk=0;always #10 clk=~clk;
reg[11:0] address=0;reg signed[15:0] full[0:4095];wire signed[15:0] sample;
bowed_quarter_sine dut(clk,address,sample);
initial begin
 $readmemh("bowed_sine.mem",full);
 for(integer i=0;i<4096;i=i+1)begin
  @(negedge clk);address=i;@(posedge clk);#1;
  if(sample!==full[i])$fatal(1,"folded sine changed angle%0d actual%0d expected%0d",i,sample,full[i]);
 end
 $display("PASS folded sine:all4096 phases bit-exact, original one-clock latency");$finish;
end
endmodule
