// 32-bit counter with load, enable, direction, and comparator
// Large enough for PnR smoke testing (~500+ cells after synthesis)
module counter (
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    input  wire        load,
    input  wire        up_down,    // 1=count up, 0=count down
    input  wire [31:0] load_val,
    input  wire [31:0] threshold,
    output reg  [31:0] count,
    output reg         zero,
    output reg         overflow,
    output reg         thresh_hit
);
  reg [32:0] next_val;

  always @(posedge clock) begin
    if (reset) begin
      count      <= 32'b0;
      zero       <= 1'b1;
      overflow   <= 1'b0;
      thresh_hit <= 1'b0;
    end else if (load) begin
      count      <= load_val;
      zero       <= (load_val == 32'b0);
      overflow   <= 1'b0;
      thresh_hit <= (load_val >= threshold);
    end else if (enable) begin
      if (up_down) next_val = {1'b0, count} + 33'b1;
      else next_val = {1'b0, count} - 33'b1;
      count      <= next_val[31:0];
      zero       <= (next_val[31:0] == 32'b0);
      overflow   <= next_val[32];
      thresh_hit <= (next_val[31:0] >= threshold);
    end
  end
endmodule
