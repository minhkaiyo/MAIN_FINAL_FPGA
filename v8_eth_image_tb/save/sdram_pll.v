// ==========================================================================
// PLL WRAPPER: 50MHz → 100MHz (logic) + 100MHz -3ns (SDRAM) + 25MHz (VGA)
// Dùng Altera altpll primitive cho Cyclone IV GX
// ==========================================================================
module sdram_pll (
    input  wire inclk0,     // 50MHz từ oscillator trên board
    output wire c0,         // 100MHz cho logic bên trong FPGA
    output wire c1,         // 100MHz lệch pha -3ns cho chân SDRAM_CLK
    output wire c2,         // 25MHz cho VGA pixel logic
    output wire c3,         // 25MHz lệch pha -10ns cho VGA_CLK (DAC sampling)
    output wire locked      // 1 = PLL đã ổn định
);

wire [4:0] clk_bus;
assign c0 = clk_bus[0];
assign c1 = clk_bus[1];
assign c2 = clk_bus[2];
assign c3 = clk_bus[3];

altpll altpll_component (
    .inclk  ({1'b0, inclk0}),
    .clk    (clk_bus),
    .locked (locked),
    // --- Các cổng không dùng ---
    .activeclock (), .areset (1'b0), .clkbad (), .clkena ({6{1'b1}}),
    .clkloss (), .clkswitch (1'b0), .configupdate (1'b0),
    .enable0 (), .enable1 (), .extclk (), .extclkena ({4{1'b1}}),
    .fbin (1'b1), .fbmimicbidir (), .fbout (), .fref (), .icdrclk (),
    .pfdena (1'b1), .phasecounterselect ({4{1'b1}}), .phasedone (),
    .phasestep (1'b1), .phaseupdown (1'b1), .pllena (1'b1),
    .scanaclr (1'b0), .scanclk (1'b0), .scanclkena (1'b1),
    .scandata (1'b0), .scandataout (), .scandone (),
    .scanread (1'b0), .scanwrite (1'b0),
    .sclkout0 (), .sclkout1 (), .vcooverrange (), .vcounderrange ()
);

defparam
    altpll_component.bandwidth_type          = "AUTO",
    // c0: 100MHz (50 × 2), phase 0
    altpll_component.clk0_divide_by          = 1,
    altpll_component.clk0_duty_cycle         = 50,
    altpll_component.clk0_multiply_by        = 2,
    altpll_component.clk0_phase_shift        = "0",
    // c1: 100MHz, phase -3ns (cho SDRAM)
    altpll_component.clk1_divide_by          = 1,
    altpll_component.clk1_duty_cycle         = 50,
    altpll_component.clk1_multiply_by        = 2,
    altpll_component.clk1_phase_shift        = "-2500",
    // c2: 25MHz (50 / 2) cho VGA pixel clock
    altpll_component.clk2_divide_by          = 2,
    altpll_component.clk2_duty_cycle         = 50,
    altpll_component.clk2_multiply_by        = 1,
    altpll_component.clk2_phase_shift        = "0",
    // c3: 25MHz, lệch pha -10ns (-10000ps) cho VGA_CLK ra DAC
    // DAC ADV7123 lấy mẫu R/G/B tại cạnh lên của VGA_CLK.
    // Lệch pha đảm bảo clock đến SAU khi dữ liệu pixel đã ổn định → loại bỏ nhiễu sóng.
    altpll_component.clk3_divide_by          = 2,
    altpll_component.clk3_duty_cycle         = 50,
    altpll_component.clk3_multiply_by        = 1,
    altpll_component.clk3_phase_shift        = "-10000",
    altpll_component.compensate_clock        = "CLK0",
    altpll_component.inclk0_input_frequency  = 20000,      // 50MHz = 20000 ps
    altpll_component.intended_device_family  = "Cyclone IV GX",
    altpll_component.lpm_hint                = "CBX_MODULE_PREFIX=sdram_pll",
    altpll_component.lpm_type                = "altpll",
    altpll_component.operation_mode          = "NORMAL",
    altpll_component.pll_type                = "AUTO",
    altpll_component.port_activeclock        = "PORT_UNUSED",
    altpll_component.port_areset             = "PORT_UNUSED",
    altpll_component.port_clkbad0            = "PORT_UNUSED",
    altpll_component.port_clkbad1            = "PORT_UNUSED",
    altpll_component.port_clkloss            = "PORT_UNUSED",
    altpll_component.port_clkswitch          = "PORT_UNUSED",
    altpll_component.port_configupdate       = "PORT_UNUSED",
    altpll_component.port_fbin               = "PORT_UNUSED",
    altpll_component.port_inclk0             = "PORT_USED",
    altpll_component.port_inclk1             = "PORT_UNUSED",
    altpll_component.port_locked             = "PORT_USED",
    altpll_component.port_pfdena             = "PORT_UNUSED",
    altpll_component.port_phasecounterselect = "PORT_UNUSED",
    altpll_component.port_phasedone          = "PORT_UNUSED",
    altpll_component.port_phasestep          = "PORT_UNUSED",
    altpll_component.port_phaseupdown        = "PORT_UNUSED",
    altpll_component.port_pllena             = "PORT_UNUSED",
    altpll_component.port_scanaclr           = "PORT_UNUSED",
    altpll_component.port_scanclk            = "PORT_UNUSED",
    altpll_component.port_scanclkena         = "PORT_UNUSED",
    altpll_component.port_scandata           = "PORT_UNUSED",
    altpll_component.port_scandataout        = "PORT_UNUSED",
    altpll_component.port_scandone           = "PORT_UNUSED",
    altpll_component.port_scanread           = "PORT_UNUSED",
    altpll_component.port_scanwrite          = "PORT_UNUSED",
    altpll_component.port_clk0               = "PORT_USED",
    altpll_component.port_clk1               = "PORT_USED",
    altpll_component.port_clk2               = "PORT_USED",
    altpll_component.port_clk3               = "PORT_USED",
    altpll_component.port_clk4               = "PORT_UNUSED",
    altpll_component.self_reset_on_loss_lock = "OFF",
    altpll_component.width_clock             = 5;

endmodule
