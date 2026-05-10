// Reference TinyTapeout wrapper for rapt (RISC-V SoC, AXI4 master)
// -----------------------------------------------------------------
// This is a FUNCTIONAL reference wrapper showing how to bridge a
// CPU-with-AXI-master interface to TinyTapeout IO.  The default flow
// uses an auto-generated evaluation wrapper; this file is for reference
// and correctness verification only.
//
// To use this wrapper explicitly:
//
//   make tt-preflight \
//     RTL_FILES="result/sky130hd-rapt-50MHz/rapt.netlist.src.v \
//                tests/designs/axi4_sram_slave.v \
//                tests/designs/tt_um_rapt_axi_ref.v" \
//     TT_NATIVE=1 \
//     DESIGN=tt_um_rapt_axi_ref \
//     PLATFORM=sky130hd
//
// The internal AXI4 SRAM slave is now factored out into
//   tests/designs/axi4_sram_slave.v
// and exercised by a standalone (rapt-free) testbench at
//   tests/tb/tb_axi4_sram_slave.v
//
// Architecture:
//   rapt is an AXI4 master (CPU core). This wrapper provides a small
//   internal SRAM slave (MEM_DEPTH words of 32 bits) so rapt can fetch
//   and execute instructions.  A minimal NOP-sled + JAL-to-self loop is
//   pre-loaded; set MEM_INIT_FILE to a hex image for a real program.
//
//   The full AXI bus runs internally between rapt and the SRAM.  The
//   TinyTapeout IO pins carry JTAG pass-through plus AXI bus-activity
//   status.  This is enough to observe whether the CPU is alive and
//   accessing memory, and to connect an external JTAG debugger.
//
// TT IO protocol:
//   ui_in[0]    -> jtag_tms
//   ui_in[1]    -> jtag_tdi
//   ui_in[2]    -> jtag_trst_n (active-low, pass-through)
//   ui_in[3]    -> io_interrupt
//   ui_in[4]    -> ext_irq_i[1] (first external IRQ)
//   ui_in[5]    -> hold_reset   (1 = assert CPU reset independently of rst_n)
//   ui_in[7:6]  -> reserved
//   uio_in      -> reserved
//
//   uo_out[0]   <- jtag_tdo
//   uo_out[1]   <- io_master_awvalid (CPU issuing AXI write address)
//   uo_out[2]   <- io_master_wvalid  (CPU sending AXI write data)
//   uo_out[3]   <- io_master_arvalid (CPU issuing AXI read address)
//   uo_out[4]   <- s_rvalid          (SRAM returning read data)
//   uo_out[5]   <- s_bvalid          (SRAM returning write response)
//   uo_out[6]   <- axi_err           (non-OKAY RRESP or BRESP observed)
//   uo_out[7]   -> 0 (reserved)
//   uio_out     <- io_master_araddr[7:0] (lower byte of current read address)
//   uio_oe      =  8'hff (always output)
//
// AXI4 slave notes:
//   - One outstanding read burst and one outstanding write burst at a time.
//   - INCR and FIXED burst types supported; WRAP is treated as INCR.
//   - Out-of-range addresses return 0 on reads and are silently dropped on
//     writes.
//   - Not pipelined; throughput is one beat per two cycles worst case.
//
// Area note:
//   MEM_DEPTH=64 (256-byte SRAM) is larger than a typical TT 1x1 tile
//   budget.  Reduce MEM_DEPTH or replace with a hard macro for tape-out.

