// Baseline source update: first request at clock 8, then every 1024 clocks.
// Continuous scheduling avoids stopping the codec clock during release or mute.
module native_source_stream #(parameter integer STARTUP_CYCLES=5000000)(
    input wire clk,reset_n,
    input wire signed [15:0] pcm,pcm_left,
    input wire pcm_valid,
    output reg frame_tick,underrun,ready,
    output reg [15:0] sample,sample_left
);
    reg [22:0] startup_count;
    reg [9:0] phase;
    reg started;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            startup_count<=0;ready<=0;phase<=0;started<=0;
            frame_tick<=0;underrun<=0;sample<=0;sample_left<=0;
        end else begin
            phase<=phase+1'b1;frame_tick<=0;underrun<=0;
            if(!ready) begin
                if(startup_count==STARTUP_CYCLES-1) ready<=1;
                else startup_count<=startup_count+1'b1;
            end
            if(phase==10'd7) begin
                frame_tick<=1;
                sample<=ready && pcm_valid ? pcm : 16'd0;
                sample_left<=ready && pcm_valid ? pcm_left : 16'd0;
                underrun<=ready && started && !pcm_valid;
                started<=1;
            end
        end
    end
endmodule
