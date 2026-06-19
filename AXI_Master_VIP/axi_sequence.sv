//-----------------------------------------------------------------------------
// File Name    : axi_sequence.sv
// Project      : DDR3 & DDR4 & DDR5 Controller Subsystem verfication using AXI3
// Created Date : 2026-04-15
//
// Description  : Implementation of the axi_sequence module
//
// Features     : - Utility tasks/functions 
//
// Dependencies : None
//
// Revision History:
// -----------------------------------------------------------------------
// Rev  | Date       | Author         | Description
// -----------------------------------------------------------------------
// 0.1  | 2026-04-15 | ELOBCHIP    | Initial draft
// -----------------------------------------------------------------------
//-----------------------------------------------------------------------------
class axi_sequence extends uvm_sequence#(axi_tx);
    `uvm_object_utils(axi_sequence)
    function new(string name="");
        super.new(name);
    endfunction

endclass



//-----------------------------------------------------------------------------
// WRITE ONLY TRANSACTION WITH 512bit of data 64byte aligned request
// Description of TEST:
// We are mainly sending from axi 8 beats of data by setting awlen=7, addr any
// random aligned address, aligned with awsize =3  ex awaddr=0,8,16 
// then inside DRAM interface checking all 64 bytes of data properly visisble
// in all edges of dqs also we are analysisng DM all 8 edges always 0 or not.
//
//Organization: ELOBCHIP 
//-----------------------------------------------------------------------------
class single_write_with_64_bytes_aligned extends axi_sequence;
    `uvm_object_utils(single_write_with_64_bytes_aligned)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 0; //aligned address    add% 2^awsize=0 
            awlen == 7; // 8 beats of data in each transaction, each beat 64 bit totaly 64 bytes of data in each transaction 
            awsize == 3;//8 bytes of data in each beat
            awburst == 1;//INCR
            wid == wr_tx.awid;//random values awid will update same id to wid 
        });
        `uvm_send(wr_tx);
     
    endtask
endclass



//--------------------------------------------------------------------------------------------------------
//TESTCSE2:
//WRITE ONLY TRANSACTION WITH NARROW TRANSFERS
//TESTCASE Description:
//We are Mainly sending from axi less than 8 beats of data by using awlen.
//We are checking DM signal properly working in dram interface.
//We are expecting some edges DM moving to 1 (Masking the data)
//
//
//Organization: ELOBCHIP 
//---------------------------------------------------------------------------------------------------------

class single_write_with_narrow_sequence extends axi_sequence;
    `uvm_object_utils(single_write_with_narrow_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 0; //aligned address    add% 2^awsize=0 
            awlen < 7; // less than 8 beats of data in each transaction, each beat 64 bit totaly less than 64 bytes of data in each transaction 
            awsize == 3;//8 bytes of data in each beat
            awburst == 1;//INCR
            wid == wr_tx.awid;//random values awid will update same id to wid 
        });
        `uvm_send(wr_tx);
     
    endtask
endclass

//-------------------------------------------------------------------------------------------------------------------------------------------
//TESTCASE3 
//WRITE AND READ ONLY TRANSACTION 64 byte aligned request
//TESTCASE DESCRIPTION:
//We are genreting single write and read request from AXI.
//Setting both awlen & arlen is 7 means 8 beats of data (64 bytes of data).
//Awsize and arsize is 3 and awburst and arburst INCR.
//W.r.t write data in dq is equals to read data in dq, we need to check by using scoreboard.
//
//Organization: ELOBCHIP
//-------------------------------------------------------------------------------------------------------------------------------------------

class single_wr_rd_64_bytes_data_aligned extends axi_sequence;
    `uvm_object_utils(single_wr_rd_64_bytes_data_aligned)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 32'hA5C3_ADB8; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 32'hA5C3_ADB8;              
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);
/*
	 `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 16; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 0;
            awsize == 6;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 16;              
            arlen == 0;
            arsize == 6;
            arburst == 1;
        });
        `uvm_send(rd_tx);

	*/

    endtask
endclass


//----------------------------------------------------------------------------------------------------------------------------------------------
//Testcase4:
//WRITE AND READ with NARROW TRANSFER
////Testcase Description:
//"We are genreting single write and read request from AXI.
//Setting both awlen & arlen less than 7 means less than 8 beats of data (64 bytes of data).
//Awsize and arsize is 3 and awburst and arburst INCR.
//W.r.t write data in dq is equals to read data in dq, we need to check by using scoreboard."
//
//Organization: ELOBCHIP
//------------------------------------------------------------------------------------------------------------------------------------------

