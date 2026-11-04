`timescale 1ns/1ps
module tb_s3005_rom;
reg clk=0,reset=1,mode=0;always #8.333 clk=~clk;
wire[9:0] addr;wire[3:0] inst;wire en;
ukp #(.FULL_SPEED(1)) dut(.clk(clk),.reset(reset),.cs(1'b1),.usb_dp_i(1'b0),.usb_dm_i(1'b1),
 .load_data(8'd0),.rom_addr(addr),.rom_dout(inst),.rom_en(en));
usb_hid_host_rom rom(clk,addr,inst,en,mode);
reg[95:0] bytes;integer count,previous;
task request(input integer entry,input[95:0] expected);
begin
 reset=1;repeat(8)@(negedge clk);reset=0;dut.pc=entry;dut.state=0;
 rom.dout=rom.mem[{mode,10'(entry)}];bytes=0;count=0;previous=0;
 while(dut.state!=10)begin
  @(negedge clk);
  if(dut.state==14 && previous!=14 && dut.insth==6)begin bytes={bytes[87:0],dut.sb};count=count+1;end
  previous=dut.state;
 end
 if(count!=12 || bytes!==expected)$fatal(1,"ROM request mode%0d entry%0d bytes%h expected%h count%0d",mode,entry,bytes,expected,count);
end endtask
initial begin
 force dut.conct=0;
 for(integer speed=0;speed<2;speed=speed+1)begin
  if(speed==0)force dut.full_speed=0;else force dut.full_speed=1;
  mode=0;
  request(552,96'h80c3210a000000000000d620);
  request(596,96'h80c3210b000000000000c6e0);
  request(640,96'h80c38106002200000900ee0f);
  mode=1;
  request(552,96'h80c3210a000001000000d7dc);
  request(596,96'h80c3210b010001000000c6cd);
  request(640,96'h80c38106002201000900eff3);
 end
 $display("PASS production UKP instructions: low/full speed, original interface0 Boot page preserved; S3005 SET_IDLE iface1, descriptor iface1, SET_PROTOCOL Report1 iface1 including exact CRC16");$finish;
end
initial begin #10000000;$fatal(1,"ROM watchdog pc%h state%0d",dut.pc,dut.state);end
endmodule
