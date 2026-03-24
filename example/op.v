// Simple 4-function ALU with accumulator
module op #(
    integer XLEN = 64
) (
    input  wire            clock,
    input  wire            reset,
    input  wire [XLEN-1:0] a,
    input  wire [XLEN-1:0] b,
    input  wire [     1:0] op_sel,   // 00=ADD, 01=SUB, 10=AND, 11=XOR
    input  wire            acc_en,   // 1=load ALU result into accumulator
    output reg  [XLEN-1:0] out,      // current ALU result
    output reg  [XLEN-1:0] acc,      // accumulator register
    output reg             zero,     // out == 0
    output reg             overflow  // signed overflow (ADD/SUB only)
);

  // --- combinational ALU ---
  reg [  XLEN:0] wide_sum;
  reg [XLEN-1:0] alu_out;
  reg            ov;

  always_comb begin
    wide_sum = {XLEN + 1{1'b0}};
    ov       = 1'b0;
    case (op_sel)
      2'b00: begin  // ADD
        wide_sum = {{1{a[XLEN-1]}}, a} + {{1{b[XLEN-1]}}, b};
        alu_out  = wide_sum[XLEN-1:0];
        ov       = wide_sum[XLEN] ^ wide_sum[XLEN-1];
      end
      2'b01: begin  // SUB
        wide_sum = {{1{a[XLEN-1]}}, a} - {{1{b[XLEN-1]}}, b};
        alu_out  = wide_sum[XLEN-1:0];
        ov       = wide_sum[XLEN] ^ wide_sum[XLEN-1];
      end
      2'b10: begin  // AND
        alu_out = a & b;
      end
      2'b11: begin  // XOR
        alu_out = a ^ b;
      end
      default: alu_out = {XLEN{1'b0}};
    endcase
  end

  // --- registered outputs ---
  always @(posedge clock) begin
    if (reset) begin
      out      <= {XLEN{1'b0}};
      acc      <= {XLEN{1'b0}};
      zero     <= 1'b1;
      overflow <= 1'b0;
    end else begin
      out      <= alu_out;
      zero     <= (alu_out == {XLEN{1'b0}});
      overflow <= ov;
      if (acc_en) acc <= alu_out;
    end
  end

endmodule
