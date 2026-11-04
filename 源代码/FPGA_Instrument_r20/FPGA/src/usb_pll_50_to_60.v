// GW5AT-60 PLLA: 50 MHz input, 900 MHz VCO, 60 MHz USB clock.
module usb_pll_50_to_60 (
    input wire clkin,
    output wire clkout,
    output wire lock
);
    PLLA #(
        .FCLKIN("50"), .IDIV_SEL(1), .FBDIV_SEL(1),
        .MDIV_SEL(18), .ODIV0_SEL(15),
        .CLKFB_SEL("INTERNAL"), .CLKOUT0_EN("TRUE")
    ) pll (
        .CLKIN(clkin), .CLKOUT0(clkout), .LOCK(lock),
        .CLKFB(1'b0), .RESET(1'b0), .PLLPWD(1'b0),
        .RESET_I(1'b0), .RESET_O(1'b0),
        .PSSEL(3'b0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
        .MDCLK(1'b0), .MDOPC(2'b0), .MDAINC(1'b0), .MDWDI(8'b0)
    );
endmodule
