// =============================================================
// ddr5_refresh_engine.sv
// DDR5 Refresh Engine
//
// Policy (JESD79-5B):
//   • Tracks tREFI interval counter (T_REFI_C ctrl cycles)
//   • Maintains postpone credit counter (max 8)
//   • Supports REFab (all-bank, tRFC1) and REFpb (per-bank, tRFC2)
//   • Round-robin bank selector for REFpb
//   • Generates soft (early) and hard (urgent) refresh requests
//
// Credit model:
//   Each tREFI tick without a refresh issued increments credit.
//   Scheduler may postpone up to REF_MAX_POST (8) refreshes.
//   credit==REF_MAX_POST → urgent flag forces immediate issue.
//
// tRFC timer:
//   After scheduler acknowledges (ref_ack), starts RFC countdown.
//   rfc_busy blocks all normal transactions until RFC expires.
// =============================================================

`timescale 1ns/1ps

import ddr5_pkg::*;

module ddr5_refresh_engine (
  input  logic       clk,
  input  logic       rst_n,

  // Configuration (static after init_done)
  input  logic       use_pbref,    // 0=REFab, 1=REFpb

  // Refresh request to scheduler
  output ref_req_t   ref_req,

  // Scheduler acknowledges and begins issuing refresh
  input  logic       ref_ack,

  // Scheduler signals RFC period complete (tRFC expired)
  input  logic       ref_done,

  // RFC busy signal (blocks normal traffic)
  output logic       rfc_busy,

  // Debug / coverage
  output logic [3:0] credit_cnt,
  output logic [3:0] pb_bank_idx   // current per-bank target (bg*4+ba)
);

  // -----------------------------------------------------------
  // tREFI interval counter
  // -----------------------------------------------------------
  logic [13:0] refi_cnt;
  logic        refi_pulse;       // fires every tREFI_C cycles

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) refi_cnt <= '0;
    else        refi_cnt <= (refi_cnt == T_REFI_C[13:0] - 1)
                            ? '0 : refi_cnt + 1'b1;
  end

  assign refi_pulse = (refi_cnt == T_REFI_C[13:0] - 1);

  // -----------------------------------------------------------
  // Credit counter
  // -----------------------------------------------------------
  logic [3:0] credit;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      credit <= '0;
    end else begin
      unique case ({refi_pulse, ref_ack})
        2'b10: credit <= (credit < REF_MAX_POST[3:0]) ? credit + 1'b1 : credit;
        2'b01: credit <= (credit > 0)                 ? credit - 1'b1 : credit;
        2'b11: credit <= credit;   // pulse + ack same cycle: neutral
        default: ;
      endcase
    end
  end

  assign credit_cnt = credit;

  // -----------------------------------------------------------
  // Per-bank round-robin selector (for REFpb)
  // -----------------------------------------------------------
  logic [1:0] pb_bg;   // bank-group pointer
  logic [1:0] pb_ba;   // bank pointer

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pb_bg <= '0;
      pb_ba <= '0;
    end else if (ref_ack) begin
      if (use_pbref) begin
        // Advance to next bank
        if (pb_ba == 2'd3) begin
          pb_ba <= '0;
          pb_bg <= pb_bg + 1'b1;
        end else begin
          pb_ba <= pb_ba + 1'b1;
        end
      end else begin
        // REFab: reset round-robin after each all-bank refresh
        pb_bg <= '0;
        pb_ba <= '0;
      end
    end
  end

  assign pb_bank_idx = {pb_bg, pb_ba};

  // -----------------------------------------------------------
  // tRFC timer
  // -----------------------------------------------------------
  logic [8:0] rfc_cnt;
  logic [8:0] rfc_limit;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rfc_busy  <= 1'b0;
      rfc_cnt   <= '0;
      rfc_limit <= '0;
    end else if (ref_ack && !rfc_busy) begin
      rfc_busy  <= 1'b1;
      rfc_cnt   <= '0;
      // REFab → tRFC1_C, REFpb → tRFC2_C
      rfc_limit <= ref_req.is_ab ? T_RFC1_C[8:0] : T_RFC2_C[8:0];
    end else if (rfc_busy) begin
      rfc_cnt  <= rfc_cnt + 1'b1;
      if (rfc_cnt >= rfc_limit - 1) begin
        rfc_busy <= 1'b0;
        rfc_cnt  <= '0;
      end
    end
  end

  // -----------------------------------------------------------
  // Refresh request output
  // -----------------------------------------------------------
  // Soft request: once half the tREFI window has passed or credit > 0
  logic soft_req;
  assign soft_req = (refi_cnt >= (T_REFI_C[13:0] >> 1)) || (credit > 0);

  assign ref_req.valid  = soft_req && !rfc_busy;
  assign ref_req.urgent = (credit == REF_MAX_POST[3:0]) && !rfc_busy;
  assign ref_req.is_ab  = ~use_pbref;
  assign ref_req.bg     = pb_bg;
  assign ref_req.ba     = pb_ba;

endmodule : ddr5_refresh_engine
