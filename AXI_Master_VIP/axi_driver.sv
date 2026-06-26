//-----------------------------------------------------------------------------
// File Name    : axi_driver.sv
// Project      : DDR3 Controller Subsystem verfication using AXI3
// Engineer     : amith

// Created Date : 2025-05-15
//
// Description  : Implementation of the axi_driver module
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
class axi_pcie_master_driver extends uvm_driver#(axi_tx);
    `uvm_component_utils(axi_pcie_master_driver)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

    typedef struct {
        int beats_remaining;  // How many beats left to receive
        int total_beats;      // Total beats expected
        bit active;           // Transaction is active
    } rd_tracking_t;
    
    rd_tracking_t rd_track[int];  // Associative array indexed by arid

    //assosiative array to store the data's
    axi_tx wr_tx[int];

    int data_size_in_bytes;
    int each_beat_active_bytes;
    int each_beat_start_address;
    int offset_addr;
    int aligned_addr;
    int wstrb_bit;
    bit out_of_order;
    bit overlapping;
    int a[int];
	int b;
    int c;

    //virtual interface:- vif
    virtual axi_pcie_intf#(64,32,4,8,10000,4) vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_pcie_intf#(64,32,4,8,10000,4))::get(this,"","pvif",vif))
            `uvm_fatal("NOVIF", "axi_pcie_master_driver: virtual AXI interface not found")
        void'(uvm_config_db#(bit)::get(this,"","order",out_of_order));
        void'(uvm_config_db#(bit)::get(this,"","overlap",overlapping));
    endfunction

    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        vif.awvalid <= 0;
        vif.wvalid  <= 0;
        vif.wlast   <= 0;
        vif.bready  <= 0;
        vif.arvalid <= 0;
        vif.rready  <= 0;
        wait(vif.areset_n == 1);
        @(posedge vif.aclk);
        fork
        forever begin
            @(posedge vif.aclk);
            seq_item_port.get_next_item(req);
                //write then read
                if(req.wr_rd == WRITE_THEN_READ)begin
                    
                    write_address_channel();
                    write_data_channel();
                    write_response_channel();
                    read_address_channel();
                    //read_data_channel();

                end
                
                //write parallel read
                else if(req.wr_rd==WRITE_PARALEL_READ)begin
                    begin
                    write_address_channel();
                    write_data_channel();
                    write_response_channel();
                    end
                    begin
                    read_address_channel();
                    //read_data_channel();
                    end
                end
 
                //write only
                else if(req.wr_rd==WRITE_ONLY)begin
                    if(out_of_order || overlapping)begin
                        //the write address and the write data is coming from themaster
                        if(req.awvalid ==1 && req.wvalid==0)begin
                            write_address_channel();
                        end
                        if(req.wvalid==1)begin
                            write_data_channel();
                            write_response_channel();
                        end
                    end
                    else begin
                       // $display("inside the write read else block");
                        write_address_channel();
                        write_data_channel();
                        write_response_channel();
                    end
                end
                //read only
                else if(req.wr_rd==READ_ONLY)begin
			    //$display("ENTERED READ ONLY");
                   // if(out_of_order || overlapping)begin
                       // if(req.arvalid ==1 && req.rready==1)begin
                         //   read_address_channel();
                        //end 
		     // end
                       // else begin
			//$display("ENTERED READ ONLY ELSE");
				
                            read_address_channel();
                            //read_data_channel();
                        //end
                   // end
                end

            seq_item_port.item_done();

        end
        read_data_monitor();
         join_none
    endtask

    //write address channel
    task write_address_channel();
        vif.awaddr<=req.awaddr;
        vif.awid<=req.awid;
        vif.awlen<=req.awlen;
        vif.awcache<=req.awcache;
        vif.awprot<=req.awprot;
        vif.awlock<=req.awlock;
        vif.awsize<=req.awsize;
        vif.awburst<=req.awburst;
        vif.awvalid<=1;

        wait(vif.awready==1);
        wr_tx[req.awid] = new();
        wr_tx[req.awid].awaddr = req.awaddr;
        wr_tx[req.awid].awlen = req.awlen;
        wr_tx[req.awid].awsize = req.awsize;
        wr_tx[req.awid].awprot = req.awprot;
        wr_tx[req.awid].awcache = req.awcache;
        wr_tx[req.awid].awburst = req.awburst;
        wr_tx[req.awid].awid = req.awid;

        @(posedge vif.aclk);

        vif.awvalid<=0;
        //$display("after awvalid in master time=%0t",$time);

    endtask

    //write data channel
    task write_data_channel();
        vif.bready<=1;
        //$display("inside the write_datachannel bready=%0d",vif.bready);
        fork
                begin
                    if(overlapping)begin
                        write_address_channel();
                    end
                end

                begin
          //              $display("awlen in driver = %0d",req.awlen);
                    for(int i=0; i<=req.awlen; i=i+1)begin 
                       // @(posedge vif.aclk);
                        vif.wdata<=req.wdata.pop_back();
                        vif.wid<= req.wid;
                        vif.wvalid<=1;
            //            $display("inside the write_datachannel wvalid=%0d time=%0t",vif.wvalid,$time);

                            //wdata size in bytes
                            data_size_in_bytes = ($size(vif.wdata)/8);
                            //how many bytes are active in each beat or transfer
                            each_beat_active_bytes = (2**req.awsize);
                            //start address is aligned or unaligned or the remainder value 
                            offset_addr = req.awaddr % data_size_in_bytes;
                            //convert the unaligned address to aligned address
                            aligned_addr = req.awaddr - (req.awaddr % req.awsize);

                            req.wstrb = 0;

                            if(req.awaddr % each_beat_active_bytes == 0)begin
                                for(int j=0; j<each_beat_active_bytes; j++)begin
                                        wstrb_bit = (offset_addr + j) % data_size_in_bytes;
                                        req.wstrb[wstrb_bit] = 1;
                                end
                            end

                            if(req.awaddr % each_beat_active_bytes != 0) begin
                                if(req.awsize==1)
                                    c=0;
                                else
                                    c=1;
                                    for(int j=offset_addr; j<(wr_tx[req.wid].awsize +offset_addr+c); j=j+1)begin
                            
                                        req.wstrb[j] = 1'b1;
                                    end
                            end
              //          $display("awlen=%0d i=%0d",req.awlen,i);

                        if(i==req.awlen)begin 
                //            $display("inside the wlast condition i=%0d",i);
                            vif.wlast<=1;
                        end

                            vif.wstrb <= req.wstrb;

                            //convert unaligned address to aligned address
                            req.awaddr = req.awaddr - (req.awaddr % (2** req.awsize));

                            req.awaddr = req.awaddr + (2**req.awsize);

                            wait(vif.wready==1);
                            @(posedge vif.aclk);
                            vif.wlast <= 0;
                            vif.wvalid<=0;
                        
                    end
                end
        join
    endtask


    //write response channel
    task write_response_channel();
        wait(vif.bvalid==1);
        if(out_of_order || overlapping)begin
            @(posedge vif.aclk);
            @(posedge vif.aclk);
            //we can handle the response forwarding to the noc or the response handlig or the retry mechanism
        end
        vif.bready = 0;
    endtask

    //read address channel
    task read_address_channel();
	   // $display("DRIVER READ ADDRESS CHANNEEL");
        vif.araddr <= req.araddr;
        vif.arid <= req.arid;
        vif.arlen <= req.arlen;
        vif.arcache <= req.arcache;
        vif.arprot <= req.arprot;
        vif.arlock <= req.arlock;
        vif.arsize <= req.arsize;
        vif.arburst <= req.arburst;
        vif.arvalid <= 1;
        

        // Track this transaction
        rd_track[req.arid].beats_remaining = req.arlen + 1;  // arlen+1 total beats
        rd_track[req.arid].total_beats = req.arlen + 1;
        rd_track[req.arid].active = 1;
        //address  this address is valid =1 master is telling

        wait(vif.arready==1);
        @(posedge vif.aclk);
        vif.arvalid <= 0;
        a[req.arid] = req.arlen;
    endtask

    // a[1] = 2    a[2] = 4

    //a[1,2]a.first = 1  =2      b=2

    //address=1; arlen=2(3 beats) arsize=3   3beats 

    //read response channel
    // task read_data_channel();
	//     //$display("DRIVER READ DATA CHANNEEL");
    //     a.first(b);
    //     for(int i=0; i<a[b]; i=i+1)begin //it will start from 0 and continue until 2
    //             vif.rready <= 1;
    //             wait(vif.rvalid==1);
    //             @(posedge vif.aclk);
    //             vif.rready<=0; // done with getting the read response
    //     end
    //     a.delete(b);
    // endtask

    // NEW: Continuous read data monitoring
    task read_data_monitor();
        forever begin
            @(posedge vif.aclk);
            
            // Check if any outstanding read transactions exist
            if(rd_track.size() > 0) begin
                vif.rready <= 1;  // Keep ready high when expecting data
                
                // Check for valid data
                if(vif.rvalid == 1) begin
                    vif.rready<=1;
                    // Match response to transaction using RID
                    if(rd_track.exists(vif.rid) && rd_track[vif.rid].active) begin
                        
                        rd_track[vif.rid].beats_remaining--;
                        
                    //    $display("[DRIVER] Read data received: ID=%0d, Data=0x%h, RLAST=%0b, Remaining=%0d/%0d",
                                 //vif.rid, vif.rdata, vif.rlast, 
                                 //rd_track[vif.rid].beats_remaining,
                                 //rd_track[vif.rid].total_beats);
                        
                        // Check for completion
                        if(vif.rlast == 1) begin
                          //  if(rd_track[vif.rid].beats_remaining != 0) begin
                              //  $error("[DRIVER] RLAST received but beats remaining = %0d for ID=%0d",
                                       //rd_track[vif.rid].beats_remaining, vif.rid);
                          //  end
                            
                            // Transaction complete
                            rd_track.delete(vif.rid);
                          //  $display("[DRIVER] Read transaction complete: ID=%0d", vif.rid);
                            
                            // Check if all transactions done
                            if(rd_track.size() == 0) begin
                                vif.rready <= 1;  // Can deassert when no outstanding reads
                            end
                        end
                        //else begin
                           // if(rd_track[vif.rid].beats_remaining == 0) begin
                              //  $error("[DRIVER] All beats received but RLAST=0 for ID=%0d", vif.rid);
                           // end
                        //end
                    end
                    //else begin
                       // $error("[DRIVER] Received data for unknown/inactive transaction ID=%0d", vif.rid);
                    //end
                end
            end
            else begin
                vif.rready <= 1;  // No outstanding transactions
            end
        end
    endtask

    
