//-----------------------------------------------------------------------------
// File Name    : axi_test.sv
// Project      : DDR3 Controller Subsystem verification using AXI3
// Engineer     : amith
// Created Date : 2025-05-15
// Updated Date : 2025-11-17
//
// Description  : Comprehensive test suite for AXI sequences
//
// Features     : - Base test
//                - PCIe tests
//                - DDR targeting tests
//                - Outstanding transaction tests
//                - Performance tests
//
//-----------------------------------------------------------------------------

//=============================================================================
// BASE TEST CLASS
//=============================================================================
class axi_test extends uvm_test;
    `uvm_component_utils(axi_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    axi_pcie_env penv;
    axi_cfg_env  cenv; 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        penv = axi_pcie_env::type_id::create("penv", this);
        cenv = axi_cfg_env::type_id::create("cenv", this);
    endfunction

endclass

class base_vseq_test extends axi_test;
    `uvm_component_utils(base_vseq_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 
    
    // Virtual sequencer
    top_sequencer sqr;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = top_sequencer::type_id::create("sqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect virtual sequencer to real sequencers
        sqr.csqr = cenv.ag.sqr;
        sqr.psqr = penv.agent.sqr;
    endfunction

    task main_phase(uvm_phase phase);
        uvm_objection objection;
        super.main_phase(phase);
        objection = phase.get_objection();
        objection.set_drain_time(this, 10000ns);
    endtask
endclass

//SINGLE WRITE TESTCASE
class pcie_single_write_aligned_test extends base_vseq_test;
    `uvm_component_utils(pcie_single_write_aligned_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_single_write_aligned_sequence::type_id::get());
    endfunction
endclass



class pcie_single_write_narrow_test extends base_vseq_test;
    `uvm_component_utils(pcie_single_write_narrow_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_single_write_narrow_sequence::type_id::get());
    endfunction
endclass



class pcie_single_write_read_aligned_test extends base_vseq_test;
    `uvm_component_utils(pcie_single_write_read_aligned_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_single_write_read_aligned_sequence::type_id::get());
    endfunction
endclass


class pcie_single_write_read_narrow_test extends base_vseq_test;
    `uvm_component_utils(pcie_single_write_read_narrow_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_single_write_read_narrow_sequence::type_id::get());
    endfunction
endclass



class pcie_multiple_write_read_aligned_test extends base_vseq_test;
    `uvm_component_utils(pcie_multiple_write_read_aligned_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_multiple_write_read_aligned_sequence::type_id::get());
    endfunction
endclass


class pcie_multiple_write_read_narrow_test extends base_vseq_test;
    `uvm_component_utils(pcie_multiple_write_read_narrow_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_multiple_write_read_narrow_sequence::type_id::get());
    endfunction
endclass

//Functionality Testcase 

class pcie_single_wr_rd_diffrent_addr_test extends base_vseq_test;
    `uvm_component_utils(pcie_single_wr_rd_diffrent_addr_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_single_wr_rd_diffrent_locations_sequence::type_id::get());
    endfunction
endclass



class pcie_multiple_wr_rd_same_addr_back_to_back_test extends base_vseq_test;
    `uvm_component_utils(pcie_multiple_wr_rd_same_addr_back_to_back_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_multiple_wr_rd_same_addr_back_to_back_sequence::type_id::get());
    endfunction
endclass


class pcie_multiple_wr_rd_BA_CA_RA_sequence_test extends base_vseq_test;
    `uvm_component_utils(pcie_multiple_wr_rd_BA_CA_RA_sequence_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_multiple_wr_rd_BA_CA_RA_sequence_sequence::type_id::get());
    endfunction
endclass


class pcie_precharge_single_bank_test extends base_vseq_test;
    `uvm_component_utils(pcie_precharge_single_bank_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_precharge_single_bank_sequence::type_id::get());
    endfunction
endclass

class pcie_precharge_all_bank_test extends base_vseq_test;
    `uvm_component_utils(pcie_precharge_all_bank_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_precharge_all_bank_sequence::type_id::get());
    endfunction
endclass

class multiple_wr_rd_address_boundry_test extends base_vseq_test;
    `uvm_component_utils(multiple_wr_rd_address_boundry_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", multiple_wr_rd_addr_boundry_v_sequence::type_id::get());
    endfunction
endclass


class pcie_buschop8_test extends base_vseq_test;
    `uvm_component_utils(pcie_buschop8_test)

    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase",
            "default_sequence", vseq_buschop8_sequence::type_id::get());
    endfunction
endclass


/*

//=============================================================================
// VIRTUAL SEQUENCER TEST (Base for complex tests)
//=============================================================================
class top_test extends base_vseq_test;
    `uvm_component_utils(top_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Set default virtual sequence
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", top_sequence::type_id::get());
    endfunction
endclass


//=============================================================================
// PCIe BASIC TESTS
//=============================================================================
//-----------------------------------------------------------------------------
// Test: PCIe Multiple Write Same Address
//-----------------------------------------------------------------------------
class pcie_multi_wr_same_test extends base_vseq_test;
    `uvm_component_utils(pcie_multi_wr_same_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_multi_wr_same::type_id::get());
    endfunction
endclass

//-----------------------------------------------------------------------------
// Test: PCIe Multiple Write Different Addresses
//-----------------------------------------------------------------------------
class pcie_multi_wr_diff_test extends base_vseq_test;
    `uvm_component_utils(pcie_multi_wr_diff_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_multi_wr_diff::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Multiple Read Same Address
//-----------------------------------------------------------------------------
class pcie_multi_rd_same_test extends base_vseq_test;
    `uvm_component_utils(pcie_multi_rd_same_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_multi_rd_same::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Multiple Read Different Addresses
//-----------------------------------------------------------------------------
class pcie_multi_rd_diff_test extends base_vseq_test;
    `uvm_component_utils(pcie_multi_rd_diff_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_multi_rd_diff::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Back-to-Back Write-Read
//-----------------------------------------------------------------------------
class pcie_back2back_test extends base_vseq_test;
    `uvm_component_utils(pcie_back2back_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_back2back::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Burst Length Variation
//-----------------------------------------------------------------------------
class pcie_burst_var_test extends base_vseq_test;
    `uvm_component_utils(pcie_burst_var_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_burst_var::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Random Write
//-----------------------------------------------------------------------------
class pcie_random_wr_test extends base_vseq_test;
    `uvm_component_utils(pcie_random_wr_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_random_wr::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Random Read
//-----------------------------------------------------------------------------
class pcie_random_rd_test extends base_vseq_test;
    `uvm_component_utils(pcie_random_rd_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_random_rd::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Random Mixed Write/Read
//-----------------------------------------------------------------------------
class pcie_random_mix_test extends base_vseq_test;
    `uvm_component_utils(pcie_random_mix_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_random_mix::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: PCIe Sequential Write-Read
//-----------------------------------------------------------------------------
class pcie_sequential_test extends base_vseq_test;
    `uvm_component_utils(pcie_sequential_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_pcie_sequential::type_id::get());
    endfunction
endclass


//=============================================================================
// DDR BANK TARGETING TESTS
//=============================================================================

//-----------------------------------------------------------------------------
// Test: DDR Different Banks
//-----------------------------------------------------------------------------
class ddr_diff_banks_test extends base_vseq_test;
    `uvm_component_utils(ddr_diff_banks_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_diff_banks::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: DDR Interleaved Bank Access
//-----------------------------------------------------------------------------
class ddr_interleaved_banks_test extends base_vseq_test;
    `uvm_component_utils(ddr_interleaved_banks_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_interleaved_banks::type_id::get());
    endfunction
endclass


//=============================================================================
// DDR COLUMN TARGETING TESTS
//=============================================================================

//-----------------------------------------------------------------------------
// Test: DDR Different Columns
//-----------------------------------------------------------------------------
class ddr_diff_columns_test extends base_vseq_test;
    `uvm_component_utils(ddr_diff_columns_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_diff_columns::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: DDR Sequential Column Burst
//-----------------------------------------------------------------------------
class ddr_seq_column_test extends base_vseq_test;
    `uvm_component_utils(ddr_seq_column_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_seq_column::type_id::get());
    endfunction
endclass


//=============================================================================
// DDR ROW TARGETING TESTS
//=============================================================================

//-----------------------------------------------------------------------------
// Test: DDR Different Rows
//-----------------------------------------------------------------------------
class ddr_diff_rows_test extends base_vseq_test;
    `uvm_component_utils(ddr_diff_rows_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_diff_rows::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: DDR Row Hit/Miss Pattern
//-----------------------------------------------------------------------------
class ddr_row_hit_miss_test extends base_vseq_test;
    `uvm_component_utils(ddr_row_hit_miss_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_row_hit_miss::type_id::get());
    endfunction
endclass


//=============================================================================
// RANDOM ACCESS TESTS
//=============================================================================

//-----------------------------------------------------------------------------
// Test: DDR Random Row/Column/Bank Access
//-----------------------------------------------------------------------------
class ddr_random_rcb_test extends base_vseq_test;
    `uvm_component_utils(ddr_random_rcb_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_random_rcb::type_id::get());
    endfunction
endclass


//=============================================================================
// OUTSTANDING TRANSACTION TESTS
//=============================================================================

//-----------------------------------------------------------------------------
// Test: Outstanding Writes (16 transactions)
//-----------------------------------------------------------------------------
class outstanding_wr_test extends base_vseq_test;
    `uvm_component_utils(outstanding_wr_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_outstanding_wr::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: Outstanding Reads (16 transactions)
//-----------------------------------------------------------------------------
class outstanding_rd_test extends base_vseq_test;
    `uvm_component_utils(outstanding_rd_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_outstanding_rd::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: Outstanding Mixed Write/Read
//-----------------------------------------------------------------------------
class outstanding_mix_test extends base_vseq_test;
    `uvm_component_utils(outstanding_mix_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_outstanding_mix::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: Outstanding Stress Test
//-----------------------------------------------------------------------------
class outstanding_stress_test_case extends base_vseq_test;
    `uvm_component_utils(outstanding_stress_test_case)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_outstanding_stress::type_id::get());
    endfunction
endclass


//=============================================================================
// PERFORMANCE TESTS
//=============================================================================

//-----------------------------------------------------------------------------
// Test: DDR Write Performance
//-----------------------------------------------------------------------------
class ddr_write_perf_test extends base_vseq_test;
    `uvm_component_utils(ddr_write_perf_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_write_perf::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: DDR Read Performance
//-----------------------------------------------------------------------------
class ddr_read_perf_test extends base_vseq_test;
    `uvm_component_utils(ddr_read_perf_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_read_perf::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: DDR Mixed Read/Write Performance
//-----------------------------------------------------------------------------
class ddr_mixed_perf_test extends base_vseq_test;
    `uvm_component_utils(ddr_mixed_perf_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_mixed_perf::type_id::get());
    endfunction
endclass


//-----------------------------------------------------------------------------
// Test: DDR Sustained Bandwidth
//-----------------------------------------------------------------------------
class ddr_bandwidth_test extends base_vseq_test;
    `uvm_component_utils(ddr_bandwidth_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_ddr_bandwidth::type_id::get());
    endfunction
endclass


//=============================================================================
// COMPREHENSIVE REGRESSION TEST
//=============================================================================

//-----------------------------------------------------------------------------
// Test: Full Regression Suite
//-----------------------------------------------------------------------------
class full_regression_test extends base_vseq_test;
    `uvm_component_utils(full_regression_test)
    
    function new(string name="", uvm_component parent=null);
        super.new(name, parent);
    endfunction 

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_object_wrapper)::set(this, "sqr.main_phase", 
            "default_sequence", vseq_full_regression::type_id::get());
    endfunction
endclass


//=============================================================================
// NOTES
//=============================================================================
/*
 * All tests follow the virtual sequencer approach:
 *   - Extend from base_vseq_test
 *   - Use config_db to set default_sequence in build_phase
 *   - Virtual sequences handle objection management
 *   - Automatic connection to real sequencers via connect_phase
 *   - Consistent drain_time management in main_phase
 *
 * Benefits:
 *   - Clean, consistent test structure
 *   - Easy to add new tests
 *   - Automatic objection handling
 *   - Multi-agent coordination support
 *   - No manual sequence start/stop required
 */
