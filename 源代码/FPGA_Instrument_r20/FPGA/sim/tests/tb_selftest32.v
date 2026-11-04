`timescale 1ns/1ps
module tb_selftest32;
reg clk=0,rst=0,ready=1,fault=0;
reg [1:0] buttons=0;
wire active,valid;
wire [1:0] timbre;
wire [2:0] stage;
wire [31:0] mask;
always #10 clk=~clk;
polyphony_selftest32 #(.HOLD_MS(3),.SOUND_MS(4),.GAP_MS(2)) dut(
 .clk(clk),.reset_n(rst),.tick_ms(1'b1),.ready(ready),.fault(fault),.buttons(buttons),.current_timbre(2'd3),
 .active(active),.timbre_valid(valid),.test_timbre(timbre),.mask(mask),.stage(stage));
initial begin
 repeat(3)@(negedge clk);rst=1;buttons=3;
 repeat(2)@(negedge clk);if(active)$fatal(1,"short press started test");buttons=0;
 @(negedge clk);buttons=3;ready=0;
 repeat(5)@(negedge clk);if(active)$fatal(1,"unready started test");ready=1;
 wait(active);@(negedge clk);
 for(integer s=0;s<5;s=s+1)begin
   wait(stage==s && mask!=0);@(negedge clk);
   if(mask!==32'hffffffff || timbre!==(s==4 ? 0 : s))$fatal(1,"stage%0d mask/timbre",s);
   wait(mask==0);
 end
 wait(!active);@(negedge clk);if(timbre!=3)$fatal(1,"restore timbre");
 repeat(10)@(negedge clk);if(active)$fatal(1,"held buttons repeated test");
 buttons=0;@(negedge clk);buttons=3;wait(active);
 @(negedge clk);fault=1;@(negedge clk);
 if(active || mask!=0 || timbre!=3)$fatal(1,"fault abort");
 $display("PASS selftest32: ready gate, short press, four32 timbres plus32 pure tones, silence gaps, restore, no repeat while held, fault abort");$finish;
end
initial begin #10000;$fatal(1,"unit watchdog");end
endmodule
