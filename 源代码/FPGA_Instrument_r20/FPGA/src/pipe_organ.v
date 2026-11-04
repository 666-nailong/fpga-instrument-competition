// Three independently phased pipe ranks: principal 8', octave 4', superoctave 2'.
// All partials, key envelopes and chiff noise are generated at run time.
module pipe_organ(
    input wire clk,reset_n,frame_tick,enable,octave,
    input wire [31:0] gate,
    output reg signed [15:0] sample,
    output reg ready
);
    `include "natural_pitch.vh"
    reg [3:0] state;
    reg [4:0] voice;
    reg [1:0] group;
    reg [31:0] gates,previous_gate;
    reg octave_frame,previous_octave;
    reg [31:0] phase8[0:31],phase4[0:31],phase2[0:31];
    reg [15:0] levels[0:31],ages[0:31];
    reg [15:0] level,age;
    reg [31:0] p8,p4,p2,increment;
    reg signed [23:0] partial_sum,mix;
    reg signed [32:0] products[0:3];
    reg signed [40:0] envelope_product;
    reg [22:0] noise=23'h65ab39;
    wire [5:0] note={1'b0,voice}+(octave_frame ? 6'd12 : 6'd0);
    function [31:0] angle;
        input [3:0] partial;
        begin case(partial)
            0:angle=p8;1:angle=p8<<1;2:angle=p8+(p8<<1);3:angle=p8<<2;
            4:angle=p8+(p8<<2);5:angle=(p8<<1)+(p8<<2);6:angle=(p8<<3)-p8;7:angle=p8<<3;
            8:angle=p4;9:angle=p4<<1;10:angle=p4+(p4<<1);11:angle=p4<<2;
            12:angle=p2;13:angle=p2<<1;default:angle=0;
        endcase end
    endfunction
    function signed [15:0] amplitude;
        input [3:0] partial;
        reg [4:0] multiple;
        reg [36:0] frequency_word;
        reg signed [15:0] value;
        begin
            case(partial)
                0:begin value=16384;multiple=1;end
                1:begin value=4096;multiple=2;end
                2:begin value=3072;multiple=3;end
                3:begin value=2048;multiple=4;end
                4:begin value=1536;multiple=5;end
                5:begin value=1024;multiple=6;end
                6:begin value=768;multiple=7;end
                7:begin value=512;multiple=8;end
                8:begin value=6144;multiple=2;end
                9:begin value=1536;multiple=4;end
                10:begin value=1024;multiple=6;end
                11:begin value=512;multiple=8;end
                12:begin value=2048;multiple=4;end
                13:begin value=512;multiple=8;end
                default:begin value=0;multiple=0;end
            endcase
            frequency_word={5'd0,increment}*multiple;
            amplitude=frequency_word>=37'h080000000 ? 16'sd0 : value;
        end
    endfunction
    wire [31:0] angles[0:3];
    wire signed [15:0] waves[0:3];
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin: oscillators
        assign angles[lane]=angle({group,2'b00}+lane);
        sine_rom sine(clk,angles[lane][31:22],waves[lane]);
    end endgenerate
    function signed [15:0] clipped;
        input signed [23:0] value;
        begin clipped=value>24'sd32767 ? 16'sh7fff : value< -24'sd32768 ? 16'sh8000 : value[15:0];end
    endfunction
    wire signed [23:0] chiff=age<16'd600 ?
        ($signed({{8{noise[22]}},noise[22:7]}) >>> 5) : 24'sd0;
    integer i;
    always @(posedge clk) begin
        if(!reset_n || !enable) begin
            state<=0;voice<=0;group<=0;gates<=0;previous_gate<=0;octave_frame<=0;previous_octave<=0;
            sample<=0;ready<=0;mix<=0;partial_sum<=0;level<=0;age<=0;p8<=0;p4<=0;p2<=0;increment<=0;
            envelope_product<=0;noise<=23'h65ab39;
            for(i=0;i<4;i=i+1) products[i]<=0;
            for(i=0;i<32;i=i+1) begin
                phase8[i]<={i[4:0],27'd0};phase4[i]<={i[3:0],28'h1900000};phase2[i]<={i[2:0],29'h13300000};
                levels[i]<=0;ages[i]<=0;
            end
        end else if(frame_tick) begin
            state<=1;voice<=0;gates<=gate;octave_frame<=octave;ready<=0;mix<=0;
        end else case(state)
            1:begin
                increment<=natural_increment(note);
                p8<=phase8[voice];p4<=phase4[voice];p2<=phase2[voice];
                if(gates[voice]) begin
                    level<=levels[voice]>16'd32735 ? 16'd32767 : levels[voice]+16'd32;
                    age<=!previous_gate[voice] ? 16'd0 : ages[voice]==65535 ? ages[voice] : ages[voice]+1'b1;
                end else begin level<=levels[voice]>16'd64 ? levels[voice]-16'd64 : 16'd0;age<=65535;end
                partial_sum<=0;group<=0;state<=2;
            end
            2:state<=3;
            3:begin
                for(i=0;i<4;i=i+1) products[i]<=waves[i]*amplitude({group,2'b00}+i);
                state<=4;
            end
            4:begin
                partial_sum<=partial_sum+(products[0]>>>15)+(products[1]>>>15)+(products[2]>>>15)+(products[3]>>>15);
                if(group==3) state<=5;else begin group<=group+1'b1;state<=2;end
            end
            5:begin
                envelope_product<=(partial_sum+chiff)*$signed({1'b0,level});
                phase8[voice]<=p8+increment;
                phase4[voice]<=p4+(increment<<1)+(increment>>8);
                phase2[voice]<=p2+(increment<<2)-(increment>>7);
                levels[voice]<=level;ages[voice]<=age;
                noise<={noise[21:0],noise[22]^noise[17]};state<=6;
            end
            6:begin
                mix<=mix+(envelope_product>>>19);
                if(voice==31) state<=7;else begin voice<=voice+1'b1;state<=1;end
            end
            7:begin sample<=clipped(mix);ready<=1;previous_gate<=gates;previous_octave<=octave_frame;state<=0;end
            default:state<=0;
        endcase
    end
endmodule
