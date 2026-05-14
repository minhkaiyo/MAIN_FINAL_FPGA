# set_pins_de2i150.tcl - REVERTED TO VALIDATED PINS
# Dung bo chan da chay thanh cong o ban Sniffer

set_location_assignment PIN_A12 -to ENET_GTX_CLK
set_location_assignment PIN_D14 -to ENET_TX_EN
set_location_assignment PIN_B12 -to ENET_TX_DATA[0]
set_location_assignment PIN_E7 -to ENET_TX_DATA[1]
set_location_assignment PIN_C13 -to ENET_TX_DATA[2]
set_location_assignment PIN_D15 -to ENET_TX_DATA[3]

set_location_assignment PIN_L15 -to ENET_RX_CLK
set_location_assignment PIN_A8 -to ENET_RX_DV
set_location_assignment PIN_F15 -to ENET_RX_DATA[0]
set_location_assignment PIN_E13 -to ENET_RX_DATA[1]
set_location_assignment PIN_A5 -to ENET_RX_DATA[2]
set_location_assignment PIN_B7 -to ENET_RX_DATA[3]

set_location_assignment PIN_C15 -to ENET_MDIO
set_location_assignment PIN_C16 -to ENET_MDC
set_location_assignment PIN_C14 -to ENET_RST_N

# IO Standards
set_instance_assignment -name IO_STANDARD "2.5 V" -to ENET_*
set_instance_assignment -name IO_STANDARD "2.5 V" -to ENET_RX_DATA[*]
set_instance_assignment -name IO_STANDARD "2.5 V" -to ENET_TX_DATA[*]
