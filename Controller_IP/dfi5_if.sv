// =============================================================
// dfi5_if.sv  — DFI 5.1 interface
// Connects DDR5 controller output to PHY / DRAM model
// =============================================================
`timescale 1ns/1ps

import ddr5_pkg::*;

// =====================================================================
// dfi5_if.sv
// DFI 5.1 Interface — DDR PHY Interface Specification v5.1 (May 2021)
//
// Target: DDR5-6400 UDIMM, 1 rank per sub-channel, 1:4 frequency ratio
//         Controller @ 800 MHz, DRAM @ 3200 MHz
//         One instance of this interface = ONE sub-channel
//         Top level instantiates two (ch0 and ch1).
//
// Naming convention (from DFI 5.1 spec Section 3):
//   _pN  = phase-indexed command signals  (N = 0..DFI_PHASES-1 = 0..3)
//   _wN  = word-indexed data signals      (N = 0..DFI_DATA_W-1 = 0..7)
//   _aN  = clock-cycle indexed (alert)
//
//   In this interface the suffix arrays are implemented as:
//     [DFI_PHASES-1:0] for _pN signals  (4 phases for 1:4 ratio)
//     [DFI_WORDS-1:0]  for _wN signals  (8 words  for 1:4 × DDR)
//
// Directions shown are from the DFI spec perspective:
//   MC  → PHY  (MC drives, PHY consumes)
//   PHY → MC   (PHY drives, MC consumes)
//
// =====================================================================
// Interface groups implemented (all from Table 4, DFI 5.1):
//   1. Command Interface
//   2. Write Data Interface
//   3. Read Data Interface
//   4. Update Interface
//   5. Status Interface
//   6. PHY Master Interface
//   7. Disconnect / Error Interface
//   8. Low Power Control Interface
//   9. MC-to-PHY Message Interface
//  10. WCK Control Interface (LPDDR5 — included as optional, tied off)
// =====================================================================
 
`timescale 1ns/1ps
 
