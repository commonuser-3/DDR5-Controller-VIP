vlog -sv run.sv
vlog -sv ./memory_module/ddr5_mem_if.sv
vlog -sv ./memory_module/ddr5.sv
vlog -sv -suppress 7061  +define+UVM_NO_REGISTERED_CONVERTER ./AXI_Master_VIP/tb_run.sv +incdir+./AXI_Master_VIP +incdir+C:/questasim_10.4e/verilog_src/uvm-1.1c/src
vsim work.top -l result.log -sv_lib C:/questasim_10.4e/uvm-1.1c/win32/uvm_dpi -voptargs=+acc +UVM_TESTNAME=pcie_single_write_read_narrow_test

# Keep going even if one add wave path can't be resolved.
onerror {resume}

# 1. AXI Master VIP interface
add wave -position insertpoint sim:/top/axi_pcie_intf/*

# 3. AXI slave / DDR5 AXI frontend
add wave -r sim:/top/u_dut/u_axi_fe/s*

# 4. DDR5 channel demux
add wave -r sim:/top/u_dut/u_demux/ch0*
add wave -r sim:/top/u_dut/u_demux/ch1*

# 6. DDR5 bank schedulers
add wave -position insertpoint sim:/top/u_dut/u_sch_ch0/cmd_out*
add wave -position insertpoint sim:/top/u_dut/u_sch_ch1/cmd_out*

# 7. DDR5 command encoder
add wave -position insertpoint sim:/top/u_dut/u_enc/req_ch0*
add wave -position insertpoint sim:/top/u_dut/u_enc/req_ch1*

# 9. DFI interfaces
add wave -position insertpoint sim:/top/dfi_ch0_if/*
add wave -position insertpoint sim:/top/dfi_ch1_if/*


# 8. PHY and ZQ calibration
add wave -r sim:/top/u_phy/*


# =============================================================
# 11. DRAM side - keep memory-module visibility
# =============================================================
add wave -r sim:/top/dram_if/*

run -all

