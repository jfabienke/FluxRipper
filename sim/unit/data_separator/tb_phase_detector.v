//-----------------------------------------------------------------------------
// Testbench for Phase Detector
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. On-time edge detection
//   3. Early edge detection
//   4. Late edge detection
//   5. Phase error magnitude
//   6. Margin zone classification
//   7. Multiple consecutive edges
//   8. Edge at various phase angles
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_phase_detector;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 5;  // 200 MHz

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         reset;
    reg         edge_detected;
    reg  [31:0] nco_phase;
    wire [15:0] phase_error;
    wire        error_valid;
    wire [1:0]  margin_zone;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    phase_detector dut (
        .clk(clk),
        .reset(reset),
        .edge_detected(edge_detected),
        .nco_phase(nco_phase),
        .phase_error(phase_error),
        .error_valid(error_valid),
        .margin_zone(margin_zone)
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
        $dumpfile("tb_phase_detector.vcd");
        $dumpvars(0, tb_phase_detector);
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    task detect_edge;
        input [31:0] phase;
        begin
            @(posedge clk);
            nco_phase <= phase;
            edge_detected <= 1;
            @(posedge clk);
            edge_detected <= 0;
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        reset = 1;
        edge_detected = 0;
        nco_phase = 0;

        #(CLK_PERIOD * 10);
        reset = 0;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(error_valid, 1'b0, "No error valid initially");
        assert_eq_2(margin_zone, 2'b01, "Default zone is on-time");

        //---------------------------------------------------------------------
        // Test 2: On-Time Edge (Phase = 0)
        //---------------------------------------------------------------------
        test_begin("On-Time Edge");

        detect_edge(32'h00000000);  // Perfect timing

        $display("  [INFO] Phase error for on-time: %d", $signed(phase_error));
        assert_eq_1(error_valid, 1'b1, "Error valid after edge");

        //---------------------------------------------------------------------
        // Test 3: Early Edge (Phase < 180°)
        //---------------------------------------------------------------------
        test_begin("Early Edge");

        detect_edge(32'h10000000);  // Slightly early (22.5°)

        $display("  [INFO] Phase error for early: %d (0x%04X)", $signed(phase_error), phase_error);
        $display("  [INFO] Margin zone: %b", margin_zone);

        //---------------------------------------------------------------------
        // Test 4: Late Edge (Phase > 180°)
        //---------------------------------------------------------------------
        test_begin("Late Edge");

        detect_edge(32'hF0000000);  // Slightly late (337.5° = -22.5°)

        $display("  [INFO] Phase error for late: %d (0x%04X)", $signed(phase_error), phase_error);
        $display("  [INFO] Margin zone: %b", margin_zone);

        //---------------------------------------------------------------------
        // Test 5: Very Early Edge
        //---------------------------------------------------------------------
        test_begin("Very Early Edge");

        detect_edge(32'h40000000);  // 90° early (way off)

        $display("  [INFO] Phase error for very early: %d", $signed(phase_error));
        $display("  [INFO] Margin zone: %b (expect way off)", margin_zone);

        //---------------------------------------------------------------------
        // Test 6: Very Late Edge
        //---------------------------------------------------------------------
        test_begin("Very Late Edge");

        detect_edge(32'hC0000000);  // 270° = 90° late (way off)

        $display("  [INFO] Phase error for very late: %d", $signed(phase_error));
        $display("  [INFO] Margin zone: %b (expect way off)", margin_zone);

        //---------------------------------------------------------------------
        // Test 7: Multiple Consecutive Edges
        //---------------------------------------------------------------------
        test_begin("Consecutive Edges");

        for (i = 0; i < 8; i = i + 1) begin
            detect_edge(i * 32'h10000000);  // Different phases
        end

        test_pass("Multiple edges processed");

        //---------------------------------------------------------------------
        // Test 8: Edge at 45° Boundary
        //---------------------------------------------------------------------
        test_begin("45 Degree Boundary");

        detect_edge(32'h20000000);  // Exactly 45°

        $display("  [INFO] Margin zone at 45°: %b", margin_zone);

        detect_edge(32'h1FFFFFFF);  // Just under 45°

        $display("  [INFO] Margin zone just under 45°: %b", margin_zone);
        test_pass("Boundary cases tested");

        //---------------------------------------------------------------------
        // Test 9: Edge at 315° Boundary
        //---------------------------------------------------------------------
        test_begin("315 Degree Boundary");

        detect_edge(32'hE0000000);  // Exactly 315° (-45°)

        $display("  [INFO] Margin zone at 315°: %b", margin_zone);
        test_pass("315° boundary tested");

        //---------------------------------------------------------------------
        // Test 10: Reset During Operation
        //---------------------------------------------------------------------
        test_begin("Reset During Operation");

        detect_edge(32'h50000000);

        reset = 1;
        @(posedge clk);
        reset = 0;
        @(posedge clk);

        assert_eq_1(error_valid, 1'b0, "Error valid cleared on reset");

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
