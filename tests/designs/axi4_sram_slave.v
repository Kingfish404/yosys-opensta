// Standalone AXI4 SRAM slave (rapt-free)
// ---------------------------------------
// Word-addressed (32-bit) SRAM AXI4 slave with byte-enable writes.
// One outstanding read burst and one outstanding write burst at a time.
// INCR and FIXED burst types supported; WRAP is treated as INCR.
// Out-of-range reads return 0; out-of-range writes are silently dropped.
// Read response RRESP and write response BRESP are always OKAY (2'b00).
//
// Optional reset-time seed:
//   RESET_NOP=1  -- fill memory with RV32I `addi x0,x0,0` and place a
//                  `jal x0, 0` self-loop at word 0 (matches the legacy
//                  rapt boot pattern).
//   MEM_INIT_FILE -- Verilog $readmemh hex file. Loaded after the NOP
//                  seed if both are set.
//
// All AXI signal names use the `s_` prefix (slave-facing).

`default_nettype none

module axi4_sram_slave #(
    parameter integer MEM_DEPTH     = 64,    // 32-bit words
    parameter         MEM_INIT_FILE = "",    // optional $readmemh image
    parameter         RESET_NOP     = 1'b0   // seed RV32 NOP-sled + JAL@0
) (
    input  wire        clk,
    input  wire        rst,                  // synchronous, active-high

    // AR channel
    input  wire [31:0] s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    input  wire [1:0]  s_arburst,
    input  wire [2:0]  s_arsize,
    input  wire [7:0]  s_arlen,
    input  wire [3:0]  s_arid,

    // R channel
    output wire [31:0] s_rdata,
    output wire        s_rvalid,
    input  wire        s_rready,
    output wire [3:0]  s_rid,
    output wire        s_rlast,
    output wire [1:0]  s_rresp,

    // AW channel
    input  wire [31:0] s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [1:0]  s_awburst,
    input  wire [2:0]  s_awsize,
    input  wire [7:0]  s_awlen,
    input  wire [3:0]  s_awid,

    // W channel
    input  wire [31:0] s_wdata,
    input  wire        s_wvalid,
    output wire        s_wready,
    input  wire        s_wlast,
    input  wire [3:0]  s_wstrb,

    // B channel
    output wire [3:0]  s_bid,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready
);

  // Suppress "unused" lint for AXI fields the slave does not interpret.
  /* verilator lint_off UNUSED */
  wire _unused_ok = &{1'b0, s_arsize, s_awsize, 1'b0};
  /* verilator lint_on UNUSED */

  localparam [31:0] MEM_BYTE_SIZE = MEM_DEPTH * 4;

  reg [31:0] mem [0:MEM_DEPTH-1];

  integer ii;
  initial begin
    for (ii = 0; ii < MEM_DEPTH; ii = ii + 1)
      mem[ii] = 32'h0000_0000;
    if (RESET_NOP) begin
      for (ii = 0; ii < MEM_DEPTH; ii = ii + 1)
        mem[ii] = 32'h0000_0013;        // ADDI x0, x0, 0  (NOP)
      mem[0] = 32'h0000_006F;            // JAL  x0, 0      (self-loop)
    end
    if (MEM_INIT_FILE != "")
      $readmemh(MEM_INIT_FILE, mem);
  end

  function automatic [31:0] sram_read;
    input [31:0] baddr;
    sram_read = (baddr < MEM_BYTE_SIZE) ? mem[baddr[31:2]] : 32'h0;
  endfunction

  // =============== Read FSM ===============
  localparam RS_IDLE  = 1'b0;
  localparam RS_BURST = 1'b1;

  reg        rs_state;
  reg [7:0]  r_cnt;
  reg [31:0] r_addr;
  reg [3:0]  r_id;
  reg [1:0]  r_burst;

  reg        r_arready;
  reg [31:0] r_rdata;
  reg        r_rvalid;
  reg        r_rlast;
  reg [3:0]  r_rid;
  reg [1:0]  r_rresp;

  wire [31:0] r_next_addr = (r_burst != 2'b00) ? r_addr + 32'd4 : r_addr;

  always @(posedge clk) begin
    if (rst) begin
      rs_state  <= RS_IDLE;
      r_arready <= 1'b0;
      r_rvalid  <= 1'b0;
      r_rlast   <= 1'b0;
      r_rid     <= 4'h0;
      r_rresp   <= 2'b00;
      r_cnt     <= 8'h0;
      r_addr    <= 32'h0;
      r_id      <= 4'h0;
      r_burst   <= 2'b00;
    end else case (rs_state)
      RS_IDLE: begin
        r_arready <= 1'b1;
        r_rvalid  <= 1'b0;
        if (s_arvalid && r_arready) begin
          r_arready <= 1'b0;
          r_addr    <= s_araddr;
          r_id      <= s_arid;
          r_burst   <= s_arburst;
          r_cnt     <= s_arlen;
          r_rdata   <= sram_read(s_araddr);
          r_rid     <= s_arid;
          r_rresp   <= 2'b00;
          r_rlast   <= (s_arlen == 8'h0);
          r_rvalid  <= 1'b1;
          rs_state  <= RS_BURST;
        end
      end
      RS_BURST: begin
        if (s_rready && r_rvalid) begin
          if (r_cnt == 8'h0) begin
            r_rvalid <= 1'b0;
            r_rlast  <= 1'b0;
            rs_state <= RS_IDLE;
          end else begin
            r_cnt    <= r_cnt - 8'h1;
            r_addr   <= r_next_addr;
            r_rdata  <= sram_read(r_next_addr);
            r_rid    <= r_id;
            r_rresp  <= 2'b00;
            r_rlast  <= (r_cnt == 8'h1);
            r_rvalid <= 1'b1;
          end
        end
      end
    endcase
  end

  assign s_arready = r_arready;
  assign s_rdata   = r_rdata;
  assign s_rvalid  = r_rvalid;
  assign s_rlast   = r_rlast;
  assign s_rid     = r_rid;
  assign s_rresp   = r_rresp;

  // =============== Write FSM ===============
  localparam WS_IDLE = 2'd0;
  localparam WS_DATA = 2'd1;
  localparam WS_RESP = 2'd2;

  reg [1:0]  ws_state;
  reg [31:0] w_addr;
  reg [3:0]  w_id;
  reg [1:0]  w_burst;

  reg        w_awready;
  reg        w_wready;
  reg        w_bvalid;
  reg [3:0]  w_bid;
  reg [1:0]  w_bresp;

  always @(posedge clk) begin
    if (rst) begin
      ws_state  <= WS_IDLE;
      w_awready <= 1'b0;
      w_wready  <= 1'b0;
      w_bvalid  <= 1'b0;
      w_bid     <= 4'h0;
      w_bresp   <= 2'b00;
      w_addr    <= 32'h0;
      w_id      <= 4'h0;
      w_burst   <= 2'b00;
    end else case (ws_state)
      WS_IDLE: begin
        w_bvalid  <= 1'b0;
        w_awready <= 1'b1;
        w_wready  <= 1'b0;
        if (s_awvalid && w_awready) begin
          w_awready <= 1'b0;
          w_addr    <= s_awaddr;
          w_id      <= s_awid;
          w_burst   <= s_awburst;
          ws_state  <= WS_DATA;
        end
      end
      WS_DATA: begin
        w_wready <= 1'b1;
        if (s_wvalid && w_wready) begin
          if (w_addr < MEM_BYTE_SIZE) begin
            if (s_wstrb[0]) mem[w_addr[31:2]][ 7: 0] <= s_wdata[ 7: 0];
            if (s_wstrb[1]) mem[w_addr[31:2]][15: 8] <= s_wdata[15: 8];
            if (s_wstrb[2]) mem[w_addr[31:2]][23:16] <= s_wdata[23:16];
            if (s_wstrb[3]) mem[w_addr[31:2]][31:24] <= s_wdata[31:24];
          end
          if (s_wlast) begin
            w_wready <= 1'b0;
            ws_state <= WS_RESP;
          end else begin
            // INCR advances by 4 bytes; FIXED stays put
            if (w_burst != 2'b00)
              w_addr <= w_addr + 32'd4;
          end
        end
      end
      WS_RESP: begin
        // Drive BVALID and hold until master acknowledges with BREADY.
        // Guard the consume on `w_bvalid` so a master that pre-asserts
        // BREADY before the slave raises BVALID does not lose the
        // response (NBA-ordering hazard if we tested s_bready alone).
        w_bvalid <= 1'b1;
        w_bresp  <= 2'b00;
        w_bid    <= w_id;
        if (w_bvalid && s_bready) begin
          w_bvalid <= 1'b0;
          ws_state <= WS_IDLE;
        end
      end
    endcase
  end

  assign s_awready = w_awready;
  assign s_wready  = w_wready;
  assign s_bvalid  = w_bvalid;
  assign s_bid     = w_bid;
  assign s_bresp   = w_bresp;

endmodule

`default_nettype wire
