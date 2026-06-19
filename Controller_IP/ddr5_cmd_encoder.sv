// =============================================================
// ddr5_cmd_encoder.sv
// DDR5 CA-bus command encoder
//
// Takes an internal cmd_req_t and produces a 4-phase DFI
// CA-bus output (rise/fall per DRAM clock, per sub-channel).
//
// DDR5 CA Encoding  (JESD79-5B Table 3/4):
// -----------------------------------------
// CA[13:0] is driven at every DRAM clock edge.
// CS_n=LOW qualifies the command (like a command strobe).
//
// NOP   : cs_n=1, CA=14'h3FFF
//
// In this integration the PHY forwards dfi_address_p[0..3] on successive
// dram_clk edges while CK_t toggles on those same edges. The DRAM model samples
// CA only on CK_t rising edges, so a DDR5 two-cycle command must use phases
// p0 and p2 (pkt[0].rise and pkt[1].rise), with CS_n low on both packets.
//
// PRE   : rise={4'b0100,bg,ba,6'h0}   fall=NOP       cs_n=0
// PREab : rise={4'b0110,10'h0}        fall=NOP       cs_n=0
// REFab : rise={4'b0010,10'h0}        fall=NOP       cs_n=0
// REFpb : rise={4'b0001,bg,ba,6'h0}  fall=NOP       cs_n=0
//
// RD/RDA (2 DRAM clocks):
//   rise0: {2'b10,rda,bg,ba,ap,col[9:4]}              cs_n=0
//   fall0: {4'h0,col[3:0],6'h0}                       cs_n=0
//
// WR/WRA (2 DRAM clocks):
//   rise0: {2'b11,wra,bg,ba,ap,col[9:4]}              cs_n=0
//   fall0: {4'h0,col[3:0],6'h0}                       cs_n=0
//
// MRS (2 DRAM clocks):
//   rise0: {4'b0111,mr_addr[7:0],2'h0}                cs_n=0
//   fall0: {mr_op[7:0],6'h0}                          cs_n=0
//
// ZQS  : rise={4'b0101,10'h0}        cs_n=0
// ZQL  : rise={4'b0101,10'h1}        cs_n=0
// SRE  : rise={4'b0011,10'h0}        cs_n=0
// PDE  : rise={4'b0011,10'h2}        cs_n=0
//
// At 1:4 DFI ratio each controller cycle covers 4 DRAM clocks
// (phases p0..p3). Each phase carries rise+fall.
// Commands are placed starting at p0 of the issuing cycle.
// =============================================================

