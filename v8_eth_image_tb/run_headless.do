transcript file sim_log.txt
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

# Load và Chạy — 10ms đủ cho 3 frame gửi + VGA quét
vsim -c -t 1ps -novopt -L altera_mf_ver -L altera_ver -L lpm_ver -L sgate_ver work.tb_top
run 150ms
quit -f
