`timescale 1ns/1ps
module tb_s3005_nkro;
reg clk=0,reset_n=0,kready=0,strobe=0;always #8.333 clk=~clk;
reg nkro=1,bitmap=1;reg[47:0] boot=0;reg[63:0] data=0;reg[3:0] length=8;
wire[31:0] notes;wire invalid;
usb_note_decoder32 dut(clk,reset_n,kready,strobe,boot,notes,invalid,nkro,data,length,bitmap);
reg[7:0] usage[0:31];reg[63:0] packet;integer single_checks=0;
task send(input[7:0] id,input[31:0] mask,input[3:0] len);
begin
 packet=0;packet[7:0]=id;
 for(integer i=0;i<32;i=i+1)if(mask[i])begin
  if(id==4 && usage[i]<48)packet[16+usage[i]]=1;
  if(id==5 && usage[i]>=48 && usage[i]<104)packet[8+usage[i]-48]=1;
 end
 @(negedge clk);data=packet;length=len;strobe=1;
 @(negedge clk);strobe=0;repeat(2)@(negedge clk);
end endtask
task check(input[31:0] expected);begin if(notes!==expected)$fatal(1,"mask got%h expected%h",notes,expected);end endtask
initial begin
 usage[0]=4;usage[1]=26;usage[2]=22;usage[3]=8;usage[4]=7;usage[5]=9;usage[6]=23;usage[7]=10;
 usage[8]=28;usage[9]=11;usage[10]=24;usage[11]=13;usage[12]=14;usage[13]=18;usage[14]=15;usage[15]=19;
 usage[16]=29;usage[17]=27;usage[18]=6;usage[19]=25;usage[20]=5;usage[21]=17;usage[22]=16;usage[23]=54;
 usage[24]=55;usage[25]=56;usage[26]=20;usage[27]=21;usage[28]=12;usage[29]=30;usage[30]=31;usage[31]=32;
 repeat(3)@(negedge clk);reset_n=1;kready=1;
 for(integer i=0;i<32;i=i+1)begin
  send(4,32'd1<<i,8);send(5,32'd1<<i,8);check(32'd1<<i);single_checks=single_checks+1;
 end
 send(4,32'hffffffff,8);send(5,32'hffffffff,8);check(32'hffffffff);
 // Consumer/system/third bitmap reports cannot release notes from IDs4 and5.
 send(1,0,3);send(2,0,2);send(3,0,2);send(6,0,8);check(32'hffffffff);
 send(4,0,8);check(32'h03800000);send(5,0,8);check(0);
 send(5,32'hffffffff,8);send(4,32'hffffffff,8);check(32'hffffffff);
 send(5,0,8);check(32'hfc7fffff);
 send(4,0,7);check(0);if(!invalid)$fatal(1,"truncated report accepted");
 send(4,1,8);check(1);if(invalid)$fatal(1,"valid recovery");
 @(negedge clk);data=64'h0000000000040004;strobe=1;
 @(negedge clk);strobe=0;repeat(2)@(negedge clk);check(0);if(!invalid)$fatal(1,"error usage bit ignored");
 send(4,32'hffffffff,8);send(5,32'hffffffff,8);check(32'hffffffff);
 kready=0;repeat(2)@(negedge clk);check(0);if(invalid)$fatal(1,"disconnect invalid flag");
 kready=1;send(4,1,8);check(1);send(4,0,8);check(0);
 nkro=0;boot=48'h090708161a04;
 @(negedge clk);strobe=1;@(negedge clk);strobe=0;repeat(2)@(negedge clk);check(32'h3f);
 nkro=1;bitmap=0;
 @(negedge clk);strobe=1;@(negedge clk);strobe=0;repeat(2)@(negedge clk);check(32'h3f);
 bitmap=1;send(4,32'hffffffff,8);send(5,32'hffffffff,8);check(32'hffffffff);
 send(4,0,8);send(5,0,8);check(32'h3f);
 bitmap=0;boot=0;@(negedge clk);strobe=1;@(negedge clk);strobe=0;repeat(2)@(negedge clk);check(0);
 $display("CHECK real S3005 split: Boot first6 plus supplemental bitmap; either interface release preserves other");
 $display("PASS S3005 NKRO: all%0d single keys; all32 simultaneous across IDs4/5 both orders; independent bank release; irrelevant IDs ignored; truncated/error release; unplug/replug; Boot fallback",single_checks);$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
