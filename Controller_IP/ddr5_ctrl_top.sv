// =============================================================
// ddr5_ctrl_top.sv
//
// *** CHANGES FROM PREVIOUS VERSION — summary ***
//
//  [CHG-1] ddr5_cmd_encoder instantiated as u_enc (was inlined).
//          All inline helper functions (encode_ca_p0/p1, encode_cs_n,
//          manual always_comb encoder block) REMOVED.
//
//  [CHG-2] dfi_address_p[p] now mapped correctly from ca_pkt_t:
//            p0 ← ch_dfi_pkt[0].rise  (DRAM CK0 rising  edge CA)
//            p1 ← ch_dfi_pkt[0].fall  (DRAM CK0 falling edge CA)
//            p2 ← ch_dfi_pkt[1].rise  (DRAM CK1 rising  edge CA)
//            p3 ← ch_dfi_pkt[1].fall  (DRAM CK1 falling edge CA)
//          Previous version was dfi_address_p[p] = pkt[p].rise only —
//          losing the fall-edge CA word (critical for ACT row address).
//
//  [CHG-3] dfi_cs_p[p] now mapped from pkt[p/2].cs_n  (two DFI phases
//          share one DRAM CK cycle, so same cs_n for both edges):
//            p0,p1 ← ch_dfi_pkt[0].cs_n
//            p2,p3 ← ch_dfi_pkt[1].cs_n
//          Previous version was dfi_cs_p[p] = pkt[p].cs_n —
//          wrong because pkt[1..3] are all NOP for single-cycle cmds,
//          so ACT would have lost CS on p1 (fall edge of CK0).
//
//  [CHG-4] wr_en_in now driven from sched_cmd_ch0 WR command pulse
//          (sched_cmd_ch0.valid && sched_cmd_ch0.cmd==CMD_WR) instead
//          of ch0_valid && ch0_is_wr && ch0_ready (demux handshake).
//          Demux handshake fires 1 cycle before the scheduler issues WR.
//          Using it caused data to enter the write pipeline one cycle
//          too early, creating a timing skew of 1 ctrl cycle.
//
//  [CHG-5] rd_en_in now uses separate per-channel enables. The previous
//          OR (sch_rd_en_ch0 | sch_rd_en_ch1) was correct functionally
//          but a single shared pipe means both channels must always fire
//          reads together. Changed to two independent pipes (rd_en_pipe_ch0,
//          rd_en_pipe_ch1) each driving their own dfi_rddata_en_p.
//
//  [CHG-6] Read data assembly: collects all 16 DFI_WORDS (512b per
//          sub-channel) in one valid return from the PHY.
//
//
//
//
//  [CHG-7] dfi_init_start is now a registered pulse (1 ctrl cycle wide)
//          asserted exactly one cycle after rst_n asserts.
//          Previous combinational !init_done_int caused it to stay
//          asserted for the entire ~1.6M cycle init period, violating
//          the DFI 5.1 spec (init_start must be a one-cycle pulse).
//
// *** Block instantiation status ***
//   u_init     : ddr5_init_fsm          [UNCOMMENTED — was commented]
//   u_axi_fe   : axi_slave1_module      [unchanged]
//   u_demux    : ddr5_sub_ch_demux      [unchanged]
//   u_ref_ch0  : ddr5_refresh_engine    [UNCOMMENTED — was commented]
//   u_ref_ch1  : ddr5_refresh_engine    [UNCOMMENTED — was commented]
//   u_sch_ch0  : ddr5_bank_scheduler    [UNCOMMENTED — was commented]
//   u_sch_ch1  : ddr5_bank_scheduler    [UNCOMMENTED — was commented]
//   u_enc      : ddr5_cmd_encoder       [NEW INSTANCE — replaces inline]
// =============================================================
 
