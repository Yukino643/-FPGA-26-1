// EG4 PLL 参考时钟：50 MHz * 27 / 50 = 27 MHz；VCO=540 MHz。
// 分频范围与 VCO 范围按 TN305_1.1；必须等待 lock 稳定后释放后级 PLL。
module ref27_pll(input wire refclk, reset, output wire clk0_out, extlock);
    wire clk0_buf;
    wire [3:0] unused_clocks;
    EG_LOGIC_BUFG bufg_feedback(.i(clk0_buf), .o(clk0_out));
    EG_PHY_PLL #(
        .DPHASE_SOURCE("DISABLE"), .DYNCFG("DISABLE"), .FIN("50.000000"),
        .FEEDBK_MODE("NORMAL"), .FEEDBK_PATH("CLKC0_EXT"),
        .STDBY_ENABLE("DISABLE"), .PLLRST_ENA("ENABLE"), .SYNC_ENABLE("DISABLE"),
        .GMC_GAIN(2), .ICP_CURRENT(9), .KVCO(2), .LPF_CAPACITOR(1), .LPF_RESISTOR(8),
        .REFCLK_DIV(50), .FBCLK_DIV(27),
        .CLKC0_ENABLE("ENABLE"), .CLKC0_DIV(20), .CLKC0_CPHASE(19), .CLKC0_FPHASE(0)
    ) pll_inst (
        .refclk(refclk), .reset(reset), .stdby(1'b0), .extlock(extlock),
        .load_reg(1'b0), .psclk(1'b0), .psdown(1'b0), .psstep(1'b0),
        .psclksel(3'd0), .psdone(), .dclk(1'b0), .dcs(1'b0), .dwe(1'b0),
        .di(8'd0), .daddr(6'd0), .do(), .fbclk(clk0_out), .clkc({unused_clocks, clk0_buf})
    );
endmodule
