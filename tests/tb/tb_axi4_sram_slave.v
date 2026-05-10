// Standalone AXI4 SRAM slave testbench (no rapt dependency)
// ---------------------------------------------------------
// Drives a synthetic AXI4 master against axi4_sram_slave to verify:
//   * single-beat write + read-back (RRESP/BRESP = OKAY)
//   * INCR burst write (len=4) + INCR burst read-back
//   * byte-strobe partial write
//   * out-of-range read returns 0
//   * RESET_NOP=1 seed: word 0 = 0x0000_006F (JAL self-loop)
//
// Run:
//   iverilog -g2012 -o /tmp/tb_axi.vvp \
//     tests/tb/tb_axi4_sram_slave.v \
//     tests/designs/axi4_sram_slave.v
//   vvp /tmp/tb_axi.vvp

`timescale 1ns/1ps
`default_nettype none

module tb_axi4_sram_slave;

  // ---- DUT IO ----
  reg         clk;
  reg         rst;

  reg  [31:0] s_araddr;
  reg         s_arvalid;
  wire        s_arready;
  reg  [1:0]  s_arburst;
  reg  [2:0]  s_arsize;
  reg  [7:0]  s_arlen;
  reg  [3:0]  s_arid;

  wire [31:0] s_rdata;
  wire        s_rvalid;
  reg         s_rready;
  wire [3:0]  s_rid;
  wire        s_rlast;
  wire [1:0]  s_rresp;

  reg  [31:0] s_awaddr;
  reg         s_awvalid;
  wire        s_awready;
  reg  [1:0]  s_awburst;
  reg  [2:0]  s_awsize;
  reg  [7:0]  s_awlen;
  reg  [3:0]  s_awid;

  reg  [31:0] s_wdata;
  reg         s_wvalid;
  wire        s_wready;
  reg         s_wlast;
  reg  [3:0]  s_wstrb;

  wire [3:0]  s_bid;
  wire [1:0]  s_bresp;
  wire        s_bvalid;
  reg         s_bready;

  integer     errors = 0;

  // 100 MHz clock
  initial clk = 1'b0;
  always  #5 clk = ~clk;

  axi4_sram_slave #(
      .MEM_DEPTH    (16),       // 64 bytes
      .MEM_INIT_FILE(""),
      .RESET_NOP    (1'b1)
  ) dut (
      .clk      (clk),
      .rst      (rst),

      .s_araddr (s_araddr),
      .s_arvalid(s_arvalid),
      .s_arready(s_arready),
      .s_arburst(s_arburst),
      .s_arsize (s_arsize),
      .s_arlen  (s_arlen),
      .s_arid   (s_arid),

      .s_rdata  (s_rdata),
      .s_rvalid (s_rvalid),
      .s_rready (s_rready),
      .s_rid    (s_rid),
      .s_rlast  (s_rlast),
      .s_rresp  (s_rresp),

      .s_awaddr (s_awaddr),
      .s_awvalid(s_awvalid),
      .s_awready(s_awready),
      .s_awburst(s_awburst),
      .s_awsize (s_awsize),
      .s_awlen  (s_awlen),
      .s_awid   (s_awid),

      .s_wdata  (s_wdata),
      .s_wvalid (s_wvalid),
      .s_wready (s_wready),
      .s_wlast  (s_wlast),
      .s_wstrb  (s_wstrb),

      .s_bid    (s_bid),
      .s_bresp  (s_bresp),
      .s_bvalid (s_bvalid),
      .s_bready (s_bready)
  );

  // ---- Helpers ----
  task automatic check32(input [31:0] got, input [31:0] exp,
                         input [255:0] msg);
    begin
      if (got !== exp) begin
        $display("FAIL [%0t] %0s: got=0x%08h exp=0x%08h", $time, msg, got, exp);
        errors = errors + 1;
      end else begin
        $display("PASS [%0t] %0s: 0x%08h", $time, msg, got);
      end
    end
  endtask

  task automatic check_resp(input [1:0] got, input [255:0] msg);
    begin
      if (got !== 2'b00) begin
        $display("FAIL [%0t] %0s: resp=%0d (exp OKAY)", $time, msg, got);
        errors = errors + 1;
      end
    end
  endtask

  // Single-beat AXI write
  task automatic axi_write_single(input [31:0] addr, input [31:0] data,
                                  input [3:0] strb, input [3:0] id);
    begin
      @(posedge clk);
      s_awaddr  <= addr;
      s_awid    <= id;
      s_awlen   <= 8'h00;
      s_awsize  <= 3'h2;
      s_awburst <= 2'b01;     // INCR
      s_awvalid <= 1'b1;
      do @(posedge clk); while (!s_awready);
      s_awvalid <= 1'b0;

      s_wdata  <= data;
      s_wstrb  <= strb;
      s_wlast  <= 1'b1;
      s_wvalid <= 1'b1;
      do @(posedge clk); while (!s_wready);
      s_wvalid <= 1'b0;
      s_wlast  <= 1'b0;

      s_bready <= 1'b1;
      do @(posedge clk); while (!s_bvalid);
      check_resp(s_bresp, "BRESP single");
      if (s_bid !== id) begin
        $display("FAIL: bid mismatch got=%0d exp=%0d", s_bid, id);
        errors = errors + 1;
      end
      @(posedge clk);
      s_bready <= 1'b0;
    end
  endtask

  // Single-beat AXI read
  task automatic axi_read_single(input [31:0] addr, input [3:0] id,
                                 output [31:0] data);
    begin
      @(posedge clk);
      s_araddr  <= addr;
      s_arid    <= id;
      s_arlen   <= 8'h00;
      s_arsize  <= 3'h2;
      s_arburst <= 2'b01;
      s_arvalid <= 1'b1;
      do @(posedge clk); while (!s_arready);
      s_arvalid <= 1'b0;

      s_rready <= 1'b1;
      do @(posedge clk); while (!s_rvalid);
      data = s_rdata;
      check_resp(s_rresp, "RRESP single");
      if (!s_rlast) begin
        $display("FAIL: rlast not asserted on single-beat read");
        errors = errors + 1;
      end
      if (s_rid !== id) begin
        $display("FAIL: rid mismatch got=%0d exp=%0d", s_rid, id);
        errors = errors + 1;
      end
      @(posedge clk);
      s_rready <= 1'b0;
    end
  endtask

  // INCR burst write of N (1..256) beats; data[k] -> mem[(addr/4)+k]
  task automatic axi_write_burst(input [31:0] addr, input integer n,
                                 input [3:0] id);
    integer k;
    begin
      @(posedge clk);
      s_awaddr  <= addr;
      s_awid    <= id;
      s_awlen   <= n - 1;
      s_awsize  <= 3'h2;
      s_awburst <= 2'b01;
      s_awvalid <= 1'b1;
      do @(posedge clk); while (!s_awready);
      s_awvalid <= 1'b0;

      for (k = 0; k < n; k = k + 1) begin
        s_wdata  <= 32'hA000_0000 | k;     // distinctive pattern
        s_wstrb  <= 4'hF;
        s_wlast  <= (k == n - 1);
        s_wvalid <= 1'b1;
        do @(posedge clk); while (!s_wready);
      end
      s_wvalid <= 1'b0;
      s_wlast  <= 1'b0;

      s_bready <= 1'b1;
      do @(posedge clk); while (!s_bvalid);
      check_resp(s_bresp, "BRESP burst");
      @(posedge clk);
      s_bready <= 1'b0;
    end
  endtask

  // INCR burst read of N beats; check pattern matches axi_write_burst.
  task automatic axi_read_burst_check(input [31:0] addr, input integer n,
                                      input [3:0] id);
    integer k;
    reg     last_seen;
    begin
      last_seen = 1'b0;
      @(posedge clk);
      s_araddr  <= addr;
      s_arid    <= id;
      s_arlen   <= n - 1;
      s_arsize  <= 3'h2;
      s_arburst <= 2'b01;
      s_arvalid <= 1'b1;
      do @(posedge clk); while (!s_arready);
      s_arvalid <= 1'b0;

      s_rready <= 1'b1;
      for (k = 0; k < n; k = k + 1) begin
        do @(posedge clk); while (!s_rvalid);
        check32(s_rdata, 32'hA000_0000 | k, "burst beat");
        check_resp(s_rresp, "RRESP burst");
        if (k == n - 1) last_seen = s_rlast;
        else if (s_rlast) begin
          $display("FAIL: rlast asserted early at beat %0d", k);
          errors = errors + 1;
        end
      end
      if (!last_seen) begin
        $display("FAIL: rlast missed on final beat");
        errors = errors + 1;
      end
      @(posedge clk);
      s_rready <= 1'b0;
    end
  endtask

  reg [31:0] rd;
  initial begin
    $dumpfile("tb_axi4_sram_slave.vcd");
    $dumpvars(0, tb_axi4_sram_slave);

    s_araddr  = 0; s_arvalid = 0; s_arburst = 0; s_arsize = 0;
    s_arlen   = 0; s_arid = 0; s_rready = 0;
    s_awaddr  = 0; s_awvalid = 0; s_awburst = 0; s_awsize = 0;
    s_awlen   = 0; s_awid = 0;
    s_wdata   = 0; s_wvalid = 0; s_wlast = 0; s_wstrb = 0;
    s_bready  = 0;

    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    // 1) Verify RESET_NOP seed: word 0 = 0x0000_006F (JAL x0,0)
    axi_read_single(32'h00, 4'h1, rd);
    check32(rd, 32'h0000_006F, "RESET_NOP seed @0");

    // 2) Verify a NOP-seeded interior word
    axi_read_single(32'h08, 4'h2, rd);
    check32(rd, 32'h0000_0013, "RESET_NOP NOP @8");

    // 3) Single write + read-back (full word)
    axi_write_single(32'h10, 32'hDEAD_BEEF, 4'hF, 4'h3);
    axi_read_single(32'h10, 4'h4, rd);
    check32(rd, 32'hDEAD_BEEF, "single rw @0x10");

    // 4) Byte-strobe partial write: only update bits [15:0]
    axi_write_single(32'h14, 32'h1122_3344, 4'hF, 4'h5);
    axi_write_single(32'h14, 32'hFFFF_AAAA, 4'b0011, 4'h6);
    axi_read_single (32'h14, 4'h7, rd);
    check32(rd, 32'h1122_AAAA, "byte-strobe wlow");

    // 5) Burst write+read (4 beats) starting at 0x20 (mem index 8..11)
    axi_write_burst(32'h20, 4, 4'h8);
    axi_read_burst_check(32'h20, 4, 4'h9);

    // 6) Out-of-range read returns 0 (MEM_DEPTH=16 -> 64 B)
    axi_read_single(32'h40, 4'hA, rd);
    check32(rd, 32'h0000_0000, "OOR read -> 0");

    // 7) Two back-to-back single writes with different IDs to ensure
    //    BID is returned correctly.
    axi_write_single(32'h0C, 32'h1111_2222, 4'hF, 4'hC);
    axi_write_single(32'h0C, 32'h3333_4444, 4'hF, 4'hD);
    axi_read_single (32'h0C, 4'hE, rd);
    check32(rd, 32'h3333_4444, "back-to-back writes last wins");

    repeat (4) @(posedge clk);
    if (errors == 0) begin
      $display("==== tb_axi4_sram_slave: ALL TESTS PASSED ====");
      $finish;
    end else begin
      $display("==== tb_axi4_sram_slave: %0d FAILURE(S) ====", errors);
      $fatal(1);
    end
  end

  // Watchdog
  initial begin
    #200000;
    $display("FAIL: timeout");
    $fatal(1);
  end

endmodule

`default_nettype wire
