// =============================================================
// ddr5_pkg.sv
// Global parameter package for DDR5-6400 Controller
//
// Target  : DDR5 UDIMM, 1 rank, 2 sub-channels
// Speed   : DDR5-6400 (3200 MHz DRAM clock)
// DFI     : 1:4 ratio  → controller at 800 MHz, 4 phases
// AXI4    : 256-bit host data bus
// Reference: JEDEC JESD79-5B
// =============================================================

package ddr5_pkg;

  // -----------------------------------------------------------
  // Clock / ratio
  // -----------------------------------------------------------
  localparam int DRAM_FREQ_MHZ  = 3200;
  localparam int CTRL_FREQ_MHZ  = 800;
  localparam int DFI_RATIO      = 4;     // 1 ctrl_clk = 4 dram_clk
  localparam int DFI_PHASES     = 4;     // p0..p3

  // -----------------------------------------------------------
  // Structural geometry
  // -----------------------------------------------------------
  localparam int NUM_SUBCH      = 2;
  localparam int NUM_RANKS      = 1;
  localparam int NUM_BG         = 4;     // bank groups
  localparam int NUM_BA         = 4;     // banks per bank-group
  localparam int NUM_BANKS      = NUM_BG * NUM_BA;  // 16 total
  localparam int ROW_BITS       = 16;    // 64 K rows
  localparam int COL_BITS       = 10;    // 1 K columns
  localparam int BG_BITS        = 2;
  localparam int BA_BITS        = 2;

  // DDR5 BL=16 fixed; per sub-channel DQ width = 32b (x16 ×2)
  localparam int BL             = 16;
  localparam int DQ_WIDTH       = 32;    // per sub-channel

  // -----------------------------------------------------------
  // AXI3 host interface widths
  // -----------------------------------------------------------
  localparam int AXI_ADDR_W     = 32;   // 64 GB
  localparam int AXI_DATA_W     = 512;  // 128b per sub-ch × 2
  localparam int AXI_STRB_W     = AXI_DATA_W / 8;  // 64
  localparam int AXI_ID_W       = 8;

  // -----------------------------------------------------------
  // DFI widths
  // -----------------------------------------------------------
  localparam int DFI_CA_W       = 14;   // CA[13:0]
  // Write/read data at 1:4 ratio: 8 data phases per ctrl cycle
  // (4 rising + 4 falling = 8 × 32b = 256b per sub-channel)
  localparam int DFI_DATA_PHASES = BL;
  localparam int DFI_WRDATA_W   = DQ_WIDTH * DFI_DATA_PHASES; // 512b

  // -----------------------------------------------------------
  // New parameters added (compatibility with mem_pkg/interface.sv)
  // Reference: mem_pkg.sv — define rank/device widths and burst sizes
  // -----------------------------------------------------------
  localparam int DQ_BITS        = 8;    // per-device DQ width (x8 devices = 64-bit rank)
  localparam int DQS_BITS       = 1;    // per-device DQS lanes
  localparam int DM_BITS        = 1;    // per-device DM width

  localparam int RANK_DEVICES   = 8;    // devices per rank
  localparam int RANK_DQ_BITS   = RANK_DEVICES * DQ_BITS;   // = 64
  localparam int RANK_DQS_BITS  = RANK_DEVICES * DQS_BITS;  // = 8
  localparam int RANK_DM_BITS   = RANK_DEVICES * DM_BITS;   // = 8

  localparam int BURST_L        = BL;   // number of DQS edges per full DDR5 burst
  localparam int BL8_DQ_BITS    = BURST_L * RANK_DQ_BITS;   // = 512
  localparam int BL8_DM_BITS    = BURST_L * RANK_DM_BITS;   // = 64

  // Address widths seen at the DRAM and to the controller
  localparam int ADDR_BITS      = ROW_BITS + COL_BITS + BA_BITS; // DRAM addr width
  localparam int ADDR_MCTRL     = AXI_ADDR_W;   // address bus width to controller (32)

  // AXI widths compatible names (used by some testbench files)
 // localparam int AXI_DATA_WIDTH = RANK_DQ_BITS;
  //localparam int AXI_STRB_WIDTH = RANK_DM_BITS;

  // -----------------------------------------------------------
  // DDR5-6400 timing (DRAM clock cycles, nCK)
  // -----------------------------------------------------------
  // Latencies
  localparam int CL             = 40;
  localparam int CWL            = 36;
  localparam int AL             = 0;
  localparam int RL             = CL + AL;
  localparam int WL             = CWL + AL;

  // Row timing
  localparam int T_RCD          = 39;
  localparam int T_RP           = 39;
  localparam int T_RAS          = 76;
  localparam int T_RC           = 115;
  localparam int T_RRD_S        = 8;
  localparam int T_RRD_L        = 11;
  localparam int T_FAW          = 40;

  // Column timing
  localparam int T_CCD_S        = 8;
  localparam int T_CCD_L        = 12;
  localparam int T_WTR_S        = 4;
  localparam int T_WTR_L        = 22;
  localparam int T_RTP          = 12;
  localparam int T_WR           = 60;

  // Refresh timing
  localparam int T_REFI         = 12480;  // 3.9 µs @ 3200 MHz
  localparam int T_RFC1         = 944;    // 295 ns @ 3200 MHz (≤16Gb)
  localparam int T_RFC2         = 512;    // 160 ns @ 3200 MHz
  localparam int REF_MAX_POST   = 8;      // max postponed refresh credits

  // ZQ calibration
  localparam int T_ZQCAL        = 512;
  localparam int T_ZQLAT        = 30;

  // Init / power-on
  localparam int T_PWRUP = 320;   // tiny — exits S_RESET in ~80 ctrl cycles
 // localparam int T_PWRUP = 6400000; // 2 ms @ 3200 MHz (for synthesis/formal)
  localparam int T_XPR          = T_RFC1 + 10;

  // -----------------------------------------------------------
  // Controller-domain timing  (÷ DFI_RATIO, rounded up)
  // -----------------------------------------------------------
  function automatic int to_ctrl(input int nck);
    return (nck + DFI_RATIO - 1) / DFI_RATIO;
  endfunction

  localparam int CL_C           = to_ctrl(CL);        // 10
  localparam int CWL_C          = to_ctrl(CWL);       // 9
  localparam int T_RCD_C        = to_ctrl(T_RCD);     // 10
  localparam int T_RP_C         = to_ctrl(T_RP);      // 10
  localparam int T_RAS_C        = to_ctrl(T_RAS);     // 19
  localparam int T_RC_C         = to_ctrl(T_RC);      // 29
  localparam int T_RFC1_C       = to_ctrl(T_RFC1);    // 236
  localparam int T_RFC2_C       = to_ctrl(T_RFC2);    // 128
  localparam int T_REFI_C       = to_ctrl(T_REFI);    // 3120
  localparam int T_WR_C         = to_ctrl(T_WR);      // 15
  localparam int T_RTP_C        = to_ctrl(T_RTP);     // 3
  localparam int T_RRD_S_C      = to_ctrl(T_RRD_S);  // 2
  localparam int T_RRD_L_C      = to_ctrl(T_RRD_L);  // 3
  localparam int T_CCD_S_C      = to_ctrl(T_CCD_S);  // 2
  localparam int T_CCD_L_C      = to_ctrl(T_CCD_L);  // 3
  localparam int T_WTR_L_C      = to_ctrl(T_WTR_L);  // 6
  localparam int T_FAW_C        = to_ctrl(T_FAW);     // 10
  localparam int T_ZQCAL_C      = to_ctrl(T_ZQCAL);  // 128
  localparam int T_ZQLAT_C      = to_ctrl(T_ZQLAT);  // 8
  localparam int T_XPR_C        = to_ctrl(T_XPR);    // 239
  localparam int T_PWRUP_C      = to_ctrl(T_PWRUP);  // 1600000





  // -----------------------------------------------------------
  // DFI pipeline latencies (in DRAM nCK)
  // -----------------------------------------------------------
  localparam int DFI_TCTRL_DELAY  = 4;
  localparam int DFI_TWRLAT       = WL  - DFI_TCTRL_DELAY;
  localparam int DFI_TRDDATA_EN   = RL  - DFI_TCTRL_DELAY - 2;
  localparam int DFI_WORDS = DFI_DATA_PHASES;

  // -----------------------------------------------------------
  // Command opcodes (5-bit, internal use)
  // -----------------------------------------------------------
  typedef enum logic [4:0] {
    CMD_NOP   = 5'h00,
    CMD_ACT   = 5'h01,
    CMD_PRE   = 5'h02,
    CMD_PREAB = 5'h03,
    CMD_REFAB = 5'h04,
    CMD_REFPB = 5'h05,
    CMD_RD    = 5'h06,
    CMD_RDA   = 5'h07,
    CMD_WR    = 5'h08,
    CMD_WRA   = 5'h09,
    CMD_MRS   = 5'h0A,
    CMD_SRE   = 5'h0B,
    CMD_SRX   = 5'h0C,
    CMD_PDE   = 5'h0D,
    CMD_PDX   = 5'h0E,
    CMD_ZQS   = 5'h0F,
    CMD_ZQL   = 5'h10
  } ddr5_cmd_e;

  // -----------------------------------------------------------
  // CA-bus packet (one DRAM clock = rising + falling edge)
  // -----------------------------------------------------------
  typedef struct packed {
    logic [DFI_CA_W-1:0] rise;   // CA driven at rising  CK edge
    logic [DFI_CA_W-1:0] fall;   // CA driven at falling CK edge
    logic                cs_n;   // chip select (active-low)
  } ca_pkt_t;

  // Full 4-phase DFI command bundle (one sub-channel)
  typedef ca_pkt_t [DFI_PHASES-1:0] dfi_cmd_phases_t;

  // -----------------------------------------------------------
  // Scheduler → CA-encoder request
  // -----------------------------------------------------------
  typedef struct packed {
    logic                valid;
    ddr5_cmd_e           cmd;
    logic [BG_BITS-1:0]  bg;
    logic [BA_BITS-1:0]  ba;
    logic [ROW_BITS-1:0] row;
    logic [COL_BITS-1:0] col;
    logic [7:0]          mr_addr;
    logic [7:0]          mr_op;
    logic                ap;       // auto-precharge
    logic                sub_ch;   // 0=CH0, 1=CH1
    logic [AXI_ID_W-1:0] tid;      // transaction ID (for read return)
  } cmd_req_t;

  // -----------------------------------------------------------
  // Refresh request (engine → scheduler)
  // -----------------------------------------------------------
  typedef struct packed {
    logic                valid;
    logic                urgent;   // credit limit hit
    logic                is_ab;    // 1=REFab, 0=REFpb
    logic [BG_BITS-1:0]  bg;
    logic [BA_BITS-1:0]  ba;
  } ref_req_t;

  // -----------------------------------------------------------
  // MRS table for DDR5-6400  (CL=40, CWL=36, BL=16)
  // Encoding per JESD79-5B Section 5 Mode Registers
  // -----------------------------------------------------------
  function automatic logic [7:0] mrs_value(input logic [7:0] mr_addr);
    case (mr_addr)
      8'd0  : return 8'h24;  // MR0: CL=40 in the supplied model, BL=16
      8'd1  : return 8'h00;  // MR1: burst type, WCK sync off
      8'd2  : return 8'h28;  // MR2: RL=40  (field[7:2]=0x0A << 2)
      8'd3  : return 8'h24;  // MR3: WL=36  (field[7:2]=0x09 << 2)
      8'd4  : return 8'h02;  // MR4: refresh rate = normal (×1)
      8'd5  : return 8'h00;  // MR5: pull-up ODT disabled
      8'd6  : return 8'h00;  // MR6: pull-down ODT disabled
      default: return 8'h00;
    endcase
  endfunction

endpackage : ddr5_pkg
