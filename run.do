vlog -sv run.sv
vlog -sv ./memory_module/ddr5_mem_if.sv
vlog -sv ./memory_module/ddr5.sv
vlog -sv -suppress 7061 +define+UVM_NO_REGISTERED_CONVERTER ./AXI_Master_VIP/tb_run.sv +incdir+./AXI_Master_VIP +incdir+C:/questasim_10.4e/verilog_src/uvm-1.1c/src

vsim work.top -l result.log -sv_lib C:/questasim_10.4e/uvm-1.1c/win32/uvm_dpi -voptargs=+acc +UVM_TESTNAME=pcie_single_write_read_aligned_test

onerror {resume}
quietly WaveActivateNextPane {} 0

# =============================================================
# 1. AXI interface
# =============================================================
add wave -divider "1. AXI VIP 64-bit Interface"
add wave -radix binary sim:/top/axi_pcie_intf/awvalid
add wave -radix binary sim:/top/axi_pcie_intf/awready
add wave -radix hex    sim:/top/axi_pcie_intf/awaddr
add wave -radix hex    sim:/top/axi_pcie_intf/awid
add wave -radix unsigned sim:/top/axi_pcie_intf/awlen
add wave -radix binary sim:/top/axi_pcie_intf/wvalid
add wave -radix binary sim:/top/axi_pcie_intf/wready
add wave -radix hex    sim:/top/axi_pcie_intf/wdata
add wave -radix hex    sim:/top/axi_pcie_intf/wstrb
add wave -radix binary sim:/top/axi_pcie_intf/wlast
add wave -radix binary sim:/top/axi_pcie_intf/bvalid
add wave -radix binary sim:/top/axi_pcie_intf/bready
add wave -radix binary sim:/top/axi_pcie_intf/arvalid
add wave -radix binary sim:/top/axi_pcie_intf/arready
add wave -radix hex    sim:/top/axi_pcie_intf/araddr
add wave -radix hex    sim:/top/axi_pcie_intf/arid
add wave -radix unsigned sim:/top/axi_pcie_intf/arlen
add wave -radix binary sim:/top/axi_pcie_intf/rvalid
add wave -radix binary sim:/top/axi_pcie_intf/rready
add wave -radix hex    sim:/top/axi_pcie_intf/rdata
add wave -radix binary sim:/top/axi_pcie_intf/rlast

add wave -divider "1a. AXI 64-to-512 Bridge"
add wave -radix binary sim:/top/dut_awvalid
add wave -radix binary sim:/top/dut_awready
add wave -radix hex    sim:/top/dut_awaddr
add wave -radix binary sim:/top/dut_wvalid
add wave -radix binary sim:/top/dut_wready
add wave -radix hex    sim:/top/dut_wdata
add wave -radix hex    sim:/top/dut_wstrb
add wave -radix binary sim:/top/dut_arvalid
add wave -radix binary sim:/top/dut_arready
add wave -radix hex    sim:/top/dut_araddr
add wave -radix binary sim:/top/dut_rvalid
add wave -radix hex    sim:/top/dut_rdata

# =============================================================
# 2. DDR5 frontend
# =============================================================
add wave -divider "2. DDR5 AXI Frontend"
add wave -radix binary sim:/top/u_dut/u_axi_fe/s_awvalid
add wave -radix binary sim:/top/u_dut/u_axi_fe/s_awready
add wave -radix hex    sim:/top/u_dut/u_axi_fe/s_awaddr
add wave -radix binary sim:/top/u_dut/u_axi_fe/s_wvalid
add wave -radix binary sim:/top/u_dut/u_axi_fe/s_wready
add wave -radix hex    sim:/top/u_dut/u_axi_fe/s_wdata
add wave -radix binary sim:/top/u_dut/u_axi_fe/s_arvalid
add wave -radix binary sim:/top/u_dut/u_axi_fe/s_arready
add wave -radix hex    sim:/top/u_dut/u_axi_fe/s_araddr
add wave -radix binary sim:/top/u_dut/u_axi_fe/req_valid
add wave -radix binary sim:/top/u_dut/u_axi_fe/req_ready
add wave -radix binary sim:/top/u_dut/u_axi_fe/req_is_wr
add wave -radix hex    sim:/top/u_dut/u_axi_fe/req_addr
add wave -radix hex    sim:/top/u_dut/u_axi_fe/req_wdata
add wave -radix hex    sim:/top/u_dut/u_axi_fe/req_wstrb
add wave -radix binary sim:/top/u_dut/u_axi_fe/rd_data_valid
add wave -radix hex    sim:/top/u_dut/u_axi_fe/rd_data

