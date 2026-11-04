// Complete-report boundary model. No USB packet/electrical/enumeration claim.
// The bench drives typ/key/full_report nets; production decoder/CDC/audio stay real.
module usb_hid_host #(
    parameter FULL_SPEED=1,MOUSE_SUPPORT=0,GAME_SUPPORT=0
)(
    input wire clk,reset,cs,usb_dp_i,usb_dm_i,
    output wire usb_dp_o,usb_dm_o,usb_oe,
    output wire [1:0] typ,
    output wire full_report,connerr,
    output wire [7:0] key_0,key_1,key_2,key_3,key_4,key_5,
    output wire [9:0] rom_addr,
    input wire [3:0] rom_dout,
    output wire rom_en,
    output wire s3005_nkro,
    output wire [3:0] keyboard_report_length,
    output wire [63:0] dbg_hid_report
    ,output wire keyboard_bitmap_report
);
    assign {usb_dp_o,usb_dm_o,usb_oe}=0;
    assign typ=0;
    assign {full_report,connerr}=0;
    assign {key_0,key_1,key_2,key_3,key_4,key_5}=0;
    assign rom_addr=0;
    assign rom_en=0;
    assign s3005_nkro=0;
    assign keyboard_report_length=8;
    assign dbg_hid_report=0;
    assign keyboard_bitmap_report=0;
endmodule
