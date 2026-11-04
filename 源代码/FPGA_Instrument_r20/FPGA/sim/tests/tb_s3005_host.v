`timescale 1ns/1ps
module tb_s3005_host;
reg clk=0,reset=1;always #8.333 clk=~clk;
wire [1:0] typ;wire report,mode;wire[63:0] raw;wire[3:0] length;wire[47:0] keys;
wire[9:0] address;wire[3:0] instruction;wire en;
wire bitmap;
wire[31:0] notes;wire invalid;
usb_hid_host #(.MOUSE_SUPPORT(0),.GAME_SUPPORT(0)) host(.clk(clk),.reset(reset),.cs(1'b1),
 .usb_dp_i(1'b0),.usb_dm_i(1'b1),.typ(typ),.full_report(report),.dbg_hid_report(raw),
 .key_0(keys[7:0]),.key_1(keys[15:8]),.key_2(keys[23:16]),.key_3(keys[31:24]),.key_4(keys[39:32]),.key_5(keys[47:40]),
 .rom_addr(address),.rom_dout(instruction),.rom_en(en),.s3005_nkro(mode),.keyboard_report_length(length),.keyboard_bitmap_report(bitmap));
usb_hid_host_rom rom(clk,address,instruction,en,mode);
usb_note_decoder32 decoder(clk,!reset,typ==1,report,keys,notes,invalid,mode,raw,length,bitmap);
reg ready=0,strobe=0,start=0,connected=0,error=0,save=0,load=0;
reg[7:0] data=0;reg[3:0] addra=0,addrb=0;
initial begin
 force host.full_speed=0; // measured S3005 is USB low speed
 force host.ukprdy=ready;force host.ukpstb=strobe;force host.ukpstart=start;
 force host.ukpdat=data;force host.connected=connected;force host.connerr=error;
 force host.save=save;force host.load=load;force host.addra=addra;force host.addrb=addrb;
end
// Exercise the real wrapper's byte capture/count/CRC-tail exclusion.
// This boundary model includes two CRC byte slots, not USB line/CRC validation.
task packet(input[63:0] value,input integer count);
begin
 @(negedge clk);start=1;@(negedge clk);start=0;ready=1;
 for(integer i=0;i<count+2;i=i+1)begin
  data=i<count ? value>>(i*8) : 8'h00;strobe=1;
  @(negedge clk);strobe=0;@(negedge clk);
 end
 ready=0;repeat(5)@(negedge clk);
end endtask
task reg_write(input[3:0] index,input[7:0] value);
begin packet({56'd0,value},1);addra=index;addrb=0;save=1;@(negedge clk);save=0;repeat(3)@(negedge clk);end endtask
task check(input[31:0] value);begin if(notes!==value)$fatal(1,"host/decoder got%h expected%h raw%h len%d",notes,value,raw,length);end endtask
initial begin
 repeat(4)@(negedge clk);reset=0;
 reg_write(0,8'h2c);reg_write(1,8'h1a);reg_write(2,8'h7e);reg_write(3,8'h4d);
 reg_write(4,3);reg_write(5,1);reg_write(6,1);repeat(4)@(negedge clk);
 if(!mode || host.in_payload[0]!==8'h81 || host.in_payload[1]!==8'h58)$fatal(1,"S3005 initial endpoint1 selection");
 connected=1;repeat(6)@(negedge clk);
 packet(64'h0001fffffff00004,8);check(32'hfc7fffff);
 if(!bitmap || host.in_payload[0]!==8'h01 || host.in_payload[1]!==8'hc1 || host.polling_interval!==5)$fatal(1,"alternate endpoint2/5ms schedule");
 if(length!==8 || raw!==64'h0001fffffff00004)$fatal(1,"raw report capture");
 packet(64'h090708161a040000,8);check(32'hfc7fffff);
 if(bitmap || host.in_payload[0]!==8'h81 || host.in_payload[1]!==8'h58)$fatal(1,"alternate endpoint1 selection");
 packet(64'h000000000001c005,8);check(32'hffffffff);
 packet(64'h090708161a040000,8);check(32'hffffffff);
 packet(64'h0000000000000001,3);check(32'hffffffff);
 packet(64'h090708161a040000,8);check(32'hffffffff);
 packet(64'h0000000000000004,8);check(32'h0380003f);
 packet(0,8);check(32'h03800000);
 packet(64'h0000000000000005,8);check(0);
 packet(0,8);check(0);
 packet(64'h0001fffffff00004,7);check(0);if(!invalid)$fatal(1,"short packet not rejected");
 packet(0,8);check(0);
 packet(64'h000000000001c005,8);check(32'h03800000);
 error=1;repeat(3)@(negedge clk);check(0);if(mode)$fatal(1,"disconnect mode retained");
 connected=0;error=0;reg_write(0,8'h01);reg_write(1,8'h02);reg_write(2,8'h03);reg_write(3,8'h04);
 reg_write(4,3);reg_write(5,1);reg_write(6,1);repeat(4)@(negedge clk);
 if(mode || host.in_payload[0]!==8'h81 || host.in_payload[1]!==8'h58)$fatal(1,"other VID/PID changed");
 connected=1;repeat(6)@(negedge clk);packet(64'h090708161a040000,8);check(32'h3f);
 $display("PASS actual host wrapper: measured VID/PID selects endpoint2 and alternate ROM; all32 raw reports through capture/length/decoder; independent release; short-report/error cleanup; other keyboard endpoint1 Boot fallback");$finish;
end
initial begin #1000000;$fatal(1,"host watchdog");end
endmodule