# =============================================================
# 3. Demux, scheduler, command encoder
# =============================================================
add wave -divider "3. DDR5 Sub-channel Demux"
add wave -radix binary sim:/top/u_dut/u_demux/req_valid
add wave -radix binary sim:/top/u_dut/u_demux/req_ready
add wave -radix binary sim:/top/u_dut/u_demux/req_is_wr
add wave -radix hex    sim:/top/u_dut/u_demux/req_addr
add wave -radix binary sim:/top/u_dut/u_demux/dch
add wave -radix binary sim:/top/u_dut/u_demux/ch0_valid
add wave -radix binary sim:/top/u_dut/u_demux/ch0_ready
add wave -radix binary sim:/top/u_dut/u_demux/ch1_valid
add wave -radix binary sim:/top/u_dut/u_demux/ch1_ready
add wave -radix hex    sim:/top/u_dut/u_demux/ch0_wdata
add wave -radix hex    sim:/top/u_dut/u_demux/ch1_wdata
add wave -radix binary sim:/top/u_dut/u_demux/merged_rvalid
add wave -radix hex    sim:/top/u_dut/u_demux/merged_rdata

add wave -divider "3a. Bank Scheduler CH0"
add wave -radix binary sim:/top/u_dut/u_sch_ch0/req_valid
add wave -radix binary sim:/top/u_dut/u_sch_ch0/req_ready
add wave -radix binary sim:/top/u_dut/u_sch_ch0/req_is_wr
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/req_bg
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/req_ba
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/req_row
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/req_col
add wave -radix binary sim:/top/u_dut/u_sch_ch0/cmd_out/valid
add wave -radix ascii  sim:/top/u_dut/u_sch_ch0/cmd_out/cmd
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/cmd_out/bg
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/cmd_out/ba
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/cmd_out/row
add wave -radix hex    sim:/top/u_dut/u_sch_ch0/cmd_out/col
add wave -radix binary sim:/top/u_dut/u_sch_ch0/rd_en

add wave -divider "3b. Bank Scheduler CH1"
add wave -radix binary sim:/top/u_dut/u_sch_ch1/req_valid
add wave -radix binary sim:/top/u_dut/u_sch_ch1/req_ready
add wave -radix binary sim:/top/u_dut/u_sch_ch1/req_is_wr
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/req_bg
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/req_ba
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/req_row
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/req_col
add wave -radix binary sim:/top/u_dut/u_sch_ch1/cmd_out/valid
add wave -radix ascii  sim:/top/u_dut/u_sch_ch1/cmd_out/cmd
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/cmd_out/bg
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/cmd_out/ba
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/cmd_out/row
add wave -radix hex    sim:/top/u_dut/u_sch_ch1/cmd_out/col
add wave -radix binary sim:/top/u_dut/u_sch_ch1/rd_en

add wave -divider "3c. Command Encoder"
add wave -radix binary sim:/top/u_dut/u_enc/req_ch0/valid
add wave -radix ascii  sim:/top/u_dut/u_enc/req_ch0/cmd
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch0/bg
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch0/ba
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch0/row
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch0/col
add wave -radix hex    sim:/top/u_dut/ch0_dfi_pkt
add wave -radix binary sim:/top/u_dut/u_enc/req_ch1/valid
add wave -radix ascii  sim:/top/u_dut/u_enc/req_ch1/cmd
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch1/bg
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch1/ba
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch1/row
add wave -radix hex    sim:/top/u_dut/u_enc/req_ch1/col
add wave -radix hex    sim:/top/u_dut/ch1_dfi_pkt

# =============================================================
# 4. DFI write/read interface
# =============================================================
add wave -divider "4. DFI CH0 Command Write Read"
add wave -radix binary sim:/top/dfi_ch0_if/dfi_cs_p
add wave -radix hex    sim:/top/dfi_ch0_if/dfi_address_p
add wave -radix binary sim:/top/dfi_ch0_if/dfi_wrdata_en_p
add wave -radix hex    sim:/top/dfi_ch0_if/dfi_wrdata_p
add wave -radix hex    sim:/top/dfi_ch0_if/dfi_wrdata_mask_p
add wave -radix binary sim:/top/dfi_ch0_if/dfi_rddata_en_p
add wave -radix binary sim:/top/dfi_ch0_if/dfi_rddata_valid_w
add wave -radix hex    sim:/top/dfi_ch0_if/dfi_rddata_w

