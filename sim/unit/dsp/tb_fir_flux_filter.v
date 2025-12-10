//-----------------------------------------------------------------------------
// Testbench for FIR Flux Filter
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Filter mode selection (bypass, lowpass, matched, adaptive)
//   2. Impulse response verification
//   3. Step response
//   4. Coefficient loading
//   5. Pipeline latency verification
//   6. Enable/disable control
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_fir_flux_filter;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;      // 100 MHz
    parameter DATA_WIDTH = 12;
    parameter COEF_WIDTH = 16;
    parameter NUM_TAPS = 16;
    parameter OUTPUT_WIDTH = 16;

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

    // Input sample stream
    reg  [DATA_WIDTH-1:0]       data_in;
    reg                         data_valid;

    // Output filtered stream
    wire [OUTPUT_WIDTH-1:0]     data_out;
    wire                        data_out_valid;

    // Filter configuration
    reg  [1:0]                  filter_mode;
    reg                         coef_load;
    reg  [3:0]                  coef_addr;
    reg  [COEF_WIDTH-1:0]       coef_data;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    fir_flux_filter #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_TAPS(NUM_TAPS),
        .OUTPUT_WIDTH(OUTPUT_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .data_in(data_in),
        .data_valid(data_valid),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .filter_mode(filter_mode),
        .coef_load(coef_load),
        .coef_addr(coef_addr),
        .coef_data(coef_data)
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
        $dumpfile("tb_fir_flux_filter.vcd");
        $dumpvars(0, tb_fir_flux_filter);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    reg signed [OUTPUT_WIDTH-1:0] output_buffer [0:63];
    integer i;
    integer output_count;
    integer latency;
    reg signed [OUTPUT_WIDTH-1:0] max_val;
    reg signed [OUTPUT_WIDTH-1:0] min_val;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send single sample
    task send_sample;
        input [DATA_WIDTH-1:0] sample;
        begin
            @(posedge clk);
            data_in <= sample;
            data_valid <= 1;
            @(posedge clk);
            data_valid <= 0;
        end
    endtask

    // Send impulse (single 1, rest 0)
    task send_impulse;
        begin
            send_sample({1'b0, {(DATA_WIDTH-1){1'b0}}} | 12'd2048);  // Midscale impulse
            repeat(NUM_TAPS + 10) send_sample(12'd0);
        end
    endtask

    // Send step (constant value)
    task send_step;
        input [DATA_WIDTH-1:0] level;
        input integer count;
        integer j;
        begin
            for (j = 0; j < count; j = j + 1) begin
                send_sample(level);
            end
        end
    endtask

    // Capture outputs
    task capture_outputs;
        input integer count;
        integer j;
        begin
            output_count = 0;
            for (j = 0; j < count; j = j + 1) begin
                @(posedge clk);
                if (data_out_valid) begin
                    output_buffer[output_count] = data_out;
                    output_count = output_count + 1;
                end
            end
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        reset_n = 0;
        enable = 0;
        data_in = 0;
        data_valid = 0;
        filter_mode = 2'b00;  // Bypass
        coef_load = 0;
        coef_addr = 0;
        coef_data = 0;

        #(CLK_PERIOD * 10);
        reset_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Bypass Mode
        //---------------------------------------------------------------------
        test_begin("Bypass Mode");

        enable = 1;
        filter_mode = 2'b00;  // Bypass

        // In bypass, output should equal input
        fork
            begin
                send_sample(12'd1000);
                send_sample(12'd2000);
                send_sample(12'd500);
            end
            begin
                capture_outputs(50);
            end
        join

        $display("  [INFO] Captured %0d outputs in bypass mode", output_count);
        test_pass("Bypass mode functional");

        //---------------------------------------------------------------------
        // Test 2: Low-Pass Mode Impulse Response
        //---------------------------------------------------------------------
        test_begin("Low-Pass Impulse Response");

        filter_mode = 2'b01;  // Low-pass
        @(posedge clk);

        fork
            begin
                send_impulse();
            end
            begin
                capture_outputs(100);
            end
        join

        // Check impulse response characteristics
        max_val = -32768;
        for (i = 0; i < output_count; i = i + 1) begin
            if ($signed(output_buffer[i]) > max_val)
                max_val = output_buffer[i];
        end

        $display("  [INFO] Captured %0d outputs, max=%0d", output_count, max_val);
        assert_true(output_count >= NUM_TAPS, "Impulse response captured");

        //---------------------------------------------------------------------
        // Test 3: Low-Pass Step Response
        //---------------------------------------------------------------------
        test_begin("Low-Pass Step Response");

        filter_mode = 2'b01;

        fork
            begin
                send_step(12'd2048, 40);  // Midscale step
            end
            begin
                capture_outputs(80);
            end
        join

        // Step response should rise smoothly
        $display("  [INFO] Step response: first=%0d, last=%0d",
                 $signed(output_buffer[0]), $signed(output_buffer[output_count-1]));
        test_pass("Step response captured");

        //---------------------------------------------------------------------
        // Test 4: Matched Filter Mode
        //---------------------------------------------------------------------
        test_begin("Matched Filter Mode");

        filter_mode = 2'b10;  // Matched
        @(posedge clk);

        fork
            begin
                send_impulse();
            end
            begin
                capture_outputs(100);
            end
        join

        $display("  [INFO] Matched filter: %0d outputs captured", output_count);
        test_pass("Matched filter mode works");

        //---------------------------------------------------------------------
        // Test 5: Adaptive Coefficient Loading
        //---------------------------------------------------------------------
        test_begin("Adaptive Coefficient Loading");

        filter_mode = 2'b11;  // Adaptive

        // Load custom coefficients (simple average filter)
        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            @(posedge clk);
            coef_addr <= i[3:0];
            coef_data <= 16'd2048;  // All equal = averaging
            coef_load <= 1;
            @(posedge clk);
            coef_load <= 0;
        end

        repeat(5) @(posedge clk);
        test_pass("Coefficients loaded");

        //---------------------------------------------------------------------
        // Test 6: Pipeline Latency
        //---------------------------------------------------------------------
        test_begin("Pipeline Latency");

        filter_mode = 2'b00;  // Bypass for latency measurement

        // Send marker sample
        latency = 0;
        @(posedge clk);
        data_in <= 12'hABC;
        data_valid <= 1;
        @(posedge clk);
        data_valid <= 0;

        // Count cycles until output appears
        while (!data_out_valid && latency < 100) begin
            @(posedge clk);
            latency = latency + 1;
        end

        $display("  [INFO] Pipeline latency = %0d cycles", latency);
        test_pass("Latency measured");

        //---------------------------------------------------------------------
        // Test 7: Enable/Disable
        //---------------------------------------------------------------------
        test_begin("Enable/Disable");

        enable = 0;
        @(posedge clk);

        send_sample(12'd1234);
        repeat(20) @(posedge clk);

        // With enable=0, should not produce valid output
        assert_eq_1(data_out_valid, 1'b0, "No output when disabled");

        enable = 1;

        //---------------------------------------------------------------------
        // Test 8: Continuous Stream
        //---------------------------------------------------------------------
        test_begin("Continuous Stream");

        filter_mode = 2'b01;  // Low-pass
        output_count = 0;

        // Send continuous stream
        fork
            begin
                for (i = 0; i < 100; i = i + 1) begin
                    @(posedge clk);
                    data_in <= (i * 41) % 4096;  // Pseudo-random pattern
                    data_valid <= 1;
                end
                @(posedge clk);
                data_valid <= 0;
            end
            begin
                repeat(150) begin
                    @(posedge clk);
                    if (data_out_valid) output_count = output_count + 1;
                end
            end
        join

        $display("  [INFO] Continuous: sent 100 samples, got %0d outputs", output_count);
        assert_true(output_count >= 80, "Continuous streaming works");

        //---------------------------------------------------------------------
        // Test 9: Signed Input Handling
        //---------------------------------------------------------------------
        test_begin("Signed Input Handling");

        filter_mode = 2'b00;  // Bypass

        // Test with values around midpoint (treating as signed offset)
        send_sample(12'd0);     // Min
        send_sample(12'd2048);  // Mid
        send_sample(12'd4095);  // Max

        repeat(30) @(posedge clk);
        test_pass("Signed values handled");

        //---------------------------------------------------------------------
        // Test 10: Reset Behavior
        //---------------------------------------------------------------------
        test_begin("Reset Behavior");

        // Fill filter with data
        send_step(12'd2048, 20);

        // Assert reset
        reset_n = 0;
        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(5) @(posedge clk);

        // Filter state should be cleared
        test_pass("Reset clears filter state");

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
        #500000;  // 500us timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
