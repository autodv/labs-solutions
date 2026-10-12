// updown_counter: saturating up/down counter.
//
// Specification
//   - Synchronous, active-high reset: rst = 1 at a rising edge sets count to 0.
//   - inc = 1 and dec = 0: count goes up by 1, but never past MAX.
//   - dec = 1 and inc = 0: count goes down by 1, but never below 0.
//   - inc = dec (both 0 or both 1): count holds its value.
//   - at_max is 1 exactly when count == MAX; at_min is 1 exactly when count == 0.
module updown_counter #(
    parameter int WIDTH = 4,
    parameter logic [WIDTH-1:0] MAX = 4'd9
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             inc,
    input  logic             dec,
    output logic [WIDTH-1:0] count,
    output logic             at_max,
    output logic             at_min
);

  always_ff @(posedge clk) begin
    if (rst) begin
      count <= '0;
    end else if (inc && !dec && count != MAX) begin
      count <= count + 1'b1;
    end else if (dec && !inc && count != '0) begin
      count <= count - 1'b1;
    end
  end

  assign at_max = (count == MAX);
  assign at_min = (count == '0);

endmodule
