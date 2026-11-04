`timescale 1ns/1ps
module tb_pressure_scan32;
reg clk=0,rst=0,tick=0,clear=0,valid=0,error=0;always #10 clk=~clk;
reg[31:0] held=0;reg[15:0] sample=20000;
wire[31:0] sustained;wire[7:0] pressure;wire sensor_ready;
pressure_sustain32 #(.TIMEOUT_MS(1000),.MAX_HOLD_MS(255)) d(clk,rst,tick,clear,held,sample,valid,error,sustained,pressure,sensor_ready);
reg[31:0] expected;
task adc;begin @(negedge clk);valid=1;@(negedge clk);valid=0;repeat(70)@(negedge clk);end endtask
task ms;begin
@(negedge clk);tick=1;@(negedge clk);tick=0;
repeat(32)@(negedge clk);
if(d.scan_active)$fatal(1,"32-slot scan deadline");
end endtask
initial begin
repeat(3)@(negedge clk);rst=1;adc();held=32'hffffffff;ms();
if(sustained!==32'hffffffff)$fatal(1,"all32 retained initialization");
for(integer t=1;t<=300;t=t+1)begin
held=t<32 ? 32'hffffffff<<t : 32'd0;ms();expected=0;
for(integer j=0;j<32;j=j+1)if(t<j+256)expected[j]=1;
if(sustained!==expected)$fatal(1,"independent hold t=%0d actual=%h expected=%h",t,sustained,expected);
end
held=32'hffffffff;ms();held=0;
@(negedge clk);tick=1;@(negedge clk);tick=0;repeat(5)@(negedge clk);
clear=1;@(negedge clk);clear=0;repeat(40)@(negedge clk);
if(sustained!==0 || d.scan_active)$fatal(1,"clear must cancel active scan");
adc();held=32'ha5a5ffff;ms();held=0;error=1;@(negedge clk);error=0;repeat(40)@(negedge clk);
if(sustained!==0)$fatal(1,"NACK must cancel all32 retained notes");
held=32'h80000001;@(negedge clk);if(sustained!==held)$fatal(1,"physical key bypass");
$display("PASS pressure scan: all32 staggered releases independent/exact, 32-clock deadline, active-scan clear and NACK, physical bypass");$finish;
end
initial begin #5000000;$fatal(1,"watchdog");end
endmodule
