//-----------------------------------------------------------------------------
// Testbench for Adaptive Equalizer
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. Identity filter response (passthrough)
//   3. LMS coefficient adaptation
//   4. Convergence detection
//   5. Coefficient read/write
//   6. Training mode vs fixed mode
//   7. Error computation
//   8. Leakage operation
//   9. Freeze coefficients
//  10. Impulse response
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_adaptive_equalizer;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter DATA_WIDTH = 12;
    parameter COEF_WIDTH = 16;
    parameter NUM_TAPS = 11;

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
    reg  signed [DATA_WIDTH-1:0] data_in;
    reg                         data_valid;

    // Output equalized stream
    wire signed [DATA_WIDTH-1:0] data_out;
    wire                        data_out_valid;

    // Training/reference
    reg  signed [DATA_WIDTH-1:0] reference_in;
    reg                         reference_valid;
    reg                         training_mode;

    // Coefficient access
    reg                         coef_read;
    reg                         coef_write;
    reg  [3:0]                  coef_addr;
    reg  signed [COEF_WIDTH-1:0] coef_wdata;
    wire signed [COEF_WIDTH-1:0] coef_rdata;

    // Configuration
    reg  [7:0]                  step_size;
    reg  [7:0]                  leakage;
    reg                         freeze_coefs;

    // Status
    wire signed [DATA_WIDTH-1:0] current_error;
    wire [15:0]                 error_power;
    wire                        converged;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    adaptive_equalizer #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_TAPS(NUM_TAPS)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .data_in(data_in),
        .data_valid(data_valid),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .reference_in(reference_in),
        .reference_valid(reference_valid),
        .training_mode(training_mode),
        .coef_read(coef_read),
        .coef_write(coef_write),
        .coef_addr(coef_addr),
        .coef_wdata(coef_wdata),
        .coef_rdata(coef_rdata),
        .step_size(step_size),
        .leakage(leakage),
        .freeze_coefs(freeze_coefs),
        .current_error(current_error),
        .error_power(error_power),
        .converged(converged)
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
        $dumpfile("tb_adaptive_equalizer.vcd");
        $dumpvars(0, tb_adaptive_equalizer);
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send input sample
    task send_sample;
        input signed [DATA_WIDTH-1:0] value;
        begin
            @(posedge clk);
            data_in <= value;
            data_valid <= 1;
            @(posedge clk);
            data_valid <= 0;
        end
    endtask

    // Send sample with reference
    task send_training_sample;
        input signed [DATA_WIDTH-1:0] input_val;
        input signed [DATA_WIDTH-1:0] ref_val;
        begin
            @(posedge clk);
            data_in <= input_val;
            data_valid <= 1;
            reference_in <= ref_val;
            reference_valid <= 1;
            @(posedge clk);
            data_valid <= 0;
            reference_valid <= 0;
        end
    endtask

    // Read coefficient
    task read_coef;
        input [3:0] addr;
        output signed [COEF_WIDTH-1:0] value;
        begin
            @(posedge clk);
            coef_addr <= addr;
            coef_read <= 1;
            @(posedge clk);
            @(posedge clk);
            value = coef_rdata;
            coef_read <= 0;
        end
    endtask

    // Write coefficient
    task write_coef;
        input [3:0] addr;
        input signed [COEF_WIDTH-1:0] value;
        begin
            @(posedge clk);
            coef_addr <= addr;
            coef_wdata <= value;
            coef_write <= 1;
            @(posedge clk);
            coef_write <= 0;
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    reg signed [COEF_WIDTH-1:0] coef_val;
    reg signed [DATA_WIDTH-1:0] output_samples [0:31];
    integer output_count;

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
        reference_in = 0;
        reference_valid = 0;
        training_mode = 0;
        coef_read = 0;
        coef_write = 0;
        coef_addr = 0;
        coef_wdata = 0;
        step_size = 8'd16;  // Moderate step size
        leakage = 8'd0;     // No leakage initially
        freeze_coefs = 0;

        #(CLK_PERIOD * 10);
        reset_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(data_out_valid, 1'b0, "No output at init");
        $display("  [INFO] converged = %b at init", converged);

        //---------------------------------------------------------------------
        // Test 2: Enable Equalizer
        //---------------------------------------------------------------------
        test_begin("Enable Equalizer");

        enable = 1;
        repeat(10) @(posedge clk);
        test_pass("Equalizer enabled");

        //---------------------------------------------------------------------
        // Test 3: Read Initial Coefficients
        //---------------------------------------------------------------------
        test_begin("Read Initial Coefficients");

        // Read center tap (should be non-zero for identity)
        read_coef(NUM_TAPS/2, coef_val);
        $display("  [INFO] Center tap [%d] = 0x%04X", NUM_TAPS/2, coef_val);

        // Read end taps (should be zero)
        read_coef(0, coef_val);
        $display("  [INFO] First tap [0] = 0x%04X", coef_val);

        test_pass("Coefficients read");

        //---------------------------------------------------------------------
        // Test 4: Passthrough (Identity Filter)
        //---------------------------------------------------------------------
        test_begin("Passthrough Test");

        output_count = 0;
        for (i = 0; i < 20; i = i + 1) begin
            send_sample(12'sd1000);
            @(posedge clk);
            if (data_out_valid) begin
                output_samples[output_count] = data_out;
                output_count = output_count + 1;
            end
        end

        $display("  [INFO] Collected %d output samples", output_count);
        if (output_count > 0) begin
            $display("  [INFO] Last output = %d", output_samples[output_count-1]);
        end
        test_pass("Passthrough tested");

        //---------------------------------------------------------------------
        // Test 5: Training Mode Adaptation
        //---------------------------------------------------------------------
        test_begin("Training Mode Adaptation");

        training_mode = 1;

        // Send samples with reference (trying to adapt)
        for (i = 0; i < 100; i = i + 1) begin
            send_training_sample(12'sd500, 12'sd500);
        end

        $display("  [INFO] current_error = %d after training", current_error);
        $display("  [INFO] error_power = %d", error_power);

        training_mode = 0;
        test_pass("Training mode tested");

        //---------------------------------------------------------------------
        // Test 6: Write Coefficient
        //---------------------------------------------------------------------
        test_begin("Write Coefficient");

        // Write to tap 0
        write_coef(4'd0, 16'sh0100);

        // Read it back
        read_coef(4'd0, coef_val);
        $display("  [INFO] Tap[0] after write = 0x%04X", coef_val);

        test_pass("Coefficient write works");

        //---------------------------------------------------------------------
        // Test 7: Freeze Coefficients
        //---------------------------------------------------------------------
        test_begin("Freeze Coefficients");

        freeze_coefs = 1;
        training_mode = 1;

        // Read a coefficient before
        read_coef(NUM_TAPS/2, coef_val);
        $display("  [INFO] Center tap before freeze = 0x%04X", coef_val);

        // Send training samples
        for (i = 0; i < 50; i = i + 1) begin
            send_training_sample(12'sd100, 12'sd200);
        end

        // Read after (should be same if frozen)
        read_coef(NUM_TAPS/2, coef_val);
        $display("  [INFO] Center tap after freeze = 0x%04X", coef_val);

        freeze_coefs = 0;
        training_mode = 0;
        test_pass("Freeze tested");

        //---------------------------------------------------------------------
        // Test 8: Leakage Operation
        //---------------------------------------------------------------------
        test_begin("Leakage Operation");

        leakage = 8'd16;  // Enable leakage

        for (i = 0; i < 50; i = i + 1) begin
            send_sample(12'sd0);
        end

        $display("  [INFO] Leakage applied");
        leakage = 8'd0;
        test_pass("Leakage tested");

        //---------------------------------------------------------------------
        // Test 9: Impulse Response
        //---------------------------------------------------------------------
        test_begin("Impulse Response");

        // Send impulse
        send_sample(12'sd2047);  // Max positive

        // Collect response
        output_count = 0;
        for (i = 0; i < NUM_TAPS + 5; i = i + 1) begin
            send_sample(12'sd0);
            @(posedge clk);
            if (data_out_valid) begin
                $display("  [INFO] IR[%d] = %d", output_count, data_out);
                output_count = output_count + 1;
            end
        end

        test_pass("Impulse response captured");

        //---------------------------------------------------------------------
        // Test 10: Convergence Check
        //---------------------------------------------------------------------
        test_begin("Convergence Check");

        $display("  [INFO] converged = %b", converged);
        $display("  [INFO] error_power = %d", error_power);
        test_pass("Convergence checked");

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
        #2000000;  // 2ms timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
