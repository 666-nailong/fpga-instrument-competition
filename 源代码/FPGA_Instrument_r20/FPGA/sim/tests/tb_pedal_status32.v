`timescale 1ns/1ps
module tb_pedal_status32;
reg clk=0,rst=0,rx=1;always #10 clk=~clk;
wire tx;reg[31:0] held=0;reg[55:0] reply=0;reg[7:0] ch;integer n=0;
keyboard_status_uart dut(.clk(clk),.reset_n(rst),.rx(rx),.tx(tx),.held(held[15:0]),.held_full(32'd0),.pedal_status(held),
 .timbre(2'd1),.audio_ready(1'b1),.audio_fault(1'b0),.octave(1'b0),.keyboard_ready(1'b1),.invalid_report(1'b0),
 .pcm_left(16'd0),.pcm_right(16'd0),.note_snapshot(1'b0),.volume_target(9'd256),.volume_applied(9'd256));
task byte_out(input[7:0] value);begin
 rx=0;#8680;for(integer i=0;i<8;i=i+1)begin rx=value[i];#8680;end rx=1;#8680;
end endtask
initial forever begin
 @(negedge tx);#13020;for(integer i=0;i<8;i=i+1)begin ch[i]=tx;#8680;end
 if(tx!==1)$fatal(1,"diagnostic stop bit");
 reply[n*8+:8]=ch;n=n+1;#4340;
end
task query(input[31:0] value);
reg[31:0] decoded;reg[6:0] checksum;begin
 held=value;n=0;reply=0;
 byte_out(8'hfa);repeat(4)byte_out(0);wait(n==7);
 decoded=reply[15:8]|(reply[23:16]<<7)|(reply[31:24]<<14)|(reply[39:32]<<21)|(reply[47:40]<<28);
 checksum=reply[15:8]^reply[23:16]^reply[31:24]^reply[39:32]^reply[47:40];
 if(reply[7:0]!==8'hff || decoded!==value || reply[55:48]!=={1'b0,checksum})$fatal(1,"FA/FF32 got%h expected%h raw%h",decoded,value,reply);
 repeat(100)@(negedge clk);
end endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 query(32'hffffffff);query(32'h80000000);query(32'ha9011234);query(32'h00000001);query(0);
 $display("PASS real115200 FA/FF full32 diagnostic UART: ADC raw/scaled/ready/error/sequence, endpoints and XOR checksum");$finish;
end
initial begin #20000000;$fatal(1,"status32 watchdog");end
endmodule
