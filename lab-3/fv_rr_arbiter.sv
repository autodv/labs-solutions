// fv_rr_arbiter: formal testbench for rr_arbiter.
//
// Per-requester properties live in a generate loop (g_req). Each copy gets its
// own hierarchical name, such as g_req[2].a_name, so a failure names the
// requester. A labeled assertion inside a plain procedural for loop would give
// every copy the same name, which Yosys rejects.
module fv_rr_arbiter (
    input logic       clk,
    input logic       rst,
    input logic [3:0] req
);

  localparam int N = 4;

  logic [N-1:0] gnt;

  rr_arbiter #(.N(N)) dut (.*);

  logic f_past_valid = 1'b0;
  always_ff @(posedge clk) f_past_valid <= 1'b1;

  always_comb if (!f_past_valid) m_reset_first: assume (rst);

  // ---------------------------------------------------------------------------
  // Provided assertion: at most one grant.
  //   SVA: a_onehot0: assert property (@(posedge clk) disable iff (rst) $onehot0(gnt));
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid && !rst) a_onehot0: assert ($onehot0(gnt));

  // ---------------------------------------------------------------------------
  // Task 1: grants go only to requesters, and nobody waits while it is free.
  //   SVA: a_gnt_has_req:     assert property (@(posedge clk) disable iff (rst) (gnt & ~req) == 0);
  //   SVA: a_work_conserving: assert property (@(posedge clk) disable iff (rst) |req |-> |gnt);
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid && !rst) a_gnt_has_req:     assert ((gnt & ~req) == '0);
  always_comb if (f_past_valid && !rst) a_work_conserving: assert (!(|req) || (|gnt));

  for (genvar i = 0; i < N; i++) begin : g_req
    // -------------------------------------------------------------------------
    // Task 2: requesters keep asking until served (environment assumption).
    //   SVA: m_hold: assume property (@(posedge clk) disable iff (rst)
    //          req[i] && !gnt[i] |=> req[i]);
    // -------------------------------------------------------------------------
    always_ff @(posedge clk)
      if (f_past_valid && !$past(rst) && $past(req[i]) && !$past(gnt[i])) m_hold: assume (req[i]);

    // -------------------------------------------------------------------------
    // Task 3: bounded wait. wait_cnt counts consecutive cycles that requester i
    // has asked without being granted; it must stay below N.
    //   SVA: a_bounded_wait: assert property (@(posedge clk) disable iff (rst)
    //          req[i] |-> ##[0:N-1] gnt[i]);
    // -------------------------------------------------------------------------
    logic [2:0] wait_cnt;
    always_ff @(posedge clk)
      wait_cnt <= (rst || !req[i] || gnt[i]) ? '0 : wait_cnt + 1'b1;
    always_comb if (f_past_valid) a_bounded_wait: assert (wait_cnt < N);

    // -------------------------------------------------------------------------
    // Task 4a: every requester can be granted, including after the longest wait.
    //   SVA: c_granted:  cover property (@(posedge clk) gnt[i]);
    //   SVA: c_max_wait: cover property (@(posedge clk) req[i] && !gnt[i] [*N-1] ##1 gnt[i]);
    // -------------------------------------------------------------------------
    always_comb if (f_past_valid && !rst) c_granted:  cover (gnt[i]);
    always_comb if (f_past_valid && !rst) c_max_wait: cover (gnt[i] && wait_cnt == N - 1);
  end

  // ---------------------------------------------------------------------------
  // Task 4b: contention is reachable - all four ask in the same cycle.
  //   SVA: c_all_req: cover property (@(posedge clk) disable iff (rst) &req);
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid && !rst) c_all_req: cover (&req);

endmodule
