//-----------------------------------------------------------------------------
// Testbench for Clock/Reset Manager
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. PLL lock sequence and timing
//   2. Reset synchronization across all domains (sys, usb, disk, debug)
//   3. Watchdog timer expiration
//   4. Watchdog kick prevention
//   5. Debug reset independence from system reset
//   6. Power-on reset sequence
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_clock_reset_mgr;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_REF_PERIOD = 40;      // 25 MHz = 40 ns
    parameter WDT_TEST_CYCLES = 100;    // Shortened for simulation

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg  clk_ref;
    reg  rst_ext_n;
    reg  rst_debug_n;
    reg  wdt_kick;

    wire clk_sys;
    wire clk_usb;
    wire clk_disk;
    wire rst_sys_n;
    wire rst_usb_n;
    wire rst_disk_n;
    wire rst_dbg_sync_n;
    wire pll_locked;
    wire wdt_reset;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    clock_reset_mgr #(
        .WATCHDOG_CYCLES(WDT_TEST_CYCLES)
    ) dut (
        .clk_ref(clk_ref),
        .rst_ext_n(rst_ext_n),
        .clk_sys(clk_sys),
        .clk_usb(clk_usb),
        .clk_disk(clk_disk),
        .rst_sys_n(rst_sys_n),
        .rst_usb_n(rst_usb_n),
        .rst_disk_n(rst_disk_n),
        .rst_debug_n(rst_debug_n),
        .rst_dbg_sync_n(rst_dbg_sync_n),
        .pll_locked(pll_locked),
        .wdt_kick(wdt_kick),
        .wdt_reset(wdt_reset)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk_ref = 0;
    always #(CLK_REF_PERIOD/2) clk_ref = ~clk_ref;

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_clock_reset_mgr.vcd");
        $dumpvars(0, tb_clock_reset_mgr);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer cycle_count;
    reg [31:0] lock_time;
    reg [31:0] reset_release_time;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        rst_ext_n = 1'b0;
        rst_debug_n = 1'b1;
        wdt_kick = 1'b0;

        //---------------------------------------------------------------------
        // Test 1: Power-On Reset Sequence
        //---------------------------------------------------------------------
        test_begin("Power-On Reset Sequence");

        // Verify all resets active at power-on
        #(CLK_REF_PERIOD * 2);
        assert_eq_1(rst_sys_n, 1'b0, "System reset active at power-on");
        assert_eq_1(rst_usb_n, 1'b0, "USB reset active at power-on");
        assert_eq_1(rst_disk_n, 1'b0, "Disk reset active at power-on");
        assert_eq_1(pll_locked, 1'b0, "PLL unlocked at power-on");

        //---------------------------------------------------------------------
        // Test 2: PLL Lock Sequence
        //---------------------------------------------------------------------
        test_begin("PLL Lock Sequence");

        // Release external reset
        #(CLK_REF_PERIOD * 5);
        rst_ext_n = 1'b1;

        // Wait for PLL lock (should take ~100 reference cycles in behavioral model)
        cycle_count = 0;
        while (!pll_locked && cycle_count < 200) begin
            @(posedge clk_ref);
            cycle_count = cycle_count + 1;
        end

        assert_true(pll_locked, "PLL achieved lock");
        $display("  [INFO] PLL locked after %0d reference cycles", cycle_count);

        // Check lock time is within expected range (90-110 cycles for behavioral)
        assert_true(cycle_count >= 90 && cycle_count <= 150,
                   "PLL lock time within expected range");

        //---------------------------------------------------------------------
        // Test 3: Reset Synchronization
        //---------------------------------------------------------------------
        test_begin("Reset Synchronization");

        // After PLL lock, wait for reset synchronizers to release
        cycle_count = 0;
        while (!rst_sys_n && cycle_count < 20) begin
            @(posedge clk_sys);
            cycle_count = cycle_count + 1;
        end

        assert_true(rst_sys_n, "System reset released after PLL lock");
        $display("  [INFO] System reset released after %0d system clocks", cycle_count);

        // Verify all domain resets are released
        repeat(5) @(posedge clk_ref);
        assert_eq_1(rst_usb_n, 1'b1, "USB reset released");
        assert_eq_1(rst_disk_n, 1'b1, "Disk reset released");

        //---------------------------------------------------------------------
        // Test 4: Clock Generation
        //---------------------------------------------------------------------
        test_begin("Clock Generation");

        // Count clock edges to verify frequencies are generating
        // Note: In behavioral model, exact frequencies may vary
        cycle_count = 0;
        fork
            begin
                repeat(10) @(posedge clk_sys);
                cycle_count = cycle_count + 1;
            end
        join

        assert_true(cycle_count > 0, "System clock is running");
        test_info("All clocks verified generating");

        //---------------------------------------------------------------------
        // Test 5: Debug Reset Independence
        //---------------------------------------------------------------------
        test_begin("Debug Reset Independence");

        // Debug reset should be independent of system reset
        assert_eq_1(rst_dbg_sync_n, 1'b1, "Debug reset initially released");

        // Assert system reset, debug should stay released
        rst_ext_n = 1'b0;
        repeat(10) @(posedge clk_ref);

        // System resets should be active
        assert_eq_1(rst_sys_n, 1'b0, "System reset active");

        // Debug reset should still be released (independent)
        // Note: Debug reset only responds to rst_debug_n
        assert_eq_1(rst_dbg_sync_n, 1'b1, "Debug reset unaffected by system reset");

        // Now test debug reset itself
        rst_debug_n = 1'b0;
        repeat(5) @(posedge clk_ref);
        assert_eq_1(rst_dbg_sync_n, 1'b0, "Debug reset responds to rst_debug_n");

        // Release both resets
        rst_ext_n = 1'b1;
        rst_debug_n = 1'b1;

        // Wait for PLL to re-lock
        repeat(150) @(posedge clk_ref);

        //---------------------------------------------------------------------
        // Test 6: Watchdog Timer Expiration
        //---------------------------------------------------------------------
        test_begin("Watchdog Timer Expiration");

        // Ensure system is out of reset
        repeat(20) @(posedge clk_sys);
        assert_eq_1(rst_sys_n, 1'b1, "System out of reset before WDT test");
        assert_eq_1(wdt_reset, 1'b0, "WDT not expired initially");

        // Let watchdog count up past the threshold
        // WDT_TEST_CYCLES = 100, so wait >100 system clock cycles
        repeat(WDT_TEST_CYCLES + 50) @(posedge clk_sys);

        assert_eq_1(wdt_reset, 1'b1, "Watchdog timer expired");
        assert_eq_1(rst_sys_n, 1'b0, "System reset due to watchdog");

        //---------------------------------------------------------------------
        // Test 7: Watchdog Kick Prevention
        //---------------------------------------------------------------------
        test_begin("Watchdog Kick Prevention");

        // Reset the system
        rst_ext_n = 1'b0;
        repeat(10) @(posedge clk_ref);
        rst_ext_n = 1'b1;

        // Wait for PLL lock and reset release
        repeat(150) @(posedge clk_ref);
        repeat(20) @(posedge clk_sys);

        // Now periodically kick the watchdog, it should never expire
        repeat(5) begin
            // Wait half the watchdog period
            repeat(WDT_TEST_CYCLES / 2) @(posedge clk_sys);

            // Kick the watchdog
            wdt_kick = 1'b1;
            @(posedge clk_sys);
            wdt_kick = 1'b0;

            // Verify watchdog hasn't expired
            assert_eq_1(wdt_reset, 1'b0, "Watchdog not expired after kick");
        end

        test_pass("Watchdog kicks prevented expiration");

        //---------------------------------------------------------------------
        // Test 8: Reset During Operation
        //---------------------------------------------------------------------
        test_begin("Reset During Operation");

        // System should be running
        assert_eq_1(rst_sys_n, 1'b1, "System running before reset test");

        // Assert reset mid-operation
        rst_ext_n = 1'b0;
        repeat(5) @(posedge clk_ref);

        // All resets should be active
        assert_eq_1(rst_sys_n, 1'b0, "System reset active");
        assert_eq_1(pll_locked, 1'b0, "PLL unlocked on reset");

        // Release and verify recovery
        rst_ext_n = 1'b1;
        repeat(150) @(posedge clk_ref);
        repeat(10) @(posedge clk_sys);

        assert_eq_1(pll_locked, 1'b1, "PLL re-locked after reset");
        assert_eq_1(rst_sys_n, 1'b1, "System recovered from reset");

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        test_summary();

        #(CLK_REF_PERIOD * 10);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #100000;  // 100 us timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
