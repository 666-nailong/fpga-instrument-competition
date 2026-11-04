// Generated from Windows HID single-bit probes; run generate_s3005_nkro.py.
localparam [31:0] S3005_BANK4=32'hfc7fffff;
function [31:0] s3005_bank4;
input [63:0] report;
begin
s3005_bank4=0;
s3005_bank4[0]=report[20]; // A
s3005_bank4[1]=report[42]; // W
s3005_bank4[2]=report[38]; // S
s3005_bank4[3]=report[24]; // E
s3005_bank4[4]=report[23]; // D
s3005_bank4[5]=report[25]; // F
s3005_bank4[6]=report[39]; // T
s3005_bank4[7]=report[26]; // G
s3005_bank4[8]=report[44]; // Y
s3005_bank4[9]=report[27]; // H
s3005_bank4[10]=report[40]; // U
s3005_bank4[11]=report[29]; // J
s3005_bank4[12]=report[30]; // K
s3005_bank4[13]=report[34]; // O
s3005_bank4[14]=report[31]; // L
s3005_bank4[15]=report[35]; // P
s3005_bank4[16]=report[45]; // Z
s3005_bank4[17]=report[43]; // X
s3005_bank4[18]=report[22]; // C
s3005_bank4[19]=report[41]; // V
s3005_bank4[20]=report[21]; // B
s3005_bank4[21]=report[33]; // N
s3005_bank4[22]=report[32]; // M
s3005_bank4[26]=report[36]; // Q
s3005_bank4[27]=report[37]; // R
s3005_bank4[28]=report[28]; // I
s3005_bank4[29]=report[46]; // 1
s3005_bank4[30]=report[47]; // 2
s3005_bank4[31]=report[48]; // 3
end
endfunction
localparam [31:0] S3005_BANK5=32'h03800000;
function [31:0] s3005_bank5;
input [63:0] report;
begin
s3005_bank5=0;
s3005_bank5[23]=report[14]; // ,
s3005_bank5[24]=report[15]; // .
s3005_bank5[25]=report[16]; // /
end
endfunction