endclass




//CFG
class axi_cfg_master_driver extends uvm_driver#(axi_tx);
    `uvm_component_utils(axi_cfg_master_driver)
    function new(string name="",uvm_component parent=null);
        super.new(name,parent);
    endfunction

    //assosiative array to store the data's
    axi_tx wr_tx[int];

    int data_size_in_bytes;
    int each_beat_active_bytes;
    int each_beat_start_address;
    int offset_addr;
    int aligned_addr;
    int wstrb_bit;
    bit out_of_order;
    bit overlapping;
    int a[int];
	int b;
    int c;

    //virtual interface:- vif
    virtual axi_cfg_intf vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_cfg_intf)::get(this,"","pvif",vif))
            `uvm_fatal("NOVIF", "axi_cfg_master_driver: virtual AXI config interface not found")
        void'(uvm_config_db#(bit)::get(this,"","order",out_of_order));
        void'(uvm_config_db#(bit)::get(this,"","overlap",overlapping));
    endfunction

    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        vif.awvalid <= 0;
        vif.wvalid  <= 0;
        vif.wlast   <= 0;
        vif.bready  <= 0;
        vif.arvalid <= 0;
        vif.rready  <= 0;
        wait(vif.areset_n == 1);
        @(posedge vif.aclk);
        forever begin
            @(posedge vif.aclk);
            seq_item_port.get_next_item(req);
                //write then read
                if(req.wr_rd == WRITE_THEN_READ)begin
                    
                    write_address_channel();
                    write_data_channel();
                    write_response_channel();
                    read_address_channel();
                    read_data_channel();

                end
                
                //write parallel read
                else if(req.wr_rd==WRITE_PARALEL_READ)begin
                    begin
                    write_address_channel();
                    write_data_channel();
                    write_response_channel();
                    end
                    begin
                    read_address_channel();
                    read_data_channel();
                    end
                end
 
                //write only
                else if(req.wr_rd==WRITE_ONLY)begin
                    if(out_of_order || overlapping)begin
                        if(req.awvalid ==1 && req.wvalid==0)begin
                            write_address_channel();
                        end
                        if(req.wvalid==1)begin
                            write_data_channel();
                            write_response_channel();
                        end
                    end
                    else begin
           //             $display("inside the write read else block");
                        write_address_channel();
                        write_data_channel();
                        write_response_channel();
                    end
                end
                //read only
                else if(req.wr_rd==READ_ONLY)begin
			//            $display("ENTERED READ ONLY");
                   // if(out_of_order || overlapping)begin
                       // if(req.arvalid ==1 && req.rready==1)begin
                         //   read_address_channel();
                        //end 
		     // end
                       // else begin
			//$display("ENTERED READ ONLY ELSE");
				
                            read_address_channel();
                            read_data_channel();
                        //end
                   // end
                end

            seq_item_port.item_done();
        end
         
    endtask

    //write address channel
    task write_address_channel();
        vif.awaddr<=req.awaddr;
        vif.awid<=req.awid;
        vif.awlen<=req.awlen;
        vif.awcache<=req.awcache;
        vif.awprot<=req.awprot;
        vif.awlock<=req.awlock;
        vif.awsize<=req.awsize;
        vif.awburst<=req.awburst;
        vif.awvalid<=1;

        wait(vif.awready==1);
        wr_tx[req.awid] = new();
        wr_tx[req.awid].awaddr = req.awaddr;
        wr_tx[req.awid].awlen = req.awlen;
        wr_tx[req.awid].awsize = req.awsize;
        wr_tx[req.awid].awprot = req.awprot;
        wr_tx[req.awid].awcache = req.awcache;
        wr_tx[req.awid].awburst = req.awburst;
        wr_tx[req.awid].awid = req.awid;

        @(posedge vif.aclk);

        vif.awvalid<=0;
        //$display("after awvalid in master time=%0t",$time);

    endtask

    //write data channel
    task write_data_channel();
        vif.bready<=1;
        //$display("inside the write_datachannel bready=%0d",vif.bready);
        fork
                begin
                    if(overlapping)begin
                        write_address_channel();
                    end
                end

                begin
          //              $display("awlen in driver = %0d",wr_tx[req.wid].awlen);
                    for(int i=0; i<=wr_tx[req.wid].awlen; i=i+1)begin 
                       // @(posedge vif.aclk);
                        vif.wdata<=req.wdata.pop_back();  
                        vif.wid<= req.wid;
                        vif.wvalid<=1;
            //            $display("inside the write_datachannel wvalid=%0d time=%0t",vif.wvalid,$time);

                            //wdata size in bytes
                            data_size_in_bytes = ($size(vif.wdata)/8);
                            //how many bytes are active in each beat or transfer
                            each_beat_active_bytes = (2**wr_tx[req.wid].awsize);
                            //start address is aligned or unaligned or the remainder value 
                            offset_addr = wr_tx[req.wid].awaddr % data_size_in_bytes;
                            //convert the unaligned address to aligned address
                            aligned_addr = wr_tx[req.wid].awaddr - (wr_tx[req.wid].awaddr % wr_tx[req.wid].awsize);

                            req.wstrb = 0;

                            if(wr_tx[req.wid].awaddr % each_beat_active_bytes == 0)begin
                                for(int j=0; j<each_beat_active_bytes; j++)begin
                                        wstrb_bit = (offset_addr + j) % data_size_in_bytes;
                                        req.wstrb[wstrb_bit] = 1;
                                end
                            end

                            if(wr_tx[req.wid].awaddr % each_beat_active_bytes != 0) begin
                                if(wr_tx[req.wid].awsize==1)
                                    c=0;
                                else
                                    c=1;
                                    for(int j=offset_addr; j<(wr_tx[req.wid].awsize +offset_addr+c); j=j+1)begin
                            
                                        req.wstrb[j] = 1'b1;
                                    end
                            end
              //          $display("awlen=%0d i=%0d",wr_tx[req.wid].awlen,i);

                        if(i==wr_tx[req.wid].awlen)begin 
                //            $display("inside the wlast condition i=%0d",i);
                            vif.wlast<=1;
                        end

                            vif.wstrb <= req.wstrb;

                            //convert unaligned address to aligned address
                            wr_tx[req.wid].awaddr = wr_tx[req.wid].awaddr - (wr_tx[req.wid].awaddr % (2** wr_tx[req.wid].awsize));

                            wr_tx[req.wid].awaddr = wr_tx[req.wid].awaddr - (wr_tx[req.wid].awaddr + 2**wr_tx[req.wid].awsize);

                            wait(vif.wready==1);
                            @(posedge vif.aclk);
                            vif.wlast <= 0;
                            vif.wvalid<=0;
                        
                    end
                end
        join
    endtask


    //write response channel
    task write_response_channel();
        wait(vif.bvalid==1);
        if(out_of_order || overlapping)begin
            @(posedge vif.aclk);
            @(posedge vif.aclk);
        end
        vif.bready = 0;
    endtask

    //read address channel
    task read_address_channel();
	    //$display("DRIVER READ ADDRESS CHANNEEL");
        vif.araddr <= req.araddr;
        vif.arid <= req.arid;
        vif.arlen <= req.arlen;
        vif.arcache <= req.arcache;
        vif.arprot <= req.arprot;
        vif.arlock <= req.arlock;
        vif.arsize <= req.arsize;
        vif.arburst <= req.arburst;
        vif.arvalid <= 1;

        wait(vif.arready==1);
        @(posedge vif.aclk);
        vif.arvalid <= 0;
        a[req.arid] = req.arlen;
    endtask

    //read response channel
    task read_data_channel();
	    //$display("DRIVER READ DATA CHANNEEL");
        void'(a.first(b));
        //for(int i=0; i<a[b]; i=i+1)begin
                vif.rready <= 1;
                wait(vif.rvalid==1);
                vif.rready<=1;
                //@(posedge vif.aclk);
        //end
        a.delete(b);
    endtask

    //always@(posedge vif.aclk)begin

    //end
endclass
