`timescale 1ps/1ps

/***************************************************************************************************************************
*
*    File Name:  interface.sv
*      Version:  2.2  (multi-beat burst support + width fixes)
*
*  CHANGES vs v1.0:
*
*  [1] o_cpu_rd_data: 64-bit -> 512-bit (BL8_DQ_BITS)
*      Was [8*DQ_BITS-1:0] = 64 bits. DUT drives all 8 beats (512 bits).
*      Truncating to 64 bits made read return only beat 0.
*
*  [2] Write task: added burst_len + dm parameters; now sets i_cpu_burst/i_cpu_dm
*      Old: Write(addr, data) -> never set i_cpu_burst -> controller saw 0 ->
*           i_cpu_burst <= 1 was TRUE -> went to ACT per beat -> 4 BL8 transactions
*      New: Write(addr, data, burst_len, dm)
*           Beat 0 (IDLE)   : sets i_cpu_burst = total beats, presents beat 0 data
*           Beats 1..N-1    : call Write again; controller is in COLLECT (rdy=1)
*           Each call sends one beat. Testbench loops N times for N-beat burst.
*
*  [3] Read task: output widened to BL8_DQ_BITS (512 bits)
*      AXI slave extracts beat N as read_data[N*64 +: 64].
*
*  mem_if interface (CONTROLLER <-> DRAM):
*      dq, dqs, dqs_n width now match rank (64-bit DQ, 8-lane DQS)
*      - was [1-1:0] = 1 bit for dqs/dqs_n
*      - now [7:0] for dqs/dqs_n and [63:0] for dq
*
*****************************************************************************************************************************/
import ddr5_pkg::*;

//==================================================================================================================================================
// Interface 1: Controller <-> DDR3 Memory Rank
//==================================================================================================================================================
interface legacy_mem_if(input logic i_cpu_ck);

    logic   rst_n;
    logic   ck;
    logic   ck_n;
    logic   cke;
    logic   cs_n;
    logic   ras_n;
    logic   cas_n;
    logic   we_n;
    tri  [RANK_DM_BITS-1:0]  dm_tdqs;          // 8-bit DM (one per device)
    logic [BA_BITS-1:0]      ba;
    logic [ADDR_BITS-1:0]    addr;
    tri  [RANK_DQ_BITS-1:0]  dq;               // 64-bit DQ (8 devices x 8 bits)
    tri  [RANK_DQS_BITS-1:0] dqs;              // 8-lane DQS
    tri  [RANK_DQS_BITS-1:0] dqs_n;            // 8-lane DQS_N
    logic [RANK_DQS_BITS-1:0] tdqs_n;          // TDQS_N (output from memory)
    logic odt;

    // Controller drives commands/clock/data; memory drives TDQS_N
    modport contr_sig (
        output ck, ck_n, rst_n, cs_n, cke, ras_n, cas_n, we_n, odt, ba, addr, tdqs_n,
        inout  dm_tdqs, dq, dqs, dqs_n
    );

    // Memory receives commands; drives TDQS_N back
    modport mem_sig (
        input  ck, ck_n, rst_n, cs_n, cke, ras_n, cas_n, we_n, odt, ba, addr, tdqs_n,
        inout  dm_tdqs, dq, dqs, dqs_n
    );

endinterface : legacy_mem_if


//==================================================================================================================================================
// Interface 2: CPU/AXI Slave <-> DDR3 Controller
//==================================================================================================================================================
interface mem_intf(input logic i_cpu_ck);

    logic                       i_cpu_reset;    // active-high sync reset
    logic [ADDR_MCTRL-1:0]      i_cpu_addr;     // 32-bit address {BA,ROW,COL}
    logic                       i_cpu_cmd;      // 1=WRITE  0=READ
    logic [RANK_DQ_BITS-1:0]    i_cpu_wr_data;  // 64-bit write data (one beat)
    logic                       i_cpu_valid;    // request valid
    logic                       i_cpu_enable;   // chip select / enable
    logic [RANK_DM_BITS-1:0]    i_cpu_dm;       // 8-bit byte mask (one beat, 0=write)
    logic [$clog2(BURST_L):0]   i_cpu_burst;    // number of valid beats (1-8)

    // FIX [1]: 64-bit -> 512-bit.  DUT packs all 8 beats here.
    // AXI slave extracts beat N as o_cpu_rd_data[N*64 +: 64].
    logic [63:0]     o_cpu_rd_data;       // 512-bit read data (8 beats)
    logic                       o_cpu_data_rdy;      // controller ready for next beat
    logic                       o_cpu_rd_data_valid; // read data valid

    // Controller modport (inputs from AXI slave, outputs back to AXI slave)
    modport MemController (
        input  i_cpu_ck,
        input  i_cpu_reset,
        input  i_cpu_addr,
        input  i_cpu_cmd,
        input  i_cpu_wr_data,
        input  i_cpu_valid,
        input  i_cpu_enable,
        input  i_cpu_dm,
        input  i_cpu_burst,
        output o_cpu_rd_data,       // 512-bit
        output o_cpu_data_rdy,
        output o_cpu_rd_data_valid
    );

    // AXI slave modport (drives commands, receives read data)
    modport axi_MemController (
        output i_cpu_ck,
        output i_cpu_reset,
        output i_cpu_addr,
        output i_cpu_cmd,
        output i_cpu_wr_data,
        output i_cpu_valid,
        output i_cpu_enable,
        output i_cpu_dm,
        output i_cpu_burst,
        input  o_cpu_rd_data,       // 512-bit
        input  o_cpu_data_rdy,
        input  o_cpu_rd_data_valid
    );

int count;

//==================================================================================================================================================
// Task: Reset
// Pulses i_cpu_reset high for 1 clock cycle then releases.
//==================================================================================================================================================
task Reset();
    @(posedge i_cpu_ck);
    $display("[DRIVER] Reset Started");
    i_cpu_reset  = 1;
    i_cpu_valid  = 0;
    i_cpu_enable = 0;
    @(posedge i_cpu_ck);
    i_cpu_reset  = 0;
    i_cpu_enable = 1;
    $display("[DRIVER] Reset Ended");
endtask

//==================================================================================================================================================
// Task: Write
//
// Sends ONE beat of write data to the controller.
// Call this task N times for an N-beat AXI burst (awlen = N-1).
//
// Parameters:
//   address   : DDR3 address {BA,ROW,COL} - only used on beat 0 (IDLE state)
//   write_data: 64-bit data for this beat
//   burst_len : TOTAL beats in this AXI transaction (= awlen+1).  Must be the
//               same value on every call for the same transaction.
//               FIX [2]: was never set -> controller saw 0 -> i_cpu_burst<=1
//               was always TRUE -> went ACT per beat -> 4 BL8 transactions
//   dm        : 8-bit byte mask for this beat (0=write byte, 1=mask byte)
//               = ~AXI_wstrb. Default 8'h00 = write all bytes.
//
// Usage for awlen=3 (4 beats):
//   Write(addr, data0, 4, ~strb0);   // beat 0 - controller in IDLE  -> COLLECT
//   Write(addr, data1, 4, ~strb1);   // beat 1 - controller in COLLECT
//   Write(addr, data2, 4, ~strb2);   // beat 2 - controller in COLLECT
//   Write(addr, data3, 4, ~strb3);   // beat 3 - controller in COLLECT -> ACT
//
// Note: addr and burst_len are ignored by the controller on beats 1..N-1
//       (they are only latched in IDLE state). You can pass any value.
//==================================================================================================================================================
task Write(
    input logic [ADDR_MCTRL-1:0]   address,
    input logic [RANK_DQ_BITS-1:0] write_data,
    input logic [3:0]               burst_len = 4'd1,   // total beats (= awlen+1)
    input logic [RANK_DM_BITS-1:0]  dm        = '0      // byte mask (0=write)
);
    @(posedge i_cpu_ck);
    wait(o_cpu_data_rdy);       // wait for IDLE or COLLECT state (both assert rdy)
    @(posedge i_cpu_ck);
    i_cpu_valid    = 1'b1;
    i_cpu_cmd      = 1'b1;      // WRITE command
    i_cpu_addr     = address;
    $display("INTERFACE ADDR i_cpu_addr=%h",i_cpu_addr);
    i_cpu_wr_data  = write_data;
    i_cpu_burst    = burst_len; // FIX [2]: was never set
    i_cpu_dm       = dm;        // byte mask for this beat
    @(posedge i_cpu_ck);
    i_cpu_valid    = 1'b0;      // de-assert between beats; re-asserted on next call
endtask

//==================================================================================================================================================
// Task: Read
//
// Issues a CAS READ command then collects all BURST_L (8) streaming 64-bit beats
// from the controller and packs them into the 512-bit read_data output.
// AXI slave then extracts beat N as read_data[N*64 +: 64].
//
// The controller streams beats 0..BURST_L-1 one per clock on o_cpu_rd_data[63:0]
// with o_cpu_rd_data_valid = 1 for each beat (identical handshake to write direction).
//
// THREE bugs fixed vs the single-read version:
//
//  BUG A - Beat 0 NBA race:
//    wait(o_cpu_rd_data_valid) fires when the NBA for valid applies. At that exact
//    instant o_cpu_rd_data is ALSO being updated via NBA (same always_ff, same
//    time step). Depending on simulator NBA commit order, o_cpu_rd_data may still
//    hold its OLD value when we read it.  Fix: add #1 (1ps) after wait() to advance
//    past the NBA region before sampling — both valid and data are settled.
//
//  BUG B - Beats 1-7 never collected:
//    The original task read o_cpu_rd_data ONCE and returned. The controller then
//    streams beats 1-7 on the following clocks but nothing collected them.
//    read_data[511:64] stayed 0 → AXI R-channel sent 0 for beats 1-7.
//    Fix: loop BURST_L times, one @posedge per beat, sampling after #1 each time.
//
//  BUG C - Beat 7 valid guard fails:
//    The DUT deasserts o_cpu_rd_data_valid in the SAME NBA as it drives beat 7.
//    Any if(valid) guard in the loop sees valid=0 after #1 for b==7 → beat 7 missed.
//    Fix: remove the valid check entirely. o_cpu_rd_data is a registered signal and
//    holds beat 7's value even after valid deasserts (no other logic overwrites it).
//
// Sampling sequence:
//   wait(valid)           → level-sensitive, fires after NBA commits valid=1
//   #1                    → 1ps past NBA region; o_cpu_rd_data = beat 0
//   sample beat 0
//   for b=1..BURST_L-1:
//     @(posedge i_cpu_ck) → DUT has just registered beat b via NBA
//     #1                  → past NBA; o_cpu_rd_data = beat b
//     sample beat b       → no valid check; holds correct value even at b==7
//==================================================================================================================================================
task Read(
    input  logic [ADDR_MCTRL-1:0]   address,
    output logic [BL8_DQ_BITS-1:0]  read_data,   // 512-bit: beat N at [N*64+:64]
    input  logic [3:0]               burst_len = 4'd1
);
    @(posedge i_cpu_ck);
    wait(o_cpu_data_rdy);
    @(posedge i_cpu_ck);
    i_cpu_valid   = 1'b1;
    i_cpu_cmd     = 1'b0;       // READ command
    i_cpu_addr    = address;
    i_cpu_burst   = burst_len;
    i_cpu_dm      = '0;
    @(posedge i_cpu_ck);
    i_cpu_valid   = 1'b0;

    // ── Beat 0: wait for valid, advance 1ps past NBA, then sample ────────────
    // BUG A FIX: #1 ensures o_cpu_rd_data NBA has been committed before we read.
    read_data = '0;
    wait(o_cpu_rd_data_valid);
    #1;   // 1ps: past NBA region — both valid and o_cpu_rd_data are now stable
    read_data[0 * RANK_DQ_BITS +: RANK_DQ_BITS] = o_cpu_rd_data;   // beat 0
   $display("INTERFACE o_cpu_rd_data =%h time=%t",o_cpu_rd_data,$time);
    // ── Beats 1..BURST_L-1: one posedge per beat, sample after #1 ────────────
    // BUG B FIX: loop to collect all streaming beats (not just beat 0).
    // BUG C FIX: no valid check — o_cpu_rd_data holds beat value even after valid
    //            deasserts at the beat-7 clock (registered signal keeps last value).
    for (int b = 1; b < BURST_L; b++) begin// 8 
        @(posedge i_cpu_ck);
        #1;   // 1ps: past NBA — DUT has registered beat b into o_cpu_rd_data
        read_data[b * RANK_DQ_BITS +: RANK_DQ_BITS] = o_cpu_rd_data;
    $display("INTERFACE o_cpu_rd_data =%h read data=%h time=%t ",o_cpu_rd_data,read_data,$time);
    end
endtask

//==================================================================================================================================================
// Task: run (legacy combined R/W task)
//==================================================================================================================================================
task run(
    input  logic                       valid,
    input  logic                       cmd,
    input  logic [ADDR_MCTRL-1:0]     address,
    input  logic [RANK_DQ_BITS-1:0]   wr_data,
    output logic [BL8_DQ_BITS-1:0]    rd_data
);
    $display("count=%d", count++);
    $display("DUT ADDRESS address=%h",address);
    @(posedge i_cpu_ck);
    wait(o_cpu_data_rdy);
    @(posedge i_cpu_ck);
    if (valid) begin
        @(posedge i_cpu_ck);
        i_cpu_valid = valid;
        i_cpu_cmd   = cmd;
        if (valid && cmd) begin     // WRITE
            i_cpu_addr    = address;
            i_cpu_wr_data = wr_data;
            i_cpu_burst   = 4'd1;
            i_cpu_dm      = '0;
            @(posedge i_cpu_ck);
            i_cpu_valid = 0;
        end
        if (valid && ~cmd) begin    // READ
            i_cpu_addr  = address;
            i_cpu_burst = 4'd1;
            @(posedge i_cpu_ck);
            i_cpu_valid = 0;
            // Collect all BURST_L beats (same fix as Read task: #1 + no valid guard)
            rd_data = '0;
            wait(o_cpu_rd_data_valid);
            #1;
            rd_data[0 * RANK_DQ_BITS +: RANK_DQ_BITS] = o_cpu_rd_data;
            for (int b = 1; b < BURST_L; b++) begin
                @(posedge i_cpu_ck);
                #1;
                rd_data[b * RANK_DQ_BITS +: RANK_DQ_BITS] = o_cpu_rd_data;
            end
        end
    end
endtask

endinterface : mem_intf


/////////////////////////////////////////axi-interface///////////////////////////////
interface axi_pcie_intf#(
    parameter AXI_DATA_WIDTH = 512,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_STRB_WIDTH = 64,
    parameter AXI_MEM_SIZE   = 10000,
    parameter AXI_LEN_WIDTH  = 4
)(input bit aclk, areset_n);

    // Write address channel
    logic [AXI_ADDR_WIDTH-1:0] awaddr;
    logic [AXI_ID_WIDTH-1:0]   awid;
    logic [AXI_LEN_WIDTH-1:0]  awlen;
    logic                      awvalid;
    logic [2:0]                awsize;
    logic [1:0]                awburst;
    logic [3:0]                awcache;
    logic [2:0]                awprot;
    logic [1:0]                awlock;
    logic                      awready;

    // Write data channel
    logic [AXI_DATA_WIDTH-1:0] wdata;
    logic [AXI_STRB_WIDTH-1:0] wstrb;
    logic                      wlast;
    logic [AXI_ID_WIDTH-1:0]   wid;
    logic                      wvalid;
    logic                      wready;

    // Write response channel
    logic                      bready;
    logic                      bvalid;
    logic [AXI_ID_WIDTH-1:0]   bid;
    logic [1:0]                bresp;

    // Read address channel
    logic [AXI_ADDR_WIDTH-1:0] araddr;
    logic [AXI_ID_WIDTH-1:0]   arid;
    logic [AXI_LEN_WIDTH-1:0]  arlen;
    logic                      arvalid;
    logic [2:0]                arsize;
    logic [3:0]                arcache;
    logic [2:0]                arprot;
    logic [3:0]                arlock;
    logic                      arready;
    logic [1:0]                arburst;

    // Read data channel
    logic                      rready;
    logic [AXI_DATA_WIDTH-1:0] rdata;
    logic                      rvalid;
    logic [AXI_ID_WIDTH-1:0]   rid;
    logic                      rlast;
    logic [1:0]                rresp;

    modport axi_master (
        input  awready, bvalid, bid, bresp, arready, rdata, rvalid, rid, rlast,
               rresp, aclk, areset_n, wready,
        output awaddr, awid, awlen, awvalid, awsize, awburst, awcache, awprot,
               awlock, wdata, wstrb, wlast, wid, wvalid, bready, araddr, arid,
               arlen, arvalid, arsize, arburst, arcache, arprot, arlock, rready
    );

    modport axi_slave (
        input  aclk, areset_n, awaddr, awid, awlen, awvalid, awsize, awburst,
               awcache, awprot, awlock, wdata, wstrb, wlast, wid, wvalid,
               bready, araddr, arid, arburst, arsize, arlen, arvalid, arcache,
               arprot, arlock, rready,
        output awready, bvalid, bid, bresp, arready, rdata, rvalid, rid, rlast,
               rresp, wready
    );

endinterface : axi_pcie_intf


//==================================================================================================================================================
// AXI Config Interface (32-bit)
//==================================================================================================================================================
interface axi_cfg_intf(input bit aclk, areset_n);

    logic [31:0] awaddr;
    logic [3:0]  awid;
    logic [3:0]  awlen;
    logic        awvalid;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic [3:0]  awcache;
    logic [2:0]  awprot;
    logic [1:0]  awlock;
    logic        awready;

    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wlast;
    logic [3:0]  wid;
    logic        wvalid;
    logic        wready;

    logic        bready;
    logic        bvalid;
    logic [3:0]  bid;
    logic [1:0]  bresp;

    logic [31:0] araddr;
    logic [3:0]  arid;
    logic [3:0]  arlen;
    logic        arvalid;
    logic [2:0]  arsize;
    logic [3:0]  arcache;
    logic [2:0]  arprot;
    logic [3:0]  arlock;
    logic        arready;
    logic [1:0]  arburst;

    logic        rready;
    logic [31:0] rdata;
    logic        rvalid;
    logic [3:0]  rid;
    logic        rlast;
    logic [1:0]  rresp;

    modport axi_master (
        input  awready, bvalid, bid, bresp, arready, rdata, rvalid, rid, rlast,
               rresp, aclk, areset_n, wready,
        output awaddr, awid, awlen, awvalid, awsize, awburst, awcache, awprot,
               awlock, wdata, wstrb, wlast, wid, wvalid, bready, araddr, arid,
               arlen, arvalid, arsize, arburst, arcache, arprot, arlock, rready
    );

    modport axi_slave (
        input  aclk, areset_n, awaddr, awid, awlen, awvalid, awsize, awburst,
               awcache, awprot, awlock, wdata, wstrb, wlast, wid, wvalid,
               bready, araddr, arid, arburst, arsize, arlen, arvalid, arcache,
               arprot, arlock, rready,
        output awready, bvalid, bid, bresp, arready, rdata, rvalid, rid, rlast,
               rresp, wready
    );

endinterface : axi_cfg_intf
