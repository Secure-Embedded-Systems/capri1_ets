// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
// Authors:
//
// -Thomas Benz <tbenz@iis.ee.ethz.ch>
// -Tobias Senti <tsenti@student.ethz.ch>
//
// NOTE: This is a behavioral (technology-independent) version.
//       For ASIC synthesis, replace with foundry-specific clock cells.

module tc_clk_inverter (
    input  logic clk_i,
    output logic clk_o
  );
  assign clk_o = ~clk_i;
endmodule

module tc_clk_buffer (
  input  logic clk_i,
  output logic clk_o
);
  assign clk_o = clk_i;
endmodule

module tc_clk_mux2 (
    input  logic clk0_i,
    input  logic clk1_i,
    input  logic clk_sel_i,
    output logic clk_o
  );
  assign clk_o = clk_sel_i ? clk1_i : clk0_i;
endmodule

module tc_clk_xor2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  assign clk_o = clk0_i ^ clk1_i;
endmodule

module tc_clk_gating #(
    parameter bit IS_FUNCTIONAL = 1'b1
  )(
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
  );

  logic en_latch;

  always_latch begin
    if (~clk_i)
      en_latch = en_i | test_en_i;
  end

  assign clk_o = clk_i & en_latch;

endmodule
