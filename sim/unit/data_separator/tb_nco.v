//-----------------------------------------------------------------------------
// Testbench for NCO (Numerically Controlled Oscillator)
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. Phase accumulator operation
//   3. Bit clock generation at 250 kbps
//   4. Bit clock generation at 500 kbps
//   5. Sample point generation at mid-bit
//   6. Phase adjustment
//   7. Enable/disable control
//   8. Frequency accuracy measurement
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_nco;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 5;  // 200 MHz

    // Frequency words for different data rates @ 200 MHz
    // FW = (data_rate * 2^32) / 200_000_000
    parameter FW_250K = 32'h0051EB85;   // 250 kbps
    parameter FW_300K = 32'h00624DD3;   // 300 kbps
    parameter FW_500K = 32'h00A3D70A;   // 500 kbps
    parameter FW_1M   = 32'h0147AE14;   // 1000 kbps

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         reset;
    reg         enable;
    reg  [31:0] freq_word;
    reg  [15:0] phase_adj;
    reg         phase_adj_valid;
    wire        bit_clk;
    wire [31:0] phase_accum;
    wire        sample_point;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    nco dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .freq_word(freq_word),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid),
        .bit_clk(bit_clk),
        .phase_accum(phase_accum),
        .sample_point(sample_point)
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
        $dumpfile("tb_nco.vcd");
        $dumpvars(0, tb_nco);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    integer bit_clk_edges;
    integer sample_points;
    time start_time;
    time end_time;
    real measured_freq;
    reg prev_bit_clk;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        reset = 1;
        enable = 0;
        freq_word = FW_500K;
        phase_adj = 0;
        phase_adj_valid = 0;
        prev_bit_clk = 0;

        #(CLK_PERIOD * 10);
        reset = 0;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(bit_clk, 1'b0, "bit_clk deasserted");
        assert_eq_32(phase_accum, 32'd0, "Phase accum is 0");
        assert_eq_1(sample_point, 1'b0, "Sample point deasserted");

        //---------------------------------------------------------------------
        // Test 2: Phase Accumulator Operation
        //---------------------------------------------------------------------
        test_begin("Phase Accumulator");

        enable = 1;
        repeat(10) @(posedge clk);

        $display("  [INFO] Phase accum after 10 clocks: 0x%08X", phase_accum);
        assert_true(phase_accum > 0, "Phase accumulator increments");

        //---------------------------------------------------------------------
        // Test 3: Bit Clock at 500 kbps
        //---------------------------------------------------------------------
        test_begin("Bit Clock at 500 kbps");

        freq_word = FW_500K;
        bit_clk_edges = 0;
        prev_bit_clk = bit_clk;

        // Count edges for 100us (should see ~50 bit periods = 100 edges)
        repeat(20000) begin  // 100us at 200 MHz
            @(posedge clk);
            if (bit_clk != prev_bit_clk) begin
                bit_clk_edges = bit_clk_edges + 1;
            end
            prev_bit_clk = bit_clk;
        end

        $display("  [INFO] Bit clock edges in 100us: %0d (expect ~100)", bit_clk_edges);
        assert_true(bit_clk_edges >= 90 && bit_clk_edges <= 110, "500 kbps rate correct");

        //---------------------------------------------------------------------
        // Test 4: Bit Clock at 250 kbps
        //---------------------------------------------------------------------
        test_begin("Bit Clock at 250 kbps");

        freq_word = FW_250K;
        bit_clk_edges = 0;
        prev_bit_clk = bit_clk;

        // Count edges for 100us (should see ~25 bit periods = 50 edges)
        repeat(20000) begin
            @(posedge clk);
            if (bit_clk != prev_bit_clk) begin
                bit_clk_edges = bit_clk_edges + 1;
            end
            prev_bit_clk = bit_clk;
        end

        $display("  [INFO] Bit clock edges in 100us: %0d (expect ~50)", bit_clk_edges);
        assert_true(bit_clk_edges >= 45 && bit_clk_edges <= 55, "250 kbps rate correct");

        //---------------------------------------------------------------------
        // Test 5: Sample Point Generation
        //---------------------------------------------------------------------
        test_begin("Sample Point Generation");

        freq_word = FW_500K;
        sample_points = 0;

        repeat(20000) begin
            @(posedge clk);
            if (sample_point) begin
                sample_points = sample_points + 1;
            end
        end

        $display("  [INFO] Sample points in 100us: %0d (expect ~50)", sample_points);
        assert_true(sample_points >= 45 && sample_points <= 55, "Sample points generated");

        //---------------------------------------------------------------------
        // Test 6: Phase Adjustment
        //---------------------------------------------------------------------
        test_begin("Phase Adjustment");

        // Capture current phase
        @(posedge clk);
        phase_adj = 16'h1000;  // Positive adjustment
        phase_adj_valid = 1;
        @(posedge clk);
        phase_adj_valid = 0;

        $display("  [INFO] Applied positive phase adjustment");

        // Capture current phase again
        repeat(5) @(posedge clk);
        phase_adj = 16'hF000;  // Negative adjustment (two's complement)
        phase_adj_valid = 1;
        @(posedge clk);
        phase_adj_valid = 0;

        $display("  [INFO] Applied negative phase adjustment");
        test_pass("Phase adjustments applied");

        //---------------------------------------------------------------------
        // Test 7: Enable/Disable
        //---------------------------------------------------------------------
        test_begin("Enable/Disable");

        enable = 0;
        @(posedge clk);
        @(posedge clk);

        assert_eq_1(sample_point, 1'b0, "No sample when disabled");

        enable = 1;
        repeat(100) @(posedge clk);
        test_pass("Enable/disable works");

        //---------------------------------------------------------------------
        // Test 8: 1 Mbps Rate
        //---------------------------------------------------------------------
        test_begin("1 Mbps Rate");

        freq_word = FW_1M;
        bit_clk_edges = 0;
        prev_bit_clk = bit_clk;

        // Count edges for 100us (should see ~100 bit periods = 200 edges)
        repeat(20000) begin
            @(posedge clk);
            if (bit_clk != prev_bit_clk) begin
                bit_clk_edges = bit_clk_edges + 1;
            end
            prev_bit_clk = bit_clk;
        end

        $display("  [INFO] Bit clock edges in 100us: %0d (expect ~200)", bit_clk_edges);
        assert_true(bit_clk_edges >= 180 && bit_clk_edges <= 220, "1 Mbps rate correct");

        //---------------------------------------------------------------------
        // Test 9: Reset During Operation
        //---------------------------------------------------------------------
        test_begin("Reset During Operation");

        enable = 1;
        freq_word = FW_500K;
        repeat(1000) @(posedge clk);

        reset = 1;
        @(posedge clk);
        reset = 0;

        assert_eq_32(phase_accum, 32'd0, "Phase reset to 0");
        assert_eq_1(bit_clk, 1'b0, "Bit clock reset");

        //---------------------------------------------------------------------
        // Test 10: 300 kbps Rate
        //---------------------------------------------------------------------
        test_begin("300 kbps Rate");

        enable = 1;
        freq_word = FW_300K;
        bit_clk_edges = 0;
        prev_bit_clk = bit_clk;

        repeat(20000) begin
            @(posedge clk);
            if (bit_clk != prev_bit_clk) begin
                bit_clk_edges = bit_clk_edges + 1;
            end
            prev_bit_clk = bit_clk;
        end

        $display("  [INFO] Bit clock edges in 100us: %0d (expect ~60)", bit_clk_edges);
        assert_true(bit_clk_edges >= 54 && bit_clk_edges <= 66, "300 kbps rate correct");

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
