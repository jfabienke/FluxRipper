//-----------------------------------------------------------------------------
// ESDI Physical Layer Interface
//
// Implements the differential data interface for ESDI drives:
//   - 100Ω differential termination (switchable)
//   - RS-422 style differential receivers/drivers
//   - Separate clock and data recovery
//   - NRZ data with embedded clock
//
// ESDI 20-pin Data Cable Pinout:
//   Pin 1:  Ground
//   Pin 2:  +Sector/Address Mark (SAMK)
//   Pin 3:  Ground
//   Pin 4:  -Sector/Address Mark
//   Pin 5:  Ground
//   Pin 6:  +Index
//   Pin 7:  Ground
//   Pin 8:  -Index
//   Pin 9:  Ground
//   Pin 10: +Read Reference Clock
//   Pin 11: Ground
//   Pin 12: -Read Reference Clock
//   Pin 13: +Write Data
//   Pin 14: -Write Data
//   Pin 15: Ground
//   Pin 16: +Write Clock
//   Pin 17: +Read Data
//   Pin 18: -Read Data
//   Pin 19: Ground
//   Pin 20: -Write Clock
//
// Clock domain: 300 MHz
// Created: 2025-12-04 09:15
//-----------------------------------------------------------------------------

module esdi_phy (
    input  wire        clk,              // 300 MHz system clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire        phy_enable,       // Enable PHY (power save when 0)
    input  wire        termination_en,   // Enable 100Ω differential termination
    input  wire [1:0]  data_rate,        // 0=10Mbps, 1=15Mbps, 2=20Mbps, 3=24Mbps

    //-------------------------------------------------------------------------
    // Differential Data Interface (directly to/from cable)
    //-------------------------------------------------------------------------
    // Read Data pair
    input  wire        read_data_p,      // Pin 17: +READ DATA
    input  wire        read_data_n,      // Pin 18: -READ DATA

    // Read Reference Clock pair
    input  wire        read_clk_p,       // Pin 10: +READ REFERENCE CLOCK
    input  wire        read_clk_n,       // Pin 12: -READ REFERENCE CLOCK

    // Write Data pair
    output wire        write_data_p,     // Pin 13: +WRITE DATA
    output wire        write_data_n,     // Pin 14: -WRITE DATA

    // Write Clock pair
    output wire        write_clk_p,      // Pin 16: +WRITE CLOCK
    output wire        write_clk_n,      // Pin 20: -WRITE CLOCK

    // Sector/Address Mark pair
    input  wire        samk_p,           // Pin 2: +SAMK
    input  wire        samk_n,           // Pin 4: -SAMK

    // Index pair
    input  wire        index_p,          // Pin 6: +INDEX
    input  wire        index_n,          // Pin 8: -INDEX

    //-------------------------------------------------------------------------
    // Recovered Single-Ended Signals (to decoder)
    //-------------------------------------------------------------------------
    output reg         read_data,        // Recovered NRZ read data
    output reg         read_clk,         // Recovered read clock
    output reg         samk_pulse,       // Sector/Address Mark pulse
    output reg         index_pulse,      // Index pulse
    output reg         data_valid,       // Read data is valid

    //-------------------------------------------------------------------------
    // Transmit Single-Ended Signals (from encoder)
    //-------------------------------------------------------------------------
    input  wire        write_data_in,    // NRZ write data
    input  wire        write_clk_in,     // Write clock
    input  wire        write_enable,     // Enable write drivers

    //-------------------------------------------------------------------------
    // Termination Control (directly to external resistor switches)
    //-------------------------------------------------------------------------
    output wire        term_read_data,   // Enable 100Ω on read data pair
    output wire        term_read_clk,    // Enable 100Ω on read clock pair
    output wire        term_samk,        // Enable 100Ω on SAMK pair
    output wire        term_index,       // Enable 100Ω on index pair

    //-------------------------------------------------------------------------
    // Status and Diagnostics
    //-------------------------------------------------------------------------
    output reg         signal_detect,    // Differential signal detected
    output reg  [7:0]  signal_quality,   // Signal quality metric 0-255
    output reg         clock_locked,     // Read clock recovery locked
    output reg  [15:0] edge_count        // Edge count for diagnostics
);

    //-------------------------------------------------------------------------
    // Termination Control
    //-------------------------------------------------------------------------
    // All terminations enabled when termination_en is high and PHY is enabled
    assign term_read_data = phy_enable & termination_en;
    assign term_read_clk  = phy_enable & termination_en;
    assign term_samk      = phy_enable & termination_en;
    assign term_index     = phy_enable & termination_en;

    //-------------------------------------------------------------------------
    // Differential Receiver - Read Data
    //-------------------------------------------------------------------------
    // 3-stage synchronizer for metastability protection
    reg [2:0] read_data_diff_sync;
    reg       read_data_diff;

    always @(posedge clk) begin
        if (reset) begin
            read_data_diff_sync <= 3'b000;
            read_data_diff <= 1'b0;
        end else if (phy_enable) begin
            // Differential to single-ended conversion
            // In hardware, this would be done by an RS-422 receiver (e.g., AM26LS32)
            // Here we simulate the comparison: output = 1 if P > N
            read_data_diff_sync <= {read_data_diff_sync[1:0], (read_data_p & ~read_data_n)};
            read_data_diff <= read_data_diff_sync[2];
        end
    end

    //-------------------------------------------------------------------------
    // Differential Receiver - Read Clock
    //-------------------------------------------------------------------------
    reg [2:0] read_clk_diff_sync;
    reg       read_clk_diff;

    always @(posedge clk) begin
        if (reset) begin
            read_clk_diff_sync <= 3'b000;
            read_clk_diff <= 1'b0;
        end else if (phy_enable) begin
            read_clk_diff_sync <= {read_clk_diff_sync[1:0], (read_clk_p & ~read_clk_n)};
            read_clk_diff <= read_clk_diff_sync[2];
        end
    end

    //-------------------------------------------------------------------------
    // Differential Receiver - SAMK
    //-------------------------------------------------------------------------
    reg [2:0] samk_diff_sync;
    reg       samk_diff;

    always @(posedge clk) begin
        if (reset) begin
            samk_diff_sync <= 3'b000;
            samk_diff <= 1'b0;
        end else if (phy_enable) begin
            samk_diff_sync <= {samk_diff_sync[1:0], (samk_p & ~samk_n)};
            samk_diff <= samk_diff_sync[2];
        end
    end

    //-------------------------------------------------------------------------
    // Differential Receiver - Index
    //-------------------------------------------------------------------------
    reg [2:0] index_diff_sync;
    reg       index_diff;

    always @(posedge clk) begin
        if (reset) begin
            index_diff_sync <= 3'b000;
            index_diff <= 1'b0;
        end else if (phy_enable) begin
            index_diff_sync <= {index_diff_sync[1:0], (index_p & ~index_n)};
            index_diff <= index_diff_sync[2];
        end
    end

    //-------------------------------------------------------------------------
    // Edge Detection for Clock Recovery
    //-------------------------------------------------------------------------
    reg read_clk_prev;
    reg read_data_prev;
    wire read_clk_edge;
    wire read_data_edge;

    always @(posedge clk) begin
        if (reset) begin
            read_clk_prev <= 1'b0;
            read_data_prev <= 1'b0;
        end else begin
            read_clk_prev <= read_clk_diff;
            read_data_prev <= read_data_diff;
        end
    end

    assign read_clk_edge = read_clk_diff ^ read_clk_prev;
    assign read_data_edge = read_data_diff ^ read_data_prev;

    //-------------------------------------------------------------------------
    // Clock Recovery State Machine
    //-------------------------------------------------------------------------
    // ESDI provides a reference clock from the drive
    // We use it to sample data at the correct time

    localparam [1:0]
        CLK_HUNT    = 2'd0,    // Looking for clock edges
        CLK_LOCKING = 2'd1,    // Measuring clock period
        CLK_LOCKED  = 2'd2;    // Clock locked, sampling data

    reg [1:0]  clk_state;
    reg [7:0]  clk_period_counter;
    reg [7:0]  clk_period;
    reg [7:0]  sample_point;
    reg [7:0]  sample_counter;
    reg [7:0]  edge_streak;        // Consecutive good edges

    // Expected clock periods at 300 MHz for different ESDI rates
    // 10 Mbps: 30 clocks per bit
    // 15 Mbps: 26.7 clocks per bit
    // 20 Mbps: 15 clocks per bit
    // 24 Mbps: 16.7 clocks per bit

    wire [7:0] expected_period;
    assign expected_period = (data_rate == 2'd0) ? 8'd40 :   // 10 Mbps
                             (data_rate == 2'd1) ? 8'd27 :   // 15 Mbps
                             (data_rate == 2'd2) ? 8'd20 :   // 20 Mbps
                                                   8'd17;    // 24 Mbps

    always @(posedge clk) begin
        if (reset) begin
            clk_state <= CLK_HUNT;
            clk_period_counter <= 8'd0;
            clk_period <= 8'd40;
            sample_point <= 8'd20;
            sample_counter <= 8'd0;
            edge_streak <= 8'd0;
            clock_locked <= 1'b0;
            data_valid <= 1'b0;
        end else if (phy_enable) begin
            case (clk_state)
                CLK_HUNT: begin
                    clock_locked <= 1'b0;
                    data_valid <= 1'b0;

                    if (read_clk_edge) begin
                        clk_period_counter <= 8'd1;
                        clk_state <= CLK_LOCKING;
                    end
                end

                CLK_LOCKING: begin
                    clk_period_counter <= clk_period_counter + 1;

                    if (read_clk_edge) begin
                        // Check if period is within expected range
                        if (clk_period_counter >= (expected_period - 8'd5) &&
                            clk_period_counter <= (expected_period + 8'd5)) begin
                            edge_streak <= edge_streak + 1;
                            clk_period <= clk_period_counter;
                            sample_point <= clk_period_counter >> 1;  // Sample at 50%

                            if (edge_streak >= 8'd8) begin
                                clk_state <= CLK_LOCKED;
                                clock_locked <= 1'b1;
                            end
                        end else begin
                            // Bad period, restart
                            edge_streak <= 8'd0;
                        end
                        clk_period_counter <= 8'd1;
                    end else if (clk_period_counter > (expected_period + 8'd20)) begin
                        // Timeout, restart
                        clk_state <= CLK_HUNT;
                        edge_streak <= 8'd0;
                    end
                end

                CLK_LOCKED: begin
                    clock_locked <= 1'b1;
                    sample_counter <= sample_counter + 1;

                    if (read_clk_edge) begin
                        // Re-sync on clock edge
                        sample_counter <= 8'd0;

                        // Check clock stability
                        if (clk_period_counter >= (clk_period - 8'd3) &&
                            clk_period_counter <= (clk_period + 8'd3)) begin
                            // Still good
                            clk_period_counter <= 8'd1;
                        end else begin
                            // Lost lock
                            clk_state <= CLK_HUNT;
                            clock_locked <= 1'b0;
                            data_valid <= 1'b0;
                        end
                    end else begin
                        clk_period_counter <= clk_period_counter + 1;
                    end

                    // Sample data at the optimal point
                    if (sample_counter == sample_point) begin
                        data_valid <= 1'b1;
                    end else begin
                        data_valid <= 1'b0;
                    end
                end

                default: clk_state <= CLK_HUNT;
            endcase
        end else begin
            // PHY disabled
            clk_state <= CLK_HUNT;
            clock_locked <= 1'b0;
            data_valid <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // Output Data Latching
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            read_data <= 1'b0;
            read_clk <= 1'b0;
            samk_pulse <= 1'b0;
            index_pulse <= 1'b0;
        end else if (phy_enable) begin
            read_data <= read_data_diff;
            read_clk <= read_clk_diff;

            // Edge detect for SAMK and Index (pulses)
            samk_pulse <= samk_diff & ~samk_diff_sync[2];
            index_pulse <= index_diff & ~index_diff_sync[2];
        end else begin
            read_data <= 1'b0;
            read_clk <= 1'b0;
            samk_pulse <= 1'b0;
            index_pulse <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // Differential Transmitter - Write Data
    //-------------------------------------------------------------------------
    // In hardware, this would drive an RS-422 transmitter (e.g., AM26LS31)
    // Directly generate complementary outputs

    reg write_data_out;
    reg write_clk_out;

    always @(posedge clk) begin
        if (reset || !phy_enable || !write_enable) begin
            write_data_out <= 1'b0;
            write_clk_out <= 1'b0;
        end else begin
            write_data_out <= write_data_in;
            write_clk_out <= write_clk_in;
        end
    end

    // Differential outputs
    assign write_data_p = write_enable ? write_data_out : 1'b0;
    assign write_data_n = write_enable ? ~write_data_out : 1'b0;
    assign write_clk_p  = write_enable ? write_clk_out : 1'b0;
    assign write_clk_n  = write_enable ? ~write_clk_out : 1'b0;

    //-------------------------------------------------------------------------
    // Signal Detection and Quality
    //-------------------------------------------------------------------------
    reg [15:0] activity_counter;
    reg [15:0] last_edge_count;

    always @(posedge clk) begin
        if (reset) begin
            signal_detect <= 1'b0;
            signal_quality <= 8'd0;
            edge_count <= 16'd0;
            activity_counter <= 16'd0;
            last_edge_count <= 16'd0;
        end else if (phy_enable) begin
            // Count edges
            if (read_data_edge || read_clk_edge) begin
                if (edge_count < 16'hFFFF)
                    edge_count <= edge_count + 1;
            end

            // Periodic quality assessment (every 65536 clocks ≈ 218µs)
            activity_counter <= activity_counter + 1;

            if (activity_counter == 16'hFFFF) begin
                // Calculate edges in last period
                if (edge_count > last_edge_count + 16'd100) begin
                    signal_detect <= 1'b1;
                    // Quality based on edge consistency
                    if (clock_locked)
                        signal_quality <= 8'd255;
                    else if (edge_count > last_edge_count + 16'd500)
                        signal_quality <= 8'd192;
                    else
                        signal_quality <= 8'd128;
                end else begin
                    signal_detect <= 1'b0;
                    signal_quality <= 8'd0;
                end
                last_edge_count <= edge_count;
            end
        end else begin
            signal_detect <= 1'b0;
            signal_quality <= 8'd0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// ESDI Termination Switch Controller
// Controls external analog switches for 100Ω differential termination
//-----------------------------------------------------------------------------
module esdi_termination_ctrl (
    input  wire        clk,
    input  wire        reset,

    input  wire        enable,           // Global termination enable
    input  wire [3:0]  pair_select,      // Which pairs to terminate

    // To analog switches (directly control FETs or relays)
    output reg         sw_read_data,     // Read data pair termination
    output reg         sw_read_clk,      // Read clock pair termination
    output reg         sw_samk,          // SAMK pair termination
    output reg         sw_index          // Index pair termination
);

    // Simple pass-through with synchronization
    always @(posedge clk) begin
        if (reset) begin
            sw_read_data <= 1'b0;
            sw_read_clk <= 1'b0;
            sw_samk <= 1'b0;
            sw_index <= 1'b0;
        end else begin
            sw_read_data <= enable & pair_select[0];
            sw_read_clk  <= enable & pair_select[1];
            sw_samk      <= enable & pair_select[2];
            sw_index     <= enable & pair_select[3];
        end
    end

endmodule
