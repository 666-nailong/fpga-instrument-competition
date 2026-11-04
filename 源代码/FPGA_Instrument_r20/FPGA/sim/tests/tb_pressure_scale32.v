`timescale 1ns/1ps
module tb_pressure_scale32;
reg clk=0,rst=0,valid=0,error=0;always #10 clk=~clk;
reg[15:0] sample=0;reg[31:0] held=0;
wire[31:0] sustained;wire[7:0] pressure;wire sensor_ready;
pressure_sustain32 d(clk,rst,1'b0,1'b0,held,sample,valid,error,sustained,pressure,sensor_ready);
integer expected,checked=0;
task send(input[15:0] value);begin
@(negedge clk);sample=value;valid=1;@(negedge clk);valid=0;
end endtask
initial begin
repeat(3)@(negedge clk);rst=1;
for(integer code=0;code<65536;code=code+1)begin
send(code);repeat(70)@(negedge clk);
expected=code>=32768 || code<=400 ? 0 : code>=20000 ? 255 : ((code-400)*255)/19600;
if(pressure!==expected || d.duration!==(expected*8000)/255 || d.scale_state!==0)
$fatal(1,"scale code=%0d pressure=%0d expected=%0d duration=%0d",code,pressure,expected,d.duration);
checked=checked+1;
end
send(10200);repeat(10)@(negedge clk);send(15000);repeat(70)@(negedge clk);
if(pressure!==189 || d.duration!==5929)$fatal(1,"new ADC must replace in-flight scale");
send(10200);repeat(10)@(negedge clk);error=1;@(negedge clk);error=0;
held=32'h80000001;repeat(70)@(negedge clk);
if(pressure!==0 || d.duration!==0 || sustained!==held)$fatal(1,"NACK in-flight scaling cancellation / physical keys");
$display("PASS pressure scaling: all %0d raw16 codes exact, default8000ms duration, latest-sample restart and NACK cancellation",checked);$finish;
end
initial begin #150000000;$fatal(1,"watchdog");end
endmodule