`timescale 1ns/1ps
import ddr5_pkg::*;
 
module ddr5_ctrl_top (
  input  logic clk,
  input  logic rst_n,
  input  logic dch,
 
  // ---- AXI3 Slave ------------------------------------------------
  input  logic                   s_awvalid, output logic s_awready,
  input  logic [31:0]            s_awaddr,  input  logic [3:0]  s_awid,
  input  logic [3:0]             s_awlen,   input  logic [2:0]  s_awsize,
  input  logic [1:0]             s_awburst,
  input  logic                   s_wvalid,  output logic s_wready,
  input  logic [AXI_DATA_W-1:0]  s_wdata,   input  logic [AXI_STRB_W-1:0] s_wstrb,
  input  logic                   s_wlast,   input  logic [3:0]  s_wid,
  output logic                   s_bvalid,  input  logic s_bready,
  output logic [3:0]             s_bid,     output logic [1:0]  s_bresp,
  input  logic                   s_arvalid, output logic s_arready,
  input  logic [31:0]            s_araddr,  input  logic [3:0]  s_arid,
  input  logic [3:0]             s_arlen,   input  logic [2:0]  s_arsize,
  input  logic [1:0]             s_arburst,
  output logic                   s_rvalid,  input  logic s_rready,
  output logic [AXI_DATA_W-1:0]  s_rdata,   output logic [3:0]  s_rid,
  output logic [1:0]             s_rresp,   output logic        s_rlast,
 
  // ---- DFI 5.1 interfaces (one per sub-channel, mc_mp modport) ---
  dfi5_if.mc_mp dfi_ch0,   // sub-channel 0
  dfi5_if.mc_mp dfi_ch1    // sub-channel 1
);
 
  // =================================================================
  // Internal signals
  // =================================================================
 
  // Init FSM
  localparam int T_MOD_C = 128;  // Covers final MRW two-cycle CA completion plus tMOD.
  localparam int INIT_EXIT_GUARD_CYCLES = T_MOD_C + DFI_PHASES;
  localparam int INIT_GUARD_CNT_W = $clog2(INIT_EXIT_GUARD_CYCLES + 1);

  logic     init_reset_n, init_cke;
  cmd_req_t init_cmd;
  logic     init_done_int;
  logic     phy_init_done;
  logic     ctrl_init_done_raw;
  logic     ctrl_init_done;
  logic     dram_init_start;
  logic     dram_init_start_latched;
  logic [INIT_GUARD_CNT_W-1:0] init_guard_cnt;
 
  // [CHG-7] Registered init_start pulse — one ctrl cycle wide
  logic     dfi_init_start_r;
  logic     dfi_init_start_sent;
 
  // AXI frontend → demux
  logic                  fe_req_valid, fe_req_ready, fe_req_is_wr;
  logic [AXI_ADDR_W-1:0] fe_req_addr;
  logic [AXI_DATA_W-1:0] fe_req_wdata;
  logic [AXI_STRB_W-1:0] fe_req_wstrb;
  logic [AXI_ID_W-1:0]   fe_req_id;
 
  // Demux → scheduler (channel 0)
  logic                  ch0_valid, ch0_ready, ch0_is_wr;
  logic [BG_BITS-1:0]    ch0_bg;
  logic [BA_BITS-1:0]    ch0_ba;
  logic [ROW_BITS-1:0]   ch0_row;
  logic [COL_BITS-1:0]   ch0_col;
  logic [AXI_ID_W-1:0]   ch0_id;
  logic [511:0]          ch0_wdata;
  logic [63:0]           ch0_wstrb_in;
 
  // Demux → scheduler (channel 1)
  logic                  ch1_valid, ch1_ready, ch1_is_wr;
  logic [BG_BITS-1:0]    ch1_bg;
  logic [BA_BITS-1:0]    ch1_ba;
  logic [ROW_BITS-1:0]   ch1_row;
  logic [COL_BITS-1:0]   ch1_col;
  logic [AXI_ID_W-1:0]   ch1_id;
  logic [511:0]          ch1_wdata;
  logic [63:0]           ch1_wstrb_in;
 
  // Refresh engine → scheduler
  ref_req_t ref_req_ch0, ref_req_ch1;
  logic     ref_ack_ch0,  ref_ack_ch1;
  logic     ref_done_ch0, ref_done_ch1;
  logic     rfc_busy_ch0, rfc_busy_ch1;
 
  // Scheduler → CA encoder
  cmd_req_t sched_cmd_ch0, sched_cmd_ch1;
  logic     sch_rd_en_ch0, sch_rd_en_ch1;
  logic [AXI_ID_W-1:0] sch_rd_id_ch0, sch_rd_id_ch1;
 
  // Cmd mux: init_fsm overrides scheduler before init_done
  cmd_req_t enc_req_ch0, enc_req_ch1;
 
  // CA encoder output → DFI command phase driving
  ca_pkt_t ch0_dfi_pkt [DFI_PHASES];   // registered output from u_enc
  ca_pkt_t ch1_dfi_pkt [DFI_PHASES];
 
  // Read return path
  logic [AXI_DATA_W-1:0] merged_rdata;
  logic                  merged_rvalid;
  logic [AXI_ID_W-1:0]   merged_rid;
  logic [511:0]          ch0_rdata_asm;  logic ch0_rdata_vld;
  logic [511:0]          ch1_rdata_asm;  logic ch1_rdata_vld;
 
  // [CHG-6] Read data upper-half accumulator (words 4..7)
  logic [127:0]          ch0_rdata_hi;   // upper 128b (words 4..7)
  logic [127:0]          ch1_rdata_hi;
  logic                  ch0_rdhi_held;  // upper half has arrived
  logic                  ch1_rdhi_held;
 
  // =================================================================
  // 1. Initialization FSM
  // =================================================================
  // PHY pulses dfi_init_complete for ONE cycle when S_IO_CAL completes.
  // That pulse is latched here to start ddr5_init_fsm.
  // After init_done_int=1, ctrl_top drives dfi_ctrlupd_req=1 so PHY
  // exits S_FWD_CTRL and continues its own calibration sequence.
  assign dram_init_start = dfi_ch0.dfi_init_complete | dfi_ch1.dfi_init_complete;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      dram_init_start_latched <= 1'b0;
    else if (dram_init_start)
      dram_init_start_latched <= 1'b1;
  end

  ddr5_init_fsm u_init (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (dram_init_start_latched),
    .dfi_reset_n(init_reset_n),
    .dfi_cke    (init_cke),
    .init_cmd   (init_cmd),
    .init_done  (init_done_int)
  );

  assign phy_init_done       = dfi_ch0.dfi_init_complete & dfi_ch1.dfi_init_complete;
  assign ctrl_init_done_raw  = phy_init_done & init_done_int;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      init_guard_cnt <= '0;
      ctrl_init_done <= 1'b0;
    end else if (!ctrl_init_done_raw) begin
      init_guard_cnt <= '0;
      ctrl_init_done <= 1'b0;
    end else if (!ctrl_init_done) begin
      if (init_guard_cnt == INIT_GUARD_CNT_W'(INIT_EXIT_GUARD_CYCLES)) begin
        ctrl_init_done <= 1'b1;
      end else begin
        init_guard_cnt <= init_guard_cnt + 1'b1;
      end
    end
  end
 
  // [CHG-7] dfi_init_start: one-cycle pulse on the clock after rst_n
  //         rises. Previous version held it high for the full ~1.6M
  //         cycle init window, violating DFI 5.1 spec.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dfi_init_start_r <= 1'b0;
      dfi_init_start_sent <= 1'b0;
    end else begin
      dfi_init_start_r <= 1'b0;
      if (!dfi_init_start_sent) begin
        dfi_init_start_r    <= 1'b1;
        dfi_init_start_sent <= 1'b1;
      end
    end
  end
 
  // =================================================================
  // 2. AXI Frontend
  // =================================================================
  ddr5_axi_frontend_clean u_axi_fe (
    .clk          (clk),
    .rst_n        (rst_n & ctrl_init_done),
    .s_awvalid    (s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr),
    .s_awid       (s_awid),    .s_awlen  (s_awlen),   .s_awsize(s_awsize),
    .s_awburst    (s_awburst),
    .s_wvalid     (s_wvalid),  .s_wready (s_wready),  .s_wdata (s_wdata),
    .s_wstrb      (s_wstrb),   .s_wlast  (s_wlast),   .s_wid   (s_wid),
    .s_bvalid     (s_bvalid),  .s_bready (s_bready),  .s_bid   (s_bid),
    .s_bresp      (s_bresp),
    .s_arvalid    (s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
    .s_arid       (s_arid),    .s_arlen  (s_arlen),   .s_arsize(s_arsize),
    .s_arburst    (s_arburst),
    .s_rvalid     (s_rvalid),  .s_rready (s_rready),  .s_rdata (s_rdata),
    .s_rid        (s_rid),     .s_rresp  (s_rresp),   .s_rlast (s_rlast),
    .req_valid    (fe_req_valid), .req_ready(fe_req_ready),
    .req_is_wr    (fe_req_is_wr), .req_addr (fe_req_addr),
    .req_wdata    (fe_req_wdata), .req_wstrb(fe_req_wstrb),
    .req_id       (fe_req_id),
    .rd_data_valid(merged_rvalid), .rd_data(merged_rdata),
    .rd_id_in     (merged_rid)
  );
 
  // =================================================================
  // 3. Sub-channel demux
  // =================================================================
  ddr5_sub_ch_demux u_demux (
    .clk          (clk),
    .rst_n        (rst_n),
    .req_valid    (fe_req_valid), .req_ready(fe_req_ready),
    .req_is_wr    (fe_req_is_wr), .req_addr (fe_req_addr),
    .req_wdata    (fe_req_wdata), .req_wstrb(fe_req_wstrb),
    .req_id       (fe_req_id),
    .dch          (dch),
    .ch0_valid    (ch0_valid),  .ch0_ready(ch0_ready),  .ch0_is_wr(ch0_is_wr),
    .ch0_bg       (ch0_bg),     .ch0_ba   (ch0_ba),     .ch0_row  (ch0_row),
    .ch0_col      (ch0_col),    .ch0_id   (ch0_id),
    .ch0_wdata    (ch0_wdata),  .ch0_wstrb(ch0_wstrb_in),
    .ch1_valid    (ch1_valid),  .ch1_ready(ch1_ready),  .ch1_is_wr(ch1_is_wr),
    .ch1_bg       (ch1_bg),     .ch1_ba   (ch1_ba),     .ch1_row  (ch1_row),
    .ch1_col      (ch1_col),    .ch1_id   (ch1_id),
    .ch1_wdata    (ch1_wdata),  .ch1_wstrb(ch1_wstrb_in),
    .ch0_rdata    (ch0_rdata_asm), .ch0_rvalid(ch0_rdata_vld),
    .ch1_rdata    (ch1_rdata_asm), .ch1_rvalid(ch1_rdata_vld),
    .merged_rdata (merged_rdata),  .merged_rvalid(merged_rvalid),
    .merged_rid   (merged_rid)
  );
 
  // =================================================================
  // 4. Refresh engines                      [UNCOMMENTED — CHG from zip]
  // =================================================================
  ddr5_refresh_engine u_ref_ch0 (
    .clk        (clk),
    .rst_n      (rst_n & ctrl_init_done),
    .use_pbref  (1'b0),
    .ref_req    (ref_req_ch0),
    .ref_ack    (ref_ack_ch0),
    .ref_done   (ref_done_ch0),
    .rfc_busy   (rfc_busy_ch0),
    .credit_cnt (),
    .pb_bank_idx()
  );
 
  ddr5_refresh_engine u_ref_ch1 (
    .clk        (clk),
    .rst_n      (rst_n & ctrl_init_done),
    .use_pbref  (1'b0),
    .ref_req    (ref_req_ch1),
    .ref_ack    (ref_ack_ch1),
    .ref_done   (ref_done_ch1),
    .rfc_busy   (rfc_busy_ch1),
    .credit_cnt (),
    .pb_bank_idx()
  );
 
  // =================================================================
  // 5. Bank schedulers                      [UNCOMMENTED — CHG from zip]
  // =================================================================
  ddr5_bank_scheduler u_sch_ch0 (
    .clk        (clk),
    .rst_n      (rst_n & ctrl_init_done),
    .req_valid  (ch0_valid),     .req_ready(ch0_ready),
    .req_is_wr  (ch0_is_wr),
    .req_bg     (ch0_bg),        .req_ba   (ch0_ba),
    .req_row    (ch0_row),       .req_col  (ch0_col),
    .req_id     (ch0_id),
    .ref_req    (ref_req_ch0),   .ref_ack  (ref_ack_ch0),
    .ref_done   (ref_done_ch0),
    .cmd_out    (sched_cmd_ch0),
    .rd_en      (sch_rd_en_ch0), .rd_id    (sch_rd_id_ch0)
  );
 
  ddr5_bank_scheduler u_sch_ch1 (
    .clk        (clk),
    .rst_n      (rst_n & ctrl_init_done),
    .req_valid  (ch1_valid),     .req_ready(ch1_ready),
    .req_is_wr  (ch1_is_wr),
    .req_bg     (ch1_bg),        .req_ba   (ch1_ba),
    .req_row    (ch1_row),       .req_col  (ch1_col),
    .req_id     (ch1_id),
    .ref_req    (ref_req_ch1),   .ref_ack  (ref_ack_ch1),
    .ref_done   (ref_done_ch1),
    .cmd_out    (sched_cmd_ch1),
    .rd_en      (sch_rd_en_ch1), .rd_id    (sch_rd_id_ch1)
  );
 
  // =================================================================
  // 6. Command mux: init_fsm overrides scheduler before init_done
  // =================================================================
  always_comb begin
    if (!init_done_int) begin
      enc_req_ch0        = init_cmd;
      enc_req_ch0.sub_ch = 1'b0;
      enc_req_ch1        = init_cmd;
      enc_req_ch1.sub_ch = 1'b1;
    end else if (!ctrl_init_done) begin
      enc_req_ch0        = '0;
      enc_req_ch0.cmd    = CMD_NOP;
      enc_req_ch0.sub_ch = 1'b0;
      enc_req_ch1        = '0;
      enc_req_ch1.cmd    = CMD_NOP;
      enc_req_ch1.sub_ch = 1'b1;
    end else begin
      enc_req_ch0        = sched_cmd_ch0;
      enc_req_ch0.sub_ch = 1'b0;
      enc_req_ch1        = sched_cmd_ch1;
      enc_req_ch1.sub_ch = 1'b1;
    end
  end
 
  // =================================================================
  // 7. CA Encoder                           [CHG-1: instance, not inline]
  //    ddr5_cmd_encoder has a 1-cycle registered output, so
  //    ch0_dfi_pkt / ch1_dfi_pkt are already flopped at u_enc output.
  //    The DFI command interface driving (section 8) is purely comb
  //    off those registered values — no extra pipeline needed here.
  // =================================================================
  ddr5_cmd_encoder u_enc (
    .clk      (clk),
    .rst_n    (rst_n),
    .req_ch0  (enc_req_ch0),
    .req_ch1  (enc_req_ch1),
    .ch0_dfi  (ch0_dfi_pkt),
    .ch1_dfi  (ch1_dfi_pkt)
  );
 
  // =================================================================
  // 8. DFI 5.1 Command Interface
  //    (DFI 5.1 spec Table 8 — Command Interface Signals)
  //
  //    [CHG-2] dfi_address_p[p] mapping — correctly split rise/fall:
  //      DFI_PHASES = 4, each phase = one DRAM CK cycle.
  //      Within each DRAM CK cycle the CA bus carries different values
  //      on rising vs falling edge (notably for ACT 2-cycle encoding).
  //      ca_pkt_t.rise = CA value at rising  edge of that DRAM CK cycle.
  //      ca_pkt_t.fall = CA value at falling edge of that DRAM CK cycle.
  //      DFI 5.1 at 1:4 ratio: 4 phases cover 4 DRAM CK cycles, but
  //      since each phase already encodes rise+fall of one CK, we map:
  //        dfi_address_p[0] ← pkt[0].rise  (CK0 rise)
  //        dfi_address_p[1] ← pkt[0].fall  (CK0 fall — ACT row addr cont.)
  //        dfi_address_p[2] ← pkt[1].rise  (CK1 rise — NOP for all cmds)
  //        dfi_address_p[3] ← pkt[1].fall  (CK1 fall — NOP for all cmds)
  //
  //    [CHG-3] dfi_cs_p[p] mapping — both edges of same CK share cs_n:
  //        dfi_cs_p[0,1] ← pkt[0].cs_n  (CS active for CK0 both edges)
  //        dfi_cs_p[2,3] ← pkt[1].cs_n  (CS active for CK1 both edges)
  //
  //    Legacy DDR4 signals (act_n, ras_n, cas_n, we_n, bank, bg) are
  //    held at DDR5 idle values per JESD79-5B Section 3.1.1.
  // =================================================================
  always_comb begin
    for (int p = 0; p < DFI_PHASES; p++) begin
      // ---- [CHG-2] Address: interleave rise/fall across phases ----
      // Even phase p → rising edge of DRAM CK (p/2)
      // Odd  phase p → falling edge of DRAM CK (p/2)
      dfi_ch0.dfi_address_p[p] = (p[0] == 1'b0)
                                  ? ch0_dfi_pkt[p/2].rise   // even: rise
                                  : ch0_dfi_pkt[p/2].fall;  // odd:  fall
      dfi_ch1.dfi_address_p[p] = (p[0] == 1'b0)
                                  ? ch1_dfi_pkt[p/2].rise
                                  : ch1_dfi_pkt[p/2].fall;
 
      // ---- [CHG-3] CS_n: same value for both edges of one CK cycle --
      dfi_ch0.dfi_cs_p[p]      = ch0_dfi_pkt[p/2].cs_n;
      dfi_ch1.dfi_cs_p[p]      = ch1_dfi_pkt[p/2].cs_n;
 
      // ---- CKE / RESET_n: broadcast from init FSM to all phases ----
      dfi_ch0.dfi_cke_p[p]              = init_cke;
      dfi_ch0.dfi_reset_n_p[p]          = init_reset_n;
      dfi_ch1.dfi_cke_p[p]              = init_cke;
      dfi_ch1.dfi_reset_n_p[p]          = init_reset_n;
 
      // ---- Legacy DDR4 signals: held at DDR5 idle values -----------
      dfi_ch0.dfi_act_n_p[p]            = 1'b1;   // unused in DDR5 CA mode
      dfi_ch0.dfi_bank_p[p]             = '0;     // held 0 per spec
      dfi_ch0.dfi_bg_p[p]               = '0;     // held 0 per spec
      dfi_ch0.dfi_cas_n_p[p]            = 1'b1;
      dfi_ch0.dfi_ras_n_p[p]            = 1'b1;
      dfi_ch0.dfi_we_n_p[p]             = 1'b1;
      dfi_ch0.dfi_cid_p[p]              = '0;
      dfi_ch0.dfi_odt_p[p]              = '0;
      dfi_ch0.dfi_dram_clk_disable_p[p] = '0;
      dfi_ch0.dfi_parity_in_p[p]        = '0;
 
      dfi_ch1.dfi_act_n_p[p]            = 1'b1;
      dfi_ch1.dfi_bank_p[p]             = '0;
      dfi_ch1.dfi_bg_p[p]               = '0;
      dfi_ch1.dfi_cas_n_p[p]            = 1'b1;
      dfi_ch1.dfi_ras_n_p[p]            = 1'b1;
      dfi_ch1.dfi_we_n_p[p]             = 1'b1;
      dfi_ch1.dfi_cid_p[p]              = '0;
      dfi_ch1.dfi_odt_p[p]              = '0;
      dfi_ch1.dfi_dram_clk_disable_p[p] = '0;
      dfi_ch1.dfi_parity_in_p[p]        = '0;
    end
 
    dfi_ch0.dfi_2n_mode_p = 1'b0;   // 1N mode
    dfi_ch1.dfi_2n_mode_p = 1'b0;
  end
 
  // =================================================================
  // 9. Write data pipeline (CWL_C stages deep)
  //    (DFI 5.1 Table 11 — Write Data Interface)
  //
  //    [CHG-4] wr_en_in source corrected:
  //      OLD: ch0_valid && ch0_is_wr && ch0_ready  (demux handshake)
  //      NEW: sched_cmd_ch0.valid && (sched_cmd_ch0.cmd==CMD_WR)
  //           (scheduler WR command pulse — 1 cycle later, correct timing)
  //      The demux handshake fires when the address is accepted into the
  //      scheduler; the WR command is not issued until tRCD cycles later.
  //      Using the demux signal caused the data pipeline to be tRCD cycles
  //      out of phase with the actual DFI WR command.
  // =================================================================
  localparam int WL_PIPE = CWL_C + 15;   // Align DFI write launch to DRAM-model CWL window.
 
  logic [511:0] wr_pipe_ch0 [WL_PIPE];
  logic [63:0]  dm_pipe_ch0 [WL_PIPE];
  logic [511:0] wr_pipe_ch1 [WL_PIPE];
  logic [63:0]  dm_pipe_ch1 [WL_PIPE];
  logic         wr_en_pipe_ch0 [WL_PIPE];
  logic         wr_en_pipe_ch1 [WL_PIPE];
 
  // DM: invert AXI STRB (active-high DM = mask byte)
  wire [63:0] ch0_dm_in;
  wire [63:0] ch1_dm_in;
  genvar gi;
  generate
    for (gi = 0; gi < 64; gi++) begin : gen_dm
      assign ch0_dm_in[gi] = ~ch0_wstrb_in[gi];
      assign ch1_dm_in[gi] = ~ch1_wstrb_in[gi];
    end
  endgenerate
 
  // [CHG-4] Write enable: use scheduler WR command pulse, not demux handshake
  wire wr_en_ch0_in = sched_cmd_ch0.valid && (sched_cmd_ch0.cmd == CMD_WR ||
                                              sched_cmd_ch0.cmd == CMD_WRA);
  wire wr_en_ch1_in = sched_cmd_ch1.valid && (sched_cmd_ch1.cmd == CMD_WR ||
                                              sched_cmd_ch1.cmd == CMD_WRA);
 
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < WL_PIPE; i++) begin
        wr_pipe_ch0[i] <= '0;
        dm_pipe_ch0[i] <= '0;
        wr_pipe_ch1[i] <= '0;
        dm_pipe_ch1[i] <= '0;
        wr_en_pipe_ch0[i]  <= 1'b0;
        wr_en_pipe_ch1[i]  <= 1'b0;
      end
    end else begin
      wr_pipe_ch0[0] <= ch0_wdata;
      dm_pipe_ch0[0] <= ch0_dm_in;
      wr_pipe_ch1[0] <= ch1_wdata;
      dm_pipe_ch1[0] <= ch1_dm_in;
      wr_en_pipe_ch0[0]  <= wr_en_ch0_in;
      wr_en_pipe_ch1[0]  <= wr_en_ch1_in;
      for (int i = 1; i < WL_PIPE; i++) begin
        wr_pipe_ch0[i] <= wr_pipe_ch0[i-1];
        dm_pipe_ch0[i] <= dm_pipe_ch0[i-1];
        wr_pipe_ch1[i] <= wr_pipe_ch1[i-1];
        dm_pipe_ch1[i] <= dm_pipe_ch1[i-1];
        wr_en_pipe_ch0[i]  <= wr_en_pipe_ch0[i-1];
        wr_en_pipe_ch1[i]  <= wr_en_pipe_ch1[i-1];
      end
    end
  end
 
  // ---- Drive DFI 5.1 write data signals --------------------------
  // DFI_WORDS = 16; each word = 32b data + 4b DM + 1b enable.
  // The 512b per-channel word is sliced into 16 x 32b words at output.
  always_comb begin
    for (int w = 0; w < DFI_WORDS; w++) begin
      dfi_ch0.dfi_wrdata_p[w]      = wr_pipe_ch0[WL_PIPE-1][w*32 +: 32];
      dfi_ch0.dfi_wrdata_mask_p[w] = dm_pipe_ch0[WL_PIPE-1][w*4  +:  4];
      dfi_ch0.dfi_wrdata_en_p[w]   = wr_en_pipe_ch0[WL_PIPE-1];
      dfi_ch0.dfi_wrdata_cs_p[w]   = wr_en_pipe_ch0[WL_PIPE-1] ? 1'b0 : 1'b1;
      dfi_ch0.dfi_wrdata_ecc_p[w]  = '0;   // link ECC not used
 
      dfi_ch1.dfi_wrdata_p[w]      = wr_pipe_ch1[WL_PIPE-1][w*32 +: 32];
      dfi_ch1.dfi_wrdata_mask_p[w] = dm_pipe_ch1[WL_PIPE-1][w*4  +:  4];
      dfi_ch1.dfi_wrdata_en_p[w]   = wr_en_pipe_ch1[WL_PIPE-1];
      dfi_ch1.dfi_wrdata_cs_p[w]   = wr_en_pipe_ch1[WL_PIPE-1] ? 1'b0 : 1'b1;
      dfi_ch1.dfi_wrdata_ecc_p[w]  = '0;
    end
  end
 
  // =================================================================
  // 10. Read data enable pipelines
  //     (DFI 5.1 Table 14 — Read Data Interface)
  //
  //     dfi_rddata_en_p must be asserted DFI_TRDDATA_EN nCK after the
  //     RD command appears on the DFI command bus.
  //     DFI_TRDDATA_EN = RL - DFI_TCTRL_DELAY - 2 = 40 - 4 - 2 = 34 nCK.
  //     In ctrl cycles: 34/4 = 9 stages (rounded up → CL_C - 1 = 9).
  //
  //     [CHG-5] Two independent pipelines — one per sub-channel.
  //     Both channels issue reads in the same ctrl cycle (same ACT/RD
  //     sequence on both schedulers) but independence allows for future
  //     per-channel CL tuning without changing top-level wiring.
  // =================================================================
  localparam int RDDATA_EN_PIPE = CL_C - 1;   // 9 ctrl cycles
 
  // [CHG-5] Independent per-channel rddata_en pipes
  logic rd_en_pipe_ch0 [RDDATA_EN_PIPE];
  logic rd_en_pipe_ch1 [RDDATA_EN_PIPE];
 
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < RDDATA_EN_PIPE; i++) begin
        rd_en_pipe_ch0[i] <= 1'b0;
        rd_en_pipe_ch1[i] <= 1'b0;
      end
    end else begin
      // Stage 0: load from scheduler rd_en pulse
      rd_en_pipe_ch0[0] <= sch_rd_en_ch0;
      rd_en_pipe_ch1[0] <= sch_rd_en_ch1;
      // Stages 1..RDDATA_EN_PIPE-1: shift
      for (int i = 1; i < RDDATA_EN_PIPE; i++) begin
        rd_en_pipe_ch0[i] <= rd_en_pipe_ch0[i-1];
        rd_en_pipe_ch1[i] <= rd_en_pipe_ch1[i-1];
      end
    end
  end
 
  // Drive dfi_rddata_en_p for all command phases (broadcast same enable)
  always_comb begin
    for (int p = 0; p < DFI_PHASES; p++) begin
      dfi_ch0.dfi_rddata_en_p[p] = rd_en_pipe_ch0[RDDATA_EN_PIPE-1];
      dfi_ch0.dfi_rddata_cs_p[p] = rd_en_pipe_ch0[RDDATA_EN_PIPE-1] ? 1'b0 : 1'b1;
      dfi_ch1.dfi_rddata_en_p[p] = rd_en_pipe_ch1[RDDATA_EN_PIPE-1];
      dfi_ch1.dfi_rddata_cs_p[p] = rd_en_pipe_ch1[RDDATA_EN_PIPE-1] ? 1'b0 : 1'b1;
    end
  end
 
  // =================================================================
  // 11. Read data assembly from dfi5_if
  //     (DFI 5.1 Table 14 — dfi_rddata_w[DFI_WORDS], dfi_rddata_valid_w)
  //
  //     [CHG-6] Full 256b per sub-channel collected across TWO consecutive
  //     valid cycles (BL16 = 2 ctrl cycles of 128b each):
  //       Cycle A (valid_w[0]=1): words 0..3  → lower  128b of rdata_asm
  //       Cycle B (valid_w[0]=1 again, 1 cycle later): words 0..3 → upper 128b
  //     Previous version only captured one cycle, dropping the upper 128b.
  //
  //     Both sub-channels assemble independently. The demux merge waits
  //     for both ch0_rdata_vld and ch1_rdata_vld before returning to AXI.
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ch0_rdata_asm  <= '0;   ch0_rdata_vld  <= 1'b0;
      ch0_rdata_hi   <= '0;   ch0_rdhi_held  <= 1'b0;
      ch1_rdata_asm  <= '0;   ch1_rdata_vld  <= 1'b0;
      ch1_rdata_hi   <= '0;   ch1_rdhi_held  <= 1'b0;
    end else begin
      // Default: deassert valid for one cycle after assertion
      ch0_rdata_vld <= 1'b0;
      ch1_rdata_vld <= 1'b0;
 
      // ---- Sub-channel 0 ----------------------------------------
      if (dfi_ch0.dfi_rddata_valid_w[0]) begin
        for (int w = 0; w < DFI_WORDS; w++)
          ch0_rdata_asm[w*32 +: 32] <= dfi_ch0.dfi_rddata_w[w];
        ch0_rdhi_held <= 1'b0;
        ch0_rdata_vld <= 1'b1;
      end
 
      // ---- Sub-channel 1 ----------------------------------------
      if (dfi_ch1.dfi_rddata_valid_w[0]) begin
        for (int w = 0; w < DFI_WORDS; w++)
          ch1_rdata_asm[w*32 +: 32] <= dfi_ch1.dfi_rddata_w[w];
        ch1_rdhi_held <= 1'b0;
        ch1_rdata_vld <= 1'b1;
      end
    end
  end
 
  // ch*_rdata_asm carries the complete 512b BL16 sub-channel return.
 
 
 
 
  // =================================================================
  // 12. DFI 5.1 Status / Update / Low-Power / Message interfaces
  //     (DFI 5.1 Tables 17, 19, 22, 27, 33)
  // =================================================================
 
  // [CHG-7] dfi_init_start: one-cycle registered pulse (not combinational hold)
  assign dfi_ch0.dfi_init_start    = dfi_init_start_r;
  assign dfi_ch1.dfi_init_start    = dfi_init_start_r;
 
  // Frequency descriptor: DDR5-6400, 1:4 ratio
  assign dfi_ch0.dfi_frequency     = 5'd31;   // 3200 MHz encoded value
  assign dfi_ch0.dfi_freq_ratio    = 2'b10;   // 1:4 ratio code
  assign dfi_ch0.dfi_freq_fsp      = '0;
  assign dfi_ch1.dfi_frequency     = 5'd31;
  assign dfi_ch1.dfi_freq_ratio    = 2'b10;
  assign dfi_ch1.dfi_freq_fsp      = '0;
 
  // ctrlupd_req tells PHY dram init is done; PHY then runs internal ZQ/DLY/FIFO cal
  assign dfi_ch0.dfi_ctrlupd_req   = init_done_int;
  assign dfi_ch1.dfi_ctrlupd_req   = init_done_int;
  assign dfi_ch0.dfi_phyupd_ack    = dfi_ch0.dfi_phyupd_req;
  assign dfi_ch1.dfi_phyupd_ack    = dfi_ch1.dfi_phyupd_req;
  assign dfi_ch0.dfi_phymstr_ack   = dfi_ch0.dfi_phymstr_req;
  assign dfi_ch1.dfi_phymstr_ack   = dfi_ch1.dfi_phymstr_req;
 
  // Low power: not used in this version
  assign dfi_ch0.dfi_lp_ctrl_req    = 1'b0;
  assign dfi_ch0.dfi_lp_ctrl_wakeup = '0;
  assign dfi_ch0.dfi_lp_data_req    = 1'b0;
  assign dfi_ch0.dfi_lp_data_wakeup = '0;
  assign dfi_ch1.dfi_lp_ctrl_req    = 1'b0;
  assign dfi_ch1.dfi_lp_ctrl_wakeup = '0;
  assign dfi_ch1.dfi_lp_data_req    = 1'b0;
  assign dfi_ch1.dfi_lp_data_wakeup = '0;
 
  // MC-to-PHY message: not used
  assign dfi_ch0.dfi_ctrlmsg       = '0;
  assign dfi_ch0.dfi_ctrlmsg_data  = '0;
  assign dfi_ch0.dfi_ctrlmsg_req   = 1'b0;
  assign dfi_ch1.dfi_ctrlmsg       = '0;
  assign dfi_ch1.dfi_ctrlmsg_data  = '0;
  assign dfi_ch1.dfi_ctrlmsg_req   = 1'b0;
 
  // WCK (LPDDR5 only): tie off
  always_comb begin
    for (int p = 0; p < DFI_PHASES; p++) begin
      dfi_ch0.dfi_wck_cs_p[p]     = '0;
      dfi_ch0.dfi_wck_en_p[p]     = '0;
      dfi_ch0.dfi_wck_toggle_p[p] = '0;
      dfi_ch1.dfi_wck_cs_p[p]     = '0;
      dfi_ch1.dfi_wck_en_p[p]     = '0;
      dfi_ch1.dfi_wck_toggle_p[p] = '0;
    end
  end
 
  // =================================================================
  // 13. Debug display
  // =================================================================
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (s_awvalid && s_awready)
        $display("[CTRL][AW]       t=%0t addr=%0h id=%0h len=%0h",
                 $time, s_awaddr, s_awid, s_awlen);
      if (s_wvalid && s_wready)
        $display("[CTRL][W]        t=%0t wdata=%0h wstrb=%0h wlast=%0b",
                 $time, s_wdata, s_wstrb, s_wlast);
      if (fe_req_valid && fe_req_ready)
        $display("[CTRL][FE_REQ]   t=%0t is_wr=%0b addr=%0h",
                 $time, fe_req_is_wr, fe_req_addr);
      if (sched_cmd_ch0.valid)
        $display("[CTRL][CMD_CH0]  t=%0t cmd=%0s bg=%0h ba=%0h row=%0h col=%0h",
                 $time, sched_cmd_ch0.cmd.name(), sched_cmd_ch0.bg,
                 sched_cmd_ch0.ba, sched_cmd_ch0.row, sched_cmd_ch0.col);
      if (sched_cmd_ch1.valid)
        $display("[CTRL][CMD_CH1]  t=%0t cmd=%0s bg=%0h ba=%0h row=%0h col=%0h",
                 $time, sched_cmd_ch1.cmd.name(), sched_cmd_ch1.bg,
                 sched_cmd_ch1.ba, sched_cmd_ch1.row, sched_cmd_ch1.col);
      if (wr_en_pipe_ch0[WL_PIPE-1] || wr_en_pipe_ch1[WL_PIPE-1])
        $display("[CTRL][DFI_WR]   t=%0t ch0_wrdata_w0=%0h ch1_wrdata_w0=%0h en=%0b",
                 $time, dfi_ch0.dfi_wrdata_p[0], dfi_ch1.dfi_wrdata_p[0],
                 dfi_ch0.dfi_wrdata_en_p[0]);
      if (dfi_ch0.dfi_rddata_valid_w[0])
        $display("[CTRL][DFI_RD0]  t=%0t rddata_w0=%0h rddata_w1=%0h",
                 $time, dfi_ch0.dfi_rddata_w[0], dfi_ch0.dfi_rddata_w[1]);
      if (dfi_ch1.dfi_rddata_valid_w[0])
        $display("[CTRL][DFI_RD1]  t=%0t rddata_w0=%0h rddata_w1=%0h",
                 $time, dfi_ch1.dfi_rddata_w[0], dfi_ch1.dfi_rddata_w[1]);
      if (s_bvalid && s_bready)
        $display("[CTRL][B]        t=%0t bid=%0h bresp=%0h",
                 $time, s_bid, s_bresp);
      if (s_rvalid && s_rready)
        $display("[CTRL][R]        t=%0t rid=%0h rdata=%0h",
                 $time, s_rid, s_rdata);
    end
  end
 
endmodule : ddr5_ctrl_top
