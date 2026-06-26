`timescale 1ps / 1ps
`include "./memory_module/ddr5_6400_parameters.sv"

interface mem_if(input logic i_cpu_ck);
    logic [1:0]  ck_t;
    logic [1:0]  ck_c;
    logic        cke;
    logic [1:0]  cs_n;
    logic        reset_n;
    logic        odt;
    logic        dch;
    logic [27:0] ca;
    logic [1:0]  cai;

    tri [DQ_BITS-1:0]  dq;
    tri [DQS_BITS-1:0] dqs_t;
    tri [DQS_BITS-1:0] dqs_c;
    tri [DM_BITS-1:0]  dmi;

    modport contr_sig (
        output ck_t, ck_c, cke, cs_n, reset_n, odt, dch, ca, cai,
        inout  dq, dqs_t, dqs_c, dmi
    );

    modport mem_sig (
        input  ck_t, ck_c, cke, cs_n, reset_n, odt, dch, ca, cai,
        inout  dq, dqs_t, dqs_c, dmi
    );
endinterface : mem_if
