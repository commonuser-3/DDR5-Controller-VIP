`timescale 1ps / 1ps
`include "./memory_module/ddr5_6400_parameters.sv"

// =============================================================================
// File      : ddr5.sv
// Version   : 6.0  —  DDR5-3200 JEDEC JESD79-5B  DUAL-CHANNEL x8 IMPLEMENTATION
//
// ─────────────────────────────────────────────────────────────────────────────
// DUAL-CHANNEL ARCHITECTURE (per your hand-drawn spec):
//
//   Top-level pins (from controller / DRAM interface):
//     CK_T[1:0]   — CK_T[0] → Channel 0,  CK_T[1] → Channel 1
//     CK_C[1:0]   — CK_C[0] → Channel 0,  CK_C[1] → Channel 1
//     CS_N[1:0]   — CS_N[0] → Channel 0,  CS_N[1] → Channel 1
//     CA[27:0]    — CA[13:0] → Channel 0, CA[27:14] → Channel 1
//     DQS_T[7:0]  — DQS_T[3:0] → Channel 0, DQS_T[7:4] → Channel 1
//     DQS_C[7:0]  — DQS_C[3:0] → Channel 0, DQS_C[7:4] → Channel 1
//     DQ[63:0]    — DQ[31:0]   → Channel 0, DQ[63:32]   → Channel 1
//     DMI[7:0]    — DMI[3:0]   → Channel 0, DMI[7:4]    → Channel 1
//
//   Each channel has 4 x8 devices:
//     Channel 0: Device 0 (DQS_T/C[0], DQ[7:0])
//                Device 1 (DQS_T/C[1], DQ[15:8])
//                Device 2 (DQS_T/C[2], DQ[23:16])
//                Device 3 (DQS_T/C[3], DQ[31:24])
//     Channel 1: Device 0 (DQS_T/C[4], DQ[39:32])
//                Device 1 (DQS_T/C[5], DQ[47:40])
//                Device 2 (DQS_T/C[6], DQ[55:48])
//                Device 3 (DQS_T/C[7], DQ[63:56])
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA FLOW:
//   Correct single-channel behavior summary:
//   AXI sends 8 beats x 64 bits into the controller.
//   The controller and DRAM DQ bus remain 64 bits wide, but DCH selects one
//   active 32-bit half per burst.
//   DCH=0 -> AXI beat[31:0] drives DQ[31:0] and only Channel 0 stores data.
//   DCH=1 -> AXI beat[63:32] drives DQ[63:32] and only Channel 1 stores data.
//   BL16 still spans 16 DQS edges, so each edge carries one 32-bit sample for
//   the selected channel. In the current write path, edges 0..7 are real data
//   and edges 8..15 are zero padding.
//   Legacy lines below are obsolete and should be ignored.
//   AXI → 64-bit → Controller → DRAM Interface (64-bit)
//   At DRAM interface: lower 32 bits (DQ[31:0])  → Channel 0 (first  CK edge)
//                      upper 32 bits (DQ[63:32]) → Channel 1 (first  CK edge)
//   Both channels write/read simultaneously but independently.
//   Each channel has its own memory array, bank state, and pipeline.
//
// ─────────────────────────────────────────────────────────────────────────────
// JEDEC MR0 / Command encoding: unchanged from v5.0 — see original header.
// =============================================================================

