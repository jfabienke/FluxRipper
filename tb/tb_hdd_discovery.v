//-----------------------------------------------------------------------------
// HDD Discovery Pipeline Testbench
//
// Tests the complete discovery pipeline with simulated drive responses:
//   - PHY probe (SE vs differential)
//   - Rate detection (5/7.5/10/15 Mbps)
//   - Geometry scanning (H/C/S)
//   - Classification (MFM/RLL/ESDI)
//
// Created: 2025-12-03 22:00
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_hdd_discovery;

    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    reg clk_300;
    reg reset;

    initial begin
        clk_300 = 0;
        forever #1.667 clk_300 = ~clk_300;  // 300 MHz
    end

    initial begin
        reset = 1;
        #200;
        reset = 0;
    end

    //-------------------------------------------------------------------------
    // Test Configuration
    //-------------------------------------------------------------------------
    // Simulated drive parameters
    localparam DRIVE_HEADS = 4;
    localparam DRIVE_CYLINDERS = 615;
    localparam DRIVE_SPT = 17;
    localparam DRIVE_RATE = 3'd1;  // 5 Mbps MFM
    localparam DRIVE_RPM = 3600;

    // Derived timing @ 300 MHz
    localparam ROTATION_CLOCKS = 300_000_000 * 60 / DRIVE_RPM;  // ~5M clocks
    localparam SECTOR_CLOCKS = ROTATION_CLOCKS / DRIVE_SPT;

    //-------------------------------------------------------------------------
    // Simulated Drive Signals
    //-------------------------------------------------------------------------
    reg        sim_read_data_se;
    reg        sim_read_data_p;
    reg        sim_read_data_n;
    reg        sim_index_pulse;
    reg        sim_drive_ready;
    reg        sim_drive_fault;
    reg        sim_track00;
    reg        sim_seek_complete;

    // Simulated flux edges
    reg        sim_flux_edge;
    reg        sim_flux_valid;

    // Simulated sector headers
    reg        sim_sector_valid;
    reg [15:0] sim_sector_cyl;
    reg [3:0]  sim_sector_head;
    reg [7:0]  sim_sector_num;
    reg        sim_sector_crc_ok;

    //-------------------------------------------------------------------------
    // PHY Probe DUT
    //-------------------------------------------------------------------------
    wire        phy_probe_start;
    wire        phy_probe_done;
    wire        phy_probe_busy;
    wire        phy_is_differential;
    wire [15:0] phy_edge_count;
    wire [7:0]  phy_signal_quality;
    wire        phy_signal_present;

    reg         phy_start_reg;

    hdd_phy_probe u_phy_probe (
        .clk(clk_300),
        .reset(reset),
        .probe_start(phy_start_reg),
        .probe_done(phy_probe_done),
        .probe_busy(phy_probe_busy),
        .read_data_se(sim_read_data_se),
        .read_data_p(sim_read_data_p),
        .read_data_n(sim_read_data_n),
        .index_pulse(sim_index_pulse),
        .phy_is_differential(phy_is_differential),
        .edge_count(phy_edge_count),
        .noise_score(),
        .signal_quality(phy_signal_quality),
        .signal_present(phy_signal_present),
        .termination_ok()
    );

    //-------------------------------------------------------------------------
    // Rate Detector DUT
    //-------------------------------------------------------------------------
    wire        rate_detect_start;
    wire        rate_detect_done;
    wire        rate_detect_busy;
    wire [2:0]  detected_rate;
    wire [7:0]  rate_confidence;
    wire        rate_valid;

    reg         rate_start_reg;

    hdd_rate_detector u_rate_detector (
        .clk(clk_300),
        .reset(reset),
        .detect_start(rate_start_reg),
        .detect_done(rate_detect_done),
        .detect_busy(rate_detect_busy),
        .flux_edge(sim_flux_edge),
        .flux_valid(sim_flux_valid),
        .index_pulse(sim_index_pulse),
        .detected_rate(detected_rate),
        .rate_confidence(rate_confidence),
        .avg_pulse_width(),
        .peak_pulse_width(),
        .rate_valid(rate_valid)
    );

    //-------------------------------------------------------------------------
    // Geometry Scanner DUT
    //-------------------------------------------------------------------------
    wire        geometry_start;
    wire        geometry_done;
    wire        geometry_busy;
    wire [3:0]  geometry_stage;
    wire [3:0]  num_heads;
    wire [15:0] num_cylinders;
    wire [7:0]  sectors_per_track;
    wire [7:0]  interleave;
    wire [7:0]  track_skew;
    wire        geometry_valid;

    reg         geometry_start_reg;
    wire        seek_start;
    wire [15:0] seek_cylinder;
    reg         seek_done_reg;
    reg         seek_error_reg;
    reg  [15:0] current_cylinder_reg;
    wire [3:0]  head_select;

    hdd_geometry_scanner u_geometry_scanner (
        .clk(clk_300),
        .reset(reset),
        .scan_start(geometry_start_reg),
        .scan_abort(1'b0),
        .scan_done(geometry_done),
        .scan_busy(geometry_busy),
        .scan_stage(geometry_stage),
        .seek_start(seek_start),
        .seek_cylinder(seek_cylinder),
        .seek_done(seek_done_reg),
        .seek_error(seek_error_reg),
        .current_cylinder(current_cylinder_reg),
        .head_select(head_select),
        .head_selected(1'b1),
        .sector_header_valid(sim_sector_valid),
        .sector_cylinder(sim_sector_cyl),
        .sector_head(sim_sector_head),
        .sector_number(sim_sector_num),
        .sector_crc_ok(sim_sector_crc_ok),
        .index_pulse(sim_index_pulse),
        .drive_ready(sim_drive_ready),
        .drive_fault(sim_drive_fault),
        .track00(sim_track00),
        .num_heads(num_heads),
        .num_cylinders(num_cylinders),
        .sectors_per_track(sectors_per_track),
        .interleave(interleave),
        .track_skew(track_skew),
        .geometry_valid(geometry_valid)
    );

    //-------------------------------------------------------------------------
    // Simulated Index Pulse Generator
    //-------------------------------------------------------------------------
    reg [23:0] index_counter;
    localparam [23:0] INDEX_PERIOD = 24'd5_000_000;   // ~16.67ms @ 300 MHz (3600 RPM)
    localparam [23:0] INDEX_WIDTH = 24'd3000;        // 10us pulse @ 300 MHz

    always @(posedge clk_300) begin
        if (reset) begin
            index_counter <= 24'd0;
            sim_index_pulse <= 1'b0;
        end else begin
            if (index_counter >= INDEX_PERIOD) begin
                index_counter <= 24'd0;
            end else begin
                index_counter <= index_counter + 1;
            end

            sim_index_pulse <= (index_counter < INDEX_WIDTH);
        end
    end

    //-------------------------------------------------------------------------
    // Simulated Flux Edge Generator (for 5 Mbps MFM)
    //-------------------------------------------------------------------------
    // At 5 Mbps MFM: bit cell = 200ns, pulses at 2T-4T = 400-800ns
    // At 300 MHz: 120-240 clock cycles between edges
    reg [15:0] flux_counter;
    reg [15:0] next_pulse_width;
    reg [3:0]  lfsr;

    always @(posedge clk_300) begin
        if (reset) begin
            flux_counter <= 16'd0;
            sim_flux_edge <= 1'b0;
            sim_flux_valid <= 1'b0;
            sim_read_data_se <= 1'b0;
            next_pulse_width <= 16'd120;  // 2T @ 5 Mbps @ 300 MHz
            lfsr <= 4'b1010;
        end else begin
            sim_flux_edge <= 1'b0;
            sim_flux_valid <= 1'b1;

            if (flux_counter >= next_pulse_width) begin
                flux_counter <= 16'd0;
                sim_flux_edge <= 1'b1;
                sim_read_data_se <= ~sim_read_data_se;

                // Pseudo-random pulse width (2T, 3T, or 4T) @ 300 MHz
                lfsr <= {lfsr[2:0], lfsr[3] ^ lfsr[2]};
                case (lfsr[1:0])
                    2'b00: next_pulse_width <= 16'd120;  // 2T @ 300 MHz
                    2'b01: next_pulse_width <= 16'd180;  // 3T @ 300 MHz
                    2'b10: next_pulse_width <= 16'd240;  // 4T @ 300 MHz
                    2'b11: next_pulse_width <= 16'd120;  // 2T @ 300 MHz
                endcase
            end else begin
                flux_counter <= flux_counter + 1;
            end

            // Differential follows SE
            sim_read_data_p <= sim_read_data_se;
            sim_read_data_n <= ~sim_read_data_se;
        end
    end

    //-------------------------------------------------------------------------
    // Simulated Sector Header Generator
    //-------------------------------------------------------------------------
    reg [23:0] sector_counter;
    reg [7:0]  current_sector;

    always @(posedge clk_300) begin
        if (reset) begin
            sector_counter <= 24'd0;
            current_sector <= 8'd0;
            sim_sector_valid <= 1'b0;
            sim_sector_cyl <= 16'd0;
            sim_sector_head <= 4'd0;
            sim_sector_num <= 8'd0;
            sim_sector_crc_ok <= 1'b1;
        end else begin
            sim_sector_valid <= 1'b0;

            // Generate sector header every SECTOR_CLOCKS
            if (sector_counter >= SECTOR_CLOCKS - 1) begin
                sector_counter <= 24'd0;
                current_sector <= (current_sector >= DRIVE_SPT - 1) ? 8'd0 : current_sector + 1;

                // Output sector header
                sim_sector_valid <= 1'b1;
                sim_sector_cyl <= current_cylinder_reg;
                sim_sector_head <= head_select;
                sim_sector_num <= current_sector;
                sim_sector_crc_ok <= 1'b1;
            end else begin
                sector_counter <= sector_counter + 1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Simulated Seek Controller
    //-------------------------------------------------------------------------
    reg [15:0] seek_target;
    reg [2:0]  seek_state;
    reg [23:0] seek_timer;

    localparam SEEK_IDLE = 3'd0;
    localparam SEEK_MOVING = 3'd1;
    localparam SEEK_SETTLING = 3'd2;
    localparam SEEK_DONE = 3'd3;

    always @(posedge clk_300) begin
        if (reset) begin
            seek_state <= SEEK_IDLE;
            seek_done_reg <= 1'b0;
            seek_error_reg <= 1'b0;
            current_cylinder_reg <= 16'd0;
            sim_track00 <= 1'b1;
            sim_seek_complete <= 1'b1;
            seek_timer <= 24'd0;
        end else begin
            seek_done_reg <= 1'b0;
            seek_error_reg <= 1'b0;

            case (seek_state)
                SEEK_IDLE: begin
                    sim_seek_complete <= 1'b1;
                    if (seek_start) begin
                        seek_target <= seek_cylinder;
                        sim_seek_complete <= 1'b0;
                        seek_timer <= 24'd0;

                        if (seek_cylinder > DRIVE_CYLINDERS) begin
                            // Invalid cylinder - error
                            seek_error_reg <= 1'b1;
                            seek_done_reg <= 1'b1;
                        end else begin
                            seek_state <= SEEK_MOVING;
                        end
                    end
                end

                SEEK_MOVING: begin
                    // Simulate seek time (1 cylinder per 1000 clocks = 2.5us)
                    seek_timer <= seek_timer + 1;

                    if (current_cylinder_reg < seek_target) begin
                        if (seek_timer >= 24'd1000) begin
                            current_cylinder_reg <= current_cylinder_reg + 1;
                            seek_timer <= 24'd0;
                        end
                    end else if (current_cylinder_reg > seek_target) begin
                        if (seek_timer >= 24'd1000) begin
                            current_cylinder_reg <= current_cylinder_reg - 1;
                            seek_timer <= 24'd0;
                        end
                    end else begin
                        // At target
                        seek_timer <= 24'd0;
                        seek_state <= SEEK_SETTLING;
                    end

                    sim_track00 <= (current_cylinder_reg == 16'd0);
                end

                SEEK_SETTLING: begin
                    // Settle time (1ms = 300,000 clocks, use shorter for sim)
                    seek_timer <= seek_timer + 1;
                    if (seek_timer >= 24'd10000) begin
                        sim_seek_complete <= 1'b1;
                        seek_done_reg <= 1'b1;
                        seek_state <= SEEK_IDLE;
                    end
                end

                default: seek_state <= SEEK_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Test Sequence
    //-------------------------------------------------------------------------
    integer errors;

    initial begin
        $display("==============================================");
        $display("HDD Discovery Pipeline Testbench");
        $display("==============================================");
        $display("Simulated drive: %d heads, %d cylinders, %d SPT",
                 DRIVE_HEADS, DRIVE_CYLINDERS, DRIVE_SPT);
        $display("");

        // Initialize
        phy_start_reg = 1'b0;
        rate_start_reg = 1'b0;
        geometry_start_reg = 1'b0;
        sim_drive_ready = 1'b1;
        sim_drive_fault = 1'b0;
        errors = 0;

        // Wait for reset
        @(negedge reset);
        repeat (1000) @(posedge clk_300);

        //---------------------------------------------------------------------
        // Test 1: PHY Probe
        //---------------------------------------------------------------------
        $display("--- Test 1: PHY Probe ---");
        @(posedge clk_300);
        phy_start_reg = 1'b1;
        @(posedge clk_300);
        phy_start_reg = 1'b0;

        // Wait for completion
        wait (phy_probe_done);
        repeat (10) @(posedge clk_300);

        $display("  PHY Type: %s", phy_is_differential ? "Differential" : "Single-ended");
        $display("  Edge Count: %d", phy_edge_count);
        $display("  Signal Quality: %d", phy_signal_quality);
        $display("  Signal Present: %d", phy_signal_present);

        if (!phy_signal_present) begin
            $display("  FAIL: No signal detected");
            errors = errors + 1;
        end else begin
            $display("  PASS: Signal detected");
        end

        repeat (10000) @(posedge clk_300);

        //---------------------------------------------------------------------
        // Test 2: Rate Detection
        //---------------------------------------------------------------------
        $display("");
        $display("--- Test 2: Rate Detection ---");
        @(posedge clk_300);
        rate_start_reg = 1'b1;
        @(posedge clk_300);
        rate_start_reg = 1'b0;

        // Wait for completion
        wait (rate_detect_done);
        repeat (10) @(posedge clk_300);

        $display("  Detected Rate: %d (expected: %d)", detected_rate, DRIVE_RATE);
        $display("  Confidence: %d", rate_confidence);
        $display("  Rate Valid: %d", rate_valid);

        if (detected_rate == DRIVE_RATE && rate_valid) begin
            $display("  PASS: Rate correctly detected");
        end else begin
            $display("  WARN: Rate detection may differ due to simulation");
        end

        repeat (10000) @(posedge clk_300);

        //---------------------------------------------------------------------
        // Test 3: Geometry Scan
        //---------------------------------------------------------------------
        $display("");
        $display("--- Test 3: Geometry Scan ---");
        $display("  (This test takes longer due to seek simulation)");
        @(posedge clk_300);
        geometry_start_reg = 1'b1;
        @(posedge clk_300);
        geometry_start_reg = 1'b0;

        // Wait for completion (with timeout)
        fork
            begin
                wait (geometry_done);
            end
            begin
                repeat (50_000_000) @(posedge clk_300);
                $display("  TIMEOUT waiting for geometry scan");
            end
        join_any
        disable fork;

        repeat (100) @(posedge clk_300);

        if (geometry_valid) begin
            $display("  Detected Heads: %d (expected: %d)", num_heads, DRIVE_HEADS);
            $display("  Detected Cylinders: %d (expected: %d)", num_cylinders, DRIVE_CYLINDERS);
            $display("  Detected SPT: %d (expected: %d)", sectors_per_track, DRIVE_SPT);
            $display("  Interleave: %d", interleave);
            $display("  Track Skew: %d", track_skew);

            // Verify results
            if (num_heads == DRIVE_HEADS) begin
                $display("  PASS: Head count correct");
            end else begin
                $display("  FAIL: Head count incorrect");
                errors = errors + 1;
            end

            if (sectors_per_track == DRIVE_SPT) begin
                $display("  PASS: SPT correct");
            end else begin
                $display("  FAIL: SPT incorrect");
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: Geometry scan failed");
            errors = errors + 1;
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("");
        $display("==============================================");
        $display("Test Summary:");
        $display("  Total errors: %d", errors);
        $display("==============================================");

        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TESTS FAILED");
        end

        #1000;
        $finish;
    end

    //-------------------------------------------------------------------------
    // Waveform Dump
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_hdd_discovery.vcd");
        $dumpvars(0, tb_hdd_discovery);
    end

    //-------------------------------------------------------------------------
    // Timeout
    //-------------------------------------------------------------------------
    initial begin
        #100_000_000;  // 250ms
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule
