`timescale 1ns/1ps
module tb_polyphony32;
    reg clk=0,rst=0,k0=1,k1=1;
    always #10 clk=~clk;
    tri dp,dm;
    tri1 scl,sda;
    wire bck,ws,din;
    top_j18_natural32_pressure_tjc #(.STARTUP_CYCLES(64),.KEY_PRESS_CYCLES(3),.KEY_RELEASE_CYCLES(3)) dut(
      .sys_clk(clk),.rst_n(rst),.key0_n(k0),.key1_n(k1),.pc_rx(1'b1),.hmi_rx(1'b1),
      .usb2_dp(dp),.usb2_dm(dm),.ads_scl(scl),.ads_sda(sda),.i2s_bck(bck),.i2s_lrck(ws),.i2s_din(din));
    defparam dut.selftest.HOLD_MS=2,dut.selftest.SOUND_MS=12,dut.selftest.GAP_MS=2;
    integer terms[0:3][0:31];
    integer frames[0:3],nonzero[0:3],clipped[0:3];
    integer sum=0,count=0,term,mode,idx,expected;
    reg checking=0;
    reg [31:0] visited=0;
    reg [2:0] old_stage=7;
    // Observe the actual add transactions of the selected production engine.
    // Independent integer sum must equal its saturated output; no forced voice state.
    always @(negedge clk) if(rst && dut.test_active && dut.test_mask==32'hffffffff) begin
        mode=dut.timbre;
        if(dut.source_tick) begin sum=0;count=0;visited=0;checking=1;end
        if(checking) begin
            idx=-1;term=0;
            if((mode==1 || dut.audio_core.render_diagnostic) && dut.audio_core.voices.state==9) begin
                idx=dut.audio_core.voices.voice_idx;term=$signed(dut.audio_core.voices.voice_term);
            end
            if(mode==0 && !dut.audio_core.render_diagnostic && dut.audio_core.piano.state==9)begin
                idx=dut.audio_core.piano.voice;term=$signed(dut.audio_core.piano.envelope_product)>>>19;
            end
            if(mode==2 && dut.audio_core.pipes.state==6) begin
                idx=dut.audio_core.pipes.voice;term=$signed(dut.audio_core.pipes.envelope_product)>>>19;
            end
            if(mode==3 && dut.audio_core.string_model.state==13) begin
                idx=dut.audio_core.string_model.voice;term=$signed(dut.audio_core.string_model.output_product)>>>27;
            end
            if(idx>=0) begin
                if(visited[idx])$fatal(1,"duplicate voice %0d timbre%0d",idx,mode);
                visited[idx]=1;sum=sum+term;count=count+1;
                if(term!=0)terms[mode][idx]=terms[mode][idx]+1;
            end
            if(count==32 && (mode==0 && !dut.audio_core.render_diagnostic ? dut.audio_core.piano_ready : mode<2 ? dut.audio_core.voice_valid : mode==2 ? dut.audio_core.pipe_ready : dut.audio_core.guitar_ready)) begin
                expected=sum;
                if(expected>32767)expected=32767;
                if(expected< -32768)expected=-32768;
                if(visited!==32'hffffffff || $signed(mode==0 && !dut.audio_core.render_diagnostic ? dut.audio_core.piano_dry : mode<2 ? dut.audio_core.base_left : mode==2 ? dut.audio_core.pipe_dry : dut.audio_core.guitar_dry)!==expected)
                    $fatal(1,"32-term sum mismatch timbre%0d visited%h expected%0d actual%0d",mode,visited,expected,$signed(mode<2 ? dut.audio_core.base_left : mode==2 ? dut.audio_core.pipe_dry : dut.audio_core.guitar_dry));
                frames[mode]=frames[mode]+1;
                if(expected!=0)nonzero[mode]=nonzero[mode]+1;
                if(expected==32767 || expected== -32768)clipped[mode]=clipped[mode]+1;
                checking=0;
            end
        end
        if(dut.test_stage!=old_stage) begin old_stage=dut.test_stage;checking=0;end
    end else begin checking=0;old_stage=7;end
    integer words=0,wire_nonzero=0;
    reg [31:0] shift=0;
    reg last_ws=0;
    integer bits=0;
    always @(posedge bck) begin
        if(ws!=last_ws) begin
            if(bits==32) begin words=words+1;if(shift[30:15]!=0)wire_nonzero=wire_nonzero+1;end
            last_ws=ws;bits=1;shift={31'd0,din};
        end else begin shift={shift[30:0],din};bits=bits+1;end
    end
    initial begin
        for(integer t=0;t<4;t=t+1)begin
            frames[t]=0;nonzero[t]=0;clipped[t]=0;
            for(integer v=0;v<32;v=v+1)terms[t][v]=0;
        end
        repeat(8)@(negedge clk);rst=1;
        wait(dut.ready);@(negedge clk);k0=0;k1=0;
        wait(dut.test_active);@(negedge clk);k0=1;k1=1;
        wait(!dut.test_active);repeat(2048)@(negedge clk);
        if(dut.held!==0 || dut.fault || !dut.ready)$fatal(1,"test exit/recovery failed");
        for(integer t=0;t<4;t=t+1)begin
            if(frames[t]<100 || nonzero[t]==0)$fatal(1,"insufficient 32-voice frames timbre%0d frames%0d",t,frames[t]);
            for(integer v=0;v<32;v=v+1)if(terms[t][v]==0)$fatal(1,"silent voice timbre%0d voice%0d",t,v);
            $display("CHECK timbre%0d: 32/32 nonzero voice contributions; exact 32-term mixes=%0d nonzero=%0d clipped=%0d",t,frames[t],nonzero[t],clipped[t]);
        end
        if(words<100 || wire_nonzero==0)$fatal(1,"I2S output absent");
        $display("PASS polyphony32: actual board-button selftest, four procedural timbres x32, no recordings, all128 voice contributions and exact sums, I2S words=%0d nonzero=%0d; automatic exit fault-free",words,wire_nonzero);$finish;
    end
    initial begin #120000000;$fatal(1,"polyphony watchdog stage%0d",dut.test_stage);end
endmodule
