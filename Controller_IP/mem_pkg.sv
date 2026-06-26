/***************************************************************************************************************************
*
*    File Name:  DUT_pkg.sv
*      Version:  2.2
*
*  CHANGES vs v1.0 (on-disk version):
*
*  Added parameters required by interface.sv v2.2 and DUT.sv v2.3:
*
*    RANK_DEVICES, RANK_DQ_BITS, RANK_DQS_BITS, RANK_DM_BITS
*      Rank-level widths (8 devices x8 = 64-bit DQ bus).
*      interface.sv uses these for mem_if port widths (dq, dqs, dqs_n, dm_tdqs).
*      DUT.sv uses these for wdata_local, dm_local, t_dq_local, dm_out_local.
*
*    BL8_DQ_BITS  = 512  (8 DQS edges x 64-bit DQ)
*    BL8_DM_BITS  =  64  (8 DQS edges x  8-bit DM)
*      Used by interface.sv for o_cpu_rd_data (512-bit read buffer) and
*      DUT.sv for s_data / cpu_rd_data declarations.
*
*    AXI_DATA_WIDTH = 64, AXI_STRB_WIDTH = 8
*      Used by controller_subsystem.sv and axi_slave.sv.
*
*    COLLECT added to States enum (between IDLE and ACT)
*      DUT.sv FSM uses COLLECT to accumulate multi-beat write data before
*      issuing ACT.  Without COLLECT in the enum, DUT.sv line 173 fails.
*
*    States state removed from package scope
*      Declaring 'state' in the package causes duplicate-declaration errors
*      when multiple modules import the package.  Each module declares its
*      own 'States state' locally.
*
*****************************************************************************************************************************/

package DDR3MemPkg;

//==================================================================================================================================================
// Per-device (single x8 chip) bit widths
//==================================================================================================================================================
    parameter DQ_BITS   = 8;    // DQ bits per device
    parameter DQS_BITS  = 1;    // DQS lanes per device
    parameter DM_BITS   = 1;    // DM bits per device
    parameter ADDR_BITS = 14;   // DDR3 address bus width
    parameter BA_BITS   = 3;    // Bank address bits

//==================================================================================================================================================
// Rank-level widths  (8 x8 devices in parallel = 64-bit data bus)
// These are the widths seen at the controller <-> memory interface.
//==================================================================================================================================================
    parameter RANK_DEVICES  = 8;
    parameter RANK_DQ_BITS  = RANK_DEVICES * DQ_BITS;   // = 64
    parameter RANK_DQS_BITS = RANK_DEVICES * DQS_BITS;  // = 8
    parameter RANK_DM_BITS  = RANK_DEVICES * DM_BITS;   // = 8

//==================================================================================================================================================
// BL8 full-burst widths
// A complete DDR3 BL8 transaction = 8 DQS edges x 64-bit DQ = 512 bits total.
//==================================================================================================================================================
    parameter BURST_L     = 8;
    parameter BL8_DQ_BITS = BURST_L * RANK_DQ_BITS;    // = 512  (write/read buffer)
    parameter BL8_DM_BITS = BURST_L * RANK_DM_BITS;    // =  64  (DM buffer)

//==================================================================================================================================================
// Address and burst parameters
//==================================================================================================================================================
    parameter ROW_BITS      = 14;
    parameter COL_BITS      = 10;
    parameter ADDR_MCTRL    = 32;   // address bus width to controller
    parameter BURST_LENGTH  = 8;    // DDR3 burst length

//==================================================================================================================================================
// AXI interface widths  (one DQS-edge worth of data per AXI beat)
//==================================================================================================================================================
    parameter AXI_DATA_WIDTH = RANK_DQ_BITS;    // = 64
    parameter AXI_STRB_WIDTH = RANK_DM_BITS;    // = 8

//==================================================================================================================================================
// Timing parameters  (6-6-6 configuration)
//==================================================================================================================================================
    parameter T_RAS = 15;   // Row active time (ACT to PRE)
    parameter T_RCD =  6;   // RAS to CAS delay
    parameter T_CL  =  6;   // CAS latency
    parameter T_RC  = 21;   // Row cycle time (ACT to ACT)
    parameter T_BL  =  4;   // Burst length in clock cycles (BL8 / 2)
    parameter T_RP  =  6;   // Precharge time
    parameter T_MRD =  4;   // Mode register set delay

//==================================================================================================================================================
// FSM States
// COLLECT added between IDLE and ACT:
//   IDLE    -> first AXI beat arrives; latch addr + beat0
//   COLLECT -> accumulate beats 1..N-1 of a multi-beat write
//   ACT     -> issue DDR3 ACTIVATE command
//==================================================================================================================================================
    typedef enum logic [4:0] {
        RESET,
        POWERUP,
        MRLOAD,
        ZQ_CAL,
        CAL_DONE,
        IDLE,
        COLLECT,
        ACT,
        READ,
        WRITE,
        WBURST,
        RBURST,
        PRECHARGE,  // Open-page row miss: single-bank PRE before ACT
        AUTORP,
        DONE
    } States;


// NOTE: 'States state' is NOT declared here.
// Each module that needs a state register declares its own:
//   States state;
// Declaring it in the package caused duplicate-declaration errors
// when multiple modules import the package.

endpackage : DDR3MemPkg
