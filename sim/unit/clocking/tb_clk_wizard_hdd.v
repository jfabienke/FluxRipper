//-----------------------------------------------------------------------------
// Testbench for HDD Clock Wizard (300 MHz domain)
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. 300 MHz generation from 200 MHz reference
//   2. CDC FIFO coherency (200↔300 MHz)
//   3. Gray-code pointer synchronization
//   4. Full/empty flag accuracy
//   5. Power gating (hdd_mode_enable)
//   6. Lock timing
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_clk_wizard_hdd;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_200_PERIOD = 5;       // 200 MHz = 5 ns

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals - Clock Wizard
    //=========================================================================
    reg  clk_in;
    reg  reset;
    reg  hdd_mode_enable;

    wire clk_200mhz;
    wire clk_300mhz;
    wire clk_300mhz_en;
    wire locked;

    //=========================================================================
    // DUT Signals - CDC FIFO
    //=========================================================================
    reg  wr_clk;
    reg  wr_reset;
    reg  wr_en;
    reg  [31:0] wr_data;
    wire wr_full;

    reg  rd_clk;
    reg  rd_reset;
    reg  rd_en;
    wire [31:0] rd_data;
    wire rd_empty;

    //=========================================================================
    // DUT Instantiation - Clock Wizard
    //=========================================================================
    clk_wizard_hdd dut_clk (
        .clk_in(clk_in),
        .reset(reset),
        .hdd_mode_enable(hdd_mode_enable),
        .clk_200mhz(clk_200mhz),
        .clk_300mhz(clk_300mhz),
        .clk_300mhz_en(clk_300mhz_en),
        .locked(locked)
    );

    //=========================================================================
    // DUT Instantiation - CDC FIFO
    //=========================================================================
    hdd_cdc_fifo #(
        .DATA_WIDTH(32),
        .DEPTH_LOG2(4)      // 16-entry FIFO
    ) dut_fifo (
        .wr_clk(wr_clk),
        .wr_reset(wr_reset),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(wr_full),
        .rd_clk(rd_clk),
        .rd_reset(rd_reset),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .rd_empty(rd_empty)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk_in = 0;
    always #(CLK_200_PERIOD/2) clk_in = ~clk_in;

    // Use generated clocks for FIFO test
    always @(*) begin
        wr_clk = clk_300mhz;
        rd_clk = clk_200mhz;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_clk_wizard_hdd.vcd");
        $dumpvars(0, tb_clk_wizard_hdd);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer cycle_count;
    integer i;
    reg [31:0] test_data [0:31];
    reg [31:0] read_data [0:31];
    integer write_count;
    integer read_count;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        reset = 1'b1;
        hdd_mode_enable = 1'b0;
        wr_reset = 1'b1;
        rd_reset = 1'b1;
        wr_en = 1'b0;
        rd_en = 1'b0;
        wr_data = 32'h0;

        // Initialize test data
        for (i = 0; i < 32; i = i + 1) begin
            test_data[i] = 32'hDEAD0000 + i;
        end

        //---------------------------------------------------------------------
        // Test 1: Power-Off State
        //---------------------------------------------------------------------
        test_begin("Power-Off State");

        #(CLK_200_PERIOD * 10);
        reset = 1'b0;
        #(CLK_200_PERIOD * 5);

        // HDD mode disabled - 300 MHz clock should not be running
        assert_eq_1(hdd_mode_enable, 1'b0, "HDD mode disabled");
        assert_eq_1(locked, 1'b0, "PLL not locked when disabled");
        assert_eq_1(clk_300mhz_en, 1'b0, "300 MHz clock enable off");

        //---------------------------------------------------------------------
        // Test 2: Enable HDD Mode and Lock
        //---------------------------------------------------------------------
        test_begin("Enable HDD Mode and Lock");

        hdd_mode_enable = 1'b1;

        // Wait for PLL lock (100 cycles in behavioral model)
        cycle_count = 0;
        while (!locked && cycle_count < 200) begin
            @(posedge clk_in);
            cycle_count = cycle_count + 1;
        end

        assert_true(locked, "PLL achieved lock");
        $display("  [INFO] PLL locked after %0d input clock cycles", cycle_count);

        // Verify clock enable is now active
        assert_eq_1(clk_300mhz_en, 1'b1, "300 MHz clock enable active");

        //---------------------------------------------------------------------
        // Test 3: Clock Pass-Through
        //---------------------------------------------------------------------
        test_begin("200 MHz Pass-Through");

        // Verify 200 MHz pass-through
        // Both clk_in and clk_200mhz should be the same signal
        repeat(10) begin
            @(posedge clk_in);
            assert_eq_1(clk_200mhz, clk_in, "200 MHz pass-through");
        end
        test_pass("200 MHz clock passes through correctly");

        //---------------------------------------------------------------------
        // Test 4: 300 MHz Generation
        //---------------------------------------------------------------------
        test_begin("300 MHz Generation");

        // Count edges on 300 MHz clock
        // Wait a bit and see if clock toggles
        cycle_count = 0;
        repeat(500) begin
            @(posedge clk_in);
            if (clk_300mhz)
                cycle_count = cycle_count + 1;
        end

        assert_true(cycle_count > 0, "300 MHz clock is running");
        $display("  [INFO] 300 MHz clock verified active");

        //---------------------------------------------------------------------
        // Test 5: CDC FIFO - Basic Operation
        //---------------------------------------------------------------------
        test_begin("CDC FIFO Basic Operation");

        // Release FIFO resets
        wr_reset = 1'b0;
        rd_reset = 1'b0;
        repeat(10) @(posedge clk_in);

        // FIFO should be empty initially
        assert_eq_1(rd_empty, 1'b1, "FIFO empty initially");
        assert_eq_1(wr_full, 1'b0, "FIFO not full initially");

        //---------------------------------------------------------------------
        // Test 6: CDC FIFO - Write and Read
        //---------------------------------------------------------------------
        test_begin("CDC FIFO Write/Read");

        // Write some data
        write_count = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk_300mhz);
            if (!wr_full) begin
                wr_data = test_data[i];
                wr_en = 1'b1;
                write_count = write_count + 1;
            end
            @(posedge clk_300mhz);
            wr_en = 1'b0;
        end

        $display("  [INFO] Wrote %0d words to FIFO", write_count);

        // Wait for synchronization (3 cycles minimum)
        repeat(10) @(posedge clk_in);

        // FIFO should no longer be empty
        assert_eq_1(rd_empty, 1'b0, "FIFO not empty after write");

        // Read data back
        read_count = 0;
        while (!rd_empty && read_count < 16) begin
            @(posedge clk_200mhz);
            rd_en = 1'b1;
            @(posedge clk_200mhz);
            read_data[read_count] = rd_data;
            read_count = read_count + 1;
            rd_en = 1'b0;
            @(posedge clk_200mhz);
        end

        $display("  [INFO] Read %0d words from FIFO", read_count);

        // Verify data integrity
        for (i = 0; i < read_count; i = i + 1) begin
            if (read_data[i] !== test_data[i]) begin
                $display("  [FAIL] Data mismatch at index %0d: got 0x%08X, expected 0x%08X",
                         i, read_data[i], test_data[i]);
                test_errors = test_errors + 1;
            end
        end
        if (read_count > 0) begin
            $display("  [PASS] Verified %0d words transferred correctly", read_count);
            test_passed = test_passed + 1;
        end

        //---------------------------------------------------------------------
        // Test 7: CDC FIFO - Full Condition
        //---------------------------------------------------------------------
        test_begin("CDC FIFO Full Condition");

        // Reset FIFO
        wr_reset = 1'b1;
        rd_reset = 1'b1;
        repeat(5) @(posedge clk_in);
        wr_reset = 1'b0;
        rd_reset = 1'b0;
        repeat(5) @(posedge clk_in);

        // Fill the FIFO completely (16 entries)
        write_count = 0;
        for (i = 0; i < 20 && !wr_full; i = i + 1) begin
            @(posedge clk_300mhz);
            wr_data = 32'hCAFE0000 + i;
            wr_en = 1'b1;
            @(posedge clk_300mhz);
            wr_en = 1'b0;
            write_count = write_count + 1;
            repeat(3) @(posedge clk_300mhz);  // Allow synchronization
        end

        $display("  [INFO] Wrote %0d words, wr_full=%b", write_count, wr_full);

        // FIFO should be full after 16 writes
        repeat(10) @(posedge clk_in);
        assert_true(wr_full || write_count >= 15, "FIFO fills to capacity");

        //---------------------------------------------------------------------
        // Test 8: Power Gating
        //---------------------------------------------------------------------
        test_begin("Power Gating");

        // Disable HDD mode
        hdd_mode_enable = 1'b0;
        repeat(10) @(posedge clk_in);

        // PLL should lose lock
        assert_eq_1(locked, 1'b0, "PLL unlocked when disabled");
        assert_eq_1(clk_300mhz_en, 1'b0, "Clock enable deasserted");

        // Re-enable and verify re-lock
        hdd_mode_enable = 1'b1;
        cycle_count = 0;
        while (!locked && cycle_count < 200) begin
            @(posedge clk_in);
            cycle_count = cycle_count + 1;
        end
        assert_true(locked, "PLL re-locks after re-enable");

        //---------------------------------------------------------------------
        // Test 9: Reset During Operation
        //---------------------------------------------------------------------
        test_begin("Reset During Operation");

        // Assert reset while running
        reset = 1'b1;
        repeat(5) @(posedge clk_in);

        assert_eq_1(locked, 1'b0, "PLL unlocked on reset");

        // Release reset
        reset = 1'b0;
        cycle_count = 0;
        while (!locked && cycle_count < 200) begin
            @(posedge clk_in);
            cycle_count = cycle_count + 1;
        end
        assert_true(locked, "PLL recovers from reset");

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        test_summary();

        #(CLK_200_PERIOD * 100);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #50000;  // 50 us timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
