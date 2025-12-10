//-----------------------------------------------------------------------------
// FluxRipper Common Test Utilities
// Created: 2025-12-07
//
// Reusable test infrastructure for all testbenches:
//   - Standard pass/fail reporting macros
//   - Error accumulation pattern
//   - Timeout watchdog template
//   - VCD dump initialization
//   - Clock generation template
//
// Usage:
//   `include "test_utils.vh"
//
// Compatibility: Icarus Verilog 10+
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Test Result Tracking
//-----------------------------------------------------------------------------
integer test_errors;
integer test_count;
integer test_passed;

task test_init;
    begin
        test_errors = 0;
        test_count = 0;
        test_passed = 0;
        $display("==========================================");
        $display(" FluxRipper Test Suite Starting");
        $display("==========================================");
    end
endtask

//-----------------------------------------------------------------------------
// Test Case Reporting
//-----------------------------------------------------------------------------
task test_begin;
    input [255:0] test_name;  // Up to 32 chars
    begin
        test_count = test_count + 1;
        $display("\n[TEST %0d] %0s", test_count, test_name);
    end
endtask

task test_pass;
    input [255:0] message;
    begin
        test_passed = test_passed + 1;
        $display("  [PASS] %0s", message);
    end
endtask

task test_fail;
    input [255:0] message;
    begin
        test_errors = test_errors + 1;
        $display("  [FAIL] %0s", message);
    end
endtask

task test_info;
    input [255:0] message;
    begin
        $display("  [INFO] %0s", message);
    end
endtask

//-----------------------------------------------------------------------------
// Assertion Helpers
//-----------------------------------------------------------------------------
task assert_eq_32;
    input [31:0] actual;
    input [31:0] expected;
    input [255:0] message;
    begin
        if (actual === expected) begin
            $display("  [PASS] %0s: 0x%08X", message, actual);
            test_passed = test_passed + 1;
        end else begin
            $display("  [FAIL] %0s: got 0x%08X, expected 0x%08X", message, actual, expected);
            test_errors = test_errors + 1;
        end
    end
endtask

task assert_eq_8;
    input [7:0] actual;
    input [7:0] expected;
    input [255:0] message;
    begin
        if (actual === expected) begin
            $display("  [PASS] %0s: 0x%02X", message, actual);
            test_passed = test_passed + 1;
        end else begin
            $display("  [FAIL] %0s: got 0x%02X, expected 0x%02X", message, actual, expected);
            test_errors = test_errors + 1;
        end
    end
endtask

task assert_eq_2;
    input [1:0] actual;
    input [1:0] expected;
    input [255:0] message;
    begin
        if (actual === expected) begin
            $display("  [PASS] %0s: %02b", message, actual);
            test_passed = test_passed + 1;
        end else begin
            $display("  [FAIL] %0s: got %02b, expected %02b", message, actual, expected);
            test_errors = test_errors + 1;
        end
    end
endtask

task assert_eq_1;
    input actual;
    input expected;
    input [255:0] message;
    begin
        if (actual === expected) begin
            $display("  [PASS] %0s: %0b", message, actual);
            test_passed = test_passed + 1;
        end else begin
            $display("  [FAIL] %0s: got %0b, expected %0b", message, actual, expected);
            test_errors = test_errors + 1;
        end
    end
endtask

task assert_true;
    input condition;
    input [255:0] message;
    begin
        if (condition) begin
            $display("  [PASS] %0s", message);
            test_passed = test_passed + 1;
        end else begin
            $display("  [FAIL] %0s", message);
            test_errors = test_errors + 1;
        end
    end
endtask

task assert_false;
    input condition;
    input [255:0] message;
    begin
        if (!condition) begin
            $display("  [PASS] %0s (false)", message);
            test_passed = test_passed + 1;
        end else begin
            $display("  [FAIL] %0s (expected false, got true)", message);
            test_errors = test_errors + 1;
        end
    end
endtask

//-----------------------------------------------------------------------------
// Test Summary
//-----------------------------------------------------------------------------
task test_summary;
    begin
        $display("\n==========================================");
        $display(" Test Summary");
        $display("==========================================");
        $display("  Total Tests:  %0d", test_count);
        $display("  Assertions:   %0d passed, %0d failed", test_passed, test_errors);
        $display("==========================================");
        if (test_errors == 0) begin
            $display("  RESULT: ALL TESTS PASSED");
        end else begin
            $display("  RESULT: %0d FAILURES", test_errors);
        end
        $display("==========================================\n");
    end
endtask

//-----------------------------------------------------------------------------
// VCD Dump Helper
// Usage: `VCD_DUMP("tb_name.vcd", tb_module)
//-----------------------------------------------------------------------------
`define VCD_DUMP(filename, module_name) \
    initial begin \
        $dumpfile(filename); \
        $dumpvars(0, module_name); \
    end

//-----------------------------------------------------------------------------
// Clock Generation Helper
// Generates a clock with the specified period
//-----------------------------------------------------------------------------
`define CLOCK_GEN(clk_signal, period) \
    initial clk_signal = 0; \
    always #(period/2) clk_signal = ~clk_signal;

//-----------------------------------------------------------------------------
// Hex Dump Helper (for debugging)
//-----------------------------------------------------------------------------
task hex_dump;
    input [255:0] label;
    input [31:0] data;
    begin
        $display("  %0s: 0x%08X (%0d)", label, data, data);
    end
endtask

//-----------------------------------------------------------------------------
// Binary Dump Helper (for debugging bit patterns)
//-----------------------------------------------------------------------------
task bin_dump;
    input [255:0] label;
    input [31:0] data;
    begin
        $display("  %0s: %032b", label, data);
    end
endtask
