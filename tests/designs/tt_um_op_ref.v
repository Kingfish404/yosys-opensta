// Reference TinyTapeout wrapper for example/op.v
// -------------------------------------------------
// This file is a FUNCTIONAL reference, not the flow default.
// The default flow uses an auto-generated evaluation wrapper.
// To use this wrapper explicitly:
//
//   make tt-preflight \
//     RTL_FILES="example/op.v tests/designs/tt_um_op_ref.v" \
//     TT_NATIVE=1 \
//     DESIGN=tt_um_op_ref
//
// A self-contained simulation testbench lives at
//   tests/tb/tb_tt_um_op_ref.v
//
// Protocol (XLEN = 8 in TT mode; limited to 8-bit operands for pin budget):
//
//   ui_in[7:6]  cmd:   2'b00 = WRITE_A
//                      2'b01 = WRITE_B
//                      2'b10 = CONTROL  (write: {acc_en, op_sel[1:0]} on uio_in[2:0])
//                      2'b11 = READ_OUT
//   ui_in[2]    write_en (for WRITE_A / WRITE_B); read_acc (for READ_OUT)
//   uio_in[7:0] data byte written to a or b (when write_en)
//
//   uo_out[7:0] = alu byte read when cmd==READ_OUT
//   uio_out[7]  = overflow
//   uio_out[6]  = zero
//   uio_out[1:0]= op_sel_reg (status)
//   uio_oe      = 8'hff when cmd==CONTROL and !write_en, else 8'h00
//
// Note: Only 8-bit operands fit in the single-byte TT IO.  For wider
// operands, implement a multi-byte transfer protocol similar to the
// larger op example that was previously in tinytapeout/examples/.

`default_nettype none

module tt_um_op_ref (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // --- decode ui_in fields ---
  wire [1:0] cmd      = ui_in[7:6];
  wire       write_en = ui_in[2];
  wire       read_acc = ui_in[2];  // same bit, used in READ_OUT context

  localparam CMD_WRITE_A  = 2'b00;
  localparam CMD_WRITE_B  = 2'b01;
  localparam CMD_CONTROL  = 2'b10;
  localparam CMD_READ_OUT = 2'b11;

  // --- internal registers ---
  reg [7:0] a_reg;
  reg [7:0] b_reg;
  reg [1:0] op_sel_reg;
  reg       acc_en_reg;

  // --- ALU instance (XLEN=8 to fit TT single-byte IO) ---
  wire [7:0] alu_out;
  wire [7:0] acc_out;
  wire       zero_out;
  wire       overflow_out;

  op #(.XLEN(8)) alu_core (
      .clock   (clk),
      .reset   (~rst_n),
      .a       (a_reg),
      .b       (b_reg),
      .op_sel  (op_sel_reg),
      .acc_en  (acc_en_reg),
      .out     (alu_out),
      .acc     (acc_out),
      .zero    (zero_out),
      .overflow(overflow_out)
  );

  // --- register writes ---
  always @(posedge clk) begin
    if (!rst_n) begin
      a_reg      <= 8'h00;
      b_reg      <= 8'h00;
      op_sel_reg <= 2'b00;
      acc_en_reg <= 1'b0;
    end else begin
      acc_en_reg <= 1'b0;
      if (ena && write_en) begin
        case (cmd)
          CMD_WRITE_A:  a_reg      <= uio_in;
          CMD_WRITE_B:  b_reg      <= uio_in;
          CMD_CONTROL: begin
            op_sel_reg <= uio_in[1:0];
            acc_en_reg <= uio_in[2];
          end
          default: ;
        endcase
      end
    end
  end

  // --- output assignments ---
  wire status_read = (cmd == CMD_CONTROL) && !write_en;
  wire [7:0] read_word = read_acc ? acc_out : alu_out;

  assign uo_out  = (cmd == CMD_READ_OUT) ? read_word : 8'h00;
  assign uio_out = {overflow_out, zero_out, 4'b0000, op_sel_reg};
  assign uio_oe  = status_read ? 8'hff : 8'h00;

endmodule

`default_nettype wire
