`timescale 1ns/1ps

module op_asic_stuff
#(
    parameter RO_STAGES    = 11, // number of ring-oscillator inversions (odd > 1)
    parameter CHAIN_STAGES = 11  // number of inverter-chain stages
)(
    // RING OSCILLATOR
    input  wire        ro_en,      // active-high enable
    output wire        ro_q,       // RO output

    // INVERTER CHAIN
    input  wire        ro_chain_i, // chain input
    output wire        ro_chain_q, // chain output

    // FOUR-BIT REGISTER BANK
    input  wire        ro_clk,     // clock
    input  wire        ro_rst_n,   // async active-low reset
    input  wire        ro_ce_n,    // active-low enable
    input  wire [3:0]  ro_data_d,  // data in
    output reg  [3:0]  ro_data_q   // data out
);

  (* keep = "true" *) ro_11_stage #(
      .STAGES(RO_STAGES)
  ) u_ro (
      .ro_en(ro_en),
      .ro_q (ro_q)
  );

  (* keep = "true" *) inv_chain_11_stage #(
      .STAGES(CHAIN_STAGES)
  ) u_chain (
      .ro_chain_i(ro_chain_i),
      .ro_chain_q(ro_chain_q)
  );

  always @(posedge ro_clk or negedge ro_rst_n) begin
      if (!ro_rst_n)
          ro_data_q <= 4'b0000;
      else if (!ro_ce_n)
          ro_data_q <= ro_data_d;
  end

endmodule

