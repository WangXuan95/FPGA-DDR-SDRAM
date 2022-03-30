del sim.out dump.vcd
iverilog  -g2005-sv  -o sim.out  tb_ddr_sdram_ctrl.sv  axi_self_test_master.sv  micron_ddr_sdram_model.sv  ../RTL/ddr_sdram_ctrl.sv
vvp -n sim.out
del sim.out
pause