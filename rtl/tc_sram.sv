//
// Simple replacement for tc_sram that does NOT rely on IHP macros.
// Synchronous read, one-cycle latency, bit-level write masking.
// Memory: NumWords words, each DataWidth bits wide.
module tc_sram #(
  parameter int unsigned NumWords     = 128,
  parameter int unsigned DataWidth    = 32,
  parameter int unsigned ByteWidth    = 8,
  parameter int unsigned NumPorts     = 1,
  parameter int unsigned Latency      = 1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none",
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth = (NumWords > 1) ? $clog2(NumWords) : 1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 1) / ByteWidth,
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t  [NumPorts-1:0] addr_i,
  input  data_t  [NumPorts-1:0] wdata_i,
  input  be_t    [NumPorts-1:0] be_i,
  // Declare the output as a 2D array with port index first.
  output logic [0:NumPorts-1][DataWidth-1:0] rdata_o
);

  // ------------------------------------------------------------------------
  // 1) Memory array: [NumWords x DataWidth]
  // ------------------------------------------------------------------------
  logic [DataWidth-1:0] mem [0:NumWords-1];

  // ------------------------------------------------------------------------
  // 2) Read Data Pipeline Registers:
  // Declare as a 2D array: first dimension for port index, second is the data bits.
  // ------------------------------------------------------------------------
  logic [0:NumPorts-1][DataWidth-1:0] rdata_q;

  // ------------------------------------------------------------------------
  // 3) Synchronous read and bit-level write logic.
  // ------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Reset read data registers
      for (int p = 0; p < NumPorts; p++) begin
        rdata_q[p] <= '0;
      end
    end else begin
      for (int p = 0; p < NumPorts; p++) begin
        if (req_i[p]) begin
          if (we_i[p]) begin
            // Write operation: update individual bits if byte enable is high
            for (int b = 0; b < DataWidth; b++) begin
              if (be_i[p][b/ByteWidth]) begin
                mem[addr_i[p]][b] <= wdata_i[p][b];
              end
            end
          end else begin
            // Read operation: register memory content for one-cycle latency
            rdata_q[p] <= mem[addr_i[p]];
          end
        end
      end
    end
  end

  // ------------------------------------------------------------------------
  // 4) Output assignment: assign the read registers to the output.
  // ------------------------------------------------------------------------
  assign rdata_o = rdata_q;

endmodule

