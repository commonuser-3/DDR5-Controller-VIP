
//include multiple sequencers 
class top_sequencer extends uvm_sequencer#(axi_tx);
	`uvm_component_utils(top_sequencer);
	function new(string name="", uvm_component parent=null);
		super.new(name,parent);
	endfunction 
	//we need to include all 3 sequencers 
	axi_cfg_sequencer csqr;
	axi_pcie_sequencer psqr;

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		psqr=axi_pcie_sequencer::type_id::create("psqr",this);
		csqr=axi_cfg_sequencer::type_id::create("csqr",this);
	endfunction 
endclass


