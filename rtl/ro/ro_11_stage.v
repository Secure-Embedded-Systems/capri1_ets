`timescale 1ns/1ps
/*
  ro_11_stage.v
  An 11-stage ring oscillator:
    - gated by a NAND on 'ro_en'
    - 10 customInv cells + 1 customNand form 11 total inversions
    - simulation-only #2.5ns delays are stripped before synthesis
    - internal nets and cells marked keep to avoid optimization
*/
module ro_11_stage #(
  parameter integer STAGES = 11
)(
  input  wire ro_en,
  output wire ro_q
);
  (* keep = "true" *) wire [0:STAGES-2] ni;       // inputs to each inverter
  (* keep = "true" *) wire              nandout   /* synthesis keep = 1 */;
  (* keep = "true" *) wire [0:STAGES-2] no	/* synthesis keep = 1 */;
  (* keep = "true" *) customNand nc (
    .a(ro_en),
    .b(no[STAGES-2]),
    .q(nandout)
  );
  (* keep = "true" *) customInv ic [0:STAGES-2] (
    .a(ni),
    .q(no)
  );

   assign #2.5 ni[0]            = nandout;
   assign ni[1:(STAGES-2)]      = no[0:(STAGES-3)];
   assign ro_q                  = no[(STAGES-3)];

endmodule

