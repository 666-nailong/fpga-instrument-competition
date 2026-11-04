`timescale 1ns/1ps
module tb_system32;
    reg clk=0,rst=0,rx=1,pc_rx=1;
    always #10 clk=~clk;
    wire bck,ws,din,hmi_tx;
    tri dp,dm;
    // Model the documented external 3.3V I2C pull-ups even with no ADC slave.
    tri1 ads_scl,ads_sda;
    top_j18_natural32_pressure_tjc #(.STARTUP_CYCLES(64),.KEY_PRESS_CYCLES(3),.KEY_RELEASE_CYCLES(3)) dut(
        .sys_clk(clk),.rst_n(rst),.key0_n(1'b1),.key1_n(1'b1),.pc_rx(pc_rx),.hmi_rx(rx),
        .usb2_dp(dp),.usb2_dm(dm),.ads_scl(ads_scl),.ads_sda(ads_sda),
        .i2s_bck(bck),.i2s_lrck(ws),.i2s_din(din),.hmi_tx(hmi_tx));
    defparam dut.audio_core.master_volume.gain.STEP_CYCLES=16;
    reg connected=0,strobe=0;
    reg [47:0] keys=0;
    reg nkro_enabled=0;
    reg [63:0] nkro_report=0;
    reg bitmap_report=0;
    wire [1:0] report_type=connected ? 2'd1 : 2'd0;
    wire [7:0] k0=keys[7:0],k1=keys[15:8],k2=keys[23:16],k3=keys[31:24],k4=keys[39:32],k5=keys[47:40];
    // Inject complete HID report outputs. Real decoder, CDC, screen UART,
    // production audio, resampler and serial DAC remain in the test path.
    initial begin
        force dut.typ=report_type;
        force dut.full_report=strobe;
        force dut.key0=k0;force dut.key1=k1;force dut.key2=k2;
        force dut.key3=k3;force dut.key4=k4;force dut.key5=k5;
        force dut.s3005_nkro=nkro_enabled;
        force dut.raw_report=nkro_report;
        force dut.report_length=4'd8;
        force dut.bitmap_report=bitmap_report;
    end
    task report(input[47:0] usages);
        begin
            @(negedge dut.usb_clk);keys=usages;strobe=1;
            @(negedge dut.usb_clk);strobe=0;
            repeat(32)@(negedge clk);
        end
    endtask
    task expect_notes(input[31:0] expected);
        begin if(dut.held!==expected)$fatal(1,"USB/CDC notes got=%h expected=%h",dut.held,expected);end
    endtask
    task byte_out(input[7:0] b,input pc);
        begin
            if(pc)pc_rx=0;else rx=0;#8680;
            for(integer i=0;i<8;i=i+1)begin if(pc)pc_rx=b[i];else rx=b[i];#8680;end
            if(pc)pc_rx=1;else rx=1;#9680;
        end
    endtask
    task packet(input[7:0] cmd,input[7:0] value);
        begin byte_out(8'ha5,0);byte_out(cmd,0);byte_out(value,0);byte_out(8'h5a,0);end
    endtask
    task chord(input[31:0] mask);
        begin byte_out(8'ha5,0);byte_out(8'h51,0);byte_out(mask[7:0],0);byte_out(mask[15:8],0);byte_out(mask[23:16],0);byte_out(mask[31:24],0);byte_out(8'h5a,0);end
    endtask
    task volume(input[7:0] level);
        // TJC `prints value,0` emits four little-endian bytes.
        begin
            byte_out(8'ha5,0);byte_out(8'h20,0);byte_out(level,0);
            byte_out(0,0);byte_out(0,0);byte_out(0,0);byte_out(8'h5a,0);
        end
    endtask
    task effect(input[7:0] id,input[7:0] strength);
    begin byte_out(8'ha5,0);byte_out(8'h60,0);byte_out(id,0);byte_out(strength,0);byte_out(8'h5a,0);end
    endtask
    integer decoded_words=0,active_frames[0:3],cycles=0;
    always @(negedge clk)if(dut.reset_n)begin
        if(dut.fault)$fatal(1,"Production audio fault");
        cycles=cycles+1;
    end
    integer bit_no=0;
    reg synced=0,last_ws=0;
    reg [15:0] value=0,expected_sample=0;
    always @(posedge bck)begin
        if(ws!=last_ws)begin
            if(synced && bit_no!=31)$fatal(1,"I2S slot width");
            synced=1;bit_no=0;last_ws=ws;expected_sample=ws ? dut.pcm_right : dut.pcm_left;
        end else if(synced)bit_no=bit_no+1;
        if(synced && bit_no>=1 && bit_no<=16)begin
            value={value[14:0],din};
            if(bit_no==16)begin
                if(value!==expected_sample)$fatal(1,"I2S sample mismatch");
                decoded_words=decoded_words+1;
                if(value!=0)active_frames[dut.timbre]=active_frames[dut.timbre]+1;
            end
        end
        if(synced && (bit_no==0 || bit_no>16) && din!==0)$fatal(1,"I2S padding/delay");
    end
    integer screen_commands=0,nn_commands=0,gain_commands=0,ff=0;
    integer parsed,feedback_phase=0,feedback_count=0;
    reg [15:0] feedback_low=0,feedback_high=0;
    reg [31:0] feedback_mask=0;
    reg [7:0] ch;
    reg [255:0] command=0;
    initial forever begin
        @(negedge hmi_tx);#13020;
        for(integer i=0;i<8;i=i+1)begin ch[i]=hmi_tx;#8680;end
        if(hmi_tx!==1)$fatal(1,"Screen UART framing");
        if(ch==8'hff)begin
            ff=ff+1;
            if(ff==3)begin
                screen_commands=screen_commands+1;
                if(command=="nn=00145")nn_commands=nn_commands+1;
                if(command=="wg=032")gain_commands=gain_commands+1;
                if($sscanf(command,"nn=%d",parsed)==1)begin
                    if(parsed<0 || parsed>65535)$fatal(1,"nn out of range");
                    feedback_low=parsed;feedback_phase=1;
                end else if($sscanf(command,"nu=%d",parsed)==1)begin
                    if(feedback_phase!=1 || parsed<0 || parsed>65535)$fatal(1,"nu order/range");
                    feedback_high=parsed;feedback_phase=2;
                end else if(command=="click m4,0" && feedback_phase==2)begin
                    feedback_mask={feedback_high,feedback_low};feedback_count=feedback_count+1;feedback_phase=0;
                end
                command=0;ff=0;
            end
        end else begin command={command[247:0],ch};ff=0;end
        #4340;
    end
    task expect_feedback(input[31:0] mask);
        integer previous_count;
        begin
            previous_count=feedback_count;
            wait(feedback_count>previous_count && feedback_mask==mask);
        end
    endtask
    reg [7:0] usages[0:31];
    task nkro(input[7:0] id,input[31:0] mask);
        reg[63:0] value;
        begin
            value=0;value[7:0]=id;
            for(integer i=0;i<32;i=i+1)if(mask[i])begin
                if(id==4 && usages[i]<48)value[16+usages[i]]=1;
                if(id==5 && usages[i]>=48 && usages[i]<104)value[8+usages[i]-48]=1;
            end
            @(negedge dut.usb_clk);nkro_report=value;bitmap_report=1;strobe=1;
            @(negedge dut.usb_clk);strobe=0;
            repeat(32)@(negedge clk);
        end
    endtask
    initial begin
        usages[0]=8'h04;usages[1]=8'h1a;usages[2]=8'h16;usages[3]=8'h08;
        usages[4]=8'h07;usages[5]=8'h09;usages[6]=8'h17;usages[7]=8'h0a;
        usages[8]=8'h1c;usages[9]=8'h0b;usages[10]=8'h18;usages[11]=8'h0d;
        usages[12]=8'h0e;usages[13]=8'h12;usages[14]=8'h0f;usages[15]=8'h13;
        usages[16]=8'h1d;usages[17]=8'h1b;usages[18]=8'h06;usages[19]=8'h19;
        usages[20]=8'h05;usages[21]=8'h11;usages[22]=8'h10;usages[23]=8'h36;
        usages[24]=8'h37;usages[25]=8'h38;usages[26]=8'h14;usages[27]=8'h15;
        usages[28]=8'h0c;usages[29]=8'h1e;usages[30]=8'h1f;usages[31]=8'h20;
        for(integer k=0;k<4;k=k+1)active_frames[k]=0;
        #200;rst=1;wait(dut.ready);
        repeat(32)@(negedge clk);expect_notes(0);
        connected=1;repeat(32)@(negedge clk);
        for(integer k=0;k<32;k=k+1)begin report({40'd0,usages[k]});expect_notes(32'd1<<k);end
        report({usages[31],usages[27],usages[20],usages[16],usages[5],usages[0]});expect_notes(32'h88110021);
        report(48'h090708161a04);expect_notes(16'h003f);
        report(48'h041a16080709);expect_notes(16'h003f);
        report(48'h000000010404);expect_notes(0);
        if(!dut.audio_state[32])$fatal(1,"Rollover invalid flag lost");
        report(0);expect_notes(0);
        if(dut.audio_state[32])$fatal(1,"Invalid flag failed to recover");
        report(48'h0000000a0704);expect_notes(16'h0091);
        for(integer k=0;k<4;k=k+1)begin
            packet(8'h10,k);repeat(256)@(posedge dut.source_tick);
            if(dut.timbre!==k || active_frames[k]==0)$fatal(1,"USB timbre %0d silent",k);
            expect_notes(16'h0091);
            $display("CHECK USB timbre %0d nonzero wire words=%0d at %0t",k,active_frames[k],$time);
        end
        chord(32'h80000004);expect_notes(32'h80000095);
        force dut.screen_link.page_delay=0;
        expect_feedback(32'h80000095);
        release dut.screen_link.page_delay;
        repeat(256)@(posedge dut.source_tick);
        chord(0);
        effect(0,200);effect(1,128);effect(2,180);
        if(dut.stereo_depth!==200 || dut.vibrato_depth!==128 || dut.reverb_depth!==180)$fatal(1,"effect independence");
        chord(32'hffffffff);expect_notes(32'hffffffff);
        for(integer k=0;k<4;k=k+1)begin packet(8'h10,k);chord(32'hffffffff);repeat(256)@(posedge dut.source_tick);end
        force dut.screen_link.page_delay=0;
        expect_feedback(32'hffffffff);
        release dut.screen_link.page_delay;
        effect(0,0);effect(1,0);effect(2,0);chord(0);
        // Mock only the ADC result boundary here; the I2C wire protocol has its own bench.
        force dut.pressure_error=1'b0;force dut.pressure_sample=16'd20000;
        @(negedge clk);force dut.pressure_valid=1'b1;
        @(negedge clk);force dut.pressure_valid=1'b0;
        chord(32'h80000000);
        @(posedge dut.tick_ms);repeat(40)@(negedge clk);
        chord(0);expect_notes(32'h0091);
        if(dut.sustained!==32'h80000091 || dut.pressure!==255)$fatal(1,"integrated pressure high-note retain: held=%h sustained=%h pressure=%d ready=%b retained=%h age=%d error=%b",dut.held,dut.sustained,dut.pressure,dut.sensor_ready,dut.sustain.retained,dut.sustain.age,dut.pressure_error);
        force dut.pressure_error=1'b1;repeat(3)@(negedge clk);
        if(dut.sustained!==32'h0091)$fatal(1,"NACK must release tail but preserve physical keys");
        release dut.pressure_error;release dut.pressure_sample;release dut.pressure_valid;
        $display("CHECK pressure ADC boundary: bit31 retained after release, NACK clears tail, physical keys bypass");
        chord(16'h0004);expect_notes(16'h0095);
        chord(0);expect_notes(16'h0091);
        // A PC note packet and gain packet must not affect this standalone input.
        byte_out(8'hf0,1);byte_out(5,1);byte_out(0,1);byte_out(0,1);byte_out(5,1);
        expect_notes(16'h0091);
        packet(8'h40,32);if(dut.hmi_gain!==32)$fatal(1,"Screen x32");
        // The unmodified sender's real 40ms page settling is separately covered
        // by tb_combined. Skip that pause here; UART remains actual 115200 baud.
        force dut.screen_link.page_delay=0;
        wait(nn_commands>0 && gain_commands>0);
        release dut.screen_link.page_delay;
        volume(0);wait(dut.volume_applied==0);
        // Drain the real 64-tap FIR history after the gain reaches zero.
        repeat(100)@(posedge dut.source_tick);
        if(dut.pcm_left!==0 || dut.pcm_right!==0)$fatal(1,"Screen mute failed");
        volume(255);wait(dut.volume_applied>250);
        chord(4);expect_notes(16'h0095);
        connected=0;repeat(64)@(negedge clk);expect_notes(0);
        if(dut.audio_state[33])$fatal(1,"Disconnect ready stuck");
        connected=1;report(0);expect_notes(0);
        report(48'h04);expect_notes(1);report(0);expect_notes(0);
        nkro_enabled=1;
        // Replay the observed Windows split: primary A/S/D/F/J/L, overflow K/P.
        bitmap_report=0;report(48'h160f0d090704);expect_notes(32'h00004835);
        nkro(4,32'h00009000);expect_notes(32'h0000d835);
        bitmap_report=0;report(0);expect_notes(32'h00009000);
        nkro(4,0);expect_notes(0);
        $display("CHECK observed physical split replay: primary6 plus supplemental2 produces8, independent primary release");
        bitmap_report=0;report(48'h090708161a04);expect_notes(32'h0000003f);
        nkro(4,32'hffffffff);nkro(5,32'hffffffff);expect_notes(32'hffffffff);
        force dut.screen_link.page_delay=0;
        expect_feedback(32'hffffffff);
        release dut.screen_link.page_delay;
        repeat(256)@(posedge dut.source_tick);
        nkro(4,0);expect_notes(32'h0380003f);
        nkro(5,0);expect_notes(32'h0000003f);
        bitmap_report=0;report(0);expect_notes(0);
        connected=0;repeat(64)@(negedge clk);expect_notes(0);
        connected=1;nkro(4,1);expect_notes(1);nkro(4,0);expect_notes(0);
        $display("CHECK NKRO32 complete-report boundary: all32 USB notes through real decoder/CDC/audio/UART, independent bank releases and reconnect");
        if(decoded_words<500 || screen_commands==0)$fatal(1,"Insufficient actual wire coverage");
        $display("PASS J18 functional HID report boundary: 32 mappings, mixed high six-key mask, six-key permutation, rollover/recovery, release/unplug/replug; real decoder/50-60MHz CDC; PC note input ignored; screen timbre/LE32 volume/x32/touch union, actual115200 UART nn/nu/click high/all32 feedback checked (page-settle pause bypassed) commands=%0d feedback=%0d nn=%0d wg32=%0d; pressure ADC boundary high-bit retain/NACK/physical bypass; four timbres nonzero=%0d/%0d/%0d/%0d; I2S words=%0d; cycles=%0d",screen_commands,feedback_count,nn_commands,gain_commands,active_frames[0],active_frames[1],active_frames[2],active_frames[3],decoded_words,cycles);
        $finish;
    end
    initial begin #300000000;$fatal(1,"J18 watchdog: notes=%h mode=%0d nn=%0d wg32=%0d commands=%0d volume=%0d",dut.held,dut.timbre,nn_commands,gain_commands,screen_commands,dut.volume_applied);end
endmodule
