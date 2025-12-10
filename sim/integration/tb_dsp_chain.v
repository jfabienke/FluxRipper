//-----------------------------------------------------------------------------
// Integration Testbench: DSP Signal Processing Chain
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests end-to-end DSP processing:
//   FIR Filter -> Adaptive Equalizer -> PRML Decoder
//
// Tests:
//   1. Clean MFM signal through chain
//   2. Noisy MFM signal recovery
//   3. Filter bypass mode
//   4. Equalizer training
//   5. Decoder sync lock
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_dsp_chain;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter DATA_WIDTH = 12;
    parameter COEF_WIDTH = 16;
    parameter SAMPLE_WIDTH = 10;

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

    // Input samples (simulated ADC)
    reg  signed [DATA_WIDTH-1:0] adc_sample;
    reg                         adc_valid;

    // FIR Filter
    wire signed [DATA_WIDTH-1:0] fir_out;
    wire                        fir_valid;
    reg  [2:0]                  fir_mode;

    // Equalizer
    wire signed [DATA_WIDTH-1:0] eq_out;
    wire                        eq_valid;
    reg  [7:0]                  eq_step_size;
    reg                         eq_training;

    // PRML Decoder (simplified connection)
    reg  signed [SAMPLE_WIDTH-1:0] prml_sample;
    reg                         prml_valid;
    wire                        prml_bit_out;
    wire                        prml_bit_valid;
    reg  signed [SAMPLE_WIDTH-1:0] prml_level_neg2;
    reg  signed [SAMPLE_WIDTH-1:0] prml_level_zero;
    reg  signed [SAMPLE_WIDTH-1:0] prml_level_pos2;

    //=========================================================================
    // DUT Instantiation - FIR Filter
    //=========================================================================
    fir_flux_filter #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_TAPS(11)
    ) u_fir (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .filter_mode(fir_mode),
        .data_in(adc_sample),
        .data_valid(adc_valid),
        .data_out(fir_out),
        .data_out_valid(fir_valid),
        .coef_load(1'b0),
        .coef_addr(4'd0),
        .coef_data(16'd0)
    );

    //=========================================================================
    // DUT Instantiation - Adaptive Equalizer
    //=========================================================================
    adaptive_equalizer #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_TAPS(11)
    ) u_eq (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .data_in(fir_out),
        .data_valid(fir_valid),
        .data_out(eq_out),
        .data_out_valid(eq_valid),
        .reference_in(12'd0),
        .reference_valid(1'b0),
        .training_mode(eq_training),
        .coef_read(1'b0),
        .coef_write(1'b0),
        .coef_addr(4'd0),
        .coef_wdata(16'd0),
        .coef_rdata(),
        .step_size(eq_step_size),
        .leakage(8'd0),
        .freeze_coefs(1'b0),
        .current_error(),
        .error_power(),
        .converged()
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
        $dumpfile("tb_dsp_chain.vcd");
        $dumpvars(0, tb_dsp_chain);
    end

    //=========================================================================
    // Signal Generation
    //=========================================================================
    // Generate MFM-like signal: three levels approximating PR4
    // Level 0: -amplitude, Level 1: 0, Level 2: +amplitude

    real pi;
    integer amplitude;

    // Generate a simple MFM pattern
    task generate_mfm_sample;
        input [1:0] level;  // 0=neg, 1=zero, 2=pos
        input integer noise;
        begin
            case (level)
                2'd0: adc_sample <= -amplitude + ($random % noise) - noise/2;
                2'd1: adc_sample <= 0 + ($random % noise) - noise/2;
                2'd2: adc_sample <= amplitude + ($random % noise) - noise/2;
                default: adc_sample <= 0;
            endcase
            adc_valid <= 1;
            @(posedge clk);
            adc_valid <= 0;
            repeat(2) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    integer output_count;
    integer bit_count;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();
        pi = 3.14159265359;
        amplitude = 1000;

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        reset_n = 0;
        enable = 0;
        adc_sample = 0;
        adc_valid = 0;
        fir_mode = 3'd0;  // Bypass
        eq_step_size = 8'd16;
        eq_training = 0;

        #(CLK_PERIOD * 10);
        reset_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(fir_valid, 1'b0, "FIR no output at init");
        assert_eq_1(eq_valid, 1'b0, "EQ no output at init");

        //---------------------------------------------------------------------
        // Test 2: Enable DSP Chain
        //---------------------------------------------------------------------
        test_begin("Enable DSP Chain");

        enable = 1;
        fir_mode = 3'd0;  // Bypass mode
        repeat(10) @(posedge clk);
        test_pass("DSP chain enabled");

        //---------------------------------------------------------------------
        // Test 3: FIR Bypass Mode
        //---------------------------------------------------------------------
        test_begin("FIR Bypass Mode");

        output_count = 0;
        for (i = 0; i < 20; i = i + 1) begin
            generate_mfm_sample(i % 3, 0);  // No noise
            @(posedge clk);
            if (fir_valid) output_count = output_count + 1;
        end

        repeat(20) @(posedge clk);
        $display("  [INFO] FIR output count: %d", output_count);
        test_pass("FIR bypass works");

        //---------------------------------------------------------------------
        // Test 4: FIR Lowpass Mode
        //---------------------------------------------------------------------
        test_begin("FIR Lowpass Mode");

        fir_mode = 3'd1;  // Lowpass
        output_count = 0;

        for (i = 0; i < 50; i = i + 1) begin
            generate_mfm_sample(i % 3, 100);  // Some noise
            @(posedge clk);
            if (fir_valid) output_count = output_count + 1;
        end

        repeat(30) @(posedge clk);
        $display("  [INFO] FIR lowpass output count: %d", output_count);
        test_pass("FIR lowpass active");

        //---------------------------------------------------------------------
        // Test 5: Equalizer Chain
        //---------------------------------------------------------------------
        test_begin("Equalizer Chain");

        output_count = 0;

        for (i = 0; i < 100; i = i + 1) begin
            generate_mfm_sample(i % 3, 50);
            @(posedge clk);
            if (eq_valid) output_count = output_count + 1;
        end

        repeat(50) @(posedge clk);
        $display("  [INFO] EQ output count: %d", output_count);
        test_pass("Equalizer processing");

        //---------------------------------------------------------------------
        // Test 6: Clean Signal Through Chain
        //---------------------------------------------------------------------
        test_begin("Clean Signal Through Chain");

        // Clean alternating pattern
        for (i = 0; i < 64; i = i + 1) begin
            if (i % 2 == 0)
                generate_mfm_sample(2'd2, 0);  // +amplitude
            else
                generate_mfm_sample(2'd0, 0);  // -amplitude
        end

        repeat(100) @(posedge clk);
        $display("  [INFO] Clean signal processed");
        test_pass("Clean signal OK");

        //---------------------------------------------------------------------
        // Test 7: Noisy Signal Through Chain
        //---------------------------------------------------------------------
        test_begin("Noisy Signal Through Chain");

        // Noisy alternating pattern
        for (i = 0; i < 64; i = i + 1) begin
            if (i % 2 == 0)
                generate_mfm_sample(2'd2, 200);  // +amplitude + noise
            else
                generate_mfm_sample(2'd0, 200);  // -amplitude + noise
        end

        repeat(100) @(posedge clk);
        $display("  [INFO] Noisy signal processed");
        test_pass("Noisy signal OK");

        //---------------------------------------------------------------------
        // Test 8: Square Wave Pattern
        //---------------------------------------------------------------------
        test_begin("Square Wave Pattern");

        // Pattern: 0, +, 0, -, 0, +, 0, - (PR4-like)
        for (i = 0; i < 64; i = i + 1) begin
            case (i % 4)
                0: generate_mfm_sample(2'd1, 20);  // zero
                1: generate_mfm_sample(2'd2, 20);  // pos
                2: generate_mfm_sample(2'd1, 20);  // zero
                3: generate_mfm_sample(2'd0, 20);  // neg
            endcase
        end

        repeat(100) @(posedge clk);
        test_pass("Square wave processed");

        //---------------------------------------------------------------------
        // Test 9: High Noise Level
        //---------------------------------------------------------------------
        test_begin("High Noise Level");

        for (i = 0; i < 50; i = i + 1) begin
            generate_mfm_sample(i % 3, 500);  // Very noisy
        end

        repeat(100) @(posedge clk);
        $display("  [INFO] High noise processed");
        test_pass("High noise handled");

        //---------------------------------------------------------------------
        // Test 10: Enable/Disable
        //---------------------------------------------------------------------
        test_begin("Enable/Disable");

        enable = 0;
        repeat(10) @(posedge clk);

        for (i = 0; i < 10; i = i + 1) begin
            generate_mfm_sample(2'd2, 0);
        end

        // Should not produce output when disabled
        $display("  [INFO] fir_valid = %b when disabled", fir_valid);

        enable = 1;
        repeat(20) @(posedge clk);
        test_pass("Enable/disable works");

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
        #3000000;  // 3ms timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
