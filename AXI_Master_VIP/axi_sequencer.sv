//-----------------------------------------------------------------------------
// File Name    : axi_sequencer.sv
// Project      : DDR3 Controller Subsystem verfication using AXI3
// Engineer     : amith

// Created Date : 2025-05-15
//
// Description  : Implementation of the axi_sequencer module
//
// Features     : - Utility tasks/functions

//
// Dependencies : None
//
// Revision History:
// -----------------------------------------------------------------------
// Rev  | Date       | Author         | Description
// -----------------------------------------------------------------------
// 0.1  | 2025-05-15 | amith    | Initial draft
// -----------------------------------------------------------------------
//-----------------------------------------------------------------------------
class axi_pcie_sequencer extends uvm_sequencer#(axi_tx);
    `uvm_component_utils(axi_pcie_sequencer)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

endclass




















class axi_cfg_sequencer extends uvm_sequencer#(axi_tx);
    `uvm_component_utils(axi_cfg_sequencer)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

endclass
