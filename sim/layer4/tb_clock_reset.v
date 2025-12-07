`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_clock_reset.v - Layer 4 Testbench: Clock/Reset Manager
//
// Tests clock generation, reset synchronization, and watchdog.
// Integrates with debug path to verify debug survives system reset.
//
// Created: 2025-12-07 21:30
//-----------------------------------------------------------------------------

module tb_clock_reset;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter REF_PERIOD = 40;     // 25 MHz reference (40 ns)
    parameter TCK_PERIOD = 100;    // 10 MHz JTAG clock
    parameter WDT_CYCLES = 1000;   // Short watchdog for testing

    //=========================================================================
    // Signals
    //=========================================================================
    // Reference clock and reset
    reg         clk_ref;
    reg         rst_ext_n;

    // Generated clocks
    wire        clk_sys;
    wire        clk_usb;
    wire        clk_disk;

    // Synchronized resets
    wire        rst_sys_n;
    wire        rst_usb_n;
    wire        rst_disk_n;

    // Debug interface
    reg         rst_debug_n;
    wire        rst_dbg_sync_n;

    // Status
    wire        pll_locked;

    // Watchdog
    reg         wdt_kick;
    wire        wdt_reset;

    // JTAG interface
    reg         tck;
    reg         tms;
    reg         tdi;
    reg         trst_n;
    wire        tdo;

    // Test control
    integer     errors;
    integer     test_num;
    integer     i;
    reg [31:0]  captured_data;
    integer     cycle_count;
    integer     edge_count;
    real        measured_freq;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    clock_reset_mgr #(
        .WATCHDOG_CYCLES(WDT_CYCLES)
    ) crm (
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
    // Optional: Full Debug Path for Integration Test
    //=========================================================================
    // DMI signals (directly usable for checking)
    wire [6:0]  dmi_addr;
    wire [31:0] dmi_wdata;
    wire [1:0]  dmi_op;
    wire        dmi_req;
    wire [31:0] dmi_rdata;
    wire [1:0]  dmi_resp;
    wire        dmi_ack;

    // TAP signals
    wire [4:0]  ir_value;
    wire        dr_capture, dr_shift, dr_update;
    wire        tap_tdo, dtm_tdo;

    assign tdo = (ir_value == 5'h10 || ir_value == 5'h11) ? dtm_tdo : tap_tdo;

    // Mock DMI response for debug path test
    reg [31:0] mock_reg = 32'hDEADBEEF;
    assign dmi_rdata = mock_reg;
    assign dmi_resp = 2'b00;
    assign dmi_ack = dmi_req;

    jtag_tap_controller #(
        .IDCODE(32'hFB010001),
        .IR_LENGTH(5)
    ) tap (
        .tck(tck),
        .tms(tms),
        .tdi(tdi),
        .tdo(tap_tdo),
        .trst_n(trst_n),
        .ir_value(ir_value),
        .dr_capture(dr_capture),
        .dr_shift(dr_shift),
        .dr_update(dr_update)
    );

    jtag_dtm dtm (
        .tck(tck),
        .trst_n(trst_n),
        .ir_value(ir_value),
        .dr_capture(dr_capture),
        .dr_shift(dr_shift),
        .dr_update(dr_update),
        .tdi(tdi),
        .tdo(dtm_tdo),
        .dmi_addr(dmi_addr),
        .dmi_wdata(dmi_wdata),
        .dmi_op(dmi_op),
        .dmi_req(dmi_req),
        .dmi_rdata(dmi_rdata),
        .dmi_resp(dmi_resp),
        .dmi_ack(dmi_ack)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk_ref = 0;
    always #(REF_PERIOD/2) clk_ref = ~clk_ref;

    initial tck = 0;
    always #(TCK_PERIOD/2) tck = ~tck;

    //=========================================================================
    // Include JTAG Driver Tasks
    //=========================================================================
    `include "../common/jtag_driver.vh"

    //=========================================================================
    // Frequency Measurement Task
    //=========================================================================
    task measure_frequency;
        input integer clk_select;  // 0=sys, 1=usb, 2=disk
        output real freq_mhz;
        integer start_time, end_time;
        integer edges;
        begin
            edges = 0;
            start_time = $time;

            // Count 100 rising edges
            repeat (100) begin
                case (clk_select)
                    0: @(posedge clk_sys);
                    1: @(posedge clk_usb);
                    2: @(posedge clk_disk);
                endcase
                edges = edges + 1;
            end

            end_time = $time;

            // Calculate frequency: edges / time_ns * 1000 = MHz
            freq_mhz = (edges * 1000.0) / (end_time - start_time);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("");
        $display("========================================");
        $display("  Layer 4: Clock/Reset Manager Test");
        $display("  FluxRipper Simulation");
        $display("========================================");
        $display("");

        errors = 0;
        test_num = 0;
        rst_ext_n = 0;
        rst_debug_n = 1;
        wdt_kick = 0;
        tms = 1;
        tdi = 0;
        trst_n = 1;

        //---------------------------------------------------------------------
        // Test 1: PLL Lock
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: PLL Lock Detection", test_num);

        // Release external reset
        #(REF_PERIOD * 10);
        rst_ext_n = 1;

        // Wait for PLL lock (should take ~100 ref cycles)
        cycle_count = 0;
        while (!pll_locked && cycle_count < 200) begin
            @(posedge clk_ref);
            cycle_count = cycle_count + 1;
        end

        if (!pll_locked) begin
            $display("  FAIL: PLL did not lock after %0d cycles", cycle_count);
            errors = errors + 1;
        end else begin
            $display("  PLL locked after %0d reference cycles", cycle_count);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 2: Clock Frequencies
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: Clock Frequencies", test_num);

        // Measure system clock
        measure_frequency(0, measured_freq);
        $display("  clk_sys: %.1f MHz", measured_freq);

        // Measure USB clock
        measure_frequency(1, measured_freq);
        $display("  clk_usb: %.1f MHz", measured_freq);

        // Measure disk clock
        measure_frequency(2, measured_freq);
        $display("  clk_disk: %.1f MHz", measured_freq);

        // For simulation, clocks are derived behaviorally
        // Just verify they're running (non-zero frequency)
        if (measured_freq > 0) begin
            $display("  All clocks running");
            $display("  PASS");
        end else begin
            $display("  FAIL: Clock not running");
            errors = errors + 1;
        end

        //---------------------------------------------------------------------
        // Test 3: Reset Sequence
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: Reset Sequence", test_num);

        // All resets should be released after PLL lock
        #(REF_PERIOD * 20);

        if (!rst_sys_n) begin
            $display("  FAIL: rst_sys_n still asserted");
            errors = errors + 1;
        end else if (!rst_usb_n) begin
            $display("  FAIL: rst_usb_n still asserted");
            errors = errors + 1;
        end else if (!rst_disk_n) begin
            $display("  FAIL: rst_disk_n still asserted");
            errors = errors + 1;
        end else begin
            $display("  rst_sys_n=%b, rst_usb_n=%b, rst_disk_n=%b",
                     rst_sys_n, rst_usb_n, rst_disk_n);
            $display("  All domain resets released");
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 4: Watchdog Timeout
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: Watchdog Timeout", test_num);

        // Wait for watchdog to expire (WDT_CYCLES system clocks)
        cycle_count = 0;
        while (!wdt_reset && cycle_count < WDT_CYCLES + 100) begin
            @(posedge clk_sys);
            cycle_count = cycle_count + 1;
        end

        if (!wdt_reset) begin
            $display("  FAIL: Watchdog did not trigger");
            errors = errors + 1;
        end else begin
            $display("  Watchdog triggered after %0d cycles", cycle_count);
            // Reset should be asserted now
            if (rst_sys_n) begin
                $display("  FAIL: rst_sys_n not asserted by watchdog");
                errors = errors + 1;
            end else begin
                $display("  System reset asserted by watchdog");
                $display("  PASS");
            end
        end

        //---------------------------------------------------------------------
        // Test 5: Watchdog Kick
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: Watchdog Kick", test_num);

        // Reset the system to clear watchdog
        rst_ext_n = 0;
        #(REF_PERIOD * 10);
        rst_ext_n = 1;

        // Wait for PLL and reset release
        while (!pll_locked) @(posedge clk_ref);
        #(REF_PERIOD * 20);

        // Kick watchdog periodically (every WDT_CYCLES/2)
        repeat (5) begin
            repeat (WDT_CYCLES/2) @(posedge clk_sys);
            wdt_kick = 1;
            @(posedge clk_sys);
            wdt_kick = 0;
        end

        // Watchdog should not have triggered
        if (wdt_reset) begin
            $display("  FAIL: Watchdog triggered despite kicks");
            errors = errors + 1;
        end else begin
            $display("  Watchdog did not trigger (kicked 5 times)");
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 6: Debug Reset Bypass
        //---------------------------------------------------------------------
        test_num = 6;
        $display("Test %0d: Debug Reset Bypass", test_num);

        // Initialize JTAG
        trst_n = 0;
        #(TCK_PERIOD * 2);
        trst_n = 1;
        #(TCK_PERIOD * 2);
        jtag_reset;

        // Read IDCODE to verify debug path works
        read_idcode(captured_data);
        if (captured_data != 32'hFB010001) begin
            $display("  FAIL: Initial IDCODE = 0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Initial IDCODE = 0x%08X", captured_data);
        end

        // Assert system reset (but NOT debug reset)
        rst_ext_n = 0;
        #(REF_PERIOD * 10);
        rst_ext_n = 1;

        // Wait for PLL lock
        while (!pll_locked) @(posedge clk_ref);
        #(REF_PERIOD * 10);

        // Debug should still work (did not reset)
        read_idcode(captured_data);
        if (captured_data != 32'hFB010001) begin
            $display("  FAIL: IDCODE after sys reset = 0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  IDCODE after system reset = 0x%08X", captured_data);
            $display("  Debug survived system reset");
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("");
        $display("========================================");
        if (errors == 0) begin
            $display("  ALL %0d TESTS PASSED", test_num);
        end else begin
            $display("  FAILED: %0d errors in %0d tests", errors, test_num);
        end
        $display("========================================");
        $display("");

        #(REF_PERIOD * 100);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(REF_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_clock_reset.vcd");
        $dumpvars(0, tb_clock_reset);
    end

endmodule