`timescale 1ns/1ps

import ddr5_pkg::*;

module ddr5_cmd_encoder (
  input  logic       clk,
  input  logic       rst_n,

  // Command request from scheduler (one per controller cycle)
  input  cmd_req_t   req_ch0,   // sub-channel 0 command
  input  cmd_req_t   req_ch1,   // sub-channel 1 command

  // DFI 4-phase CA output per sub-channel
  output ca_pkt_t    ch0_dfi [DFI_PHASES],
  output ca_pkt_t    ch1_dfi [DFI_PHASES]
);

  // -----------------------------------------------------------
  // NOP packet constant
  // -----------------------------------------------------------
  localparam logic [DFI_CA_W-1:0] CA_NOP = 14'h3FFF;
  localparam ca_pkt_t PKT_NOP = '{rise: CA_NOP, fall: CA_NOP, cs_n: 1'b1};

  // -----------------------------------------------------------
  // Encode a single cmd_req_t into a 4-phase output array
  // -----------------------------------------------------------
  function automatic void encode_cmd(
    input  cmd_req_t req,
    output ca_pkt_t  phases [DFI_PHASES]
  );
    // Default: all phases NOP
    for (int i = 0; i < DFI_PHASES; i++) phases[i] = PKT_NOP;

    if (!req.valid) return;

    // Phase 0 is always the command slot
    phases[0].cs_n = 1'b0;

    unique case (req.cmd)

      // ---- ACT -------------------------------------------
      CMD_ACT: begin
        phases[0].rise = '0;
        phases[0].rise[1:0] = 2'b00;
        phases[0].rise[5:2] = req.row[3:0];
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = phases[0].rise;
        phases[1].cs_n = 1'b0;
        phases[1].rise = '0;
        phases[1].rise[11:0] = req.row[15:4];
        phases[1].rise[12]   = 1'b0;
        phases[1].fall = phases[1].rise;
      end

      // ---- PRE single bank --------------------------------
      CMD_PRE: begin
        phases[0].rise = '0;
        phases[0].rise[5:0] = 6'b101111;
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = CA_NOP;
      end

      // ---- PREab (all-bank precharge) ---------------------
      CMD_PREAB: begin
        phases[0].rise = '0;
        phases[0].rise[5:0] = 6'b001111;
        phases[0].rise[10] = 1'b0;
        phases[0].fall = CA_NOP;
      end

      // ---- REFab (all-bank refresh) -----------------------
      CMD_REFAB: begin
        phases[0].rise = '0;
        phases[0].rise[4:0] = 5'b10011;
        phases[0].rise[10] = 1'b0;
        phases[0].fall = CA_NOP;
      end

      // ---- REFpb (per-bank refresh) -----------------------
      CMD_REFPB: begin
        phases[0].rise = '0;
        phases[0].rise[4:0] = 5'b10011;
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = CA_NOP;
      end

      // ---- RD (read, no auto-precharge) -------------------
      CMD_RD: begin
        phases[0].rise = '0;
        phases[0].rise[3:0] = 4'b1101;
        phases[0].rise[4]   = 1'b1;
        phases[0].rise[5]   = 1'b0;
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = phases[0].rise;
        phases[1].cs_n = 1'b0;
        phases[1].rise = '0;
        phases[1].rise[8:1] = {1'b0, req.col[9:3]};
        phases[1].rise[10]  = 1'b1;
        phases[1].rise[0]   = 1'b1;
        phases[1].fall = phases[1].rise;
      end

      // ---- RDA (read + auto-precharge) --------------------
      CMD_RDA: begin
        phases[0].rise = '0;
        phases[0].rise[3:0] = 4'b1101;
        phases[0].rise[4]   = 1'b1;
        phases[0].rise[5]   = 1'b0;
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = phases[0].rise;
        phases[1].cs_n = 1'b0;
        phases[1].rise = '0;
        phases[1].rise[8:1] = {1'b0, req.col[9:3]};
        phases[1].rise[10]  = 1'b0;
        phases[1].rise[0]   = 1'b1;
        phases[1].fall = phases[1].rise;
      end

      // ---- WR (write, no auto-precharge) ------------------
      CMD_WR: begin
        phases[0].rise = '0;
        phases[0].rise[3:0] = 4'b1101;
        phases[0].rise[4]   = 1'b0;
        phases[0].rise[5]   = 1'b0;
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = phases[0].rise;
        phases[1].cs_n = 1'b0;
        phases[1].rise = '0;
        phases[1].rise[8:1] = {1'b0, req.col[9:3]};
        phases[1].rise[10]  = 1'b1;
        phases[1].rise[0]   = 1'b1;
        phases[1].fall = phases[1].rise;
      end

      // ---- WRA (write + auto-precharge) -------------------
      CMD_WRA: begin
        phases[0].rise = '0;
        phases[0].rise[3:0] = 4'b1101;
        phases[0].rise[4]   = 1'b0;
        phases[0].rise[5]   = 1'b0;
        phases[0].rise[9:6] = {req.bg[1:0], req.ba[1:0]};
        phases[0].fall = phases[0].rise;
        phases[1].cs_n = 1'b0;
        phases[1].rise = '0;
        phases[1].rise[8:1] = {1'b0, req.col[9:3]};
        phases[1].rise[10]  = 1'b0;
        phases[1].rise[0]   = 1'b1;
        phases[1].fall = phases[1].rise;
      end

      // ---- MRS (mode register set) ------------------------
      CMD_MRS: begin
        phases[0].rise = '0;
        phases[0].rise[4:0]  = 5'b00100;
        phases[0].rise[12:5] = req.mr_addr[7:0];
        phases[0].fall = phases[0].rise;
        phases[1].cs_n = 1'b0;
        phases[1].rise = '0;
        phases[1].rise[7:0] = req.mr_op[7:0];
        phases[1].fall = phases[1].rise;
      end

      // ---- ZQ Cal Start -----------------------------------
      CMD_ZQS: begin
        phases[0].rise = CA_NOP;
        phases[0].fall = CA_NOP;
      end

      // ---- ZQ Cal Latch -----------------------------------
      CMD_ZQL: begin
        phases[0].rise = CA_NOP;
        phases[0].fall = CA_NOP;
      end

      // ---- Self-Refresh Entry -----------------------------
      CMD_SRE: begin
        phases[0].rise = {4'b0011, 10'h000};
        phases[0].fall = CA_NOP;
      end

      // ---- Power-Down Entry -------------------------------
      CMD_PDE: begin
        phases[0].rise = {4'b0011, 10'h002};
        phases[0].fall = CA_NOP;
      end

      // ---- NOP / default ----------------------------------
      default: begin
        phases[0] = PKT_NOP;
      end

    endcase
  endfunction

  // -----------------------------------------------------------
  // Registered output pipeline (1 cycle)
  // -----------------------------------------------------------
  ca_pkt_t ch0_comb [DFI_PHASES];
  ca_pkt_t ch1_comb [DFI_PHASES];

  always_comb begin
    encode_cmd(req_ch0, ch0_comb);
    encode_cmd(req_ch1, ch1_comb);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DFI_PHASES; i++) begin
        ch0_dfi[i] <= PKT_NOP;
        ch1_dfi[i] <= PKT_NOP;
      end
    end else begin
      for (int i = 0; i < DFI_PHASES; i++) begin
        ch0_dfi[i] <= ch0_comb[i];
        ch1_dfi[i] <= ch1_comb[i];
      end
    end
  end

endmodule : ddr5_cmd_encoder
