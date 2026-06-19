// =============================================================
// ddr5_axi_frontend.sv
// AXI4 Slave Front-End
//================================================================

`timescale 1ns/1ps

import ddr5_pkg::*;

module axi_slave1_module #(
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter STRB_WIDTH = 64,
    parameter MEM_SIZE   = 10000
)(
    input  logic                        clk,
    input  logic                        rst_n,
    
    // ---- AXI3 Slave port ------------------------------------
    // Write address channel
    input  logic                        s_awvalid,
    output logic                        s_awready,
    input  logic [31:0]                 s_awaddr,
    input  logic [3:0]                  s_awid,
    input  logic [3:0]                  s_awlen,
    input  logic [2:0]                   s_awsize,
    input  logic [1:0]                   s_awburst,
    // Write data channel
    input  logic                        s_wvalid,
    output logic                        s_wready,
    input  logic [AXI_DATA_W-1:0]       s_wdata,
    input  logic [AXI_STRB_W-1:0]       s_wstrb,
    input  logic                        s_wlast,
    input  logic [3:0]                  s_wid,
    // Write response channel
    output logic                        s_bvalid,
    input  logic                        s_bready,
    output logic [3:0]                  s_bid,
    output logic [1:0]                   s_bresp,
    // Read address channel
    input  logic                        s_arvalid,
    output logic                        s_arready,
    input  logic [31:0]                 s_araddr,
    input  logic [3:0]                  s_arid,
    input  logic [3:0]                  s_arlen,
    input  logic [2:0]                   s_arsize,
    input  logic [1:0]                   s_arburst,
    // Read data channel
    output logic                        s_rvalid,
    input  logic                        s_rready,
    output logic [AXI_DATA_W-1:0]       s_rdata,
    output logic [3:0]                  s_rid,
    output logic [1:0]                   s_rresp,
    output logic                        s_rlast,
  
    // ---- To sub-channel demux / scheduler -------------------
    output logic                        req_valid,
    input  logic                        req_ready,
    output logic                        req_is_wr,
    output logic [AXI_ADDR_W-1:0]       req_addr,
    output logic [AXI_DATA_W-1:0]       req_wdata,
    output logic [AXI_STRB_W-1:0]       req_wstrb,
    output logic [AXI_ID_W-1:0]         req_id,
  
    // ---- From data-path (read data return) ------------------
    input  logic                        rd_data_valid,
    input  logic [AXI_DATA_W-1:0]       rd_data,
    input  logic [AXI_ID_W-1:0]         rd_id_in
  );

    // Local byte-addressable memory (for AXI compliance monitoring)
    reg [7:0] mem [MEM_SIZE];

    //Addtional signals from DDR5 AXI frontend
    logic                   aw_held;
    logic [AXI_ADDR_W-1:0]  aw_addr_r;
    logic [3:0]             aw_id_r;
    logic [3:0]             aw_len_r;
    logic [2:0]             wr_beat_cnt;
    logic                   wr_req_pending;
    logic [AXI_DATA_W-1:0]  wr_data_packed;
    logic [AXI_STRB_W-1:0]  wr_strb_packed;

    // Write burst accumulation buffers.
    // Sized for 16 beats: AXI awlen max = 15 → two DDR3 BL8 transactions.
    // Old size [0:7] caused out-of-bounds writes for beats 8..15 to silently
    // discard the data; the Write() loop then read 'x for those slots and the
    // second DDR3 transaction received garbage instead of AXI beats 8-15.
    logic [DATA_WIDTH-1:0]  burst_data [0:15];   // was [0:7] — fixed for 16-beat burst
    logic [STRB_WIDTH-1:0]  burst_strb [0:15];   // was [0:7] — fixed for 16-beat burst

    // Write transaction info (indexed by AXI transaction ID)
    typedef struct {
        logic [ADDR_WIDTH-1:0] awaddr;
        logic [3:0]            awlen;
        logic [2:0]            awsize;
        logic [1:0]            awburst;
        logic [3:0]            awid;
    } wr_tx_t;
    wr_tx_t wr_tx [0:(2**ID_WIDTH)-1];
    logic   wr_tx_valid [0:(2**ID_WIDTH)-1];

    // Read result buffer (512-bit from DDR3 ReadBurst)
    logic [BL8_DQ_BITS-1:0] rd_512;

    // Misc
    int beat_idx;
    int byte_idx;


    // -----------------------------------------------------------
  // Read path
  // -----------------------------------------------------------
  logic                   ar_held;
  logic [AXI_ADDR_W-1:0]  ar_addr_r;
  logic [3:0]             ar_id_r;
  logic [3:0]             ar_len_r;
  logic [3:0]             b_id_r;
  logic                   b_pending;
  logic [AXI_DATA_W-1:0]  r_data_r;
  logic [3:0]             r_id_r;
  logic [3:0]             r_len_r;
  logic [2:0]             r_beat_cnt;
  logic                   r_pending;

  
    // Initialise
    initial begin
        for (int i = 0; i < 2**ID_WIDTH; i++) wr_tx_valid[i] = 0;
        for (int i = 0; i < MEM_SIZE;       i++) mem[i]       = 0;
    end
    

    // -----------------------------------------------------------
    // Request mux: write first, then read (simple priority)
    // -----------------------------------------------------------
    logic wr_pending, rd_pending;
    assign wr_pending = wr_req_pending;
    assign rd_pending = ar_held;


    //AW acceptance

    always_comb begin
        req_valid  = 1'b0;
        req_is_wr  = 1'b0;
        req_addr   = '0;
        req_wdata  = '0;
        req_wstrb  = '0;
        req_id     = '0;

        if (wr_pending) begin
            req_valid  = 1'b1;
            req_is_wr  = 1'b1;
            req_addr   = aw_addr_r;
            req_wdata  = wr_data_packed;
            req_wstrb  = wr_strb_packed;
            req_id     = {{(AXI_ID_W-4){1'b0}}, aw_id_r};
        end else if (rd_pending) begin
            req_valid  = 1'b1;
            req_is_wr  = 1'b0;
            req_addr   = ar_addr_r;
            req_id     = {{(AXI_ID_W-4){1'b0}}, ar_id_r};
        end
    end

    // ================================================================
    // MAIN AXI SLAVE LOGIC
    // ================================================================
    always @(posedge clk) begin

        // ---- RESET ------------------------------------------------
        if (!rst_n) begin
            s_awready <= 'x;
	    s_wready  <= 'x;
	    s_bvalid  <= 'x;
	    s_bresp   <= 'x;
	    s_bid     <= 'x;
	    s_arready <= 'x;
	    s_rvalid  <= 'x;
	    s_rdata   <= 'x;
	    s_rlast   <= 'x;
	    s_rid     <= 'x;
	    s_rresp   <= 'x;

	    //From DDR5 Frontend
	    aw_held        <= 1'b0;
      	    aw_addr_r      <= '0;
            aw_id_r        <= '0;
            aw_len_r       <= '0;
            wr_beat_cnt    <= '0;
            wr_req_pending <= 1'b0;
            wr_data_packed <= '0;
            wr_strb_packed <= '0;

           // axi_MemController.Reset();
           for (int i = 0; i < MEM_SIZE; i++) mem[i] = 0;
           // ---- NORMAL OPERATION -------------------------------------
           end else begin
		// Default de-asserts
            	if (s_awvalid) s_awready <= 0;
            	if (s_wvalid)  s_wready  <= 0;
            	if (s_bready)  s_bvalid  <= 0;
            	if (s_arvalid) s_arready <= 0;
            	if (s_rready)  s_rvalid  <= 0;

            // ===========================================================
            // 1. WRITE ADDRESS CHANNEL
            // ===========================================================
            if (s_awvalid) begin
                s_awready <= 1'b1;
                wr_tx[s_awid].awaddr  = s_awaddr;
                wr_tx[s_awid].awlen   = s_awlen;
                wr_tx[s_awid].awsize  = s_awsize;
                wr_tx[s_awid].awburst = s_awburst;
                wr_tx[s_awid].awid    = s_awid;
                wr_tx_valid[s_awid]   = 1;

		//AW acceptance from DDR5 AXI frontend
		if(s_awready) begin
			aw_held    <= 1'b1;
        		aw_addr_r  <= s_awaddr;
     			aw_id_r    <= s_awid;
       	 		aw_len_r   <= s_awlen;
        		wr_beat_cnt <= '0;
        		wr_data_packed <= '0;
        		wr_strb_packed <= '0;
            end
            end

            // ===========================================================
            // 2. WRITE DATA CHANNEL
            //    Collect all beats, then issue one DDR3 BL8 transaction.
            // ===========================================================
            if (s_wvalid && wr_tx_valid[s_wid]) begin
                s_wready <= 1;

                // Full 512-bit write payload (64-bit strobe) arrives in this beat.
                // Pack it once and forward it to the sub-channel demux.
                wr_data_packed <= s_wdata;
                wr_strb_packed <= s_wstrb;
                wr_req_pending <= 1'b1;
                aw_held        <= 1'b0;

                // Preserve the original byte-lane logging for debug visibility.
                for (int j = 0; j < AXI_STRB_W; j++) begin
                    if (s_wstrb[j]) begin
                        mem[wr_tx[s_wid].awaddr + j] = s_wdata[j*8 +: 8];
                    end
                end

                // The broad AXI write transaction is now ready to be consumed by the demux.
                if (req_valid && req_ready && req_is_wr) begin
                    wr_req_pending <= 1'b0;
                end

                // W acceptance remains asserted while the write payload is pending.
                s_wready = aw_held && !wr_req_pending;

		//------------------------------------------------------
		//Old Logic used to transaction to the axi_MemController
		//---------------------------------------------------------
		//Untill this point we recieved all transfers data from AXI 
		//Now send this wdat other controll information to the DDR5 
		//sub channel demux 
               /* begin
                    automatic int total = int'(wr_tx[axi_if.wid].awlen) + 1;
                    automatic logic [ADDR_WIDTH-1:0] base = wr_tx[axi_if.wid].awaddr;
                    for (int b = 0; b < total; b++) begin
                        // Write(addr, data, burst_len, dm)
                        // dm = ~wstrb: strb=1 → write byte, strb=0 → mask
			$display("WRITE METHOD CLASSES INSIDE SLAVE");
                        axi_MemController.Write(
                            base,
                            burst_data[b],
                            4'(total),
                            ~burst_strb[b]
                        );
                        $display("[AXI1]   beat %0d data=0x%h dm=0x%h",
                                 b, burst_data[b], ~burst_strb[b]);
                    end
                end
*/
                // ---- write response ----
                @(posedge clk);
		
                if (s_bready) begin
                    s_bvalid <= 1;
                    s_bid    <= s_wid;
                    s_bresp  <= 2'b00;
                    $display("[AXI1] BRESP OK ID=%0d", s_wid);
	        end
                wr_tx_valid[s_wid] = 0;
		$display("[AXI DDR5 FE] Recived 512 bits of data from AXI is %0h",wr_data_packed);
            end

            // ===========================================================
            // 3. READ ADDRESS CHANNEL + READ DATA CHANNEL
            //    One DDR3 BL8 read, return arlen+1 beats on R channel.
            // ===========================================================
            if (s_arvalid) begin
                s_arready <= 1;

		if(s_arready) begin
			ar_held   <= 1'b1;
        		ar_addr_r <= s_araddr;
        		ar_id_r   <= s_arid;
        		ar_len_r  <= s_arlen;
		end
		else if(ar_held && req_valid && req_ready &&! req_is_wr) begin
			ar_held <= 1'b0;
		end

                // ---- return read data from local byte-addressable memory ----
                begin
                    automatic int  total_rd = int'(s_arlen) + 1;
                    automatic logic [ADDR_WIDTH-1:0] rd_base = s_araddr;
                    automatic logic [DATA_WIDTH-1:0] rd_beat;
                    automatic int unsigned byte_addr;
                    $display("[AXI1] RD ADDR: ID=%0d addr=0x%h len=%0d → 1 BL8",
                             s_arid, rd_base, s_arlen);

                    // ---- return beats on R channel ----
		    // Simple logic of read address channel to return the data
		    // fromthe local memory
                    @(posedge clk);
                    for (int b = 0; b < total_rd; b++) begin
                        rd_beat = '0;
                        for (int j = 0; j < DATA_WIDTH/8; j++) begin
                            byte_addr = rd_base + (b << s_arsize) + j;
                            if (byte_addr < MEM_SIZE) begin
                                rd_beat[j*8 +: 8] = mem[byte_addr];
                            end
                        end

                        wait (s_rready);
                        @(posedge clk);
                        s_rvalid <= 1;
                        s_rid    <= s_arid;
                        s_rdata  <= rd_beat;
			rd_512   <= rd_beat;
                        s_rresp  <= 2'b00;
                        s_rlast  <= (b == total_rd - 1);
                        $display("[AXI1] RD BEAT %0d data=0x%h rlast=%0d",
                                 b, rd_beat,
                                 (b == total_rd - 1));
                        @(posedge clk);
                    end
                    s_rvalid <= 0;
                    s_rlast  <= 0;
                end
            end

        end // else normal
    end // always

    always_ff @(posedge clk) begin
    if (rst_n) begin
      if (s_awvalid && s_awready) begin
        $display("[DDR5 AXI FE][AW_ACCEPT] t=%0t awaddr=%0h awid=%0h awlen=%0h awsize=%0h awburst=%0h",
                 $time, s_awaddr, s_awid, s_awlen, s_awsize, s_awburst);
      end
      if (s_wvalid && s_wready) begin
        $display("[DDR5 AXI FE][W_ACCEPT] t=%0t beat=%0d wdata=%0h wstrb=%0h wlast=%0b",
                 $time, wr_beat_cnt, s_wdata, s_wstrb, s_wlast);
      end
      if (req_valid && req_ready && req_is_wr) begin
        $display("[DDR5 AXI FE][WRITE_REQ_SENT] t=%0t req_addr=%0h req_id=%0h req_wdata=%0h req_wstrb=%0h",
                 $time, req_addr, req_id, req_wdata, req_wstrb);
      end
      if (s_bvalid && s_bready) begin
        $display("[DDR5 AXI FE][B_ACCEPT] t=%0t bid=%0h bresp=%0h",
                 $time, s_bid, s_bresp);
      end
      if (s_arvalid && s_arready) begin
        $display("[DDR5 AXI FE][AR_ACCEPT] t=%0t araddr=%0h arid=%0h arlen=%0h arsize=%0h arburst=%0h",
                 $time, s_araddr, s_arid, s_arlen, s_arsize, s_arburst);
      end
      if (req_valid && req_ready && !req_is_wr) begin
        $display("[DDR5 AXI FE][READ_REQ_SENT] t=%0t req_addr=%0h req_id=%0h",
                 $time, req_addr, req_id);
      end
      if (rd_data_valid && !r_pending) begin
        $display("[DDR5 AXI FE][RDATA_RECEIVED] t=%0t rd_id_in=%0h rd_data=%0h",
                 $time, rd_id_in, rd_data);
      end
      if (s_rvalid && s_rready) begin
        $display("[DDR5 AXI FE][R_ACCEPT] t=%0t beat=%0d rid=%0h rdata=%0h rresp=%0h rlast=%0b",
                 $time, r_beat_cnt, s_rid, s_rdata, s_rresp, s_rlast);
      end
    end
  end


endmodule

module ddr5_axi_frontend_clean (
  input  logic                        clk,
  input  logic                        rst_n,

  input  logic                        s_awvalid,
  output logic                        s_awready,
  input  logic [31:0]                 s_awaddr,
  input  logic [3:0]                  s_awid,
  input  logic [3:0]                  s_awlen,
  input  logic [2:0]                  s_awsize,
  input  logic [1:0]                  s_awburst,
  input  logic                        s_wvalid,
  output logic                        s_wready,
  input  logic [AXI_DATA_W-1:0]       s_wdata,
  input  logic [AXI_STRB_W-1:0]       s_wstrb,
  input  logic                        s_wlast,
  input  logic [3:0]                  s_wid,
  output logic                        s_bvalid,
  input  logic                        s_bready,
  output logic [3:0]                  s_bid,
  output logic [1:0]                  s_bresp,
  input  logic                        s_arvalid,
  output logic                        s_arready,
  input  logic [31:0]                 s_araddr,
  input  logic [3:0]                  s_arid,
  input  logic [3:0]                  s_arlen,
  input  logic [2:0]                  s_arsize,
  input  logic [1:0]                  s_arburst,
  output logic                        s_rvalid,
  input  logic                        s_rready,
  output logic [AXI_DATA_W-1:0]       s_rdata,
  output logic [3:0]                  s_rid,
  output logic [1:0]                  s_rresp,
  output logic                        s_rlast,

  output logic                        req_valid,
  input  logic                        req_ready,
  output logic                        req_is_wr,
  output logic [AXI_ADDR_W-1:0]       req_addr,
  output logic [AXI_DATA_W-1:0]       req_wdata,
  output logic [AXI_STRB_W-1:0]       req_wstrb,
  output logic [AXI_ID_W-1:0]         req_id,

  input  logic                        rd_data_valid,
  input  logic [AXI_DATA_W-1:0]       rd_data,
  input  logic [AXI_ID_W-1:0]         rd_id_in
);

  logic                  aw_hold;
  logic [AXI_ADDR_W-1:0] aw_addr_r;
  logic [3:0]            aw_id_r;
  logic                  wr_pending;
  logic [AXI_DATA_W-1:0] wr_data_r;
  logic [AXI_STRB_W-1:0] wr_strb_r;

  logic                  ar_pending;
  logic [AXI_ADDR_W-1:0] ar_addr_r;
  logic [3:0]            ar_id_r;

  assign s_awready = rst_n && !aw_hold && !wr_pending;
  assign s_wready  = rst_n && aw_hold && !wr_pending;
  assign s_arready = rst_n && !ar_pending && !s_rvalid && !wr_pending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_hold    <= 1'b0;
      aw_addr_r  <= '0;
      aw_id_r    <= '0;
      wr_pending <= 1'b0;
      wr_data_r  <= '0;
      wr_strb_r  <= '0;
      s_bvalid   <= 1'b0;
      s_bid      <= '0;
      s_bresp    <= 2'b00;
    end else begin
      if (s_awvalid && s_awready) begin
        aw_hold   <= 1'b1;
        aw_addr_r <= s_awaddr;
        aw_id_r   <= s_awid;
      end

      if (s_wvalid && s_wready) begin
        wr_pending <= 1'b1;
        wr_data_r  <= s_wdata;
        wr_strb_r  <= s_wstrb;
        aw_hold    <= 1'b0;
      end

      if (req_valid && req_ready && req_is_wr) begin
        wr_pending <= 1'b0;
        s_bvalid   <= 1'b1;
        s_bid      <= aw_id_r;
        s_bresp    <= 2'b00;
      end else if (s_bvalid && s_bready) begin
        s_bvalid <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ar_pending <= 1'b0;
      ar_addr_r  <= '0;
      ar_id_r    <= '0;
      s_rvalid   <= 1'b0;
      s_rdata    <= '0;
      s_rid      <= '0;
      s_rresp    <= 2'b00;
      s_rlast    <= 1'b0;
    end else begin
      if (s_arvalid && s_arready) begin
        ar_pending <= 1'b1;
        ar_addr_r  <= s_araddr;
        ar_id_r    <= s_arid;
      end

      if (req_valid && req_ready && !req_is_wr) begin
        ar_pending <= 1'b0;
      end

      if (rd_data_valid && !s_rvalid) begin
        s_rvalid <= 1'b1;
        s_rdata  <= rd_data;
        s_rid    <= rd_id_in[3:0];
        s_rresp  <= 2'b00;
        s_rlast  <= 1'b1;
      end else if (s_rvalid && s_rready) begin
        s_rvalid <= 1'b0;
        s_rlast  <= 1'b0;
      end
    end
  end

  always_comb begin
    req_valid = 1'b0;
    req_is_wr = 1'b0;
    req_addr  = '0;
    req_wdata = '0;
    req_wstrb = '0;
    req_id    = '0;

    if (wr_pending) begin
      req_valid = 1'b1;
      req_is_wr = 1'b1;
      req_addr  = aw_addr_r;
      req_wdata = wr_data_r;
      req_wstrb = wr_strb_r;
      req_id    = {{(AXI_ID_W-4){1'b0}}, aw_id_r};
    end else if (ar_pending) begin
      req_valid = 1'b1;
      req_is_wr = 1'b0;
      req_addr  = ar_addr_r;
      req_id    = {{(AXI_ID_W-4){1'b0}}, ar_id_r};
    end
  end

endmodule : ddr5_axi_frontend_clean

/*module axi_slave1_module #(
  parameter DATA_WIDTH = 64,
  parameter ADDR_WIDTH = 32,
  parameter ID_WIDTH   = 4,
  parameter STRB_WIDTH = 8,
  parameter MEM_SIZE   = 10000
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  s_awvalid,
  output logic                  s_awready,
  input  logic [31:0]           s_awaddr,
  input  logic [3:0]            s_awid,
  input  logic [3:0]            s_awlen,
  input  logic [2:0]            s_awsize,
  input  logic [1:0]            s_awburst,

  input  logic                  s_wvalid,
  output logic                  s_wready,
  input  logic [63:0]           s_wdata,
  input  logic [7:0]            s_wstrb,
  input  logic                  s_wlast,
  input  logic [3:0]            s_wid,

  output logic                  s_bvalid,
  input  logic                  s_bready,
  output logic [3:0]            s_bid,
  output logic [1:0]            s_bresp,

  input  logic                  s_arvalid,
  output logic                  s_arready,
  input  logic [31:0]           s_araddr,
  input  logic [3:0]            s_arid,
  input  logic [3:0]            s_arlen,
  input  logic [2:0]            s_arsize,
  input  logic [1:0]            s_arburst,

  output logic                  s_rvalid,
  input  logic                  s_rready,
  output logic [63:0]           s_rdata,
  output logic [3:0]            s_rid,
  output logic [1:0]            s_rresp,
  output logic                  s_rlast,

  output logic                  req_valid,
  input  logic                  req_ready,
  output logic                  req_is_wr,
  output logic [AXI_ADDR_W-1:0] req_addr,
  output logic [AXI_DATA_W-1:0] req_wdata,
  output logic [AXI_STRB_W-1:0] req_wstrb,
  output logic [AXI_ID_W-1:0]   req_id,

  input  logic                  rd_data_valid,
  input  logic [AXI_DATA_W-1:0] rd_data,
  input  logic [AXI_ID_W-1:0]   rd_id_in
);

  localparam int MAX_AXI_BEATS = AXI_DATA_W / DATA_WIDTH;
  localparam int BEAT_SEL_W    = (MAX_AXI_BEATS <= 1) ? 1 : $clog2(MAX_AXI_BEATS);

  logic [7:0] mem [0:MEM_SIZE-1];

  initial begin
    for (int i = 0; i < MEM_SIZE; i++) begin
      mem[i] = '0;
    end
  end

  logic [AXI_ADDR_W-1:0] aw_addr_r;
  logic [ID_WIDTH-1:0]   aw_id_r;
  logic [3:0]            aw_len_r;
  logic [2:0]            aw_size_r;
  logic [1:0]            aw_burst_r;
  logic                  aw_held;
  logic [BEAT_SEL_W-1:0] wr_beat_cnt;
  logic                  wr_req_pending;
  logic [AXI_DATA_W-1:0] wr_data_packed;
  logic [AXI_STRB_W-1:0] wr_strb_packed;
  logic [ID_WIDTH-1:0]   wr_wid_last_r;

  assign s_awready = !aw_held && !wr_req_pending;
  assign s_wready  = aw_held && !wr_req_pending;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_held        <= 1'b0;
      aw_addr_r      <= '0;
      aw_id_r        <= '0;
      aw_len_r       <= '0;
      aw_size_r      <= '0;
      aw_burst_r     <= '0;
      wr_beat_cnt    <= '0;
      wr_req_pending <= 1'b0;
      wr_data_packed <= '0;
      wr_strb_packed <= '0;
      wr_wid_last_r  <= '0;
    end else begin
      if (s_awvalid && s_awready) begin
        aw_held        <= 1'b1;
        aw_addr_r      <= s_awaddr;
        aw_id_r        <= s_awid;
        aw_len_r       <= s_awlen;
        aw_size_r      <= s_awsize;
        aw_burst_r     <= s_awburst;
        wr_beat_cnt    <= '0;
        wr_data_packed <= '0;
        wr_strb_packed <= '0;
      end

      if (s_wvalid && s_wready) begin
        wr_data_packed[wr_beat_cnt*DATA_WIDTH +: DATA_WIDTH] <= s_wdata;
        wr_strb_packed[wr_beat_cnt*STRB_WIDTH +: STRB_WIDTH] <= s_wstrb;
        wr_wid_last_r <= s_wid;

        for (int j = 0; j < STRB_WIDTH; j++) begin
          int unsigned byte_addr;
          byte_addr = aw_addr_r + (wr_beat_cnt << aw_size_r) + j;
          if (s_wstrb[j] && (byte_addr < MEM_SIZE)) begin
            mem[byte_addr] <= s_wdata[j*8 +: 8];
          end
        end

        if ((wr_beat_cnt == aw_len_r[BEAT_SEL_W-1:0]) ||
            s_wlast ||
            (wr_beat_cnt == MAX_AXI_BEATS-1)) begin
          wr_req_pending <= 1'b1;
          aw_held        <= 1'b0;
        end else begin
          wr_beat_cnt <= wr_beat_cnt + {{(BEAT_SEL_W-1){1'b0}}, 1'b1};
        end
      end

      if (wr_req_pending && req_valid && req_ready && req_is_wr) begin
        wr_req_pending <= 1'b0;
      end
    end
  end

  logic [AXI_ADDR_W-1:0] ar_addr_r;
  logic [ID_WIDTH-1:0]   ar_id_r;
  logic [3:0]            ar_len_r;
  logic [2:0]            ar_size_r;
  logic [1:0]            ar_burst_r;
  logic                  ar_held;

  assign s_arready = !ar_held;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ar_held    <= 1'b0;
      ar_addr_r  <= '0;
      ar_id_r    <= '0;
      ar_len_r   <= '0;
      ar_size_r  <= '0;
      ar_burst_r <= '0;
    end else begin
      if (s_arvalid && s_arready) begin
        ar_held    <= 1'b1;
        ar_addr_r  <= s_araddr;
        ar_id_r    <= s_arid;
        ar_len_r   <= s_arlen;
        ar_size_r  <= s_arsize;
        ar_burst_r <= s_arburst;
      end else if (ar_held && req_valid && req_ready && !req_is_wr) begin
        ar_held <= 1'b0;
      end
    end
  end

  always_comb begin
    req_valid = 1'b0;
    req_is_wr = 1'b0;
    req_addr  = '0;
    req_wdata = '0;
    req_wstrb = '0;
    req_id    = '0;

    if (wr_req_pending) begin
      req_valid = 1'b1;
      req_is_wr = 1'b1;
      req_addr  = aw_addr_r;
      req_wdata = wr_data_packed;
      req_wstrb = wr_strb_packed;
      req_id    = {{(AXI_ID_W-ID_WIDTH){1'b0}}, aw_id_r};
    end else if (ar_held) begin
      req_valid = 1'b1;
      req_is_wr = 1'b0;
      req_addr  = ar_addr_r;
      req_id    = {{(AXI_ID_W-ID_WIDTH){1'b0}}, ar_id_r};
    end
  end

  logic                b_pending;
  logic [ID_WIDTH-1:0] b_id_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_pending <= 1'b0;
      b_id_r    <= '0;
    end else begin
      if (req_valid && req_ready && req_is_wr && !b_pending) begin
        b_pending <= 1'b1;
        b_id_r    <= aw_id_r;
      end else if (s_bvalid && s_bready) begin
        b_pending <= 1'b0;
      end
    end
  end

  assign s_bvalid = b_pending;
  assign s_bid    = b_id_r;
  assign s_bresp  = 2'b00;

  logic [AXI_DATA_W-1:0] r_data_r;
  logic [ID_WIDTH-1:0]   r_id_r;
  logic [3:0]            r_len_r;
  logic [BEAT_SEL_W-1:0] r_beat_cnt;
  logic                  r_pending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_pending  <= 1'b0;
      r_data_r   <= '0;
      r_id_r     <= '0;
      r_len_r    <= '0;
      r_beat_cnt <= '0;
    end else begin
      if (rd_data_valid && !r_pending) begin
        r_pending  <= 1'b1;
        r_data_r   <= rd_data;
        r_id_r     <= rd_id_in[ID_WIDTH-1:0];
        r_len_r    <= ar_len_r;
        r_beat_cnt <= '0;
      end else if (s_rvalid && s_rready && s_rlast) begin
        r_pending <= 1'b0;
      end else if (s_rvalid && s_rready) begin
        r_beat_cnt <= r_beat_cnt + {{(BEAT_SEL_W-1){1'b0}}, 1'b1};
      end
    end
  end

  assign s_rvalid = r_pending;
  assign s_rdata  = r_data_r[r_beat_cnt*DATA_WIDTH +: DATA_WIDTH];
  assign s_rid    = r_id_r;
  assign s_rresp  = 2'b00;
  assign s_rlast  = (r_beat_cnt == r_len_r[BEAT_SEL_W-1:0]) ||
                    (r_beat_cnt == MAX_AXI_BEATS-1);

  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (s_awvalid && s_awready) begin
        $display("[AXI_SLAVE1][AW_RECEIVED] t=%0t awaddr=%0h awid=%0h awlen=%0h awsize=%0h awburst=%0h",
                 $time, s_awaddr, s_awid, s_awlen, s_awsize, s_awburst);
      end
      if (s_wvalid && s_wready) begin
        $display("[AXI_SLAVE1][W_RECEIVED] t=%0t beat=%0d wid=%0h wdata=%0h wstrb=%0h wlast=%0b",
                 $time, wr_beat_cnt, s_wid, s_wdata, s_wstrb, s_wlast);
      end
      if (req_valid && req_ready && req_is_wr) begin
        $display("[AXI_SLAVE1][WRITE_SENT_TO_DEMUX] t=%0t req_addr=%0h req_id=%0h last_wid=%0h req_wdata=%0h req_wstrb=%0h",
                 $time, req_addr, req_id, wr_wid_last_r, req_wdata, req_wstrb);
      end
      if (s_bvalid && s_bready) begin
        $display("[AXI_SLAVE1][B_SENT_TO_MASTER] t=%0t bid=%0h bresp=%0h",
                 $time, s_bid, s_bresp);
      end
      if (s_arvalid && s_arready) begin
        $display("[AXI_SLAVE1][AR_RECEIVED] t=%0t araddr=%0h arid=%0h arlen=%0h arsize=%0h arburst=%0h",
                 $time, s_araddr, s_arid, s_arlen, s_arsize, s_arburst);
      end
      if (req_valid && req_ready && !req_is_wr) begin
        $display("[AXI_SLAVE1][READ_SENT_TO_DEMUX] t=%0t req_addr=%0h req_id=%0h",
                 $time, req_addr, req_id);
      end
      if (rd_data_valid && !r_pending) begin
        $display("[AXI_SLAVE1][RDATA_RECEIVED_FROM_NEXT_BLOCK] t=%0t rd_id_in=%0h rd_data=%0h",
                 $time, rd_id_in, rd_data);
      end
      if (s_rvalid && s_rready) begin
        $display("[AXI_SLAVE1][R_SENT_TO_MASTER] t=%0t beat=%0d rid=%0h rdata=%0h rresp=%0h rlast=%0b",
                 $time, r_beat_cnt, s_rid, s_rdata, s_rresp, s_rlast);
      end
    end
  end

endmodule : axi_slave1_module*/
