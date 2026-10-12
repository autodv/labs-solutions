// fv_skid_buffer: formal testbench for skid_buffer.
//
// Assume-guarantee at the ports: the upstream sender's obligations are
// assumptions (m_*), the buffer's obligations on its downstream port are
// assertions (a_*). If a neighbouring block were verified the same way, each
// assumption here would be an assertion there.
module fv_skid_buffer #(
    parameter int WIDTH = 8
) (
    input logic             clk,
    input logic             rst,
    input logic             s_valid,
    input logic [WIDTH-1:0] s_data,
    input logic             m_ready
);

  logic             s_ready;
  logic             m_valid;
  logic [WIDTH-1:0] m_data;

  skid_buffer #(.WIDTH(WIDTH)) dut (.*);

  logic f_past_valid = 1'b0;
  always_ff @(posedge clk) f_past_valid <= 1'b1;

  always_comb if (!f_past_valid) m_reset_first: assume (rst);

  // Transfers on each port.
  logic s_fire, m_fire;
  assign s_fire = s_valid && s_ready;
  assign m_fire = m_valid && m_ready;

  // ---------------------------------------------------------------------------
  // Provided: upstream protocol (assumption) and downstream protocol (assertion).
  //   SVA: m_s_hold: assume property (@(posedge clk) disable iff (rst)
  //          s_valid && !s_ready |=> s_valid && $stable(s_data));
  //   SVA: a_m_hold: assert property (@(posedge clk) disable iff (rst)
  //          m_valid && !m_ready |=> m_valid && $stable(m_data));
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (f_past_valid && !$past(rst) && $past(s_valid) && !$past(s_ready))
      m_s_hold: assume (s_valid && s_data == $past(s_data));
    if (f_past_valid && !$past(rst) && $past(m_valid) && !$past(m_ready))
      a_m_hold: assert (m_valid && m_data == $past(m_data));
  end

  // ---------------------------------------------------------------------------
  // Task 1: reset empties the output.
  //   SVA: a_reset: assert property (@(posedge clk) rst |=> !m_valid);
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) if (f_past_valid && $past(rst)) a_reset: assert (!m_valid);

  // ---------------------------------------------------------------------------
  // Task 2: transfer counters (modulo 16) and occupancy.
  //   SVA: a_occ_le_2:     assert property (@(posedge clk) disable iff (rst) f_occ <= 2);
  //   SVA: a_occ_regs:     assert property (@(posedge clk) disable iff (rst)
  //                          f_occ == m_valid + dut.skid_valid);
  //   SVA: a_skid_needs_m: assert property (@(posedge clk) disable iff (rst)
  //                          dut.skid_valid |-> m_valid);
  // ---------------------------------------------------------------------------
  logic [3:0] in_cnt, out_cnt, f_occ;
  always_ff @(posedge clk) begin
    in_cnt  <= rst ? '0 : in_cnt  + 4'(s_fire);
    out_cnt <= rst ? '0 : out_cnt + 4'(m_fire);
  end
  assign f_occ = in_cnt - out_cnt;

  always_comb if (f_past_valid && !rst) a_occ_le_2:     assert (f_occ <= 4'd2);
  always_comb if (f_past_valid && !rst) a_occ_regs:     assert (f_occ == 4'(m_valid) + 4'(dut.skid_valid));
  always_comb if (f_past_valid && !rst) a_skid_needs_m: assert (!dut.skid_valid || m_valid);

  // ---------------------------------------------------------------------------
  // Task 3: track transfer number f_idx. The upstream transfer with that number
  // carries f_data; the downstream transfer with the same number must too.
  // Together with the counters this rules out drops, duplicates and reordering.
  //   SVA: m_tracked: assume property (@(posedge clk) s_fire && in_cnt == f_idx |-> s_data == f_data);
  //   SVA: a_data:    assert property (@(posedge clk) disable iff (rst)
  //                     m_fire && out_cnt == f_idx && f_occ != 0 |-> m_data == f_data);
  // ---------------------------------------------------------------------------
  logic [3:0]       f_idx;
  logic [WIDTH-1:0] f_data;
  always_ff @(posedge clk) begin
    f_idx  <= f_idx;
    f_data <= f_data;
  end

  always_comb if (s_fire && in_cnt == f_idx) m_tracked: assume (s_data == f_data);
  always_comb if (f_past_valid && !rst && m_fire && out_cnt == f_idx && f_occ != 0)
    a_data: assert (m_data == f_data);

  // ---------------------------------------------------------------------------
  // Task 4: where the tracked transfer sits while it is inside the buffer.
  // f_pos = 0: it is the oldest entry, in the output register.
  // f_pos = 1: it is the second entry, in the skid register.
  //   SVA: a_track_m:    assert property (@(posedge clk) disable iff (rst)
  //                        f_pos == 0 && f_occ >= 1 |-> m_data == f_data);
  //   SVA: a_track_skid: assert property (@(posedge clk) disable iff (rst)
  //                        f_pos == 1 && f_occ == 2 |-> dut.skid_data == f_data);
  // ---------------------------------------------------------------------------
  logic [3:0] f_pos;
  assign f_pos = f_idx - out_cnt;
  always_comb if (f_past_valid && !rst && f_pos == 4'd0 && f_occ >= 4'd1) a_track_m:    assert (m_data == f_data);
  always_comb if (f_past_valid && !rst && f_pos == 4'd1 && f_occ == 4'd2) a_track_skid: assert (dut.skid_data == f_data);

  // ---------------------------------------------------------------------------
  // Task 7: covers.
  //   SVA: c_both_full:  cover property (@(posedge clk) dut.skid_valid && m_valid && !m_ready && s_valid);
  //   SVA: c_throughput: cover property (@(posedge clk) disable iff (rst) (s_fire && m_fire) [*3]);
  //   SVA: c_drain:      cover property (@(posedge clk) dut.skid_valid ##1 !dut.skid_valid && m_valid);
  // ---------------------------------------------------------------------------
  logic [1:0] f_streak;   // consecutive cycles with a transfer on both ports
  always_ff @(posedge clk) f_streak <= (rst || !(s_fire && m_fire)) ? '0 : (f_streak == 2'd3 ? 2'd3 : f_streak + 1'b1);

  always_comb if (f_past_valid && !rst) c_both_full:  cover (dut.skid_valid && m_valid && !m_ready && s_valid);
  always_comb if (f_past_valid && !rst) c_throughput: cover (f_streak == 2'd2 && s_fire && m_fire);
  always_ff @(posedge clk)
    if (f_past_valid && !$past(rst)) c_drain: cover ($past(dut.skid_valid) && !dut.skid_valid && m_valid);

endmodule
