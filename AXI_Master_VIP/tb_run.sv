//-----------------------------------------------------------------------------
// File Name    : run.sv
// Project      : DDR3 Controller Subsystem verification using AXI3
// Engineer     : amith
// Created Date : 2025-11-09
//
// Description  : Main compilation file
//-----------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"

//=============================================================================
// IMPORTANT: Include files in correct dependency order
//=============================================================================

// 1. Transaction class (needed by monitor and other components)
`include "axi_tx.sv"

// 2. Monitor file (contains all monitor classes)
`include "axi_monitor.sv"

// 3. Scoreboard (MUST include analysis imp declarations FIRST)
`include "scoreboard.sv"

// 4. Sequence components
`include "axi_sequence.sv"
`include "axi_sequencer.sv"

// 5. Driver
`include "axi_driver.sv"

// 6. Virtual components
`include "virtual_sequencer.sv"
`include "virtual_sequence.sv"

// 7. Agent (uses monitors and driver)
`include "axi_agent.sv"

// 8. Environment (uses agent and scoreboard)
`include "env.sv"

// 9. Test
`include "axi_test.sv"

// 10. Testbench top
`include "axi_tb_top.sv"
