// Standalone J18 USB keyboard plus duplex r11 TJC; procedural audio only.
module top_j18_natural32_pressure_tjc #(
    parameter integer STARTUP_CYCLES = 5000000,
    parameter integer KEY_PRESS_CYCLES = 50000,
    parameter integer KEY_RELEASE_CYCLES = 150000,
    parameter integer PACKED_BOWED_MASK = 1,
    parameter integer HMI_RESYNC_CYCLES = 250000000
)(
    input wire sys_clk, rst_n, key0_n, key1_n, pc_rx, hmi_rx,
    inout wire usb2_dp, usb2_dm,ads_scl,ads_sda,
    output wire pc_tx, hp_bck, hp_ws, hp_din, pa_en, hmi_tx, i2s_bck, i2s_lrck, i2s_din
);
    wire usb_clk,pll_lock;
    usb_pll_50_to_60 usb_clock(.clkin(sys_clk),.clkout(usb_clk),.lock(pll_lock));
    wire common_reset_n=rst_n && pll_lock;
    reg [2:0] usb_reset_pipe=0,audio_reset_pipe=0;
    always @(posedge usb_clk or negedge common_reset_n)
        if(!common_reset_n) usb_reset_pipe<=0;
        else usb_reset_pipe<={usb_reset_pipe[1:0],1'b1};
    always @(posedge sys_clk or negedge common_reset_n)
        if(!common_reset_n) audio_reset_pipe<=0;
        else audio_reset_pipe<={audio_reset_pipe[1:0],1'b1};
    wire usb_reset_n=usb_reset_pipe[2],reset_n=audio_reset_pipe[2];
    wire usb_dp_o,usb_dm_o,usb_oe;
    assign usb2_dp=usb_oe ? usb_dp_o : 1'bz;
    assign usb2_dm=usb_oe ? usb_dm_o : 1'bz;
    wire [1:0] typ;
    wire full_report,connerr;
    wire s3005_nkro;
    wire bitmap_report;
    wire [3:0] report_length;
    wire [63:0] raw_report;
    wire [7:0] key0,key1,key2,key3,key4,key5;
    wire [9:0] rom_addr;
    wire [3:0] rom_dout;
    wire rom_en;
    usb_hid_host #(.FULL_SPEED(1),.MOUSE_SUPPORT(0),.GAME_SUPPORT(0)) host(
        .clk(usb_clk),.reset(!usb_reset_n),.cs(1'b1),
        .usb_dp_i(usb2_dp),.usb_dm_i(usb2_dm),.usb_dp_o(usb_dp_o),.usb_dm_o(usb_dm_o),.usb_oe(usb_oe),
        .typ(typ),.full_report(full_report),.connerr(connerr),
        .s3005_nkro(s3005_nkro),.keyboard_report_length(report_length),.dbg_hid_report(raw_report),
        .keyboard_bitmap_report(bitmap_report),
        .key_0(key0),.key_1(key1),.key_2(key2),.key_3(key3),.key_4(key4),.key_5(key5),
        .rom_addr(rom_addr),.rom_dout(rom_dout),.rom_en(rom_en));
    usb_hid_host_rom host_rom(.clk(usb_clk),.addr(rom_addr),.dout(rom_dout),.en(rom_en),.s3005_nkro(s3005_nkro));
    wire [31:0] notes_usb;
    wire invalid_usb;
    usb_note_decoder32 decoder(.clk(usb_clk),.reset_n(usb_reset_n),
        .keyboard_ready(typ==2'd1),.report_strobe(full_report),
        .keys({key5,key4,key3,key2,key1,key0}),.notes(notes_usb),.invalid_report(invalid_usb),
        .s3005_nkro(s3005_nkro),.report_data(raw_report),.report_length(report_length),.bitmap_report(bitmap_report));
    wire [33:0] audio_state;
    note_state_cdc32 state_bridge(.src_clk(usb_clk),.src_reset_n(usb_reset_n),
        .src_state({typ==2'd1,invalid_usb,notes_usb}),.dst_clk(sys_clk),.dst_reset_n(reset_n),.dst_state(audio_state));
    wire [31:0] held,normal_held,usb_held,sustained,retrigger;
    wire test_active,test_timbre_valid;
    wire [31:0] test_mask;
    wire [1:0] test_timbre;
    wire [2:0] test_stage;
    wire [1:0] test_buttons;
    key_capture2 #(.PRESS_CYCLES(KEY_PRESS_CYCLES),.RELEASE_CYCLES(KEY_RELEASE_CYCLES)) test_keys(
      .clk(sys_clk),.reset_n(reset_n),.key_n({key1_n,key0_n}),.held(test_buttons));
    reg was_connected;
    always @(posedge sys_clk)if(!reset_n)was_connected<=0;else was_connected<=audio_state[33];
    wire disconnected=was_connected && !audio_state[33];
    wire screen_note_valid;wire[5:0] screen_note;
    wire screen_mask_valid;wire[31:0] screen_mask;
    wire merged_snapshot_valid;
    wire snapshot_valid;
    wire ready, fault, active, source_ready, source_fault, source_tick;
    wire converted_valid,converted_overrun,codec_tick,serial_underrun;
    wire [15:0] native_left,native_right,converted_left,converted_right;
    reg underrun_seen;
    always @(posedge sys_clk)
        if(!reset_n) underrun_seen<=0;
        else if(serial_underrun) underrun_seen<=1;
    assign fault=source_fault || converted_overrun || underrun_seen;
    assign ready=source_ready && converted_valid;
    assign pa_en=!reset_n || !ready || fault;
    wire [1:0] timbre, controls;
    // DEBUG-USB2 UART is telemetry only; it never supplies notes or controls.
    wire [8:0] volume_target,volume_applied,screen_volume;
    wire screen_volume_valid,screen_timbre_valid,resync_request;
    wire [1:0] screen_timbre;
    wire [6:0] screen_gain,hmi_gain;
    wire [7:0] stereo_depth,vibrato_depth,reverb_depth;
    wire hmi_gain_valid;
    wire screen_gain_valid;
    tjc_hmi_rx32 screen_input(.clk(sys_clk),.reset_n(reset_n),.rx(hmi_rx),
        .stereo_depth(stereo_depth),.vibrato_depth(vibrato_depth),.reverb_depth(reverb_depth),
        .timbre_valid(screen_timbre_valid),.timbre_value(screen_timbre),
        .volume_valid(screen_volume_valid),.volume_value(screen_volume),
        .gain_valid(screen_gain_valid),.gain_value(screen_gain),.resync_request(resync_request),.note_valid(screen_note_valid),.note_value(screen_note),.mask_valid(screen_mask_valid),.mask_value(screen_mask));
    tjc_control_merge merge(.clk(sys_clk),.reset_n(reset_n),
        .pc_volume_valid(1'b0),.pc_volume(9'd256),
        .screen_volume_valid(screen_volume_valid),.screen_volume(screen_volume),
        .pc_gain_valid(1'b0),.pc_gain(7'd32),
        .screen_gain_valid(screen_gain_valid),.screen_gain(screen_gain),
        .volume(volume_target),.gain(hmi_gain),.gain_valid(hmi_gain_valid));
    wire [1023:0] hmi_wave_history;
    assign usb_held=audio_state[33] && !audio_state[32] ? audio_state[31:0] : 32'd0;
    reg [31:0] previous_usb_notes;
    always @(posedge sys_clk) if(!reset_n)previous_usb_notes<=0;else previous_usb_notes<=usb_held;
    assign snapshot_valid=usb_held!=previous_usb_notes;
    touch_note_merge32 notes_merge(.clk(sys_clk),.reset_n(reset_n),.pc_held(usb_held),
        .note_valid(screen_note_valid),.note_value(screen_note),.mask_valid(screen_mask_valid),.mask_value(screen_mask),
        .clear_screen(resync_request || screen_timbre_valid || disconnected || audio_state[32]),.held(normal_held),.changed(merged_snapshot_valid));
    assign held=test_active ? test_mask : normal_held;
    wire [15:0] pcm_right, pcm_left;
    reg[15:0] ms_count;
    wire tick_ms=ms_count==49999;
    always @(posedge sys_clk)if(!reset_n || tick_ms)ms_count<=0;else ms_count<=ms_count+1'b1;
    polyphony_selftest32 selftest(.clk(sys_clk),.reset_n(reset_n),.tick_ms(tick_ms),
      .ready(ready),.fault(fault),.buttons(test_buttons),.current_timbre(timbre),
      .active(test_active),.timbre_valid(test_timbre_valid),.test_timbre(test_timbre),.mask(test_mask),.stage(test_stage));
    wire[15:0] pressure_sample;wire pressure_valid,pressure_error,sensor_ready;
    wire[7:0] pressure;
    reg[5:0] pressure_sequence;
    always @(posedge sys_clk)if(!reset_n)pressure_sequence<=0;else if(pressure_valid)pressure_sequence<=pressure_sequence+1'b1;
    wire[31:0] pedal_status={pressure_sequence,pressure_error,sensor_ready,pressure,pressure_sample};
    ads1115_reader adc(.clk(sys_clk),.reset_n(reset_n),.scl(ads_scl),.sda(ads_sda),
      .sample(pressure_sample),.valid(pressure_valid),.ack_error(pressure_error));
    pressure_sustain32 sustain(.clk(sys_clk),.reset_n(reset_n),.tick_ms(tick_ms),
      .clear(test_active || screen_timbre_valid || disconnected || audio_state[32]),.held(held),.adc_sample(pressure_sample),
      .adc_valid(pressure_valid),.adc_error(pressure_error),.sustained(sustained),.pressure(pressure),.sensor_ready(sensor_ready));
    reg[31:0] held_previous,pending_onset;
    always @(posedge sys_clk)begin
    if(!reset_n)begin held_previous<=0;pending_onset<=0;end
    else begin held_previous<=held;
    pending_onset<=(source_tick ? 32'd0 : pending_onset)|(held & ~held_previous);
    end end
    assign retrigger=pending_onset;

    // Same real-time synthesis core for normal playing and the 32-note test input.
    natural_pcm_source #(.PACKED_BOWED_MASK(PACKED_BOWED_MASK),
        .STARTUP_CYCLES(STARTUP_CYCLES),.KEY_PRESS_CYCLES(KEY_PRESS_CYCLES),
        .KEY_RELEASE_CYCLES(KEY_RELEASE_CYCLES)) audio_core(
        .clk(sys_clk),.reset_n(reset_n),.key0_n(test_active ? 1'b1 : key0_n),.key1_n(test_active ? 1'b1 : key1_n),
        .keyboard_state({2'b10,test_active ? test_mask : sustained}),.retrigger(retrigger),
        .diagnostic_tones(test_active && test_stage==4),
        .stereo_depth(test_active ? 8'd0 : stereo_depth),.vibrato_depth(test_active ? 8'd0 : vibrato_depth),.reverb_depth(test_active ? 8'd0 : reverb_depth),.bck(),.ws(),.din(),.pa_en(),
        .ready(source_ready),.underrun_seen(source_fault),.amp_active(active),.timbre(timbre),
        .controls(controls),.tx_pcm(native_right),.tx_pcm_left(native_left),.source_tick(source_tick),
        .remote_timbre_valid(test_timbre_valid || (!test_active && screen_timbre_valid)),.remote_timbre(test_timbre_valid ? test_timbre : screen_timbre),
        .volume_target(test_active ? 9'd128 : volume_target),.volume_applied(volume_applied));
    natural_native_to_48k converter(.clk(sys_clk),.reset_n(reset_n),.source_tick(source_tick),
        .output_tick(codec_tick),.left_in(native_left),.right_in(native_right),
        .left_out(converted_left),.right_out(converted_right),.valid(converted_valid),.overrun(converted_overrun));
    pcm5102_i2s codec(.clk(sys_clk),.reset_n(reset_n),.enable(ready && !fault),.pcm_valid(converted_valid),
        .pcm_left(converted_left),.pcm_right(converted_right),.bck(i2s_bck),.lrck(i2s_lrck),.din(i2s_din),
        .hp_bck(hp_bck),.hp_ws(hp_ws),.hp_din(hp_din),.frame_tick(codec_tick),.underrun(serial_underrun),
        .sample_left(pcm_left),.sample_right(pcm_right));
    keyboard_status_uart #(.NOTE_ECHO(1),.SOURCE_ID(2),.VOLUME_CONTROL(1)) display_link(
        .clk(sys_clk),.reset_n(reset_n),.rx(pc_rx),.tx(pc_tx),.held(held[15:0]),.held_full(held),.pedal_status(pedal_status),.timbre(timbre),
        .audio_ready(ready),.audio_fault(fault),.octave(controls[1]),.keyboard_ready(audio_state[33]),.invalid_report(audio_state[32]),
        .pcm_left(pa_en ? 16'd0 : pcm_left),.pcm_right(pa_en ? 16'd0 : pcm_right),.note_snapshot(snapshot_valid || merged_snapshot_valid),
        .volume_target(volume_target),.volume_applied(volume_applied),.hmi_wave_history(hmi_wave_history));
    // Duplex screen: RX must use an external 5V-to-3.3V divider.
    tjc_hmi_uart_tx32 #(.RESYNC_CYCLES(HMI_RESYNC_CYCLES)) screen_link(
        .clk(sys_clk),.reset_n(reset_n),.tx(hmi_tx),.resync_request(resync_request),
        .pcm_left(pa_en ? 16'd0 : pcm_left),.pcm_right(pa_en ? 16'd0 : pcm_right),
        .timbre(timbre),.notes(held),.volume_target(volume_target),.volume_applied(volume_applied),
        .wave_history(hmi_wave_history),.wave_gain(hmi_gain),.wave_gain_valid(hmi_gain_valid));
endmodule
