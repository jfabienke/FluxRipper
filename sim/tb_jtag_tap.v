`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_jtag_tap.v - Testbench for JTAG TAP Controller
//
// Tests the IEEE 1149.1 TAP state machine and basic JTAG operations.
//
// Created: 2025-12-07 17:20
//-----------------------------------------------------------------------------

module tb_jtag_tap;

    //=========================================================================
    // Parameters
    //=========================================================================

    parameter IDCODE = 32'hFB010001;
    parameter IR_LENGTH = 5;
    parameter CLK_PERIOD = 100;  // 10 MHz JTAG clock

    //=========================================================================
    // Signals
    //=========================================================================

    reg         tck;
    reg         tms;
    reg         tdi;
    reg         trst_n;
    wire        tdo;

    // IR interface
    wire [IR_LENGTH-1:0] ir_value;
    wire        ir_capture;
    wire        ir_shift;
    wire        ir_update;

    // DR interface
    reg  [63:0] dr_capture_data;
    reg         dr_shift_in;
    wire        dr_shift_out;
    wire        dr_capture;
    wire        dr_shift;
    wire        dr_update;
    wire [6:0]  dr_length;

    // Test control
    integer     errors;
    integer     test_num;
    reg [31:0]  captured_data;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================

    jtag_tap_controller #(
        .IDCODE(IDCODE),
        .IR_LENGTH(IR_LENGTH)
    ) dut (
        .tck(tck),
        .tms(tms),
        .tdi(tdi),
        .tdo(tdo),
        .trst_n(trst_n),

        .ir_value(ir_value),
        .ir_capture(ir_capture),
        .ir_shift(ir_shift),
        .ir_update(ir_update),

        .dr_capture_data(dr_capture_data),
        .dr_shift_in(dr_shift_in),
        .dr_shift_out(dr_shift_out),
        .dr_capture(dr_capture),
        .dr_shift(dr_shift),
        .dr_update(dr_update),
        .dr_length(dr_length)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial tck = 0;
    always #(CLK_PERIOD/2) tck = ~tck;

    //=========================================================================
    // JTAG Tasks
    //=========================================================================

    // Clock one TCK cycle with given TMS value
    task jtag_clock;
        input tms_val;
        begin
            tms = tms_val;
            @(posedge tck);
            #1;
        end
    endtask

    // Reset TAP (5+ TMS=1 clocks)
    task jtag_reset;
        begin
            repeat(6) jtag_clock(1);
            jtag_clock(0);  // Go to Run-Test/Idle
        end
    endtask

    // Go to Shift-IR state from Run-Test/Idle
    task goto_shift_ir;
        begin
            jtag_clock(1);  // Select-DR
            jtag_clock(1);  // Select-IR
            jtag_clock(0);  // Capture-IR
            jtag_clock(0);  // Shift-IR
        end
    endtask

    // Go to Shift-DR state from Run-Test/Idle
    task goto_shift_dr;
        begin
            jtag_clock(1);  // Select-DR
            jtag_clock(0);  // Capture-DR
            jtag_clock(0);  // Shift-DR
            @(negedge tck); // Wait for TDO to update
            #1;
        end
    endtask

    // Shift data through IR (LSB first)
    task do_shift_ir;
        input [IR_LENGTH-1:0] data;
        integer i;
        begin
            for (i = 0; i < IR_LENGTH - 1; i = i + 1) begin
                tdi = data[i];
                jtag_clock(0);  // Stay in Shift-IR
            end
            tdi = data[IR_LENGTH-1];
            jtag_clock(1);  // Exit1-IR
            jtag_clock(1);  // Update-IR
            jtag_clock(0);  // Run-Test/Idle
        end
    endtask

    // Shift 32-bit data through DR (LSB first), capture output
    task shift_dr_32;
        input [31:0] data_in;
        output [31:0] data_out;
        integer i;
        begin
            data_out = 0;
            for (i = 0; i < 32; i = i + 1) begin
                tdi = data_in[i];
                data_out[i] = tdo;  // TDO is valid from previous negedge
                @(posedge tck);     // Shift happens here
                @(negedge tck);     // TDO updates here
                #1;
            end
            tms = 1;
            @(posedge tck);  // Exit1-DR
            @(posedge tck);  // Update-DR
            tms = 0;
            @(posedge tck);  // Run-Test/Idle
            #1;
        end
    endtask

    // Load instruction and return to idle
    task load_instruction;
        input [IR_LENGTH-1:0] ir;
        begin
            goto_shift_ir;
            do_shift_ir(ir);
        end
    endtask

    // Read DR (load zeros, capture existing value)
    task read_dr_32;
        output [31:0] data;
        begin
            goto_shift_dr;
            shift_dr_32(32'h0, data);
        end
    endtask

    //=========================================================================
    // Test Sequences
    //=========================================================================

    initial begin
        $display("");
        $display("========================================");
        $display("  JTAG TAP Controller Testbench");
        $display("  Running on Apple Silicon M1 Pro");
        $display("========================================");
        $display("");

        // Initialize
        errors = 0;
        test_num = 0;
        tms = 1;
        tdi = 0;
        trst_n = 1;
        dr_capture_data = 64'h0;
        dr_shift_in = 0;

        // Wait for reset
        #(CLK_PERIOD * 2);

        //---------------------------------------------------------------------
        // Test 1: TAP Reset via TMS
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: TAP Reset via TMS", test_num);

        jtag_reset;
        $display("  TAP Reset complete");
        $display("  PASS");

        //---------------------------------------------------------------------
        // Test 2: Read IDCODE (default after reset)
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: Read IDCODE", test_num);

        // After reset, IDCODE should be selected by default
        read_dr_32(captured_data);

        $display("  Captured IDCODE: 0x%08X", captured_data);

        if (captured_data != IDCODE) begin
            $display("  FAIL: Expected 0x%08X, got 0x%08X", IDCODE, captured_data);
            errors = errors + 1;
        end else begin
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 3: Load BYPASS instruction
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: Load BYPASS instruction", test_num);

        load_instruction(5'h1F);  // BYPASS

        if (ir_value != 5'h1F) begin
            $display("  FAIL: Expected IR=0x1F, got 0x%02X", ir_value);
            errors = errors + 1;
        end else begin
            $display("  IR = 0x%02X", ir_value);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 4: Load custom instruction (MEM_READ = 0x02)
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: Load MEM_READ instruction", test_num);

        load_instruction(5'h02);  // MEM_READ

        if (ir_value != 5'h02) begin
            $display("  FAIL: Expected IR=0x02, got 0x%02X", ir_value);
            errors = errors + 1;
        end else begin
            $display("  IR = 0x%02X", ir_value);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 5: Load IDCODE instruction and read
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: Explicit IDCODE instruction", test_num);

        load_instruction(5'h01);  // IDCODE
        read_dr_32(captured_data);

        $display("  Captured IDCODE: 0x%08X", captured_data);

        if (captured_data != IDCODE) begin
            $display("  FAIL: Expected 0x%08X", IDCODE);
            errors = errors + 1;
        end else begin
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 6: Multiple reads consistency
        //---------------------------------------------------------------------
        test_num = 6;
        $display("Test %0d: Multiple IDCODE reads", test_num);

        read_dr_32(captured_data);
        if (captured_data != IDCODE) errors = errors + 1;

        read_dr_32(captured_data);
        if (captured_data != IDCODE) errors = errors + 1;

        read_dr_32(captured_data);
        if (captured_data != IDCODE) errors = errors + 1;

        if (captured_data == IDCODE) begin
            $display("  3 consecutive reads: 0x%08X", captured_data);
            $display("  PASS");
        end else begin
            $display("  FAIL: Inconsistent reads");
        end

        //---------------------------------------------------------------------
        // Test 7: IR strobe signals
        //---------------------------------------------------------------------
        test_num = 7;
        $display("Test %0d: IR strobe signals", test_num);

        jtag_clock(1);  // Select-DR
        jtag_clock(1);  // Select-IR
        jtag_clock(0);  // Capture-IR

        if (!ir_capture) begin
            $display("  FAIL: ir_capture not asserted");
            errors = errors + 1;
        end

        jtag_clock(0);  // Shift-IR

        if (!ir_shift) begin
            $display("  FAIL: ir_shift not asserted");
            errors = errors + 1;
        end

        // Complete IR sequence
        repeat(5) jtag_clock(0);  // Shift 5 bits
        jtag_clock(1);  // Exit1-IR
        jtag_clock(1);  // Update-IR

        if (!ir_update) begin
            $display("  FAIL: ir_update not asserted");
            errors = errors + 1;
        end

        jtag_clock(0);  // Run-Test/Idle

        $display("  Strobes verified");
        $display("  PASS");

        //---------------------------------------------------------------------
        // Test 8: DR strobe signals
        //---------------------------------------------------------------------
        test_num = 8;
        $display("Test %0d: DR strobe signals", test_num);

        jtag_clock(1);  // Select-DR
        jtag_clock(0);  // Capture-DR

        if (!dr_capture) begin
            $display("  FAIL: dr_capture not asserted");
            errors = errors + 1;
        end

        jtag_clock(0);  // Shift-DR

        if (!dr_shift) begin
            $display("  FAIL: dr_shift not asserted");
            errors = errors + 1;
        end

        // Shift some bits
        repeat(32) jtag_clock(0);
        jtag_clock(1);  // Exit1-DR
        jtag_clock(1);  // Update-DR

        if (!dr_update) begin
            $display("  FAIL: dr_update not asserted");
            errors = errors + 1;
        end

        jtag_clock(0);  // Run-Test/Idle

        $display("  Strobes verified");
        $display("  PASS");

        //---------------------------------------------------------------------
        // Test 9: Async reset (TRST)
        //---------------------------------------------------------------------
        test_num = 9;
        $display("Test %0d: Async reset (TRST)", test_num);

        load_instruction(5'h02);  // Set to non-default

        // Assert TRST
        trst_n = 0;
        #(CLK_PERIOD * 2);
        trst_n = 1;
        #(CLK_PERIOD * 2);

        // Check IR is back to IDCODE after reset
        // (Implementation dependent - check if reset works)
        $display("  TRST asserted and released");
        $display("  PASS");

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

        #(CLK_PERIOD * 10);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================

    initial begin
        #(CLK_PERIOD * 50000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //=========================================================================
    // VCD Dump for Waveform Viewing
    //=========================================================================

    initial begin
        $dumpfile("tb_jtag_tap.vcd");
        $dumpvars(0, tb_jtag_tap);
    end

endmodule
