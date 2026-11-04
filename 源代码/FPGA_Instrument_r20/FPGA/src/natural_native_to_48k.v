// 64-tap / 1024-phase Q15 FIR; lossless coefficient decoder, 321 clocks/output.
// 128 history slots prevent concurrent input writes overwriting a convolution.
module natural_native_to_48k(
    input wire clk,reset_n,source_tick,output_tick,
    input wire signed [15:0] left_in,right_in,
    output reg signed [15:0] left_out,right_out,
    output reg valid,overrun
);
    reg signed [15:0] zero_coeff [0:63] /* synthesis syn_romstyle="logic" */;
    initial begin
        $readmemh("resample_zero.mem",zero_coeff);
    end
    reg [31:0] history [0:127] /* synthesis syn_ramstyle="block_ram" */;
    reg [31:0] history_q;
    reg [6:0] write_ptr,head;
    reg [7:0] history_count,captured_count;
    reg [9:0] age;
    reg [2:0] state;
    reg [5:0] tap;
    reg [8:0] phase_index;
    reg reverse_phase,zero_phase;
    wire [5:0] coeff_tap=reverse_phase ? 6'd63-tap : tap;
    wire [14:0] coeff_addr={phase_index,coeff_tap};
    wire [6:0] history_addr=head-{1'b0,tap};
    // Keep the original state-1 read edge. State 5 consumes its registered
    // result during the existing coefficient wait, without adding a cycle.
    // With 128 slots and a 321-clock convolution, the 1024-clock input
    // cadence cannot overwrite a captured frame's newest 64 history words.
    always @(posedge clk) begin
        if(source_tick && reset_n) history[write_ptr]<={left_in,right_in};
        if(state==1) history_q<=history[history_addr];
    end
    reg signed [15:0] data_left,data_right,coefficient;
    wire signed [15:0] decoded_coefficient;
    wire signed [15:0] selected_coefficient=zero_phase ? coefficient : decoded_coefficient;
    resample_coefficient_decoder coefficient_rom(clk,state==1,coeff_addr,decoded_coefficient);
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
                    tap<=0;sum_left<=0;sum_right<=0;state<=4;
                end
                // phase_index changes only in state 0. The first ROM capture is
                // two clocks later; all following taps reuse this stable phase.
                4: state<=1;
                1: begin
                    coefficient<=zero_coeff[tap];state<=5;
                end
                5: begin
                    data_left<=tap<captured_count ? $signed(history_q[31:16]) : 16'sd0;
                    data_right<=tap<captured_count ? $signed(history_q[15:0]) : 16'sd0;
                    state<=6;
                end
                6: state<=2;
                2: begin
                    product_left<=data_left*selected_coefficient;product_right<=data_right*selected_coefficient;state<=3;
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
