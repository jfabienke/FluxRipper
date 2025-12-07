`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_system.v - Layer 6 Testbench: Full System Integration
//
// Tests the complete FluxRipper system with all subsystems integrated.
// Validates end-to-end functionality from JTAG to peripherals.
//
// Created: 2025-12-07 22:50
//-----------------------------------------------------------------------------

module tb_system;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter TCK_PERIOD = 100;    // JTAG clock (10 MHz)
    parameter CLK_PERIOD = 40;     // Reference clock (25 MHz)

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk_25m;
    reg         rst_n;
    reg         tck;
    reg         tms;
    reg         tdi;
    wire        tdo;
    reg         trst_n;

    // Disk interface
    reg         flux_in;
    reg         index_in;
    wire        motor_on;
    wire        head_sel;
    wire        dir;
    wire        step;

    // USB interface
    wire        usb_connected;
    wire        usb_configured;

    // Debug outputs
    wire        pll_locked;
    wire        sys_rst_n;

    // Test control
    integer     errors;
    integer     pass_count;
    integer     test_num;
    reg [31:0]  captured_data;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    fluxripper_top dut (
        .clk_25m        (clk_25m),
        .rst_n          (rst_n),
        .tck            (tck),
        .tms            (tms),
        .tdi            (tdi),
        .tdo            (tdo),
        .trst_n         (trst_n),
        .flux_in        (flux_in),
        .index_in       (index_in),
        .motor_on       (motor_on),
        .head_sel       (head_sel),
        .dir            (dir),
        .step           (step),
        .usb_connected  (usb_connected),
        .usb_configured (usb_configured),
        .pll_locked     (pll_locked),
        .sys_rst_n      (sys_rst_n)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk_25m = 0;
    always #(CLK_PERIOD/2) clk_25m = ~clk_25m;

    initial tck = 0;
    always #(TCK_PERIOD/2) tck = ~tck;

    // Reference for waiting on system clock
    wire clk = dut.clk_sys;

    //=========================================================================
    // Include JTAG Driver Tasks
    //=========================================================================
    `include "../common/jtag_driver.vh"

    //=========================================================================
    // High-Level Access Tasks
    //=========================================================================
    task dmi_reg_read;
        input  [6:0]  addr;
        output [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);
            dmi_in = {addr, 32'h0, 2'b01};
            shift_dr_41(dmi_in, dmi_out);
            repeat(10) @(posedge clk);
            dmi_in = 41'h0;
            shift_dr_41(dmi_in, dmi_out);
            data = dmi_out[33:2];
        end
    endtask

    task dmi_reg_write;
        input [6:0]  addr;
        input [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);
            dmi_in = {addr, data, 2'b10};
            shift_dr_41(dmi_in, dmi_out);
            repeat(10) @(posedge clk);
            dmi_in = 41'h0;
            shift_dr_41(dmi_in, dmi_out);
        end
    endtask

    task jtag_mem_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            dmi_reg_write(7'h38, 32'h00000404);
            dmi_reg_write(7'h39, addr);
            repeat(20) @(posedge clk);
            dmi_reg_read(7'h3C, data);
        end
    endtask

    task jtag_mem_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            dmi_reg_write(7'h38, 32'h00000004);
            dmi_reg_write(7'h39, addr);
            dmi_reg_write(7'h3C, data);
            repeat(20) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("");
        $display("===========================================================");
        $display("  Layer 6: Full System Integration Test");
        $display("  FluxRipper - Complete System Validation");
        $display("===========================================================");
        $display("");

        errors = 0;
        pass_count = 0;
        test_num = 0;
        tms = 1;
        tdi = 0;
        trst_n = 0;
        rst_n = 0;
        flux_in = 0;
        index_in = 0;

        //---------------------------------------------------------------------
        // Test 1: Power-On Reset Sequence
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: Power-On Reset Sequence", test_num);

        // Apply reset
        #100;
        rst_n = 1;
        trst_n = 1;

        // Wait for PLL lock and system stabilization
        repeat(500) @(posedge clk_25m);

        // Additional delay for clock domains to stabilize
        #2000;

        if (pll_locked !== 1'b1) begin
            $display("  FAIL: PLL not locked");
            errors = errors + 1;
        end else begin
            $display("  PLL locked: %b", pll_locked);
        end

        if (sys_rst_n !== 1'b1) begin
            $display("  FAIL: System reset not released");
            errors = errors + 1;
        end else begin
            $display("  System reset released: %b", sys_rst_n);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 2: JTAG IDCODE Read
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: JTAG IDCODE Read", test_num);

        jtag_reset;
        read_idcode(captured_data);

        if (captured_data != 32'hFB010001) begin
            $display("  FAIL: IDCODE = 0x%08X (expected 0xFB010001)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  IDCODE = 0x%08X (FluxRipper v1)", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 3: Read Boot ROM
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: Read Boot ROM", test_num);

        jtag_mem_read(32'h00000000, captured_data);

        if (captured_data != 32'h13000000) begin
            $display("  FAIL: ROM[0] = 0x%08X (expected 0x13000000)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  ROM[0] = 0x%08X (NOP instruction)", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 4: RAM Write/Read
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: RAM Write/Read", test_num);

        jtag_mem_write(32'h10000000, 32'hDEADBEEF);
        jtag_mem_read(32'h10000000, captured_data);

        if (captured_data != 32'hDEADBEEF) begin
            $display("  FAIL: RAM = 0x%08X (expected 0xDEADBEEF)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Write 0xDEADBEEF, Read 0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 5: System Control ID
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: System Control ID", test_num);

        jtag_mem_read(32'h40000000, captured_data);

        if (captured_data != 32'hFB010100) begin
            $display("  FAIL: SYSCTRL_ID = 0x%08X (expected 0xFB010100)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  SYSCTRL_ID = 0x%08X (FluxRipper v1.0)", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 6: Disk Controller Motor Control
        //---------------------------------------------------------------------
        test_num = 6;
        $display("Test %0d: Disk Controller Motor Control", test_num);

        // Turn motor on
        jtag_mem_write(32'h40010004, 32'h00000004);
        repeat(50) @(posedge clk);

        if (motor_on != 1'b1) begin
            $display("  FAIL: motor_on = %b (expected 1)", motor_on);
            errors = errors + 1;
        end else begin
            $display("  Motor ON: motor_on = %b", motor_on);
        end

        // Turn motor off
        jtag_mem_write(32'h40010004, 32'h00000000);
        repeat(50) @(posedge clk);

        if (motor_on != 1'b0) begin
            $display("  FAIL: motor_on = %b (expected 0)", motor_on);
            errors = errors + 1;
        end else begin
            $display("  Motor OFF: motor_on = %b", motor_on);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 7: Disk Index Pulse Counter
        //---------------------------------------------------------------------
        test_num = 7;
        $display("Test %0d: Disk Index Pulse Counter", test_num);

        // Generate 5 index pulses
        repeat (5) begin
            index_in = 1;
            repeat(10) @(posedge clk);
            index_in = 0;
            repeat(100) @(posedge clk);
        end

        jtag_mem_read(32'h40010010, captured_data);

        if (captured_data < 5) begin
            $display("  FAIL: INDEX_CNT = %0d (expected >= 5)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  INDEX_CNT = %0d pulses", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 8: USB Controller ID
        //---------------------------------------------------------------------
        test_num = 8;
        $display("Test %0d: USB Controller ID", test_num);

        jtag_mem_read(32'h40020000, captured_data);

        if (captured_data != 32'h05B20001) begin
            $display("  FAIL: USB_ID = 0x%08X (expected 0x05B20001)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  USB_ID = 0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 9: USB Connection Enable
        //---------------------------------------------------------------------
        test_num = 9;
        $display("Test %0d: USB Connection Enable", test_num);

        jtag_mem_write(32'h40020008, 32'h00000003);
        repeat(50) @(posedge clk);

        if (usb_connected != 1'b1 || usb_configured != 1'b1) begin
            $display("  FAIL: connected=%b configured=%b", usb_connected, usb_configured);
            errors = errors + 1;
        end else begin
            $display("  USB connected=%b configured=%b", usb_connected, usb_configured);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 10: Signal Tap ID
        //---------------------------------------------------------------------
        test_num = 10;
        $display("Test %0d: Signal Tap ID", test_num);

        jtag_mem_read(32'h40030000, captured_data);

        if (captured_data != 32'h51670001) begin
            $display("  FAIL: SIGTAP_ID = 0x%08X (expected 0x51670001)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  SIGTAP_ID = 0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 11: Signal Tap Capture
        //---------------------------------------------------------------------
        test_num = 11;
        $display("Test %0d: Signal Tap Capture", test_num);

        // Set trigger on motor_on bit (probe bit 23)
        jtag_mem_write(32'h4003000C, 32'h00800000);  // Trigger value
        jtag_mem_write(32'h40030010, 32'h00800000);  // Trigger mask

        // Arm
        jtag_mem_write(32'h40030008, 32'h00000001);
        repeat(20) @(posedge clk);

        // Enable motor (triggers capture)
        jtag_mem_write(32'h40010004, 32'h00000004);
        repeat(300) @(posedge clk);

        // Check triggered
        jtag_mem_read(32'h40030004, captured_data);

        if (captured_data[3] != 1'b1) begin
            $display("  FAIL: Signal Tap not triggered, STATUS=0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Signal Tap triggered: STATUS=0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        // Turn motor off
        jtag_mem_write(32'h40010004, 32'h00000000);

        //---------------------------------------------------------------------
        // Test 12: Memory Pattern Test
        //---------------------------------------------------------------------
        test_num = 12;
        $display("Test %0d: Memory Pattern Test", test_num);

        // Write pattern to multiple locations
        jtag_mem_write(32'h10001000, 32'h11111111);
        jtag_mem_write(32'h10001004, 32'h22222222);
        jtag_mem_write(32'h10001008, 32'h33333333);
        jtag_mem_write(32'h1000100C, 32'h44444444);

        // Read back and verify
        jtag_mem_read(32'h10001000, captured_data);
        if (captured_data != 32'h11111111) errors = errors + 1;

        jtag_mem_read(32'h10001004, captured_data);
        if (captured_data != 32'h22222222) errors = errors + 1;

        jtag_mem_read(32'h10001008, captured_data);
        if (captured_data != 32'h33333333) errors = errors + 1;

        jtag_mem_read(32'h1000100C, captured_data);
        if (captured_data != 32'h44444444) begin
            errors = errors + 1;
            $display("  FAIL: Memory pattern mismatch");
        end else begin
            $display("  Memory pattern verified at 4 locations");
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("");
        $display("===========================================================");
        $display("  Layer 6 Full System Test Summary");
        $display("===========================================================");
        $display("  Tests Run:    %0d", test_num);
        $display("  Tests Passed: %0d", pass_count);
        $display("  Tests Failed: %0d", errors);
        $display("===========================================================");

        if (errors == 0) begin
            $display("");
            $display("  *** ALL TESTS PASSED! ***");
            $display("  FluxRipper Full System Integration Validated!");
            $display("");
        end else begin
            $display("");
            $display("  SOME TESTS FAILED!");
            $display("");
        end

        #1000;
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(TCK_PERIOD * 2000000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_system.vcd");
        $dumpvars(0, tb_system);
    end

endmodule
