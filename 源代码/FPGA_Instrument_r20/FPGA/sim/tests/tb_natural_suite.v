`timescale 1ns/1ps
module tb_natural_suite;
    reg clk=0,reset_n=0,tick=0,enable=1,octave=0;
    reg [31:0] gate=0;
    always #10 clk=~clk;
    wire signed [15:0] organ,guitar,body,left,right;
    wire organ_ready,guitar_ready,body_valid,room_valid,tail;
    reg organ_d=0,guitar_d=0;
    pipe_organ pipes(clk,reset_n,tick,enable,octave,gate,organ,organ_ready);
    plucked_guitar strings(clk,reset_n,tick,enable,octave,gate,guitar,guitar_ready);
    always @(posedge clk) begin organ_d<=organ_ready;guitar_d<=guitar_ready;end
    guitar_body soundboard(clk,reset_n,guitar_ready&&!guitar_d,enable,guitar,body,body_valid);
    organ_room hall(clk,reset_n,organ_ready&&!organ_d,enable,organ,left,right,room_valid,tail);
    integer frame_index=0,cycles,max_cycles=0,file,i,nonzero=0;
    reg body_seen,room_seen;
    task frame;
        begin
            @(negedge clk);tick=1;@(negedge clk);tick=0;
            body_seen=0;room_seen=0;cycles=0;
            while(!(body_seen&&room_seen) && cycles<1020) begin
                @(negedge clk);cycles=cycles+1;
                if(body_valid)body_seen=1;if(room_valid)room_seen=1;
            end
            if(cycles>=1020 || !organ_ready || !guitar_ready) $fatal(1,"natural deadline %d",cycles);
            if(cycles>max_cycles)max_cycles=cycles;
            if((^organ===1'bx)||(^guitar===1'bx)||(^body===1'bx)||(^left===1'bx)||(^right===1'bx))
                $fatal(1,"uninitialized state at frame %d",frame_index);
            if(organ==32767 || organ==-32768 || guitar==32767 || guitar==-32768) $fatal(1,"clipped dry");
            if(body!=0)nonzero=nonzero+1;
            $fdisplay(file,"%0d %0d %0d %0d %0d",organ,guitar,body,left,right);
            frame_index=frame_index+1;
        end
    endtask
    initial begin
        file=$fopen("suite_capture.txt","w");
        repeat(8)@(negedge clk);reset_n=1;
        // Low C4, high A5, C-major chord and two repeated A4 attacks.
        for(i=0;i<8192;i=i+1)begin
            case(i/1024)
                0:gate=32'h00000001;
                1:gate=0;
                2:gate=32'h00200000;
                3:gate=0;
                4:gate=32'h00000091;
                5:gate=0;
                6:gate=(i%512)<256 ? 32'h00000200 : 0;
                7:gate=0;
            endcase
            frame();
        end
        $fclose(file);
        $display("PASS suite: C4/A5/chord/repeated A4/release, dry/body/stereo; maximum %0d/1024 clocks; frames=%0d",max_cycles,frame_index);
        $finish;
    end
    initial begin #1500000000;$fatal(1,"natural timeout");end
endmodule
