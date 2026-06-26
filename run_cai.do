vlog -sv run.sv
vlog -sv ./memory_module/ddr5_mem_if.sv
vlog -sv ./memory_module/ddr5.sv
vlog -sv -suppress 7061 +define+UVM_NO_REGISTERED_CONVERTER ./AXI_Master_VIP/tb_run.sv +incdir+./AXI_Master_VIP +incdir+C:/questasim_10.4e/verilog_src/uvm-1.1c/src

vsim work.top -l result.log -sv_lib C:/questasim_10.4e/uvm-1.1c/win32/uvm_dpi -voptargs=+acc +UVM_TESTNAME=pcie_buschop8_test

onerror {resume}

quietly WaveActivateNextPane {} 0
delete wave *

# =============================================================
# Focused CAI waveform view
# Expected ACT CAI event is around 1138000 ps.
# =============================================================

add wave -divider "CAI ACT Event - CH0"
add wave -radix binary   sim:/top/u_phy/cs0_n
add wave -radix binary   sim:/top/u_phy/ca0_original
add wave -radix unsigned sim:/top/u_phy/ca0_ones
add wave                 sim:/top/u_phy/cai0
add wave -radix binary   sim:/top/u_phy/ca0

add wave -divider "DRAM Restored CA - CH0"
add wave -radix binary   sim:/top/dram_if/ca
add wave                 sim:/top/dram_if/cai
add wave -radix binary   sim:/top/u_dram/ca_raw_r
add wave                 sim:/top/u_dram/cai_r
add wave -radix binary   sim:/top/u_dram/ca_r
add wave                 sim:/top/u_dram/csn_r

add wave -divider "PHY CA Serializer Context"
add wave                 sim:/top/u_phy/ca_cmd_active
add wave                 sim:/top/u_phy/ca_cmd_pending
add wave                 sim:/top/u_phy/ca_cmd_second
add wave -radix binary   sim:/top/u_phy/ca_latch_ch0
add wave                 sim:/top/u_phy/cs_latch_ch0

add wave -divider "Controller Command Context"
add wave                 sim:/top/u_dut/sched_cmd_ch0/valid
add wave                 sim:/top/u_dut/sched_cmd_ch0/cmd
add wave -radix hex      sim:/top/u_dut/sched_cmd_ch0/bg
add wave -radix hex      sim:/top/u_dut/sched_cmd_ch0/ba
add wave -radix hex      sim:/top/u_dut/sched_cmd_ch0/row
add wave -radix hex      sim:/top/u_dut/sched_cmd_ch0/col

# Run past the CAI ACT, WR, RD and PRE events, then zoom around ACT CAI.
run 1350 ns
wave zoom range 1120 ns 1160 ns
