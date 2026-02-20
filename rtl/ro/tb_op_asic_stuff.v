`timescale 1ns/1ps

//---------------------------------------------------------------------
// Stub for the ring oscillator (just toggles when enabled)
//---------------------------------------------------------------------
module ro_11_stage #(
    parameter STAGES = 11
)(
    input  wire ro_en,
    output reg  ro_q
);
    initial ro_q = 0;
    // When enabled, toggle every 7ns to emulate an oscillator
    always begin
        @(posedge ro_en);
        forever begin
            #7 ro_q = ~ro_q;
        end
    end
endmodule

//---------------------------------------------------------------------
// Stub for the inverter chain (just delays the input by one clock of
// a small delay to emulate propagation through a chain of inverters)
//---------------------------------------------------------------------
module inv_chain_11_stage #(
    parameter STAGES = 11
)(
    input  wire ro_chain_i,
    output reg  ro_chain_q
);
    always @(ro_chain_i) begin
        // emulate some small propagation
        #3 ro_chain_q = ~ro_chain_i;   
        #3 ro_chain_q = ro_chain_i;
    end
endmodule

//---------------------------------------------------------------------
// Device Under Test
//---------------------------------------------------------------------
module op_asic_stuff
#(
    parameter RO_STAGES    = 11, // number of ring‐oscillator inversions
    parameter CHAIN_STAGES = 11  // number of inverter‐chain stages
)(
    // RING OSCILLATOR
    input  wire ro_en,        // active‐high enable
    output wire ro_q,         // RO output

    // INVERTER CHAIN
    input  wire ro_chain_i,   // chain input
    output wire ro_chain_q,   // chain output

    // FOUR‐BIT REGISTER BANK
    input  wire ro_clk,       // clock
    input  wire ro_rst_n,     // async active‐low reset
    input  wire ro_ce_n,      // active‐low enable
    input  wire [3:0] ro_data_d, // data in
    output reg  [3:0] ro_data_q  // data out
);

    // RING OSCILLATOR
    (* keep = "true" *) ro_11_stage #(
        .STAGES(RO_STAGES)
    ) u_ro (
        .ro_en(ro_en),
        .ro_q (ro_q )
    );

    // INVERTER CHAIN
    (* keep = "true" *) inv_chain_11_stage #(
        .STAGES(CHAIN_STAGES)
    ) u_chain (
        .ro_chain_i(ro_chain_i),
        .ro_chain_q(ro_chain_q)
    );

    // FOUR‐BIT REGISTER BANK
    always @(posedge ro_clk or negedge ro_rst_n) begin
        if (!ro_rst_n)
            ro_data_q <= 4'b0000;
        else if (!ro_ce_n)
            ro_data_q <= ro_data_d;
    end

endmodule

//---------------------------------------------------------------------
// Testbench
//---------------------------------------------------------------------
module tb_op_asic_stuff;

    reg         tb_ro_en;
    wire        tb_ro_q;

    reg         tb_ro_chain_i;
    wire        tb_ro_chain_q;

    reg         tb_clk;
    reg         tb_rst_n;
    reg         tb_ce_n;
    reg  [3:0]  tb_data_d;
    wire [3:0]  tb_data_q;

    // Instantiate DUT
    op_asic_stuff dut (
        .ro_en       (tb_ro_en),
        .ro_q        (tb_ro_q),
        .ro_chain_i  (tb_ro_chain_i),
        .ro_chain_q  (tb_ro_chain_q),
        .ro_clk      (tb_clk),
        .ro_rst_n    (tb_rst_n),
        .ro_ce_n     (tb_ce_n),
        .ro_data_d   (tb_data_d),
        .ro_data_q   (tb_data_q)
    );

    // Clock generation: 10ns period
    initial begin
        tb_clk = 0;
        forever #5 tb_clk = ~tb_clk;
    end

    // Test sequence
    initial begin
        // dump variables
        $dumpfile("tb_op_asic_stuff.vcd");
        $dumpvars(0, tb_op_asic_stuff);

        // initialize
        tb_ro_en       = 0;
        tb_ro_chain_i  = 0;
        tb_ce_n        = 1;      // disable writes
        tb_data_d      = 4'h0;
        tb_rst_n       = 0;      // assert reset

        // hold reset for a few cycles
        #20;
        tb_rst_n = 1;            // release reset

        // enable ring oscillator
        #10;
        tb_ro_en = 1;

        // test inverter chain
        repeat (10) begin
            #12 tb_ro_chain_i = ~tb_ro_chain_i;
        end

        // test register write
        #10;
        tb_data_d = 4'ha;
        tb_ce_n   = 0;  // enable write
        #10;
        tb_ce_n   = 1;  // disable write

        // change data again
        #20;
        tb_data_d = 4'h5;
        #10;
        tb_ce_n   = 0;
        #10;
        tb_ce_n   = 1;

        // wait a little bit
        #100;

        $display("Testbench complete.");
        $finish;
    end

    // Monitor outputs
    initial begin
        $monitor(
            "%0t | ro_en=%b ro_q=%b | chain_i=%b chain_q=%b | ce_n=%b data_d=%h data_q=%h",
            $time,
            tb_ro_en, tb_ro_q,
            tb_ro_chain_i, tb_ro_chain_q,
            tb_ce_n, tb_data_d, tb_data_q
        );
    end
endmodule

