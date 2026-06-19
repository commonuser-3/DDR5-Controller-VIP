// =============================================================
// ddr5_init_fsm.sv
// DDR5 UDIMM Initialization FSM  (JESD79-5B Section 4)
//
// Sequence:
//   S_IDLE     : wait until PHY IO cal done (start = dfi_phyupd_req from PHY)
//   S_RESET    : RESET_n=0, CKE=0 for T_PWRUP_C cycles
//   S_DEASSERT : RESET_n=1, CKE=0, hold 10 ctrl cycles
//   S_CKE_HIGH : CKE=1, wait T_XPR_C (tXPR = tRFC1 + 10)
//   S_ZQ_START : issue ZQCAL START command
//   S_ZQ_WAIT  : wait T_ZQCAL_C
//   S_ZQ_LATCH : issue ZQCAL LATCH command
//   S_ZQL_WAIT : wait T_ZQLAT_C
//   S_MRS      : issue MRS for MR0..MR6 sequentially
//   S_MRS_WAIT : inter-MRS gap (4 ctrl cycles)
//   S_DONE     : assert init_done, CKE=1 permanently
//
// After init_done both schedulers release from reset and
// normal traffic is accepted.
// =============================================================

`timescale 1ns/1ps

import ddr5_pkg::*;

module ddr5_init_fsm (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,

  // DFI direct outputs
  output logic       dfi_reset_n,
  output logic       dfi_cke,

  // Command to CA encoder (broadcast to both sub-channels)
  output cmd_req_t   init_cmd,

  // Status
  output logic       init_done
);

  // -----------------------------------------------------------
  // State encoding
  // -----------------------------------------------------------
  typedef enum logic [3:0] {
    S_RESET    = 4'h0,
    S_DEASSERT = 4'h1,
    S_CKE_HIGH = 4'h2,
    S_ZQ_START = 4'h3,
    S_ZQ_WAIT  = 4'h4,
    S_ZQ_LATCH = 4'h5,
    S_ZQL_WAIT = 4'h6,
    S_MRS      = 4'h7,
    S_MRS_WAIT = 4'h8,
    S_DONE     = 4'h9,
    S_IDLE     = 4'hA
  } init_state_e;

  init_state_e state, state_nxt;

  // Counter wide enough for T_PWRUP_C (~1.6M cycles)
  logic [20:0] cnt;
  logic [20:0] cnt_nxt;
  logic [2:0]  mr_idx, mr_idx_nxt;  // which MR to program

  // -----------------------------------------------------------
  // Timing limits per state
  // -----------------------------------------------------------
  localparam int CNT_PWRUP   = T_PWRUP_C - 1;   // ~1,600,000
  localparam int CNT_DEASSRT = 10 - 1;
  localparam int CNT_XPR     = T_XPR_C   - 1;   // 239
  localparam int CNT_ZQCAL   = T_ZQCAL_C - 1;   // 127
  localparam int CNT_ZQLAT   = T_ZQLAT_C - 1;   // 7
  localparam int CNT_MRSGAP  = 4 - 1;            // tMRS inter-gap

  // -----------------------------------------------------------
  // Sequential state register
  // -----------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      cnt     <= '0;
      mr_idx  <= '0;
    end else if (!start) begin
      state   <= S_IDLE;
      cnt     <= '0;
      mr_idx  <= '0;
    end else if (state == S_IDLE) begin
      state   <= S_RESET;
      cnt     <= '0;
      mr_idx  <= '0;
    end else begin
      state   <= state_nxt;
      cnt     <= cnt_nxt;
      mr_idx  <= mr_idx_nxt;
    end
  end

  // -----------------------------------------------------------
  // Next-state + output combinational logic
  // -----------------------------------------------------------
  always_comb begin
    // Default
    state_nxt   = state;
    cnt_nxt     = cnt + 1'b1;
    mr_idx_nxt  = mr_idx;
    dfi_reset_n = 1'b0;
    dfi_cke     = 1'b0;
    init_done   = 1'b0;

    init_cmd          = '0;
    init_cmd.valid    = 1'b0;
    init_cmd.cmd      = CMD_NOP;
    init_cmd.sub_ch   = 1'b0;   // broadcast: encoder drives both sub-ch

    unique case (state)

      // ---- Idle until PHY finishes IO cal (start = dfi_phyupd_req) ----
      S_IDLE: begin
        dfi_reset_n = 1'b0;
        dfi_cke     = 1'b0;
        cnt_nxt     = '0;
      end

      // ---- Hold RESET_n low --------------------------------
      S_RESET: begin
        dfi_reset_n = 1'b0;
        dfi_cke     = 1'b0;
        if (cnt == CNT_PWRUP[20:0]) begin
          state_nxt = S_DEASSERT;
          cnt_nxt   = '0;
        end
      end

      // ---- Release RESET_n, still CKE=0 -------------------
      S_DEASSERT: begin
        dfi_reset_n = 1'b1;
        dfi_cke     = 1'b0;
        if (cnt == CNT_DEASSRT[20:0]) begin
          state_nxt = S_CKE_HIGH;
          cnt_nxt   = '0;
        end
      end

      // ---- Raise CKE, wait tXPR ----------------------------
      S_CKE_HIGH: begin
        dfi_reset_n = 1'b1;
        dfi_cke     = 1'b1;
        if (cnt == CNT_XPR[20:0]) begin
          state_nxt = S_ZQ_START;
          cnt_nxt   = '0;
        end
      end

      // ---- Issue ZQCAL START -------------------------------
      S_ZQ_START: begin
        dfi_reset_n       = 1'b1;
        dfi_cke           = 1'b1;
        init_cmd.valid    = 1'b1;
        init_cmd.cmd      = CMD_ZQS;
        state_nxt         = S_ZQ_WAIT;
        cnt_nxt           = '0;
      end

      // ---- Wait tZQCAL ------------------------------------
      S_ZQ_WAIT: begin
        dfi_reset_n = 1'b1;
        dfi_cke     = 1'b1;
        if (cnt == CNT_ZQCAL[20:0]) begin
          state_nxt = S_ZQ_LATCH;
          cnt_nxt   = '0;
        end
      end

      // ---- Issue ZQCAL LATCH ------------------------------
      S_ZQ_LATCH: begin
        dfi_reset_n       = 1'b1;
        dfi_cke           = 1'b1;
        init_cmd.valid    = 1'b1;
        init_cmd.cmd      = CMD_ZQL;
        state_nxt         = S_ZQL_WAIT;
        cnt_nxt           = '0;
      end

      // ---- Wait tZQLAT ------------------------------------
      S_ZQL_WAIT: begin
        dfi_reset_n = 1'b1;
        dfi_cke     = 1'b1;
        if (cnt == CNT_ZQLAT[20:0]) begin
          state_nxt  = S_MRS;
          mr_idx_nxt = '0;
          cnt_nxt    = '0;
        end
      end

      // ---- Issue MRS (MR0..MR6) ---------------------------
      S_MRS: begin
        dfi_reset_n       = 1'b1;
        dfi_cke           = 1'b1;
        init_cmd.valid    = 1'b1;
        init_cmd.cmd      = CMD_MRS;
        init_cmd.mr_addr  = {5'h0, mr_idx};
        init_cmd.mr_op    = mrs_value({5'h0, mr_idx});
        state_nxt         = S_MRS_WAIT;
        cnt_nxt           = '0;
      end

      // ---- Inter-MRS gap ----------------------------------
      S_MRS_WAIT: begin
        dfi_reset_n = 1'b1;
        dfi_cke     = 1'b1;
        if (cnt == CNT_MRSGAP[20:0]) begin
          if (mr_idx == 3'd6) begin
            state_nxt = S_DONE;
          end else begin
            mr_idx_nxt = mr_idx + 1'b1;
            state_nxt  = S_MRS;
          end
          cnt_nxt = '0;
        end
      end

      // ---- Init complete ----------------------------------
      S_DONE: begin
        dfi_reset_n = 1'b1;
        dfi_cke     = 1'b1;
        init_done   = 1'b1;
        cnt_nxt     = cnt;   // stop counting
      end

      default: state_nxt = S_IDLE;

    endcase
  end

endmodule : ddr5_init_fsm