module ddr5 (
    mem_if.mem_sig dram_if,
    output logic        rd_valid0,
    output logic [511:0] rd_data0,
    output logic        rd_valid1,
    output logic [511:0] rd_data1
);

    `define DQ_PER_DQS   (DQ_BITS / DQS_BITS)   //   64 / 8 = 8 bits per DQS  (x8 per device, 8 devices total)
    `define DQ_PER_CH    (DQ_BITS / 2)           // 32  bits per channel
    `define DQS_PER_CH   (DQS_BITS / 2)          // 4   DQS strobes per channel
    `define DM_PER_CH    (DM_BITS / 2)           // 4   DMI bits per channel
    `define NUM_BANKS    (1 << TOTAL_BA_BITS)    // 16  (4BG × 4 banks)
    `define MAX_BITS     (TOTAL_BA_BITS + ROW_BITS + COL_BITS - BL_BITS)
    `define MEM_SIZE     (1 << MEM_BITS)
    `define MAX_PIPE     (4 * CL_MAX)

    // =========================================================================
    // JEDEC reset initialization timing
    //
    // The exact JEDEC numbers are kept for protocol reporting.
    // Shortened MODEL values keep the reset flow practical in simulation.
    //
    // RESET_n is shared across both channels.
    // CS_n and reset_init_done[] remain per-channel.
    // =========================================================================
    localparam time TINIT1_JEDEC_PS = 200_000_000;   // 200 us
    localparam time TINIT2_JEDEC_PS =     10_000;    // 10 ns
    localparam time TINIT3_JEDEC_PS = 64'd4_000_000_000; // 4 ms
    localparam time TINIT4_JEDEC_PS =  2_000_000;    // 2 us
    localparam int  TINIT5_MIN_CK   = 3;             // 3 NOP clock cycles

    // Simulation-friendly gates.
    // Project notes explicitly use #1000 as an example for the shortened
    // tINIT1 wait, so the model follows that convention.
    localparam time TINIT1_MODEL_PS =      10_000;
    localparam time TINIT3_MODEL_PS =     20_000;
    localparam time TINIT4_MODEL_PS =      1_000;

    // =========================================================================
    // Mode Registers  (256 × 8-bit)  — shared between channels (same DIMM)
    // =========================================================================
    reg [7:0] mr [0:255];

    // =========================================================================
    // Latency / init — shared (both channels trained identically)
    // =========================================================================
    integer  cas_latency;
    integer  cas_write_latency;
    integer  read_latency;
    integer  write_latency;
    integer  burst_length;
    reg      init_done;
    integer  init_step;

    // =========================================================================
    // Clock tracking — one set per channel
    // =========================================================================
    integer  ck_cnt       [1:0];
    real     tck_avg      [1:0];
    time     tm_ck_pos    [1:0];
    reg      prev_cke     [1:0];

    // =========================================================================
    // Reset / initialization trackers
    //
    // tm_reset_*           : shared RESET_n timestamps
    // tm_csn_low/high      : per-channel CS_n timestamps
    // tinit*_done          : step-by-step status flags
    // tinit5_ck_start[ch]  : ck_cnt snapshot taken when tINIT4 completes
    // reset_init_done[ch]  : final gate before cmd_task can accept real traffic
    // =========================================================================
    time     tm_reset_assert;
    time     tm_reset_deassert;
    time     tm_csn_low       [1:0];
    time     tm_csn_high      [1:0];
    reg      tinit1_done;
    reg      tinit2_done      [1:0];
    reg      tinit3_done      [1:0];
    reg      tinit4_done      [1:0];
    integer  tinit5_ck_start  [1:0];
    reg      reset_init_done  [1:0];

    // =========================================================================
    // Bank state — one set per channel (16 banks each)
    // =========================================================================
    reg [`NUM_BANKS-1:0]  bank_active [1:0];
    reg [ROW_BITS-1:0]    bank_row    [1:0][`NUM_BANKS-1:0];
    reg [`NUM_BANKS-1:0]  bank_ap     [1:0];
    reg [`NUM_BANKS-1:0]  bank_wr_ap  [1:0];
    reg [`NUM_BANKS-1:0]  bank_rd_ap  [1:0];

    // =========================================================================
    // 2-cycle command tracking — one set per channel
    // =========================================================================
    reg          act_c1   [1:0];
    reg [13:0]   act_ca1  [1:0];
    reg [TOTAL_BA_BITS-1:0] act_bank [1:0];

    reg          wr_c1    [1:0];
    reg [TOTAL_BA_BITS-1:0] wr_bank  [1:0];
    reg          wr_bl_star [1:0];

    reg          rd_c1    [1:0];
    reg [TOTAL_BA_BITS-1:0] rd_bank  [1:0];
    reg          rd_bl_star [1:0];

    reg          mrw_c1   [1:0];
    reg [7:0]    mrw_addr [1:0];

    reg [TOTAL_BA_BITS-1:0] current_wr_bank [1:0];
    reg [TOTAL_BA_BITS-1:0] current_rd_bank [1:0];

    // =========================================================================
    // Command FSM state - one visible state register per channel
    // =========================================================================
    localparam [3:0]
        CMD_ST_IDLE      = 4'd0,
        CMD_ST_ACTIVATE  = 4'd1,
        CMD_ST_WRITE     = 4'd2,
        CMD_ST_READ      = 4'd3,
        CMD_ST_MRW       = 4'd4,
        CMD_ST_PRECHARGE = 4'd5,
        CMD_ST_REFRESH   = 4'd6,
        CMD_ST_POWER     = 4'd7,
        CMD_ST_NOP       = 4'd8,
        CMD_ST_UNKNOWN   = 4'd9;

    reg [3:0] cmd_state [1:0];

    // =========================================================================
    // Memory arrays — one per channel (independent 1024-entry stores)
    // =========================================================================
    // Shared physical backing store. Channel selects the DQ slice; it is not
    // part of the memory key.
    reg [BL_MAX*`DQ_PER_CH-1:0]  mem_arr  [0:`MEM_SIZE-1];
    reg [`MAX_BITS-1:0]           mem_adr  [0:`MEM_SIZE-1];
    reg [MEM_BITS:0]               mem_idx;
    reg [MEM_BITS:0]               mem_used;

    // =========================================================================
    // Pipelines — one set per channel
    // =========================================================================
    reg [`MAX_PIPE:0]           wr_pipe  [1:0];
    reg [`MAX_PIPE:0]           rd_pipe  [1:0];
    reg [BL_BITS:0]             bl_pipe  [1:0][`MAX_PIPE:0];
    reg [TOTAL_BA_BITS-1:0]     ba_pipe  [1:0][`MAX_PIPE:0];
    reg [ROW_BITS-1:0]          row_pipe [1:0][`MAX_PIPE:0];
    reg [COL_BITS-1:0]          col_pipe [1:0][`MAX_PIPE:0];

    // =========================================================================
    // Input registers (delayed by BUS_DELAY ps)
    // =========================================================================
    reg          rst_n_r;

    // Per-channel control inputs
    reg          ckt_r   [1:0];   // CK_T[0] → ch0,  CK_T[1] → ch1
    reg          ckc_r   [1:0];   // CK_C[0] → ch0,  CK_C[1] → ch1
    reg          cke_r   [1:0];   // shared CKE (single pin, both channels)
    reg          csn_r   [1:0];   // CS_N[0] → ch0, CS_N[1] → ch1
    reg [13:0]   ca_r    [1:0];   // CA[13:0] → ch0, CA[27:14] → ch1

    // Per-channel data inputs (32 bits per channel)
    reg [`DM_PER_CH-1:0]  dmi_r  [1:0];   // DMI[3:0] → ch0, DMI[7:4] → ch1
    reg [`DQ_PER_CH-1:0]  dq_r   [1:0];   // DQ[31:0] → ch0, DQ[63:32] → ch1

    // Per-channel DQS (4 DQS per channel, packed as 32-bit even/odd pairs)
    reg [31:0]   dqs_r   [1:0];   // lower 16 = dqs_t, upper 16 = dqs_c

    reg diff_ck [1:0];

    // Channel-sliced DQS even (rising) and odd (falling) — 16 bits each per channel
    wire [`DQS_PER_CH-1:0] dqs_even [1:0];
    wire [`DQS_PER_CH-1:0] dqs_odd  [1:0];

//dqs_even[0] = channel 0 even DQS
//dqs_even[1] = channel 1 even DQS

//dqs_odd[0]  = channel 0 odd DQS
//dqs_odd[1]  = channel 1 odd DQS



    assign dqs_even[0] = dqs_r[0][`DQS_PER_CH-1:0];           // DQS_T[3:0]
    assign dqs_odd [0] = dqs_r[0][2*`DQS_PER_CH-1:`DQS_PER_CH]; // DQS_C[3:0] re-mapped as "odd"
      

    assign dqs_even[1] = dqs_r[1][`DQS_PER_CH-1:0];           // DQS_T[7:4]
    assign dqs_odd [1] = dqs_r[1][2*`DQS_PER_CH-1:`DQS_PER_CH]; // DQS_C[7:4] re-mapped as "odd"

    // =========================================================================
    // Write data state — one per channel
    // =========================================================================
    reg [BL_MAX*`DQ_PER_CH-1:0]  burst_data    [1:0];
    reg [BL_MAX*DQ_BITS-1:0]     burst_bus64   [1:0];
    reg [BL_MAX*`DQ_PER_CH-1:0]  rd_burst_data [1:0];
    reg [BL_MAX*`DQ_PER_CH-1:0]  burst_mask    [1:0];
    reg [BL_BITS-1:0]              burst_pos     [1:0];
    reg [BL_BITS:0]                burst_cnt     [1:0];
    reg [BL_BITS:0]                rd_burst_cnt  [1:0];
    reg [BL_BITS-1:0]              rd_burst_pos  [1:0];
    reg [`DQ_PER_CH-1:0]           dq_temp       [1:0];
    reg                            dq_valid      [1:0];
    reg                            dqs_valid     [1:0];
    reg                            dch           [1:0];   // 0=lower half, 1=upper half
    integer                        wdq_cnt       [1:0];
    integer                        wdqs_pos_cnt  [1:0][63:0];
    reg [BL_BITS:0]                wr_bl         [1:0];
    reg                            b2b_wr        [1:0];
    reg                            wr_burst_active    [1:0];
    integer                        wr_start_skip_cnt  [1:0];
    reg                            dq_pos_seen   [1:0];
    reg                            dq_neg_seen   [1:0];
    reg [`DM_PER_CH-1:0]           dm_pos        [1:0];
    reg [`DM_PER_CH-1:0]           dm_neg        [1:0];
    reg [127:0]                    dq_pos_acc    [1:0];  // accumulator for rising  DQS edges
    reg [127:0]                    dq_neg_acc    [1:0];  // accumulator for falling DQS edges
    reg [`DQ_PER_CH-1:0]           dq_phase_rise [1:0];
    reg [`DQ_PER_CH-1:0]           dq_phase_fall [1:0];
    reg [`DM_PER_CH-1:0]           dm_phase_rise [1:0];
    reg [`DM_PER_CH-1:0]           dm_phase_fall [1:0];
    reg [`DQ_PER_CH-1:0]           dq_first_hint [1:0];
    reg                            dq_first_hint_valid [1:0];

    // =========================================================================
    // Output registers — one per channel
    // =========================================================================
    reg                            out_en      [1:0];
    reg                            dqs_oe      [1:0];
    reg [`DQS_PER_CH-1:0]          dqs_oe_d    [1:0];
    reg                            dqs_out     [1:0];
    reg [`DQS_PER_CH-1:0]          dqs_out_d   [1:0];
    reg                            dq_oe       [1:0];
    reg [`DQ_PER_CH-1:0]           dq_oe_d     [1:0];
    reg [`DQ_PER_CH-1:0]           dq_out      [1:0];
    reg [`DQ_PER_CH-1:0]           dq_out_d    [1:0];
    integer                        rdqsen_cnt  [1:0];
    integer                        rdqs_cnt    [1:0];
    integer                        rdqen_cnt   [1:0];
    integer                        rdq_cnt     [1:0];

    // =========================================================================
    // Output tri-state buffers — Channel 0: DQS_T/C[3:0], DQ[31:0]
    //                            Channel 1: DQS_T/C[7:4], DQ[63:32]
    // =========================================================================
    bufif1 buf_dqs_t_ch0 [`DQS_PER_CH-1:0]
        (dram_if.dqs_t[`DQS_PER_CH-1:0],
         dqs_out_d[0],
         dqs_oe_d[0] & {`DQS_PER_CH{out_en[0]}});

    bufif1 buf_dqs_c_ch0 [`DQS_PER_CH-1:0]
        (dram_if.dqs_c[`DQS_PER_CH-1:0],
         ~dqs_out_d[0],
         dqs_oe_d[0] & {`DQS_PER_CH{out_en[0]}});

    bufif1 buf_dq_ch0    [`DQ_PER_CH-1:0]
        (dram_if.dq[`DQ_PER_CH-1:0],
         dq_out_d[0],
         dq_oe_d[0] & {`DQ_PER_CH{out_en[0]}});

    bufif1 buf_dqs_t_ch1 [`DQS_PER_CH-1:0]
        (dram_if.dqs_t[DQS_BITS-1:`DQS_PER_CH],
         dqs_out_d[1],
         dqs_oe_d[1] & {`DQS_PER_CH{out_en[1]}});

    bufif1 buf_dqs_c_ch1 [`DQS_PER_CH-1:0]
        (dram_if.dqs_c[DQS_BITS-1:`DQS_PER_CH],
         ~dqs_out_d[1],
         dqs_oe_d[1] & {`DQS_PER_CH{out_en[1]}});

    bufif1 buf_dq_ch1    [`DQ_PER_CH-1:0]
        (dram_if.dq[DQ_BITS-1:`DQ_PER_CH],
         dq_out_d[1],
         dq_oe_d[1] & {`DQ_PER_CH{out_en[1]}});

    // =========================================================================
    // Input sampling with BUS_DELAY — control signals
    //
    //
    //1. Samples external DDR interface pins
    //2. Adds realistic bus delay
    //3. Splits signals into Channel-0 and Channel-1
    // 4. Prepares DQ/DQS data for write capture
    //
    //
    //
    // =========================================================================
    always @(dram_if.reset_n)   rst_n_r    <= #BUS_DELAY dram_if.reset_n;
   //Whenever the interface reset signal changes, update the DRAM internal reset signal after a small propagation delay
    always @(dram_if.ck_t)   begin
        ckt_r[0] <= #BUS_DELAY dram_if.ck_t[0];
        ckt_r[1] <= #BUS_DELAY dram_if.ck_t[1];
    end
    always @(dram_if.ck_c)   begin
        ckc_r[0] <= #BUS_DELAY dram_if.ck_c[0];
        ckc_r[1] <= #BUS_DELAY dram_if.ck_c[1];
    end
    always @(dram_if.cke) begin
        cke_r[0] <= #BUS_DELAY dram_if.cke;
        cke_r[1] <= #BUS_DELAY dram_if.cke;
    end

    always @(dram_if.cs_n) begin
        csn_r[0] <= #BUS_DELAY dram_if.cs_n[0];
        csn_r[1] <= #BUS_DELAY dram_if.cs_n[1];
    end

    always @(dram_if.ca) begin
        ca_r[0] <= #BUS_DELAY dram_if.ca[13:0];
        ca_r[1] <= #BUS_DELAY dram_if.ca[27:14];
    end

    always @(dram_if.dch) begin
        dch[0] <= #BUS_DELAY dram_if.dch;
        dch[1] <= #BUS_DELAY dram_if.dch;
        $display("[DDR5 MODEL] DCH pin=%b selects CH%0d time=%t",
                 dram_if.dch,
                 (dram_if.dch === 1'b1) ? 1 : 0,
                 $time);
    end

    // DMI: [3:0] → channel 0,  [7:4] → channel 1
    always @(dram_if.dmi) begin
        dmi_r[0] <= #BUS_DELAY dram_if.dmi[`DM_PER_CH-1:0];
        dmi_r[1] <= #BUS_DELAY dram_if.dmi[DM_BITS-1:`DM_PER_CH];
    end

    // DQ: [31:0] → channel 0,  [63:32] → channel 1
    always @(dram_if.dq) begin
        dq_r[0] <= #BUS_DELAY dram_if.dq[`DQ_PER_CH-1:0];
        dq_r[1] <= #BUS_DELAY dram_if.dq[DQ_BITS-1:`DQ_PER_CH];
        if ((dram_if.dq[`DQ_PER_CH-1:0] !== {`DQ_PER_CH{1'b0}}) &&
            (dram_if.dq[`DQ_PER_CH-1:0] !== {`DQ_PER_CH{1'bz}}) &&
            (dram_if.dq[`DQ_PER_CH-1:0] !== {`DQ_PER_CH{1'bx}})) begin
            dq_first_hint[0]       <= #BUS_DELAY dram_if.dq[`DQ_PER_CH-1:0];
            dq_first_hint_valid[0] <= #BUS_DELAY 1'b1;
        end
    end

    // DQS: [3:0] t/c → channel 0,  [7:4] t/c → channel 1
    always @(dram_if.dq or dram_if.dmi or dram_if.dqs_t or dram_if.dqs_c) begin
        if ((dram_if.dqs_t[`DQS_PER_CH-1:0] == {`DQS_PER_CH{1'b0}}) &&
            (dram_if.dqs_c[`DQS_PER_CH-1:0] == {`DQS_PER_CH{1'b1}})) begin
            dq_phase_rise[0] = dram_if.dq[`DQ_PER_CH-1:0];
            dm_phase_rise[0] = dram_if.dmi[`DM_PER_CH-1:0];
        end

        if ((dram_if.dqs_t[DQS_BITS-1:`DQS_PER_CH] == {`DQS_PER_CH{1'b1}}) &&
            (dram_if.dqs_c[DQS_BITS-1:`DQS_PER_CH] == {`DQS_PER_CH{1'b0}})) begin
            dq_phase_fall[1] = dram_if.dq[DQ_BITS-1:`DQ_PER_CH];
            dm_phase_fall[1] = dram_if.dmi[DM_BITS-1:`DM_PER_CH];
        end
    end



          // This block monitors the DDR5 DQS strobes.

    always @(dram_if.dqs_t or dram_if.dqs_c) begin
        // Channel 0: DQS_T[3:0], DQS_C[3:0]
        dqs_r[0] <= #BUS_DELAY
            {dram_if.dqs_c[`DQS_PER_CH-1:0], dram_if.dqs_t[`DQS_PER_CH-1:0]};
         // DQS_BITS = 8 
	 // DQS_PER_CH = 8/2 = 4
	 // SO
	 //dram_if.dqs_t[3:0]
         //dram_if.dqs_c[3:0]


        // Channel 1: DQS_T[7:4], DQS_C[7:4]
        dqs_r[1] <= #BUS_DELAY
            {dram_if.dqs_c[DQS_BITS-1:`DQS_PER_CH], dram_if.dqs_t[DQS_BITS-1:`DQS_PER_CH]};
//dqs_r[0] = {DQS_C[3:0], DQS_T[3:0]}

	    if ((!$isunknown(dram_if.dqs_t[`DQS_PER_CH-1:0]) &&
              !$isunknown(dram_if.dqs_c[`DQS_PER_CH-1:0]))  ||      //---> CHANNEL 0 
	   
	      //CH0 DQS_T and DQS_C both contain valid values"
	      //(!$isunknown(dqs_t[3:0]) &&
               // !$isunknown(dqs_c[3:0]))
	      //

            (!$isunknown(dram_if.dqs_t[DQS_BITS-1:`DQS_PER_CH]) &&
              !$isunknown(dram_if.dqs_c[DQS_BITS-1:`DQS_PER_CH]))) // ----> CHANNEL 1 



      	      $display("MEMORY MODEL DQS dq64=%h  CH0 dqs_t=%h dqs_c=%h  CH1 dqs_t=%h dqs_c=%h  time=%t",
            dram_if.dq,
            dram_if.dqs_t[`DQS_PER_CH-1:0],   dram_if.dqs_c[`DQS_PER_CH-1:0],
            dram_if.dqs_t[DQS_BITS-1:`DQS_PER_CH], dram_if.dqs_c[DQS_BITS-1:`DQS_PER_CH],
            $time);

	    //assign dqs_even[0] = dqs_r[0][3:0];
            //assign dqs_odd[0]  = dqs_r[0][7:4];
    end

    // Differential clock reconstruction per channel
    always @(posedge ckt_r[0]) diff_ck[0] <= 1'b1;
    always @(posedge ckc_r[0]) diff_ck[0] <= 1'b0;
    always @(posedge ckt_r[1]) diff_ck[1] <= 1'b1;
    always @(posedge ckc_r[1]) diff_ck[1] <= 1'b0;

    // =========================================================================
    // Initial
    // =========================================================================
    initial begin
        $timeformat(-12, 1, " ps", 1);
        mem_used = 0;
        for (int c = 0; c < 2; c++) begin
            ck_cnt[c]    = 0;
            tck_avg[c]   = 625.0;
            tm_ck_pos[c] = 0;
            tm_csn_low[c]   = 0;
            tm_csn_high[c]  = 0;
            act_c1[c]    = 0;
            wr_c1[c]     = 0;
            rd_c1[c]     = 0;
            mrw_c1[c]    = 0;
            cmd_state[c] = CMD_ST_IDLE;
            diff_ck[c]   = 0;
            tinit2_done[c]      = 1'b0;
            tinit3_done[c]      = 1'b0;
            tinit4_done[c]      = 1'b0;
            tinit5_ck_start[c]  = -1;
            reset_init_done[c]  = 1'b0;
        end
        tm_reset_assert   = 0;
        tm_reset_deassert = 0;
        tinit1_done       = 1'b0;
    end

    // =========================================================================
    // Memory helpers — parameterised on channel index
    // =========================================================================
    function get_idx;
        input integer ch;
        input [`MAX_BITS-1:0] a;
        begin : lp
            get_idx = 0;
            for (mem_idx = 0; mem_idx < mem_used; mem_idx = mem_idx + 1)
                if (mem_adr[mem_idx] == a) begin
                    get_idx = 1;
                    disable lp;
                end
        end
    endfunction

    task mem_wr_task;
        input integer                             ch;
        input [TOTAL_BA_BITS-3:0]                 bank;
        input [TOTAL_BA_BITS-1:TOTAL_BA_BITS-2]   bank_group;
        input [ROW_BITS-1:0]                      row;
        input [COL_BITS-1:0]                      col;
        input [BL_MAX*`DQ_PER_CH-1:0]             dt;
        reg [`MAX_BITS-1:0] a;
        begin
            a = {bank_group, bank, row, col[COL_BITS-1:BL_BITS]};
            if (get_idx(ch, a)) begin
                mem_adr[mem_idx] = a;
                mem_arr[mem_idx] = dt;
                $display("╔══ DUAL-CHANNEL STORE -> MEMORY ARRAY STORE ══╗");
                $display("║ CHANNEL %0d  UPDATE      ║  addr=%h  data=%h  time=%t",
                         ch, a, dt, $time);
                $display("╚════════════════════════╝");
            end else if (mem_used == `MEM_SIZE) begin
                $display("[CH%0d] ERROR: memory overflow at %0t", ch, $time);
            end else begin
                mem_adr[mem_used] = a;
                mem_arr[mem_used] = dt;
                $display("╔══════════════════════════════════════════════╗");
                $display("║  DUAL-CHANNEL MEMORY WRITE                   ║");
                $display("║  CHANNEL %0d (%s)                    ║",
                         ch, (ch==0) ? "DQ[31:0]  = LOWER 32 BITS" : "DQ[63:32] = UPPER 32 BITS");
                $display("║  BG=%h  BA=%h  ROW=%h  COL=%h  ║",
                         bank_group, bank, row, col);
                $display("║  CHANNEL_DATA_512 = %h  ║", dt);
                $display("╚══════════════════════════════════════════════╝");
                mem_used = mem_used + 1;
            end
            $display("[CH%0d] WRITE addr/channel_data_512: addr=%h data=%h time=%t",
                     ch, a, dt, $time);
        end
    endtask

    task mem_rd_task;
        input  integer                            ch;
        input  [TOTAL_BA_BITS-3:0]                bank;
        input  [TOTAL_BA_BITS-1:TOTAL_BA_BITS-2]  bank_group;
        input  [ROW_BITS-1:0]                     row;
        input  [COL_BITS-1:0]                     col;
        output [BL_MAX*`DQ_PER_CH-1:0]            dt;
        reg [`MAX_BITS-1:0] a;
        begin
            a  = {bank_group, bank, row, col[COL_BITS-1:BL_BITS]};
            if (get_idx(ch, a)) begin
                dt = mem_arr[mem_idx];
                $display("[CH%0d] READ addr/data: addr=%h data=%h time=%t",
                         ch, a, dt, $time);
            end else begin
                dt = '0;
                $display("[CH%0d] READ MISS addr=%h returning zero time=%t",
                         ch, a, $time);
            end
        end
    endtask

    // =========================================================================
    // set_latency
    // =========================================================================
    task set_latency;
        begin
            read_latency      = cas_latency;
            cas_write_latency = cas_latency - 2;
            write_latency     = cas_write_latency;
        end
    endtask

    // =========================================================================
    // reset_task
    // =========================================================================
    task reset_task;
        integer i, c;
        begin
            mem_used = 0;
            tm_reset_deassert = 0;
            tinit1_done       = 1'b0;
            for (c = 0; c < 2; c++) begin
                ck_cnt[c]              = 0;
                tm_ck_pos[c]           = 0;
                tm_csn_low[c]          = 0;
                tm_csn_high[c]         = 0;
                tinit2_done[c]         = 1'b0;
                tinit3_done[c]         = 1'b0;
                tinit4_done[c]         = 1'b0;
                tinit5_ck_start[c]     = -1;
                reset_init_done[c]     = 1'b0;
                dq_valid[c]           = 0;
                dqs_valid[c]         <= 0;
                wdq_cnt[c]            = 0;
                b2b_wr[c]            <= 0;
                dch[c]                = 1'b0;
                wr_burst_active[c]    = 0;
                wr_start_skip_cnt[c]  = 0;
                dq_pos_seen[c]        = 0;
                dq_neg_seen[c]        = 0;
                for (i = 0; i < 64; i++) wdqs_pos_cnt[c][i] <= 0;
                out_en[c]    = 0;
                dq_oe[c]     = 0;
                rdq_cnt[c]   = 0;
                dqs_oe[c]    = 0;
                rdqs_cnt[c]  = 0;
                rdqsen_cnt[c]= 0;
                rdqen_cnt[c] = 0;
                bank_active[c] = 0;
                bank_ap[c]     = 0;
                bank_rd_ap[c]  = 0;
                bank_wr_ap[c]  = 0;
                act_c1[c]  = 0;
                wr_c1[c]   = 0;
                rd_c1[c]   = 0;
                mrw_c1[c]  = 0;
                cmd_state[c] = CMD_ST_IDLE;
                current_wr_bank[c] = 0;
                current_rd_bank[c] = 0;
                prev_cke[c]  = 1'bx;
                wr_pipe[c]   = 0;
                rd_pipe[c]   = 0;
                burst_data[c]    = '0;
                burst_bus64[c]   = '0;
                rd_burst_data[c] = '0;
                if (c == 0) begin
                    rd_valid0 = 1'b0;
                    rd_data0  = '0;
                end else begin
                    rd_valid1 = 1'b0;
                    rd_data1  = '0;
                end
                burst_mask[c]    = '0;
                dq_temp[c]       = '0;
                dq_out[c]        = '0;
                dq_pos_acc[c] = 0;
                dq_neg_acc[c] = 0;
                dq_phase_rise[c] = 0;
                dq_phase_fall[c] = 0;
                dm_phase_rise[c] = 0;
                dm_phase_fall[c] = 0;
                dq_first_hint[c] = 0;
                dq_first_hint_valid[c] = 0;
                for (i = 0; i <= `MAX_PIPE; i = i + 1) begin
                    bl_pipe [c][i] = 0;
                    ba_pipe [c][i] = 0;
                    row_pipe[c][i] = 0;
                    col_pipe[c][i] = 0;
                end
            end
            cas_latency  = CL_MIN;
            burst_length = BL_MAX;
            set_latency;
            init_done    = 0;
            init_step    = 0;
        end
    endtask

    // =========================================================================
    // report_reset_init_block
    //
    // This helper prints a simple reason when cmd_task sees a real command
    // before the reset/initialization window is complete for that channel.
    // =========================================================================
    task automatic report_reset_init_block;
        input integer ch;
        input [13:0]  c_ca;
        begin
		// THIS CHECKS IF EACH PPARAMETER HAS OCCURED OR NOT 
            if (!tinit1_done)
                $display("[CH%0d] RESET-INIT BLOCK: CA=0x%04h ignored because shared tINIT1 is not complete at %0t",
                         ch, c_ca, $time);
            else if (!tinit2_done[ch])
                $display("[CH%0d] RESET-INIT BLOCK: CA=0x%04h ignored because tINIT2 (CS_n LOW before RESET_n HIGH) is not complete at %0t",
                         ch, c_ca, $time);
            else if (!tinit3_done[ch])
                $display("[CH%0d] RESET-INIT BLOCK: CA=0x%04h ignored because tINIT3 (post-reset CS_n LOW hold) is not complete at %0t",
                         ch, c_ca, $time);
            else if (!tinit4_done[ch])
                $display("[CH%0d] RESET-INIT BLOCK: CA=0x%04h ignored because tINIT4 (CS_n HIGH settle time) is not complete at %0t",
                         ch, c_ca, $time);
            else
                $display("[CH%0d] RESET-INIT BLOCK: CA=0x%04h ignored because tINIT5 (3 NOP clocks after CS_n HIGH) is not complete at %0t",
                         ch, c_ca, $time);
        end
    endtask

    // =========================================================================
    // cmd_task — JEDEC Table 31 Command Decoder (per channel)
    // =========================================================================
    // cmd_state[ch] is updated in each state section so the command decoder is
    // easy to follow in code and waveform, with the original actions unchanged.
    // =========================================================================
    // update_reset_init_progress
    //
    // Called on each posedge diff_ck[ch].
    // It advances the per-channel post-reset state machine after CS_n has
    // legally risen->After RESET and CS timing pass:
    //   1. wait tINIT4 after CS_n HIGH
    //   2. remember ck_cnt[ch] when tINIT4 completes
    //   3. count 3 extra NOP clock edges for tINIT5
    //   4. raise reset_init_done[ch]
    //
    // This runs after cmd_task so the 3rd NOP edge still behaves as NOP and
    // the first legal command is accepted on the following CK edge.
    // =========================================================================
    task automatic update_reset_init_progress;
        input integer ch;
        time cs_high_elapsed; //How long CS_n has remained HIGH --->tINIT4 checking
        integer nop_ck_elapsed; //How many clock edges passed after tINIT4
        begin
            if (reset_init_done[ch]) begin
		    //Did initialization already complete?
                // Nothing more to do once this channel is open for commands.
            end else if (tinit3_done[ch] && (csn_r[ch] === 1'b1)) begin //CS_n remained LOW long enough after RESET_n HIGH    && CS_n is currently HIGH
                cs_high_elapsed = $time - tm_csn_high[ch];//Current simulation time - time when CS became HIGH
//Suppose:

//tm_csn_high = 100ns
//$current_time = 140ns

//Then:

//cs_high_elapsed = 40ns

//Meaning:

//CS has remained HIGH for 40ns

                if (!tinit4_done[ch]) begin //Has tINIT4 already completed? IF NOT BEGIN 
                    if (cs_high_elapsed >= TINIT4_JEDEC_PS) begin //Did CS remain HIGH long enough?according to official JEDEC timing.
                        tinit4_done[ch] = 1'b1; //tINIT4 complete
                        tinit5_ck_start[ch] = ck_cnt[ch]; //clock count when tINIT4 completed
                        $display("[CH%0d] tINIT4 SATISFIED: CS_n stayed HIGH for %0t before command acceptance at %0t",
                                 ch, cs_high_elapsed, $time);
                        $display("[CH%0d] tINIT5 START: counting 3 NOP clock edges from ck_cnt=%0d at %0t",
                                 ch, tinit5_ck_start[ch], $time);

	//----------------------------------------------------------------------------------------------------
                    end else if (cs_high_elapsed >= TINIT4_MODEL_PS) begin  //-----> THIS IS FOR THE SIMULATION LIKE BECAUSE IT AN TAKE hundreds of microseconds i.e 4
                        tinit4_done[ch] = 1'b1;
                        tinit5_ck_start[ch] = ck_cnt[ch];
                        $display("[CH%0d] tINIT4 SIM-SAT: CS_n stayed HIGH for %0t; JEDEC target=%0t, model gate=%0t at %0t",
                                 ch, cs_high_elapsed, TINIT4_JEDEC_PS, TINIT4_MODEL_PS, $time);
                        $display("[CH%0d] tINIT5 START: counting 3 NOP clock edges from ck_cnt=%0d at %0t",
                                 ch, tinit5_ck_start[ch], $time);
                    end
                end
                else if (tinit5_ck_start[ch] >= 0) begin
                    nop_ck_elapsed = ck_cnt[ch] - tinit5_ck_start[ch];
                    if ((nop_ck_elapsed >= TINIT5_MIN_CK) &&
                        tinit1_done &&
                        tinit2_done[ch] &&
                        tinit3_done[ch]) begin
                        reset_init_done[ch] = 1'b1;
                        $display("[CH%0d] tINIT5 SATISFIED: %0d NOP clock edges observed after tINIT4 at %0t",
                                 ch, nop_ck_elapsed, $time);
                        $display("[CH%0d] RESET INIT DONE: tINIT5 complete, so MRW to MR0 and normal command decode are now legal at %0t",
                                 ch, $time);
                    end
                end
            end
        end
    endtask

    // =========================================================================
    // Shared RESET_n timing checks
    // =========================================================================
    always @(negedge rst_n_r) begin
        tm_reset_assert = $time;
    end

    always @(posedge rst_n_r) begin
        time reset_low_ps;
        time cs_low_before_reset_ps;
        integer ch;
        begin
            tm_reset_deassert = $time;
            reset_low_ps      = $time - tm_reset_assert;

            if (reset_low_ps >= TINIT1_JEDEC_PS) begin
                tinit1_done = 1'b1;
                $display("[DDR5] tINIT1 SATISFIED: RESET_n stayed LOW for %0t before going HIGH at %0t",
                         reset_low_ps, $time);
            end else if (reset_low_ps >= TINIT1_MODEL_PS) begin
                tinit1_done = 1'b1;
                $display("[DDR5] tINIT1 SIM-SAT: RESET_n stayed LOW for %0t; JEDEC target=%0t, model gate=%0t at %0t",
                         reset_low_ps, TINIT1_JEDEC_PS, TINIT1_MODEL_PS, $time);
            end else begin
                tinit1_done = 1'b0;
                $display("[DDR5] ERROR: tINIT1 violation. RESET_n LOW duration=%0t, required at least model gate=%0t (JEDEC=%0t) at %0t",
                         reset_low_ps, TINIT1_MODEL_PS, TINIT1_JEDEC_PS, $time);
            end

            for (ch = 0; ch < 2; ch = ch + 1) begin
                if (csn_r[ch] !== 1'b0) begin
                    tinit2_done[ch] = 1'b0;
                    $display("[CH%0d] ERROR: tINIT2 violation. CS_n must be LOW when RESET_n goes HIGH at %0t",
                             ch, $time);
                end else begin
                    cs_low_before_reset_ps = $time - tm_csn_low[ch];
                    if (cs_low_before_reset_ps >= TINIT2_JEDEC_PS) begin
                        tinit2_done[ch] = 1'b1;
                        $display("[CH%0d] tINIT2 SATISFIED: CS_n stayed LOW for %0t before RESET_n deassert at %0t",
                                 ch, cs_low_before_reset_ps, $time);
                    end else begin
                        tinit2_done[ch] = 1'b0;
                        $display("[CH%0d] ERROR: tINIT2 violation. CS_n LOW duration before RESET_n deassert=%0t, required=%0t at %0t",
                                 ch, cs_low_before_reset_ps, TINIT2_JEDEC_PS, $time);
                    end
                end
            end
        end
    end

    // =========================================================================
    // Per-channel CS_n edge tracking
    //
    // negedge CS_n : remember when the controller pulled chip-select LOW
    // posedge CS_n : check tINIT3 and start the tINIT4/tINIT5 post-high window
    // =========================================================================
    always @(negedge csn_r[0]) begin
        if (!reset_init_done[0]) begin
            tm_csn_low[0]      = $time;
            tinit4_done[0]     = 1'b0;
            tinit5_ck_start[0] = -1;
        end
    end

    always @(negedge csn_r[1]) begin
        if (!reset_init_done[1]) begin
            tm_csn_low[1]      = $time;
            tinit4_done[1]     = 1'b0;
            tinit5_ck_start[1] = -1;
        end
    end

    always @(posedge csn_r[0]) begin
        time cs_low_after_reset_ps;
        begin
            if (!reset_init_done[0]) begin
                tm_csn_high[0]     = $time;
                tinit4_done[0]     = 1'b0;
                tinit5_ck_start[0] = -1;

                if (tm_reset_deassert == 0) begin
                    tinit3_done[0] = 1'b0;
                    $display("[CH0] ERROR: tINIT3 violation. CS_n rose before RESET_n deassert completed at %0t", $time);
                end else begin
                    cs_low_after_reset_ps = $time - tm_reset_deassert;
                    if (cs_low_after_reset_ps >= TINIT3_JEDEC_PS) begin
                        tinit3_done[0] = 1'b1;
                        $display("[CH0] tINIT3 SATISFIED: CS_n stayed LOW for %0t after RESET_n deassert before going HIGH at %0t",
                                 cs_low_after_reset_ps, $time);
                    end else if (cs_low_after_reset_ps >= TINIT3_MODEL_PS) begin
                        tinit3_done[0] = 1'b1;
                        $display("[CH0] tINIT3 SIM-SAT: CS_n stayed LOW for %0t after RESET_n deassert; JEDEC target=%0t, model gate=%0t at %0t",
                                 cs_low_after_reset_ps, TINIT3_JEDEC_PS, TINIT3_MODEL_PS, $time);
                    end else begin
                        tinit3_done[0] = 1'b0;
                        $display("[CH0] ERROR: tINIT3 violation. CS_n LOW hold after RESET_n deassert=%0t, required at least model gate=%0t (JEDEC=%0t) at %0t",
                                 cs_low_after_reset_ps, TINIT3_MODEL_PS, TINIT3_JEDEC_PS, $time);
                    end
                end
            end
        end
    end

    always @(posedge csn_r[1]) begin
        time cs_low_after_reset_ps;
        begin
            if (!reset_init_done[1]) begin
                tm_csn_high[1]     = $time;
                tinit4_done[1]     = 1'b0;
                tinit5_ck_start[1] = -1;

                if (tm_reset_deassert == 0) begin
                    tinit3_done[1] = 1'b0;
                    $display("[CH1] ERROR: tINIT3 violation. CS_n rose before RESET_n deassert completed at %0t", $time);
                end else begin
                    cs_low_after_reset_ps = $time - tm_reset_deassert;
                    if (cs_low_after_reset_ps >= TINIT3_JEDEC_PS) begin
                        tinit3_done[1] = 1'b1;
                        $display("[CH1] tINIT3 SATISFIED: CS_n stayed LOW for %0t after RESET_n deassert before going HIGH at %0t",
                                 cs_low_after_reset_ps, $time);
                    end else if (cs_low_after_reset_ps >= TINIT3_MODEL_PS) begin
                        tinit3_done[1] = 1'b1;
                        $display("[CH1] tINIT3 SIM-SAT: CS_n stayed LOW for %0t after RESET_n deassert; JEDEC target=%0t, model gate=%0t at %0t",
                                 cs_low_after_reset_ps, TINIT3_JEDEC_PS, TINIT3_MODEL_PS, $time);
                    end else begin
                        tinit3_done[1] = 1'b0;
                        $display("[CH1] ERROR: tINIT3 violation. CS_n LOW hold after RESET_n deassert=%0t, required at least model gate=%0t (JEDEC=%0t) at %0t",
                                 cs_low_after_reset_ps, TINIT3_MODEL_PS, TINIT3_JEDEC_PS, $time);
                    end
                end
            end
        end
    end

    // =========================================================================
    // cmd_task
    //
    // High-level flow inside cmd_task:
    //   1. Require two consecutive CKE=HIGH samples before looking at CA.
    //   2. Treat CS_n=HIGH as DES/NOP and leave the decoder idle.
    //   3. Reject any real command until reset_init_done[ch] is HIGH.
    //   4. Once the reset gate is open, run the existing two-cycle decoder.
    //
    // This means the new reset feature only adds a legal-entry guard in front
    // of the old command logic. ACT/WR/RD/MRW behavior stays intact after the
    // channel finishes tINIT1/tINIT2/tINIT3/tINIT4/tINIT5.
    //
    // reset_init_done[ch] is per-channel, so Channel 0 and Channel 1 can open
    // for legal command decode at different times if CS_n timing is different.
    // =========================================================================
    task cmd_task;
        input integer  ch;
        input          p_cke;
        input          c_cke;
        input          c_csn;
        input [13:0]   c_ca;

        reg [TOTAL_BA_BITS-1:0] bank;
        reg [COL_BITS-1:0]      col;
        reg [ROW_BITS-1:0]      row;
        reg [5:0]               cl_code;
        reg [1:0]               bl_code;
        integer i;

        begin
        // DDR5 only recognizes CA traffic after CKE has been HIGH across
        // consecutive sampling points. This mirrors the existing model style.
        if (p_cke && c_cke) begin
            // CS_n=HIGH means deselect / NOP. During reset initialization this
            // is also the quiet window used for tINIT4 and tINIT5.
        //---------------------------------------------------   
	    if (c_csn) begin
                cmd_state[ch] = CMD_ST_IDLE; // idel sate 
                // CS_n=H → DES/NOP
            end else begin
        //----------------------------------------------------
            if (!reset_init_done[ch]) begin
                // JEDEC says no MRW, ACT, RD, or WR can enter the DRAM until
                // the reset sequence has fully completed for this channel.
                cmd_state[ch] = CMD_ST_NOP;
                report_reset_init_block(ch, c_ca);

//Any command during reset:
//ACT
//READ
//WRITE
//MRW
//→ ALL ignored
//This ensures JEDEC compliance.
//

 

       //---------------------------------------------------------------------------------
       //DDR commands are modeled as:

       //Cycle 1 → decode intent
       //Cycle 2 → execute

        //So variables like:

        //act_c1
        //wr_c1
         //rd_c1

         //represent cycle-1 latched commands
       //---------------------------------------------------------------------------------
       //                        C Y C L E - T W O 
        //---------------------------------------------------------------------------------------

            // FSM state: ACTIVATE (cycle 2)
           //   Cycle 1 → decode WRITE → act_c1[ch] = 1
           //   Cycle 2 → execute WRITE → this block runs

            end else if (act_c1[ch]) begin //ACT was decoded in previous cycle
                cmd_state[ch] = CMD_ST_ACTIVATE; //Updates internal FSM state: IDLE → ACTIVATE
                act_c1[ch] = 1'b0; //ACT command has been consumed (executed), so clear the pending flag.
                bank       = act_bank[ch]; //ACT targets a specific bank
                row        = {ROW_BITS{1'b0}};
                row[0]  = act_ca1[ch][2]; row[1]  = act_ca1[ch][3];
                row[2]  = act_ca1[ch][4]; row[3]  = act_ca1[ch][5];
                row[4]  = c_ca[0];  row[5]  = c_ca[1];  row[6]  = c_ca[2];
                row[7]  = c_ca[3];  row[8]  = c_ca[4];  row[9]  = c_ca[5];
                row[10] = c_ca[6];  row[11] = c_ca[7];  row[12] = c_ca[8];
                row[13] = c_ca[9];  row[14] = c_ca[10]; row[15] = c_ca[11];
                row[16] = c_ca[12];
                if (!init_done) //DDR initialization not complete.
                    $display("[CH%0d] WARNING: ACT before init; accepting for pipeline debug at %0t", ch, $time);
                if (init_done && bank_active[ch][bank])//If:

                        /// DDR is fully initialized
                          //AND bank is already open

                          //  Then:

                         // 👉 INVALID ACT
                    $display("[CH%0d] ERROR: ACT to already-open bank %0d at %0t", ch, bank, $time);
                else begin
                    bank_active[ch][bank] = 1'b1; //OPEN BANK
                    bank_row[ch][bank]    = row; //STORE ROW → BANK MAPPING
                    current_wr_bank[ch]   = bank; 
                    current_rd_bank[ch]   = bank;
		    //Default active bank for:writes reads
                    $display("[CH%0d] ACT bank=%0d row=0x%0h at %0t", ch, bank, row, $time);
                end
 
           //--------------------------------------------------------------------------------------
            // FSM state: WRITE (cycle 2)
	    // Cycle 1 → decode WRITE → wr_c1[ch] = 1
            //Cycle 2 → execute WRITE → this block runs


            end else if (wr_c1[ch]) begin // //A WRITE command was detected in cycle-1 and is now being executed in cycle-2.

                cmd_state[ch] = CMD_ST_WRITE;
                wr_c1[ch] = 1'b0;
	
		//--> MAIN THING -> WITHOUT THIS WRITE HAPPEN EVERY CLOCK AND WILL NTO LIMIT TO 2 CYCLE  BECAUSE SEE IN THE FIRST CYCEL THE WR_C1[CH] =1 SO IT IS SAYING " WRIE IS STILL PENDING " THEN IN THE CYCLE 2 THIS BECOMES 0 -> INDICATES “this WRITE command has already been consumed (executed), so don’t execute it again 
             
	     
		bank      = wr_bank[ch];
                col = {c_ca[8], c_ca[7], c_ca[6], c_ca[5], c_ca[4],
                       c_ca[3], c_ca[2], c_ca[1], 3'b000};
                if (!init_done)
                    $display("[CH%0d] WARNING: WR before init; accepting for pipeline debug at %0t", ch, $time);
                if (!bank_active[ch][bank])
                    $display("[CH%0d] ERROR: WR to inactive bank=%0d at %0t", ch, bank, $time);
                else if (bank_ap[ch][bank])
                    $display("[CH%0d] ERROR: WR to AP-pending bank=%0d at %0t", ch, bank, $time);
                else begin
                    if (c_ca[10] == 1'b0) begin// auto prechage
                        bank_ap[ch][bank]    = 1'b1;
                        bank_wr_ap[ch][bank] = 1'b1;
                    end//After WRITE completes → bank automatically closes

		  //  WRITE is scheduled into future cycles
		  //  This block pushes the WRITE command into a delayed pipeline queue (wr_pipe) along with its bank, row, column, and burst length so that the actual memory write occurs after the configured write latency (write_latency) cycles.
                    wr_pipe[ch][2*write_latency+1]  = 1'b1;
                    ba_pipe [ch][2*write_latency+1] = bank;
                    row_pipe[ch][2*write_latency+1] = bank_row[ch][bank];
                    col_pipe[ch][2*write_latency+1] = col;
                    bl_pipe [ch][2*write_latency+1] = BL_MAX;
                    $display("[CH%0d] WR Cy2 bank=%0d row=0x%0h col=0x%0h AP=%0b at %0t",
                             ch, bank, bank_row[ch][bank], col, (c_ca[10]==1'b0), $time);
                end
            //-----------------------------------------------------------------------------------------------------
            // FSM state: READ (cycle 2)
            end else if (rd_c1[ch]) begin
                cmd_state[ch] = CMD_ST_READ;
                rd_c1[ch] = 1'b0;
                bank      = rd_bank[ch];
                col = {c_ca[8], c_ca[7], c_ca[6], c_ca[5], c_ca[4],
                       c_ca[3], c_ca[2], c_ca[1], 3'b000};
                if (!init_done)
                    $display("[CH%0d] WARNING: RD before init; accepting for pipeline debug at %0t", ch, $time);
                if (!bank_active[ch][bank])
                    $display("[CH%0d] ERROR: RD to inactive bank=%0d at %0t", ch, bank, $time);
                else if (bank_ap[ch][bank])
                    $display("[CH%0d] ERROR: RD to AP-pending bank=%0d at %0t", ch, bank, $time);
                else begin
                    if (c_ca[10] == 1'b0) begin
                        bank_ap[ch][bank]    = 1'b1;
                        bank_rd_ap[ch][bank] = 1'b1;
                    end
                    rd_pipe[ch][2*read_latency]  = 1'b1;
                    ba_pipe [ch][2*read_latency] = bank;
                    row_pipe[ch][2*read_latency] = bank_row[ch][bank];
                    col_pipe[ch][2*read_latency] = col;
                    bl_pipe [ch][2*read_latency] = BL_MAX;
                    $display("[CH%0d] RD Cy2 bank=%0d row=0x%0h col=0x%0h AP=%0b at %0t",
                             ch, bank, bank_row[ch][bank], col, (c_ca[10]==1'b0), $time);
                end
            //--------------------------------------------------------------------------------------------
            // FSM state: MRW (cycle 2)
	    // This block is your Mode Register Write (MRW) execution stage in cycle-2
            //It programs:

            //CAS latency (CL)
            //Burst length (BL)
            //internal timing model (read/write latency)
	    //--------------------------------------------------------------------------------------------

            end else if (mrw_c1[ch]) begin //MRW was decoded in cycle-1
                cmd_state[ch]           = CMD_ST_MRW;
                mrw_c1[ch]            = 1'b0;
                mr[mrw_addr[ch]]      = c_ca[7:0];
                $display("[CH%0d] MRW MR%0d <= 0x%02h at %0t",
                         ch, mrw_addr[ch], c_ca[7:0], $time);
	
            // mr0
                if (mrw_addr[ch] == 8'd0) begin   
                    cl_code = c_ca[7:2];
                    if (cl_code <= 6'b100011)
                        cas_latency = 22 + (cl_code * 2);
                    bl_code = c_ca[1:0];
                    case (bl_code)
                        2'b00: burst_length = 16;
                        2'b01: burst_length = 8;
                        2'b10: burst_length = 32;
                        2'b11: burst_length = 32;
                        default: burst_length = 16;
                    endcase
                    set_latency;
                    $display("[CH%0d] MR0: CL=%0d CWL=%0d BL=%0d at %0t",
                             ch, cas_latency, cas_write_latency, burst_length, $time);
                end
                // Only MR0 changes latency in this simplified model.
                // Other MRW addresses are still stored so the original init
                // flow keeps working, but they are not decoded further here.




		
                // Only count init_step on ch0 to avoid double-counting
                if (ch == 0) begin
                    if (!init_done)
                        init_step = init_step + 1;
                    if (!init_done && (mrw_addr[ch] == 8'd6)) begin
                        init_done = 1'b1;
                        $display("[DUAL-CH] INIT DONE at %0t  CL=%0d CWL=%0d RL=%0d WL=%0d BL=%0d",
                                 $time, cas_latency, cas_write_latency,
                                 read_latency, write_latency, burst_length);
                    end
                end
 


         //---------------------------------------------------------------------------------------
	 //        C Y C LE O N E 
        //---------------------------------------------------------------------------------------
            // FSM state: IDLE / first-cycle command decode
	    // // [MRW COMMAND] Cycle-1 decode → setup mode register write transaction
            end else if (c_ca[4:0] == 5'b00100) begin
                cmd_state[ch] = CMD_ST_MRW;
                mrw_c1[ch]   = 1'b1;
                mrw_addr[ch] = c_ca[12:5];
                $display("[CH%0d] MRW Cy1 MR=%0d at %0t", ch, mrw_addr[ch], $time);
       // ------------------------------------------------------------------------------------------
        // [ACT COMMAND] Cycle-1 decode → open row in selected bank    
              end else if (c_ca[1:0] == 2'b00 && c_ca[4:2] != 3'b001) begin
                cmd_state[ch] = CMD_ST_ACTIVATE;
                act_c1[ch]   = 1'b1;
                act_ca1[ch]  = c_ca;
                act_bank[ch] = {c_ca[9], c_ca[8], c_ca[7], c_ca[6]};
                $display("[CH%0d] ACT Cy1 bank=%0d CA=0x%04h at %0t",
                         ch, act_bank[ch], c_ca, $time);
        //---------------------------------------------------------------------------------------
       // [WRITE/READ COMMAND] Cycle-1 decode → column access operation (pipeline stage-1)
       // SPLIT INTO :--
       
       // // WRITE selected → schedule data write after latency
            end else if (c_ca[3:0] == 4'b1101) begin
                bank = {c_ca[9], c_ca[8], c_ca[7], c_ca[6]};
                if (c_ca[4] == 1'b0) begin
                    cmd_state[ch]  = CMD_ST_WRITE;
                    wr_c1[ch]       = 1'b1;
                    wr_bank[ch]     = bank;
                    wr_bl_star[ch]  = c_ca[5];
                    $display("[CH%0d] WR Cy1 bank=%0d at %0t", ch, bank, $time);

        //---------------------------------------------------------------------------------------
             // READ selected → schedule read burst after latency
                end else begin
                    cmd_state[ch]  = CMD_ST_READ;
                    rd_c1[ch]       = 1'b1;
                    rd_bank[ch]     = bank;
                    rd_bl_star[ch]  = c_ca[5];
                    $display("[CH%0d] RD Cy1 bank=%0d at %0t", ch, bank, $time);
                end
         //---------------------------------------------------------------------------------------
          // [PRECHARGE BANK] Close selected bank (restore idle state)
            end else if (c_ca[5:0] == 6'b101111) begin
                cmd_state[ch] = CMD_ST_PRECHARGE;
                bank = {c_ca[9], c_ca[8], c_ca[7], c_ca[6]};
                bank_active[ch][bank] = 1'b0;
                bank_ap[ch][bank]     = 1'b0;
                $display("[CH%0d] PREpb bank=%0d at %0t", ch, bank, $time);
         //---------------------------------------------------------------------------------------
          // [PRECHARGE ALL] Close all banks → global reset of row state
            end else if (c_ca[5:0] == 6'b001111 && c_ca[10] == 1'b0) begin
                cmd_state[ch] = CMD_ST_PRECHARGE;
                for (i = 0; i < `NUM_BANKS; i = i + 1) begin
                    bank_active[ch][i] = 1'b0;
                    bank_ap[ch][i]     = 1'b0;
                end
                $display("[CH%0d] PREab at %0t", ch, $time);
              //---------------------------------------------------------------------------------------
              // [PRECHARGE SELECTED BANK] Close only target bank group
            end else if (c_ca[5:0] == 6'b001111 && c_ca[10] == 1'b1) begin
                cmd_state[ch] = CMD_ST_PRECHARGE;
                begin : presb_blk
                    reg [1:0] ba_sel;
                    ba_sel = {c_ca[8], c_ca[7]};
                    for (i = 0; i < `NUM_BANKS; i = i + 1)
                        if (i[1:0] == ba_sel) begin
                            bank_active[ch][i] = 1'b0;
                            bank_ap[ch][i]     = 1'b0;
                        end
                end
                $display("[CH%0d] PRESb at %0t", ch, $time);
         //---------------------------------------------------------------------------------------
         // [REFRESH] Memory refresh cycle (restore DRAM charge)   
            end else if (c_ca[4:0] == 5'b10011 && c_ca[10] == 1'b0) begin
                cmd_state[ch] = CMD_ST_REFRESH;
                $display("[CH%0d] REFab at %0t", ch, $time);
          //---------------------------------------------------------------------------------------
         // [SELF-REFRESH ENTRY] Enter low-power refresh mode
            end else if (c_ca[4:0] == 5'b10111 && c_ca[9] == 1'b1 && c_ca[10] == 1'b0) begin
                cmd_state[ch] = CMD_ST_POWER;
                $display("[CH%0d] SRE at %0t", ch, $time);
           //---------------------------------------------------------------------------------------
         // [POWER DOWN ENTRY] Reduce power consumption, stop normal ops
            end else if (c_ca[4:0] == 5'b10111 && c_ca[10] == 1'b1) begin
                cmd_state[ch] = CMD_ST_POWER;
                $display("[CH%0d] PDE at %0t", ch, $time);
           //---------------------------------------------------------------------------------------
          // [NOP] No operation → used during idle or JEDEC init timing windows
            end else if (c_ca[4:0] == 5'b11111) begin
                cmd_state[ch] = CMD_ST_NOP;
                $display("[CH%0d] NOP at %0t", ch, $time);
              //---------------------------------------------------------------------------------------

            end else begin
                cmd_state[ch] = CMD_ST_UNKNOWN;
                $display("[CH%0d] Unknown command CA=0x%04h at %0t", ch, c_ca, $time);
            end

            end  // cs_n=L
        end  // CKE gate

        prev_cke[ch] <= c_cke;
        end
    endtask

    // =========================================================================
    // data_task — per channel (ch=0 or ch=1)
    // =========================================================================
    task data_task;
        input integer ch;
        integer i;
        reg [TOTAL_BA_BITS-3:0]               bank;
        reg [TOTAL_BA_BITS-1:TOTAL_BA_BITS-2] bank_group;
        reg [ROW_BITS-1:0]      row;
        reg [COL_BITS-1:0]      col;
        integer                 odly;
        reg                     use_fall_edge;
        reg [`DQ_PER_CH-1:0]    edge_acc;
        begin

            // Pipeline tip: latch address and pre-fetch memory
            if (wr_pipe[ch][0] || rd_pipe[ch][0]) begin
                $display("[CH%0d] pipeline[0] fired wr=%b rd=%b time=%t",
                         ch, wr_pipe[ch][0], rd_pipe[ch][0], $time);
                bank_group = ba_pipe[ch][0][TOTAL_BA_BITS-1:TOTAL_BA_BITS-2];
                bank       = ba_pipe[ch][0][TOTAL_BA_BITS-3:0];
                row        = row_pipe[ch][0];
                col        = col_pipe[ch][0];
                burst_cnt[ch]      = 0;
                dq_pos_acc[ch]     = 0;
                dq_neg_acc[ch]     = 0;
                if (rd_pipe[ch][0]) begin
                    mem_rd_task(ch, bank, bank_group, row, col, rd_burst_data[ch]);
                    if (ch == 0) begin
                        rd_valid0 = ~rd_valid0;
                        rd_data0  = rd_burst_data[ch];
                    end else begin
                        rd_valid1 = ~rd_valid1;
                        rd_data1  = rd_burst_data[ch];
                    end
		    $display("-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------");
                    $display("[CH%0d] MEMORY READ bg=%h ba=%h row=%h col=%h data=%h time=%t",
                             ch, bank_group, bank, row, col, rd_burst_data[ch], $time);
                end
            end

            // ---------------------------------------------------------------
            // Write data capture
            // Each active channel now captures on both DQS edges.
            // For the single-channel write flow, the controller drives the
            // first 8 edge slots with real 32-bit words and zero-pads edges
            // 8..15 to complete the mandatory BL16 burst.
            // ---------------------------------------------------------------
            if (wr_burst_active[ch] &&
                (dq_pos_seen[ch] || dq_neg_seen[ch])) begin
                if (wr_start_skip_cnt[ch] > 0) begin
                    wr_start_skip_cnt[ch] = wr_start_skip_cnt[ch] - 1;
                    dq_pos_seen[ch] = 1'b0;
                    dq_neg_seen[ch] = 1'b0;
                end else begin
                    use_fall_edge = dq_neg_seen[ch];
                    edge_acc      = use_fall_edge ? dq_neg_acc[ch] : dq_pos_acc[ch];
                    burst_pos[ch] = burst_cnt[ch][BL_BITS-1:0];
                    burst_mask[ch] = 0;

                    for (i = 0; i < `DM_PER_CH; i = i + 1) begin
                        if (use_fall_edge)
                            burst_mask[ch] = burst_mask[ch] |
                                ({`DQ_PER_DQS{~dm_neg[ch][i]}} <<
                                 (burst_pos[ch] * `DQ_PER_CH + i * `DQ_PER_DQS));
                        else
                            burst_mask[ch] = burst_mask[ch] |
                                ({`DQ_PER_DQS{~dm_pos[ch][i]}} <<
                                 (burst_pos[ch] * `DQ_PER_CH + i * `DQ_PER_DQS));
                    end

                    burst_data[ch] =
                        ((edge_acc <<
                          (burst_pos[ch] * `DQ_PER_CH)) & burst_mask[ch]) |
                        (burst_data[ch] & ~burst_mask[ch]);
                    burst_bus64[ch][burst_pos[ch] * DQ_BITS +: DQ_BITS] = dram_if.dq;
                    $display("[CH%0d | %s] DQS capture mask=%h data=%h pos=%h time=%t",
                             ch,
                             use_fall_edge ? "FALLING EDGE" : "RISING EDGE ",
                             burst_mask[ch], burst_data[ch], burst_pos[ch], $time);
                    dq_pos_seen[ch] = 1'b0;
                    dq_neg_seen[ch] = 1'b0;
                    dq_pos_acc[ch]  = '0;
                    dq_neg_acc[ch]  = '0;

                    dq_temp[ch] = burst_data[ch] >> (burst_pos[ch] * `DQ_PER_CH);
                    $display("[CH%0d | EDGE-%0d] WRITE BEAT bg=%h ba=%h row=%h col_beat=%h  dq64=%h selected_dq32=%h  time=%t",
                             ch,
                             burst_pos[ch],
                             bank_group, bank, row,
                             ({`MAX_BITS{1'b1}} << BL_BITS & col) + burst_pos[ch],
                             dram_if.dq, dq_temp[ch], $time);

                    if (burst_cnt[ch] == BL_MIN-1) begin
                        mem_wr_task(ch, bank, bank_group, row, col, burst_data[ch]);
                        $display("[CH%0d] FULL BURST COMMITTED bg=%h ba=%h row=%h col=%h  CHANNEL_DATA_512=%h  BUS64_BL16_1024=%h  time=%t",
                                 ch,
                                 bank_group, bank, row, col, burst_data[ch], burst_bus64[ch], $time);
                        wr_burst_active[ch] = 1'b0;
                        dq_valid[ch]        = 1'b0;
                        burst_cnt[ch]       = 0;
                        burst_bus64[ch]     = '0;
                    end else begin
                        burst_cnt[ch] = burst_cnt[ch] + 1;
                    end
                end
            end

            // Write burst activation
            if (wr_pipe[ch][0]) begin
                dq_pos_acc[ch]          = '0;
                dq_neg_acc[ch]          = '0;
                dq_pos_seen[ch]         = 1'b0;
                dq_neg_seen[ch]         = 1'b0;
                dq_first_hint_valid[ch] = 1'b0;
                burst_cnt[ch]           = 0;
                burst_data[ch]          = '0;
                burst_bus64[ch]         = '0;
                wr_burst_active[ch]     = 1'b1;
                wr_start_skip_cnt[ch]   = 0;
                dq_valid[ch]            = 1'b1;
            end

            if (!wr_burst_active[ch]) begin
                dq_valid[ch]   = 1'b0;
                dqs_valid[ch] <= 1'b0;
                for (i = 0; i < 31; i = i + 1)
                    wdqs_pos_cnt[ch][i] <= 0;
            end

            // Read DQS OE
            if (rd_pipe[ch][RDQSEN_PRE]) begin
                rdqsen_cnt[ch] = RDQSEN_PRE + bl_pipe[ch][RDQSEN_PRE] + RDQSEN_PST - 1;
                dq_pos_acc[ch]  = '0;
                dq_neg_acc[ch]  = '0;
                dq_pos_seen[ch] = 1'b0;
                dq_neg_seen[ch] = 1'b0;
            end
            if (rdqsen_cnt[ch] > 0) begin
                rdqsen_cnt[ch] = rdqsen_cnt[ch] - 1;
                dqs_oe[ch] = 1'b1;
            end else
                dqs_oe[ch] = 1'b0;

            // Read DQS toggle
            if (rd_pipe[ch][RDQS_PRE])
                rdqs_cnt[ch] = RDQS_PRE + bl_pipe[ch][RDQS_PRE] + RDQS_PST - 1;
            if (((rd_pipe[ch] >> 1) & {RDQS_PRE{1'b1}}) > 0 && rdq_cnt[ch] == 0)
                dqs_out[ch] = 1'b0;
            else if (rdqs_cnt[ch] > RDQS_PST)
                dqs_out[ch] = ~dqs_out[ch];
            else if (rdqs_cnt[ch] > 0)
                dqs_out[ch] = 1'b0;
            else
                dqs_out[ch] = 1'b1;
            if (rdqs_cnt[ch] > 0) rdqs_cnt[ch] = rdqs_cnt[ch] - 1;

            // Read DQ OE
            if (rd_pipe[ch][RDQEN_PRE])
                rdqen_cnt[ch] = RDQEN_PRE + bl_pipe[ch][RDQEN_PRE] + RDQEN_PST;
            if (rdqen_cnt[ch] > 0) begin
                rdqen_cnt[ch] = rdqen_cnt[ch] - 1;
                dq_oe[ch] = 1'b1;
            end else
                dq_oe[ch] = 1'b0;

            // Read DQ data output
            if (rd_pipe[ch][0]) begin
                rdq_cnt[ch]      = bl_pipe[ch][0];
                rd_burst_cnt[ch] = 0;
                rd_burst_pos[ch] = 0;
                dq_out[ch]       = {`DQ_PER_CH{1'b1}};
            end

            if (rdq_cnt[ch] > 0) begin
                rd_burst_pos[ch] = rd_burst_cnt[ch][BL_BITS-1:0];
                dq_temp[ch]      = rd_burst_data[ch] >> (rd_burst_pos[ch] * `DQ_PER_CH);
                dq_out[ch]       = dq_temp[ch];
                $display("[CH%0d] READ OUTPUT data=%h dq_out=%h burst_pos=%h time=%t",
                         ch, rd_burst_data[ch], dq_out[ch], rd_burst_pos[ch], $time);
                rd_burst_cnt[ch] = rd_burst_cnt[ch] + 1;
                rdq_cnt[ch]      = rdq_cnt[ch] - 1;
            end else
                dq_out[ch] = {`DQ_PER_CH{1'b1}};

            odly          = ($rtoi(tck_avg[ch]/2) > 50000) ? 0 : $rtoi(tck_avg[ch]/2);
            dqs_oe_d [ch] <= #(odly)   {`DQS_PER_CH{dqs_oe [ch]}};
            dqs_out_d[ch] <= #(odly)   {`DQS_PER_CH{dqs_out[ch]}};
            dq_oe_d  [ch] <= #(odly/2) {`DQ_PER_CH {dq_oe  [ch]}};
            dq_out_d [ch] <= #(odly/2) {`DQ_PER_CH {dq_out [ch]}};
        end
    endtask

    // =========================================================================
    // Memory clear on reset de-assertion
    // =========================================================================
    always @(posedge rst_n_r)
        if (rst_n_r) begin
            mem_used <= 0;
        end

    // =========================================================================
    // Main always block — Channel 0
    // =========================================================================
    always @(negedge rst_n_r or posedge diff_ck[0] or negedge diff_ck[0]) begin : main_ch0
        integer i;
        if (!rst_n_r) begin
            reset_task;
        end else begin
            data_task(0);
            if (diff_ck[0]) begin
                if (tm_ck_pos[0] !== 0) tck_avg[0] = $time - tm_ck_pos[0];
                tm_ck_pos[0] = $time;
                cmd_task(0, prev_cke[0], cke_r[0], csn_r[0], ca_r[0]);
                update_reset_init_progress(0);

                for (i = 0; i < `NUM_BANKS; i = i + 1) begin
                    if (bank_wr_ap[0][i] && !wr_pipe[0]) begin
                        bank_active[0][i] = 1'b0;
                        bank_ap[0][i]     = 1'b0;
                        bank_wr_ap[0][i]  = 1'b0;
                        $display("[CH0] Auto-PRE (write) bank=%0d at %0t", i, $time);
                    end
                    if (bank_rd_ap[0][i] && !rd_pipe[0]) begin
                        bank_active[0][i] = 1'b0;
                        bank_ap[0][i]     = 1'b0;
                        bank_rd_ap[0][i]  = 1'b0;
                        $display("[CH0] Auto-PRE (read) bank=%0d at %0t", i, $time);
                    end
                end
                out_en[0] = init_done;
                ck_cnt[0] = ck_cnt[0] + 1;
            end

            if (|wr_pipe[0] || |rd_pipe[0]) begin
                wr_pipe[0] = wr_pipe[0] >> 1;
                rd_pipe[0] = rd_pipe[0] >> 1;
                for (i = 0; i < `MAX_PIPE; i = i + 1) begin
                    bl_pipe [0][i] = bl_pipe [0][i+1];
                    ba_pipe [0][i] = ba_pipe [0][i+1];
                    row_pipe[0][i] = row_pipe[0][i+1];
                    col_pipe[0][i] = col_pipe[0][i+1];
                end
            end
        end
    end

    // =========================================================================
    // Main always block — Channel 1
    // =========================================================================
    always @(negedge rst_n_r or posedge diff_ck[1] or negedge diff_ck[1]) begin : main_ch1
        integer i;
        if (!rst_n_r) begin
            // reset already done by ch0 block — just guard
        end else begin
            data_task(1);
            if (diff_ck[1]) begin
                if (tm_ck_pos[1] !== 0) tck_avg[1] = $time - tm_ck_pos[1];
                tm_ck_pos[1] = $time;
                cmd_task(1, prev_cke[1], cke_r[1], csn_r[1], ca_r[1]);
                update_reset_init_progress(1);

                for (i = 0; i < `NUM_BANKS; i = i + 1) begin
                    if (bank_wr_ap[1][i] && !wr_pipe[1]) begin
                        bank_active[1][i] = 1'b0;
                        bank_ap[1][i]     = 1'b0;
                        bank_wr_ap[1][i]  = 1'b0;
                        $display("[CH1] Auto-PRE (write) bank=%0d at %0t", i, $time);
                    end
                    if (bank_rd_ap[1][i] && !rd_pipe[1]) begin
                        bank_active[1][i] = 1'b0;
                        bank_ap[1][i]     = 1'b0;
                        bank_rd_ap[1][i]  = 1'b0;
                        $display("[CH1] Auto-PRE (read) bank=%0d at %0t", i, $time);
                    end
                end
                out_en[1] = init_done;
                ck_cnt[1] = ck_cnt[1] + 1;
            end

            if (|wr_pipe[1] || |rd_pipe[1]) begin
                wr_pipe[1] = wr_pipe[1] >> 1;
                rd_pipe[1] = rd_pipe[1] >> 1;
                for (i = 0; i < `MAX_PIPE; i = i + 1) begin
                    bl_pipe [1][i] = bl_pipe [1][i+1];
                    ba_pipe [1][i] = ba_pipe [1][i+1];
                    row_pipe[1][i] = row_pipe[1][i+1];
                    col_pipe[1][i] = col_pipe[1][i+1];
                end
            end
        end
    end

    // =========================================================================
    // DQS receivers
    //   Correct capture summary:
    //   Each channel captures one 32-bit sample on both DQS edges.
    //   For single-channel writes, the selected channel sees 16 BL16 edge
    //   slots, with real data on edges 0..7 and padding on edges 8..15.
    //   Each channel now captures on BOTH DQS edges:
    //     posedge DQS_T -> rising edge sample
    //     posedge DQS_C -> falling edge sample
    //   This lets a single active channel consume all 16 BL16 edge slots.
    // =========================================================================

    task dqs_recv_rise;
        input integer ch;
        input [2:0] ii;
        reg [127:0] msk;
        reg [`DQ_PER_CH-1:0] raw_dq;
        reg [`DM_PER_CH-1:0] raw_dm;
        begin
            msk = {`DQ_PER_DQS{1'b1}} << (ii * `DQ_PER_DQS);
            if (ch == 0) begin
                raw_dq = dram_if.dq[`DQ_PER_CH-1:0];
                raw_dm = dram_if.dmi[`DM_PER_CH-1:0];
            end else begin
                raw_dq = dram_if.dq[DQ_BITS-1:`DQ_PER_CH];
                raw_dm = dram_if.dmi[DM_BITS-1:`DM_PER_CH];
            end
            dm_pos[ch][ii]  = raw_dm[ii];
            if ($isunknown(raw_dq)) begin
                dq_pos_acc[ch] = '0;
                dq_pos_acc[ch][`DQ_PER_CH-1:0] = {`DQ_PER_CH{1'bx}};
            end else begin
                dq_pos_acc[ch]  = (dq_pos_acc[ch] & ~msk) |
                                  (raw_dq & msk);
            end
            dq_pos_seen[ch] = 1'b1;
            $display("[CH%0d] DQS rise lane=%0d dq64=%h selected_dq32=%h mask=%h dq_pos=%h time=%t",
                     ch, ii, dram_if.dq, raw_dq, msk, dq_pos_acc[ch], $time);
        end
    endtask

    task dqs_recv_fall;
        input integer ch;
        input [2:0] ii;
        reg [127:0] msk;
        reg [`DQ_PER_CH-1:0] raw_dq;
        reg [`DM_PER_CH-1:0] raw_dm;
        begin
            msk = {`DQ_PER_DQS{1'b1}} << (ii * `DQ_PER_DQS);
            if (ch == 0) begin
                raw_dq = dram_if.dq[`DQ_PER_CH-1:0];
                raw_dm = dram_if.dmi[`DM_PER_CH-1:0];
            end else begin
                raw_dq = dram_if.dq[DQ_BITS-1:`DQ_PER_CH];
                raw_dm = dram_if.dmi[DM_BITS-1:`DM_PER_CH];
            end
            dm_neg[ch][ii]  = raw_dm[ii];
            if ($isunknown(raw_dq)) begin
                dq_neg_acc[ch] = '0;
                dq_neg_acc[ch][`DQ_PER_CH-1:0] = {`DQ_PER_CH{1'bx}};
            end else begin
                dq_neg_acc[ch]  = (dq_neg_acc[ch] & ~msk) |
                                  (raw_dq & msk);
            end
            dq_neg_seen[ch] = 1'b1;
            $display("[CH%0d] DQS fall lane=%0d dq64=%h selected_dq32=%h mask=%h dq_neg=%h time=%t",
                     ch, ii, dram_if.dq, raw_dq, msk, dq_neg_acc[ch], $time);
        end
    endtask

    // ── Channel 0: capture both DQS phases ──────────────────────────────────
    always @(posedge dqs_even[0][0]) dqs_recv_rise(0, 0);
    always @(posedge dqs_even[0][1]) dqs_recv_rise(0, 1);
    always @(posedge dqs_even[0][2]) dqs_recv_rise(0, 2);
    always @(posedge dqs_even[0][3]) dqs_recv_rise(0, 3);
    always @(posedge dqs_odd [0][0]) dqs_recv_fall(0, 0);
    always @(posedge dqs_odd [0][1]) dqs_recv_fall(0, 1);
    always @(posedge dqs_odd [0][2]) dqs_recv_fall(0, 2);
    always @(posedge dqs_odd [0][3]) dqs_recv_fall(0, 3);

    // ── Channel 1: capture both DQS phases ──────────────────────────────────
    always @(posedge dqs_even[1][0]) dqs_recv_rise(1, 0);
    always @(posedge dqs_even[1][1]) dqs_recv_rise(1, 1);
    always @(posedge dqs_even[1][2]) dqs_recv_rise(1, 2);
    always @(posedge dqs_even[1][3]) dqs_recv_rise(1, 3);
    always @(posedge dqs_odd [1][0]) dqs_recv_fall(1, 0);
    always @(posedge dqs_odd [1][1]) dqs_recv_fall(1, 1);
    always @(posedge dqs_odd [1][2]) dqs_recv_fall(1, 2);
    always @(posedge dqs_odd [1][3]) dqs_recv_fall(1, 3);

endmodule
