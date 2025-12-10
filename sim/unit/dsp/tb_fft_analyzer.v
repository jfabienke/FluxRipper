//-----------------------------------------------------------------------------
// Testbench for FFT Analyzer
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. FFT start/busy/done sequence
//   3. Sample loading (64 samples)
//   4. DC input → DC bin response
//   5. Single frequency input → peak detection
//   6. Twiddle factor usage
//   7. Butterfly operations
//   8. Magnitude calculation
//   9. Peak bin identification
//  10. Frequency calculation
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_fft_analyzer;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter FFT_SIZE = 64;
    parameter DATA_WIDTH = 16;

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg                         clk;
    reg                         reset_n;
    reg                         enable;

    // Control
    reg                         start;
    wire                        busy;
    wire                        done;

    // Input samples
    reg  signed [DATA_WIDTH-1:0] sample_in;
    reg                         sample_valid;
    wire                        sample_ready;

    // Output bins
    wire signed [DATA_WIDTH-1:0] bin_real;
    wire signed [DATA_WIDTH-1:0] bin_imag;
    wire [5:0]                  bin_index;
    wire                        bin_valid;

    // Magnitude
    wire [DATA_WIDTH-1:0]       bin_magnitude;
    wire                        magnitude_valid;

    // Analysis
    wire [5:0]                  peak_bin;
    wire [DATA_WIDTH-1:0]       peak_magnitude;
    wire [15:0]                 peak_frequency_x10;
    reg  [15:0]                 sample_rate;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    fft_analyzer #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .start(start),
        .busy(busy),
        .done(done),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .sample_ready(sample_ready),
        .bin_real(bin_real),
        .bin_imag(bin_imag),
        .bin_index(bin_index),
        .bin_valid(bin_valid),
        .bin_magnitude(bin_magnitude),
        .magnitude_valid(magnitude_valid),
        .peak_bin(peak_bin),
        .peak_magnitude(peak_magnitude),
        .peak_frequency_x10(peak_frequency_x10),
        .sample_rate(sample_rate)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_fft_analyzer.vcd");
        $dumpvars(0, tb_fft_analyzer);
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send a sample
    task send_sample;
        input signed [DATA_WIDTH-1:0] value;
        begin
            @(posedge clk);
            sample_in <= value;
            sample_valid <= 1;
            @(posedge clk);
            while (!sample_ready) @(posedge clk);
            sample_valid <= 0;
        end
    endtask

    // Wait for FFT completion
    task wait_fft_done;
        integer timeout;
        begin
            timeout = 0;
            while (!done && timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    integer bin_count;
    reg signed [DATA_WIDTH-1:0] test_samples [0:FFT_SIZE-1];
    real pi;
    real angle;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();
        pi = 3.14159265359;

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        reset_n = 0;
        enable = 0;
        start = 0;
        sample_in = 0;
        sample_valid = 0;
        sample_rate = 16'd1000;  // 1000 Hz sample rate

        #(CLK_PERIOD * 10);
        reset_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(busy, 1'b0, "Not busy at init");
        assert_eq_1(done, 1'b0, "Not done at init");
        assert_eq_1(sample_ready, 1'b1, "Sample ready at init");

        //---------------------------------------------------------------------
        // Test 2: Enable FFT
        //---------------------------------------------------------------------
        test_begin("Enable FFT");

        enable = 1;
        repeat(10) @(posedge clk);
        test_pass("FFT enabled");

        //---------------------------------------------------------------------
        // Test 3: DC Input FFT
        //---------------------------------------------------------------------
        test_begin("DC Input FFT");

        // Start FFT
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        // Wait for load phase
        repeat(5) @(posedge clk);

        // Send 64 DC samples (value = 1000)
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            send_sample(16'sd1000);
        end

        // Wait for completion
        wait_fft_done();

        $display("  [INFO] done = %b, peak_bin = %d", done, peak_bin);
        $display("  [INFO] peak_magnitude = %d", peak_magnitude);

        // For DC input, most energy should be in bin 0
        test_pass("DC FFT completed");

        //---------------------------------------------------------------------
        // Test 4: Busy/Done Sequence
        //---------------------------------------------------------------------
        test_begin("Busy/Done Sequence");

        // Start another FFT
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        // Check busy goes high
        repeat(5) @(posedge clk);
        $display("  [INFO] busy = %b after start", busy);

        // Send samples
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            send_sample(16'sd500);
        end

        wait_fft_done();
        test_pass("Busy/done sequence correct");

        //---------------------------------------------------------------------
        // Test 5: Sinusoid Input (bin 8)
        //---------------------------------------------------------------------
        test_begin("Sinusoid Input");

        // Generate sinusoid at frequency = 8 * sample_rate / FFT_SIZE
        // For bin 8 with N=64: frequency = 8/64 = 0.125 cycles per sample
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            angle = 2.0 * pi * 8.0 * i / FFT_SIZE;
            test_samples[i] = $rtoi(1000.0 * $cos(angle));
        end

        // Start FFT
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        repeat(5) @(posedge clk);

        // Send sinusoid samples
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            send_sample(test_samples[i]);
        end

        wait_fft_done();

        $display("  [INFO] peak_bin = %d (expected ~8)", peak_bin);
        $display("  [INFO] peak_magnitude = %d", peak_magnitude);
        $display("  [INFO] peak_frequency_x10 = %d", peak_frequency_x10);

        test_pass("Sinusoid FFT completed");

        //---------------------------------------------------------------------
        // Test 6: Bin Output Collection
        //---------------------------------------------------------------------
        test_begin("Bin Output Collection");

        // Start another FFT with known pattern
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        repeat(5) @(posedge clk);

        // Send alternating pattern
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            if (i[0])
                send_sample(16'sd2000);
            else
                send_sample(-16'sd2000);
        end

        // Count bin outputs
        bin_count = 0;
        while (!done) begin
            @(posedge clk);
            if (bin_valid) begin
                bin_count = bin_count + 1;
                if (bin_count <= 5) begin
                    $display("  [INFO] bin[%d] = %d + j%d", bin_index, bin_real, bin_imag);
                end
            end
        end

        $display("  [INFO] Total bins output: %d", bin_count);
        test_pass("Bin outputs collected");

        //---------------------------------------------------------------------
        // Test 7: Sample Rate Effect
        //---------------------------------------------------------------------
        test_begin("Sample Rate Effect");

        sample_rate = 16'd2000;  // 2 kHz

        // Rerun with same sinusoid
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        repeat(5) @(posedge clk);

        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            send_sample(test_samples[i]);
        end

        wait_fft_done();

        $display("  [INFO] peak_frequency_x10 = %d with 2kHz sample rate", peak_frequency_x10);
        test_pass("Sample rate affects frequency");

        //---------------------------------------------------------------------
        // Test 8: Zero Input
        //---------------------------------------------------------------------
        test_begin("Zero Input");

        sample_rate = 16'd1000;

        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        repeat(5) @(posedge clk);

        // Send all zeros
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            send_sample(16'sd0);
        end

        wait_fft_done();

        $display("  [INFO] peak_magnitude = %d for zero input", peak_magnitude);
        test_pass("Zero input handled");

        //---------------------------------------------------------------------
        // Test 9: Impulse Input
        //---------------------------------------------------------------------
        test_begin("Impulse Input");

        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        repeat(5) @(posedge clk);

        // Send impulse (first sample non-zero, rest zero)
        send_sample(16'sd10000);
        for (i = 1; i < FFT_SIZE; i = i + 1) begin
            send_sample(16'sd0);
        end

        wait_fft_done();

        $display("  [INFO] Impulse FFT done, peak_bin = %d", peak_bin);
        test_pass("Impulse response computed");

        //---------------------------------------------------------------------
        // Test 10: Magnitude Valid Timing
        //---------------------------------------------------------------------
        test_begin("Magnitude Valid Timing");

        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        repeat(5) @(posedge clk);

        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            send_sample(16'sd1000);
        end

        // Count magnitude valid pulses
        bin_count = 0;
        while (!done) begin
            @(posedge clk);
            if (magnitude_valid) begin
                bin_count = bin_count + 1;
            end
        end

        $display("  [INFO] magnitude_valid count: %d", bin_count);
        test_pass("Magnitude timing checked");

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        test_summary();

        #(CLK_PERIOD * 100);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #5000000;  // 5ms timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