add wave -divider "4a. DFI CH1 Command Write Read"
add wave -radix binary sim:/top/dfi_ch1_if/dfi_cs_p
add wave -radix hex    sim:/top/dfi_ch1_if/dfi_address_p
add wave -radix binary sim:/top/dfi_ch1_if/dfi_wrdata_en_p
add wave -radix hex    sim:/top/dfi_ch1_if/dfi_wrdata_p
add wave -radix hex    sim:/top/dfi_ch1_if/dfi_wrdata_mask_p
add wave -radix binary sim:/top/dfi_ch1_if/dfi_rddata_en_p
add wave -radix binary sim:/top/dfi_ch1_if/dfi_rddata_valid_w
add wave -radix hex    sim:/top/dfi_ch1_if/dfi_rddata_w

# =============================================================
# 5. PHY block
# =============================================================
add wave -divider "5. PHY Wrapper"
add wave -radix binary sim:/top/phy/dram_cs_init_done
add wave -radix binary sim:/top/phy/dram_reset_n_pin
add wave -radix binary sim:/top/phy/phy_cs0_n
add wave -radix binary sim:/top/phy/phy_cs1_n
add wave -radix binary sim:/top/phy/phy_dq0_oe
add wave -radix hex    sim:/top/phy/phy_dq0_out
add wave -radix binary sim:/top/phy/phy_dqs0_oe
add wave -radix binary sim:/top/phy/phy_dqs0_t
add wave -radix binary sim:/top/phy/phy_dqs0_c
add wave -radix binary sim:/top/phy/dram_rd_valid0
add wave -radix hex    sim:/top/phy/dram_rd_data0
add wave -radix binary sim:/top/phy/phy_dq1_oe
add wave -radix hex    sim:/top/phy/phy_dq1_out
add wave -radix binary sim:/top/phy/phy_dqs1_oe
add wave -radix binary sim:/top/phy/phy_dqs1_t
add wave -radix binary sim:/top/phy/phy_dqs1_c
add wave -radix binary sim:/top/phy/dram_rd_valid1
add wave -radix hex    sim:/top/phy/dram_rd_data1

add wave -divider "5a. PHY Internal"
add wave -radix ascii  sim:/top/phy/u_phy/state
add wave -radix binary sim:/top/phy/u_phy/clk_enable
add wave -radix unsigned sim:/top/phy/u_phy/ca_phase
add wave -radix binary sim:/top/phy/u_phy/ca_cmd_active
add wave -radix binary sim:/top/phy/u_phy/ca_cmd_pending
add wave -radix binary sim:/top/phy/u_phy/ca_cmd_second
add wave -radix binary sim:/top/phy/u_phy/wr_req_ch0
add wave -radix binary sim:/top/phy/u_phy/wr_active_ch0
add wave -radix unsigned sim:/top/phy/u_phy/wr_idx_ch0
add wave -radix binary sim:/top/phy/u_phy/wr_req_ch1
add wave -radix binary sim:/top/phy/u_phy/wr_active_ch1
add wave -radix unsigned sim:/top/phy/u_phy/wr_idx_ch1

# =============================================================
# 6. DRAM interface and memory model
# =============================================================
add wave -divider "6. DRAM Interface Pins"
add wave -radix binary sim:/top/dram_if/ck_t
add wave -radix binary sim:/top/dram_if/ck_c
add wave -radix binary sim:/top/dram_if/cke
add wave -radix binary sim:/top/dram_if/cs_n
add wave -radix binary sim:/top/dram_if/reset_n
add wave -radix binary sim:/top/dram_if/odt
add wave -radix binary sim:/top/dram_if/dch
add wave -radix hex    sim:/top/dram_if/ca
add wave -radix binary sim:/top/dram_if/cai
add wave -radix hex    sim:/top/dram_if/dq
add wave -radix binary sim:/top/dram_if/dqs_t
add wave -radix binary sim:/top/dram_if/dqs_c
add wave -radix hex    sim:/top/dram_if/dmi

add wave -divider "6a. DRAM Model Read Write Core"
add wave -radix binary sim:/top/u_dram/init_done
add wave -radix hex    sim:/top/u_dram/csn_r
add wave -radix hex    sim:/top/u_dram/ca_r
add wave -radix binary sim:/top/u_dram/rd_valid0
add wave -radix hex    sim:/top/u_dram/rd_data0
add wave -radix binary sim:/top/u_dram/rd_valid1
add wave -radix hex    sim:/top/u_dram/rd_data1
add wave -radix binary sim:/top/u_dram/out_en
add wave -radix binary sim:/top/u_dram/dq_oe
add wave -radix binary sim:/top/u_dram/dqs_oe
add wave -radix hex    sim:/top/u_dram/dq_out
add wave -radix hex    sim:/top/u_dram/dq_out_d

run -all
