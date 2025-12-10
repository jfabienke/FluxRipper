//-----------------------------------------------------------------------------
// Hard-Sector Disk Detector
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Detects hard-sectored disks by counting sector holes (pulses) between
// index pulses. Hard-sectored 8" disks have physical holes punched in them
// that generate electrical pulses as they pass the sensor.
//
// Common hard-sector formats:
//   - 10 sectors: DEC RX01/RX02, Intel SBC systems
//   - 16 sectors: North Star, Cromemco
//   - 26 sectors: IBM 3740 (CP/M origin)
//   - 32 sectors: Some 5.25" systems
//
// Detection Algorithm:
//   1. Wait for index pulse (start of revolution)
//   2. Count pulses on flux_stream or dedicated sector line until next index
//   3. If count > 0 and consistent across revolutions, disk is hard-sectored
//
// Target: AMD Spartan UltraScale+ SCU35
// Created: 2025-12-10
//-----------------------------------------------------------------------------

module hard_sector_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Input signals
    input  wire        index_pulse,      // Index pulse (once per revolution)
    input  wire        flux_stream,      // Flux/sector pulse stream

    // Detection outputs
    output reg         sector_detected,  // Hard-sector disk detected
    output reg  [3:0]  sector_count      // Number of sectors detected (0-15)
);

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    localparam [7:0] MIN_SECTORS = 8'd10;   // Minimum valid sector count
    localparam [7:0] MAX_SECTORS = 8'd32;   // Maximum valid sector count
    localparam [2:0] CONFIRM_REVS = 3'd3;   // Revolutions to confirm count

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [1:0] ST_WAIT_INDEX    = 2'd0;  // Wait for first index
    localparam [1:0] ST_COUNTING      = 2'd1;  // Count sector pulses
    localparam [1:0] ST_VERIFY        = 2'd2;  // Verify count consistency
    localparam [1:0] ST_DETECTED      = 2'd3;  // Hard-sector confirmed

    reg [1:0]  state;

    //-------------------------------------------------------------------------
    // Pulse Detection
    //-------------------------------------------------------------------------
    reg [2:0]  index_sync;
    reg [2:0]  flux_sync;
    wire       index_edge;
    wire       flux_edge;

    always @(posedge clk) begin
        index_sync <= {index_sync[1:0], index_pulse};
        flux_sync  <= {flux_sync[1:0], flux_stream};
    end

    assign index_edge = (index_sync[2:1] == 2'b01);  // Rising edge
    assign flux_edge  = (flux_sync[2:1] == 2'b01);   // Rising edge

    //-------------------------------------------------------------------------
    // Counting Logic
    //-------------------------------------------------------------------------
    reg [7:0]  current_count;      // Sector count for current revolution
    reg [7:0]  last_count;         // Sector count from previous revolution
    reg [2:0]  consistent_count;   // How many revolutions with same count
    reg        counting;           // Currently counting sectors

    // Debounce/minimum time between sector pulses
    // At 300 RPM with 32 sectors: ~6.25ms per sector = 1.25M clocks @ 200MHz
    // Use a much smaller window to reject noise but catch real pulses
    localparam [19:0] MIN_SECTOR_INTERVAL = 20'd100_000;  // 0.5ms minimum
    reg [19:0] sector_timer;
    reg        sector_armed;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state            <= ST_WAIT_INDEX;
            current_count    <= 8'd0;
            last_count       <= 8'd0;
            consistent_count <= 3'd0;
            counting         <= 1'b0;
            sector_detected  <= 1'b0;
            sector_count     <= 4'd0;
            sector_timer     <= 20'd0;
            sector_armed     <= 1'b1;
        end else if (!enable) begin
            state            <= ST_WAIT_INDEX;
            sector_detected  <= 1'b0;
        end else begin
            // Sector pulse timing
            if (sector_timer > 0)
                sector_timer <= sector_timer - 1'b1;
            else
                sector_armed <= 1'b1;

            case (state)
                ST_WAIT_INDEX: begin
                    // Wait for first index pulse to start counting
                    if (index_edge) begin
                        current_count <= 8'd0;
                        counting      <= 1'b1;
                        sector_armed  <= 1'b1;
                        sector_timer  <= 20'd0;
                        state         <= ST_COUNTING;
                    end
                end

                ST_COUNTING: begin
                    // Count sector pulses until next index
                    if (flux_edge && sector_armed) begin
                        current_count <= current_count + 1'b1;
                        sector_timer  <= MIN_SECTOR_INTERVAL;
                        sector_armed  <= 1'b0;
                    end

                    if (index_edge) begin
                        // Revolution complete - check count
                        if (current_count >= MIN_SECTORS && current_count <= MAX_SECTORS) begin
                            // Valid sector count range
                            if (current_count == last_count) begin
                                consistent_count <= consistent_count + 1'b1;
                            end else begin
                                consistent_count <= 3'd1;
                            end
                            last_count <= current_count;
                            state <= ST_VERIFY;
                        end else begin
                            // Invalid count or no sectors - soft sector disk
                            last_count       <= 8'd0;
                            consistent_count <= 3'd0;
                        end
                        current_count <= 8'd0;
                        sector_armed  <= 1'b1;
                        sector_timer  <= 20'd0;
                    end
                end

                ST_VERIFY: begin
                    // Continue counting and verify consistency
                    if (flux_edge && sector_armed) begin
                        current_count <= current_count + 1'b1;
                        sector_timer  <= MIN_SECTOR_INTERVAL;
                        sector_armed  <= 1'b0;
                    end

                    if (index_edge) begin
                        if (current_count == last_count) begin
                            consistent_count <= consistent_count + 1'b1;
                            if (consistent_count >= CONFIRM_REVS - 1) begin
                                // Confirmed hard-sector disk
                                sector_detected <= 1'b1;
                                sector_count    <= (last_count > 15) ? 4'd15 : last_count[3:0];
                                state           <= ST_DETECTED;
                            end
                        end else if (current_count >= MIN_SECTORS && current_count <= MAX_SECTORS) begin
                            // Different but valid count - reset consistency
                            consistent_count <= 3'd1;
                            last_count <= current_count;
                        end else begin
                            // Invalid count - probably soft sector with noise
                            consistent_count <= 3'd0;
                            last_count <= 8'd0;
                            state <= ST_COUNTING;
                        end
                        current_count <= 8'd0;
                        sector_armed  <= 1'b1;
                        sector_timer  <= 20'd0;
                    end
                end

                ST_DETECTED: begin
                    // Hard-sector confirmed - stay in this state
                    sector_detected <= 1'b1;
                    // Could optionally continue monitoring for disk change
                end

                default: state <= ST_WAIT_INDEX;
            endcase
        end
    end

endmodule
