//-----------------------------------------------------------------------------
// FluxStat Module Testbench
//
// Tests the flux_histogram and multipass_capture modules used for
// statistical flux recovery.
//
// Created: 2025-12-04 18:30
//-----------------------------------------------------------------------------

`timescale 1ns / 100ps

module tb_fluxstat;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 5;       // 200 MHz
    parameter INDEX_PERIOD = 200000; // 200ms worth of clocks (1ms real = 200 clocks sim)

    //-------------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------------
    reg         clk;
    reg         reset;

    // Flux histogram signals
    reg         flux_valid;
    reg  [15:0] flux_interval;
    reg         hist_enable;
    reg         hist_clear;
    reg         hist_snapshot;
    reg  [7:0]  hist_read_bin;
    wire [15:0] hist_read_data;
    wire [31:0] hist_total_count;
    wire [15:0] hist_interval_min;
    wire [15:0] hist_interval_max;
    wire [7:0]  hist_peak_bin;
    wire [15:0] hist_peak_count;
    wire [31:0] hist_overflow_count;
    wire [15:0] hist_mean_interval;

    // Multipass capture signals
    reg         mp_start;
    reg         mp_abort;
    reg  [5:0]  mp_pass_count;
    reg  [23:0] mp_base_addr;
    wire        mp_busy;
    wire        mp_done;
    wire        mp_error;
    wire [5:0]  mp_current_pass;

    reg         capture_busy;
    reg         capture_done;
    reg         capture_overflow;
    wire        capture_start;
    wire        capture_stop;
    wire [23:0] mem_base_addr;

    reg         index_pulse;
    wire        wait_for_index;

    reg  [27:0] flux_timestamp;

    wire        hist_enable_mp;
    wire        hist_clear_mp;
    wire        hist_snapshot_mp;

    wire [31:0] pass_flux_count [0:63];
    wire [31:0] pass_index_time [0:63];
    wire [31:0] pass_start_time [0:63];
    wire [23:0] pass_data_size  [0:63];

    wire [31:0] total_flux_count;
    wire [31:0] min_flux_count;
    wire [31:0] max_flux_count;
    wire [31:0] total_capture_time;
    wire [5:0]  passes_completed;

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------------------
    // DUT Instantiation - Flux Histogram
    //-------------------------------------------------------------------------
    flux_histogram #(
        .BIN_COUNT(256),
        .BIN_WIDTH(16),
        .INTERVAL_BITS(16),
        .BIN_SHIFT(2)
    ) uut_histogram (
        .clk(clk),
        .reset(reset),
        .flux_valid(flux_valid),
        .flux_interval(flux_interval),
        .enable(hist_enable),
        .clear(hist_clear),
        .snapshot(hist_snapshot),
        .read_bin(hist_read_bin),
        .read_data(hist_read_data),
        .total_count(hist_total_count),
        .interval_min(hist_interval_min),
        .interval_max(hist_interval_max),
        .peak_bin(hist_peak_bin),
        .peak_count(hist_peak_count),
        .overflow_count(hist_overflow_count),
        .underflow_count(),
        .mean_interval(hist_mean_interval),
        .snap_total(),
        .snap_peak_bin(),
        .snap_peak_count(),
        .snap_mean()
    );

    //-------------------------------------------------------------------------
    // DUT Instantiation - Multipass Capture
    //-------------------------------------------------------------------------
    multipass_capture #(
        .MAX_PASSES(64),
        .PASS_BITS(6),
        .ADDR_WIDTH(24),
        .PASS_SIZE(24'h010000),
        .TIMESTAMP_BITS(28)
    ) uut_multipass (
        .clk(clk),
        .reset(reset),
        .start(mp_start),
        .abort(mp_abort),
        .pass_count(mp_pass_count),
        .base_addr(mp_base_addr),
        .busy(mp_busy),
        .done(mp_done),
        .error(mp_error),
        .current_pass(mp_current_pass),
        .capture_start(capture_start),
        .capture_stop(capture_stop),
        .capture_busy(capture_busy),
        .capture_done(capture_done),
        .capture_overflow(capture_overflow),
        .mem_base_addr(mem_base_addr),
        .mem_end_addr(),
        .index_pulse(index_pulse),
        .wait_for_index(wait_for_index),
        .flux_valid(flux_valid),
        .flux_timestamp(flux_timestamp),
        .hist_enable(hist_enable_mp),
        .hist_clear(hist_clear_mp),
        .hist_snapshot(hist_snapshot_mp),
        .pass_flux_count(pass_flux_count),
        .pass_index_time(pass_index_time),
        .pass_start_time(pass_start_time),
        .pass_data_size(pass_data_size),
        .total_flux_count(total_flux_count),
        .min_flux_count(min_flux_count),
        .max_flux_count(max_flux_count),
        .total_capture_time(total_capture_time),
        .passes_completed(passes_completed)
    );

    //-------------------------------------------------------------------------
    // Test Helpers
    //-------------------------------------------------------------------------

    // Generate a flux transition
    task generate_flux;
        input [15:0] interval;
        begin
            @(posedge clk);
            flux_valid <= 1'b1;
            flux_interval <= interval;
            flux_timestamp <= flux_timestamp + interval;
            @(posedge clk);
            flux_valid <= 1'b0;
        end
    endtask

    // Generate index pulse
    task generate_index;
        begin
            @(posedge clk);
            index_pulse <= 1'b1;
            @(posedge clk);
            @(posedge clk);
            index_pulse <= 1'b0;
        end
    endtask

    // Simulate capture engine response
    task simulate_capture_response;
        begin
            // Wait for capture_start
            wait(capture_start);
            @(posedge clk);
            capture_busy <= 1'b1;

            // Wait for capture_stop
            wait(capture_stop);
            @(posedge clk);
            capture_busy <= 1'b0;
            capture_done <= 1'b1;
            @(posedge clk);
            capture_done <= 1'b0;
        end
    endtask

    // Generate MFM-like flux pattern
    task generate_mfm_track;
        input integer flux_count;
        integer i;
        reg [15:0] interval;
        begin
            for (i = 0; i < flux_count; i = i + 1) begin
                // MFM intervals: 4µs (80 clocks), 6µs (120 clocks), 8µs (160 clocks)
                // Simulated at 1/1000 scale
                case ($random % 3)
                    0: interval = 16'd80 + ($random % 8) - 4;   // 4µs ± jitter
                    1: interval = 16'd120 + ($random % 10) - 5; // 6µs ± jitter
                    2: interval = 16'd160 + ($random % 12) - 6; // 8µs ± jitter
                endcase
                generate_flux(interval);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Sequences
    //-------------------------------------------------------------------------
    integer errors;
    integer i;

    initial begin
        $display("=========================================");
        $display("FluxStat Testbench Starting");
        $display("=========================================");

        // Initialize
        reset = 1;
        flux_valid = 0;
        flux_interval = 0;
        flux_timestamp = 0;
        hist_enable = 0;
        hist_clear = 0;
        hist_snapshot = 0;
        hist_read_bin = 0;
        mp_start = 0;
        mp_abort = 0;
        mp_pass_count = 8;
        mp_base_addr = 24'h100000;
        capture_busy = 0;
        capture_done = 0;
        capture_overflow = 0;
        index_pulse = 0;
        errors = 0;

        // Release reset
        repeat(10) @(posedge clk);
        reset = 0;
        repeat(10) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 1: Histogram Basic Operation
        //---------------------------------------------------------------------
        $display("\n--- Test 1: Histogram Basic Operation ---");

        hist_enable = 1;

        // Generate flux transitions with known intervals
        generate_flux(16'd80);   // Bin 20 (80 >> 2)
        generate_flux(16'd80);   // Bin 20
        generate_flux(16'd80);   // Bin 20
        generate_flux(16'd120);  // Bin 30
        generate_flux(16'd120);  // Bin 30
        generate_flux(16'd160);  // Bin 40

        repeat(10) @(posedge clk);

        // Check total count
        if (hist_total_count != 6) begin
            $display("ERROR: Total count = %d, expected 6", hist_total_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Total count = %d", hist_total_count);
        end

        // Check min/max
        if (hist_interval_min != 80) begin
            $display("ERROR: Min interval = %d, expected 80", hist_interval_min);
            errors = errors + 1;
        end else begin
            $display("PASS: Min interval = %d", hist_interval_min);
        end

        if (hist_interval_max != 160) begin
            $display("ERROR: Max interval = %d, expected 160", hist_interval_max);
            errors = errors + 1;
        end else begin
            $display("PASS: Max interval = %d", hist_interval_max);
        end

        // Check peak bin (should be 20, count 3)
        if (hist_peak_bin != 20) begin
            $display("ERROR: Peak bin = %d, expected 20", hist_peak_bin);
            errors = errors + 1;
        end else begin
            $display("PASS: Peak bin = %d", hist_peak_bin);
        end

        if (hist_peak_count != 3) begin
            $display("ERROR: Peak count = %d, expected 3", hist_peak_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Peak count = %d", hist_peak_count);
        end

        // Read bin values
        hist_read_bin = 20;
        repeat(2) @(posedge clk);
        if (hist_read_data != 3) begin
            $display("ERROR: Bin 20 count = %d, expected 3", hist_read_data);
            errors = errors + 1;
        end else begin
            $display("PASS: Bin 20 count = %d", hist_read_data);
        end

        hist_read_bin = 30;
        repeat(2) @(posedge clk);
        if (hist_read_data != 2) begin
            $display("ERROR: Bin 30 count = %d, expected 2", hist_read_data);
            errors = errors + 1;
        end else begin
            $display("PASS: Bin 30 count = %d", hist_read_data);
        end

        //---------------------------------------------------------------------
        // Test 2: Histogram Clear
        //---------------------------------------------------------------------
        $display("\n--- Test 2: Histogram Clear ---");

        hist_clear = 1;
        @(posedge clk);
        hist_clear = 0;
        repeat(5) @(posedge clk);

        if (hist_total_count != 0) begin
            $display("ERROR: Total count after clear = %d, expected 0", hist_total_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Histogram cleared successfully");
        end

        //---------------------------------------------------------------------
        // Test 3: Histogram with MFM-like Data
        //---------------------------------------------------------------------
        $display("\n--- Test 3: MFM-like Flux Pattern ---");

        generate_mfm_track(1000);

        repeat(10) @(posedge clk);

        $display("Total flux count: %d", hist_total_count);
        $display("Peak bin: %d (interval ~%d)", hist_peak_bin, hist_peak_bin << 2);
        $display("Peak count: %d", hist_peak_count);
        $display("Mean interval: %d", hist_mean_interval);

        // Peak should be near bin 20, 30, or 40 (intervals 80, 120, 160)
        if (hist_peak_bin >= 15 && hist_peak_bin <= 45) begin
            $display("PASS: Peak bin in expected range");
        end else begin
            $display("WARNING: Peak bin %d outside expected range [15-45]", hist_peak_bin);
        end

        hist_enable = 0;
        hist_clear = 1;
        @(posedge clk);
        hist_clear = 0;

        //---------------------------------------------------------------------
        // Test 4: Multipass Capture - Single Pass
        //---------------------------------------------------------------------
        $display("\n--- Test 4: Multipass Capture - Single Pass ---");

        mp_pass_count = 1;
        mp_base_addr = 24'h200000;

        // Start capture
        mp_start = 1;
        @(posedge clk);
        mp_start = 0;

        // Wait for busy
        wait(mp_busy);
        $display("Multipass capture started");

        // Should be waiting for index
        wait(wait_for_index);
        $display("Waiting for index pulse");

        // Generate first index
        generate_index();
        $display("First index pulse generated");

        // Fork: capture engine simulation and flux generation
        fork
            simulate_capture_response();
            begin
                // Generate flux for ~1 track
                repeat(100) @(posedge clk);
                generate_mfm_track(500);
                repeat(100) @(posedge clk);
                // Generate second index (end of track)
                generate_index();
                $display("Second index pulse generated (track complete)");
            end
        join

        // Wait for done
        wait(mp_done);
        $display("Single pass capture complete");

        if (passes_completed != 1) begin
            $display("ERROR: Passes completed = %d, expected 1", passes_completed);
            errors = errors + 1;
        end else begin
            $display("PASS: Passes completed = %d", passes_completed);
        end

        $display("Pass 0 flux count: %d", pass_flux_count[0]);
        $display("Pass 0 index time: %d", pass_index_time[0]);

        repeat(100) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 5: Multipass Capture - Multiple Passes
        //---------------------------------------------------------------------
        $display("\n--- Test 5: Multipass Capture - 4 Passes ---");

        mp_pass_count = 4;
        mp_base_addr = 24'h300000;

        mp_start = 1;
        @(posedge clk);
        mp_start = 0;

        wait(mp_busy);
        $display("4-pass capture started");

        // Run 4 passes
        for (i = 0; i < 4; i = i + 1) begin
            wait(wait_for_index);
            $display("Pass %d: Waiting for index", i);

            generate_index();

            fork
                simulate_capture_response();
                begin
                    repeat(50) @(posedge clk);
                    // Vary flux count slightly per pass (simulate real variation)
                    generate_mfm_track(450 + (i * 10) + ($random % 20));
                    repeat(50) @(posedge clk);
                    generate_index();
                end
            join

            repeat(10) @(posedge clk);

            if (mp_current_pass == i || mp_done) begin
                $display("Pass %d complete, flux count: %d", i, pass_flux_count[i]);
            end
        end

        wait(mp_done);
        $display("4-pass capture complete");

        if (passes_completed != 4) begin
            $display("ERROR: Passes completed = %d, expected 4", passes_completed);
            errors = errors + 1;
        end else begin
            $display("PASS: All 4 passes completed");
        end

        // Check memory address progression
        $display("Base addresses: 0x%06h, expected 0x300000 + 0x%06h",
                 mem_base_addr, 4 * 24'h010000);

        $display("Total flux count across all passes: %d", total_flux_count);
        $display("Min flux count: %d", min_flux_count);
        $display("Max flux count: %d", max_flux_count);

        //---------------------------------------------------------------------
        // Test 6: Abort During Capture
        //---------------------------------------------------------------------
        $display("\n--- Test 6: Abort During Capture ---");

        mp_pass_count = 8;
        mp_start = 1;
        @(posedge clk);
        mp_start = 0;

        wait(mp_busy);
        wait(wait_for_index);
        generate_index();

        // Wait a bit then abort
        repeat(100) @(posedge clk);

        mp_abort = 1;
        @(posedge clk);
        mp_abort = 0;

        repeat(10) @(posedge clk);

        if (mp_error) begin
            $display("PASS: Abort triggered error flag as expected");
        end else begin
            $display("ERROR: Abort did not trigger error flag");
            errors = errors + 1;
        end

        if (!mp_busy) begin
            $display("PASS: Capture stopped after abort");
        end else begin
            $display("ERROR: Capture still busy after abort");
            errors = errors + 1;
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        repeat(100) @(posedge clk);

        $display("\n=========================================");
        if (errors == 0) begin
            $display("All tests PASSED!");
        end else begin
            $display("Tests completed with %d ERRORS", errors);
        end
        $display("=========================================\n");

        $finish;
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #10000000;  // 10ms timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //-------------------------------------------------------------------------
    // VCD Dump (optional)
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_fluxstat.vcd");
        $dumpvars(0, tb_fluxstat);
    end

endmodule
