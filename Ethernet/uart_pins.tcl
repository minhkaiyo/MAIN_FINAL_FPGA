# ==============================================================================
# PIN ASSIGNMENT SCRIPT: UART RX TEST
# Board: Terasic DE2i-150
# ==============================================================================

# CLOCK
set_location_assignment PIN_AJ16 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

# KEY
set_location_assignment PIN_AA26 -to KEY[0]
set_location_assignment PIN_AE25 -to KEY[1]
set_location_assignment PIN_AF30 -to KEY[2]
set_location_assignment PIN_AE26 -to KEY[3]
set_instance_assignment -name IO_STANDARD "2.5 V" -to KEY*

# UART RXD PIN (CỰC KỲ QUAN TRỌNG)
set_location_assignment PIN_B27 -to UART_RXD
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_RXD

# LEDR
set_location_assignment PIN_T23 -to LEDR[0]
set_location_assignment PIN_T24 -to LEDR[1]
set_location_assignment PIN_V27 -to LEDR[2]
set_location_assignment PIN_W25 -to LEDR[3]
set_location_assignment PIN_T21 -to LEDR[4]
set_location_assignment PIN_T26 -to LEDR[5]
set_location_assignment PIN_R25 -to LEDR[6]
set_location_assignment PIN_T27 -to LEDR[7]
set_location_assignment PIN_P25 -to LEDR[8]
set_location_assignment PIN_R24 -to LEDR[9]
set_location_assignment PIN_P21 -to LEDR[10]
set_location_assignment PIN_N24 -to LEDR[11]
set_location_assignment PIN_N21 -to LEDR[12]
set_location_assignment PIN_M25 -to LEDR[13]
set_location_assignment PIN_K24 -to LEDR[14]
set_location_assignment PIN_L25 -to LEDR[15]
set_location_assignment PIN_M21 -to LEDR[16]
set_location_assignment PIN_M22 -to LEDR[17]
set_instance_assignment -name IO_STANDARD "2.5 V" -to LEDR*

# LEDG
set_location_assignment PIN_AA25 -to LEDG[0]
set_location_assignment PIN_AB25 -to LEDG[1]
set_location_assignment PIN_F27 -to LEDG[2]
set_location_assignment PIN_F26 -to LEDG[3]
set_location_assignment PIN_W26 -to LEDG[4]
set_location_assignment PIN_Y22 -to LEDG[5]
set_location_assignment PIN_Y25 -to LEDG[6]
set_location_assignment PIN_AA22 -to LEDG[7]
set_location_assignment PIN_J25 -to LEDG[8]
set_instance_assignment -name IO_STANDARD "2.5 V" -to LEDG*

# HEX0
set_location_assignment PIN_E15 -to HEX0[0]
set_location_assignment PIN_E12 -to HEX0[1]
set_location_assignment PIN_G11 -to HEX0[2]
set_location_assignment PIN_F11 -to HEX0[3]
set_location_assignment PIN_F16 -to HEX0[4]
set_location_assignment PIN_D16 -to HEX0[5]
set_location_assignment PIN_F14 -to HEX0[6]
set_instance_assignment -name IO_STANDARD "2.5 V" -to HEX0*

# HEX1
set_location_assignment PIN_G14 -to HEX1[0]
set_location_assignment PIN_B13 -to HEX1[1]
set_location_assignment PIN_G13 -to HEX1[2]
set_location_assignment PIN_F12 -to HEX1[3]
set_location_assignment PIN_G12 -to HEX1[4]
set_location_assignment PIN_J9 -to HEX1[5]
set_location_assignment PIN_G10 -to HEX1[6]
set_instance_assignment -name IO_STANDARD "2.5 V" -to HEX1*
