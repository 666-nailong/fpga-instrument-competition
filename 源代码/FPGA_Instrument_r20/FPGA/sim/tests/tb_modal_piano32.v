`timescale 1ns/1ps
module tb_modal_piano32;
reg clk=0,rst=0,tick=0,octave=0;
reg[31:0] gate=0,retrigger=0;
always #10 clk=~clk;
wire signed[15:0] pcm;
wire ready,overrun;
modal_piano32 dut(clk,rst,tick,octave,gate,retrigger,pcm,ready,overrun);
integer file,index=0,cycles,max_cycles=0;
reg [31:0] terms_seen=0;
always @(negedge clk)if(rst && dut.state==9 && dut.envelope_product!=0)terms_seen[dut.voice]=1;
task frame;begin
 @(negedge clk);tick=1;@(negedge clk);tick=0;cycles=0;
 while(!ready && cycles<1020)begin @(negedge clk);cycles=cycles+1;end
 if(!ready || overrun || ^pcm===1'bx)$fatal(1,"modal deadline/unknown frame%0d cycles%0d",index,cycles);
 if(cycles>max_cycles)max_cycles=cycles;
 $fdisplay(file,"%0d %h %h %0d %0d",index,gate,retrigger,octave,pcm);
 repeat(1022-cycles)@(negedge clk);index=index+1;
end endtask
initial begin
 file=$fopen("modal_capture.txt","w");repeat(4)@(negedge clk);rst=1;
 gate=512;repeat(1536)frame();gate=0;repeat(512)frame();
 gate=32'hffffffff;repeat(512)frame();
 if(terms_seen!==32'hffffffff)$fatal(1,"missing independent piano voice%h",terms_seen);
 retrigger=32'h80000201;frame();retrigger=0;repeat(127)frame();
 octave=1;repeat(512)frame();gate=0;repeat(2048)frame();
 if(pcm!=0)$fatal(1,"pedal/key release did not decay to zero");
 rst=0;repeat(4)@(negedge clk);rst=1;repeat(8)frame();
 if(pcm!==0)$fatal(1,"stale modal RAM leaked after reset");
 $fclose(file);$display("PASS modal piano32:16 independent decays x32 notes, both octaves, retrigger under sustain, release/reset masking; max%0d/1024 clocks; frames=%0d",max_cycles,index);$finish;
end
initial begin #150000000;$fatal(1,"modal watchdog");end
endmodule
