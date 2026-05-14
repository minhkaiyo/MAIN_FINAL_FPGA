vlib work
# Compile only necessary simulation files
vlog -sv +define+SIMULATION sdram_pll.v pll_125.v sdram_model.v phy_init_88e1111.v sdram_ethernet_stream_v4.v tb_top.v
vsim -L altera_mf_ver -L altera_ver -L cycloneiv_ver -L lpm_ver -L sgate_ver -L 220model_ver tb_top -l sim_results.log
run -all
quit
