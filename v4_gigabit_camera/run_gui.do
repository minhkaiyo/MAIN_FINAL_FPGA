if [file exists work] {vdel -all}
vlib work
vmap work work

# Biên dịch
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./lib/oddr.v}
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./sdram_model.v}
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./sdram_pll.v}
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./pll_125.v}
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./phy_init_88e1111.v}
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./sdram_ethernet_stream_v4.v}
vlog -vlog01compat -work work +define+SIMULATION +incdir+./lib/Sdram_Control {./tb_top.v}

# Load sim (Bật tính năng tối ưu voptargs="+acc" để chạy lướt nhanh hơn, thay vì -novopt làm chậm máy)
vsim -t 1ps -voptargs="+acc" -L altera_mf_ver -L altera_ver -L lpm_ver -L sgate_ver work.tb_top

# =========================================================
# BƯỚC 1: CHẠY NGẦM KHÔNG WAVE (Để Tăng Tốc & Đỡ tốn RAM)
# Tùy chỉnh: Đổi "0ms" thành thời gian cậu muốn BỎ QUA không xem
# (Ví dụ: "10ms", "25ms" nếu muốn nhảy nhanh qua phần khởi tạo)
# =========================================================
run 15ms

# Mở cửa sổ Wave sau khi đã tua nhanh xong
view wave

# =========================================================
# BƯỚC 2: ADD WAVE CHO GIAI ĐOẠN CẦN SOI
# =========================================================
add wave -divider "CLOCKS"
add wave /tb_top/clk_gen_100
add wave /tb_top/clk_gen_125
add wave /tb_top/clk_gen_vga

add wave -divider "ETHERNET RX"
add wave /tb_top/dut/rx_axis_tvalid
add wave -hex /tb_top/dut/rx_axis_tdata
add wave /tb_top/dut/rx_axis_tlast
add wave -hex /tb_top/dut/byte_cnt

add wave -divider "TRIPLE BUFFER"
add wave /tb_top/dut/wr_frame
add wave /tb_top/dut/rd_frame
add wave /tb_top/dut/frame_ready
add wave /tb_top/dut/fifo_rdusedw

add wave -divider "SDRAM"
add wave -hex /tb_top/dut/state
add wave -hex /tb_top/DRAM_DQ
add wave /tb_top/DRAM_WE_N

add wave -divider "VGA"
add wave -hex /tb_top/dut/v_cnt
add wave -hex /tb_top/VGA_R
add wave -hex /tb_top/VGA_G
add wave -hex /tb_top/VGA_B
add wave /tb_top/VGA_VS

# =========================================================
# BƯỚC 3: CHẠY ĐỂ LẤY SÓNG
# Tùy chỉnh: Đây là khoảng thời gian cậu THỰC SỰ MUỐN XEM sóng
# (Ví dụ: Tua đi 25ms ở Bước 1, rồi chạy thêm "5ms" ở đây là vừa)
# =========================================================
run 5ms

wave zoom full
