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

  logic wr_req_ch0;
  logic wr_req_ch1;
  logic dqs_toggle_ch0;
  logic dqs_toggle_ch1;
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

  always_ff @(posedge dram_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      ck0_t <= 1'b0;
      ck0_c <= 1'b1;
      ck1_t <= 1'b0;
      ck1_c <= 1'b1;
    end else if (clk_enable) begin
      ck0_t <= ~ck0_t;
      ck0_c <= ~ck0_c;
      ck1_t <= ~ck1_t;
      ck1_c <= ~ck1_c;
    end else begin
      ck0_t <= 1'b0;
      ck0_c <= 1'b1;
      ck1_t <= 1'b0;
      ck1_c <= 1'b1;
    end
  end

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
      ca0      <= 14'h3fff;
      cs0_n    <= 1'b1;
      cke0     <= 1'b0;
      reset0_n <= 1'b0;
      ca1      <= 14'h3fff;
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

      // Present cycle-0 and cycle-1 in adjacent CA slots. The old code held
      // cycle-0 while waiting for the next CK_t rising edge, which made the
      // first command word occupy two visible slots.
      if (!ck0_t) begin
        if (ca_cmd_pending) begin
          ca0      <= ca_latch_ch0[0];
          cs0_n    <= cs_latch_ch0[0];
          ca1      <= ca_latch_ch1[0];
          cs1_n    <= cs_latch_ch1[0];
          ca_cmd_pending <= 1'b0;
          ca_cmd_second  <= 1'b1;
        end else begin
          ca0   <= 14'h3fff;
          cs0_n <= 1'b1;
          ca1   <= 14'h3fff;
          cs1_n <= 1'b1;
        end
      end else begin
        if (ca_cmd_second) begin
          ca0      <= ca_latch_ch0[2];
          cs0_n    <= cs_latch_ch0[2];
          ca1      <= ca_latch_ch1[2];
          cs1_n    <= cs_latch_ch1[2];
          ca_cmd_second <= 1'b0;
        end else begin
          ca0   <= 14'h3fff;
          cs0_n <= 1'b1;
          ca1   <= 14'h3fff;
          cs1_n <= 1'b1;
        end
      end
    end
  end

  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if (!ctrl_rst_n) begin
      dq0_out        <= '0;
      dq0_oe         <= 1'b0;
      dqs0_t         <= '0;
      dqs0_c         <= '1;
      dqs0_oe        <= 1'b0;
      dm0            <= '0;
      dqs_toggle_ch0 <= 1'b0;

      dq1_out        <= '0;
      dq1_oe         <= 1'b0;
      dqs1_t         <= '0;
      dqs1_c         <= '1;
      dqs1_oe        <= 1'b0;
      dm1            <= '0;
      dqs_toggle_ch1 <= 1'b0;
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
      if (wr_req_ch0 && !wr_active_ch0) begin
        wr_latch_ch0   <= wr_pack_ch0;
        dm_latch_ch0   <= dm_pack_ch0;
        wr_active_ch0  <= 1'b1;
        wr_idx_ch0     <= 5'd1;
        dq0_out        <= wr_pack_ch0[31:0];
        dm0            <= dm_pack_ch0[3:0];
        dq0_oe         <= 1'b1;
        dqs0_oe        <= 1'b1;
        dqs_toggle_ch0 <= ~dqs_toggle_ch0;
        dqs0_t         <= {4{dqs_toggle_ch0}};
        dqs0_c         <= {4{~dqs_toggle_ch0}};
      end else if (wr_active_ch0) begin
        dq0_out        <= wr_latch_ch0[wr_idx_ch0*32 +: 32];
        dm0            <= dm_latch_ch0[wr_idx_ch0*4 +: 4];
        dq0_oe         <= 1'b1;
        dqs0_oe        <= 1'b1;
        dqs_toggle_ch0 <= ~dqs_toggle_ch0;
        dqs0_t         <= {4{dqs_toggle_ch0}};
        dqs0_c         <= {4{~dqs_toggle_ch0}};
        if (wr_idx_ch0 == 5'd15) begin
          wr_active_ch0 <= 1'b0;
          wr_idx_ch0    <= '0;
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

      if (wr_req_ch1 && !wr_active_ch1) begin
        wr_latch_ch1   <= wr_pack_ch1;
        dm_latch_ch1   <= dm_pack_ch1;
        wr_active_ch1  <= 1'b1;
        wr_idx_ch1     <= 5'd1;
        dq1_out        <= wr_pack_ch1[31:0];
        dm1            <= dm_pack_ch1[3:0];
        dq1_oe         <= 1'b1;
        dqs1_oe        <= 1'b1;
        dqs_toggle_ch1 <= ~dqs_toggle_ch1;
        dqs1_t         <= {4{dqs_toggle_ch1}};
        dqs1_c         <= {4{~dqs_toggle_ch1}};
      end else if (wr_active_ch1) begin
        dq1_out        <= wr_latch_ch1[wr_idx_ch1*32 +: 32];
        dm1            <= dm_latch_ch1[wr_idx_ch1*4 +: 4];
        dq1_oe         <= 1'b1;
        dqs1_oe        <= 1'b1;
        dqs_toggle_ch1 <= ~dqs_toggle_ch1;
        dqs1_t         <= {4{dqs_toggle_ch1}};
        dqs1_c         <= {4{~dqs_toggle_ch1}};
        if (wr_idx_ch1 == 5'd15) begin
          wr_active_ch1 <= 1'b0;
          wr_idx_ch1    <= '0;
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
