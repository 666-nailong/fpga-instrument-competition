// FE uses the F0 payload format for notes 16..31; independent timeout.
// 115200 8N1: F0, mask[6:0], mask[13:7], {5'd0,mask[15:14]}, XOR of payload.
// F1 echoes XOR-checked snapshots. F2/zero queries return F3 telemetry without changing held.
// No complete note snapshot for 100ms releases notes; status queries do not refresh this timer.
module laptop_note_uart #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer TIMEOUT_MS = 100,
    parameter integer ENABLE_TX = 1,
    parameter integer ENABLE_VOLUME = 0,
    parameter integer ENABLE_HMI_GAIN = 0
)(
    input wire clk, reset_n, rx,
    output reg tx,
    output reg [15:0] held, upper_held,
    output reg snapshot_valid,
    input wire [1:0] timbre,
    input wire audio_ready, audio_fault, octave,
    output reg [8:0] volume_target,
    output reg [6:0] hmi_gain,
    output reg volume_valid,
    output reg hmi_gain_valid
);
    localparam integer BIT_CYCLES = (CLK_HZ + BAUD/2)/BAUD;
    localparam integer TIMEOUT_CYCLES = CLK_HZ/1000*TIMEOUT_MS;
    localparam integer GAP_CYCLES = CLK_HZ/1000*5;
    reg rx_meta, rx_sync;
    reg [1:0] rx_state;
    reg [15:0] rx_timer;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift, byte_data;
    reg byte_valid, byte_bad;
    reg [2:0] packet_index;
    reg [15:0] packet_mask;
    reg [6:0] checksum;
    reg [31:0] idle_timer, upper_timer, gap_timer;
    reg [2:0] packet_kind;
    reg status_valid;
    always @(posedge clk) begin
        if (!reset_n) begin
            rx_meta<=1;rx_sync<=1;rx_state<=0;rx_timer<=0;rx_bit<=0;
            rx_shift<=0;byte_data<=0;byte_valid<=0;byte_bad<=0;
        end else begin
            rx_meta<=rx;rx_sync<=rx_meta;byte_valid<=0;byte_bad<=0;
            case(rx_state)
                0: if(!rx_sync) begin rx_timer<=BIT_CYCLES/2-1;rx_state<=1;end
                1: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else if(rx_sync) rx_state<=0;
                   else begin rx_timer<=BIT_CYCLES-1;rx_bit<=0;rx_state<=2;end
                2: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       rx_shift[rx_bit]<=rx_sync;rx_timer<=BIT_CYCLES-1;
                       if(rx_bit==7) rx_state<=3;else rx_bit<=rx_bit+1'b1;
                   end
                3: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       byte_data<=rx_shift;byte_valid<=rx_sync;byte_bad<=!rx_sync;rx_state<=0;
                   end
            endcase
        end
    end
    always @(posedge clk) begin
        if(!reset_n) begin
            held<=0;upper_held<=0;upper_timer<=0;snapshot_valid<=0;packet_index<=0;packet_mask<=0;
            checksum<=0;idle_timer<=0;gap_timer<=0;
            packet_kind<=0;status_valid<=0;volume_target<=9'd256;
            hmi_gain<=7'd64;hmi_gain_valid<=0;volume_valid<=0;
        end else begin
            snapshot_valid<=0;
            volume_valid<=0;hmi_gain_valid<=0;
            status_valid<=0;
            if(upper_timer<TIMEOUT_CYCLES) upper_timer<=upper_timer+1'b1;
            if(upper_timer==TIMEOUT_CYCLES-1) upper_held<=0;
            if(idle_timer<TIMEOUT_CYCLES) idle_timer<=idle_timer+1'b1;
            if(idle_timer==TIMEOUT_CYCLES-1) held<=0;
            if(gap_timer<GAP_CYCLES) gap_timer<=gap_timer+1'b1;
            if(gap_timer==GAP_CYCLES-1 || byte_bad) packet_index<=0;
            if(byte_valid) begin
                gap_timer<=0;
                if(byte_data==8'hfe || byte_data==8'hf0 || byte_data==8'hf2 || (ENABLE_VOLUME!=0 && byte_data==8'hfa) ||
                   (ENABLE_HMI_GAIN!=0 && byte_data==8'hfd)) begin
                    packet_index<=1;checksum<=0;
                    packet_kind<=byte_data==8'hfe ? 3'd4 : byte_data==8'hfd ? 3'd3 : byte_data==8'hfa ? 3'd2 : byte_data==8'hf2 ? 3'd1 : 3'd0;
                end
                else if(byte_data[7]) packet_index<=0;
                else case(packet_index)
                    1: begin packet_mask[6:0]<=byte_data[6:0];checksum<=byte_data[6:0];packet_index<=2;end
                    2: begin packet_mask[13:7]<=byte_data[6:0];checksum<=checksum^byte_data[6:0];packet_index<=3;end
                    3: if(byte_data[6:2]!=0) packet_index<=0;
                       else begin packet_mask[15:14]<=byte_data[1:0];checksum<=checksum^byte_data[6:0];packet_index<=4;end
                    4: begin
                        if(byte_data[6:0]==checksum) begin
                            if(packet_kind==4) begin
                                upper_held<=packet_mask;upper_timer<=0;
                            end else if(packet_kind==3) begin
                                if(packet_mask==1 || packet_mask==4 || packet_mask==16 || packet_mask==32 || packet_mask==64) begin
                                    hmi_gain<=packet_mask[6:0];hmi_gain_valid<=1;
                                end
                            end else if(packet_kind==2) begin
                                if(packet_mask<=16'd256) begin volume_target<=packet_mask[8:0];volume_valid<=1;end
                            end else if(packet_kind==1) begin
                                if(packet_mask==0) status_valid<=1;
                            end else begin held<=packet_mask;snapshot_valid<=1;idle_timer<=0;end
                        end
                        packet_index<=0;
                    end
                    default: packet_index<=0;
                endcase
            end
        end
    end
    reg [39:0] reply;
    reg [15:0] tx_timer;
    reg [3:0] tx_bit;
    reg [2:0] tx_byte;
    reg tx_busy;
    reg status_pending;
    wire reply_status=status_valid || status_pending;
    wire [6:0] reply_c=reply_status ? {octave,audio_ready,audio_fault,timbre,held[15:14]} : {5'd0,held[15:14]};
    // A query can arrive during a note echo; preserve it until TX becomes idle.
    always @(posedge clk)
        if(!reset_n) status_pending<=0;
        else status_pending<=(status_pending || status_valid) && tx_busy;
    always @(posedge clk) begin
        if(!reset_n || ENABLE_TX==0) begin tx<=1;reply<=0;tx_timer<=0;tx_bit<=0;tx_byte<=0;tx_busy<=0;end
        else if(!tx_busy) begin
            if(snapshot_valid || reply_status) begin
                reply<={1'b0,(held[6:0]^held[13:7]^reply_c),
                        1'b0,reply_c,1'b0,held[13:7],1'b0,held[6:0],(reply_status ? 8'hf3 : 8'hf1)};
                tx<=0;tx_timer<=BIT_CYCLES-1;tx_bit<=0;tx_byte<=0;tx_busy<=1;
            end
        end else if(tx_timer!=0) tx_timer<=tx_timer-1'b1;
        else begin
            tx_timer<=BIT_CYCLES-1;
            if(tx_bit<8) begin tx<=reply[0];reply<=reply>>1;tx_bit<=tx_bit+1'b1;end
            else if(tx_bit==8) begin tx<=1;tx_bit<=9;end
            else if(tx_byte==4) begin tx<=1;tx_busy<=0;end
            else begin tx<=0;tx_bit<=0;tx_byte<=tx_byte+1'b1;end
        end
    end
endmodule
