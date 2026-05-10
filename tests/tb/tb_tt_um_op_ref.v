// Testbench for tt_um_op_ref (TinyTapeout wrapper around example/op.v)
// --------------------------------------------------------------------
// Self-checking. Exercises the byte protocol:
//   WRITE_A=0x05, WRITE_B=0x03, CONTROL(op=ADD,acc_en=1) -> READ_OUT acc=0x08
//   then SUB, AND, XOR, and the zero flag path.
//
// Run with iverilog:
//   iverilog -g2012 -o /tmp/tb_op.vvp \
//     tests/tb/tb_tt_um_op_ref.v \
//     tests/designs/tt_um_op_ref.v \
//     example/op.v
//   vvp /tmp/tb_op.vvp

`timescale 1ns/1ps
`default_nettype none

module tb_tt_um_op_ref;

  reg        clk;
  reg        rst_n;
  reg        ena;
  reg  [7:0] ui_in;
  reg  [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  integer    errors = 0;

  // Command encoding (must match tt_um_op_ref.v)
  localparam [1:0] CMD_WRITE_A  = 2'b00;
  localparam [1:0] CMD_WRITE_B  = 2'b01;
  localparam [1:0] CMD_CONTROL  = 2'b10;
  localparam [1:0] CMD_READ_OUT = 2'b11;
  localparam [1:0] OP_ADD = 2'b00;
  localparam [1:0] OP_SUB = 2'b01;
  localparam [1:0] OP_AND = 2'b10;
  localparam [1:0] OP_XOR = 2'b11;

  // 100 MHz clock
  initial clk = 1'b0;
  always  #5 clk = ~clk;

  tt_um_op_ref dut (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // ---- Helpers ----
  task automatic do_idle;
    begin
      @(posedge clk);
      ui_in  <= 8'h00;
      uio_in <= 8'h00;
    end
  endtask

  // Issue a one-cycle command; ui_in[2] = write_en/read_acc, payload on uio_in.
  task automatic issue(input [1:0] cmd, input write_en, input [7:0] payload);
    begin
      @(posedge clk);
      ui_in  <= {cmd, 3'b000, write_en, 2'b00};
      uio_in <= payload;
      @(posedge clk);
      ui_in  <= 8'h00;
      uio_in <= 8'h00;
    end
  endtask

  // Read uo_out for the current cmd; return the captured byte.
  task automatic read_out(input read_acc, output [7:0] data);
    begin
      @(posedge clk);
      ui_in  <= {CMD_READ_OUT, 3'b000, read_acc, 2'b00};
      uio_in <= 8'h00;
      // uo_out is purely combinational from cmd + register state, so the
      // value is valid in the same cycle ui_in is driven; sample at next
      // negedge for stability.
      @(negedge clk);
      data = uo_out;
      @(posedge clk);
      ui_in <= 8'h00;
    end
  endtask

  task automatic check_eq8(input [7:0] got, input [7:0] exp,
                           input [255:0] msg);
    begin
      if (got !== exp) begin
        $display("FAIL [%0t] %0s: got=0x%02h exp=0x%02h", $time, msg, got, exp);
        errors = errors + 1;
      end else begin
        $display("PASS [%0t] %0s: 0x%02h", $time, msg, got);
      end
    end
  endtask

  // Write A and B, run an op, capture acc.
  task automatic run_op(input [7:0] a, input [7:0] b, input [1:0] op_sel,
                        output [7:0] acc_byte);
    begin
      issue(CMD_WRITE_A, 1'b1, a);
      issue(CMD_WRITE_B, 1'b1, b);
      // CONTROL: payload = {acc_en=1, op_sel[1:0]} on uio_in[2:0]
      issue(CMD_CONTROL, 1'b1, {5'b0, 1'b1, op_sel});
      // Two clocks: 1) op core registers alu_out and acc; 2) propagate
      @(posedge clk);
      @(posedge clk);
      read_out(1'b1, acc_byte);
    end
  endtask

  reg [7:0] r;
  initial begin
    $dumpfile("tb_tt_um_op_ref.vcd");
    $dumpvars(0, tb_tt_um_op_ref);

    ui_in  = 8'h00;
    uio_in = 8'h00;
    ena    = 1'b1;
    rst_n  = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // ADD: 5 + 3 = 8
    run_op(8'h05, 8'h03, OP_ADD, r);
    check_eq8(r, 8'h08, "ADD 5+3");

    // SUB: 9 - 4 = 5
    run_op(8'h09, 8'h04, OP_SUB, r);
    check_eq8(r, 8'h05, "SUB 9-4");

    // AND: 0xF0 & 0x3C = 0x30
    run_op(8'hF0, 8'h3C, OP_AND, r);
    check_eq8(r, 8'h30, "AND F0&3C");

    // XOR: 0xAA ^ 0x55 = 0xFF
    run_op(8'hAA, 8'h55, OP_XOR, r);
    check_eq8(r, 8'hFF, "XOR AA^55");

    // Zero flag via ADD 0+0 = 0; check status byte
    run_op(8'h00, 8'h00, OP_ADD, r);
    check_eq8(r, 8'h00, "ADD 0+0 -> acc=0");
    // After CONTROL, status read returns op_sel_reg in uio_out[1:0]
    // and zero flag in uio_out[6].
    @(posedge clk);
    ui_in <= {CMD_CONTROL, 6'b0};   // CONTROL with write_en=0 -> status read
    @(negedge clk);
    if (uio_oe !== 8'hFF) begin
      $display("FAIL: status read uio_oe=0x%02h (exp 0xFF)", uio_oe);
      errors = errors + 1;
    end
    if (uio_out[6] !== 1'b1) begin
      $display("FAIL: zero flag low after 0+0; uio_out=0x%02h", uio_out);
      errors = errors + 1;
    end else begin
      $display("PASS zero-flag set after ADD 0+0");
    end
    @(posedge clk);
    ui_in <= 8'h00;

    // Final summary
    repeat (4) @(posedge clk);
    if (errors == 0) begin
      $display("==== tb_tt_um_op_ref: ALL TESTS PASSED ====");
      $finish;
    end else begin
      $display("==== tb_tt_um_op_ref: %0d FAILURE(S) ====", errors);
      $fatal(1);
    end
  end

  // Watchdog
  initial begin
    #100000;
    $display("FAIL: timeout");
    $fatal(1);
  end

endmodule

`default_nettype wire
