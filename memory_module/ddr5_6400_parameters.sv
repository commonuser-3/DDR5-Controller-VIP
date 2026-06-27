// =============================================================================
// File Name  : ddr5_6400_parameters.sv
// Description: Timing and size parameters for DDR5-6400 (JEDEC JESD79-5B)
//              Speed bin: DDR5-6400AN (46-46-46), tCK = 312 ps
//              // =============================================================================

`define sg312   // DDR5-6400AN  46-46-46  speed bin

// -----------------------------------------------------------------------------
// Speed-bin: sg312  →  DDR5-6400  (tCK = 312 ps = 3200 MHz clock = 6400 MT/s)
// Source: JEDEC JESD79-5B Table 281 (DDR5-6400 Speed Bins and Operations)
// -----------------------------------------------------------------------------
`ifdef sg312
    parameter TCK_MIN          =     312; // tCK       ps   Minimum Clock Cycle Time (6400 MT/s)
    parameter TDS              =      25; // tDS       ps   DQ/DM input setup time relative to DQS
    parameter TDH              =      15; // tDH       ps   DQ/DM input hold  time relative to DQS
    parameter TDQSQ            =      50; // tDQSQ     ps   DQS-DQ skew per group per access
    parameter TDQSCK           =     175; // tDQSCK    ps   DQS output access time from CK
    parameter TIS              =      20; // tIS       ps   CA input setup time
    parameter TIH              =      30; // tIH       ps   CA input hold  time
    parameter TRAS_MIN         =   32000; // tRAS      ps   ACT to PRE minimum         (JEDEC Table 281: 32.000 ns)
    parameter TRC              =   46375; // tRC       ps   ACT to ACT/REF (same bank) (JEDEC Table 281: 46.375 ns)
    parameter TRCD             =   14375; // tRCD      ps   ACT to RD/WR               (JEDEC Table 281: 14.375 ns)
    parameter TRP              =   14375; // tRP       ps   Precharge command period    (JEDEC Table 281: 14.375 ns)
    parameter TAA_MIN          =   14375; // tAA       ps   READ cmd to first data      (JEDEC Table 281: CL=46 × 312ps = 14.375 ns)
    parameter CL_TIME          =   14375; // CL        ps   Minimum CAS Latency (same as TAA_MIN)
    parameter TCK_MAX          =   10000; // tCK       ps   Maximum Clock Cycle Time (slow init)
    parameter TWR              =   30000; // tWR       ps   Write recovery (DDR5 JEDEC ≥ 30 ns)
    parameter TRTP             =    7500; // tRTP      ps   READ to PRE delay
    parameter TRTP_TCK         =      12; // tRTP      tCK  (max of 7.5 ns / 12 tCK)
    // DDR5 same-BG / diff-BG timing
    parameter TWTR_L           =   10000; // tWTR_L    ps   WR→RD same bank-group
    parameter TWTR_S           =    2500; // tWTR_S    ps   WR→RD diff bank-group
    parameter TWTR_L_TCK       =      16; // tWTR_L    tCK
    parameter TWTR_S_TCK       =       4; // tWTR_S    tCK
    parameter TRRD_L           =    5000; // tRRD_L    ps   ACT→ACT same bank-group
    parameter TRRD_S           =    2500; // tRRD_S    ps   ACT→ACT diff bank-group
    parameter TRRD_L_TCK       =       8; // tRRD_L    tCK
    parameter TRRD_S_TCK       =       4; // tRRD_S    tCK
    parameter TCCD_L           =    5000; // tCCD_L    ps   CAS→CAS same bank-group
    parameter TCCD_S           =    2500; // tCCD_S    ps   CAS→CAS diff bank-group
    parameter TCCD_L_TCK       =       8; // tCCD_L    tCK
    parameter TCCD_S_TCK       =       4; // tCCD_S    tCK
    parameter TFAW             =   25000; // tFAW      ps   Four Activate Window (x8)
