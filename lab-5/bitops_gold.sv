// bitops (golden reference): registered leading-zero count and population count
// of a 16-bit word. Written for clarity, not speed.
//
// Specification
//   - When in_valid = 1 at a rising edge, the results for din appear on the
//     outputs one cycle later with out_valid = 1.
//   - lzc = number of leading zeros of din (16 when din == 0).
//   - pop = number of 1 bits in din.
//   - Synchronous, active-high reset clears out_valid and both results.
module bitops (
    input  logic        clk,
    input  logic        rst,
    input  logic        in_valid,
    input  logic [15:0] din,
    output logic        out_valid,
    output logic [4:0]  lzc,
    output logic [4:0]  pop
);

  logic [4:0] lzc_d, pop_d;

  always_comb begin
    lzc_d = 5'd16;
    for (int i = 0; i < 16; i++) if (din[i]) lzc_d = 5'(15 - i);
  end

  always_comb begin
    pop_d = '0;
    for (int i = 0; i < 16; i++) pop_d = pop_d + 5'(din[i]);
  end

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
