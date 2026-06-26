//-----------------------------------------------------------------------------
// File Name    : axi_tb_top.sv
// Project      : DDR3 Controller Subsystem verfication using AXI3
// Engineer     : amith

// Created Date : 2025-05-15
//
// Description  : Implementation of the axi_tb_top module
//
// Features     : - Module implementation

//
// Dependencies : None
//
// Revision History:
// -----------------------------------------------------------------------
// Rev  | Date       | Author         | Description
// -----------------------------------------------------------------------
// 0.1  | 2025-05-15 | amith    | Initial draft
// -----------------------------------------------------------------------
//-----------------------------------------------------------------------------
`timescale 1ps/1ps


//test bench top // axi_tb_top.sv
module top;
	

	
	reg aclk; //100Mhz
	reg areset_n;
    bit out_of_order=0;
	bit overlapping=0;
	bit verbose = 1;

	//=============================================axi related parameters================================================
	parameter AXI_DATA_WIDTH = 64;
	parameter AXI_ADDR_WIDTH = 32;
	parameter AXI_ID_WIDTH = 4;
	parameter AXI_STRB_WIDTH = 8;
	parameter AXI_MEM_SIZE = 10000;
	parameter AXI_LEN_WIDTH = 4;
	parameter tck = 2500/4;      // 800 MHz controller / DFI clock
	parameter ps = 2500/4;
	parameter real dram_tck = 156.25; // 3200 MHz CK, 6400 MT/s data rate
	logic i_cpu_ck=1;
	logic i_cpu_ck_ps=1;
	logic i_dram_ck=1;
	logic dch;

	//=============================================== Clock Generation========================================================
    // clock generator
    always i_cpu_ck = #tck ~i_cpu_ck;
	always i_cpu_ck_ps = #ps ~i_cpu_ck_ps;
	always i_dram_ck = #dram_tck ~i_dram_ck;
	
	// initial begin
	// aclk = 0;
	// forever #5 aclk=~aclk;
	// end

	initial begin 
		areset_n=0;
		repeat(2)@(posedge i_cpu_ck);
		areset_n=1;
	end



	axi_pcie_intf#(
		.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
		.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
		.AXI_ID_WIDTH  (AXI_ID_WIDTH),
		.AXI_STRB_WIDTH(AXI_STRB_WIDTH),
		.AXI_LEN_WIDTH (AXI_LEN_WIDTH)
	) axi_pcie_intf (
			i_cpu_ck, areset_n
		);

	//config axi
	axi_cfg_intf axi_cfg_interface(
			i_cpu_ck,areset_n
			//outputs from the config registers
		);
      //need to add one more interface 


		dfi5_if dfi_ch0_if(i_cpu_ck, areset_n);
		dfi5_if dfi_ch1_if(i_cpu_ck, areset_n);
		mem_if  dram_if(i_dram_ck);

		logic        phy_ck0_t, phy_ck0_c;
		logic [13:0] phy_ca0;
		logic        phy_cai0;
		logic        phy_cs0_n, phy_cke0, phy_reset0_n;
		logic [31:0] phy_dq0_out, phy_dq0_in;
		logic        phy_dq0_oe;
		logic [3:0]  phy_dqs0_t, phy_dqs0_c, phy_dm0;
		logic        phy_dqs0_oe;

		logic        phy_ck1_t, phy_ck1_c;
		logic [13:0] phy_ca1;
		logic        phy_cai1;
		logic        phy_cs1_n, phy_cke1, phy_reset1_n;
		logic [31:0] phy_dq1_out, phy_dq1_in;
		logic        phy_dq1_oe;
		logic [3:0]  phy_dqs1_t, phy_dqs1_c, phy_dm1;
		logic        phy_dqs1_oe;
		logic        dram_wr_valid0, dram_wr_valid1;
		logic [511:0] dram_wr_data0, dram_wr_data1;
		logic [63:0]  dram_wr_mask0, dram_wr_mask1;
		logic        dram_rd_valid0, dram_rd_valid1;
		logic [511:0] dram_rd_data0, dram_rd_data1;
		logic        dram_reset_n_pin;
		logic        dram_cs_init_done;
		logic [13:0] cai_decoded_ch0, cai_decoded_ch1;
		bit          cai_tb_seen_ch0, cai_tb_seen_ch1;

		logic        dut_awvalid, dut_awready;
		logic [31:0] dut_awaddr;
		logic [7:0]  dut_awid;
		logic [7:0]  dut_awlen;
		logic [2:0]  dut_awsize;
		logic [1:0]  dut_awburst;
		logic        dut_wvalid, dut_wready;
		logic [511:0] dut_wdata;
		logic [63:0]  dut_wstrb;
		logic        dut_wlast;
		logic [7:0]  dut_wid;
		logic        dut_bvalid, dut_bready;
		logic [7:0]  dut_bid;
		logic [1:0]  dut_bresp;
		logic        dut_arvalid, dut_arready;
		logic [31:0] dut_araddr;
		logic [7:0]  dut_arid;
		logic [7:0]  dut_arlen;
		logic [2:0]  dut_arsize;
		logic [1:0]  dut_arburst;
		logic        dut_rvalid, dut_rready;
		logic [511:0] dut_rdata;
		logic [7:0]  dut_rid;
		logic [1:0]  dut_rresp;
		logic        dut_rlast;

		initial dch = 1'b0;

		assign dram_if.ck_t    = {phy_ck1_t, phy_ck0_t};
		assign dram_if.ck_c    = {phy_ck1_c, phy_ck0_c};
		assign dram_if.ca      = {phy_ca1, phy_ca0};
		assign dram_if.cai     = {phy_cai1, phy_cai0};
		assign dram_reset_n_pin = areset_n & phy_reset0_n & phy_reset1_n;
		initial dram_cs_init_done = 1'b0;
		always @(negedge dram_reset_n_pin) dram_cs_init_done = 1'b0;
		always @(posedge dram_reset_n_pin) begin
			dram_cs_init_done = 1'b0;
			#25_000;
			dram_cs_init_done = 1'b1;
		end

		assign dram_if.cs_n    = dram_cs_init_done ? {phy_cs1_n, phy_cs0_n} : 2'b00;
		assign dram_if.cke     = phy_cke0 | phy_cke1;
		assign dram_if.reset_n = dram_reset_n_pin;
		assign dram_if.odt     = 1'b0;
		assign dram_if.dch     = dch;

		// Single-master channel presentation:
		// CH0 write drives lower 32b data and marks the inactive upper half with all 1s.
		// CH1 write drives upper 32b data and marks the inactive lower half with all 1s.
		assign dram_if.dq[31:0]   = phy_dq0_oe ? phy_dq0_out :
		                            phy_dq1_oe ? 32'hFFFF_FFFF : 32'bz;
		assign dram_if.dq[63:32]  = phy_dq1_oe ? phy_dq1_out :
		                            phy_dq0_oe ? 32'hFFFF_FFFF : 32'bz;
		assign dram_if.dqs_t[3:0] = phy_dqs0_oe ? phy_dqs0_t  : 4'bz;
		assign dram_if.dqs_c[3:0] = phy_dqs0_oe ? phy_dqs0_c  : 4'bz;
		assign dram_if.dqs_t[7:4] = phy_dqs1_oe ? phy_dqs1_t  : 4'bz;
		assign dram_if.dqs_c[7:4] = phy_dqs1_oe ? phy_dqs1_c  : 4'bz;
		assign dram_if.dmi[3:0]   = phy_dq0_oe  ? phy_dm0     : 4'bz;
		assign dram_if.dmi[7:4]   = phy_dq1_oe  ? phy_dm1     : 4'bz;

		assign phy_dq0_in = dram_if.dq[31:0];
		assign phy_dq1_in = dram_if.dq[63:32];
		assign cai_decoded_ch0 = dram_if.cai[0] ? ~dram_if.ca[13:0]  : dram_if.ca[13:0];
		assign cai_decoded_ch1 = dram_if.cai[1] ? ~dram_if.ca[27:14] : dram_if.ca[27:14];

		function automatic [3:0] tb_count_ca_ones(input logic [13:0] ca_word);
			logic [3:0] count;
			begin
				count = '0;
				for (int b = 0; b < 14; b++) begin
					if (ca_word[b] === 1'b1)
						count = count + 1'b1;
				end
				tb_count_ca_ones = count;
			end
		endfunction

		always @(posedge i_dram_ck) begin
			if (areset_n) begin
				if (dram_cs_init_done && !dram_if.cs_n[0] &&
				    !$isunknown({dram_if.cai[0], dram_if.ca[13:0]}) &&
				    (dram_if.cai[0] !== (tb_count_ca_ones(cai_decoded_ch0) > 4'd7))) begin
					$error("[CAI TB][CH0] FAIL t=%0t tx_ca=%014b cai=%0b decoded_ca=%014b ones=%0d",
					       $time, dram_if.ca[13:0], dram_if.cai[0],
					       cai_decoded_ch0, tb_count_ca_ones(cai_decoded_ch0));
				end
				if (dram_cs_init_done && !dram_if.cs_n[1] &&
				    !$isunknown({dram_if.cai[1], dram_if.ca[27:14]}) &&
				    (dram_if.cai[1] !== (tb_count_ca_ones(cai_decoded_ch1) > 4'd7))) begin
					$error("[CAI TB][CH1] FAIL t=%0t tx_ca=%014b cai=%0b decoded_ca=%014b ones=%0d",
					       $time, dram_if.ca[27:14], dram_if.cai[1],
					       cai_decoded_ch1, tb_count_ca_ones(cai_decoded_ch1));
				end
				if (!cai_tb_seen_ch0 && dram_cs_init_done && !dram_if.cs_n[0] && (dram_if.cai[0] === 1'b1) &&
				    !$isunknown({dram_if.cai[0], dram_if.ca[13:0]})) begin
					cai_tb_seen_ch0 = 1'b1;
					$display("[CAI TB][CH0] PASS t=%0t transmitted_ca=%014b CAI=1 restored_ca=%014b ones=%0d",
					         $time, dram_if.ca[13:0], cai_decoded_ch0,
					         tb_count_ca_ones(cai_decoded_ch0));
				end
				if (!cai_tb_seen_ch1 && dram_cs_init_done && !dram_if.cs_n[1] && (dram_if.cai[1] === 1'b1) &&
				    !$isunknown({dram_if.cai[1], dram_if.ca[27:14]})) begin
					cai_tb_seen_ch1 = 1'b1;
					$display("[CAI TB][CH1] PASS t=%0t transmitted_ca=%014b CAI=1 restored_ca=%014b ones=%0d",
					         $time, dram_if.ca[27:14], cai_decoded_ch1,
					         tb_count_ca_ones(cai_decoded_ch1));
				end
			end
		end

		axi64_to_dut512_bridge u_axi_bridge (
			.clk       (i_cpu_ck),
			.rst_n     (areset_n),
			.s_awvalid (axi_pcie_intf.awvalid),
			.s_awready (axi_pcie_intf.awready),
			.s_awaddr  (axi_pcie_intf.awaddr),
			.s_awid    (axi_pcie_intf.awid),
			.s_awlen   (axi_pcie_intf.awlen),
			.s_awsize  (axi_pcie_intf.awsize),
			.s_awburst (axi_pcie_intf.awburst),
			.s_wvalid  (axi_pcie_intf.wvalid),
			.s_wready  (axi_pcie_intf.wready),
			.s_wdata   (axi_pcie_intf.wdata),
			.s_wstrb   (axi_pcie_intf.wstrb),
			.s_wlast   (axi_pcie_intf.wlast),
			.s_wid     (axi_pcie_intf.wid),
			.s_bvalid  (axi_pcie_intf.bvalid),
			.s_bready  (axi_pcie_intf.bready),
			.s_bid     (axi_pcie_intf.bid),
			.s_bresp   (axi_pcie_intf.bresp),
			.s_arvalid (axi_pcie_intf.arvalid),
			.s_arready (axi_pcie_intf.arready),
			.s_araddr  (axi_pcie_intf.araddr),
			.s_arid    (axi_pcie_intf.arid),
			.s_arlen   (axi_pcie_intf.arlen),
			.s_arsize  (axi_pcie_intf.arsize),
			.s_arburst (axi_pcie_intf.arburst),
			.s_rvalid  (axi_pcie_intf.rvalid),
			.s_rready  (axi_pcie_intf.rready),
			.s_rdata   (axi_pcie_intf.rdata),
			.s_rid     (axi_pcie_intf.rid),
			.s_rresp   (axi_pcie_intf.rresp),
			.s_rlast   (axi_pcie_intf.rlast),
			.m_awvalid (dut_awvalid),
			.m_awready (dut_awready),
			.m_awaddr  (dut_awaddr),
			.m_awid    (dut_awid),
			.m_awlen   (dut_awlen),
			.m_awsize  (dut_awsize),
			.m_awburst (dut_awburst),
			.m_wvalid  (dut_wvalid),
			.m_wready  (dut_wready),
			.m_wdata   (dut_wdata),
			.m_wstrb   (dut_wstrb),
			.m_wlast   (dut_wlast),
			.m_wid     (dut_wid),
			.m_bvalid  (dut_bvalid),
			.m_bready  (dut_bready),
			.m_bid     (dut_bid),
			.m_bresp   (dut_bresp),
			.m_arvalid (dut_arvalid),
			.m_arready (dut_arready),
			.m_araddr  (dut_araddr),
			.m_arid    (dut_arid),
			.m_arlen   (dut_arlen),
			.m_arsize  (dut_arsize),
			.m_arburst (dut_arburst),
			.m_rvalid  (dut_rvalid),
			.m_rready  (dut_rready),
			.m_rdata   (dut_rdata),
			.m_rid     (dut_rid),
			.m_rresp   (dut_rresp),
			.m_rlast   (dut_rlast)
		);

		ddr5_ctrl_top u_dut (
			.clk(i_cpu_ck), .rst_n(areset_n), .dch(dch),
			// AXI3
		//Write address channel
		.s_awvalid(dut_awvalid), .s_awready(dut_awready),
		.s_awaddr (dut_awaddr),  .s_awid   (dut_awid[3:0]),
		.s_awlen  (dut_awlen[3:0]),   .s_awsize (dut_awsize),
		.s_awburst(dut_awburst),
		//Write data channel
		.s_wvalid (dut_wvalid),  .s_wready (dut_wready),
		.s_wdata  (dut_wdata),   .s_wstrb  (dut_wstrb),
		.s_wlast  (dut_wlast),   .s_wid    (dut_wid[3:0]),

		//Write response channel	
		.s_bvalid (dut_bvalid),  .s_bready (dut_bready),
		.s_bid    (dut_bid[3:0]),     .s_bresp  (dut_bresp),

		//Read address channel
		.s_arvalid(dut_arvalid), .s_arready(dut_arready),
		.s_araddr (dut_araddr),  .s_arid   (dut_arid[3:0]),
		.s_arlen  (dut_arlen[3:0]),   .s_arsize (dut_arsize),
		.s_arburst(dut_arburst),

		//Read data channel
		.s_rvalid (dut_rvalid),  .s_rready (dut_rready),
		.s_rdata  (dut_rdata),   .s_rid    (dut_rid[3:0]),
		.s_rresp  (dut_rresp),   .s_rlast  (dut_rlast),
    		// DFI control
    	//	.dfi_ch0_ca_rise_p   (dfi_if.ch0_ca_rise_p),
    	//	.dfi_ch0_ca_fall_p   (dfi_if.ch0_ca_fall_p),
    	//	.dfi_ch0_cs_n_p      (dfi_if.ch0_cs_n_p),
    	//	.dfi_ch1_ca_rise_p   (dfi_if.ch1_ca_rise_p),
    	//	.dfi_ch1_ca_fall_p   (dfi_if.ch1_ca_fall_p),
    	//	.dfi_ch1_cs_n_p      (dfi_if.ch1_cs_n_p),
    	//	.dfi_cke             (dfi_if.dfi_cke),
    	//	.dfi_reset_n         (dfi_if.dfi_reset_n),
    		// DFI write data
    	//	.dfi_ch0_wrdata_p    (dfi_if.ch0_wrdata_p),
   	//	.dfi_ch0_wrdm_p      (dfi_if.ch0_wrdm_p),
    	//	.dfi_ch0_wrdata_en_p (dfi_if.ch0_wrdata_en_p),
    	//	.dfi_ch1_wrdata_p    (dfi_if.ch1_wrdata_p),
    	//	.dfi_ch1_wrdm_p      (dfi_if.ch1_wrdm_p),
    	//	.dfi_ch1_wrdata_en_p (dfi_if.ch1_wrdata_en_p),
    		// DFI read data
    	//	.dfi_ch0_rddata_p    (dfi_if.ch0_rddata_p),
    	//	.dfi_ch0_rddata_vld_p(dfi_if.ch0_rddata_vld_p),
    	//	.dfi_ch1_rddata_p    (dfi_if.ch1_rddata_p),
    	//	.dfi_ch1_rddata_vld_p(dfi_if.ch1_rddata_vld_p),
    	//	.dfi_ctrlupd_req     (dfi_if.ctrlupd_req),
    	//	.dfi_ctrlupd_ack     (dfi_if.ctrlupd_ack),
    	//	.init_done           (init_done_sig)

		.dfi_ch0(dfi_ch0_if),
		.dfi_ch1(dfi_ch1_if)
  	);	

		ddr5_phy u_phy (
			.ctrl_clk   (i_cpu_ck),
			.dram_clk   (i_dram_ck),
			.ctrl_rst_n (areset_n),
			.dfi_ch0    (dfi_ch0_if),
			.dfi_ch1    (dfi_ch1_if),

			.ck0_t      (phy_ck0_t),
			.ck0_c      (phy_ck0_c),
			.ca0        (phy_ca0),
			.cai0       (phy_cai0),
			.cs0_n      (phy_cs0_n),
			.cke0       (phy_cke0),
			.reset0_n   (phy_reset0_n),
			.dq0_out    (phy_dq0_out),
			.dq0_in     (phy_dq0_in),
			.dq0_oe     (phy_dq0_oe),
			.dqs0_t     (phy_dqs0_t),
			.dqs0_c     (phy_dqs0_c),
			.dqs0_oe    (phy_dqs0_oe),
			.dm0        (phy_dm0),
			.dram_wr_valid0(dram_wr_valid0),
			.dram_wr_data0 (dram_wr_data0),
			.dram_wr_mask0 (dram_wr_mask0),
			.dram_rd_valid0(dram_rd_valid0),
			.dram_rd_data0 (dram_rd_data0),

			.ck1_t      (phy_ck1_t),
			.ck1_c      (phy_ck1_c),
			.ca1        (phy_ca1),
			.cai1       (phy_cai1),
			.cs1_n      (phy_cs1_n),
			.cke1       (phy_cke1),
			.reset1_n   (phy_reset1_n),
			.dq1_out    (phy_dq1_out),
			.dq1_in     (phy_dq1_in),
			.dq1_oe     (phy_dq1_oe),
			.dqs1_t     (phy_dqs1_t),
			.dqs1_c     (phy_dqs1_c),
			.dqs1_oe    (phy_dqs1_oe),
			.dm1        (phy_dm1),
			.dram_wr_valid1(dram_wr_valid1),
			.dram_wr_data1 (dram_wr_data1),
			.dram_wr_mask1 (dram_wr_mask1),
			.dram_rd_valid1(dram_rd_valid1),
			.dram_rd_data1 (dram_rd_data1)
		);

		ddr5 u_dram (
			.dram_if  (dram_if),
			.rd_valid0(dram_rd_valid0),
			.rd_data0 (dram_rd_data0),
			.rd_valid1(dram_rd_valid1),
			.rd_data1 (dram_rd_data1)
		);

	
	initial begin
		uvm_config_db#(virtual axi_pcie_intf#(64,32,4,8,10000,4))::set(null,"*","pvif",axi_pcie_intf);
		uvm_config_db#(virtual axi_cfg_intf)::set(null,"*","pvif",axi_cfg_interface);
		uvm_config_db#(bit )::set(null,"*","verbose",verbose);
		//to do set the mem_if
		//set the verbose
		//set the enable_checks
		//one more interface (cfg register)
    	uvm_config_db#(bit)::set(null,"*","order",out_of_order);
    	uvm_config_db#(bit)::set(null,"*","overlap",overlapping);
		run_test();
	end


endmodule

module axi64_to_dut512_bridge (
	input  logic        clk,
	input  logic        rst_n,
	input  logic        s_awvalid,
	output logic        s_awready,
	input  logic [31:0] s_awaddr,
	input  logic [3:0]  s_awid,
	input  logic [3:0]  s_awlen,
	input  logic [2:0]  s_awsize,
	input  logic [1:0]  s_awburst,
	input  logic        s_wvalid,
	output logic        s_wready,
	input  logic [63:0] s_wdata,
	input  logic [7:0]  s_wstrb,
	input  logic        s_wlast,
	input  logic [3:0]  s_wid,
	output logic        s_bvalid,
	input  logic        s_bready,
	output logic [3:0]  s_bid,
	output logic [1:0]  s_bresp,
	input  logic        s_arvalid,
	output logic        s_arready,
	input  logic [31:0] s_araddr,
	input  logic [3:0]  s_arid,
	input  logic [3:0]  s_arlen,
	input  logic [2:0]  s_arsize,
	input  logic [1:0]  s_arburst,
	output logic        s_rvalid,
	input  logic        s_rready,
	output logic [63:0] s_rdata,
	output logic [3:0]  s_rid,
	output logic [1:0]  s_rresp,
	output logic        s_rlast,
	output logic        m_awvalid,
	input  logic        m_awready,
	output logic [31:0] m_awaddr,
	output logic [7:0]  m_awid,
	output logic [7:0]  m_awlen,
	output logic [2:0]  m_awsize,
	output logic [1:0]  m_awburst,
	output logic        m_wvalid,
	input  logic        m_wready,
	output logic [511:0] m_wdata,
	output logic [63:0] m_wstrb,
	output logic        m_wlast,
	output logic [7:0]  m_wid,
	input  logic        m_bvalid,
	output logic        m_bready,
	input  logic [7:0]  m_bid,
	input  logic [1:0]  m_bresp,
	output logic        m_arvalid,
	input  logic        m_arready,
	output logic [31:0] m_araddr,
	output logic [7:0]  m_arid,
	output logic [7:0]  m_arlen,
	output logic [2:0]  m_arsize,
	output logic [1:0]  m_arburst,
	input  logic        m_rvalid,
	output logic        m_rready,
	input  logic [511:0] m_rdata,
	input  logic [7:0]  m_rid,
	input  logic [1:0]  m_rresp,
	input  logic        m_rlast
);
	logic        wr_active;
	logic [31:0] wr_addr;
	logic [3:0]  wr_id;
	logic [3:0]  wr_len;
	logic [2:0]  wr_size;
	logic [1:0]  wr_burst;
	logic [2:0]  wr_count;
	logic [511:0] pack_data;
	logic [63:0]  pack_strb;
	logic        send_wr;
	logic        aw_sent;
	logic        w_sent;
	logic        aw_wait_release;
	logic        b_hold;
	logic [3:0]  b_id_hold;
	logic [1:0]  b_resp_hold;

	assign s_awready = !wr_active && !send_wr && !aw_wait_release;
	assign s_wready  = wr_active && !send_wr;
	assign m_awvalid = send_wr && !aw_sent;
	assign m_wvalid  = send_wr && !w_sent;
	assign m_awaddr  = wr_addr;
	assign m_awid    = {4'b0, wr_id};
	assign m_awlen   = 8'd0;
	assign m_awsize  = 3'd6;
	assign m_awburst = wr_burst;
	assign m_wdata   = pack_data;
	assign m_wstrb   = pack_strb;
	assign m_wlast   = 1'b1;
	assign m_wid     = {4'b0, wr_id};
	assign m_bready  = !b_hold;
	assign s_bvalid  = b_hold;
	assign s_bid     = b_id_hold;
	assign s_bresp   = b_resp_hold;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			wr_active <= 1'b0;
			wr_addr <= '0;
			wr_id <= '0;
			wr_len <= '0;
			wr_size <= '0;
			wr_burst <= '0;
			wr_count <= '0;
			pack_data <= '0;
			pack_strb <= '0;
			send_wr <= 1'b0;
			aw_sent <= 1'b0;
			w_sent <= 1'b0;
			aw_wait_release <= 1'b0;
			b_hold <= 1'b0;
			b_id_hold <= '0;
			b_resp_hold <= '0;
		end else begin
			if (!s_awvalid) begin
				aw_wait_release <= 1'b0;
			end

			if (s_awvalid && s_awready) begin
				wr_active <= 1'b1;
				aw_wait_release <= 1'b1;
				wr_addr <= s_awaddr;
				wr_id <= s_awid;
				wr_len <= s_awlen;
				wr_size <= s_awsize;
				wr_burst <= s_awburst;
				wr_count <= 3'd0;
				pack_data <= '0;
				pack_strb <= '0;
				aw_sent <= 1'b0;
				w_sent <= 1'b0;
			end

			if (s_wvalid && s_wready) begin
				pack_data[wr_count*64 +: 64] <= s_wdata;
				pack_strb[wr_count*8 +: 8] <= s_wstrb;
				if (wr_count == wr_len[2:0] || s_wlast || wr_count == 3'd7) begin
					send_wr <= 1'b1;
					wr_active <= 1'b0;
				end else begin
					wr_count <= wr_count + 3'd1;
				end
			end

			if (m_awvalid && m_awready) begin
				aw_sent <= 1'b1;
			end

			if (m_wvalid && m_wready) begin
				w_sent <= 1'b1;
			end

			if (send_wr &&
			    ((aw_sent || (m_awvalid && m_awready)) &&
			     (w_sent  || (m_wvalid  && m_wready)))) begin
				send_wr <= 1'b0;
			end

			if (m_bvalid && m_bready) begin
				b_hold <= 1'b1;
				b_id_hold <= m_bid[3:0];
				b_resp_hold <= m_bresp;
			end else if (s_bvalid && s_bready) begin
				b_hold <= 1'b0;
			end
		end
	end

	logic        rd_busy;
	logic [3:0]  rd_id;
	logic [3:0]  rd_len;
	logic [2:0]  rd_count;
	logic [511:0] rd_pack_data;
	logic [1:0]  rd_resp;

	assign s_arready = !rd_busy && !m_arvalid;
	assign m_araddr  = s_araddr;
	assign m_arid    = {4'b0, s_arid};
	assign m_arlen   = 8'd0;
	assign m_arsize  = 3'd6;
	assign m_arburst = s_arburst;
	assign m_rready  = rd_busy && !s_rvalid;
	assign s_rvalid  = rd_busy && (rd_pack_data !== 512'bx);
	assign s_rdata   = rd_pack_data[rd_count*64 +: 64];
	assign s_rid     = rd_id;
	assign s_rresp   = rd_resp;
	assign s_rlast   = (rd_count == rd_len[2:0]);

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			m_arvalid <= 1'b0;
			rd_busy <= 1'b0;
			rd_id <= '0;
			rd_len <= '0;
			rd_count <= '0;
			rd_pack_data <= 'x;
			rd_resp <= '0;
		end else begin
			if (s_arvalid && s_arready) begin
				m_arvalid <= 1'b1;
				rd_busy <= 1'b1;
				rd_id <= s_arid;
				rd_len <= s_arlen;
				rd_count <= 3'd0;
				rd_pack_data <= 'x;
			end

			if (m_arvalid && m_arready) begin
				m_arvalid <= 1'b0;
			end

			if (m_rvalid && m_rready) begin
				rd_pack_data <= m_rdata;
				rd_resp <= m_rresp;
			end

			if (s_rvalid && s_rready) begin
				if (s_rlast) begin
					rd_busy <= 1'b0;
					rd_pack_data <= 'x;
				end else begin
					rd_count <= rd_count + 3'd1;
				end
			end
		end
	end
endmodule
