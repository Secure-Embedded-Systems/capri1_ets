`timescale 1ns/1ps
/*
  inv_chain_11_stage.v
  An 11-stage inveter chain:
    - 11 total inversions
    - simulation-only #2.5ns delays are stripped before synthesis
    - internal nets and cells marked keep to avoid optimization
*/
module inv_chain_11_stage #(
  parameter integer STAGES = 11
)(
  input  wire ro_chain_i,
  output wire ro_chain_q
);
  (* keep = "true" *) wire [0:STAGES-2] ni;      
  (* keep = "true" *) wire [0:STAGES-2] no /* synthesis keep = 1 */;
  (* keep = "true" *) customInv ic [0:STAGES-2] (
    .a(ni),
    .q(no)
  );

   assign #2.5 ni[0]       = ro_chain_i;
   assign ni[1:(STAGES-2)] = no[0:(STAGES-3)];
   assign ro_chain_q       = no[(STAGES-3)];

endmodule

