//-----------------------------------------------------------------------------
// File Name    : axi_tx.sv
// Project      : DDR3 Controller Subsystem verfication using AXI3
// Engineer     : amith

// Created Date : 2025-05-15
//
// Description  : Implementation of the axi_tx module
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

typedef enum  { WRITE_ONLY, READ_ONLY, WRITE_THEN_READ, WRITE_PARALEL_READ } write_read;
typedef enum {
    WRITE_ADDR,
    WRITE_DATA,
    WRITE_RESP,
    READ_ADDR,
    READ_DATA
} axi_trans_type_e;

class axi_tx extends uvm_sequence_item;
    `uvm_object_utils(axi_tx)
    function new(string name="");
        super.new(name);
    endfunction

    rand write_read wr_rd; 
    time timestamp;
    axi_trans_type_e trans_type;
    //write address channel
    rand bit[31:0] awaddr;
    rand bit[3:0] awid;
    rand bit[3:0] awlen;
    rand bit awvalid;
    rand bit[2:0]awsize;
    rand bit[1:0]awburst;
    rand bit[3:0]awcache;
    rand bit[2:0]awprot;
    rand bit[1:0]awlock;
    bit awready;

    //write data channel
    rand bit[63:0] wdata[$];
    rand bit[7:0] wstrb;
    rand bit wlast;
    rand bit[3:0] wid;
    rand bit wvalid;
    rand bit wready;

    //write response channel
    rand bit bready;
    rand bit bvalid;
    rand bit[1:0]bresp;
    rand bit[3:0]bid; 

    //read address channel
    rand bit [31:0]araddr;
    rand bit[3:0]arid;
    rand bit[3:0]arlen;
    rand bit[2:0]arsize;
    rand bit[1:0]arburst;
    rand bit[3:0]arcache;
    rand bit[2:0]arprot;
    rand bit[1:0]arlock;
    rand bit arvalid;
    bit arready;

    //read response channel
    bit [63:0]rdata;
    rand bit rready;
    bit rvalid;
    bit [3:0]rid;
    bit rlast;
    bit [1:0]rresp;


    constraint c1{
        wdata.size() == awlen +1;  //wdata is a queue the size of this queue should be len+1
        awaddr[1:0]==2'b00; // 
	araddr[1:0]==2'b00;

        //two masters 0-1000 targetting the config slave   1000-2000 targetting the PCIe slave 
        //write aawddr=1 , read araddr=1   write awaddr=1   read aradddr=3
        soft araddr == awaddr;
        //4kb address boundry constraint implementation
       // awaddr = (awaddr % 4096) + ((awlen+1) *(2**awsize)-1) <= 4096;
        
       // awaddr % (2**awsize) ==0; //only send the alinged address 

	//(araddr%(2**arsize)) == 'd0;

    
    } 

endclass

// class mem_tx extends uvm_sequence_item;
//     `uvm_object_utils(mem_tx)
//     function new(string name="")begin
//         super.new(name);
//     end

//     rand logic   rst_n;                         //Reset Signal
//     rand logic   ck;                            // complement of CPU Clock
//     rand logic   ck_n;                          //CPU Clock (90 degree phase shifted singnal of ck)
//     rand logic   cke;                           //Clock_enable from MemController to Memory
//     rand logic   cs_n;                          //Chip Select Signal
//     rand logic   ras_n;                         //RAS Signal row to column signal
//     rand logic   cas_n;                         //CAS Signal column to data delay signal
//     rand logic   we_n;                          //Write or read enable signal
//     rand tri     [1-1:0]   dm_tdqs;
//     rand logic   [BA_BITS-1:0]   ba;            // bank Bits 
//     rand logic   [ADDR_BITS-1:0] addr;          //MAX Address Bits for the address bus
//     rand tri     [DQ_BITS-1:0]   dq;              //data bits from/to memory controller form memory or CPU
//     rand tri     [1-1:0]  dqs;                    //data strobe signal
//     rand tri     [1-1:0]  dqs_n;                  //Checks if data is valid and assigned to complement of Cpu clock
//     rand logic   [1-1:0] tdqs_n;                //terminating Data strobe signal
//     rand logic   odt;                            //on-die terminating Signal
    

// endclass
