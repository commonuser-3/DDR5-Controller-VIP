class axi_master_monitor extends uvm_monitor;
		`uvm_component_utils(axi_master_monitor)
	function new(string name="", uvm_component parent=null);
		super.new(name,parent);
	endfunction
    //get pointed virtual interface from top module 
    virtual axi_pcie_intf#(64,32,4,8,10000,4) m_vif;
    //TLM 
    uvm_analysis_port#(axi_tx)  tlm_mon;
    function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual axi_pcie_intf#(64,32,4,8,10000,4))::get(this,"","pvif",m_vif))
			`uvm_fatal("NOVIF", "axi_master_monitor: virtual AXI interface not found")
		tlm_mon=new("tlm_mon",this);
    endfunction 

    axi_tx tx;
    
    //will every clock cycle all signals from interface then will sedn to
    //scoreboard and coverage block 
     task run_phase(uvm_phase phase);
	     super.run_phase(phase);
	     forever begin 
		     @(negedge m_vif.aclk);//signals statble 
		     tx=axi_tx::type_id::create("tx",this);
		     //write address channel
		     tx.awaddr=m_vif.awaddr;
		     tx.awid=m_vif.awid;
		     tx.awvalid=m_vif.awvalid;
		     tx.awready=m_vif.awready;
		     tx.awlen=m_vif.awlen;
		     tx.awsize=m_vif.awsize;
		     tx.awlock=m_vif.awlock;
		     tx.awprot=m_vif.awprot;
		     tx.awburst=m_vif.awburst;
		     tx.awcache=m_vif.awcache;
		     //write data 
		     tx.wdata.push_back(m_vif.wdata);
		     tx.wvalid = m_vif.wvalid;
		     tx.wready = m_vif.wready;
		     tx.wid = m_vif.wid;
		     tx.wstrb = m_vif.wstrb;
		     tx.wlast = m_vif.wlast;
		     //write response 
		     tx.bid=m_vif.bid;
		     tx.bvalid=m_vif.bvalid;
		     tx.bready=m_vif.bready;
		     tx.bresp=m_vif.bresp;
		     //read address
		     tx.araddr=m_vif.araddr;
		     tx.arid=m_vif.arid;
		     tx.arvalid=m_vif.arvalid;
		     tx.arready=m_vif.arready;
		     tx.arlen=m_vif.arlen;
		     tx.arsize=m_vif.arsize;
		     tx.arlock=m_vif.arlock;
		     tx.arprot=m_vif.arprot;
		     tx.arburst=m_vif.arburst;
		     tx.arcache=m_vif.arcache;
		     //read data channel 
		     tx.rdata=m_vif.rdata;
		     tx.rvalid=m_vif.rvalid;
		     tx.rready=m_vif.rready;
		     tx.rid=m_vif.rid;
		     tx.rresp=m_vif.rresp;
		     tx.rlast=m_vif.rlast;
		     //send tx to scoereboard or coverage 
		     tlm_mon.write(tx);
	     end        
     endtask
endclass

//will do all logic 
