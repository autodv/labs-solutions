// fv_updown_counter: formal testbench for updown_counter.
//
// The inputs of this wrapper (rst, inc, dec) are left unconstrained, so the
// formal tool may drive any value on every cycle. Assumptions narrow that down
// to legal stimulus; assertions state what the design must do; covers ask the
// tool to show that something can happen.
//
// Property style used in these labs
//   Runnable here:   always_ff @(posedge clk) if (<guard>) a_name: assert (<expr>);
//   Commercial SVA:  a_name: assert property (@(posedge clk) disable iff (rst) <seq>);
// The SVA form is given in a comment above each runnable property.
module fv_updown_counter (
    input logic clk,
    input logic rst,
    input logic inc,
    input logic dec
);

  localparam int WIDTH = 4;
  localparam logic [WIDTH-1:0] MAX = 4'd9;

  logic [WIDTH-1:0] count;
  logic             at_max;
  logic             at_min;

  updown_counter #(.WIDTH(WIDTH), .MAX(MAX)) dut (.*);

  // ---------------------------------------------------------------------------
  // f_past_valid is 0 in the first cycle and 1 forever after. Guard every
  // $past() with it: in cycle 0 there is no past, and $past returns a value the
  // tool is free to choose.
  // ---------------------------------------------------------------------------
  logic f_past_valid = 1'b0;
  always_ff @(posedge clk) f_past_valid <= 1'b1;

  // Start from reset: the design is in an arbitrary state in cycle 0.
  always_comb if (!f_past_valid) m_reset_first: assume (rst);

  // ---------------------------------------------------------------------------
  // Provided assertion: count never exceeds MAX.
  //   SVA: a_count_le_max: assert property (@(posedge clk) count <= MAX);
  // An invariant (true in every cycle) is checked in always_comb, so a failure
  // is reported on the step whose values break it.
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid) a_count_le_max: assert (count <= MAX);

  // ---------------------------------------------------------------------------
  // Task 2: at_max and at_min agree with count (invariants).
  //   SVA: a_at_max: assert property (@(posedge clk) at_max == (count == MAX));
  //   SVA: a_at_min: assert property (@(posedge clk) at_min == (count == 0));
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid) a_at_max: assert (at_max == (count == MAX));
  always_comb if (f_past_valid) a_at_min: assert (at_min == (count == '0));

  // ---------------------------------------------------------------------------
  // Task 3: reset clears the counter on the next cycle.
  //   SVA: a_reset: assert property (@(posedge clk) rst |=> count == 0);
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) if (f_past_valid && $past(rst)) a_reset: assert (count == '0);

  // ---------------------------------------------------------------------------
  // Task 4: one-cycle behaviour. Each property looks at the previous cycle's
  // inputs ($past) and checks the value count took at the edge.
  //   SVA: a_inc: assert property (@(posedge clk) disable iff (rst)
  //          inc && !dec && count != MAX |=> count == $past(count) + 1);
  //   SVA: a_inc_sat: assert property (@(posedge clk) disable iff (rst)
  //          inc && !dec && count == MAX |=> count == MAX);
  //   SVA: a_dec: assert property (@(posedge clk) disable iff (rst)
  //          dec && !inc && count != 0 |=> count == $past(count) - 1);
  //   SVA: a_dec_sat: assert property (@(posedge clk) disable iff (rst)
  //          dec && !inc && count == 0 |=> count == 0);
  //   SVA: a_hold: assert property (@(posedge clk) disable iff (rst)
  //          inc == dec |=> $stable(count));
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (f_past_valid && !$past(rst) && $past(inc) && !$past(dec) && $past(count) != MAX)
      a_inc: assert (count == $past(count) + 1'b1);
    if (f_past_valid && !$past(rst) && $past(inc) && !$past(dec) && $past(count) == MAX)
      a_inc_sat: assert (count == MAX);
    if (f_past_valid && !$past(rst) && $past(dec) && !$past(inc) && $past(count) != '0)
      a_dec: assert (count == $past(count) - 1'b1);
    if (f_past_valid && !$past(rst) && $past(dec) && !$past(inc) && $past(count) == '0)
      a_dec_sat: assert (count == '0);
    if (f_past_valid && !$past(rst) && $past(inc) == $past(dec))
      a_hold: assert (count == $past(count));
  end

  // ---------------------------------------------------------------------------
  // Task 5: covers - evidence that interesting behaviour is reachable.
  //   SVA: c_max:      cover property (@(posedge clk) at_max);
  //   SVA: c_sat_up:   cover property (@(posedge clk) at_max && inc && !dec ##1 at_max);
  //   SVA: c_max_to_0: cover property (@(posedge clk) at_max ##[1:$] at_min);
  // ---------------------------------------------------------------------------
  logic seen_max = 1'b0;   // helper register: at_max has been seen since reset
  always_ff @(posedge clk) seen_max <= rst ? 1'b0 : (seen_max || at_max);

  always_ff @(posedge clk) begin
    if (f_past_valid) c_max:      cover (at_max);
    if (f_past_valid) c_sat_up:   cover (!$past(rst) && $past(at_max) && $past(inc) && !$past(dec) && at_max);
    if (f_past_valid) c_max_to_0: cover (seen_max && at_min && !rst);
  end

endmodule
