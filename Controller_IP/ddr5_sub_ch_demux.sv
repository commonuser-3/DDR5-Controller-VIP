// =============================================================
// ddr5_sub_ch_demux.sv  (FIXED)
// Fix: rd_id_r was declared but never assigned → merged_rid=0.
//      Now captured from req_id when a read is issued.
// =============================================================
`timescale 1ns/1ps
import ddr5_pkg::*;

module ddr5_sub_ch_demux (
  input  logic clk, input logic rst_n,

  input  logic                   req_valid,
  output logic                   req_ready,
  input  logic                   req_is_wr,
  input  logic [AXI_ADDR_W-1:0]  req_addr,
  input  logic [AXI_DATA_W-1:0]  req_wdata,
  input  logic [AXI_STRB_W-1:0]  req_wstrb,
  input  logic [AXI_ID_W-1:0]    req_id,
  input  logic                   dch,

  output logic                   ch0_valid, input logic ch0_ready,
  output logic                   ch0_is_wr,
  output logic [BG_BITS-1:0]     ch0_bg,   output logic [BA_BITS-1:0]  ch0_ba,
  output logic [ROW_BITS-1:0]    ch0_row,  output logic [COL_BITS-1:0] ch0_col,
  output logic [AXI_ID_W-1:0]    ch0_id,
  output logic [511:0]           ch0_wdata, output logic [63:0] ch0_wstrb,

  output logic                   ch1_valid, input logic ch1_ready,
  output logic                   ch1_is_wr,
  output logic [BG_BITS-1:0]     ch1_bg,   output logic [BA_BITS-1:0]  ch1_ba,
  output logic [ROW_BITS-1:0]    ch1_row,  output logic [COL_BITS-1:0] ch1_col,
  output logic [AXI_ID_W-1:0]    ch1_id,
  output logic [511:0]           ch1_wdata, output logic [63:0] ch1_wstrb,

  input  logic [511:0]           ch0_rdata, input logic ch0_rvalid,
  input  logic [511:0]           ch1_rdata, input logic ch1_rvalid,

  output logic [AXI_DATA_W-1:0]  merged_rdata,
  output logic                   merged_rvalid,
  output logic [AXI_ID_W-1:0]    merged_rid
);

  // Address decode
  logic [COL_BITS-1:0] dec_col;
  logic [BA_BITS-1:0]  dec_ba;
  logic [BG_BITS-1:0]  dec_bg;
  logic [ROW_BITS-1:0] dec_row;
  logic ch0_accepted, ch1_accepted;
  logic [511:0]         held_ch0, held_ch1;
  logic                 ch0_held, ch1_held;
  logic [AXI_ID_W-1:0]  rd_id_r;

 /* assign dec_col = {1'b0, req_addr[14:6]};
  assign dec_ba  = req_addr[16:15];
  assign dec_bg  = req_addr[18:17];
  assign dec_row = {{(ROW_BITS-13){1'b0}}, req_addr[31:19]};*/

  //Address mapping from AXI to DDR
  assign dec_bg = {req_addr[13],req_addr[5]};
  assign dec_ba = req_addr[15:14];
  assign dec_row = req_addr[31:16];
  assign dec_col = {req_addr[12:6],req_addr[4:2]};

  // Per-channel accepted flags
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ch0_accepted <= 1'b0; ch1_accepted <= 1'b0;
    end else begin
      if (ch0_valid && ch0_ready) ch0_accepted <= 1'b1;
      if (ch1_valid && ch1_ready) ch1_accepted <= 1'b1;
      if (req_ready) begin ch0_accepted <= 1'b0; ch1_accepted <= 1'b0; end
    end
  end

  assign req_ready = !dch ? (ch0_accepted || (ch0_valid && ch0_ready)) :
                            (ch1_accepted || (ch1_valid && ch1_ready));

  assign ch0_valid = req_valid && !dch && !ch0_accepted;
  assign ch1_valid = req_valid &&  dch && !ch1_accepted;
  assign ch0_is_wr = req_is_wr; assign ch1_is_wr = req_is_wr;
  assign ch0_bg=dec_bg; assign ch1_bg=dec_bg;
  assign ch0_ba=dec_ba; assign ch1_ba=dec_ba;
  assign ch0_row=dec_row; assign ch1_row=dec_row;
  assign ch0_col=dec_col; assign ch1_col=dec_col;
  assign ch0_id=req_id;   assign ch1_id=req_id;
  always_comb begin
    ch0_wdata = '0;
    ch1_wdata = '0;
    ch0_wstrb = '0;
    ch1_wstrb = '0;
    for (int beat = 0; beat < 8; beat++) begin
      if (!dch) begin
        ch0_wdata[(2*beat)*32 +: 32]   = req_wdata[beat*64 +: 32];
        ch0_wdata[(2*beat+1)*32 +: 32] = req_wdata[beat*64+32 +: 32];
        ch0_wstrb[(2*beat)*4 +: 4]     = req_wstrb[beat*8 +: 4];
        ch0_wstrb[(2*beat+1)*4 +: 4]   = req_wstrb[beat*8+4 +: 4];
      end else begin
        ch1_wdata[(2*beat)*32 +: 32]   = req_wdata[beat*64 +: 32];
        ch1_wdata[(2*beat+1)*32 +: 32] = req_wdata[beat*64+32 +: 32];
        ch1_wstrb[(2*beat)*4 +: 4]     = req_wstrb[beat*8 +: 4];
        ch1_wstrb[(2*beat+1)*4 +: 4]   = req_wstrb[beat*8+4 +: 4];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && req_valid && req_ready) begin
      $display("[DDR5 DEMUX][REQ_ACCEPTED] t=%0t req_is_wr=%0b req_addr=%0h req_id=%0h",
               $time, req_is_wr, req_addr, req_id);
      $display("[DDR5 DEMUX][DECODE] bg=%0h ba=%0h row=%0h col=%0h ch0_valid=%0b ch1_valid=%0b ch0_ready=%0b ch1_ready=%0b",
               dec_bg, dec_ba, dec_row, dec_col, ch0_valid, ch1_valid, ch0_ready, ch1_ready);
      if (req_is_wr) begin
        $display("[DDR5 DEMUX][WRITE_FULL] req_wdata[511:0]=%0h req_wstrb[63:0]=%0h",
                 req_wdata, req_wstrb);
        $display("[DDR5 DEMUX][WRITE_CH0] ch0_id=%0h ch0_wdata[511:0]=%0h ch0_wstrb[63:0]=%0h",
                 ch0_id, ch0_wdata, ch0_wstrb);
        $display("[DDR5 DEMUX][WRITE_CH1] ch1_id=%0h ch1_wdata[511:0]=%0h ch1_wstrb[63:0]=%0h",
                 ch1_id, ch1_wdata, ch1_wstrb);
      end else begin
        $display("[DDR5 DEMUX][READ_REQ] ch0_id=%0h ch1_id=%0h", ch0_id, ch1_id);
      end
    end
  end

  // Read data merge

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ch0_held <= 1'b0; ch1_held <= 1'b0;
      held_ch0 <= '0;   held_ch1 <= '0;
      rd_id_r  <= '0;
    end else begin
      if (ch0_rvalid && !ch0_held) begin
        held_ch0 <= ch0_rdata;
        ch0_held <= 1'b1;
        rd_id_r  <= ch0_id;
      end
      if (ch1_rvalid && !ch1_held) begin
        held_ch1 <= ch1_rdata;
        ch1_held <= 1'b1;
        rd_id_r  <= ch1_id;
      end
      if (merged_rvalid) begin
        ch0_held <= 1'b0; ch1_held <= 1'b0;
      end
    end
  end

  assign merged_rvalid = !dch ? ch0_held : ch1_held;
  always_comb begin
    merged_rdata = '0;
    for (int beat = 0; beat < 8; beat++) begin
      if (!dch) begin
        merged_rdata[beat*64 +: 32]    = held_ch0[(2*beat)*32 +: 32];
        merged_rdata[beat*64+32 +: 32] = held_ch0[(2*beat+1)*32 +: 32];
      end else begin
        merged_rdata[beat*64 +: 32]    = held_ch1[(2*beat)*32 +: 32];
        merged_rdata[beat*64+32 +: 32] = held_ch1[(2*beat+1)*32 +: 32];
      end
    end
  end
  assign merged_rid    = rd_id_r;

endmodule : ddr5_sub_ch_demux
