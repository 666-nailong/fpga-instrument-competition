`timescale 1ns/1ps
module tb_resampler_wait;
    reg clk=0,reset_n=0;
    always #10 clk=~clk;
    reg [9:0] source_phase=0;
    always @(posedge clk) source_phase<=reset_n ? source_phase+1'b1 : 10'd0;
    wire source_tick=reset_n && source_phase==7;
    wire tick;
    pcm5102_i2s cadence(.clk(clk),.reset_n(reset_n),.enable(1'b1),.pcm_valid(1'b1),
        .pcm_left(16'd0),.pcm_right(16'd0),.frame_tick(tick));
    reg [31:0] random_state=32'h672ac351;
    reg [15:0] left=0,right=0;
    integer inputs=0,frames=0,reads=0,epoch_age=0;
    always @(posedge clk) if(reset_n && source_tick) begin
        random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        inputs<=inputs+1;
        case(inputs%16)
            0:begin left<=16'h8000;right<=16'h7fff;end
            1:begin left<=0;right<=0;end
            2:begin left<=16'h7fff;right<=16'h8000;end
            default:begin left<=random_state[15:0];right<=random_state[31:16];end
        endcase
    end
    wire [15:0] dl,dr,gl,gr;
    wire dv,df,gv,gf;
    natural_native_to_48k dut(clk,reset_n,source_tick,tick,left,right,dl,dr,dv,df);
    native_to_48k golden(clk,reset_n,source_tick,tick,left,right,gl,gr,gv,gf);
    // Independent register-memory model of the original state-1 read.
    reg [31:0] register_history[0:127];
    reg [31:0] expected_history;
    integer history_checks=0,wraps=0;
    always @(posedge clk) begin
        if(!reset_n) expected_history<=0;
        else begin
            if(source_tick) begin
                register_history[dut.write_ptr]<={left,right};
                if(dut.write_ptr==127) wraps=wraps+1;
            end
            if(dut.state==1) begin
                if(source_tick && dut.write_ptr==dut.history_addr)
                    $fatal(1,"history read/write collision under legal cadence");
                expected_history<=dut.tap<dut.captured_count ? register_history[dut.history_addr] : 32'd0;
            end
        end
    end
    always @(posedge clk) begin
        if(!reset_n)epoch_age<=0;
        else if(dut.state==0 && tick)epoch_age<=0;
        else epoch_age<=epoch_age+1;
    end
    reg [8:0] stable_phase=0;
    reg [511:0] phases_seen=0;
    integer phases=0;
    always @(negedge clk) if(reset_n)begin
        if(dut.state==4)begin stable_phase=dut.phase_index;phases_seen[dut.phase_index]=1;end
        if(dut.state!=0 && dut.state!=4 && dut.phase_index!==stable_phase)$fatal(1,"phase changed before FIR completion");
        if(dut.state==2)begin
            if(epoch_age<2)$fatal(1,"coefficient captured before E2");
            if({dut.data_left,dut.data_right}!==expected_history)
                $fatal(1,"synchronous history differs from register-memory read");
            history_checks=history_checks+1;
            reads=reads+1;
        end
        if(tick)begin
            if({dl,dr,dv,df}!=={gl,gr,gv,gf} || df)$fatal(1,"FIR output differs at DAC frame %0d",frames);
            frames=frames+1;
            if(frames==1200)begin
                for(integer k=0;k<512;k=k+1)phases=phases+phases_seen[k];
                if(reads<70000 || phases<256 || history_checks!=reads || wraps<8)$fatal(1,"insufficient FIR coverage");
                $display("PASS FIR wait: 1200 DAC frames bit-exact vs frozen 192-cycle FIR; %0d coefficient captures at E2 or later; phase stable all taps; %0d/512 stored phases; random/extreme stereo",reads,phases);
                $display("PASS synchronous history: %0d original register-read checks, %0d ring wraps, startup zero masking and reset during convolution",history_checks,wraps);
                $finish;
            end
        end
    end
    initial begin
        #200;reset_n=1;
        wait(frames==7 && dut.state==5);
        @(negedge clk);reset_n=0;
        repeat(4) @(negedge clk);
        reset_n=1;
    end
    initial begin #30000000;$fatal(1,"FIR watchdog");end
endmodule