`endif

// -----------------------------------------------------------------------------
// Refresh (DDR5-6400 8Gb per JEDEC Table 166)
// -----------------------------------------------------------------------------
parameter TRFC1_MIN        =  295000; // tRFC1     ps   REFab cycle minimum
parameter TRFC2_MIN        =  160000; // tRFC2     ps   REFsb cycle minimum

// -----------------------------------------------------------------------------
// Mode Register latency parameters decoded by the controller  (MR0 / MR2)
// DDR5-6400AN supported CL: 22,24,26,28,30,32,34,36,38,40,42,46,48,50,52,54,56
// -----------------------------------------------------------------------------
parameter CL_MIN           =      46; // CL        tCK  Minimum  CAS Latency  (DDR5-6400AN)
parameter CL_MAX           =      56; // CL        tCK  Maximum  CAS Latency
parameter CWL_MIN          =      30; // CWL       tCK  Minimum  CAS Write Latency  (CL-2 per JEDEC)
parameter CWL_MAX          =      46; // CWL       tCK  Maximum  CAS Write Latency
parameter BL_MIN           =      16; // BL        tCK  Fixed BL16 (DDR5 mandatory)
parameter BL_MAX           =      16; // BL        tCK  Fixed BL16

// -----------------------------------------------------------------------------
// Clock shape
// -----------------------------------------------------------------------------
parameter TCH_AVG_MIN      =    0.47; // tCH       tCK  Clock high pulse width min
parameter TCL_AVG_MIN      =    0.47; // tCL       tCK  Clock low  pulse width min
parameter TCH_AVG_MAX      =    0.53;
parameter TCL_AVG_MAX      =    0.53;

// -----------------------------------------------------------------------------
// DQS preamble / postamble  (DDR5: 2-cycle write preamble)
// -----------------------------------------------------------------------------
parameter TWPRE            =    2.00; // tWPRE     tCK  Write DQS preamble (2 cycles)
parameter TWPST            =    0.50; // tWPST     tCK  Write DQS postamble
parameter TRPRE            =    1.80; // tRPRE     tCK  Read  DQS preamble
parameter TRPST            =    0.50; // tRPST     tCK  Read  DQS postamble
parameter TDQSH            =    0.45; // tDQSH     tCK  DQS input high pulse width
parameter TDQSL            =    0.45; // tDQSL     tCK  DQS input low  pulse width

// -----------------------------------------------------------------------------
// Size / Organisation   (x8, 8 Gb kept compatible with existing interface)
// -----------------------------------------------------------------------------
parameter DM_BITS          =       8; // DMI bits per DQS group
parameter ADDR_BITS        =      17; // CA bus width (17-bit row address for 8Gb DDR5)
parameter ROW_BITS         =      17; // Row address bits
parameter COL_BITS         =      10; // Column address bits
parameter DQ_BITS          =       64; // Data bus width per device (x32 organisation, no ECC)
parameter DQS_BITS         =        8; // DQS bits per device (one per 8 DQ bits)

// DDR5 bank-group structure: 4 BGs × 4 banks = 16 banks total
parameter BG_BITS          =       2; // Bank-group address bits (4 BGs)
parameter BA_BITS          =       2; // Bank address bits within group (4 banks/BG)
parameter TOTAL_BA_BITS    =       4; // BG_BITS + BA_BITS  (drives `BANKS macro = 16)

parameter MEM_BITS         =      10; // Memory array depth = 2^10 = 1024 entries
parameter AP               =      10; // Address bit controlling auto-precharge (A10)
parameter BC               =      12; // Address bit for burst-chop (not used — BL16 fixed)
parameter BL_BITS          =       4; // Bits needed to count to BL_MAX (16 → 4 bits)
parameter BO_BITS          =       2; // Burst order bits

// Chip-select
`ifdef DUAL_RANK
    parameter CS_BITS      =       2;
    parameter RANKS        =       2;
`else
    parameter CS_BITS      =       1;
    parameter RANKS        =       1;
`endif

// -----------------------------------------------------------------------------
// Simulation helpers  (preserved from DDR3 source)
// -----------------------------------------------------------------------------
parameter STOP_ON_ERROR    =       1;
parameter DEBUG            =       1;
parameter BUS_DELAY        =       0; // ps  PCB propagation delay
parameter RANDOM_OUT_DELAY =       0;
parameter RANDOM_SEED      =   31913;

// Read/write DQS driver timing (half-clock periods)
// DDR5 uses 2-cycle write preamble → WDQS_PRE = 4 half-clocks
parameter RDQSEN_PRE       =       2;
parameter RDQSEN_PST       =       1;
parameter RDQS_PRE         =       2;
parameter RDQS_PST         =       1;
parameter RDQEN_PRE        =       0;
parameter RDQEN_PST        =       0;
parameter WDQS_PRE         =       4; // 2-cycle DDR5 write preamble
parameter WDQS_PST         =       1;

// -----------------------------------------------------------------------------
// CL / CWL validity check  (DDR5-6400AN operating points — JEDEC Table 281)
// CWL = CL - 2 per JEDEC DDR5 spec
// -----------------------------------------------------------------------------
function valid_cl_ddr5;
    input [5:0] cl;
    input [5:0] cwl;
    case ({cwl, cl})
        {6'd44, 6'd46},
        {6'd46, 6'd48},
        {6'd48, 6'd50},
        {6'd50, 6'd52},
        {6'd52, 6'd54},
        {6'd54, 6'd56}: valid_cl_ddr5 = 1;
        default       : valid_cl_ddr5 = 0;
    endcase
endfunction
