// 32 independent notes x16 decaying stiff-string modes; no recorded waveforms.
// Four lanes share arithmetic over the16 modes and32 notes within1024 clocks.
module modal_piano32(
 input wire clk,reset_n,frame_tick,octave,
 input wire [31:0] gate,retrigger,
 output reg signed [15:0] sample,
 output reg ready,overrun
);
 reg [3:0] state;
 reg [4:0] voice;
 reg [1:0] group;
 reg [31:0] gates,onsets,previous_gate,initialized;
 reg octave_frame,previous_octave;
 reg [15:0] levels[0:31],ages[0:31];
 reg [15:0] level,age;
 reg attack;
 reg signed [23:0] partial_sum;
 reg signed [25:0] mix;
 reg signed [40:0] envelope_product;
 reg [22:0] noise;
 reg signed [15:0] previous_noise;
 wire [5:0] note={1'b0,voice}+(octave_frame ? 6'd12 : 6'd0);
 wire [7:0] rom_address={note,group};
 wire [6:0] address={voice,group};
 wire signed [33:0] contributions[0:3];
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:modes
  reg [51:0] constants[0:255] /* synthesis syn_romstyle="logic" */;
  if(lane==0)initial $readmemh("piano_modes_0.mem",constants);
  if(lane==1)initial $readmemh("piano_modes_1.mem",constants);
  if(lane==2)initial $readmemh("piano_modes_2.mem",constants);
  if(lane==3)initial $readmemh("piano_modes_3.mem",constants);
  reg [55:0] contexts[0:127];
  reg [55:0] stored;
  reg [51:0] coefficient;
  reg [31:0] phase;
  reg [23:0] envelope;
  reg signed [31:0] weighted;
  reg signed [56:0] product;
  wire [31:0] increment=coefficient[50:19];
  wire [31:0] next_phase=phase+increment;
  wire signed [15:0] gain={2'b00,coefficient[18:5]};
  wire [4:0] decay=coefficient[4:0];
  wire signed [15:0] wave;
  piano_sine oscillator(clk,state==4,phase[31:22],wave);
  always @(posedge clk)begin
   if(state==2)begin coefficient<=constants[rom_address];stored<=contexts[address];end
   if(state==3)begin
    phase<=attack || !initialized[voice] ? 32'd0 : stored[55:24];
    if(attack)envelope<=24'hffffff;
    else if(!initialized[voice])envelope<=0;
    else envelope<=stored[23:0]-((stored[23:0]>>(gates[voice] ? decay : 5'd10))+(stored[23:0]!=0));
   end
   if(state==5)weighted<=wave*gain;
   if(state==6)begin
    product<=$signed(weighted)*$signed({1'b0,envelope});
    contexts[address]<={next_phase,envelope};
   end
  end
  assign contributions[lane]=product>>>39;
 end endgenerate
 wire signed [16:0] difference=$signed({noise[22],noise[22:7]})-$signed({previous_noise[15],previous_noise});
 wire signed [23:0] excitation=age<160 ? ($signed(difference)>>>5) : 24'sd0;
 integer i;
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=0;voice<=0;group<=0;gates<=0;onsets<=0;previous_gate<=0;initialized<=0;
   octave_frame<=0;previous_octave<=0;level<=0;age<=0;attack<=0;
   partial_sum<=0;mix<=0;sample<=0;ready<=0;overrun<=0;envelope_product<=0;
   noise<=23'h513a97;previous_noise<=0;
   for(i=0;i<32;i=i+1)begin levels[i]<=0;ages[i]<=0;end
  end else if(frame_tick)begin
   if(state!=0)overrun<=1;
   state<=1;voice<=0;group<=0;gates<=gate;
   onsets<=octave!=previous_octave ? gate : gate&(~previous_gate|retrigger);
   octave_frame<=octave;ready<=0;mix<=0;
   if(octave!=previous_octave)begin
    initialized<=0;
    for(i=0;i<32;i=i+1)begin levels[i]<=0;ages[i]<=0;end
   end
  end else case(state)
   1:begin
    attack<=onsets[voice];
    age<=gates[voice] ? (onsets[voice] ? 16'd0 : ages[voice]==65535 ? ages[voice] : ages[voice]+1'b1) : 16'd65535;
    if(onsets[voice])level<=1024;
    else if(gates[voice])level<=levels[voice]>31743 ? 16'd32767 : levels[voice]+16'd1024;
    else level<=levels[voice]>24 ? levels[voice]-16'd24 : 16'd0;
    partial_sum<=0;group<=0;
    state<=!gates[voice] && levels[voice]==0 ? 11 : 2;
   end
   2:state<=3;
   3:state<=4;
   4:state<=5;
   5:state<=6;
   6:state<=7;
   7:begin
    partial_sum<=partial_sum+contributions[0]+contributions[1]+contributions[2]+contributions[3];
    if(group==3)state<=8;else begin group<=group+1'b1;state<=2;end
   end
   8:begin
    envelope_product<=(partial_sum+excitation)*$signed({1'b0,level});
    levels[voice]<=level;ages[voice]<=age;initialized[voice]<=1;
    noise<={noise[21:0],noise[22]^noise[17]};previous_noise<=noise[22:7];state<=9;
   end
   9:begin
    mix<=mix+(envelope_product>>>19);
    if(voice==31)state<=10;else begin voice<=voice+1'b1;state<=1;end
   end
   10:begin
    sample<=mix>32767 ? 16'sh7fff : mix< -32768 ? 16'sh8000 : mix[15:0];
    ready<=1;previous_gate<=gates;previous_octave<=octave_frame;state<=0;
   end
   11:begin
    envelope_product<=0;levels[voice]<=0;ages[voice]<=65535;
    noise<={noise[21:0],noise[22]^noise[17]};previous_noise<=noise[22:7];state<=9;
   end
   default:state<=0;
  endcase
 end
endmodule

module piano_sine(input wire clk,enable,input wire[9:0] address,output reg signed[15:0] sample);
 reg signed[15:0] data[0:1023];
 initial $readmemh("piano_sine.mem",data);
 always @(posedge clk)if(enable)sample<=data[address];
endmodule