interface dfi5_if #(

  parameter int DFI_RATIO	= 4,
  // ---- Frequency ratio -------------------------------------------
  parameter int DFI_PHASES    = DFI_RATIO,   // command phases per ctrl clock (1:4)
  parameter int DFI_WORDS     = 16,   // DDR5 BL16 data words per transaction
 
  // ---- Address / command widths -----------------------------------
  parameter int DFI_ADDR_W    = 14,  // DDR5 CA bus (CA[13:0])
  parameter int DFI_BANK_W    = 2,   // bank addr (held 0 for DDR5)
  parameter int DFI_BG_W      = 2,   // bank group (held 0 for DDR5)
  parameter int DFI_CID_W     = 2,   // chip ID for 3DS
 
  // ---- Data widths ------------------------------------------------
  parameter int DFI_DATA_W    = 32,  // DQ bits per phase per sub-channel
  parameter int DFI_DM_W      = 4,   // DM bits  = DFI_DATA_W/8
 
  // ---- Control widths per phase ----------------------------------
  parameter int DFI_CS_W      = 1,   // chip selects (1 rank)
  parameter int DFI_CKE_W     = 1,   // CKE signals
  parameter int DFI_ODT_W     = 1,   // ODT signals
  parameter int DFI_RESET_W   = 1,   // DRAM RESET_n
  parameter int DFI_CLKDIS_W  = 1,   // dram_clk_disable
 
  // ---- Alert / Status widths -------------------------------------
  parameter int DFI_ALERT_W   = 1,
  parameter int DFI_FREQ_W    = 5,   // encoded frequency value
  parameter int DFI_FSP_W     = 2,   // frequency set point
  parameter int DFI_ERR_W     = 4,   // error info bits
 
  // ---- MC→PHY Message widths -------------------------------------
  parameter int DFI_MSG_W     = 8,   // ctrlmsg opcode
  parameter int DFI_MSG_DATA_W= 32,  // ctrlmsg data
 
  // ---- WCK (LPDDR5 only, not used for DDR5 but declared) --------
  parameter int DFI_WCK_W     = 1
)(
  input logic dfi_clk,    // DFI controller clock (800 MHz for 1:4)
  input logic dfi_rst_n   // active-low reset
);
 
  // =================================================================
  // 1. COMMAND INTERFACE  (MC → PHY, phased)
  //    DFI 5.1 Table 8 — Command Interface Signals
  //    For DDR5: dfi_address carries the CA bus (SDR, 14-bit).
  //              dfi_bank, dfi_bg, dfi_cas_n, dfi_ras_n, dfi_we_n,
  //              dfi_act_n are held at idle/default for DDR5
  //              (spec Sec 3.1.1: "held at constant values").
  // =================================================================
 
  // ---- dfi_address: DDR5 CA bus, one value per DFI phase ---------
  // MC drives one 14-bit CA word per clock phase.
  // PHY serialises onto the DRAM CA bus (SDR for DDR5).
  logic [DFI_ADDR_W-1:0]  dfi_address_p  [DFI_PHASES]; // MC→PHY
 
  // ---- Legacy command encoding signals (DDR1/2/3/4 only) --------
  // For DDR5 these must be held at their idle/default levels:
  //   dfi_act_n = 1, dfi_cas_n = 1, dfi_ras_n = 1, dfi_we_n = 1
  logic                   dfi_act_n_p    [DFI_PHASES]; // MC→PHY  default=1
  logic [DFI_BANK_W-1:0]  dfi_bank_p     [DFI_PHASES]; // MC→PHY  default=0
  logic [DFI_BG_W-1:0]    dfi_bg_p       [DFI_PHASES]; // MC→PHY  default=0
  logic                   dfi_cas_n_p    [DFI_PHASES]; // MC→PHY  default=1
  logic                   dfi_ras_n_p    [DFI_PHASES]; // MC→PHY  default=1
  logic                   dfi_we_n_p     [DFI_PHASES]; // MC→PHY  default=1
  logic [DFI_CID_W-1:0]   dfi_cid_p      [DFI_PHASES]; // MC→PHY  3DS only
 
  // ---- Chip select — one per rank, one per phase -----------------
  // Polarity same as the DRAM CS signal (DDR5 CS is active-low on DRAM,
  // but DFI polarity mirrors the DRAM signal polarity per spec Sec 3.1).
  logic [DFI_CS_W-1:0]    dfi_cs_p       [DFI_PHASES]; // MC→PHY
 
  // ---- Clock / power control signals (per phase) -----------------
  logic [DFI_CKE_W-1:0]   dfi_cke_p      [DFI_PHASES]; // MC→PHY
  logic [DFI_ODT_W-1:0]   dfi_odt_p      [DFI_PHASES]; // MC→PHY  default=0
  logic [DFI_RESET_W-1:0] dfi_reset_n_p  [DFI_PHASES]; // MC→PHY
  logic [DFI_CLKDIS_W-1:0] dfi_dram_clk_disable_p [DFI_PHASES]; // MC→PHY
 
  // ---- 2N Mode ---------------------------------------------------
  // 0 = 1N (default), 1 = 2N (MC holds CA for 2 DFI clocks)
  logic                   dfi_2n_mode_p  ; // MC→PHY  default=0
 
  // ---- CA Parity -------------------------------------------------
  // Required for DDR5 RDIMM / systems supporting CA parity.
  // Driven by MC for the PHY to forward or verify.
  logic                   dfi_parity_in_p [DFI_PHASES]; // MC→PHY  default=0
 
  // ---- Alert (CRC / CA parity error from PHY) --------------------
  // PHY asserts this when it detects a CRC or command parity error.
  // Width = DFI_ALERT_W (replicated per alert source / frequency ratio word).
  logic [DFI_ALERT_W-1:0] dfi_alert_n_a  ;  // PHY→MC  default=1
 
 
  // =================================================================
  // 2. WRITE DATA INTERFACE  (MC → PHY, phased)
  //    DFI 5.1 Table 11 — Write Data Interface Signals
  //    DDR5 BL16 exposes 16 write data transfer words per burst.
  // =================================================================
 
  // ---- Write data ------------------------------------------------
  logic [DFI_DATA_W-1:0]  dfi_wrdata_p      [DFI_WORDS]; // MC→PHY
 
  // ---- Write data enable -----------------------------------------
  // Asserted by MC to tell PHY that valid wrdata follows in tphy_wrdata
  // DFI clocks. PHY uses this to enable write path in the I/O.
  logic                   dfi_wrdata_en_p   [DFI_WORDS]; // MC→PHY  default=0
 
  // ---- Write data mask (DM / DBI) --------------------------------
  // If DBI disabled: each bit masks the corresponding write data byte.
  // If DBI enabled (phydbi_mode=0): becomes the write-DBI indicator.
  logic [DFI_DM_W-1:0]    dfi_wrdata_mask_p [DFI_WORDS]; // MC→PHY
 
  // ---- Write data chip select ------------------------------------
  // Required when NUM_CS > 1. Indicates target chip select for the
  // write data path; allows PHY to independently time each CS's data.
  logic [DFI_CS_W-1:0]    dfi_wrdata_cs_p   [DFI_WORDS]; // MC→PHY
 
  // ---- Write data ECC (Link ECC, LPDDR5 / DDR5 link ECC) --------
  // Used when phylinkecc_mode = 1. MC sends ECC alongside write data.
  logic [DFI_DM_W-1:0]    dfi_wrdata_ecc_p  [DFI_WORDS]; // MC→PHY
 
 
  // =================================================================
  // 3. READ DATA INTERFACE
  //    DFI 5.1 Table 14 — Read Data Interface Signals
  //    dfi_rddata_en is MC→PHY (command side, phased).
  //    dfi_rddata, dfi_rddata_valid are PHY→MC (word side).
  // =================================================================
 
  // ---- Read data enable (MC → PHY, phased) -----------------------
  // MC asserts this to tell PHY how many words to capture.
  // CRITICAL: PHY measures tphy_rdlat from this signal assertion
  // to know when to drive dfi_rddata_valid.
  logic                   dfi_rddata_en_p   [DFI_PHASES]; // MC→PHY  default=0
 
  // ---- Read data chip select (MC → PHY, phased) ------------------
  // Indicates which chip select the PHY's data path should target for
  // read data capture; allows per-CS timing compensation.
  logic [DFI_CS_W-1:0]    dfi_rddata_cs_p   [DFI_PHASES]; // MC→PHY
 
  // ---- Read data (PHY → MC, word-indexed) ------------------------
  logic [DFI_DATA_W-1:0]  dfi_rddata_w      [DFI_WORDS]; // PHY→MC
 
  // ---- Read data valid (PHY → MC, word-indexed) ------------------
  // PHY asserts this within tphy_rdlat cycles of dfi_rddata_en.
  // One bit per data slice (one-to-one with DFI data slices).
  logic                   dfi_rddata_valid_w [DFI_WORDS]; // PHY→MC
 
  // ---- Read DBI / Link ECC (PHY → MC, word-indexed) -------------
  // Two functions (mutually exclusive):
  //   DBI mode   : indicates whether read data byte is inverted
  //   Link ECC   : carries ECC bits returned with read data
  logic [DFI_DM_W-1:0]    dfi_rddata_dbi_w  [DFI_WORDS]; // PHY→MC
 
  // ---- Read data not valid (PHY → MC, word-indexed) --------------
  // PHY asserts individual bits to indicate the corresponding data
  // byte lane returned invalid data (e.g., DRAM did not respond).
  logic [DFI_DM_W-1:0]    dfi_rddata_dnv_w  [DFI_WORDS]; // PHY→MC
 
 
  // =================================================================
  // 4. UPDATE INTERFACE
  //    DFI 5.1 Table 17 — Update Interface Signals
  //    Allows MC or PHY to request the other pause the DFI bus
  //    to perform internal recalibration.
  // =================================================================
 
  // ---- MC-initiated update (MC → PHY, then PHY → MC ack) --------
  // MC asserts to request a PHY update (e.g., before self-refresh exit).
  logic dfi_ctrlupd_req;  // MC→PHY
  logic dfi_ctrlupd_ack;  // PHY→MC
 
  // ---- PHY-initiated update (PHY → MC, then MC → PHY ack) -------
  // PHY requests the MC to pause issuing commands while PHY re-trains.
  logic dfi_phyupd_req;   // PHY→MC
  logic dfi_phyupd_ack;   // MC→PHY
  // Update type: 0=long, 1=short, 2=channel, 3=reserved
  logic [1:0] dfi_phyupd_type; // PHY→MC
 
 
  // =================================================================
  // 5. STATUS INTERFACE
  //    DFI 5.1 Table 19 — Status Interface Signals
  //    Handshake for PHY initialisation and frequency change.
  //    dfi_init_start / dfi_init_complete is the CRITICAL handshake
  //    that gates all DRAM commands.
  // =================================================================
 
  // ---- Initialisation handshake ----------------------------------
  // MC asserts dfi_init_start with valid dfi_frequency / dfi_freq_ratio.
  // PHY completes init and asserts dfi_init_complete.
  // MC must NOT issue DRAM commands until dfi_init_complete is seen.
  logic dfi_init_start;     // MC→PHY
  logic dfi_init_complete;  // PHY→MC
 
  // ---- Frequency information (driven by MC before init_start) ----
  // dfi_frequency: encoded operating frequency (PHY maps to PLL config)
  logic [DFI_FREQ_W-1:0] dfi_frequency;   // MC→PHY
  // dfi_freq_ratio: current MC:PHY clock ratio (00=1:1, 01=1:2, 10=1:4)
  logic [1:0]             dfi_freq_ratio;  // MC→PHY
  // dfi_freq_fsp: frequency set point for FSP-aware memories (LPDDR5/DDR5)
  logic [DFI_FSP_W-1:0]  dfi_freq_fsp;    // MC→PHY
 
 
  // =================================================================
  // 6. PHY MASTER INTERFACE
  //    DFI 5.1 Table 27 — PHY Master Interface Signals
  //    PHY can request to take control of the DRAM bus (e.g., for
  //    gate training, read/write levelling, ZQ calibration).
  // =================================================================
 
  logic               dfi_phymstr_req;       // PHY→MC
  logic               dfi_phymstr_ack;       // MC→PHY
  // Type of PHY master operation requested
  // 0x0=normal, 0x1=DQS gate, 0x2=RD level, 0x3=WR level
  logic [1:0]         dfi_phymstr_type;      // PHY→MC
  // Per-CS desired chip state: 0=idle, 1=self-refresh
  logic [DFI_CS_W-1:0] dfi_phymstr_cs_state; // PHY→MC
  // 0=PHY requests IDLE state, 1=PHY requests self-refresh state
  logic               dfi_phymstr_state_sel; // PHY→MC
 
 
  // =================================================================
  // 7. DISCONNECT / ERROR INTERFACE
  //    DFI 5.1 Table 31/32 — Disconnect Protocol and Error Signals
  // =================================================================
 
  // ---- Disconnect error ------------------------------------------
  // PHY drives this when it encounters a fatal error requiring the MC
  // to stop all DFI transactions. The ongoing handshake (ctrlupd,
  // phyupd, phymstr) must be completed on error detection.
  logic dfi_disconnect_error; // PHY→MC  optional
 
  // ---- Error interface -------------------------------------------
  logic                  dfi_error;       // PHY→MC  error detected
  logic [DFI_ERR_W-1:0]  dfi_error_info;  // PHY→MC  error classification
 
 
  // =================================================================
  // 8. LOW POWER CONTROL INTERFACE
  //    DFI 5.1 Table 22 — Low Power Control Interface Signals
  //    Two independent request/ack pairs:
  //      ctrl = affects command bus (self-refresh / power-down)
  //      data = affects data bus    (data path power-down)
  // =================================================================
 
  // ---- Control low power (command bus) ---------------------------
  logic       dfi_lp_ctrl_req;       // MC→PHY  request LP for cmd bus
  logic       dfi_lp_ctrl_ack;       // PHY→MC  LP acknowledged
  // Wakeup latency code: encoded number of DFI clocks PHY needs to exit LP
  logic [4:0] dfi_lp_ctrl_wakeup;    // MC→PHY
 
  // ---- Data low power (data bus) ---------------------------------
  logic       dfi_lp_data_req;       // MC→PHY  request LP for data bus
  logic       dfi_lp_data_ack;       // PHY→MC  LP acknowledged
  logic [4:0] dfi_lp_data_wakeup;    // MC→PHY
 
 
  // =================================================================
  // 9. MC-TO-PHY MESSAGE INTERFACE  (optional)
  //    DFI 5.1 Table 33 — MC to PHY Message Interface Signals
  //    Allows MC to send opcode + data messages to PHY
  //    without using the DRAM command bus.
  //    Example uses: MRS forwarding to PHY registers, PHY config.
  // =================================================================
 
  logic [DFI_MSG_W-1:0]      dfi_ctrlmsg;      // MC→PHY  message opcode
  logic [DFI_MSG_DATA_W-1:0] dfi_ctrlmsg_data; // MC→PHY  message payload
  logic                      dfi_ctrlmsg_req;  // MC→PHY  message valid
  logic                      dfi_ctrlmsg_ack;  // PHY→MC  message accepted
 
 
  // =================================================================
  // 10. WCK CONTROL INTERFACE  (LPDDR5 only)
  //     DFI 5.1 Table 35 — WCK Control Interface Signals
  //     Not used for DDR5; declared for completeness and tied off.
  //     WCK is the write-clock for LPDDR5 (separate from CK).
  // =================================================================
 
  // Per WCK instance, per phase:
  logic [DFI_WCK_W*DFI_CS_W-1:0] dfi_wck_cs_p     [DFI_PHASES]; // MC→PHY
  logic [DFI_WCK_W-1:0]           dfi_wck_en_p     [DFI_PHASES]; // MC→PHY
  // 2 bits per WCK: 00=idle, 01=fast-toggle, 10=toggle, 11=reserved
  logic [DFI_WCK_W*2-1:0]         dfi_wck_toggle_p [DFI_PHASES]; // MC→PHY
 
 
  // =================================================================
  // MODPORTS
  // =================================================================
 
  // MC drives command + write data + rddata_en; receives rddata + status
  modport mc_mp (
    // Clock
    input  dfi_clk, dfi_rst_n,
 
    // --- Command interface: MC drives ---------
    output dfi_address_p,
    output dfi_act_n_p,
    output dfi_bank_p,
    output dfi_bg_p,
    output dfi_cas_n_p,
    output dfi_ras_n_p,
    output dfi_we_n_p,
    output dfi_cid_p,
    output dfi_cs_p,
    output dfi_cke_p,
    output dfi_odt_p,
    output dfi_reset_n_p,
    output dfi_dram_clk_disable_p,
    output dfi_2n_mode_p,
    output dfi_parity_in_p,
    input  dfi_alert_n_a,
 
    // --- Write data: MC drives ----------------
    output dfi_wrdata_p,
    output dfi_wrdata_en_p,
    output dfi_wrdata_mask_p,
    output dfi_wrdata_cs_p,
    output dfi_wrdata_ecc_p,
 
    // --- Read data: MC drives enable, PHY returns data
    output dfi_rddata_en_p,
    output dfi_rddata_cs_p,
    input  dfi_rddata_w,
    input  dfi_rddata_valid_w,
    input  dfi_rddata_dbi_w,
    input  dfi_rddata_dnv_w,
 
    // --- Update ---
    output dfi_ctrlupd_req,
    input  dfi_ctrlupd_ack,
    input  dfi_phyupd_req,
    output dfi_phyupd_ack,
    input  dfi_phyupd_type,
 
    // --- Status ---
    output dfi_init_start,
    input  dfi_init_complete,
    output dfi_frequency,
    output dfi_freq_ratio,
    output dfi_freq_fsp,
 
    // --- PHY Master ---
    input  dfi_phymstr_req,
    output dfi_phymstr_ack,
    input  dfi_phymstr_type,
    input  dfi_phymstr_cs_state,
    input  dfi_phymstr_state_sel,
 
    // --- Error / Disconnect ---
    input  dfi_disconnect_error,
    input  dfi_error,
    input  dfi_error_info,
 
    // --- Low Power ---
    output dfi_lp_ctrl_req,
    input  dfi_lp_ctrl_ack,
    output dfi_lp_ctrl_wakeup,
    output dfi_lp_data_req,
    input  dfi_lp_data_ack,
    output dfi_lp_data_wakeup,
 
    // --- Message ---
    output dfi_ctrlmsg,
    output dfi_ctrlmsg_data,
    output dfi_ctrlmsg_req,
    input  dfi_ctrlmsg_ack,
 
    // --- WCK (LPDDR5) ---
    output dfi_wck_cs_p,
    output dfi_wck_en_p,
    output dfi_wck_toggle_p
  );
 
  // PHY is the mirror of MC
  modport phy_mp (
    input  dfi_clk, dfi_rst_n,
 
    input  dfi_address_p,
    input  dfi_act_n_p,
    input  dfi_bank_p,
    input  dfi_bg_p,
    input  dfi_cas_n_p,
    input  dfi_ras_n_p,
    input  dfi_we_n_p,
    input  dfi_cid_p,
    input  dfi_cs_p,
    input  dfi_cke_p,
    input  dfi_odt_p,
    input  dfi_reset_n_p,
    input  dfi_dram_clk_disable_p,
    input  dfi_2n_mode_p,
    input  dfi_parity_in_p,
    output dfi_alert_n_a,
 
    input  dfi_wrdata_p,
    input  dfi_wrdata_en_p,
    input  dfi_wrdata_mask_p,
    input  dfi_wrdata_cs_p,
    input  dfi_wrdata_ecc_p,
 
    input  dfi_rddata_en_p,
    input  dfi_rddata_cs_p,
    output dfi_rddata_w,
    output dfi_rddata_valid_w,
    output dfi_rddata_dbi_w,
    output dfi_rddata_dnv_w,
 
    input  dfi_ctrlupd_req,
    output dfi_ctrlupd_ack,
    output dfi_phyupd_req,
    input  dfi_phyupd_ack,
    output dfi_phyupd_type,
 
    input  dfi_init_start,
    output dfi_init_complete,
    input  dfi_frequency,
    input  dfi_freq_ratio,
    input  dfi_freq_fsp,
 
    output dfi_phymstr_req,
    input  dfi_phymstr_ack,
    output dfi_phymstr_type,
    output dfi_phymstr_cs_state,
    output dfi_phymstr_state_sel,
 
    output dfi_disconnect_error,
    output dfi_error,
    output dfi_error_info,
 
    output dfi_lp_ctrl_ack,
    input  dfi_lp_ctrl_req,
    input  dfi_lp_ctrl_wakeup,
    output dfi_lp_data_ack,
    input  dfi_lp_data_req,
    input  dfi_lp_data_wakeup,
 
    output dfi_ctrlmsg_ack,
    input  dfi_ctrlmsg,
    input  dfi_ctrlmsg_data,
    input  dfi_ctrlmsg_req,
 
    input  dfi_wck_cs_p,
    input  dfi_wck_en_p,
    input  dfi_wck_toggle_p
  );
 
  // Monitor modport — all inputs for observation
  modport monitor_mp (
    input  dfi_clk, dfi_rst_n,
    input  dfi_address_p, dfi_act_n_p, dfi_bank_p, dfi_bg_p,
    input  dfi_cas_n_p, dfi_ras_n_p, dfi_we_n_p, dfi_cid_p,
    input  dfi_cs_p, dfi_cke_p, dfi_odt_p, dfi_reset_n_p,
    input  dfi_dram_clk_disable_p, dfi_2n_mode_p, dfi_parity_in_p,
    input  dfi_alert_n_a,
    input  dfi_wrdata_p, dfi_wrdata_en_p, dfi_wrdata_mask_p,
    input  dfi_wrdata_cs_p, dfi_wrdata_ecc_p,
    input  dfi_rddata_en_p, dfi_rddata_cs_p,
    input  dfi_rddata_w, dfi_rddata_valid_w, dfi_rddata_dbi_w, dfi_rddata_dnv_w,
    input  dfi_ctrlupd_req, dfi_ctrlupd_ack,
    input  dfi_phyupd_req,  dfi_phyupd_ack, dfi_phyupd_type,
    input  dfi_init_start, dfi_init_complete,
    input  dfi_frequency, dfi_freq_ratio, dfi_freq_fsp,
    input  dfi_phymstr_req, dfi_phymstr_ack, dfi_phymstr_type,
    input  dfi_phymstr_cs_state, dfi_phymstr_state_sel,
    input  dfi_disconnect_error, dfi_error, dfi_error_info,
    input  dfi_lp_ctrl_req, dfi_lp_ctrl_ack, dfi_lp_ctrl_wakeup,
    input  dfi_lp_data_req, dfi_lp_data_ack, dfi_lp_data_wakeup,
    input  dfi_ctrlmsg, dfi_ctrlmsg_data, dfi_ctrlmsg_req, dfi_ctrlmsg_ack,
    input  dfi_wck_cs_p, dfi_wck_en_p, dfi_wck_toggle_p
  );
 
