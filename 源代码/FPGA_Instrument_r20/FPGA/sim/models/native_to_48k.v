// 64-tap / 1024-phase Q15 FIR; single 50MHz domain, 192 clocks per output.
// 128 history slots prevent concurrent input writes overwriting a convolution.
module native_to_48k(
    input wire clk,reset_n,source_tick,output_tick,
    input wire signed [15:0] left_in,right_in,
    output reg signed [15:0] left_out,right_out,
    output reg valid,overrun
);
    reg signed [15:0] coeff [0:32767];
    reg signed [15:0] zero_coeff [0:63];
    initial begin
        $readmemh("resample_coeff.mem",coeff);
        $readmemh("resample_zero.mem",zero_coeff);
    end
    reg signed [15:0] history_left [0:127],history_right [0:127];
    reg [6:0] write_ptr,head;
    reg [7:0] history_count,captured_count;
    reg [9:0] age;
    reg [1:0] state;
    reg [5:0] tap;
    reg [8:0] phase_index;
    reg reverse_phase,zero_phase;
    wire [5:0] coeff_tap=reverse_phase ? 6'd63-tap : tap;
    wire [14:0] coeff_addr={phase_index,coeff_tap};
    wire [6:0] history_addr=head-{1'b0,tap};
    reg signed [15:0] data_left,data_right,coefficient;
    reg signed [31:0] product_left,product_right;
    reg signed [47:0] sum_left,sum_right;
    wire signed [47:0] final_left=sum_left+{{16{product_left[31]}},product_left};
    wire signed [47:0] final_right=sum_right+{{16{product_right[31]}},product_right};
    function [15:0] quantize;
        input signed [47:0] value;
        reg signed [47:0] rounded;
        begin
            rounded=value<0 ? -(((-value)+48'sd16384)>>>15) : (value+48'sd16384)>>>15;
            quantize=rounded>48'sd32767 ? 16'h7fff : rounded< -48'sd32768 ? 16'h8000 : rounded[15:0];
        end
    endfunction
    always @(posedge clk) begin
        if(source_tick && reset_n) begin
            history_left[write_ptr]<=left_in;history_right[write_ptr]<=right_in;
        end
        if(!reset_n) begin
            write_ptr<=0;head<=0;history_count<=0;captured_count<=0;age<=0;
            state<=0;tap<=0;phase_index<=0;reverse_phase<=0;zero_phase<=0;
            data_left<=0;data_right<=0;coefficient<=0;product_left<=0;product_right<=0;
            sum_left<=0;sum_right<=0;left_out<=0;right_out<=0;valid<=0;overrun<=0;
        end else begin
            if(source_tick) begin
                write_ptr<=write_ptr+1'b1;age<=0;
                if(history_count<8'd128) history_count<=history_count+1'b1;
            end else if(age!=10'd1023) age<=age+1'b1;
            if(output_tick && state!=0) overrun<=1;
            case(state)
                0: if(output_tick) begin
                    head<=source_tick ? write_ptr : write_ptr-1'b1;
                    captured_count<=source_tick && history_count<128 ? history_count+1'b1 : history_count;
                    zero_phase<=source_tick || age==0;
                    reverse_phase<=!source_tick && age>512;
                    phase_index<=age<=512 ? age[8:0]-1'b1 : 10'd1023-age;
                    tap<=0;sum_left<=0;sum_right<=0;state<=1;
                end
                1: begin
                    data_left<=tap<captured_count ? history_left[history_addr] : 16'sd0;
                    data_right<=tap<captured_count ? history_right[history_addr] : 16'sd0;
                    coefficient<=zero_phase ? zero_coeff[tap] : coeff[coeff_addr];
                    state<=2;
                end
                2: begin
                    product_left<=data_left*coefficient;product_right<=data_right*coefficient;state<=3;
                end
                3: begin
                    sum_left<=final_left;sum_right<=final_right;
                    if(tap==63) begin
                        left_out<=quantize(final_left);right_out<=quantize(final_right);valid<=1;state<=0;
                    end else begin tap<=tap+1'b1;state<=1;end
                end
            endcase
        end
    end
endmodule
