class axi_scoreboard extends uvm_scoreboard;
	`uvm_component_utils(axi_scoreboard)
	function new(string name="", uvm_component parent=null);
		super.new(name,parent);
	endfunction 
//TLM 
uvm_tlm_analysis_fifo#(axi_tx) tlm_scor;

function void build_phase(uvm_phase phase);
	super.build_phase(phase);
	tlm_scor=new("tlm_scor",this);
endfunction 

bit [7:0] expected_data[int];
bit [7:0] actual_data[int];
axi_tx tx;
axi_tx wr_tx[int];
axi_tx rd_tx[int];
bit [63:0] wr_data,rd_data;
int wdata_burst_width_in_bytes;
int pass_cnt=0;
int fail_cnt=0;
int range;
int address_remainder;
int count;
int byte_addr;
bit [7:0] exp_byte;
bit [7:0] act_byte;

task run_phase(uvm_phase phase);
	super.run_phase(phase);
	//need to get data from monitor 
	forever begin
	       tlm_scor.get(tx);//awaddr=5   awid=7   awlen=3  awsize=2
	       //wdata=32'haabbccdd  wstrb=4'b0011

	       //all signals present in axi need to store to one array 
	       if(tx.awvalid==1)begin 
		       wr_tx[tx.awid]=tx; //wr_tx[7]
	       end
	       //write data 
	         if(tx.wvalid==1 && tx.wready==1)begin 
			  if (!wr_tx.exists(tx.wid)) begin
				  `uvm_error("SCOREBOARD", $sformatf("W beat arrived for unknown WID=%0d", tx.wid))
				  continue;
			  end
			  if (tx.wdata.size() == 0) begin
				  `uvm_error("SCOREBOARD", $sformatf("W beat for WID=%0d has empty wdata queue", tx.wid))
				  continue;
			  end
			  wdata_burst_width_in_bytes = ($size(wr_data)/8); //128
			  
                                    count=0;
				    wr_data=tx.wdata.pop_back();
                                    for(int i=0; i<wdata_burst_width_in_bytes; i++)begin
                                      if(tx.wstrb[i]==1)begin 
                                        expected_data[wr_tx[tx.wid].awaddr+count]=wr_data[i*8 +:8];
                                        count=count+1;               
				    end
			            end
                     wr_tx[tx.wid].awaddr= wr_tx[tx.wid].awaddr - (wr_tx[tx.wid].awaddr % 2**wr_tx[tx.wid].awsize); 
                     wr_tx[tx.wid].awaddr= wr_tx[tx.wid].awaddr + 2**wr_tx[tx.wid].awsize;
	          end
		 //read address
		 if(tx.arvalid==1)begin 
			rd_tx[tx.arid]=tx;
		 end
		 //read data 
		 if(tx.rvalid==1 && tx.rready==1)begin
		  if (!rd_tx.exists(tx.rid)) begin
			  `uvm_error("SCOREBOARD", $sformatf("R beat arrived for unknown RID=%0d rdata=%h", tx.rid, tx.rdata))
			  fail_cnt=fail_cnt+1;
			  continue;
		  end
		  rd_data=tx.rdata;	 
                  address_remainder = (rd_tx[tx.rid].araddr % (2**rd_tx[tx.rid].arsize)); 
	          range = (2**rd_tx[tx.rid].arsize) - address_remainder;
                  count=0;
                  for(int i=0; i< range; i++)begin 
                  byte_addr = rd_tx[tx.rid].araddr + count;
                  actual_data[byte_addr]=rd_data[i*8 +:8];//reading from memeory//mem[1000] mem[1001] 
		  if(!expected_data.exists(byte_addr))begin
			  `uvm_error("SCOREBOARD", $sformatf("Read address %0h has no expected write data; actual=%02h rid=%0d", byte_addr, actual_data[byte_addr], tx.rid))
			  fail_cnt=fail_cnt+1;
		  end
		  else begin
		  exp_byte = expected_data[byte_addr];
		  act_byte = actual_data[byte_addr];
		  if(exp_byte == act_byte)begin 
			  $display("SCOREBOARD PASS address=%h expected_data=%h actual_data=%h",byte_addr, exp_byte, act_byte);
			  pass_cnt=pass_cnt+1;
		  end
		  else begin
			  $display("SCOREBOARD FAIL address=%h expected_data=%h actual_data=%h",byte_addr, exp_byte, act_byte);
                        fail_cnt=fail_cnt+1;
		end
		end
                  count=count+1;
                  end  
                  rd_tx[tx.rid].araddr= rd_tx[tx.rid].araddr - (rd_tx[tx.rid].araddr % 2**rd_tx[tx.rid].arsize);//0
                 rd_tx[tx.rid].araddr= rd_tx[tx.rid].araddr + 2**rd_tx[tx.rid].arsize;//4
		 $display("pass_cnt=%d fail_cnt=%d", pass_cnt, fail_cnt);
		 end
	end//forver
endtask
endclass 
