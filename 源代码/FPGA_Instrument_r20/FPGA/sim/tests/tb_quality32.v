`timescale 1ns/1ps
module tb_quality32;
reg clk=0,rst=0,tick=0,tones=0;
reg [31:0] gate=0;
always #10 clk=~clk;
wire signed [15:0] before_pcm,after_pcm;
wire before_ready,after_ready;
voice_engine_32_r16 #(.PIANO_PROFILE(1),.NEAR_NOTE_SOFTEN(1)) baseline(
 .clk(clk),.reset_n(rst),.frame_tick(tick),.gate(gate),.timbre(2'd0),.octave(1'b0),
 .expression(8'd255),.next_pcm(before_pcm),.ready(before_ready),.retrigger(32'd0),.pitch_offset(16'sd0));
voice_engine_32 #(.PIANO_PROFILE(1),.NEAR_NOTE_SOFTEN(0)) improved(
 .clk(clk),.reset_n(rst),.frame_tick(tick),.gate(gate),.timbre(2'd0),.octave(1'b0),
 .expression(8'd255),.next_pcm(after_pcm),.ready(after_ready),.retrigger(32'd0),.pitch_offset(16'sd0),.diagnostic_tones(tones));
integer file,segment=0,index=0,checks=0,restored=0;
reg [31:0] active_seen=0;
always @(negedge clk) if(rst && improved.state==8) begin
 if(!tones && gate[improved.voice_idx]) begin
  if(improved.gain!==((improved.env[improved.voice_idx]*255)>>8))$fatal(1,"unexpected neighbour attenuation voice%0d",improved.voice_idx);
  checks=checks+1;
  if(improved.gain>baseline.gain*3 && baseline.gain>100)restored=restored+1;
 end
 if(tones && gate[improved.voice_idx]) begin
  if(improved.wave_mix!==improved.fundamental_ext || improved.gain!==32767)$fatal(1,"diagnostic voice is not a pure gate-controlled DDS sine");
  active_seen[improved.voice_idx]=1;
 end
end
task frame;begin
 @(negedge clk);tick=1;@(negedge clk);tick=0;
 repeat(1022)@(negedge clk);
 if(!before_ready || !after_ready)$fatal(1,"quality source frame deadline");
 if(segment==0 && before_pcm!==after_pcm)$fatal(1,"isolated piano note changed");
 if(^after_pcm===1'bx)$fatal(1,"quality unknown sample");
 $fdisplay(file,"%0d %0d %0d %0d",segment,index,before_pcm,after_pcm);index=index+1;
end endtask
initial begin
 file=$fopen("quality_capture.txt","w");repeat(4)@(negedge clk);rst=1;
 gate=32'h200;repeat(4096)frame();
 $display("CHECK quality: isolated A4 identical before/after");
 segment=1;index=0;gate=0;repeat(4096)frame();
 segment=2;index=0;gate=32'h895;repeat(16384)frame();
 $display("CHECK quality: Cmaj9 chord, neighbour-note gains restored");
 segment=3;index=0;gate=0;repeat(4096)frame();
 segment=4;index=0;tones=1;gate=32'hffffffff;repeat(16384)frame();
 if(active_seen!==32'hffffffff || checks<10000 || restored<1000)$fatal(1,"quality coverage checks%0d restored%0d voices%h",checks,restored,active_seen);
 $fclose(file);
 $display("PASS quality32: isolated A4 bit-identical; full neighbour gains checks=%0d restored=%0d; all32 pure DDS contributions, no recorded samples; captured16384 spectral frames",checks,restored);$finish;
end
initial begin #1200000000;$fatal(1,"quality watchdog segment%0d index%0d",segment,index);end
endmodule
