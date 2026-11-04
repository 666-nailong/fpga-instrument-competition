// Exact 768 LUT6 INIT bits, packed into 32 shared-address 24-bit tables for speed.
module bowed_conflict_decode(input wire [191:0] codes,output wire [767:0] patterns);
    reg [63:0] truth [0:767];
    reg [23:0] packed_truth [0:2047];
    integer group_index,address,bit_index;
    initial begin
        $readmemh("conflict_lut_truth.mem",truth);
        for(group_index=0;group_index<32;group_index=group_index+1)
            for(address=0;address<64;address=address+1)
                for(bit_index=0;bit_index<24;bit_index=bit_index+1)
                    packed_truth[group_index*64+address][bit_index]=truth[group_index*24+bit_index][address];
    end
    genvar group_number;
    generate for(group_number=0;group_number<32;group_number=group_number+1) begin: lut
        assign patterns[group_number*24+:24]=packed_truth[group_number*64+codes[group_number*6+:6]];
    end endgenerate
endmodule
