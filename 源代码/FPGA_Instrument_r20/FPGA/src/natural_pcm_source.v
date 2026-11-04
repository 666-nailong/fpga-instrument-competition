// Four procedural timbres; no recorded-note decoder or sample asset is compiled.
module natural_pcm_source #(
    parameter integer STARTUP_CYCLES=5000000,
    parameter integer KEY_PRESS_CYCLES=50000,
    parameter integer KEY_RELEASE_CYCLES=150000,
    parameter integer PACKED_BOWED_MASK=1
)(
    input wire clk,reset_n,key0_n,key1_n,
    input wire [33:0] keyboard_state,
    input wire [31:0] retrigger,
    input wire diagnostic_tones,
    input wire [7:0] stereo_depth,vibrato_depth,reverb_depth,
    output wire bck,ws,din,pa_en,ready,
    output reg underrun_seen,
    output reg amp_active,
    output reg [1:0] timbre,
    output wire [1:0] controls,
    output wire [15:0] tx_pcm,tx_pcm_left,
    output wire source_tick,
    input wire remote_timbre_valid,
    input wire [1:0] remote_timbre,
    input wire [8:0] volume_target,
    output wire [8:0] volume_applied
);
    wire frame_tick,voice_valid,underrun,pcm_valid,fx_overrun,piano_overrun;
    wire can_play=keyboard_state[33] && !keyboard_state[32];
    wire [31:0] held=can_play ? keyboard_state[31:0] : 32'd0;
    reg control0_d;
    key_capture2 #(.PRESS_CYCLES(KEY_PRESS_CYCLES),.RELEASE_CYCLES(KEY_RELEASE_CYCLES)) buttons(
        .clk(clk),.reset_n(reset_n),.key_n({key1_n,key0_n}),.held(controls));
    always @(posedge clk) begin
        if(!reset_n) begin timbre<=0;control0_d<=0;underrun_seen<=0;amp_active<=0;end
        else begin
            control0_d<=controls[0];
            if(remote_timbre_valid) timbre<=remote_timbre;
            else if(controls[0] && !control0_d) timbre<=timbre+1'b1;
            if(underrun || fx_overrun || piano_overrun) underrun_seen<=1;
            amp_active<=ready && !underrun_seen;
        end
    end
    wire signed [15:0] base_left,base_right,pcm_left,pcm_right;
    wire base_valid=voice_valid;
    wire natural_organ_tail;
    voice_engine_32 #(.PIANO_PROFILE(1),.NEAR_NOTE_SOFTEN(0),.BOWED_STRINGS(1),
        .PACKED_BOWED_MASK(PACKED_BOWED_MASK),.QUARTER_BOWED_SINE(1),.STRING_SAMPLE(0),.PAN_STRINGS(1),.PAN_RIGHT(0)) voices(
        .clk(clk),.reset_n(reset_n),.frame_tick(frame_tick),.gate(held),
        .timbre(timbre),.octave(controls[1]),.expression(8'd255),.next_pcm(base_left),
        .ready(voice_valid),.retrigger(retrigger),.pitch_offset(16'sd0),.diagnostic_tones(diagnostic_tones));
    assign base_right=base_left;
    wire signed [15:0] pipe_dry,guitar_dry,natural_organ_left,natural_organ_right,natural_guitar;
    wire pipe_ready,guitar_ready,room_valid,body_valid;
    reg pipe_ready_d,guitar_ready_d,organ_complete,guitar_complete;
    reg [1:0] render_timbre;
    reg render_diagnostic;
    wire signed[15:0] piano_dry,piano_left,piano_right;
    wire piano_ready,piano_valid;
    reg piano_ready_d,piano_complete;
    modal_piano32 piano(.clk(clk),.reset_n(reset_n),.frame_tick(frame_tick),.octave(controls[1]),
      .gate(timbre==0 && !diagnostic_tones && can_play ? held : 32'd0),.retrigger(retrigger),
      .sample(piano_dry),.ready(piano_ready),.overrun(piano_overrun));
    piano_space piano_room(.clk(clk),.reset_n(reset_n),.sample_valid(piano_ready && !piano_ready_d),
      .enable(render_timbre==0 && !render_diagnostic),.sample_in(piano_dry),
      .left(piano_left),.right(piano_right),.valid(piano_valid));
    pipe_organ pipes(clk,reset_n,frame_tick,1'b1,controls[1],
        timbre==2 ? held : 32'd0,pipe_dry,pipe_ready);
    plucked_guitar string_model(clk,reset_n,frame_tick,1'b1,controls[1],
        timbre==3 ? held : 32'd0,guitar_dry,guitar_ready);
    organ_room cathedral(clk,reset_n,pipe_ready && !pipe_ready_d,render_timbre==2,
        pipe_dry,natural_organ_left,natural_organ_right,room_valid,natural_organ_tail);
    guitar_body soundboard(clk,reset_n,guitar_ready && !guitar_ready_d,render_timbre==3,
        guitar_dry,natural_guitar,body_valid);
    always @(posedge clk) begin
        if(!reset_n) begin
            pipe_ready_d<=0;guitar_ready_d<=0;organ_complete<=0;guitar_complete<=0;render_timbre<=0;
            piano_ready_d<=0;piano_complete<=0;render_diagnostic<=0;
        end else begin
            pipe_ready_d<=pipe_ready;guitar_ready_d<=guitar_ready;
            piano_ready_d<=piano_ready;
            if(frame_tick) begin organ_complete<=0;guitar_complete<=0;piano_complete<=0;render_timbre<=timbre;render_diagnostic<=diagnostic_tones;end
            else begin
                if(room_valid) organ_complete<=1;
                if(body_valid) guitar_complete<=1;
                if(piano_valid)piano_complete<=1;
            end
        end
    end
    assign pcm_left=render_timbre==0 && !render_diagnostic ? piano_left : render_timbre==2 ? natural_organ_left : render_timbre==3 ? natural_guitar : base_left;
    assign pcm_right=render_timbre==0 && !render_diagnostic ? piano_right : render_timbre==2 ? natural_organ_right : render_timbre==3 ? natural_guitar : base_right;
    assign pcm_valid=render_timbre==0 && !render_diagnostic ? piano_complete : render_timbre==2 ? organ_complete : render_timbre==3 ? guitar_complete : base_valid;
    reg fx_started;
    always @(posedge clk)if(!reset_n || frame_tick)fx_started<=0;else if(pcm_valid)fx_started<=1;
    wire signed [15:0] fx_left,fx_right;
    wire fx_valid;
    audio_fx32 effects(.clk(clk),.reset_n(reset_n),.start(pcm_valid && !fx_started),
      .left_in(pcm_left),.right_in(pcm_right),.stereo_depth(stereo_depth),.vibrato_depth(vibrato_depth),.reverb_depth(reverb_depth),
      .left_out(fx_left),.right_out(fx_right),.ready(fx_valid),.overrun(fx_overrun));
    wire signed [15:0] output_right,output_left;
    wire output_valid;
    generate begin: master_volume
        audio_master_volume gain(.clk(clk),.reset_n(reset_n),.target(volume_target),
            .pcm_left(can_play && !underrun_seen ? fx_left : 16'sd0),
            .pcm_right(can_play && !underrun_seen ? fx_right : 16'sd0),.pcm_valid(fx_valid),
            .left(output_left),.right(output_right),.valid(output_valid),.applied(volume_applied));
    end endgenerate
    native_source_stream #(.STARTUP_CYCLES(STARTUP_CYCLES)) audio(
        .clk(clk),.reset_n(reset_n),.pcm(output_right),.pcm_left(output_left),.pcm_valid(output_valid),
        .frame_tick(frame_tick),.underrun(underrun),.ready(ready),.sample(tx_pcm),.sample_left(tx_pcm_left));
    assign source_tick=frame_tick;
    assign bck=0;assign ws=0;assign din=0;
    assign pa_en=!ready || underrun_seen || !amp_active;
endmodule

// Q8 attenuation only, unity=256. Independent ramp keeps moving even while audio is paused.
module audio_master_volume #(parameter integer STEP_CYCLES=4096)(
    input wire clk,reset_n,
    input wire [8:0] target,
    input wire signed [15:0] pcm_left,pcm_right,
    input wire pcm_valid,
    output reg signed [15:0] left,right,
    output reg valid,
    output reg [8:0] applied
);
    localparam integer TIMER_BITS=STEP_CYCLES>1 ? $clog2(STEP_CYCLES) : 1;
    reg [TIMER_BITS-1:0] timer;
    wire signed [9:0] gain={1'b0,applied};
    reg signed [25:0] product_left,product_right;
    function [15:0] truncate_gain;
        input signed [25:0] value;
        reg signed [25:0] scaled;
        begin
            scaled=value<0 ? -((-value)>>>8) : value>>>8;
            truncate_gain=scaled[15:0];
        end
    endfunction
    // Register the multiplies before rounding, avoiding a long path into the serial sender.
    reg product_valid;
    always @(posedge clk) begin
        if(!reset_n) begin
            timer<=0;applied<=9'd256;product_left<=0;product_right<=0;
            product_valid<=0;left<=0;right<=0;valid<=0;
        end else begin
            if(timer==STEP_CYCLES-1) begin
                timer<=0;
                if(applied<target) applied<=applied+1'b1;
                else if(applied>target) applied<=applied-1'b1;
            end else timer<=timer+1'b1;
            product_left<=pcm_left*gain;product_right<=pcm_right*gain;product_valid<=pcm_valid;
            left<=truncate_gain(product_left);right<=truncate_gain(product_right);valid<=product_valid;
        end
    end
endmodule
