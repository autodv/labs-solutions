// tl_ctrl: traffic-light controller for a main road with a side-road sensor.
//
// Specification
//   - The main road is green by default. When car_waiting = 1 and the main road
//     has been green for at least MIN_GREEN cycles, the controller goes
//     MAIN_YELLOW (YELLOW_T cycles), then SIDE_GREEN (SIDE_T cycles), then
//     SIDE_YELLOW (YELLOW_T cycles), then back to MAIN_GREEN.
//   - main_light and side_light are 2-bit codes: 0 = red, 1 = yellow, 2 = green.
//   - Synchronous, active-high reset goes to MAIN_GREEN with the timer at 0.
module tl_ctrl #(
    parameter int MIN_GREEN = 6,
    parameter int YELLOW_T  = 2,
    parameter int SIDE_T    = 4
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       car_waiting,
    output logic [1:0] main_light,
    output logic [1:0] side_light
);

  typedef enum logic [1:0] {
    MAIN_GREEN  = 2'd0,
    MAIN_YELLOW = 2'd1,
    SIDE_GREEN  = 2'd2,
    SIDE_YELLOW = 2'd3
  } state_e;

  localparam logic [1:0] RED = 2'd0, YELLOW = 2'd1, GREEN = 2'd2;

  state_e     state;
  logic [3:0] timer;   // cycles spent in the current state (saturates at 15)

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= MAIN_GREEN;
      timer <= '0;
    end else begin
      unique case (state)
        MAIN_GREEN:
          if (car_waiting && timer >= 4'(MIN_GREEN - 1)) begin state <= MAIN_YELLOW; timer <= '0; end
          else if (timer != 4'hF) timer <= timer + 1'b1;
        MAIN_YELLOW:
          if (timer == 4'(YELLOW_T - 1)) begin state <= SIDE_GREEN; timer <= '0; end
          else timer <= timer + 1'b1;
        SIDE_GREEN:
          if (timer == 4'(SIDE_T - 1)) begin state <= SIDE_YELLOW; timer <= '0; end
          else timer <= timer + 1'b1;
        SIDE_YELLOW:
          if (timer == 4'(YELLOW_T - 1)) begin state <= MAIN_GREEN; timer <= '0; end
          else timer <= timer + 1'b1;
      endcase
    end
  end

  always_comb begin
    main_light = RED;
    side_light = RED;
    unique case (state)
      MAIN_GREEN:  main_light = GREEN;
      MAIN_YELLOW: main_light = YELLOW;
      SIDE_GREEN:  side_light = GREEN;
      SIDE_YELLOW: side_light = YELLOW;
    endcase
  end

endmodule
