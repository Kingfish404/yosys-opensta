module op (
    input  wire [2:0] a,
    input  wire [2:0] b,
    output wire [2:0] out
);
  assign out = a & b;
endmodule
