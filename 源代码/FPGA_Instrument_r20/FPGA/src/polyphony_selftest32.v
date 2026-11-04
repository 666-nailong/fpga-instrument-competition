// Hold both debounced board keys for 2s. One bounded run, rearm after release.
module polyphony_selftest32 #(
    parameter integer HOLD_MS=2000, SOUND_MS=2000, GAP_MS=1000
)(
    input wire clk,reset_n,tick_ms,ready,fault,
    input wire [1:0] buttons,current_timbre,
    output reg active,timbre_valid,
    output reg [1:0] test_timbre,
    output wire [31:0] mask,
    output reg [2:0] stage
);
    reg armed;
    reg [15:0] hold_ms,elapsed;
    reg [1:0] saved_timbre;
    assign mask=active && elapsed<SOUND_MS ? 32'hffffffff : 32'd0;
    always @(posedge clk) begin
        if(!reset_n) begin
            active<=0;timbre_valid<=0;test_timbre<=0;stage<=0;
            armed<=1;hold_ms<=0;elapsed<=0;saved_timbre<=0;
        end else begin
            timbre_valid<=0;
            if(buttons!=3) armed<=1;
            if(active) begin
                if(fault || !ready || (tick_ms && elapsed==SOUND_MS+GAP_MS-1 && stage==4)) begin
                    active<=0;test_timbre<=saved_timbre;timbre_valid<=1;hold_ms<=0;
                end else if(tick_ms) begin
                    if(elapsed==SOUND_MS+GAP_MS-1) begin
                        elapsed<=0;stage<=stage+1'b1;
                        test_timbre<=stage==3 ? 2'd0 : stage[1:0]+1'b1;timbre_valid<=1;
                    end else elapsed<=elapsed+1'b1;
                end
            end else if(buttons!=3 || !ready || fault || !armed) hold_ms<=0;
            else if(tick_ms) begin
                if(hold_ms==HOLD_MS-1) begin
                    active<=1;armed<=0;hold_ms<=0;elapsed<=0;stage<=0;
                    saved_timbre<=current_timbre;test_timbre<=0;timbre_valid<=1;
                end else hold_ms<=hold_ms+1'b1;
            end
        end
    end
endmodule
