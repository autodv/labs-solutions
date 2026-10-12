// rr_arbiter: round-robin arbiter for N requesters.
//
// Specification
//   - req[i] = 1 means requester i wants the resource this cycle.
//   - gnt is combinational from req and the priority pointer: at most one bit
//     is set, only a requesting bit can be set, and if any req bit is set,
//     exactly one gnt bit is set (work conserving).
//   - Priority rotates: the search for a winner starts at index ptr and wraps.
//     After requester k is granted, ptr moves to k + 1 (mod N), so k has the
//     lowest priority next time.
//   - Synchronous, active-high reset sets ptr to 0.
//   - Fairness: a requester that keeps req high is granted within N cycles.
module rr_arbiter #(
    parameter int N = 4
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic [N-1:0]         req,
    output logic [N-1:0]         gnt
);

  localparam int PW = $clog2(N);

  logic [PW-1:0] ptr;

  // Search for the first requester at or after ptr, wrapping around.
  always_comb begin
    gnt = '0;
    for (int off = N - 1; off >= 0; off--) begin
      if (req[(ptr + PW'(off)) % N]) begin
        gnt = '0;
        gnt[(ptr + PW'(off)) % N] = 1'b1;
      end
    end
  end

  // Index of the granted requester.
  logic [PW-1:0] gnt_idx;
  always_comb begin
    gnt_idx = '0;
    for (int i = 0; i < N; i++) if (gnt[i]) gnt_idx = PW'(i);
  end

  always_ff @(posedge clk) begin
    if (rst) ptr <= '0;
    else if (|gnt) ptr <= (gnt_idx == PW'(N - 1)) ? '0 : gnt_idx + 1'b1;
  end

endmodule
