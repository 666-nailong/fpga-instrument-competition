// Lossless representation of the frozen Q15 FIR table. Three-clock ROM pipeline.
module resample_coefficient_decoder(
    input wire clk,enable,
    input wire [14:0] address,
    output reg signed [15:0] coefficient
);
    reg [31:0] anchors[0:1023];
    initial $readmemh("resample_anchor.mem",anchors);
    wire [8:0] phase=address[14:6];
    wire [5:0] tap=address[5:0];
    wire [13:0] residual_address=phase*14'd22+tap/6'd3;
    reg [31:0] anchor;
    reg [4:0] fraction;
    reg [3:0] bank;
    reg [1:0] slot;
    wire [15:0] residue_words[0:10];
    genvar i;
    generate for(i=0;i<11;i=i+1) begin: banks
        reg [15:0] data[0:1023];reg [15:0] q;
        if(i==0) initial $readmemh("resample_residual_0.mem",data);
        if(i==1) initial $readmemh("resample_residual_1.mem",data);
        if(i==2) initial $readmemh("resample_residual_2.mem",data);
        if(i==3) initial $readmemh("resample_residual_3.mem",data);
        if(i==4) initial $readmemh("resample_residual_4.mem",data);
        if(i==5) initial $readmemh("resample_residual_5.mem",data);
        if(i==6) initial $readmemh("resample_residual_6.mem",data);
        if(i==7) initial $readmemh("resample_residual_7.mem",data);
        if(i==8) initial $readmemh("resample_residual_8.mem",data);
        if(i==9) initial $readmemh("resample_residual_9.mem",data);
        if(i==10) initial $readmemh("resample_residual_10.mem",data);
        always @(posedge clk) if(enable) q<=data[residual_address[9:0]];
        assign residue_words[i]=q;
    end endgenerate
    reg signed [21:0] product;
    reg signed [15:0] base;
    reg signed [4:0] correction;
    wire [15:0] selected=residue_words[bank];
    always @(posedge clk) begin
        if(enable) begin
            anchor<=anchors[{phase[8:5],tap}];fraction<=phase[4:0];
            bank<=residual_address[13:10];slot<=tap%6'd3;
        end
        product<=$signed(anchor[31:16])*$signed({1'b0,fraction});
        base<=anchor[15:0];correction<=selected[slot*5 +:5];
        coefficient<=$signed(base)+($signed(product)>>>5)+$signed(correction);
    end
endmodule
