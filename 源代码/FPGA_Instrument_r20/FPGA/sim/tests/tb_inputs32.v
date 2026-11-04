`timescale 1ns/1ps
module tb_inputs32;
reg clk=0,rst=0,kready=0,strobe=0;
always #10 clk=~clk;
reg [47:0] keys=0;wire [31:0] notes;wire invalid;
usb_note_decoder32 d(clk,rst,kready,strobe,keys,notes,invalid,1'b0,64'd0,4'd0,1'b0);
reg tick=0,clear=0,valid=0,error=0;reg [15:0] sample=0;reg[31:0] held=0;
wire[31:0] sustained;wire[7:0] pressure;wire sensor_ready;
pressure_sustain32 #(.TIMEOUT_MS(20),.FULL_SCALE(20000),.DEAD_ZONE(400),.MAX_HOLD_MS(255)) s(clk,rst,tick,clear,held,sample,valid,error,sustained,pressure,sensor_ready);
reg[7:0] usages[0:31];
task report(input [47:0] value);begin @(negedge clk);keys=value;strobe=1;@(negedge clk);strobe=0;end endtask
task ms;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(34)@(negedge clk);end endtask
task adc(input[15:0] value);begin @(negedge clk);sample=value;valid=1;@(negedge clk);valid=0;repeat(70)@(negedge clk);end endtask
initial begin
usages[0]=8'd4;
usages[1]=8'd26;
usages[2]=8'd22;
usages[3]=8'd8;
usages[4]=8'd7;
usages[5]=8'd9;
usages[6]=8'd23;
usages[7]=8'd10;
usages[8]=8'd28;
usages[9]=8'd11;
usages[10]=8'd24;
usages[11]=8'd13;
usages[12]=8'd14;
usages[13]=8'd18;
usages[14]=8'd15;
usages[15]=8'd19;
usages[16]=8'd29;
usages[17]=8'd27;
usages[18]=8'd6;
usages[19]=8'd25;
usages[20]=8'd5;
usages[21]=8'd17;
usages[22]=8'd16;
usages[23]=8'd54;
usages[24]=8'd55;
usages[25]=8'd56;
usages[26]=8'd20;
usages[27]=8'd21;
usages[28]=8'd12;
usages[29]=8'd30;
usages[30]=8'd31;
usages[31]=8'd32;
repeat(3)@(negedge clk);rst=1;kready=1;
for(integer i=0;i<32;i=i+1)begin report({40'd0,usages[i]});if(notes!==(32'd1<<i))$fatal(1,"mapping %0d",i);end
report({usages[31],usages[27],usages[20],usages[16],usages[5],usages[0]});
if(notes!==32'h88110021)$fatal(1,"six-key high mask %h",notes);
report(48'h010000000004);if(notes!==0 || !invalid)$fatal(1,"rollover");
report(0);if(notes!==0 || invalid)$fatal(1,"recovery");
kready=0;@(negedge clk);if(notes!==0)$fatal(1,"unplug");
adc(20000);held=32'h80000001;ms();held=0;ms();
if(sustained!==32'h80000001 || pressure!==255)$fatal(1,"pressure retain");
error=1;ms();if(sustained!==0)$fatal(1,"error must release");error=0;
adc(20000);held=1;ms();held=0;for(integer i=0;i<22;i=i+1)ms();
if(sensor_ready || sustained!==0)$fatal(1,"stale sensor");
adc(400);held=1;ms();held=0;ms();if(sustained!==0)$fatal(1,"dead zone");
adc(16'hffff);if(pressure!==0)$fatal(1,"negative ADC");
adc(20000);held=4;ms();held=0;clear=1;ms();if(sustained!==0)$fatal(1,"clear");
clear=0;
// Same released key: greater pressure must yield a strictly longer hold.
adc(10200);held=1;ms();held=0;
for(integer i=0;i<130;i=i+1)begin adc(10200);ms();end
if(sustained!==0)$fatal(1,"half pressure duration");
adc(20000);held=1;ms();held=0;
for(integer i=0;i<130;i=i+1)begin adc(20000);ms();end
if(sustained!==1)$fatal(1,"full pressure too short");
for(integer i=0;i<130;i=i+1)begin adc(20000);ms();end
if(sustained!==0)$fatal(1,"full pressure not finite");
$display("PASS32 mappings incl bit31; 6-key mask; invalid/unplug; pressure retain/deadzone/NACK/timeout/clear");$finish;
end
initial begin #2000000;$fatal(1,"watchdog");end
endmodule