`default_nettype none

module tt_um_rapt_axi_ref #(
    parameter integer MEM_DEPTH     = 64,  // number of 32-bit words in SRAM
    parameter         MEM_INIT_FILE = ""   // optional $readmemh hex file
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ------------------------------------------------------------------
  // IO decode
  // ------------------------------------------------------------------
  wire jtag_tms_in    = ui_in[0];
  wire jtag_tdi_in    = ui_in[1];
  wire jtag_trst_n_in = ui_in[2];
  wire io_intr_in     = ui_in[3];
  wire ext_irq1_in    = ui_in[4];
  wire hold_reset     = ui_in[5];

  wire cpu_reset      = ~rst_n | hold_reset;

  // rapt ext_irq_i is [31:1] (1-indexed, bit-1 = IRQ #1)
  wire [31:1] ext_irq_i_w = {30'b0, ext_irq1_in};

  // ------------------------------------------------------------------
  // AXI4 wire declarations  (rapt = master, SRAM = slave)
  // ------------------------------------------------------------------

  // AR channel (master -> slave)
  wire [31:0] m_araddr;
  wire        m_arvalid;
  wire [1:0]  m_arburst;
  wire [2:0]  m_arsize;
  wire [7:0]  m_arlen;
  wire [3:0]  m_arid;
  // AR channel (slave -> master)
  wire        m_arready;

  // R channel (slave -> master)
  wire [31:0] m_rdata;
  wire        m_rvalid;
  wire [3:0]  m_rid;
  wire        m_rlast;
  wire [1:0]  m_rresp;
  // R channel (master -> slave)
  wire        m_rready;

  // AW channel (master -> slave)
  wire [31:0] m_awaddr;
  wire        m_awvalid;
  wire [1:0]  m_awburst;
  wire [2:0]  m_awsize;
  wire [7:0]  m_awlen;
  wire [3:0]  m_awid;
  // AW channel (slave -> master)
  wire        m_awready;

  // W channel (master -> slave)
  wire [31:0] m_wdata;
  wire        m_wvalid;
  wire        m_wlast;
  wire [3:0]  m_wstrb;
  // W channel (slave -> master)
  wire        m_wready;

  // B channel (slave -> master)
  wire [3:0]  m_bid;
  wire [1:0]  m_bresp;
  wire        m_bvalid;
  // B channel (master -> slave)
  wire        m_bready;

  wire        jtag_tdo_w;

  // ------------------------------------------------------------------
  // rapt  (RISC-V SoC, AXI4 master)
  // ------------------------------------------------------------------
  rapt cpu (
      .reset              (cpu_reset),
      .clock              (clk),
      // AR
      .io_master_araddr   (m_araddr),
      .io_master_arvalid  (m_arvalid),
      .io_master_arready  (m_arready),
      .io_master_arburst  (m_arburst),
      .io_master_arsize   (m_arsize),
      .io_master_arlen    (m_arlen),
      .io_master_arid     (m_arid),
      // R
      .io_master_rdata    (m_rdata),
      .io_master_rvalid   (m_rvalid),
      .io_master_rready   (m_rready),
      .io_master_rid      (m_rid),
      .io_master_rlast    (m_rlast),
      .io_master_rresp    (m_rresp),
      // AW
      .io_master_awaddr   (m_awaddr),
      .io_master_awvalid  (m_awvalid),
      .io_master_awready  (m_awready),
      .io_master_awburst  (m_awburst),
      .io_master_awsize   (m_awsize),
      .io_master_awlen    (m_awlen),
      .io_master_awid     (m_awid),
      // W
      .io_master_wdata    (m_wdata),
      .io_master_wvalid   (m_wvalid),
      .io_master_wready   (m_wready),
      .io_master_wlast    (m_wlast),
      .io_master_wstrb    (m_wstrb),
      // B
      .io_master_bid      (m_bid),
      .io_master_bresp    (m_bresp),
      .io_master_bvalid   (m_bvalid),
      .io_master_bready   (m_bready),
      // Misc
      .io_interrupt       (io_intr_in),
      .ext_irq_i          (ext_irq_i_w),
      .jtag_trst_n        (jtag_trst_n_in),
      .jtag_tms           (jtag_tms_in),
      .jtag_tdi           (jtag_tdi_in),
      .jtag_tdo           (jtag_tdo_w)
  );

  // ------------------------------------------------------------------
  // Internal SRAM  (AXI4 slave, MEM_DEPTH x 32-bit words)
  //
  // The AXI4 slave logic is in its own module (axi4_sram_slave) so it
  // can be exercised standalone (without rapt) by tb_axi4_sram_slave.v.
  // The internal seed memory ("NOP sled + JAL self-loop at reset
  // vector") is preserved by passing a default MEM_INIT pattern: when
  // no MEM_INIT_FILE is given the slave initialises to all-zero, then
  // we overwrite location 0 in this wrapper using $deposit-style logic
  // is not portable; instead, the slave accepts an INIT_FILE and the
  // wrapper hands one (or zero) through.
  // ------------------------------------------------------------------
  axi4_sram_slave #(
      .MEM_DEPTH    (MEM_DEPTH),
      .MEM_INIT_FILE(MEM_INIT_FILE),
      .RESET_NOP    (1'b1)
  ) u_sram (
      .clk      (clk),
      .rst      (cpu_reset),
      // AR
      .s_araddr (m_araddr),
      .s_arvalid(m_arvalid),
      .s_arready(m_arready),
      .s_arburst(m_arburst),
      .s_arsize (m_arsize),
      .s_arlen  (m_arlen),
      .s_arid   (m_arid),
      // R
      .s_rdata  (m_rdata),
      .s_rvalid (m_rvalid),
      .s_rready (m_rready),
      .s_rid    (m_rid),
      .s_rlast  (m_rlast),
      .s_rresp  (m_rresp),
      // AW
      .s_awaddr (m_awaddr),
      .s_awvalid(m_awvalid),
      .s_awready(m_awready),
      .s_awburst(m_awburst),
      .s_awsize (m_awsize),
      .s_awlen  (m_awlen),
      .s_awid   (m_awid),
      // W
      .s_wdata  (m_wdata),
      .s_wvalid (m_wvalid),
      .s_wready (m_wready),
      .s_wlast  (m_wlast),
      .s_wstrb  (m_wstrb),
      // B
      .s_bid    (m_bid),
      .s_bresp  (m_bresp),
      .s_bvalid (m_bvalid),
      .s_bready (m_bready)
  );

  // The signals s_arready/s_rdata/... below were re-driven by the
  // factored-out slave above; the legacy in-place FSM has been
  // removed. The TT IO outputs at the bottom alias the slave's
  // valid/ready strobes via the `m_*` wires.

  // ---- Legacy FSM (removed) ----
  // The read-FSM and write-FSM that used to live here have been
  // replaced by the axi4_sram_slave instantiation above.

  // ------------------------------------------------------------------
  // TT IO outputs
  // ------------------------------------------------------------------
  wire axi_err = (m_rvalid && m_rresp != 2'b00) |
                 (m_bvalid && m_bresp != 2'b00);

  assign uo_out  = {1'b0, axi_err, m_bvalid, m_rvalid,
                    m_arvalid, m_wvalid, m_awvalid, jtag_tdo_w};
  assign uio_out = m_araddr[7:0];
  assign uio_oe  = 8'hff;

endmodule

`default_nettype wire