class single_wr_rd_with_narrow_sequence extends axi_sequence;
    `uvm_object_utils(single_wr_rd_with_narrow_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
       axi_tx tx[$]; 
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
           // awaddr == 'haaf7ef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen < 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
       tx.push_back(wr_tx);


        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == tx[0].awaddr;              //precharge all bank 
            arlen == tx[0].awlen;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);


    endtask
endclass


//---------------------------------------------------------------------------------------------------------------
//TESTCASE- 5
//MULTIPLE WRITE AND READ 64 bytes aligned request 
//
//Testcase Description:
//"We are genreting Multiple write request and Multiple read request from AXI.
//We are analysisng all write and read working fine in dram interface.
//All write and read cases INCR transaction, Awsize is 3, awlen=7"
//
//Orgnazization : ELOBCHIP
//
//----------------------------------------------------------------------------------------------------------------

class multiple_wr_rd_with_aligned_sequence extends axi_sequence;
    `uvm_object_utils(multiple_wr_rd_with_aligned_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'haaf7ef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

         
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'haaf7ef;               
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

	 `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);



  `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'habcdef;              
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);


    endtask
endclass

//--------------------------------------------------------------------------------------------------------
//TESTCASE- 6
//MULTIPLE WRITE AND READ narrow request 
//
//Testcase Description:
//"We are genreting Multiple write request and Multiple read request from AXI.
//We are analysisng all write and read working fine in dram interface.
//All write and read cases INCR transaction, Awsize is 3, awlen<7"
//
//Orgnazization : ELOBCHIP
//
//----------------------------------------------------------------------------------------------------------------

class multiple_wr_rd_with_narrow_sequence extends axi_sequence;
    `uvm_object_utils(multiple_wr_rd_with_narrow_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
         axi_tx tx[$]; 

        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'haaf7ef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen < 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
	  tx.push_back(wr_tx);

 `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'haaf7ef;              //precharge all bank 
            arlen == tx[0].awlen;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);




  `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen < 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
	  tx.push_back(wr_tx);

        
         `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'habcdef;              //precharge all bank 
            arlen == tx[1].awlen;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);


    endtask
endclass


//FUNCTIONALITY TESTCASES 

//-----------------------------------------------------------------------------------------------------------------------------------------


//------------------------------------------------------------------------------------------------------------------------
//TESTCASE7:
//WRITE at one location and READ at different location
//Description:
//AXI write time setting one address and read time setting diffrent address 
//
//Organization : ELOBCHIP
//
//-------------------------------------------------------------------------------------------------------------------------

