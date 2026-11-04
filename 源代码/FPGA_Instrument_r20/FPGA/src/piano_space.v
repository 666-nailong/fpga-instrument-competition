// Short stereo early reflections. State is generated online; no impulse recording.
module piano_space(
    input wire clk,reset_n,sample_valid,enable,
    input wire signed [15:0] sample_in,
    output reg signed [15:0] left,right,
    output reg valid
);
    reg signed [15:0] memory[0:1023];
    reg [9:0] pointer,filled,address;
    reg signed [15:0] q,dry,tap0,tap1;
    reg [3:0] state;
    always @(posedge clk) begin
        q<=memory[address];
        if(state==8) memory[pointer]<=dry;
    end
    function signed [15:0] clip;
        input signed [18:0] v;
        begin clip=v>19'sd32767 ? 16'sh7fff : v< -19'sd32768 ? 16'sh8000 : v[15:0];end
    endfunction
    always @(posedge clk) begin
        valid<=0;
        if(!reset_n) begin pointer<=0;filled<=0;address<=0;dry<=0;tap0<=0;tap1<=0;left<=0;right<=0;state<=0;valid<=0;end
        else if(sample_valid) begin
            dry<=enable ? sample_in : 16'sd0;address<=pointer-10'd431;state<=1;
        end else case(state)
            1:state<=2;
            2:begin tap0<=filled>=431 ? q : 16'sd0;address<=pointer-10'd719;state<=3;end
            3:state<=4;
            4:begin tap1<=filled>=719 ? q : 16'sd0;state<=8;end
            8:begin
                left<=enable ? clip($signed({{3{dry[15]}},dry})+($signed(tap0)>>>3)+($signed(tap1)>>>4)) : 16'sd0;
                right<=enable ? clip($signed({{3{dry[15]}},dry})+($signed(tap1)>>>3)-($signed(tap0)>>>4)) : 16'sd0;
                pointer<=pointer+1'b1;if(filled!=1023)filled<=filled+1'b1;
                valid<=1;state<=0;
            end
            default:state<=0;
        endcase
    end
endmodule