endinterface : dfi5_if





//===========================================================
/*
interface dfi5_if (input logic clk, input logic rst_n);

  // ---- Control path (4 phases per controller clock) -------
  logic [DFI_CA_W-1:0]   ch0_ca_rise_p [DFI_PHASES];
  logic [DFI_CA_W-1:0]   ch0_ca_fall_p [DFI_PHASES];
  logic                  ch0_cs_n_p    [DFI_PHASES];

  logic [DFI_CA_W-1:0]   ch1_ca_rise_p [DFI_PHASES];
  logic [DFI_CA_W-1:0]   ch1_ca_fall_p [DFI_PHASES];
  logic                  ch1_cs_n_p    [DFI_PHASES];

  logic                  dfi_cke;
  logic                  dfi_reset_n;

  // ---- Write data path (8 data phases = 4 rising + 4 falling)
  logic [31:0]           ch0_wrdata_p    [DFI_DATA_PHASES];
  logic [3:0]            ch0_wrdm_p      [DFI_DATA_PHASES];
  logic                  ch0_wrdata_en_p [DFI_DATA_PHASES];

  logic [31:0]           ch1_wrdata_p    [DFI_DATA_PHASES];
  logic [3:0]            ch1_wrdm_p      [DFI_DATA_PHASES];
  logic                  ch1_wrdata_en_p [DFI_DATA_PHASES];

  // ---- Read data path
  logic [31:0]           ch0_rddata_p    [DFI_DATA_PHASES];
  logic                  ch0_rddata_vld_p[DFI_DATA_PHASES];

  logic [31:0]           ch1_rddata_p    [DFI_DATA_PHASES];
  logic                  ch1_rddata_vld_p[DFI_DATA_PHASES];

  // ---- Update interface
  logic                  ctrlupd_req;
  logic                  ctrlupd_ack;

  // Monitor clocking block
  clocking monitor_cb @(posedge clk);
    default input #1;
    input ch0_ca_rise_p, ch0_ca_fall_p, ch0_cs_n_p;
    input ch1_ca_rise_p, ch1_ca_fall_p, ch1_cs_n_p;
    input dfi_cke, dfi_reset_n;
    input ch0_wrdata_p, ch0_wrdm_p, ch0_wrdata_en_p;
    input ch1_wrdata_p, ch1_wrdm_p, ch1_wrdata_en_p;
    input ch0_rddata_p, ch0_rddata_vld_p;
    input ch1_rddata_p, ch1_rddata_vld_p;
    input ctrlupd_req;
    output ctrlupd_ack;
  endclocking

  modport ctrl_side (
    output ch0_ca_rise_p, ch0_ca_fall_p, ch0_cs_n_p,
    output ch1_ca_rise_p, ch1_ca_fall_p, ch1_cs_n_p,
    output dfi_cke, dfi_reset_n,
    output ch0_wrdata_p, ch0_wrdm_p, ch0_wrdata_en_p,
    output ch1_wrdata_p, ch1_wrdm_p, ch1_wrdata_en_p,
    input  ch0_rddata_p, ch0_rddata_vld_p,
    input  ch1_rddata_p, ch1_rddata_vld_p,
    output ctrlupd_req, input ctrlupd_ack
  );

  modport phy_side (
    input  ch0_ca_rise_p, ch0_ca_fall_p, ch0_cs_n_p,
    input  ch1_ca_rise_p, ch1_ca_fall_p, ch1_cs_n_p,
    input  dfi_cke, dfi_reset_n,
    input  ch0_wrdata_p, ch0_wrdm_p, ch0_wrdata_en_p,
    input  ch1_wrdata_p, ch1_wrdm_p, ch1_wrdata_en_p,
    output ch0_rddata_p, ch0_rddata_vld_p,
    output ch1_rddata_p, ch1_rddata_vld_p,
    input  ctrlupd_req, output ctrlupd_ack
  );

  modport monitor_mp (clocking monitor_cb, input clk, rst_n);

endinterface : dfi5_if
*/