class single_wr_rd_diffrent_addr extends axi_sequence;
    `uvm_object_utils(single_wr_rd_diffrent_addr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'haaf7ef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 0;              
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass


//---------------------------------------------------------------------------------------------------------------
//TESTCASE8
//Same address back to back write and read transaction 
//Description:
//"Mainly we are checking Memory overridng cocnept working correct or wrong 
//firstsending write transaction address='habcdef   data=;h1122334455667788 like this 8 beats of data avilable
//Second also sending write transaction address='habcdef data='haabbccddeeff1100 like these 8 beats of data avilable
//first read at same address='habcdef   we will get insted of getting this data  'h1122334455667788  we will get 'haabbccddeeff1100 becuse second write override to first write due to same address.

//Second read also with same address we will get 'haabbccddeeff1100 only."
//
//Orgnaization: ELOBCHIP
//----------------------------------------------------------------------------------------------------------------


class multiple_wr_rd_same_addr_back_to_back_sequence extends axi_sequence;
    `uvm_object_utils(multiple_wr_rd_same_addr_back_to_back_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

  `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'habcdef;              //precharge all bank 
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);
    endtask
endclass


//------------------------------------------------------------------------------------------------------------------------------------------
//TESTCASE9:
//Bank address functionality testcase, Row address functionality testcse
//, Culomn address functionality testcases 
//
//Description:
//"We are verifing BANK address properly our controller IP mapping to dram.
//Write time sending BA=0 and read time sending BA=5 but remaining CA and RA mentioned same for both write and read transaction. 

//Read data not genrated due to BA address missmatch.

//same way need to verify RA and CA -> We are not creating any specific testcases in same testcase only we can check by setting awaddr and araddr 

//Awaddr[2:0] -> BA
//Awaddr[16:3] -> RA
//Awaddr[26:17] -> CA

//"
//Organization: ELOBCHIP
//
//----------------------------------------------------------------------------------------------------------------------------------------

class multiple_wr_rd_BA_CA_RA_sequence extends axi_sequence;
    `uvm_object_utils(multiple_wr_rd_BA_CA_RA_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // BA Address check write and read AWADDR[2:0] Write time 11
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // awaddr[2:0] = BA    awaddr[16:3]=RA awaddr[26:17]=CA
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'habcde8;        //BA=000 
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);


    //RA mapping checking , BA and CA we maitaine same but only RA address
    //will chnage 
  `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // awaddr[16:3] = RA  = 1_1100_1101_1110_1  
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'habffff;        //RA= 1_1111_1111_1111_1  BA and CA same 
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);


 //CA check 
     
   `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'habcdef; // ca=     0000_1010_101
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'hffcdef;        //ca = 0000_1111_111
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass



//----------------------------------------------------------------------------------
//TESTCASE 10:
//Precharge Single bank 
/*"We need to send Write request, our controller need to start,
Activate ---> Write    ---> Prechrage 
From axi what value we are setting at write address that will deside BA at precharge time.
We need to check after precharge again need to send a request to open a row in same write address (Same bank ), this time our memeory module not proviving any error or violations messages then this operation working fine. 

If Memory module sending any error messages then need to debug and fix the issues (We devloped one negetive testcse to check this bevhiour that testcase present corner testlist)

 
We need to send Write request, our controller need to start,
Activate ---> Write    ---> Prechrage 
AXI AWADDR 27th bit will deside either our request Precharge single bank or precharge all bank 

Awaddr[27]=0  precharge single bank
Awaddr[27]=1 prechrage all bank 

From axi what value we are setting at write address that will deside BA at precharge time.
We need to check after precharge again need to send a request to open a row in same write address (Same bank ), this time our memeory module not proviving any error or violations messages then this operation working fine. 

If Memory module sending any error messages then need to debug and fix the issues (We devloped one negetive testcse to check this bevhiour that testcase present corner testlist)"*/
//
// WITHOUT a precharge if we are requesting again to open a row in same as previous request bank MEmory Module will
// send below error 
//
//  $error("%m: at time %t ERROR: ACTIVATE to already-open bank %0d.", $time, bank);
//in this way we need to conclude single bank precharge properly working or
//not 
//Organization: ELOBCHIP
//---------------------------------------------------------------------------------

class precharge_single_bank_sequence extends axi_sequence;
    `uvm_object_utils(precharge_single_bank_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
       
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'h7aaf7ef; //awaddr[27]=0  precharge single bank 
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            
            wr_rd == READ_ONLY;
            araddr == 'h7aaf7ef;              //araddr[27]=0  
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass


//------------------------------------------------------------------------------------------
//TESTCASE 11
//Precharge all bank sequence 
//Description:
//"We need to send Write request, our controller need to start,
//Activate ---> Write    ---> Prechrage all bank 

//AXI AWADDR 27th bit will deside either our request Precharge single bank or precharge all bank 

//Awaddr[27]=0  precharge single bank
//Awaddr[27]=1 prechrage all bank 
//No need to set any BA becuse it will precharge all banks .
//"
//
//Organization: ELOBCHIP
//--------------------------------------------------------------------------------------------------

class precharge_all_bank_sequence extends axi_sequence;
    `uvm_object_utils(precharge_all_bank_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
       
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'hfaaf7ef; //awaddr[27]=0  precharge single bank 
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            
            wr_rd == READ_ONLY;
            araddr == 'hfaaf7ef;              //araddr[27]=0  
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass



//------------------------------------------------------------------------------------------
//TESTCASE 12
//Write and read with autoprecharge 
//"
//
//Organization: ELOBCHIP
//--------------------------------------------------------------------------------------------------

class write_read_with_autoprecharge_sequence extends axi_sequence;
    `uvm_object_utils(write_read_with_autoprecharge_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
       
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'hfaaf7ef; //awaddr[27]=1  
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            
            wr_rd == READ_ONLY;
            araddr == 'hfaaf7ef;         
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass


//------------
//TESTCASE 13
//Write and read without autoprecharge 
//"
//
//Organization: ELOBCHIP
//--------------------------------------------------------------------------------------------------

class write_read_without_autoprecharge_sequence extends axi_sequence;
    `uvm_object_utils(write_read_without_autoprecharge_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
       
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'h7aaf7ef; //awaddr[27]=1  
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            
            wr_rd == READ_ONLY;
            araddr == 'h7aaf7ef;         
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass

//---------------------------------------





//------------------------------------------------------------------------------------------
//TESTCASE 11
//Precharge all bank sequence 
//Description:
//"We need to send Write request, our controller need to start,
//Activate ---> Write    ---> Prechrage all bank 

//AXI AWADDR 27th bit will deside either our request Precharge single bank or precharge all bank 

//Awaddr[27]=0  precharge single bank
//Awaddr[27]=1 prechrage all bank 
//No need to set any BA becuse it will precharge all banks .
//"
//
//Organization: ELOBCHIP
//--------------------------------------------------------------------------------------------------

class precharge_all_bank_sequence_one extends axi_sequence;
    `uvm_object_utils(precharge_all_bank_sequence_one)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
       
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'hfaaf7ef; //awaddr[27]=1  precharge single bank 
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);

	
        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            
            wr_rd == READ_ONLY;
            araddr == 'hfaaf7ef;              //araddr[27]=1 
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

    endtask
endclass


//-------------------------------------------------------------------------------------------------------------------------------------------


//--------------------------------------------------------------------------------------------------------
//TESTCASE- 13
//MULTIPLE WRITE AND READ address boundry testcase  
//
//Testcase Description:
//
//Orgnazization : ELOBCHIP
//
//----------------------------------------------------------------------------------------------------------------

class multiple_wr_rd_with_addr_boundry_sequence extends axi_sequence;
    `uvm_object_utils(multiple_wr_rd_with_addr_boundry_sequence)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
         axi_tx tx[$]; 

	 for(int i=0; i<=1024; i++)begin 
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY; 
            awlen == 7;  
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);
	  tx.push_back(wr_tx);

 `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == tx[i].awaddr;              //precharge all bank 
            arlen == tx[i].awlen;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);

end


    endtask
endclass




/*
//single read 
class single_write_sequence extends axi_sequence; 
	//fcatory registraion
	`uvm_object_utils(single_write_sequence)
       function new(string name="");
	       super.new(name);
       endfunction 

       task body();
	       `uvm_do_with(req,{req.wr_rd==WRITE_ONLY; req.awaddr==2; req.awlen==3; req.awsize==2; req.awburst==1; req.wid==req.awid;});
       endtask         	       
endclass


/*
                                                                        
//single write and read
class single_write_read_one extends axi_sequence;
    `uvm_object_utils(single_write_read_one)
    function new(string name="");
        super.new(name);
    endfunction
       task body();
            axi_tx wr_tx ,rd_tx;
           `uvm_create(wr_tx);//write awaddr=1  //size should be always 3 narrow transfer are not allowed in out design
	       assert(wr_tx.randomize() with {wr_rd==WRITE_ONLY; awlen==3; awsize==3; awburst==1; awid==5; wid==wr_tx.awid;});
           `uvm_send(wr_tx);

            `uvm_create(rd_tx);//read araddr=1
	            assert(rd_tx.randomize() with {wr_rd==READ_ONLY; arlen==3; arsize==3; arburst==1; arid==5;});
            `uvm_send(rd_tx);
       endtask         	       
endclass

//single write and read
class single_write_read_two extends axi_sequence;
    `uvm_object_utils(single_write_read_two)
    int temp_awaddr_num;
    function new(string name="");
        super.new(name);
    endfunction
       task body();
	        axi_tx wr_tx, rd_tx;
           `uvm_create(wr_tx);
	       assert(wr_tx.randomize() with {wr_rd==WRITE_ONLY;  awlen==7; awsize==3; awburst==1; awid==5; wid==wr_tx.awid; awaddr==0;});
           `uvm_send(wr_tx);

            `uvm_create(rd_tx);
	            assert(rd_tx.randomize() with {wr_rd==READ_ONLY;  arlen==7; arsize==3; arburst==1; arid==5; araddr == 0;});
            `uvm_send(rd_tx);
       endtask         	       


endclass
/* awsize must be 3 and unaligned and narrow and overlapping and outof order are not allowed */
// mulriple write and read sequence of the same adress 

// multiple write and read sequence of the differnet addresses

// write and read targetting the differnet banks

// write and read targetting the differnt column

//write adn read targetting the differnet rows

// random addresses with the random rows and columns and banks 

// total outstanding transactions 16 outstanding transaction

//performance testcases

// DDR  read performance 

// DDR  write performance

// DDR  read and write performance 


//=============================================================================
// PCIe MASTER AND SLAVE SEQUENCES (Simple Implementation)
//=============================================================================

//-----------------------------------------------------------------------------
// Multiple Write to Same Address (PCIe)
//-----------------------------------------------------------------------------

/*
class pcie_multi_write_same_addr extends axi_sequence;
    `uvm_object_utils(pcie_multi_write_same_addr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        
        // Send 3 write transactions to the same address
        repeat(3) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {wr_rd==WRITE_ONLY; awaddr==008;  awlen==3; awsize==3; awburst==1; awid==5; wid==wr_tx.awid;});
            `uvm_send(wr_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Multiple Write to Different Addresses (PCIe)
//-----------------------------------------------------------------------------
class pcie_multi_write_diff_addr extends axi_sequence;
    `uvm_object_utils(pcie_multi_write_diff_addr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        bit[31:0] addr_array[5] = '{32'h1000, 32'h1100, 32'h1200, 32'h1300, 32'h1400};
        
        // Write to 5 different addresses
        foreach(addr_array[i]) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == addr_array[i];
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Multiple Read from Same Address (PCIe)
//-----------------------------------------------------------------------------
class pcie_multi_read_same_addr extends axi_sequence;
    `uvm_object_utils(pcie_multi_read_same_addr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx rd_tx;

        //write it using backdoor method RAL && using the mem_if i will do the write operation to the address 1000
        
        // Send 3 read transactions to the same address
        repeat(3) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == 32'h1000;  // Fixed PCIe address
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Multiple Read from Different Addresses (PCIe)
//-----------------------------------------------------------------------------
class pcie_multi_read_diff_addr extends axi_sequence;
    `uvm_object_utils(pcie_multi_read_diff_addr)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx rd_tx;
        bit[31:0] addr_array[5] = '{32'h1000, 32'h1100, 32'h1200, 32'h1300, 32'h1400};
        
        // Read from 5 different addresses
        foreach(addr_array[i]) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == addr_array[i];
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Back-to-Back Write-Read (PCIe)
//-----------------------------------------------------------------------------
class pcie_back2back_wr_rd extends axi_sequence;
    `uvm_object_utils(pcie_back2back_wr_rd)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        bit[31:0] test_addr = 32'h1500;
        
        // Write then immediately read same address    // write transaction 
        `uvm_create(wr_tx);
        assert(wr_tx.randomize() with {
            wr_rd == WRITE_ONLY;
            awaddr == 'h7ef; // 0011_1110_1111    precharge all bank 
            awlen == 7;
            awsize == 3;
            awburst == 1;
            wid == wr_tx.awid;
        });
        `uvm_send(wr_tx);


        
        `uvm_create(rd_tx);
        assert(rd_tx.randomize() with {            //read transaction 
            wr_rd == READ_ONLY;
            araddr == 'h7ef;              //precharge all bank 
            arlen == 7;
            arsize == 3;
            arburst == 1;
        });
        `uvm_send(rd_tx);


    endtask
endclass


//-----------------------------------------------------------------------------
// Burst Length Variation (PCIe)
//-----------------------------------------------------------------------------
class pcie_burst_length_variation extends axi_sequence;
    `uvm_object_utils(pcie_burst_length_variation)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        bit[3:0] burst_lengths[4] = '{4'd0, 4'd3, 4'd7, 4'd15};  // 1, 4, 8, 16 beats
        
        // Write with different burst lengths
        foreach(burst_lengths[i]) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == 32'h1600 + (i * 32'h100);
                awlen == burst_lengths[i];
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Random PCIe Write Sequence
//-----------------------------------------------------------------------------
class pcie_random_write extends axi_sequence;
    `uvm_object_utils(pcie_random_write)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        
        // 10 random write transactions in PCIe range
        repeat(10) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr inside {[32'h1000:32'h2000]};  // PCIe address range
                awlen inside {[0:15]};
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Random PCIe Read Sequence
//-----------------------------------------------------------------------------
class pcie_random_read extends axi_sequence;
    `uvm_object_utils(pcie_random_read)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx rd_tx;
        
        // 10 random read transactions in PCIe range
        repeat(10) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr inside {[32'h1000:32'h2000]};  // PCIe address range
                arlen inside {[0:15]};
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Mixed Random Write and Read (PCIe)
//-----------------------------------------------------------------------------
class pcie_random_wr_rd_mix extends axi_sequence;
    `uvm_object_utils(pcie_random_wr_rd_mix)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx tx;
        
        // 20 random transactions (write or read)
        repeat(20) begin
            `uvm_create(tx);
            assert(tx.randomize() with {
                wr_rd inside {WRITE_ONLY, READ_ONLY};
                awaddr inside {[32'h1000:32'h2000]};  // PCIe range
                araddr inside {[32'h1000:32'h2000]};
                awlen inside {[0:7]};
                arlen inside {[0:7]};
                awsize == 3;
                arsize == 3;
                awburst == 1;
                arburst == 1;
                wid == tx.awid;
            });
            `uvm_send(tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Sequential Write-Read Pattern (PCIe)
//-----------------------------------------------------------------------------
class pcie_sequential_wr_rd extends axi_sequence;
    `uvm_object_utils(pcie_sequential_wr_rd)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        bit[31:0] base_addr = 32'h1000;
        
        // Write 5 sequential addresses, then read them back
        for(int i = 0; i < 5; i++) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr + (i * 32'h40);
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
        
        // Now read back
        for(int i = 0; i < 5; i++) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == base_addr + (i * 32'h40);
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//=============================================================================
// DDR BANK TARGETING SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Target Different DDR Banks
// DDR3 bank bits are typically [14:12] or [13:11] depending on configuration
//-----------------------------------------------------------------------------
class ddr_target_different_banks extends axi_sequence;
    `uvm_object_utils(ddr_target_different_banks)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        bit[31:0] base_addr;
        
        // Target 8 different banks (bank[2:0])
        for(int bank = 0; bank < 8; bank++) begin
            // Bank address at bits [14:12] - adjust based on your memory map
            base_addr = 32'h1000 + (bank << 12);
            
            // Write to this bank
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr;
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
            
            // Read from this bank
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == base_addr;
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Interleaved Bank Access
//-----------------------------------------------------------------------------
class ddr_interleaved_bank_access extends axi_sequence;
    `uvm_object_utils(ddr_interleaved_bank_access)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        bit[31:0] addr;
        
        // Write to alternating banks (0, 1, 0, 1, ...)
        repeat(10) begin
            for(int bank = 0; bank < 2; bank++) begin
                addr = 32'h1000 + (bank << 12);
                `uvm_create(wr_tx);
                assert(wr_tx.randomize() with {
                    wr_rd == WRITE_ONLY;
                    awaddr == addr;
                    awlen == 3;
                    awsize == 3;
                    awburst == 1;
                    wid == wr_tx.awid;
                });
                `uvm_send(wr_tx);
            end
        end
    endtask
endclass


//=============================================================================
// DDR COLUMN TARGETING SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Target Different Columns in Same Row/Bank
// Column bits are typically lower bits [11:3] or similar
//-----------------------------------------------------------------------------
class ddr_target_different_columns extends axi_sequence;
    `uvm_object_utils(ddr_target_different_columns)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        bit[31:0] base_addr = 32'h1000;  // Same row and bank
        
        // Access 8 different columns within same row/bank
        for(int col = 0; col < 8; col++) begin
            // Column address at lower bits [6:3] - 64-bit aligned
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr + (col * 64);  // 64-byte column spacing
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
            
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == base_addr + (col * 64);
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Sequential Column Burst
//-----------------------------------------------------------------------------
class ddr_sequential_column_burst extends axi_sequence;
    `uvm_object_utils(ddr_sequential_column_burst)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        bit[31:0] base_addr = 32'h1000;
        
        // Sequential column access with bursts
        for(int i = 0; i < 16; i++) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr + (i * 32);  // 32-byte increments
                awlen == 3;
                awsize == 3;
                awburst == 1;  // INCR burst
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
    endtask
endclass


//=============================================================================
// DDR ROW TARGETING SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// Target Different Rows in Same Bank
// Row bits are typically upper bits [31:15] or similar
//-----------------------------------------------------------------------------
class ddr_target_different_rows extends axi_sequence;
    `uvm_object_utils(ddr_target_different_rows)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        bit[31:0] base_addr;
        
        // Access 8 different rows in same bank
        for(int row = 0; row < 8; row++) begin
            // Row address at upper bits [18:15] for example
            base_addr = 32'h1000 + (row << 15);
            
            // Write to this row
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr;
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
            
            // Read from this row
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == base_addr;
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Row Hit/Miss Pattern
//-----------------------------------------------------------------------------
class ddr_row_hit_miss_pattern extends axi_sequence;
    `uvm_object_utils(ddr_row_hit_miss_pattern)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        bit[31:0] row0_addr = 32'h1000;
        bit[31:0] row1_addr = 32'h1000 + (1 << 15);
        
        // Alternate between two rows (causes row misses)
        repeat(5) begin
            // Row 0 - Row Hit
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == row0_addr;
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
            
            // Row 1 - Row Miss
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == row1_addr;
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
    endtask
endclass


//=============================================================================
// RANDOM ADDRESS TARGETING (Rows, Columns, Banks)
//=============================================================================

//-----------------------------------------------------------------------------
// Random Row, Column, Bank Access
//-----------------------------------------------------------------------------
class ddr_random_rcb_access extends axi_sequence;
    `uvm_object_utils(ddr_random_rcb_access)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        
        // 20 completely random accesses
        repeat(20) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr inside {[32'h1000:32'h8000]};  // Covers multiple rows/banks/columns
                awlen inside {[0:7]};
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
            
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr inside {[32'h1000:32'h8000]};
                arlen inside {[0:7]};
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//=============================================================================
// OUTSTANDING TRANSACTIONS SEQUENCES (Up to 16)
//=============================================================================

//-----------------------------------------------------------------------------
// Multiple Outstanding Writes
//-----------------------------------------------------------------------------
class outstanding_writes extends axi_sequence;
    `uvm_object_utils(outstanding_writes)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        
        // Send 16 writes with different IDs (maximum outstanding)
        for(int id = 0; id < 16; id++) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == 32'h1000 + (id * 32'h40);
                awid == id;  // Different ID for each transaction
                awlen == 3;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Multiple Outstanding Reads
//-----------------------------------------------------------------------------
class outstanding_reads extends axi_sequence;
    `uvm_object_utils(outstanding_reads)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx rd_tx;
        
        // Send 16 reads with different IDs (maximum outstanding)
        for(int id = 0; id < 16; id++) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == 32'h1000 + (id * 32'h40);
                arid == id;  // Different ID for each transaction
                arlen == 3;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Mixed Outstanding Writes and Reads
//-----------------------------------------------------------------------------
class outstanding_mixed_wr_rd extends axi_sequence;
    `uvm_object_utils(outstanding_mixed_wr_rd)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx tx;
        
        // Send 16 mixed transactions with different IDs
        for(int id = 0; id < 16; id++) begin
            `uvm_create(tx);
            assert(tx.randomize() with {
                wr_rd inside {WRITE_ONLY, READ_ONLY};
                awaddr == 32'h1000 + (id * 32'h40);
                araddr == 32'h1000 + (id * 32'h40);
                awid == id;
                arid == id;
                awlen == 3;
                arlen == 3;
                awsize == 3;
                arsize == 3;
                awburst == 1;
                arburst == 1;
                wid == tx.awid;
            });
            `uvm_send(tx);
        end
    endtask
endclass


//-----------------------------------------------------------------------------
// Outstanding Transaction Stress Test
//-----------------------------------------------------------------------------
class outstanding_stress_test extends axi_sequence;
    `uvm_object_utils(outstanding_stress_test)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx tx;
        
        // Send 50 transactions with reused IDs (max 16 outstanding)
        repeat(50) begin
            `uvm_create(tx);
            assert(tx.randomize() with {
                wr_rd inside {WRITE_ONLY, READ_ONLY};
                awaddr inside {[32'h1000:32'h2000]};
                araddr inside {[32'h1000:32'h2000]};
                awid inside {[0:15]};  // Only 16 IDs available
                arid inside {[0:15]};
                awlen inside {[0:7]};
                arlen inside {[0:7]};
                awsize == 3;
                arsize == 3;
                awburst == 1;
                arburst == 1;
                wid == tx.awid;
            });
            `uvm_send(tx);
        end
    endtask
endclass


//=============================================================================
// PERFORMANCE TEST SEQUENCES
//=============================================================================

//-----------------------------------------------------------------------------
// DDR Write Performance Test
//-----------------------------------------------------------------------------
class ddr_write_performance extends axi_sequence;
    `uvm_object_utils(ddr_write_performance)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx;
        bit[31:0] base_addr = 32'h1000;
        
        `uvm_info("PERF", "Starting DDR Write Performance Test", UVM_LOW)
        
        // Continuous writes with maximum burst length
        for(int i = 0; i < 100; i++) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr + (i * 32'h80);
                awlen == 15;  // Maximum burst (16 beats)
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
        
        `uvm_info("PERF", "Completed DDR Write Performance Test", UVM_LOW)
    endtask
endclass


//-----------------------------------------------------------------------------
// DDR Read Performance Test
//-----------------------------------------------------------------------------
class ddr_read_performance extends axi_sequence;
    `uvm_object_utils(ddr_read_performance)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx rd_tx;
        bit[31:0] base_addr = 32'h1000;
        
        `uvm_info("PERF", "Starting DDR Read Performance Test", UVM_LOW)
        
        // Continuous reads with maximum burst length
        for(int i = 0; i < 100; i++) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == base_addr + (i * 32'h80);
                arlen == 15;  // Maximum burst (16 beats)
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
        
        `uvm_info("PERF", "Completed DDR Read Performance Test", UVM_LOW)
    endtask
endclass


//-----------------------------------------------------------------------------
// DDR Mixed Read/Write Performance Test
//-----------------------------------------------------------------------------
class ddr_mixed_performance extends axi_sequence;
    `uvm_object_utils(ddr_mixed_performance)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx tx;
        bit[31:0] base_addr = 32'h1000;
        
        `uvm_info("PERF", "Starting DDR Mixed R/W Performance Test", UVM_LOW)
        
        // Alternating reads and writes for performance measurement
        for(int i = 0; i < 100; i++) begin
            `uvm_create(tx);
            assert(tx.randomize() with {
                wr_rd dist {WRITE_ONLY := 50, READ_ONLY := 50};  // 50/50 distribution
                awaddr == base_addr + (i * 32'h80);
                araddr == base_addr + (i * 32'h80);
                awlen == 15;
                arlen == 15;
                awsize == 3;
                arsize == 3;
                awburst == 1;
                arburst == 1;
                wid == tx.awid;
            });
            `uvm_send(tx);
        end
        
        `uvm_info("PERF", "Completed DDR Mixed R/W Performance Test", UVM_LOW)
    endtask
endclass


//-----------------------------------------------------------------------------
// DDR Sustained Bandwidth Test
//-----------------------------------------------------------------------------
class ddr_sustained_bandwidth extends axi_sequence;
    `uvm_object_utils(ddr_sustained_bandwidth)
    
    function new(string name="");
        super.new(name);
    endfunction
    
    task body();
        axi_tx wr_tx, rd_tx;
        bit[31:0] base_addr = 32'h1000;
        
        `uvm_info("PERF", "Starting DDR Sustained Bandwidth Test", UVM_LOW)
        
        // Write phase
        for(int i = 0; i < 50; i++) begin
            `uvm_create(wr_tx);
            assert(wr_tx.randomize() with {
                wr_rd == WRITE_ONLY;
                awaddr == base_addr + (i * 32'h80);
                awlen == 15;
                awsize == 3;
                awburst == 1;
                wid == wr_tx.awid;
            });
            `uvm_send(wr_tx);
        end
        
        // Read phase
        for(int i = 0; i < 50; i++) begin
            `uvm_create(rd_tx);
            assert(rd_tx.randomize() with {
                wr_rd == READ_ONLY;
                araddr == base_addr + (i * 32'h80);
                arlen == 15;
                arsize == 3;
                arburst == 1;
            });
            `uvm_send(rd_tx);
        end
        
        `uvm_info("PERF", "Completed DDR Sustained Bandwidth Test", UVM_LOW)
    endtask
endclass


//=============================================================================
// NOTES
//=============================================================================
/* 
 * awsize must be 3 (64-bit transfers)
 * Unaligned, narrow, overlapping and out-of-order transfers are not allowed
 * Maximum 16 outstanding transactions (ID 0-15)
 * DDR addressing depends on your memory controller configuration
 * Adjust row/bank/column bit positions based on your design
 */
