// sync_fifo: synchronous FIFO with a first-word-fall-through read port.
//
// Specification
//   - DEPTH = 2**AW entries of WIDTH bits. Synchronous, active-high reset empties it.
//   - A write (wr_en = 1) stores wdata unless the FIFO is full; a write while
//     full is dropped. A read (rd_en = 1) removes the head entry unless the FIFO
//     is empty; a read while empty is ignored. Both may happen in one cycle.
//   - rdata always shows the head entry (valid only when empty = 0).
//   - level is the number of stored entries, 0 .. DEPTH.
//   - full = 1 exactly when level == DEPTH; empty = 1 exactly when level == 0.
module sync_fifo #(
    parameter int WIDTH = 8,
    parameter int AW    = 2           // DEPTH = 2**AW
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wdata,
    input  logic             rd_en,
    output logic [WIDTH-1:0] rdata,
    output logic             full,
    output logic             empty,
    output logic [AW:0]      level
);

  localparam int DEPTH = 1 << AW;

  logic [WIDTH-1:0] mem [DEPTH];
  logic [AW:0]      wr_ptr, rd_ptr;    // one extra bit tells full from empty

  logic do_write, do_read;
  assign do_write = wr_en && !full;
  assign do_read  = rd_en && !empty;

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      level  <= '0;
    end else begin
      if (do_write) begin
        mem[wr_ptr[AW-1:0]] <= wdata;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (do_read) rd_ptr <= rd_ptr + 1'b1;
      level <= level + (AW+1)'(do_write) - (AW+1)'(do_read);
    end
  end

  assign empty = (wr_ptr == rd_ptr);
  assign full  = (wr_ptr[AW] != rd_ptr[AW]) && (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]);
  assign rdata = mem[rd_ptr[AW-1:0]];

endmodule
