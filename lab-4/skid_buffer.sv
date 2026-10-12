// skid_buffer: two-entry valid/ready pipeline stage with registered outputs.
//
// Specification (both ports follow the usual valid/ready rules)
//   - A transfer happens on a port in a cycle where valid and ready are both 1.
//   - Once a sender raises valid, it keeps valid high and data unchanged until
//     the transfer happens. This buffer relies on that from its upstream sender
//     (s_*) and guarantees it on its downstream port (m_*).
//   - Every upstream transfer appears exactly once downstream, in order, with
//     the same data. Nothing is dropped, duplicated or reordered.
//   - Up to two entries are buffered: the output register (m_*) and a skid
//     register that catches one transfer while the output is stalled.
//   - Synchronous, active-high reset empties both registers.
module skid_buffer #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst,
    // upstream (sink side of this block)
    input  logic             s_valid,
    output logic             s_ready,
    input  logic [WIDTH-1:0] s_data,
    // downstream (source side of this block)
    output logic             m_valid,
    input  logic             m_ready,
    output logic [WIDTH-1:0] m_data
);

  logic             skid_valid;
  logic [WIDTH-1:0] skid_data;

  // Accept only while the skid register is empty. (The lower-latency version,
  // !skid_valid || m_ready, accepted a transfer it had nowhere to store.)
  assign s_ready = !skid_valid;

  always_ff @(posedge clk) begin
    if (rst) begin
      m_valid    <= 1'b0;
      skid_valid <= 1'b0;
    end else if (m_ready || !m_valid) begin
      // The output register can take a new entry: oldest first.
      if (skid_valid) begin
        m_data     <= skid_data;
        m_valid    <= 1'b1;
        skid_valid <= 1'b0;
      end else begin
        m_data  <= s_data;
        m_valid <= s_valid;
      end
    end else if (s_valid && s_ready) begin
      // Output stalled: park the accepted transfer in the skid register.
      skid_data  <= s_data;
      skid_valid <= 1'b1;
    end
  end

endmodule
