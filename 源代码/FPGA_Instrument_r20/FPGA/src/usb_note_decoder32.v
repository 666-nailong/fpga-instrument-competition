// Measured S3005 NKRO uses two report IDs; preserve the other bank on updates.
module usb_note_decoder32(
 input wire clk,reset_n,keyboard_ready,report_strobe,
 input wire [47:0] keys,
 output reg [31:0] notes,
 output reg invalid_report,
 input wire s3005_nkro,
 input wire [63:0] report_data,
 input wire [3:0] report_length,
 input wire bitmap_report
);
 `include "s3005_note_map.vh"
 reg [31:0] boot_notes,bitmap_notes;
 function [31:0] usage_bit;
 input [7:0] usage;
 begin case(usage)
            8'h04: usage_bit=32'h00000001; // A
            8'h1a: usage_bit=32'h00000002; // W
            8'h16: usage_bit=32'h00000004; // S
            8'h08: usage_bit=32'h00000008; // E
            8'h07: usage_bit=32'h00000010; // D
            8'h09: usage_bit=32'h00000020; // F
            8'h17: usage_bit=32'h00000040; // T
            8'h0a: usage_bit=32'h00000080; // G
            8'h1c: usage_bit=32'h00000100; // Y
            8'h0b: usage_bit=32'h00000200; // H
            8'h18: usage_bit=32'h00000400; // U
            8'h0d: usage_bit=32'h00000800; // J
            8'h0e: usage_bit=32'h00001000; // K
            8'h12: usage_bit=32'h00002000; // O
            8'h0f: usage_bit=32'h00004000; // L
            8'h13: usage_bit=32'h00008000; // P
            8'h1d: usage_bit=32'h00010000; // Z
            8'h1b: usage_bit=32'h00020000; // X
            8'h06: usage_bit=32'h00040000; // C
            8'h19: usage_bit=32'h00080000; // V
            8'h05: usage_bit=32'h00100000; // B
            8'h11: usage_bit=32'h00200000; // N
            8'h10: usage_bit=32'h00400000; // M
            8'h36: usage_bit=32'h00800000; // ,
            8'h37: usage_bit=32'h01000000; // .
            8'h38: usage_bit=32'h02000000; // /
            8'h14: usage_bit=32'h04000000; // Q
            8'h15: usage_bit=32'h08000000; // R
            8'h0c: usage_bit=32'h10000000; // I
            8'h1e: usage_bit=32'h20000000; // 1
            8'h1f: usage_bit=32'h40000000; // 2
            8'h20: usage_bit=32'h80000000; // 3
 default:usage_bit=0;
 endcase end endfunction
 integer i;
 reg [31:0] decoded;
 reg invalid;
 always @* begin
 decoded=0;invalid=0;
 for(i=0;i<6;i=i+1)begin
 decoded=decoded|usage_bit(keys[i*8+:8]);
 if(keys[i*8+:8]>=1 && keys[i*8+:8]<=3)invalid=1;
 end
 end
 always @(posedge clk or negedge reset_n)
 if(!reset_n)begin notes<=0;boot_notes<=0;bitmap_notes<=0;invalid_report<=0;end
 else if(!keyboard_ready)begin notes<=0;boot_notes<=0;bitmap_notes<=0;invalid_report<=0;end
 else if(report_strobe)begin
 if(s3005_nkro)begin
 if(!bitmap_report)begin
 if(report_length!=8 || invalid)begin notes<=0;boot_notes<=0;bitmap_notes<=0;invalid_report<=1;end
 else begin boot_notes<=decoded;notes<=decoded|bitmap_notes;invalid_report<=0;end
 end else begin
 if(report_data[7:0]==4 || report_data[7:0]==5)begin
 if(report_length!=8 || (report_data[7:0]==4 && |report_data[19:17]))begin notes<=0;boot_notes<=0;bitmap_notes<=0;invalid_report<=1;end
 else if(report_data[7:0]==4)begin
 bitmap_notes<=(bitmap_notes & ~S3005_BANK4)|s3005_bank4(report_data);
 notes<=boot_notes|(bitmap_notes & ~S3005_BANK4)|s3005_bank4(report_data);invalid_report<=0;
 end else begin
 bitmap_notes<=(bitmap_notes & ~S3005_BANK5)|s3005_bank5(report_data);
 notes<=boot_notes|(bitmap_notes & ~S3005_BANK5)|s3005_bank5(report_data);invalid_report<=0;end
 end
 end
 end else begin notes<=invalid ? 32'd0 : decoded;invalid_report<=invalid;end
 end
endmodule
