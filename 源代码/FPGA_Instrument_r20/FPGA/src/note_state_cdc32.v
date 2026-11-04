// Bundled-data handshake: payload stays fixed until the destination acknowledges.
// Source updates while busy coalesce to the latest state. USB reports are much slower.
module note_state_cdc32(
    input wire src_clk, src_reset_n,
    input wire [33:0] src_state,
    input wire dst_clk, dst_reset_n,
    output reg [33:0] dst_state
);
    reg [33:0] payload;
    reg request_toggle, acknowledge_toggle;
    (* syn_preserve = 1 *) reg [1:0] request_sync, acknowledge_sync;
    always @(posedge src_clk or negedge src_reset_n) begin
        if (!src_reset_n) begin
            payload <= 0; request_toggle <= 0; acknowledge_sync <= 0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
            if (request_toggle == acknowledge_sync[1] && src_state != payload) begin
                payload <= src_state;
                request_toggle <= ~request_toggle;
            end
        end
    end
    always @(posedge dst_clk or negedge dst_reset_n) begin
        if (!dst_reset_n) begin
            dst_state <= 0; acknowledge_toggle <= 0; request_sync <= 0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (request_sync[1] != acknowledge_toggle) begin
                dst_state <= payload;
                acknowledge_toggle <= request_sync[1];
            end
        end
    end
endmodule
