// bitops (refactored): same function as bitops_gold.sv, restructured for
// timing. Leading zeros are found by halving the search window; population
// count is a balanced adder tree.
module bitops (
    input  logic        clk,
    input  logic        rst,
    input  logic        in_valid,
    input  logic [15:0] din,
    output logic        out_valid,
    output logic [4:0]  lzc,
    output logic [4:0]  pop
);

  // ---- leading-zero count: binary search over 8/4/2/1-bit windows ---------
  logic [15:0] w16;
  logic [7:0]  w8;
  logic [3:0]  w4;
  logic [1:0]  w2;
  logic        z8, z4, z2, z1;
  logic [4:0]  lzc_d;

  assign w16 = din;
  assign z8  = (w16[15:8] == 8'h00);
  assign w8  = z8 ? w16[7:0] : w16[15:8];
  assign z4  = (w8[7:4] == 4'h0);
  assign w4  = z4 ? w8[3:0] : w8[7:4];
  assign z2  = (w4[3:2] == 2'b00);
  assign w2  = z2 ? w4[1:0] : w4[3:2];
  assign z1  = !w2[1];
  assign lzc_d = (din == 16'h0000) ? 5'd16 : {1'b0, z8, z4, z2, z1};

  // ---- population count: 2-bit, 3-bit, 4-bit, 5-bit adder tree ------------
  logic [1:0] p2 [8];
  logic [2:0] p4 [4];
  logic [3:0] p8 [2];
  logic [4:0] pop_d;

  for (genvar i = 0; i < 8; i++) begin : g_p2
    assign p2[i] = {1'b0, din[2*i]} + {1'b0, din[2*i+1]};
  end
  for (genvar i = 0; i < 4; i++) begin : g_p4
    assign p4[i] = {1'b0, p2[2*i]} + {1'b0, p2[2*i+1]};
  end
  for (genvar i = 0; i < 2; i++) begin : g_p8
    assign p8[i] = {1'b0, p4[2*i]} + {1'b0, p4[2*i+1]};
  end
  assign pop_d = {1'b0, p8[0]} + {1'b0, p8[1]};

  always_ff @(posedge clk) begin
    if (rst) begin
      out_valid <= 1'b0;
      lzc       <= '0;
      pop       <= '0;
    end else begin
      out_valid <= in_valid;
      if (in_valid) begin
        lzc <= lzc_d;
        pop <= pop_d;
      end
    end
  end

endmodule
