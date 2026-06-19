vlog -sv run.sv
vlog -sv ./memory_module/ddr5_mem_if.sv
vlog -sv ./memory_module/ddr5.sv
vlog -sv -suppress 7061  +define+UVM_NO_REGISTERED_CONVERTER ./AXI_Master_VIP/tb_run.sv +incdir+./AXI_Master_VIP +incdir+C:/questasim_10.4e/verilog_src/uvm-1.1c/src
vsim work.top -l result.log -sv_lib C:/questasim_10.4e/uvm-1.1c/win32/uvm_dpi -voptargs=+acc +UVM_TESTNAME=pcie_single_write_read_aligned_test

# Keep going even if one add wave path can't be resolved.
onerror {resume}

# 1. AXI Master VIP interface
add wave -position insertpoint sim:/top/axi_pcie_intf/*

# 3. AXI slave / DDR5 AXI frontend
add wave -r sim:/top/u_dut/u_axi_fe/*

# 4. DDR5 channel demux
add wave -r sim:/top/u_dut/u_demux/*

# 6. DDR5 bank schedulers
add wave -position insertpoint sim:/top/u_dut/u_sch_ch0/*
add wave -position insertpoint sim:/top/u_dut/u_sch_ch1/*

# 7. DDR5 command encoder
add wave -position insertpoint sim:/top/u_dut/u_enc/*

# 9. DFI interfaces
add wave -position insertpoint sim:/top/dfi_ch0_if/*
add wave -position insertpoint sim:/top/dfi_ch1_if/*


# 8. PHY and ZQ calibration
add wave -r sim:/top/u_phy/*

# ---- CH0 commands ----
add wave -group "CH0 CMD" -radix binary sim:/top/dfi_ch0_if/dfi_cs_p
add wave -group "CH0 CMD" -radix binary sim:/top/dfi_ch0_if/dfi_address_p
add wave -group "CH0 CMD"               sim:/top/u_phy/cs0_n
add wave -group "CH0 CMD" -radix binary sim:/top/u_phy/ca0

# ---- CH0 write data ----
add wave -group "CH0 WDATA"             sim:/top/u_phy/wr_req_ch0
add wave -group "CH0 WDATA"             sim:/top/dfi_ch0_if/dfi_wrdata_en_p
add wave -group "CH0 WDATA" -radix hex  sim:/top/dfi_ch0_if/dfi_wrdata_p
add wave -group "CH0 WDATA" -radix hex  sim:/top/dfi_ch0_if/dfi_wrdata_mask_p
add wave -group "CH0 WDATA"             sim:/top/u_phy/dq0_oe
add wave -group "CH0 WDATA" -radix hex  sim:/top/u_phy/dq0_out
add wave -group "CH0 WDATA" -radix hex  sim:/top/u_phy/dm0

# ---- CH0 read data ----
add wave -group "CH0 RDATA"             sim:/top/dfi_ch0_if/dfi_rddata_en_p
add wave -group "CH0 RDATA" -radix hex  sim:/top/u_phy/dq0_in
add wave -group "CH0 RDATA" -radix hex  sim:/top/dfi_ch0_if/dfi_rddata_w
add wave -group "CH0 RDATA"             sim:/top/dfi_ch0_if/dfi_rddata_valid_w

# ---- CH1 commands ----
add wave -group "CH1 CMD" -radix binary sim:/top/dfi_ch1_if/dfi_cs_p
add wave -group "CH1 CMD" -radix binary sim:/top/dfi_ch1_if/dfi_address_p
add wave -group "CH1 CMD"               sim:/top/u_phy/cs1_n
add wave -group "CH1 CMD" -radix binary sim:/top/u_phy/ca1

# ---- CH1 write data ----
add wave -group "CH1 WDATA"             sim:/top/u_phy/wr_req_ch1
add wave -group "CH1 WDATA"             sim:/top/dfi_ch1_if/dfi_wrdata_en_p
add wave -group "CH1 WDATA" -radix hex  sim:/top/dfi_ch1_if/dfi_wrdata_p
add wave -group "CH1 WDATA"             sim:/top/u_phy/dq1_oe
add wave -group "CH1 WDATA" -radix hex  sim:/top/u_phy/dq1_out

# ---- CH1 read data ----
add wave -group "CH1 RDATA"             sim:/top/dfi_ch1_if/dfi_rddata_en_p
add wave -group "CH1 RDATA" -radix hex  sim:/top/u_phy/dq1_in
add wave -group "CH1 RDATA" -radix hex  sim:/top/dfi_ch1_if/dfi_rddata_w
add wave -group "CH1 RDATA"             sim:/top/dfi_ch1_if/dfi_rddata_valid_w

# ---- PHY CA two-cycle serializer debug ----
add wave -group "PHY CA SERIAL"          sim:/top/u_phy/ca_cmd_active
add wave -group "PHY CA SERIAL"          sim:/top/u_phy/ca_cmd_pending
add wave -group "PHY CA SERIAL"          sim:/top/u_phy/ca_cmd_second
add wave -group "PHY CA SERIAL" -radix hex sim:/top/u_phy/ca_latch_ch0
add wave -group "PHY CA SERIAL" -radix hex sim:/top/u_phy/ca_latch_ch1
add wave -group "PHY CA SERIAL"          sim:/top/u_phy/cs_latch_ch0
add wave -group "PHY CA SERIAL"          sim:/top/u_phy/cs_latch_ch1

# =============================================================
# 11. DRAM side - keep memory-module visibility
# =============================================================
add wave -r sim:/top/dram_if/*

run -all

