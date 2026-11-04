// Analytic constant-skirt band-pass modes, coefficients Q28.
function signed [30:0] body_a1;
input [1:0] index;
begin case(index)
2'd0:body_a1=31'sd535553733;
2'd1:body_a1=31'sd534920476;
2'd2:body_a1=31'sd532430321;
2'd3:body_a1=31'sd446072583;
endcase end endfunction
function signed [30:0] body_a2;
input [1:0] index;
begin case(index)
2'd0:body_a2=-31'sd267171933;
2'd1:body_a2=-31'sd266671192;
2'd2:body_a2=-31'sd264792073;
2'd3:body_a2=-31'sd203822628;
endcase end endfunction
function signed [30:0] body_b;
input [1:0] index;
begin case(index)
2'd0:body_b=31'sd284293;
2'd1:body_b=31'sd441066;
2'd2:body_b=31'sd1275184;
2'd3:body_b=31'sd6461283;
endcase end endfunction
