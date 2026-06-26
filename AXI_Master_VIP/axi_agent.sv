class axi_pcie_agent extends uvm_agent;
    `uvm_component_utils(axi_pcie_agent)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

    axi_pcie_sequencer sqr;
    axi_pcie_master_driver drv;
    axi_master_monitor  axi_mon;
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(is_active==UVM_ACTIVE)begin
            sqr = axi_pcie_sequencer::type_id::create("sqr",this);
            drv = axi_pcie_master_driver::type_id::create("drv",this);
            //mon = base_monitor::type_id::create("mon",this);
           
        end
        axi_mon = axi_master_monitor::type_id::create("axi_mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

class axi_cfg_agent extends uvm_agent;
    `uvm_component_utils(axi_cfg_agent)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

    axi_cfg_sequencer sqr;
    axi_cfg_master_driver drv;
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(is_active==UVM_ACTIVE)begin
            sqr = axi_cfg_sequencer::type_id::create("sqr",this);
            drv = axi_cfg_master_driver::type_id::create("drv",this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
