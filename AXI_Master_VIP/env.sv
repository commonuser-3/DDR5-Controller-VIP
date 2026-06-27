class axi_pcie_env extends uvm_env;
    `uvm_component_utils(axi_pcie_env)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

    axi_pcie_agent agent;
    axi_scoreboard sco;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axi_pcie_agent::type_id::create("agent",this);
        sco = axi_scoreboard::type_id::create("sco",this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.axi_mon.tlm_mon.connect(sco.tlm_scor.analysis_export);
endfunction 
endclass

class axi_cfg_env extends uvm_env;
    `uvm_component_utils(axi_cfg_env)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

    axi_cfg_agent ag;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ag = axi_cfg_agent::type_id::create("ag",this);
    endfunction

endclass
