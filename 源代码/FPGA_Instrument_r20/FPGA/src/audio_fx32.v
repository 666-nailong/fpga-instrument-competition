// Native-rate insert effects. One 512x16 fractional-delay vibrato RAM and
// four 2048x16 comb banks; every memory read is synchronous. No reset RAM clear.
module audio_fx32(
 input wire clk,reset_n,start,
 input wire signed[15:0] left_in,right_in,
 input wire[7:0] stereo_depth,vibrato_depth,reverb_depth,
 output reg signed[15:0] left_out,right_out,
 output reg ready,overrun
);
 reg signed[15:0] delay_ram[0:511];
 reg signed[15:0] room_ram[0:8191];
 reg[8:0] delay_addr,delay_write;
 reg signed[15:0] delay_q;
 reg[12:0] room_addr;
 reg[12:0] room_write_addr;
 reg signed[15:0] room_write_data;
 reg room_write_enable;
 reg signed[15:0] room_q;
 always @(posedge clk)begin
 delay_q<=delay_ram[delay_addr];room_q<=room_ram[room_addr];
 if(room_write_enable)room_ram[room_write_addr]<=room_write_data;
 end
 reg[5:0] state;
 reg[31:0] phase;
 reg[15:0] frames;
 reg[8:0] filled_delay;
 reg[10:0] pos[0:3];
 reg[1:0] line_no;
 reg signed[15:0] dry_l,dry_r,mono,a,b,vib,side;
 reg signed[19:0] sum_l,sum_r;
 reg signed[31:0] product;
 reg signed[16:0] delta;
 reg[7:0] fraction;
 reg[7:0] width,depth,wet;
 reg signed[15:0] tap;
 reg[15:0] delay_fixed;
 wire[15:0] triangle=phase[31] ? ~phase[30:15] : phase[30:15];
 wire signed[16:0] centered=$signed({1'b0,triangle})-17'sd32768;
 wire signed[25:0] modulation=centered*$signed({1'b0,vibrato_depth});
 wire signed[16:0] mono_sum=$signed({left_in[15],left_in})+$signed({right_in[15],right_in});
 function[10:0] length;
 input[1:0] k;begin case(k)0:length=1499;1:length=1613;2:length=1747;3:length=1867;endcase end
 endfunction
 function signed[15:0] sat;
 input signed[31:0] x;begin sat=x>32767 ? 16'sh7fff : x< -32768 ? 16'sh8000 : x[15:0];end
 endfunction
 integer i;
 always @(posedge clk)begin
 if(!reset_n)begin
 state<=0;phase<=0;frames<=0;filled_delay<=0;delay_write<=0;delay_addr<=0;room_addr<=0;
 dry_l<=0;dry_r<=0;mono<=0;a<=0;b<=0;vib<=0;side<=0;sum_l<=0;sum_r<=0;
 product<=0;delta<=0;fraction<=0;width<=0;depth<=0;wet<=0;tap<=0;delay_fixed<=0;
 line_no<=0;left_out<=0;right_out<=0;ready<=0;overrun<=0;
 room_write_enable<=0;room_write_addr<=0;room_write_data<=0;
 for(i=0;i<4;i=i+1)pos[i]<=0;
 end else begin
 room_write_enable<=0;
 if(start && state!=0)overrun<=1;
 case(state)
 0:if(start)begin
 ready<=0;dry_l<=left_in;dry_r<=right_in;mono<=mono_sum>>>1;
 width<=stereo_depth;depth<=vibrato_depth;wet<=reverb_depth;
 phase<=phase+32'd439805;
 delay_ram[delay_write]<=mono_sum>>>1;
 if(filled_delay<511)filled_delay<=filled_delay+1'b1;
 delay_fixed<=16'd10240+(modulation>>>10);state<=1;
 end
 1:begin delay_addr<=delay_write-delay_fixed[15:8];fraction<=delay_fixed[7:0];state<=2;end
 2:state<=3;
 3:begin a<=filled_delay>80 ? delay_q : 16'sd0;delay_addr<=delay_addr-1'b1;state<=4;end
 4:state<=5;
 5:begin b<=filled_delay>80 ? delay_q : 16'sd0;state<=6;end
 6:begin delta<=$signed({b[15],b})-$signed({a[15],a});state<=7;end
 7:begin product<=delta*$signed({1'b0,fraction});state<=8;end
 8:begin vib<=depth==0 ? mono : sat($signed(a)+(product>>>8));delay_addr<=delay_write-9'd24;state<=9;end
 9:state<=10;
 10:begin side<=filled_delay>80 ? delay_q : 16'sd0;line_no<=0;sum_l<=0;sum_r<=0;state<=11;end
 11:begin room_addr<={line_no,pos[line_no]};state<=12;end
 12:state<=13;
 13:begin tap<=frames>=length(line_no) ? room_q : 16'sd0;state<=14;end
 14:begin
 room_write_addr<=room_addr;
 room_write_data<=sat(($signed(tap)*32'sd7>>>3)+($signed(vib)>>>3));
 room_write_enable<=1;
 sum_l<=sum_l+(line_no==1 ? -$signed(tap) : $signed(tap));
 sum_r<=sum_r+(line_no==2 ? -$signed(tap) : $signed(tap));
 pos[line_no]<=pos[line_no]==length(line_no)-1 ? 11'd0 : pos[line_no]+1'b1;
 if(line_no==3)state<=15;else begin line_no<=line_no+1'b1;state<=11;end
 end
 15:begin
 // Side channel vanishes exactly at width=0. Wet is independently bypassable.
 product<=($signed(vib)-$signed(side))*$signed({1'b0,width});state<=16;
 end
 16:begin
 left_out<=sat($signed(depth==0 && width==0 ? mono : vib)+(product>>>10)+(($signed(sum_l)*$signed({1'b0,wet}))>>>11));
 right_out<=sat($signed(depth==0 && width==0 ? mono : vib)-(product>>>10)+(($signed(sum_r)*$signed({1'b0,wet}))>>>11));
 // True bypass preserves existing stereo when width is fully on and others off.
 if(width==255 && depth==0 && wet==0)begin left_out<=dry_l;right_out<=dry_r;end
 // Reverb also folds to mono when stereo is disabled.
 if(width==0)begin
 left_out<=sat($signed(vib)+((($signed(sum_l)+$signed(sum_r))*$signed({1'b0,wet}))>>>12));
 right_out<=sat($signed(vib)+((($signed(sum_l)+$signed(sum_r))*$signed({1'b0,wet}))>>>12));
 end
 // All effects off is an exact stereo bypass; preserve anti-phase material.
 if(width==0 && depth==0 && wet==0)begin left_out<=dry_l;right_out<=dry_r;end
 delay_write<=delay_write+1'b1;if(frames!=65535)frames<=frames+1'b1;
 ready<=1;state<=0;
 end
 default:state<=0;
 endcase
 end
 end
endmodule
