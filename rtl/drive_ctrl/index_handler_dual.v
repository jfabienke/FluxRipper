//-----------------------------------------------------------------------------
// Dual Index Handler for FluxRipper
// Handles 4 independent index pulse inputs with RPM detection
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-03 18:15
//-----------------------------------------------------------------------------

module index_handler_dual (
    input  wire        clk,
    input  wire        reset,

    // Configuration
    input  wire [31:0] clk_freq,        // System clock frequency (e.g., 200MHz)

    // Index inputs from 4 drives
    input  wire        index_0,         // Drive 0 index
    input  wire        index_1,         // Drive 1 index
    input  wire        index_2,         // Drive 2 index
    input  wire        index_3,         // Drive 3 index

    // Per-drive outputs
    output reg  [3:0]  index_pulse,     // One-clock index pulse per drive
    output reg  [31:0] revolution_time_0,
    output reg  [31:0] revolution_time_1,
    output reg  [31:0] revolution_time_2,
    output reg  [31:0] revolution_time_3,
    output reg  [3:0]  rpm_300,         // 1 if drive is 300 RPM
    output reg  [3:0]  rpm_360,         // 1 if drive is 360 RPM
    output reg  [3:0]  rpm_valid,       // 1 if RPM measurement is valid
    output reg  [15:0] revolution_count_0,
    output reg  [15:0] revolution_count_1,
    output reg  [15:0] revolution_count_2,
    output reg  [15:0] revolution_count_3
);

    //-------------------------------------------------------------------------
    // RPM timing thresholds
    //-------------------------------------------------------------------------
    // At 200 MHz clock:
    // 300 RPM = 200ms/rev = 40,000,000 clocks
    // 360 RPM = 166.67ms/rev = 33,333,333 clocks
    // Allow +/- 5% tolerance

    wire [31:0] rpm_300_nominal = clk_freq / 5;          // 200ms = clk/5
    wire [31:0] rpm_360_nominal = (clk_freq * 10) / 60;  // 166.67ms

    wire [31:0] rpm_300_min = (rpm_300_nominal * 95) / 100;
    wire [31:0] rpm_300_max = (rpm_300_nominal * 105) / 100;
    wire [31:0] rpm_360_min = (rpm_360_nominal * 95) / 100;
    wire [31:0] rpm_360_max = (rpm_360_nominal * 105) / 100;

    //-------------------------------------------------------------------------
    // Per-drive state
    //-------------------------------------------------------------------------
    reg [2:0]  index_sync [0:3];        // 3-stage synchronizer per drive
    reg        index_prev [0:3];        // Previous index state (edge detection)
    reg [31:0] timer [0:3];             // Revolution timer per drive

    //-------------------------------------------------------------------------
    // Index edge detection and timing
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 4; i = i + 1) begin
                index_sync[i] <= 3'b000;
                index_prev[i] <= 1'b0;
                timer[i] <= 32'd0;
                index_pulse[i] <= 1'b0;
                rpm_300[i] <= 1'b0;
                rpm_360[i] <= 1'b0;
                rpm_valid[i] <= 1'b0;
            end
            revolution_time_0 <= 32'd0;
            revolution_time_1 <= 32'd0;
            revolution_time_2 <= 32'd0;
            revolution_time_3 <= 32'd0;
            revolution_count_0 <= 16'd0;
            revolution_count_1 <= 16'd0;
            revolution_count_2 <= 16'd0;
            revolution_count_3 <= 16'd0;
        end else begin
            // Synchronize index inputs
            index_sync[0] <= {index_sync[0][1:0], index_0};
            index_sync[1] <= {index_sync[1][1:0], index_1};
            index_sync[2] <= {index_sync[2][1:0], index_2};
            index_sync[3] <= {index_sync[3][1:0], index_3};

            // Process each drive
            for (i = 0; i < 4; i = i + 1) begin
                index_prev[i] <= index_sync[i][2];

                // Increment timers
                if (timer[i] < 32'hFFFF_FFFF)
                    timer[i] <= timer[i] + 1'b1;

                // Detect rising edge on index
                if (index_sync[i][2] && !index_prev[i]) begin
                    index_pulse[i] <= 1'b1;

                    // Store revolution time
                    case (i)
                        0: begin
                            revolution_time_0 <= timer[i];
                            revolution_count_0 <= revolution_count_0 + 1'b1;
                        end
                        1: begin
                            revolution_time_1 <= timer[i];
                            revolution_count_1 <= revolution_count_1 + 1'b1;
                        end
                        2: begin
                            revolution_time_2 <= timer[i];
                            revolution_count_2 <= revolution_count_2 + 1'b1;
                        end
                        3: begin
                            revolution_time_3 <= timer[i];
                            revolution_count_3 <= revolution_count_3 + 1'b1;
                        end
                    endcase

                    // Determine RPM
                    if (timer[i] >= rpm_300_min && timer[i] <= rpm_300_max) begin
                        rpm_300[i] <= 1'b1;
                        rpm_360[i] <= 1'b0;
                        rpm_valid[i] <= 1'b1;
                    end else if (timer[i] >= rpm_360_min && timer[i] <= rpm_360_max) begin
                        rpm_300[i] <= 1'b0;
                        rpm_360[i] <= 1'b1;
                        rpm_valid[i] <= 1'b1;
                    end else begin
                        // Out of expected range
                        rpm_valid[i] <= 1'b0;
                    end

                    // Reset timer
                    timer[i] <= 32'd0;
                end else begin
                    index_pulse[i] <= 1'b0;
                end
            end
        end
    end

endmodule
