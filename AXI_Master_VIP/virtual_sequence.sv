//-----------------------------------------------------------------------------
// File Name    : virtual_sequence.sv
// Project      : DDR3 Controller Subsystem verification using AXI3
// Engineer     : amith
// Created Date : 2025-05-15
// Updated Date : 2025-11-17
//
// Description  : Virtual sequences for multi-agent coordination
//
// Features     : - Virtual sequences for all test scenarios
//                - Uses virtual sequencer (top_sequencer)
//                - Coordinates PCIe and Config agents
//
//-----------------------------------------------------------------------------

//=============================================================================
// BASE VIRTUAL SEQUENCE
//=============================================================================
class base_virtual_sequence extends uvm_sequence#(axi_tx);
    `uvm_object_utils(base_virtual_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    // Declare p_sequencer as top_sequencer type
    `uvm_declare_p_sequencer(top_sequencer)
    
endclass


//Bringup testcase 
class vseq_single_write_aligned_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_single_write_aligned_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    single_write_with_64_bytes_aligned seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass




class vseq_single_write_narrow_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_single_write_narrow_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    single_write_with_narrow_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass



class vseq_single_write_read_aligned_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_single_write_read_aligned_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    single_wr_rd_64_bytes_data_aligned seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


class vseq_single_write_read_narrow_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_single_write_read_narrow_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    single_wr_rd_with_narrow_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass



class vseq_multiple_write_read_aligned_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_multiple_write_read_aligned_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    multiple_wr_rd_with_aligned_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass



class vseq_multiple_write_read_narrow_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_multiple_write_read_narrow_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    multiple_wr_rd_with_narrow_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass

//Functionality Testcases 
class vseq_single_wr_rd_diffrent_locations_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_single_wr_rd_diffrent_locations_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    single_wr_rd_diffrent_addr seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


class vseq_multiple_wr_rd_same_addr_back_to_back_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_multiple_wr_rd_same_addr_back_to_back_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    multiple_wr_rd_same_addr_back_to_back_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass



class vseq_multiple_wr_rd_BA_CA_RA_sequence_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_multiple_wr_rd_BA_CA_RA_sequence_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    multiple_wr_rd_BA_CA_RA_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


class vseq_precharge_single_bank_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_precharge_single_bank_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    precharge_single_bank_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


class vseq_precharge_all_bank_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_precharge_all_bank_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    precharge_all_bank_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass



class multiple_wr_rd_addr_boundry_v_sequence extends base_virtual_sequence;
    `uvm_object_utils(multiple_wr_rd_addr_boundry_v_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    multiple_wr_rd_with_addr_boundry_sequence seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


class vseq_buschop8_sequence extends base_virtual_sequence;
    `uvm_object_utils(vseq_buschop8_sequence)

    function new(string name="");
        super.new(name);
    endfunction

    buschop8_sequence seq;

    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting BUSCHOP8 / BC8 write-read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed BUSCHOP8 / BC8 write-read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass















