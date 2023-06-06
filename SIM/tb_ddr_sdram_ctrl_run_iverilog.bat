del sim.out dump.vcd
iverilog  -g2001  -o sim.out  tb_ddr_sdram_ctrl.v  axi_self_test_master.v  micron_ddr_sdram_model.v  ../RTL/ddr_sdram_ctrl.v
vvp -n sim.out
del sim.out
pause