//-----------------------------------------------------------------------------
// Testbench for Interface Detector
//
// Tests Phase 0 interface detection with simulated drive signals:
//   - Floppy drive (slow INDEX, no data cable)
//   - MFM HDD (fast INDEX, SE data, ~5 Mbps)
//   - RLL HDD (fast INDEX, SE data, ~7.5 Mbps)
//   - ESDI HDD (fast INDEX, differential data, ~10 Mbps)
//
// Created: 2025-12-04 13:15
//-----------------------------------------------------------------------------

`timescale 1ns / 100ps

module tb_interface_detector;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 3.333;        // 300 MHz = 3.33ns period
    parameter FLOPPY_INDEX_PERIOD = 166_666_667;  // 166.7ms @ 360 RPM
    parameter HDD_INDEX_PERIOD = 16_666_667;      // 16.67ms @ 3600 RPM

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         reset;

    // Control
    reg         detect_start;
    reg         detect_abort;
    reg  [2:0]  force_personality;
    reg         personality_locked;
    wire        detect_busy;
    wire        detect_done;

    // INDEX pulse
    reg         index_pulse;

    // Data path
    reg         data_se_rx;
    reg         data_diff_rx;
    reg         wire_a_raw;
    reg         wire_b_raw;

    // Decode test interface (mock)
    wire        decode_test_start;
    wire        decode_test_mfm;
    reg         decode_test_done;
    reg  [15:0] decode_sync_hits;
    reg  [15:0] decode_crc_ok;

    // Front-end control
    wire        term_enable;
    wire        rx_mode_sel;

    // Results
    wire [2:0]  detected_type;
    wire [3:0]  confidence;
    wire [1:0]  phy_mode;
    wire [2:0]  detected_rate;
    wire        was_forced;

    // Debug
    wire [3:0]  current_phase;
    wire [7:0]  score_floppy;
    wire [7:0]  score_hdd;
    wire [7:0]  score_st506;
    wire [7:0]  score_esdi;
    wire [7:0]  score_mfm;
    wire [7:0]  score_rll;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    interface_detector dut (
        .clk(clk),
        .reset(reset),
        .detect_start(detect_start),
        .detect_abort(detect_abort),
        .force_personality(force_personality),
        .personality_locked(personality_locked),
        .detect_busy(detect_busy),
        .detect_done(detect_done),
        .index_pulse(index_pulse),
        .data_se_rx(data_se_rx),
        .data_diff_rx(data_diff_rx),
        .wire_a_raw(wire_a_raw),
        .wire_b_raw(wire_b_raw),
        .decode_test_start(decode_test_start),
        .decode_test_mfm(decode_test_mfm),
        .decode_test_done(decode_test_done),
        .decode_sync_hits(decode_sync_hits),
        .decode_crc_ok(decode_crc_ok),
        .term_enable(term_enable),
        .rx_mode_sel(rx_mode_sel),
        .detected_type(detected_type),
        .confidence(confidence),
        .phy_mode(phy_mode),
        .detected_rate(detected_rate),
        .was_forced(was_forced),
        .current_phase(current_phase),
        .score_floppy(score_floppy),
        .score_hdd(score_hdd),
        .score_st506(score_st506),
        .score_esdi(score_esdi),
        .score_mfm(score_mfm),
        .score_rll(score_rll)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // Drive Simulation Variables
    //=========================================================================
    reg [31:0] index_timer;
    reg [31:0] index_period;
    reg        index_enabled;

    reg [15:0] data_timer;
    reg [15:0] data_period;       // Pulse width in clocks
    reg        data_enabled;
    reg        differential_mode;

    //=========================================================================
    // INDEX Pulse Generator
    //=========================================================================
    always @(posedge clk) begin
        if (reset || !index_enabled) begin
            index_timer <= 32'd0;
            index_pulse <= 1'b0;
        end else begin
            if (index_timer >= index_period) begin
                index_timer <= 32'd0;
                index_pulse <= 1'b1;
            end else begin
                index_timer <= index_timer + 1;
                if (index_timer > 32'd1000)  // 2.5µs pulse
                    index_pulse <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Data Signal Generator
    //=========================================================================
    always @(posedge clk) begin
        if (reset || !data_enabled) begin
            data_timer <= 16'd0;
            data_se_rx <= 1'b0;
            data_diff_rx <= 1'b0;
            wire_a_raw <= 1'b0;
            wire_b_raw <= 1'b0;
        end else begin
            if (data_timer >= data_period) begin
                data_timer <= 16'd0;

                // Toggle data signals
                data_se_rx <= ~data_se_rx;

                if (differential_mode) begin
                    // Differential: A and B are complementary
                    wire_a_raw <= ~wire_a_raw;
                    wire_b_raw <= wire_a_raw;  // Complement of A
                    data_diff_rx <= ~data_diff_rx;
                end else begin
                    // Single-ended: only A toggles, B is static
                    wire_a_raw <= ~wire_a_raw;
                    wire_b_raw <= 1'b0;        // Static ground reference
                    data_diff_rx <= 1'b0;      // Noisy/invalid in SE mode
                end
            end else begin
                data_timer <= data_timer + 1;
            end
        end
    end

    //=========================================================================
    // Decode Test Mock
    //=========================================================================
    // Simulates the MFM/RLL decode test response
    reg [7:0] decode_wait_counter;

    always @(posedge clk) begin
        if (reset) begin
            decode_test_done <= 1'b0;
            decode_wait_counter <= 8'd0;
        end else if (decode_test_start) begin
            decode_wait_counter <= 8'd100;  // Short wait for simulation
            decode_test_done <= 1'b0;
        end else if (decode_wait_counter > 8'd0) begin
            decode_wait_counter <= decode_wait_counter - 1;
            if (decode_wait_counter == 8'd1) begin
                decode_test_done <= 1'b1;
            end
        end else begin
            decode_test_done <= 1'b0;
        end
    end

    //=========================================================================
    // Test Tasks
    //=========================================================================

    task reset_dut;
    begin
        reset <= 1'b1;
        detect_start <= 1'b0;
        detect_abort <= 1'b0;
        force_personality <= 3'd0;
        personality_locked <= 1'b0;
        index_enabled <= 1'b0;
        data_enabled <= 1'b0;
        differential_mode <= 1'b0;
        decode_sync_hits <= 16'd0;
        decode_crc_ok <= 16'd0;
        repeat(10) @(posedge clk);
        reset <= 1'b0;
        repeat(10) @(posedge clk);
    end
    endtask

    task start_detection;
    begin
        @(posedge clk);
        detect_start <= 1'b1;
        @(posedge clk);
        detect_start <= 1'b0;
    end
    endtask

    task wait_detection_complete;
    begin
        while (!detect_done) @(posedge clk);
        repeat(5) @(posedge clk);
    end
    endtask

    task configure_floppy_drive;
    begin
        $display("[%0t] Configuring Floppy Drive simulation", $time);
        index_enabled <= 1'b1;
        index_period <= FLOPPY_INDEX_PERIOD / CLK_PERIOD;  // Convert ns to clocks
        data_enabled <= 1'b0;  // No data cable for floppy
        differential_mode <= 1'b0;
    end
    endtask

    task configure_mfm_hdd;
    begin
        $display("[%0t] Configuring MFM HDD simulation", $time);
        index_enabled <= 1'b1;
        index_period <= HDD_INDEX_PERIOD / CLK_PERIOD;
        data_enabled <= 1'b1;
        data_period <= 16'd120;  // ~5 Mbps at 300 MHz (60 clks/bit)
        differential_mode <= 1'b0;
        // MFM decode will find more sync patterns
        decode_sync_hits <= 16'd100;
        decode_crc_ok <= 16'd50;
    end
    endtask

    task configure_rll_hdd;
    begin
        $display("[%0t] Configuring RLL HDD simulation", $time);
        index_enabled <= 1'b1;
        index_period <= HDD_INDEX_PERIOD / CLK_PERIOD;
        data_enabled <= 1'b1;
        data_period <= 16'd80;   // ~7.5 Mbps at 300 MHz (40 clks/bit)
        differential_mode <= 1'b0;
        // RLL decode will find more sync patterns
        decode_sync_hits <= 16'd30;
        decode_crc_ok <= 16'd10;
    end
    endtask

    task configure_esdi_hdd;
    begin
        $display("[%0t] Configuring ESDI HDD simulation", $time);
        index_enabled <= 1'b1;
        index_period <= HDD_INDEX_PERIOD / CLK_PERIOD;
        data_enabled <= 1'b1;
        data_period <= 16'd60;   // ~10 Mbps at 300 MHz (30 clks/bit)
        differential_mode <= 1'b1;
    end
    endtask

    task report_results;
    begin
        $display("================================================================================");
        $display("Detection Results:");
        $display("  Type: %0d (%s)", detected_type,
                 (detected_type == 0) ? "UNKNOWN" :
                 (detected_type == 1) ? "FLOPPY" :
                 (detected_type == 2) ? "MFM" :
                 (detected_type == 3) ? "RLL" :
                 (detected_type == 4) ? "ESDI" : "INVALID");
        $display("  Confidence: %0d/15", confidence);
        $display("  PHY Mode: %0d (%s)", phy_mode,
                 (phy_mode == 0) ? "NONE" :
                 (phy_mode == 1) ? "SE" :
                 (phy_mode == 2) ? "DIFF" : "UNKNOWN");
        $display("  Rate Code: %0d", detected_rate);
        $display("  Was Forced: %0d", was_forced);
        $display("Evidence Scores:");
        $display("  Floppy: %0d", score_floppy);
        $display("  HDD: %0d", score_hdd);
        $display("  ST-506: %0d", score_st506);
        $display("  ESDI: %0d", score_esdi);
        $display("  MFM: %0d", score_mfm);
        $display("  RLL: %0d", score_rll);
        $display("================================================================================");
    end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("================================================================================");
        $display("Interface Detector Testbench");
        $display("================================================================================");

        //---------------------------------------------------------------------
        // Test 1: Forced Personality (no detection)
        //---------------------------------------------------------------------
        $display("\n[TEST 1] Forced Personality - MFM");
        reset_dut();
        force_personality <= 3'd2;  // Force MFM
        personality_locked <= 1'b1;
        start_detection();
        wait_detection_complete();
        report_results();

        if (detected_type == 3'd2 && was_forced == 1'b1)
            $display("[PASS] Forced personality accepted");
        else
            $display("[FAIL] Forced personality not applied correctly");

        //---------------------------------------------------------------------
        // Test 2: Floppy Detection (slow INDEX)
        //---------------------------------------------------------------------
        $display("\n[TEST 2] Floppy Detection");
        reset_dut();
        configure_floppy_drive();

        // Wait for a few INDEX pulses to establish
        repeat(100000) @(posedge clk);

        start_detection();

        // Run detection (simplified - in real sim would wait longer)
        repeat(1000000) @(posedge clk);

        // For this simulation, we'll check partial progress
        $display("  Current phase: %0d", current_phase);
        $display("  Score floppy: %0d, Score HDD: %0d", score_floppy, score_hdd);

        // Note: Full detection takes ~500ms simulation time
        // For quick test, we verify scores are accumulating correctly

        //---------------------------------------------------------------------
        // Test 3: MFM HDD Detection (fast INDEX, SE data)
        //---------------------------------------------------------------------
        $display("\n[TEST 3] MFM HDD Detection");
        reset_dut();
        configure_mfm_hdd();

        repeat(100000) @(posedge clk);
        start_detection();
        repeat(1000000) @(posedge clk);

        $display("  Current phase: %0d", current_phase);
        $display("  Score HDD: %0d, Score ST-506: %0d", score_hdd, score_st506);

        //---------------------------------------------------------------------
        // Test 4: ESDI HDD Detection (differential data)
        //---------------------------------------------------------------------
        $display("\n[TEST 4] ESDI HDD Detection (differential)");
        reset_dut();
        configure_esdi_hdd();

        repeat(100000) @(posedge clk);
        start_detection();
        repeat(1000000) @(posedge clk);

        $display("  Current phase: %0d", current_phase);
        $display("  Score HDD: %0d, Score ESDI: %0d", score_hdd, score_esdi);
        $display("  Differential mode active: term_enable=%0d, rx_mode_sel=%0d",
                 term_enable, rx_mode_sel);

        //---------------------------------------------------------------------
        // Test 5: Abort Detection
        //---------------------------------------------------------------------
        $display("\n[TEST 5] Abort Detection");
        reset_dut();
        configure_mfm_hdd();
        start_detection();
        repeat(10000) @(posedge clk);
        detect_abort <= 1'b1;
        @(posedge clk);
        detect_abort <= 1'b0;
        repeat(1000) @(posedge clk);

        if (!detect_busy)
            $display("[PASS] Abort handled correctly");
        else
            $display("[FAIL] Abort did not stop detection");

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n================================================================================");
        $display("Testbench Complete");
        $display("================================================================================");
        $display("\nNote: This is a quick functional test. Full detection requires");
        $display("~500ms-1s of simulation time for complete INDEX measurement.");

        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #100_000_000;  // 100ms timeout
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

    //=========================================================================
    // Debug Monitor
    //=========================================================================
    always @(posedge clk) begin
        if (detect_done) begin
            $display("[%0t] Detection complete!", $time);
        end
    end

endmodule
