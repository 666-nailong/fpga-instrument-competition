// 50 MHz -> average 3.072 MHz BCLK / 48 kHz LRCLK, 64 BCLK per frame.
// All state stays in clk. External PCM5102 SCK is grounded (BCK PLL mode).
module pcm5102_i2s(
    input wire clk, reset_n, enable, pcm_valid,
    input wire [15:0] pcm_left, pcm_right,
    output reg bck, lrck, din,
    output reg hp_bck, hp_ws, hp_din,
    output wire frame_tick,
    output reg underrun,
    output reg [15:0] sample_left, sample_right
);
    localparam [32:0] HALF_BCLK_STEP = 33'd527765581;
    reg [31:0] phase;
    wire [32:0] next_phase = {1'b0,phase} + HALF_BCLK_STEP;
    wire falling = next_phase[32] && bck;
    reg [5:0] bit_pos;
    reg [4:0] pt_bit;
    reg started;
    assign frame_tick = falling && bit_pos == 0;
    always @(posedge clk) begin
        if(!reset_n) begin
            phase<=0;bit_pos<=0;bck<=0;lrck<=0;din<=0;
            hp_bck<=0;hp_ws<=1;hp_din<=0;pt_bit<=0;
            sample_left<=0;sample_right<=0;underrun<=0;started<=0;
        end else begin
            phase<=next_phase[31:0];
            underrun<=0;
            if(next_phase[32]) bck<=~bck;
            if(falling) begin
                // PT8211 uses 32 clocks/frame and right-first LSBJ. Both DACs
                // receive the identical frozen pair, without a second rate converter.
                hp_bck<=~hp_bck;
                if(hp_bck) begin
                    pt_bit<=pt_bit+1'b1;
                    hp_ws<=pt_bit>=16;
                    hp_din<=pt_bit<16 ? sample_right[15-pt_bit] : sample_left[31-pt_bit];
                end
                bit_pos<=bit_pos+1'b1;
                if(bit_pos==0) begin
                    lrck<=0;din<=0;
                    sample_left<=enable && pcm_valid ? pcm_left : 16'd0;
                    sample_right<=enable && pcm_valid ? pcm_right : 16'd0;
                    underrun<=enable && started && !pcm_valid;
                    started<=enable;
                end else if(bit_pos==32) begin
                    lrck<=1;din<=0;
                end else if(bit_pos>=1 && bit_pos<=16)
                    din<=sample_left[16-bit_pos];
                else if(bit_pos>=33 && bit_pos<=48)
                    din<=sample_right[48-bit_pos];
                else din<=0;
            end
        end
    end
endmodule