/*
//=============================================================================
// PCIe VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Multiple Write Same Address
//-----------------------------------------------------------------------------
class vseq_pcie_multi_wr_same extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_multi_wr_same)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_multi_write_same_addr seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Multiple Write Same Address", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Multiple Write Same Address", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Multiple Write Different Addresses
//-----------------------------------------------------------------------------
class vseq_pcie_multi_wr_diff extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_multi_wr_diff)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_multi_write_diff_addr seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Multiple Write Different Addresses", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Multiple Write Different Addresses", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Multiple Read Same Address
//-----------------------------------------------------------------------------
class vseq_pcie_multi_rd_same extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_multi_rd_same)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_multi_read_same_addr seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Multiple Read Same Address", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Multiple Read Same Address", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Multiple Read Different Addresses
//-----------------------------------------------------------------------------
class vseq_pcie_multi_rd_diff extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_multi_rd_diff)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_multi_read_diff_addr seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Multiple Read Different Addresses", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Multiple Read Different Addresses", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Back-to-Back Write-Read
//-----------------------------------------------------------------------------
class vseq_pcie_back2back extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_back2back)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_back2back_wr_rd seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Back-to-Back Write-Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Burst Length Variation
//-----------------------------------------------------------------------------
class vseq_pcie_burst_var extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_burst_var)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_burst_length_variation seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Burst Length Variation", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Burst Length Variation", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Random Write
//-----------------------------------------------------------------------------
class vseq_pcie_random_wr extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_random_wr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_random_write seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Random Write", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Random Write", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Random Read
//-----------------------------------------------------------------------------
class vseq_pcie_random_rd extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_random_rd)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_random_read seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Random Read", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Random Read", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Random Mixed Write/Read
//-----------------------------------------------------------------------------
class vseq_pcie_random_mix extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_random_mix)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_random_wr_rd_mix seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Random Mixed W/R", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Random Mixed W/R", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: PCIe Sequential Write-Read
//-----------------------------------------------------------------------------
class vseq_pcie_sequential extends base_virtual_sequence;
    `uvm_object_utils(vseq_pcie_sequential)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    pcie_sequential_wr_rd seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting PCIe Sequential W/R", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed PCIe Sequential W/R", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// DDR BANK TARGETING VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Different Banks
//-----------------------------------------------------------------------------
class vseq_ddr_diff_banks extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_diff_banks)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_target_different_banks seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Different Banks", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Different Banks", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Interleaved Bank Access
//-----------------------------------------------------------------------------
class vseq_ddr_interleaved_banks extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_interleaved_banks)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_interleaved_bank_access seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Interleaved Banks", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Interleaved Banks", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// DDR COLUMN TARGETING VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Different Columns
//-----------------------------------------------------------------------------
class vseq_ddr_diff_columns extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_diff_columns)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_target_different_columns seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Different Columns", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Different Columns", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Sequential Column Burst
//-----------------------------------------------------------------------------
class vseq_ddr_seq_column extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_seq_column)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_sequential_column_burst seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Sequential Column Burst", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Sequential Column Burst", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// DDR ROW TARGETING VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Different Rows
//-----------------------------------------------------------------------------
class vseq_ddr_diff_rows extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_diff_rows)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_target_different_rows seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Different Rows", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Different Rows", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Row Hit/Miss Pattern
//-----------------------------------------------------------------------------
class vseq_ddr_row_hit_miss extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_row_hit_miss)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_row_hit_miss_pattern seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Row Hit/Miss Pattern", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Row Hit/Miss Pattern", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// RANDOM ACCESS VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Random Row/Column/Bank Access
//-----------------------------------------------------------------------------
class vseq_ddr_random_rcb extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_random_rcb)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_random_rcb_access seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Random RCB Access", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Random RCB Access", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// OUTSTANDING TRANSACTION VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: Outstanding Writes
//-----------------------------------------------------------------------------
class vseq_outstanding_wr extends base_virtual_sequence;
    `uvm_object_utils(vseq_outstanding_wr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    outstanding_writes seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting Outstanding Writes (16 transactions)", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed Outstanding Writes", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: Outstanding Reads
//-----------------------------------------------------------------------------
class vseq_outstanding_rd extends base_virtual_sequence;
    `uvm_object_utils(vseq_outstanding_rd)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    outstanding_reads seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting Outstanding Reads (16 transactions)", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed Outstanding Reads", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: Outstanding Mixed Write/Read
//-----------------------------------------------------------------------------
class vseq_outstanding_mix extends base_virtual_sequence;
    `uvm_object_utils(vseq_outstanding_mix)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    outstanding_mixed_wr_rd seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting Outstanding Mixed W/R", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed Outstanding Mixed W/R", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: Outstanding Stress Test
//-----------------------------------------------------------------------------
class vseq_outstanding_stress extends base_virtual_sequence;
    `uvm_object_utils(vseq_outstanding_stress)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    outstanding_stress_test seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting Outstanding Stress Test (50 transactions)", UVM_MEDIUM)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed Outstanding Stress Test", UVM_MEDIUM)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// PERFORMANCE VIRTUAL SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Write Performance
//-----------------------------------------------------------------------------
class vseq_ddr_write_perf extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_write_perf)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_write_performance seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Write Performance Test", UVM_LOW)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Write Performance Test", UVM_LOW)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Read Performance
//-----------------------------------------------------------------------------
class vseq_ddr_read_perf extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_read_perf)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_read_performance seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Read Performance Test", UVM_LOW)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Read Performance Test", UVM_LOW)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Mixed Performance
//-----------------------------------------------------------------------------
class vseq_ddr_mixed_perf extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_mixed_perf)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_mixed_performance seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Mixed Performance Test", UVM_LOW)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Mixed Performance Test", UVM_LOW)
        starting_phase.drop_objection(this);
    endtask
endclass


//-----------------------------------------------------------------------------
// Virtual Sequence: DDR Sustained Bandwidth
//-----------------------------------------------------------------------------
class vseq_ddr_bandwidth extends base_virtual_sequence;
    `uvm_object_utils(vseq_ddr_bandwidth)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    ddr_sustained_bandwidth seq;
    
    task body();
        starting_phase.raise_objection(this);
        `uvm_info("VSEQ", "Starting DDR Sustained Bandwidth Test", UVM_LOW)
        `uvm_do_on(seq, p_sequencer.psqr)
        `uvm_info("VSEQ", "Completed DDR Sustained Bandwidth Test", UVM_LOW)
        starting_phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// COMPREHENSIVE REGRESSION VIRTUAL SEQUENCE
//=============================================================================

//-----------------------------------------------------------------------------
// Virtual Sequence: Full Regression Suite
//-----------------------------------------------------------------------------
class vseq_full_regression extends base_virtual_sequence;
    `uvm_object_utils(vseq_full_regression)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    // PCIe sequences
    pcie_multi_write_same_addr      pcie_seq1;
    pcie_random_wr_rd_mix           pcie_seq2;
    
    // DDR sequences
    ddr_target_different_banks      ddr_seq1;
    ddr_target_different_rows       ddr_seq2;
    ddr_random_rcb_access           ddr_seq3;
    
    // Outstanding sequences
    outstanding_stress_test         out_seq;
    
    // Performance sequences
    ddr_mixed_performance           perf_seq;
    
    task body();
        starting_phase.raise_objection(this);
        
        `uvm_info("VSEQ", "========================================", UVM_LOW)
        `uvm_info("VSEQ", "Starting Full Regression Test Suite", UVM_LOW)
        `uvm_info("VSEQ", "========================================", UVM_LOW)
        
        // Run PCIe tests
        `uvm_info("VSEQ", "Phase 1: PCIe Tests", UVM_LOW)
        `uvm_do_on(pcie_seq1, p_sequencer.psqr)
        #1000;
        
        `uvm_do_on(pcie_seq2, p_sequencer.psqr)
        #3000;
        
        // Run DDR tests
        `uvm_info("VSEQ", "Phase 2: DDR Targeting Tests", UVM_LOW)
        `uvm_do_on(ddr_seq1, p_sequencer.psqr)
        #3000;
        
        `uvm_do_on(ddr_seq2, p_sequencer.psqr)
        #3000;
        
        `uvm_do_on(ddr_seq3, p_sequencer.psqr)
        #5000;
        
        // Run Outstanding tests
        `uvm_info("VSEQ", "Phase 3: Outstanding Transaction Tests", UVM_LOW)
        `uvm_do_on(out_seq, p_sequencer.psqr)
        #10000;
        
        // Run Performance tests
        `uvm_info("VSEQ", "Phase 4: Performance Tests", UVM_LOW)
        `uvm_do_on(perf_seq, p_sequencer.psqr)
        #20000;
        
        `uvm_info("VSEQ", "========================================", UVM_LOW)
        `uvm_info("VSEQ", "Full Regression Test Completed", UVM_LOW)
        `uvm_info("VSEQ", "========================================", UVM_LOW)
        
        starting_phase.drop_objection(this);
    endtask
endclass


*/
