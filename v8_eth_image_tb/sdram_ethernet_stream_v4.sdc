# SDC for V4 Gigabit Camera — DE2i-150
# Tham khảo từ EthernetRepeater.sdc (bản chạy thành công 1Gbps)

#**************************************************************
# Create Clock
#**************************************************************
create_clock -name CLOCK_50  -period 20.000ns [get_ports CLOCK_50]
create_clock -name CLOCK2_50 -period 20.000ns [get_ports CLOCK2_50]
create_clock -name CLOCK3_50 -period 20.000ns [get_ports CLOCK3_50]

# RGMII RX clock — source-synchronous from PHY (Marvell 88E1111)
# Khi Reg20 bit 7 = 1 (RX delay ON), clock đến FPGA đã center-aligned
# Period = 8ns (125MHz cho 1Gbps), waveform shifted 2ns (center-aligned)
create_clock -name virtual_ENET_RX_CLK_1000 -period 8.000ns
create_clock -name ENET_RX_CLK_1000 -period 8.000ns -waveform { 2.000 6.000 } [get_ports ENET_RX_CLK]

# Input delay cho DDR RX data (từ datasheet Marvell 88E1111)
# Khi Reg20.7 = 1 (PHY thêm internal RX delay):
#   t_setup = 1.2ns, t_hold = 1.2ns
#   Unit interval = 4ns (DDR half-period)
#   max input delay = 4.0 - 1.2 = 2.8ns
#   min input delay = 1.2ns
set_input_delay -max 2.800ns \
  -clock [get_clocks ENET_RX_CLK_1000] \
  -add_delay [get_ports ENET_RX_DATA*]
set_input_delay -min 1.200ns \
  -clock [get_clocks ENET_RX_CLK_1000] \
  -add_delay [get_ports ENET_RX_DATA*]

set_input_delay -max 2.800ns \
  -clock [get_clocks ENET_RX_CLK_1000] \
  -add_delay [get_ports ENET_RX_DV]
set_input_delay -min 1.200ns \
  -clock [get_clocks ENET_RX_CLK_1000] \
  -add_delay [get_ports ENET_RX_DV]

# Same-Edge Capture Center-Aligned false paths
set_false_path -setup -fall_from [get_clocks virtual_ENET_RX_CLK_1000] -rise_to [get_clocks ENET_RX_CLK_1000]
set_false_path -setup -rise_from [get_clocks virtual_ENET_RX_CLK_1000] -fall_to [get_clocks ENET_RX_CLK_1000]
set_false_path -hold  -rise_from [get_clocks virtual_ENET_RX_CLK_1000] -rise_to [get_clocks ENET_RX_CLK_1000]
set_false_path -hold  -fall_from [get_clocks virtual_ENET_RX_CLK_1000] -fall_to [get_clocks ENET_RX_CLK_1000]

#**************************************************************
# Derive PLL Clocks & Uncertainty
#**************************************************************
derive_pll_clocks
derive_clock_uncertainty

# Intentional CDC synchronizer first stages. These paths are asynchronous by
# design; timing is handled by the following synchronizer registers.
set_false_path \
  -from [get_registers -nowarn {*phy_init*|configured}] \
  -to   [get_registers -nowarn {*phy_ready_125_sync*}]

set_false_path \
  -from [get_registers -nowarn {rd_frame[*]}] \
  -to   [get_registers -nowarn {rd_frame_eth_s1[*]}]

# The RGMII RX clock, SDRAM/VGA PLL, and Ethernet PLL are independent capture
# domains in this design. Cross-domain transfers go through FIFOs/synchronizers.
set_clock_groups -asynchronous \
  -group [get_clocks -nowarn {CLOCK_50}] \
  -group [get_clocks -nowarn {ENET_RX_CLK_1000}] \
  -group [get_clocks -nowarn {pll_125_inst|altpll_component|auto_generated|pll1|clk[0]}] \
  -group [get_clocks -nowarn {pll_sdram_inst|altpll_component|auto_generated|pll1|clk[0] pll_sdram_inst|altpll_component|auto_generated|pll1|clk[2]}]
