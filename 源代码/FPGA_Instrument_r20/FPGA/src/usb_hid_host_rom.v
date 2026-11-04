`default_nettype none
`timescale 1ns / 1ps
module usb_hid_host_rom(
  input  wire       clk,

  input  wire [9:0] addr,
  output reg  [3:0] dout,
  input  wire       en,
  input  wire       s3005_nkro
);

reg [3:0] mem [0:2047];

initial
  $readmemh("usb_hid_host_s3005.mem", mem);

always @(posedge clk)
  if (en)
    dout <= mem[{s3005_nkro,addr}];

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
