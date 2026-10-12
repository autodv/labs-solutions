// fv_sync_fifo: formal testbench for sync_fifo.
//
// Inputs are unconstrained except for the reset assumption. Internal signals of
// the DUT are reached with hierarchical references (dut.wr_ptr), the same way a
// bound checker sees them in a commercial flow.
module fv_sync_fifo (
    input logic       clk,
    input logic       rst,
    input logic       wr_en,
    input logic [7:0] wdata,
    input logic       rd_en
);

  localparam int WIDTH = 8;
  localparam int AW    = 2;
  localparam int DEPTH = 1 << AW;

  logic [WIDTH-1:0] rdata;
  logic             full, empty;
  logic [AW:0]      level;

  sync_fifo #(.WIDTH(WIDTH), .AW(AW)) dut (.*);

  logic f_past_valid = 1'b0;
  always_ff @(posedge clk) f_past_valid <= 1'b1;

  always_comb if (!f_past_valid) m_reset_first: assume (rst);

  // ---------------------------------------------------------------------------
  // Provided assertion: the FIFO never holds more than DEPTH entries.
  //   SVA: a_level_le_depth: assert property (@(posedge clk) level <= DEPTH);
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid) a_level_le_depth: assert (level <= DEPTH);

  // ---------------------------------------------------------------------------
  // Task 2: level is exactly the distance between the pointers. This is true in
  // every reachable state and rules out the unreachable states that broke
  // induction (level = 4 with equal pointers).
  //   SVA: a_level_ptrs: assert property (@(posedge clk) level == dut.wr_ptr - dut.rd_ptr);
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid) a_level_ptrs: assert (level == dut.wr_ptr - dut.rd_ptr);

  // ---------------------------------------------------------------------------
  // Task 3: status flags and dropped operations.
  //   SVA: a_full:  assert property (@(posedge clk) full  == (level == DEPTH));
  //   SVA: a_empty: assert property (@(posedge clk) empty == (level == 0));
  //   SVA: a_drop_write: assert property (@(posedge clk) disable iff (rst)
  //          full && wr_en && !rd_en |=> $stable(level));
  //   SVA: a_drop_read:  assert property (@(posedge clk) disable iff (rst)
  //          empty && rd_en && !wr_en |=> $stable(level));
  // ---------------------------------------------------------------------------
  always_comb if (f_past_valid) a_full:  assert (full  == (level == DEPTH));
  always_comb if (f_past_valid) a_empty: assert (empty == (level == '0));

  always_ff @(posedge clk) begin
    if (f_past_valid && !$past(rst) && $past(full) && $past(wr_en) && !$past(rd_en))
      a_drop_write: assert (level == $past(level));
    if (f_past_valid && !$past(rst) && $past(empty) && $past(rd_en) && !$past(wr_en))
      a_drop_read: assert (level == $past(level));
  end

  // ---------------------------------------------------------------------------
  // Data integrity (Tasks 4 and 5). Track one arbitrary entry through the FIFO.
  //
  // A register with no reset whose next value is itself is a free constant:
  // the tool picks its initial value, and it never changes. Commercial tools
  // spell this "rand const" or a free variable with an $stable assumption.
  // ---------------------------------------------------------------------------
  logic [AW:0]      f_ptr;    // pointer value at which the tracked entry is written
  logic [WIDTH-1:0] f_data;   // the data it carries
  always_ff @(posedge clk) begin
    f_ptr  <= f_ptr;
    f_data <= f_data;
  end

  // f_in_fifo is 1 while the tracked entry is stored and not yet read.
  logic f_in_fifo;
  always_ff @(posedge clk)
    if (rst) f_in_fifo <= 1'b0;
    else if (wr_en && !full && dut.wr_ptr == f_ptr) f_in_fifo <= 1'b1;
    else if (rd_en && !empty && dut.rd_ptr == f_ptr) f_in_fifo <= 1'b0;

  // ---------------------------------------------------------------------------
  // Task 4: the tracked write carries f_data; when that entry is at the head,
  // the read port must show it.
  //   SVA: m_tracked_data: assume property (@(posedge clk)
  //          wr_en && !full && dut.wr_ptr == f_ptr |-> wdata == f_data);
  //   SVA: a_data: assert property (@(posedge clk) disable iff (rst)
  //          f_in_fifo && dut.rd_ptr == f_ptr |-> rdata == f_data);
  // ---------------------------------------------------------------------------
  always_comb if (wr_en && !full && dut.wr_ptr == f_ptr) m_tracked_data: assume (wdata == f_data);
  always_comb if (f_past_valid && !rst && f_in_fifo && dut.rd_ptr == f_ptr) a_data: assert (rdata == f_data);

  // ---------------------------------------------------------------------------
  // Task 5: invariants for the data check. f_off is how far f_ptr sits behind
  // the head; the tracked entry is stored exactly when that offset is inside
  // the occupied region, and while stored its memory slot holds f_data.
  //   SVA: a_in_fifo_iff: assert property (@(posedge clk) disable iff (rst)
  //          f_in_fifo == ((f_ptr - dut.rd_ptr) < level));
  //   SVA: a_mem_holds:   assert property (@(posedge clk) disable iff (rst)
  //          f_in_fifo |-> dut.mem[f_ptr[AW-1:0]] == f_data);
  // ---------------------------------------------------------------------------
  logic [AW:0] f_off;
  assign f_off = f_ptr - dut.rd_ptr;
  always_comb if (f_past_valid && !rst) a_in_fifo_iff: assert (f_in_fifo == (f_off < level));
  always_comb if (f_past_valid && !rst && f_in_fifo) a_mem_holds: assert (dut.mem[f_ptr[AW-1:0]] == f_data);

  // ---------------------------------------------------------------------------
  // Task 6: covers.
  //   SVA: c_full:      cover property (@(posedge clk) full);
  //   SVA: c_wrap:      cover property (@(posedge clk) disable iff (rst) dut.wr_ptr == DEPTH ##[0:$] empty);
  //   SVA: c_read_full: cover property (@(posedge clk) f_in_fifo && dut.rd_ptr == f_ptr && full && rd_en);
  // c_wrap uses a helper: the write pointer has passed DEPTH (wrapped once).
  // ---------------------------------------------------------------------------
  logic f_wrapped = 1'b0;
  always_ff @(posedge clk) f_wrapped <= rst ? 1'b0 : (f_wrapped || (dut.wr_ptr == DEPTH));

  always_comb begin
    if (f_past_valid && !rst) c_full:      cover (full);
    if (f_past_valid && !rst) c_wrap:      cover (f_wrapped && empty && dut.wr_ptr != '0);
    if (f_past_valid && !rst) c_read_full: cover (f_in_fifo && dut.rd_ptr == f_ptr && full && rd_en);
  end

endmodule
