// =============================================================
// ddr5_phy.sv
// DDR5 PHY behavioral model for the DFI 5.1 controller interface.
// =============================================================

`timescale 1ns/1ps

import ddr5_pkg::*;

module ddr5_zq_cal #(
  parameter int CAL_CYCLES = 8
)(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  output logic       done,
  output logic       fail,
  output logic [5:0] pu_code,
  output logic [5:0] pd_code
);

  logic       busy;
  logic [7:0] count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy    <= 1'b0;
      count   <= '0;
      done    <= 1'b0;
      fail    <= 1'b0;
      pu_code <= 6'd32;
      pd_code <= 6'd32;
    end else begin
      done <= 1'b0;
      fail <= 1'b0;

      if (start && !busy) begin
        busy  <= 1'b1;
        count <= CAL_CYCLES[7:0];
      end else if (busy) begin
        if (count == 8'd0) begin
          busy    <= 1'b0;
          done    <= 1'b1;
          pu_code <= 6'd32;
          pd_code <= 6'd32;
        end else begin
          count <= count - 8'd1;
        end
      end
    end
  end

endmodule : ddr5_zq_cal

module ddr5_phy (
  input  logic ctrl_clk,
  input  logic dram_clk,
  input  logic ctrl_rst_n,

  dfi5_if.phy_mp dfi_ch0,
  dfi5_if.phy_mp dfi_ch1,

  output logic        ck0_t,
  output logic        ck0_c,
  output logic [13:0] ca0,
  output logic        cai0,
  output logic        cs0_n,
  output logic        cke0,
  output logic        reset0_n,
  output logic [31:0] dq0_out,
  input  logic [31:0] dq0_in,
  output logic        dq0_oe,
  output logic [3:0]  dqs0_t,
  output logic [3:0]  dqs0_c,
  output logic        dqs0_oe,
  output logic [3:0]  dm0,
  output logic        dram_wr_valid0,
  output logic [511:0] dram_wr_data0,
  output logic [63:0]  dram_wr_mask0,
  input  logic        dram_rd_valid0,
  input  logic [511:0] dram_rd_data0,

  output logic        ck1_t,
  output logic        ck1_c,
  output logic [13:0] ca1,
  output logic        cai1,
  output logic        cs1_n,
  output logic        cke1,
  output logic        reset1_n,
  output logic [31:0] dq1_out,
  input  logic [31:0] dq1_in,
  output logic        dq1_oe,
  output logic [3:0]  dqs1_t,
  output logic [3:0]  dqs1_c,
  output logic        dqs1_oe,
  output logic [3:0]  dm1,
  output logic        dram_wr_valid1,
  output logic [511:0] dram_wr_data1,
  output logic [63:0]  dram_wr_mask1,
  input  logic        dram_rd_valid1,
  input  logic [511:0] dram_rd_data1
);

  typedef enum logic [3:0] {
    S_IDLE      = 4'h0,
    S_PLL_LOCK  = 4'h1,
    S_DLL_LOCK  = 4'h2,
    S_CLK_START = 4'h3,
    S_IO_CAL    = 4'h4,
    S_ZQ_CAL    = 4'h5,
    S_DLY_CAL   = 4'h6,
    S_FIFO_RST  = 4'h7,
    S_INIT_DONE = 4'h8,
    S_CMD_FWD   = 4'h9,
    S_NORMAL    = 4'hA,
    S_FWD_CTRL  = 4'hB   // forward MC reset/cke/CA until dram init completes
  } phy_state_e;

  localparam int T_PLL_LOCK  = 100;
  localparam int T_DLL_LOCK  = 50;
  localparam int T_CLK_STAB  = 10;
  localparam int T_IO_CAL    = 50;
  localparam int T_DLY_CAL   = 30;
  localparam int T_FIFO_RST  = 10;
  localparam int T_INIT_HOLD = 4;
  localparam int TPHY_RDLAT  = 2;
 parameter real dram_tck = 156.25; 
logic dqs_oe_int_ch0_d;

  phy_state_e state;
  logic [9:0] timer;
  logic       clk_enable;
  logic       zq_started;
  logic       zq_start;
  logic       zq_done;
  logic       zq_fail;
  logic [5:0] pu_code;
  logic [5:0] pd_code;

  logic [1:0] dram_phase;
  logic [1:0] ca_phase;
  logic [3:0] data_phase;
  logic       ca_cmd_pending;
  logic       ca_cmd_active;
  logic       ca_cmd_second;
  logic [13:0] ca_latch_ch0 [DFI_PHASES];
  logic [13:0] ca_latch_ch1 [DFI_PHASES];
  logic        cs_latch_ch0 [DFI_PHASES];
  logic        cs_latch_ch1 [DFI_PHASES];
  logic [13:0] ca0_original;
  logic [13:0] ca1_original;
  logic [3:0]  ca0_ones;
  logic [3:0]  ca1_ones;

  logic wr_req_ch0;
  logic wr_req_ch1;
  logic dqs_toggle_ch0;
  logic dqs_toggle_ch1;
  // Intermediate OE signals: set by posedge write-control block,
  // used by the dual-edge DQS toggle block to gate output.
  logic dqs_oe_int_ch0;
  logic dqs_oe_int_ch1;
  logic rd_token_ch0_q;
  logic rd_token_ch1_q;
  logic        wr_active_ch0;
  logic        wr_active_ch1;
  logic [4:0]  wr_idx_ch0;
  logic [4:0]  wr_idx_ch1;
  logic [511:0] wr_latch_ch0;
  logic [511:0] wr_latch_ch1;
  logic [63:0]  dm_latch_ch0;
  logic [63:0]  dm_latch_ch1;
  logic [511:0] wr_pack_ch0;
  logic [511:0] wr_pack_ch1;
  logic [63:0]  dm_pack_ch0;
  logic [63:0]  dm_pack_ch1;

  logic [TPHY_RDLAT:0] rd_en_pipe_ch0;
  logic [TPHY_RDLAT:0] rd_en_pipe_ch1;
  logic [1:0]          rd_burst_ch0;
  logic [1:0]          rd_burst_ch1;

  ddr5_zq_cal u_zq_cal (
    .clk     (ctrl_clk),
    .rst_n   (ctrl_rst_n),
    .start   (zq_start),
    .done    (zq_done),
    .fail    (zq_fail),
    .pu_code (pu_code),
    .pd_code (pd_code)
  );
//counting number of ones 
  function automatic logic [3:0] count_ca_ones(input logic [13:0] ca_word);
    logic [3:0] count;
    begin
      count = '0;
      for (int b = 0; b < 14; b++) begin
        if (ca_word[b] === 1'b1)
          count = count + 1'b1;
      end
      count_ca_ones = count;
    end
  endfunction
//decide wheather cai needed 
  function automatic logic ca_needs_cai(input logic [13:0] ca_word);
    begin
      ca_needs_cai = (count_ca_ones(ca_word) > 4'd7);
    end
  endfunction
//logic
// Combinational — no register delay
assign dqs_oe_int_ch0 = wr_active_ch0 || (wr_req_ch0 && !wr_active_ch0);
assign dqs_oe_int_ch1 = wr_active_ch1 || (wr_req_ch1 && !wr_active_ch1);
  always_comb begin
    ca0_ones = count_ca_ones(ca0_original);
    ca1_ones = count_ca_ones(ca1_original);
    cai0 = (ctrl_rst_n && !cs0_n && (ca0_ones > 4'd7));
    cai1 = (ctrl_rst_n && !cs1_n && (ca1_ones > 4'd7));
    ca0  = cai0 ? ~ca0_original : ca0_original;
    ca1  = cai1 ? ~ca1_original : ca1_original;
  end

  always_comb begin
    ca_cmd_active = 1'b0;
    for (int p = 0; p < DFI_PHASES; p++) begin
      ca_cmd_active |= ~dfi_ch0.dfi_cs_p[p][0];
      ca_cmd_active |= ~dfi_ch1.dfi_cs_p[p][0];
    end
  end

  always_comb begin
    wr_req_ch0 = 1'b0;
    wr_req_ch1 = 1'b0;
    wr_pack_ch0 = '0;
    wr_pack_ch1 = '0;
    dm_pack_ch0 = '0;
    dm_pack_ch1 = '0;
    for (int w = 0; w < DFI_WORDS; w++) begin
      wr_req_ch0 |= dfi_ch0.dfi_wrdata_en_p[w];
      wr_req_ch1 |= dfi_ch1.dfi_wrdata_en_p[w];
      wr_pack_ch0[w*32 +: 32] = dfi_ch0.dfi_wrdata_p[w];
      dm_pack_ch0[w*4  +:  4] = dfi_ch0.dfi_wrdata_mask_p[w];
      wr_pack_ch1[w*32 +: 32] = dfi_ch1.dfi_wrdata_p[w];
      dm_pack_ch1[w*4  +:  4] = dfi_ch1.dfi_wrdata_mask_p[w];
    end
  end

  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      dram_phase <= 2'd0;
      data_phase <= 4'd0;
    end else begin
      dram_phase <= dram_phase + 2'd1;
      data_phase <= data_phase + 4'd1;
    end
  end

  always_ff @(posedge dram_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      ca_phase <= 2'd0;
    end else if (clk_enable) begin
      ca_phase <= ca_phase + 2'd1;
    end else begin
      ca_phase <= 2'd0;
    end
  end
//===============ck_t ck_c generation========================
assign ck0_t = (clk_enable && ctrl_rst_n)?  dram_clk: 1'bz;
assign ck0_c = (clk_enable && ctrl_rst_n)? ~dram_clk: 1'bz;
assign ck1_t = (clk_enable && ctrl_rst_n)?  dram_clk: 1'bz;
assign ck1_c = (clk_enable && ctrl_rst_n)? ~dram_clk: 1'bz;

  //always_ff @(posedge dram_clk or negedge ctrl_rst_n ) begin
//    if (!ctrl_rst_n) begin
//      ck0_t <= 1'b0;
//      ck0_c <= 1'b1;
//      ck1_t <= 1'b0;
 //     ck1_c <= 1'b1;
//    end else if (clk_enable) begin
 //     ck0_t <= ~ck0_t;
 //     ck0_c <= ~ck0_c;
 //     ck1_t <= ~ck1_t;
 //     ck1_c <= ~ck1_c;
 //   end else begin
 //     ck0_t <= 1'b0;
    //  ck0_c <= 1'b1;
//      ck1_t <= 1'b0;
//      ck1_c <= 1'b1;
//    end
//  end

  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      state       <= S_IDLE;
      timer       <= '0;
      clk_enable  <= 1'b0;
      zq_started  <= 1'b0;
      zq_start    <= 1'b0;

      dfi_ch0.dfi_init_complete    <= 1'b0;
      dfi_ch0.dfi_ctrlupd_ack      <= 1'b0;
      dfi_ch0.dfi_phyupd_req       <= 1'b0;
      dfi_ch0.dfi_phyupd_type      <= 2'b00;
      dfi_ch0.dfi_phymstr_req      <= 1'b0;
      dfi_ch0.dfi_phymstr_type     <= 2'b00;
      dfi_ch0.dfi_phymstr_cs_state <= '0;
      dfi_ch0.dfi_phymstr_state_sel<= 1'b0;
      dfi_ch0.dfi_alert_n_a        <= '1;
      dfi_ch0.dfi_disconnect_error <= 1'b0;
      dfi_ch0.dfi_error            <= 1'b0;
      dfi_ch0.dfi_error_info       <= '0;
      dfi_ch0.dfi_lp_ctrl_ack      <= 1'b0;
      dfi_ch0.dfi_lp_data_ack      <= 1'b0;
      dfi_ch0.dfi_ctrlmsg_ack      <= 1'b0;

      dfi_ch1.dfi_init_complete    <= 1'b0;
      dfi_ch1.dfi_ctrlupd_ack      <= 1'b0;
      dfi_ch1.dfi_phyupd_req       <= 1'b0;
      dfi_ch1.dfi_phyupd_type      <= 2'b00;
      dfi_ch1.dfi_phymstr_req      <= 1'b0;
      dfi_ch1.dfi_phymstr_type     <= 2'b00;
      dfi_ch1.dfi_phymstr_cs_state <= '0;
      dfi_ch1.dfi_phymstr_state_sel<= 1'b0;
      dfi_ch1.dfi_alert_n_a        <= '1;
      dfi_ch1.dfi_disconnect_error <= 1'b0;
      dfi_ch1.dfi_error            <= 1'b0;
      dfi_ch1.dfi_error_info       <= '0;
      dfi_ch1.dfi_lp_ctrl_ack      <= 1'b0;
      dfi_ch1.dfi_lp_data_ack      <= 1'b0;
      dfi_ch1.dfi_ctrlmsg_ack      <= 1'b0;
    end else begin
      zq_start <= 1'b0;

      dfi_ch0.dfi_ctrlupd_ack <= dfi_ch0.dfi_ctrlupd_req;
      dfi_ch1.dfi_ctrlupd_ack <= dfi_ch1.dfi_ctrlupd_req;
      dfi_ch0.dfi_lp_ctrl_ack <= dfi_ch0.dfi_lp_ctrl_req;
      dfi_ch1.dfi_lp_ctrl_ack <= dfi_ch1.dfi_lp_ctrl_req;
      dfi_ch0.dfi_lp_data_ack <= dfi_ch0.dfi_lp_data_req;
      dfi_ch1.dfi_lp_data_ack <= dfi_ch1.dfi_lp_data_req;
      dfi_ch0.dfi_ctrlmsg_ack <= dfi_ch0.dfi_ctrlmsg_req;
      dfi_ch1.dfi_ctrlmsg_ack <= dfi_ch1.dfi_ctrlmsg_req;
      dfi_ch0.dfi_phyupd_req  <= 1'b0;
      dfi_ch1.dfi_phyupd_req  <= 1'b0;
      dfi_ch0.dfi_phymstr_req <= 1'b0;
      dfi_ch1.dfi_phymstr_req <= 1'b0;
      dfi_ch0.dfi_alert_n_a   <= '1;
      dfi_ch1.dfi_alert_n_a   <= '1;

      unique case (state)
        S_IDLE: begin
          clk_enable                   <= 1'b0;
          dfi_ch0.dfi_init_complete    <= 1'b0;
          dfi_ch1.dfi_init_complete    <= 1'b0;
          dfi_ch0.dfi_disconnect_error <= 1'b0;
          dfi_ch1.dfi_disconnect_error <= 1'b0;
          dfi_ch0.dfi_error            <= 1'b0;
          dfi_ch1.dfi_error            <= 1'b0;
          dfi_ch0.dfi_error_info       <= '0;
          dfi_ch1.dfi_error_info       <= '0;

          if (dfi_ch0.dfi_init_start || dfi_ch1.dfi_init_start) begin
            state <= S_PLL_LOCK;
            timer <= T_PLL_LOCK - 1;
          end
        end

        S_PLL_LOCK: begin
          if (timer == 10'd0) begin
            state <= S_DLL_LOCK;
            timer <= T_DLL_LOCK - 1;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        S_DLL_LOCK: begin
          if (timer == 10'd0) begin
            state <= S_CLK_START;
            timer <= T_CLK_STAB - 1;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        S_CLK_START: begin
          clk_enable <= 1'b1;
          if (timer == 10'd0) begin
            state <= S_IO_CAL;
            timer <= T_IO_CAL - 1;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        S_IO_CAL: begin
          if (timer == 10'd0) begin
            // IO cal done — pulse dfi_init_complete for ONE cycle.
            // ctrl_top sees this and starts ddr5_init_fsm.
            // It will be deasserted next cycle until S_INIT_DONE.
            dfi_ch0.dfi_init_complete <= 1'b1;
            dfi_ch1.dfi_init_complete <= 1'b1;
            state <= S_FWD_CTRL;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        // Wait for controller dram-init; forward DFI reset/cke/CA to DRAM pins.
        // init_fsm started when dfi_init_complete pulsed above.
        // ctrl_top drives dfi_ctrlupd_req = init_done_int.
        // PHY exits only when full DRAM init sequence is done.
        S_FWD_CTRL: begin
          dfi_ch0.dfi_init_complete <= 1'b0;
          dfi_ch1.dfi_init_complete <= 1'b0;
          if (dfi_ch0.dfi_ctrlupd_req || dfi_ch1.dfi_ctrlupd_req) begin
            state      <= S_ZQ_CAL;
            zq_started <= 1'b0;
          end
        end

        S_ZQ_CAL: begin
          if (!zq_started) begin
            zq_start   <= 1'b1;
            zq_started <= 1'b1;
          end else if (zq_done) begin
            zq_started <= 1'b0;
            state      <= S_DLY_CAL;
            timer      <= T_DLY_CAL - 1;
          end else if (zq_fail) begin
            dfi_ch0.dfi_error      <= 1'b1;
            dfi_ch1.dfi_error      <= 1'b1;
            dfi_ch0.dfi_error_info <= 4'h1;
            dfi_ch1.dfi_error_info <= 4'h1;
          end
        end

        S_DLY_CAL: begin
          if (timer == 10'd0) begin
            state <= S_FIFO_RST;
            timer <= T_FIFO_RST - 1;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        S_FIFO_RST: begin
          if (timer == 10'd0) begin
            state <= S_INIT_DONE;
            timer <= T_INIT_HOLD - 1;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        S_INIT_DONE: begin
          dfi_ch0.dfi_init_complete <= 1'b1;
          dfi_ch1.dfi_init_complete <= 1'b1;
          if (timer == 10'd0) begin
            state <= S_CMD_FWD;
          end else begin
            timer <= timer - 10'd1;
          end
        end

        S_CMD_FWD: begin
          dfi_ch0.dfi_init_complete <= 1'b1;
          dfi_ch1.dfi_init_complete <= 1'b1;
          state <= S_NORMAL;
        end

        S_NORMAL: begin
          dfi_ch0.dfi_init_complete <= 1'b1;
          dfi_ch1.dfi_init_complete <= 1'b1;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

  always_ff @(posedge dram_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      ca0_original <= 14'h3fff;
      cs0_n    <= 1'b1;
      cke0     <= 1'b0;
      reset0_n <= 1'b0;
      ca1_original <= 14'h3fff;
      cs1_n    <= 1'b1;
      cke1     <= 1'b0;
      reset1_n <= 1'b0;
      ca_cmd_pending <= 1'b0;
      ca_cmd_second  <= 1'b0;
      for (int p = 0; p < DFI_PHASES; p++) begin
        ca_latch_ch0[p] <= 14'h3fff;
        ca_latch_ch1[p] <= 14'h3fff;
        cs_latch_ch0[p] <= 1'b1;
        cs_latch_ch1[p] <= 1'b1;
      end
    end else begin
      cke0     <= dfi_ch0.dfi_cke_p[ca_phase][0];
      reset0_n <= dfi_ch0.dfi_reset_n_p[ca_phase][0];
      cke1     <= dfi_ch1.dfi_cke_p[ca_phase][0];
      reset1_n <= dfi_ch1.dfi_reset_n_p[ca_phase][0];

      if (clk_enable && (ca_phase == 2'd0) &&
          ca_cmd_active && !ca_cmd_pending && !ca_cmd_second) begin
        for (int p = 0; p < DFI_PHASES; p++) begin
          ca_latch_ch0[p] <= dfi_ch0.dfi_address_p[p];
          ca_latch_ch1[p] <= dfi_ch1.dfi_address_p[p];
          cs_latch_ch0[p] <= dfi_ch0.dfi_cs_p[p][0];
          cs_latch_ch1[p] <= dfi_ch1.dfi_cs_p[p][0];
        end
        ca_cmd_pending <= 1'b1;
      end

      // Present CA only on CK_t rising command cycles. Falling CK half-cycles
      // are deselect/NOP so the DRAM model observes exactly cycle-1, cycle-2.
      if (ca_phase[0]==1'b0) begin
        if (ca_cmd_pending) begin
          ca0_original <= ca_latch_ch0[0];
          cs0_n    <= cs_latch_ch0[0];
          ca1_original <= ca_latch_ch1[0];
          cs1_n    <= cs_latch_ch1[0];
          if (!cs_latch_ch0[0] && ca_needs_cai(ca_latch_ch0[0]))
            $display("[DDR5 PHY][CAI][CH0] t=%0t original_ca=%014b ones=%0d transmitted_ca=%014b CAI=1",
                     $time, ca_latch_ch0[0], count_ca_ones(ca_latch_ch0[0]), ~ca_latch_ch0[0]);
          if (!cs_latch_ch1[0] && ca_needs_cai(ca_latch_ch1[0]))
            $display("[DDR5 PHY][CAI][CH1] t=%0t original_ca=%014b ones=%0d transmitted_ca=%014b CAI=1",
                     $time, ca_latch_ch1[0], count_ca_ones(ca_latch_ch1[0]), ~ca_latch_ch1[0]);
          ca_cmd_pending <= 1'b0;
          ca_cmd_second  <= 1'b1;
        end else begin
          ca0_original   <= 14'h3fff;
          cs0_n <= 1'b1;
          ca1_original   <= 14'h3fff;
          cs1_n <= 1'b1;
        end
      end else begin
        if (ca_cmd_second) begin
          ca0_original      <= ca_latch_ch0[2];
          cs0_n    <= cs_latch_ch0[2];
          ca1_original <= ca_latch_ch1[2];
          cs1_n    <= cs_latch_ch1[2];
          if (!cs_latch_ch0[2] && ca_needs_cai(ca_latch_ch0[2]))
            $display("[DDR5 PHY][CAI][CH0] t=%0t original_ca=%014b ones=%0d transmitted_ca=%014b CAI=1",
                     $time, ca_latch_ch0[2], count_ca_ones(ca_latch_ch0[2]), ~ca_latch_ch0[2]);
          if (!cs_latch_ch1[2] && ca_needs_cai(ca_latch_ch1[2]))
            $display("[DDR5 PHY][CAI][CH1] t=%0t original_ca=%014b ones=%0d transmitted_ca=%014b CAI=1",
                     $time, ca_latch_ch1[2], count_ca_ones(ca_latch_ch1[2]), ~ca_latch_ch1[2]);
          ca_cmd_second <= 1'b0;
        end else begin
          ca0_original <= 14'h3fff;
          cs0_n <= 1'b1;
          ca1_original <= 14'h3fff;
          cs1_n <= 1'b1;
        end
end    end
  end

  // -------------------------------------------------------------------
  // Write-control block (posedge and negedhe).
  // Drives DQ, DM, and OE signals.  DQS toggling is moved to the
  // dual-edge block below so that DQS frequency == ctrl_clk frequency.
  // -------------------------------------------------------------------
  always_ff @(posedge dram_clk or negedge dram_clk) begin
    if (!ctrl_rst_n) begin
      dq0_out        <= '0;
      dq0_oe         <= 1'b0;
      dqs0_t         <= '0;
      dqs0_c         <= '1;
      dqs0_oe        <= 1'b0;
      dm0            <= '0;
   //   dqs_oe_int_ch0 <= 1'b0;

      dq1_out        <= '0;
      dq1_oe         <= 1'b0;
      dqs1_t         <= '0;
      dqs1_c         <= '1;
      dqs1_oe        <= 1'b0;
      dm1            <= '0;
   //   dqs_oe_int_ch1 <= 1'b0;

      wr_active_ch0  <= 1'b0;
      wr_active_ch1  <= 1'b0;
      wr_idx_ch0     <= '0;
      wr_idx_ch1     <= '0;
      wr_latch_ch0   <= '0;
      wr_latch_ch1   <= '0;
      dm_latch_ch0   <= '0;
      dm_latch_ch1   <= '0;
      dram_wr_valid0 <= 1'b0;
      dram_wr_data0  <= '0;
      dram_wr_mask0  <= '0;
      dram_wr_valid1 <= 1'b0;
      dram_wr_data1  <= '0;
      dram_wr_mask1  <= '0;
    end else begin
      dram_wr_valid0 <= wr_req_ch0;
      dram_wr_valid1 <= wr_req_ch1;
      for (int w = 0; w < DFI_WORDS; w++) begin
        dram_wr_data0[w*32 +: 32] <= dfi_ch0.dfi_wrdata_p[w];
        dram_wr_mask0[w*4  +:  4] <= dfi_ch0.dfi_wrdata_mask_p[w];
        dram_wr_data1[w*32 +: 32] <= dfi_ch1.dfi_wrdata_p[w];
        dram_wr_mask1[w*4  +:  4] <= dfi_ch1.dfi_wrdata_mask_p[w];
      end

      // -- Channel 0 write control --
      if (wr_req_ch0 && !wr_active_ch0) begin
        wr_latch_ch0   <= wr_pack_ch0;
        dm_latch_ch0   <= dm_pack_ch0;
        wr_active_ch0  <= 1'b1;
        wr_idx_ch0     <= 5'd1;
	if(wr_idx_ch0!=16) begin
        	dq0_out        <= wr_pack_ch0[31:0];
        	dm0            <= dm_pack_ch0[3:0];
        	dq0_oe         <= 1'b1;
	end
        dqs0_oe        <= 1'b1;
      // enable dual-edge DQS toggle
      end else if (wr_active_ch0) begin
	      if(wr_idx_ch0!=16) begin
        dq0_out        <= wr_latch_ch0[wr_idx_ch0*32 +: 32];
        dm0            <= dm_latch_ch0[wr_idx_ch0*4 +: 4];
        dq0_oe         <= 1'b1;
end
        dqs0_oe        <= 1'b1;
        if (wr_idx_ch0 == 5'd16) begin
          wr_active_ch0  <= 1'b0;
          wr_idx_ch0     <= '0;
        // last beat: disable DQS next cycle
        end else begin
          wr_idx_ch0 <= wr_idx_ch0 + 5'd1;
        end
      end else begin
        dq0_out        <= '0;
        dq0_oe         <= 1'b0;
        dqs0_t         <= '0;
        dqs0_c         <= '1;
        dqs0_oe        <= 1'b0;
        dm0            <= '0;
        dqs_toggle_ch0 <= 1'b0;
      end
      // -- Channel 1 write control --
      if (wr_req_ch1 && !wr_active_ch1) begin
        wr_latch_ch1   <= wr_pack_ch1;
        dm_latch_ch1   <= dm_pack_ch1;
        wr_active_ch1  <= 1'b1;
        wr_idx_ch1     <= 5'd1;
	if(wr_idx_ch1!=16) begin
        dq1_out        <= wr_pack_ch1[31:0];
        dm1            <= dm_pack_ch1[3:0];
        dq1_oe         <= 1'b1;
end
        dqs1_oe        <= 1'b1;
      end else if (wr_active_ch1) begin
	      if(wr_idx_ch1!=16) begin
        dq1_out        <= wr_latch_ch1[wr_idx_ch1*32 +: 32];
        dm1            <= dm_latch_ch1[wr_idx_ch1*4 +: 4];
        dq1_oe         <= 1'b1;
end
        dqs1_oe        <= 1'b1;
        if (wr_idx_ch1 == 5'd16) begin
          wr_active_ch1  <= 1'b0;
          wr_idx_ch1     <= '0;
        end else begin
          wr_idx_ch1 <= wr_idx_ch1 + 5'd1;
        end
      end else begin
        dq1_out        <= '0;
        dq1_oe         <= 1'b0;
        dqs1_t         <= '0;
        dqs1_c         <= '1;
        dqs1_oe        <= 1'b0;
        dm1            <= '0;
        dqs_toggle_ch1 <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------------------
  // Dual-edge DQS toggle block.
  // Toggling on BOTH posedge and negedge of ctrl_clk produces a DQS
  // waveform whose frequency equals ctrl_clk (one full cycle per
  // ctrl_clk period, i.e. half-period = half of ctrl_clk period).
  // Reset is synchronised to posedge only; negedge arm initialises
  // from the same rst_n but drives its own flop bank.
  // -------------------------------------------------------------------
  always_ff @(posedge dram_clk or negedge dram_clk) begin
    if (!ctrl_rst_n) begin
      dqs_toggle_ch0 <= 1'b0;
      dqs0_t         <= '0;
      dqs0_c         <= '1;
    end else if (dqs_oe_int_ch0) begin
      dqs_toggle_ch0 <= ~dqs_toggle_ch0;
      dqs0_t         <= {4{ck0_t}};
      dqs0_c         <= {4{ck0_c}};
    end else begin
      dqs_toggle_ch0 <= 1'b0;
      dqs0_t         <= '0;
      dqs0_c         <= '1;
    end
  end

  
  always_ff @(posedge dram_clk or negedge dram_clk) begin
    if (!ctrl_rst_n) begin
      dqs_toggle_ch1 <= 1'b0;
      dqs1_t         <= '0;
      dqs1_c         <= '1;
    end else if (dqs_oe_int_ch1) begin
      dqs_toggle_ch1 <= ~dqs_toggle_ch1;
      dqs1_t         <= {4{~dqs_toggle_ch1}};
      dqs1_c         <= {4{ dqs_toggle_ch1}};
    end else begin
      dqs_toggle_ch1 <= 1'b0;
      dqs1_t         <= '0;
      dqs1_c         <= '1;
    end
  end

   always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      rd_en_pipe_ch0 <= '0;
      rd_en_pipe_ch1 <= '0;
      rd_burst_ch0   <= '0;
      rd_burst_ch1   <= '0;
      rd_token_ch0_q <= 1'b0;
      rd_token_ch1_q <= 1'b0;
      for (int w = 0; w < DFI_WORDS; w++) begin
        dfi_ch0.dfi_rddata_w[w]       <= '0;
        dfi_ch0.dfi_rddata_valid_w[w] <= 1'b0;
        dfi_ch0.dfi_rddata_dbi_w[w]   <= '0;
        dfi_ch0.dfi_rddata_dnv_w[w]   <= '0;
        dfi_ch1.dfi_rddata_w[w]       <= '0;
        dfi_ch1.dfi_rddata_valid_w[w] <= 1'b0;
        dfi_ch1.dfi_rddata_dbi_w[w]   <= '0;
        dfi_ch1.dfi_rddata_dnv_w[w]   <= '0;
      end
    end else begin
      rd_en_pipe_ch0 <= {rd_en_pipe_ch0[TPHY_RDLAT-1:0], dfi_ch0.dfi_rddata_en_p[0]};
      rd_en_pipe_ch1 <= {rd_en_pipe_ch1[TPHY_RDLAT-1:0], dfi_ch1.dfi_rddata_en_p[0]};

      for (int w = 0; w < DFI_WORDS; w++) begin
        dfi_ch0.dfi_rddata_valid_w[w] <= (dram_rd_valid0 != rd_token_ch0_q);
        dfi_ch0.dfi_rddata_w[w]       <= dram_rd_data0[w*32 +: 32];
        dfi_ch0.dfi_rddata_dbi_w[w]   <= '0;
        dfi_ch0.dfi_rddata_dnv_w[w]   <= '0;

        dfi_ch1.dfi_rddata_valid_w[w] <= (dram_rd_valid1 != rd_token_ch1_q);
        dfi_ch1.dfi_rddata_w[w]       <= dram_rd_data1[w*32 +: 32];
        dfi_ch1.dfi_rddata_dbi_w[w]   <= '0;
        dfi_ch1.dfi_rddata_dnv_w[w]   <= '0;
      end

      if (dram_rd_valid0 != rd_token_ch0_q)
        rd_token_ch0_q <= dram_rd_valid0;
      if (dram_rd_valid1 != rd_token_ch1_q)
        rd_token_ch1_q <= dram_rd_valid1;
    end
  end

endmodule : ddr5_phy


module phy_top(
	input ctrl_clk,
	input dram_clk,
	input ctrl_rst_n,
	dfi5_if.phy_mp dfi_ch0,
	dfi5_if.phy_mp dfi_ch1,
	mem_if dram_if,
	input [31:0] dq0_in,
	input dram_rd_valid0,
	input [511:0] dram_rd_data0,
	input [31:0] dq1_in,
	input dram_rd_valid1,
	input [511:0]dram_rd_data1,
	input dch
);
		logic        phy_ck0_t, phy_ck0_c;
		logic [13:0] phy_ca0;
		logic        phy_cai0;
		logic        phy_cs0_n, phy_cke0, phy_reset0_n;
		logic [31:0] phy_dq0_out, phy_dq0_in;
		logic        phy_dq0_oe;
		logic [3:0]  phy_dqs0_t, phy_dqs0_c, phy_dm0;
		logic        phy_dqs0_oe;

		logic        phy_ck1_t, phy_ck1_c;
		logic [13:0] phy_ca1;
		logic        phy_cai1;
		logic        phy_cs1_n, phy_cke1, phy_reset1_n;
		logic [31:0] phy_dq1_out, phy_dq1_in;
		logic        phy_dq1_oe;
		logic [3:0]  phy_dqs1_t, phy_dqs1_c, phy_dm1;
		logic        phy_dqs1_oe;
		logic        dram_wr_valid0, dram_wr_valid1;
		logic [511:0] dram_wr_data0, dram_wr_data1;
		logic [63:0]  dram_wr_mask0, dram_wr_mask1;

		logic        dram_reset_n_pin;
		logic        dram_cs_init_done;
		parameter real dram_tck = 156.25ps; 
                ddr5_phy u_phy (
			.ctrl_clk   (ctrl_clk),
			.dram_clk   (dram_clk),
			.ctrl_rst_n (ctrl_rst_n),
			.dfi_ch0    (dfi_ch0),
			.dfi_ch1    (dfi_ch1),

			.ck0_t      (phy_ck0_t),
			.ck0_c      (phy_ck0_c),
			.ca0        (phy_ca0),
			.cai0       (phy_cai0),
			.cs0_n      (phy_cs0_n),
			.cke0       (phy_cke0),
			.reset0_n   (phy_reset0_n),
			.dq0_out    (phy_dq0_out),
			.dq0_in     (phy_dq0_in),
			.dq0_oe     (phy_dq0_oe),
			.dqs0_t     (phy_dqs0_t),
			.dqs0_c     (phy_dqs0_c),
			.dqs0_oe    (phy_dqs0_oe),
			.dm0        (phy_dm0),
			.dram_wr_valid0(dram_wr_valid0),
			.dram_wr_data0 (dram_wr_data0),
			.dram_wr_mask0 (dram_wr_mask0),
			.dram_rd_valid0(dram_rd_valid0),
			.dram_rd_data0 (dram_rd_data0),

			.ck1_t      (phy_ck1_t),
			.ck1_c      (phy_ck1_c),
			.ca1        (phy_ca1),
			.cai1       (phy_cai1),
			.cs1_n      (phy_cs1_n),
			.cke1       (phy_cke1),
			.reset1_n   (phy_reset1_n),
			.dq1_out    (phy_dq1_out),
			.dq1_in     (phy_dq1_in),
			.dq1_oe     (phy_dq1_oe),
			.dqs1_t     (phy_dqs1_t),
			.dqs1_c     (phy_dqs1_c),
			.dqs1_oe    (phy_dqs1_oe),
			.dm1        (phy_dm1),
			.dram_wr_valid1(dram_wr_valid1),
			.dram_wr_data1 (dram_wr_data1),
			.dram_wr_mask1 (dram_wr_mask1),
			.dram_rd_valid1(dram_rd_valid1),
			.dram_rd_data1 (dram_rd_data1)
		);


		assign dram_if.ck_t    = {phy_ck1_t, phy_ck0_t};
		assign dram_if.ck_c    = {phy_ck1_c, phy_ck0_c};
		assign dram_if.ca      = {phy_ca1, phy_ca0};
		assign dram_if.cai     = {phy_cai1, phy_cai0};
		assign dram_reset_n_pin = ctrl_rst_n & phy_reset0_n & phy_reset1_n;
		initial dram_cs_init_done = 1'b0;
		always @(negedge dram_reset_n_pin) dram_cs_init_done = 1'b0;
		always @(posedge dram_reset_n_pin) begin
			dram_cs_init_done = 1'b0;
			#25ns;
			dram_cs_init_done = 1'b1;
		end

		assign dram_if.cs_n    = dram_cs_init_done ? {phy_cs1_n, phy_cs0_n} : 2'b00;
		assign dram_if.cke     = phy_cke0 | phy_cke1;
		assign dram_if.reset_n = dram_reset_n_pin;
		assign dram_if.odt     = 1'b0;
		assign dram_if.dch     = dch;

		// Single-master channel presentation:
		// CH0 write drives lower 32b data and marks the inactive upper half with all 1s.
		// CH1 write drives upper 32b data and marks the inactive lower half with all 1s.
		assign #(dram_tck) dram_if.dq[31:0]   = phy_dq0_oe ? phy_dq0_out :
		                            phy_dq1_oe ? 32'hFFFF_FFFF : 32'bz;
		assign #(dram_tck) dram_if.dq[63:32]  = phy_dq1_oe ? phy_dq1_out :
		                            phy_dq0_oe ? 32'hFFFF_FFFF : 32'bz;
		assign #(dram_tck/2) dram_if.dqs_t[3:0] = phy_dqs0_oe ? phy_dqs0_t  : 4'bz;
		assign #(dram_tck/2) dram_if.dqs_c[3:0] = phy_dqs0_oe ? phy_dqs0_c  : 4'bz;
		assign #(dram_tck/2) dram_if.dqs_t[7:4] = phy_dqs1_oe ? phy_dqs1_t  : 4'bz;
		assign #(dram_tck/2) dram_if.dqs_c[7:4] = phy_dqs1_oe ? phy_dqs1_c  : 4'bz;
		assign #(dram_tck)   dram_if.dmi[3:0]   = phy_dq0_oe  ? phy_dm0     : 4'bz;
		assign #(dram_tck)   dram_if.dmi[7:4]   = phy_dq1_oe  ? phy_dm1     : 4'bz;

		assign phy_dq0_in = dram_if.dq[31:0];
		assign phy_dq1_in = dram_if.dq[63:32];

endmodule : phy_top 

