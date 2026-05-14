# MAIN_FINAL — DE2i-150 FPGA Project Files
# Ngay tao: 2026-05-04
# Cac file chinh thuc da chay ra ket qua tren board DE2i-150 (Cyclone IV GX)

## Cau truc thu muc

```
MAIN_FINAL/
├── VGA/                      # VGA 640x480 output
│   ├── vga_top.v             # Top-level: ghep vga_controller + vga_pattern
│   ├── vga_controller.v      # Timing 640x480 @ 60Hz (25MHz pixel clock)
│   ├── vga_pattern.v         # Sinh hinh colorbar / checkerboard / solid
│   ├── vga_pins.tcl          # Pin assignment cho VGA DAC
│   └── vga_top.sdc           # Timing constraint
│
├── SDRAM/                    # SDRAM Controller (don le)
│   ├── sdram_controller.v    # FSM: INIT → IDLE → READ/WRITE/REFRESH
│   └── sdram_pins.tcl        # Pin assignment cho 2x SDRAM (64MB)
│
├── SDRAM_VGA/                # SDRAM + VGA: hien thi anh tu SDRAM len man hinh
│   ├── sdram_vga_demo.v      # Top-level tich hop: load .hex → SDRAM → VGA
│   ├── sdram_pll.v           # PLL: 50MHz → 100MHz (SDRAM) + 25MHz (VGA)
│   ├── sdram_pins.tcl        # Pin assignment SDRAM
│   ├── vga_pins.tcl          # Pin assignment VGA
│   └── image_data.hex        # Du lieu anh 320x240 RGB565
│
├── Ethernet/                 # Ethernet RGMII + UART streaming
│   ├── eth_basic_link.v      # Top-level: UART RX → Ethernet TX (UDP)
│   ├── mdio_init.v           # Cau hinh PHY Marvell 88E1111 qua MDIO
│   ├── uart_rx.v             # UART receiver (921600 baud)
│   ├── uart_test_top.v       # Test UART doc du lieu
│   ├── ethernet_pins.tcl     # Pin assignment Ethernet RGMII
│   ├── uart_pins.tcl         # Pin assignment UART (GPIO header)
│   ├── stream_img_truecolor.py   # Python: stream anh qua UART → FPGA → Eth
│   ├── stream_live_webcam.py     # Python: stream webcam realtime
│   └── send_eth_udp.py           # Python: gui raw UDP packet
│
├── ESP32_SPI_Control/        # ESP32 ↔ FPGA SPI bridge (dieu khien tu xa)
│   ├── esp32_web_fpga_control.v  # FPGA SPI slave: nhan lenh LED/HEX/LCD/VGA
│   ├── bi_spi_test.v             # SPI slave test co ban
│   └── esp32_firebase_bridge.ino # Firmware ESP32: WiFi+Firebase+SPI
│
├── LCD/                      # LCD 16x2 controller
│   ├── lcd_marquee.v         # LCD chay chu (marquee effect)
│   ├── lcd_test.v            # LCD test co ban
│   └── lcd_pins.tcl          # Pin assignment LCD
│
├── SD_Card/                  # SD Card SPI interface
│   ├── sd_card_test.v        # Doc/ghi SD Card qua SPI mode
│   └── sd_card_pins.tcl      # Pin assignment SD Card slot
│
└── Pin_Assignments/          # Master pin assignment files
    ├── assign_all_pins.tcl   # Tat ca pin cua DE2i-150
    └── board_test_pins.tcl   # Pin cho board test tong hop
```

## Ghi chu
- Moi thu muc con co the su dung doc lap (tao project Quartus rieng)
- File `.tcl` chay trong Quartus: `Tools → Tcl Scripts → chon file → Run`
- File `.sdc` them vao project de constraint timing
- File `.hex` dung cho khoi tao ROM/RAM trong Quartus
- Firmware `.ino` nap vao ESP32 bang Arduino IDE hoac PlatformIO
