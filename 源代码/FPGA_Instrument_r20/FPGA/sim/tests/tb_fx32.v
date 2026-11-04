`timescale 1ns/1ps
module tb_fx32;
reg clk=0,rst=0,start=0;always #10 clk=~clk;
reg signed[15:0] l=0,r=0;reg[7:0] sd=0,vd=0,rd=0;
wire signed[15:0] lo,ro;wire ready,overrun;
audio_fx32 d(clk,rst,start,l,r,sd,vd,rd,lo,ro,ready,overrun);
integer tail=0,stereo=0,modulated=0;
task frame;begin @(negedge clk);start=1;@(negedge clk);start=0;repeat(90)@(negedge clk);
if(!ready || overrun)$fatal(1,"FX deadline/overrun");
if(^lo===1'bx || ^ro===1'bx)$fatal(1,"uninitialized RAM leaked");end endtask
initial begin repeat(3)@(negedge clk);rst=1;
for(integer i=0;i<100;i=i+1)begin l=i*100-5000;r=-l;frame();if(lo!==l || ro!==r)$fatal(1,"zero-effect stereo bypass");end
sd=255;vd=0;rd=0;
for(integer i=0;i<100;i=i+1)begin l=i*100-5000;r=-l;frame();if(lo!==l || ro!==r)$fatal(1,"stereo dry bypass");end
sd=180;vd=128;rd=192;l=16000;r=16000;frame();l=0;r=0;
repeat(10000)begin frame();if(lo!=0 || ro!=0)tail=tail+1;if(lo!=ro)stereo=stereo+1;end
if(tail<10 || stereo<10)$fatal(1,"combined wet/stereo absent %0d %0d",tail,stereo);
rd=0;sd=0;vd=160;
for(integer i=0;i<2000;i=i+1)begin l=(i%200)*100-10000;r=l;frame();if(lo!=l)modulated=modulated+1;if(lo!==ro)$fatal(1,"stereo off");end
if(modulated<1000)$fatal(1,"vibrato bypassed");
vd=0;l=0;r=0;repeat(10)frame();if(lo!==0 || ro!==0)$fatal(1,"effects off wet leaking");
$display("PASS FX32 dry/mono/stereo, no X, bounded deadlines, combined reverb/stereo impulse tail=%0d stereo=%0d, modulated=%0d, wet bypass",tail,stereo,modulated);$finish;
end
initial begin #50000000;$fatal(1,"watchdog");end
endmodule
