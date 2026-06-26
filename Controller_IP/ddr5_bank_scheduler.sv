// =============================================================
// ddr5_bank_scheduler.sv  (FIXED v2)
// Fixes:
//   1. No automatic variables inside always_ff
//   2. PRE → SCH_PRECLOSE (tRP wait) → ACT → SCH_ACTIVATE
//      (tRCD wait) → CAS   [was PRE → SCH_ACTIVATE, skipping tRP]
// =============================================================
`timescale 1ns/1ps
import ddr5_pkg::*;

module ddr5_bank_scheduler (
  input  logic clk, input logic rst_n,

  input  logic                   req_valid,
  output logic                   req_ready,
  input  logic                   req_is_wr,
  input  logic [BG_BITS-1:0]     req_bg,
  input  logic [BA_BITS-1:0]     req_ba,
  input  logic [ROW_BITS-1:0]    req_row,
  input  logic [COL_BITS-1:0]    req_col,
  input  logic [AXI_ID_W-1:0]    req_id,

  input  ref_req_t   ref_req,
  output logic       ref_ack,
  output logic       ref_done,
  output cmd_req_t   cmd_out,
  output logic       rd_en,
  output logic [AXI_ID_W-1:0] rd_id
);

  // ---- Per-bank state ----------------------------------------
  typedef struct packed {
    logic                open;
    logic [ROW_BITS-1:0] open_row;
    logic [5:0]          cnt_rcd;
    logic [5:0]          cnt_ras;
    logic [5:0]          cnt_rp;
    logic [6:0]          cnt_rc;
    logic [5:0]          cnt_wr;
    logic [3:0]          cnt_rtp;
  } bank_st_t;

  bank_st_t banks [NUM_BANKS];
  logic pre_pending[NUM_BANKS];
  logic all_banks_closed;

  // ---- Flat bank index (wire, not automatic inside always_ff) --
  logic [3:0] b_idx;
  assign b_idx = {req_bg, req_ba};
  logic                 pend_valid;
logic                 pend_is_wr;
logic [BG_BITS-1:0]   pend_bg;
logic [BA_BITS-1:0]   pend_ba;
logic [ROW_BITS-1:0]  pend_row;
logic [COL_BITS-1:0]  pend_col;
logic [AXI_ID_W-1:0]  pend_id;

  logic [3:0] pend_bidx;
assign pend_bidx = {pend_bg, pend_ba};
logic wait_req_drop;
logic [3:0] close_bidx;
logic [BG_BITS-1:0] close_bg;
logic [BA_BITS-1:0] close_ba;
logic [5:0] close_wait_cnt;

  // ---- Shared bus counters ------------------------------------
  logic [3:0] cnt_rrd, cnt_ccd;
  logic [5:0] cnt_wtr;
  logic [1:0] last_act_bg, last_cas_bg;
  logic       last_was_wr;
  localparam int WR_TO_RD_SAFE_C = CWL_C + T_WTR_L_C + 16;
  localparam int POST_WR_CLOSE_C = CWL_C + 15 + BL + 8;
  localparam int POST_RD_CLOSE_C = CL_C  + BL + 8;

  // ---- FAW shift register + popcount --------------------------
  logic [T_FAW_C-1:0] faw_sr;
  logic [3:0]         faw_cnt;
  logic               faw_full;
  always_comb begin
    faw_cnt = '0;
    for (int i=0;i<T_FAW_C;i++) faw_cnt = faw_cnt + {3'b0,faw_sr[i]};
    faw_full = (faw_cnt >= 4'd4);
  end

  // ---- RFC timer ----------------------------------------------
  logic [8:0] rfc_cnt, rfc_limit;
  logic       rfc_busy;

  // ---- Timing checks (combinational) -------------------------
  logic rcd_ok,ras_ok,rp_ok,rc_ok,wr_ok,rtp_ok;
  logic rrd_ok,ccd_ok,wtr_ok,cas_ok;
  always_comb begin
    rcd_ok = (banks[pend_bidx].cnt_rcd == '0);
    ras_ok = (banks[pend_bidx].cnt_ras == '0);
    rp_ok  = (banks[pend_bidx].cnt_rp  == '0);
    rc_ok  = (banks[pend_bidx].cnt_rc  == '0);
    wr_ok  = (banks[pend_bidx].cnt_wr  == '0);
    rtp_ok = (banks[pend_bidx].cnt_rtp == '0);
    rrd_ok = (cnt_rrd == '0);
    ccd_ok = (cnt_ccd == '0);
    wtr_ok = (cnt_wtr == '0) || !last_was_wr;
    cas_ok = rcd_ok && ccd_ok && (pend_is_wr ? 1'b1 : wtr_ok);
  end

  // ---- FSM ---------------------------------------------------
  typedef enum logic [2:0] {
    SCH_IDLE=3'd0, SCH_PRECLOSE=3'd1,
    SCH_ACTIVATE=3'd2, SCH_RFCWAIT=3'd3,
    SCH_POSTCLOSE=3'd4, SCH_CLOSE_RP=3'd5
  } sch_st_e;
  sch_st_e sch_state;

  // Macro to issue CAS (avoids code duplication inline)
  `define ISSUE_CAS \
    cmd_out.valid <= 1'b1; \
    cmd_out.cmd   <= pend_is_wr ? CMD_WR : CMD_RD; \
    cmd_out.bg    <= pend_bg; cmd_out.ba <= pend_ba; \
    cmd_out.col   <= pend_col; cmd_out.tid <= pend_id; \
    req_ready     <= 1'b1; \
    rd_en         <= !pend_is_wr; rd_id <= pend_id; \
    last_cas_bg   <= pend_bg; last_was_wr <= pend_is_wr; \
    pend_valid <= 1'b0; \
    cnt_ccd <= (pend_bg==last_cas_bg) ? T_CCD_L_C[3:0]:T_CCD_S_C[3:0]; \
    if (pend_is_wr) begin \
      banks[pend_bidx].cnt_wr <= T_WR_C[5:0]; \
      cnt_wtr                 <= WR_TO_RD_SAFE_C[5:0]; \
    end else banks[pend_bidx].cnt_rtp <= T_RTP_C[3:0];

  `define ISSUE_ACT \
    cmd_out.valid         <= 1'b1; \
    cmd_out.cmd           <= CMD_ACT; \
    cmd_out.bg            <= pend_bg; cmd_out.ba <= pend_ba; \
    cmd_out.row           <= pend_row; \
    banks[pend_bidx].open     <= 1'b1; \
      banks[pend_bidx].open_row <= pend_row; \
    banks[pend_bidx].cnt_rcd  <= T_RCD_C[5:0]; \
    banks[pend_bidx].cnt_ras  <= T_RAS_C[5:0]; \
    banks[pend_bidx].cnt_rc   <= T_RC_C[6:0]; \
    last_act_bg           <= pend_bg; \
    cnt_rrd <= (pend_bg==last_act_bg)?T_RRD_L_C[3:0]:T_RRD_S_C[3:0]; \
    faw_sr[T_FAW_C-1]     <= 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
	    for (int i=0;i<NUM_BANKS;i++)begin
		    banks[i]<='0;
		    pre_pending[i] <= 1'b0;
	    end
      cnt_rrd<='0; cnt_ccd<='0; cnt_wtr<='0;
      last_act_bg<='0; last_cas_bg<='0; last_was_wr<=1'b0;
      faw_sr<='0; rfc_cnt<='0; rfc_limit<='0; rfc_busy<=1'b0;
      sch_state<=SCH_IDLE;
      ref_ack<=1'b0; ref_done<=1'b0; cmd_out<='0;
      req_ready<=1'b0; rd_en<=1'b0; rd_id<='0;
      pend_valid <= 1'b0;
wait_req_drop <= 1'b0;
pend_is_wr <= 1'b0;
pend_bg    <= '0;
pend_ba    <= '0;
pend_row   <= '0;
pend_col   <= '0;
pend_id    <= '0;
close_bidx <= '0;
close_bg <= '0;
close_ba <= '0;
close_wait_cnt <= '0;
    end else begin
      ref_ack<=1'b0; ref_done<=1'b0;
      req_ready<=1'b0; rd_en<=1'b0; cmd_out<='0;

      if (!req_valid)
        wait_req_drop <= 1'b0;

      // Tick all bank timers
      for (int i=0;i<NUM_BANKS;i++) begin
        if(banks[i].cnt_rcd>0) banks[i].cnt_rcd<=banks[i].cnt_rcd-1;
        if(banks[i].cnt_ras>0) banks[i].cnt_ras<=banks[i].cnt_ras-1;
        if(banks[i].cnt_rp >0) banks[i].cnt_rp <=banks[i].cnt_rp -1;
        if(banks[i].cnt_rc >0) banks[i].cnt_rc <=banks[i].cnt_rc -1;
        if(banks[i].cnt_wr >0) banks[i].cnt_wr <=banks[i].cnt_wr -1;
        if(banks[i].cnt_rtp>0) banks[i].cnt_rtp<=banks[i].cnt_rtp-1;
	if(pre_pending[i] &&
   banks[i].cnt_rp == 0)
begin
    banks[i].open <= 1'b0;
    pre_pending[i] <= 1'b0;
end
      end
      if(cnt_rrd>0) cnt_rrd<=cnt_rrd-1;
      if(cnt_ccd>0) cnt_ccd<=cnt_ccd-1;
      if(cnt_wtr>0) cnt_wtr<=cnt_wtr-1;
      faw_sr<={1'b0,faw_sr[T_FAW_C-1:1]};

      // RFC timer
      if (rfc_busy) begin
        rfc_cnt<=rfc_cnt+1;
        if (rfc_cnt>=rfc_limit-1) begin
          rfc_busy<=1'b0; rfc_cnt<='0; ref_done<=1'b1;
        end
      end

      unique case (sch_state)

        SCH_IDLE: begin
		if(req_valid && !pend_valid && !wait_req_drop) begin
    			pend_valid <= 1'b1;
    			pend_is_wr <= req_is_wr;
    			pend_bg    <= req_bg;
    			pend_ba    <= req_ba;
    			pend_row   <= req_row;
    			pend_col   <= req_col;
    			pend_id    <= req_id;
		end
          if (ref_req.valid && (ref_req.urgent || !req_valid) && all_banks_closed) begin
            ref_ack<=1'b1; rfc_busy<=1'b1; rfc_cnt<='0;
            rfc_limit<=ref_req.is_ab?T_RFC1_C[8:0]:T_RFC2_C[8:0];
            cmd_out.valid<=1'b1;
            cmd_out.cmd<=ref_req.is_ab?CMD_REFAB:CMD_REFPB;
            cmd_out.bg<=ref_req.bg; cmd_out.ba<=ref_req.ba;
            sch_state<=SCH_RFCWAIT;

          end else if (pend_valid && !rfc_busy) begin
            if (banks[pend_bidx].open && banks[pend_bidx].open_row==pend_row) begin
              // ROW HIT
              if (cas_ok) begin
                `ISSUE_CAS
                close_bidx <= pend_bidx;
                close_bg <= pend_bg;
                close_ba <= pend_ba;
                close_wait_cnt <= pend_is_wr ? POST_WR_CLOSE_C[5:0] : POST_RD_CLOSE_C[5:0];
                wait_req_drop <= req_valid;
                sch_state<=SCH_POSTCLOSE;
              end
            end else if (banks[pend_bidx].open) begin
              // ROW CONFLICT → PRE then wait tRP (SCH_PRECLOSE)
              if (ras_ok && wr_ok && rtp_ok) begin
                cmd_out.valid<=1'b1; cmd_out.cmd<=CMD_PRE;
                cmd_out.bg<=pend_bg; cmd_out.ba<=pend_ba;
                pre_pending[pend_bidx] <= 1'b1;
		banks[pend_bidx].cnt_rp <= T_RP_C[5:0];
                sch_state<=SCH_PRECLOSE;   // ← FIXED (was SCH_ACTIVATE)
              end
            end else begin
              // BANK CLOSED → ACT directly
              if (rp_ok && rc_ok && rrd_ok && !faw_full) begin
                `ISSUE_ACT
                sch_state<=SCH_ACTIVATE;
              end
            end
          end
        end

        // Wait tRP, then issue ACT
        SCH_PRECLOSE: begin
          if (rp_ok && rc_ok && rrd_ok && !faw_full) begin
            `ISSUE_ACT
            sch_state<=SCH_ACTIVATE;
          end
        end

        // Wait tRCD, then issue CAS
        SCH_ACTIVATE: begin
          if (cas_ok) begin
            `ISSUE_CAS
            close_bidx <= pend_bidx;
            close_bg <= pend_bg;
            close_ba <= pend_ba;
            close_wait_cnt <= pend_is_wr ? POST_WR_CLOSE_C[5:0] : POST_RD_CLOSE_C[5:0];
            wait_req_drop <= req_valid;
            sch_state<=SCH_POSTCLOSE;
          end
        end

        // Closed-page policy: wait until the full BL16 data window is over,
        // then close the row before allowing the next transaction.
        SCH_POSTCLOSE: begin
          if (close_wait_cnt > 0) begin
            close_wait_cnt <= close_wait_cnt - 1'b1;
          end else if (banks[close_bidx].open &&
                       banks[close_bidx].cnt_ras == 0 &&
                       banks[close_bidx].cnt_wr  == 0 &&
                       banks[close_bidx].cnt_rtp == 0) begin
            cmd_out.valid<=1'b1;
            cmd_out.cmd<=CMD_PRE;
            cmd_out.bg<=close_bg;
            cmd_out.ba<=close_ba;
            pre_pending[close_bidx] <= 1'b1;
            banks[close_bidx].cnt_rp <= T_RP_C[5:0];
            sch_state<=SCH_CLOSE_RP;
          end
        end

        SCH_CLOSE_RP: begin
          if (!pre_pending[close_bidx] && banks[close_bidx].cnt_rp == 0)
            sch_state<=SCH_IDLE;
        end

        SCH_RFCWAIT: begin
          if (!rfc_busy) sch_state<=SCH_IDLE;
        end

        default: sch_state<=SCH_IDLE;
      endcase
    end
  end

  always_comb begin
	all_banks_closed = 1;

	for(int i=0; i<NUM_BANKS; i=i+1)begin
		if(banks[i].open || pre_pending[i])begin
			all_banks_closed =0;
		end
	end	
  end

endmodule : ddr5_bank_scheduler
