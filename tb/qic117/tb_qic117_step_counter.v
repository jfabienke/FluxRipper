//==============================================================================
// QIC-117 STEP Pulse Counter Testbench
//==============================================================================
// File: tb_qic117_step_counter.v
// Description: Verifies STEP pulse counting and command decoding for QIC-117
//              tape protocol. Tests debouncing, timeout behavior, and various
//              command pulse counts.
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_step_counter;

    //=========================================================================
    // Parameters - Use shorter timeouts for simulation
    //=========================================================================
    parameter CLK_PERIOD    = 5;            // 200 MHz = 5ns period
    parameter CLK_FREQ_HZ   = 200_000_000;
    parameter TIMEOUT_MS    = 1;            // 1ms timeout for faster sim
    parameter DEBOUNCE_US   = 1;            // 1us debounce for faster sim

    // Derived timing
    parameter TIMEOUT_CLKS  = (CLK_FREQ_HZ / 1000) * TIMEOUT_MS;
    parameter DEBOUNCE_CLKS = (CLK_FREQ_HZ / 1_000_000) * DEBOUNCE_US;

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;
    reg         tape_mode_en;
    reg         step_in;

    wire [5:0]  pulse_count;
    wire        command_valid;
    wire [5:0]  latched_command;
    wire        counting;
    wire        timeout_pending;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_step_counter #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .TIMEOUT_MS(TIMEOUT_MS),
        .DEBOUNCE_US(DEBOUNCE_US)
    ) u_dut (
        .clk(clk),
        .reset_n(reset_n),
        .tape_mode_en(tape_mode_en),
        .step_in(step_in),
        .pulse_count(pulse_count),
        .command_valid(command_valid),
        .latched_command(latched_command),
        .counting(counting),
        .timeout_pending(timeout_pending)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // Tasks
    //=========================================================================

    // Generate a single STEP pulse with proper timing
    task send_step_pulse;
        begin
            step_in = 1'b1;
            #(DEBOUNCE_US * 1000 * 2);  // Hold high for debounce + margin
            step_in = 1'b0;
            #(DEBOUNCE_US * 1000 * 2);  // Hold low for debounce + margin
        end
    endtask

    // Generate N STEP pulses for a command
    task send_command;
        input [5:0] num_pulses;
        integer i;
        begin
            $display("  Sending %0d STEP pulses...", num_pulses);
            for (i = 0; i < num_pulses; i = i + 1) begin
                send_step_pulse;
            end
        end
    endtask

    // Wait for command timeout to expire
    task wait_for_timeout;
        begin
            $display("  Waiting for timeout...");
            #(TIMEOUT_MS * 1_000_000 + 10000);  // Timeout + margin
        end
    endtask

    // Generate glitchy/bouncy STEP pulse
    task send_bouncy_step;
        integer i;
        begin
            // Simulate contact bounce
            for (i = 0; i < 5; i = i + 1) begin
                step_in = 1'b1;
                #(DEBOUNCE_US * 100);  // Short pulse (less than debounce)
                step_in = 1'b0;
                #(DEBOUNCE_US * 100);
            end
            // Finally settle high
            step_in = 1'b1;
            #(DEBOUNCE_US * 1000 * 3);  // Hold long enough to debounce
            step_in = 1'b0;
            #(DEBOUNCE_US * 1000 * 2);
        end
    endtask

    //=========================================================================
    // Test Stimulus
    //=========================================================================
    integer errors;
    integer test_num;

    initial begin
        $display("============================================");
        $display("QIC-117 STEP Pulse Counter Testbench");
        $display("============================================");
        $display("CLK_FREQ_HZ   = %0d", CLK_FREQ_HZ);
        $display("TIMEOUT_MS    = %0d", TIMEOUT_MS);
        $display("DEBOUNCE_US   = %0d", DEBOUNCE_US);
        $display("TIMEOUT_CLKS  = %0d", TIMEOUT_CLKS);
        $display("DEBOUNCE_CLKS = %0d", DEBOUNCE_CLKS);

        // Initialize
        reset_n      = 0;
        tape_mode_en = 0;
        step_in      = 0;
        errors       = 0;
        test_num     = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        //=====================================================================
        // Test 1: Tape mode disabled - no counting
        //=====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Tape mode disabled ---", test_num);

        tape_mode_en = 0;
        send_command(5);
        wait_for_timeout;

        if (command_valid) begin
            $display("  FAIL: Command generated when tape mode disabled");
            errors = errors + 1;
        end else begin
            $display("  PASS: No command when tape mode disabled");
        end

        //=====================================================================
        // Test 2: Single pulse command (QIC_RESET = 1)
        //=====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Single pulse command (RESET) ---", test_num);

        tape_mode_en = 1;
        #1000;

        send_command(1);
        wait_for_timeout;

        // Wait for command_valid pulse
        repeat (100) @(posedge clk);

        if (latched_command == 6'd1) begin
            $display("  PASS: Received command %0d (expected 1)", latched_command);
        end else begin
            $display("  FAIL: Received command %0d (expected 1)", latched_command);
            errors = errors + 1;
        end

        // Let FSM return to idle
        #10000;

        //=====================================================================
        // Test 3: Report Next Bit command (5 pulses)
        //=====================================================================
        test_num = 3;
        $display("\n--- Test %0d: 5 pulses (REPORT_NEXT_BIT) ---", test_num);

        send_command(5);
        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (latched_command == 6'd5) begin
            $display("  PASS: Received command %0d (expected 5)", latched_command);
        end else begin
            $display("  FAIL: Received command %0d (expected 5)", latched_command);
            errors = errors + 1;
        end

        #10000;

        //=====================================================================
        // Test 4: Seek Load Point command (8 pulses)
        //=====================================================================
        test_num = 4;
        $display("\n--- Test %0d: 8 pulses (SEEK_LOAD_POINT) ---", test_num);

        send_command(8);
        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (latched_command == 6'd8) begin
            $display("  PASS: Received command %0d (expected 8)", latched_command);
        end else begin
            $display("  FAIL: Received command %0d (expected 8)", latched_command);
            errors = errors + 1;
        end

        #10000;

        //=====================================================================
        // Test 5: Maximum valid command (48 pulses)
        //=====================================================================
        test_num = 5;
        $display("\n--- Test %0d: 48 pulses (max valid) ---", test_num);

        send_command(48);
        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (latched_command == 6'd48) begin
            $display("  PASS: Received command %0d (expected 48)", latched_command);
        end else begin
            $display("  FAIL: Received command %0d (expected 48)", latched_command);
            errors = errors + 1;
        end

        #10000;

        //=====================================================================
        // Test 6: Debounce filtering
        //=====================================================================
        test_num = 6;
        $display("\n--- Test %0d: Debounce filtering ---", test_num);

        send_bouncy_step;  // Should count as 1 pulse
        send_bouncy_step;  // Should count as 1 pulse
        send_bouncy_step;  // Should count as 1 pulse
        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (latched_command == 6'd3) begin
            $display("  PASS: Debounce filtered correctly, command = %0d", latched_command);
        end else begin
            $display("  FAIL: Debounce failed, command = %0d (expected 3)", latched_command);
            errors = errors + 1;
        end

        #10000;

        //=====================================================================
        // Test 7: Counting state indicator
        //=====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Counting state indicator ---", test_num);

        // Check counting goes high during pulse sequence
        fork
            begin
                send_command(10);
            end
            begin
                // Wait for first pulse to register
                #(DEBOUNCE_US * 1000 * 3);
                repeat (100) @(posedge clk);
                if (counting) begin
                    $display("  PASS: counting=1 during pulse sequence");
                end else begin
                    $display("  FAIL: counting=0 during pulse sequence");
                    errors = errors + 1;
                end
            end
        join

        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (!counting) begin
            $display("  PASS: counting=0 after timeout");
        end else begin
            $display("  FAIL: counting=1 after timeout");
            errors = errors + 1;
        end

        #10000;

        //=====================================================================
        // Test 8: Rapid consecutive commands
        //=====================================================================
        test_num = 8;
        $display("\n--- Test %0d: Consecutive commands ---", test_num);

        // First command: 6 pulses
        send_command(6);
        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (latched_command == 6'd6) begin
            $display("  PASS: First command = %0d", latched_command);
        end else begin
            $display("  FAIL: First command = %0d (expected 6)", latched_command);
            errors = errors + 1;
        end

        #5000;

        // Second command: 9 pulses
        send_command(9);
        wait_for_timeout;
        repeat (100) @(posedge clk);

        if (latched_command == 6'd9) begin
            $display("  PASS: Second command = %0d", latched_command);
        end else begin
            $display("  FAIL: Second command = %0d (expected 9)", latched_command);
            errors = errors + 1;
        end

        #10000;

        //=====================================================================
        // Test 9: Disable tape mode mid-count
        //=====================================================================
        test_num = 9;
        $display("\n--- Test %0d: Disable tape mode mid-count ---", test_num);

        send_step_pulse;
        send_step_pulse;
        send_step_pulse;

        // Disable tape mode before timeout
        tape_mode_en = 0;
        #1000;

        if (!counting && pulse_count == 0) begin
            $display("  PASS: State reset when tape mode disabled");
        end else begin
            $display("  FAIL: State not reset, counting=%0d, pulse_count=%0d",
                     counting, pulse_count);
            errors = errors + 1;
        end

        tape_mode_en = 1;
        #10000;

        //=====================================================================
        // Test 10: Command valid pulse width
        //=====================================================================
        test_num = 10;
        $display("\n--- Test %0d: command_valid pulse width ---", test_num);

        send_command(7);
        wait_for_timeout;

        // Count cycles command_valid is high
        begin : check_valid_width
            integer valid_cycles;
            valid_cycles = 0;
            repeat (200) begin
                @(posedge clk);
                if (command_valid) valid_cycles = valid_cycles + 1;
            end

            if (valid_cycles == 1) begin
                $display("  PASS: command_valid is single-cycle pulse");
            end else begin
                $display("  FAIL: command_valid high for %0d cycles (expected 1)",
                         valid_cycles);
                errors = errors + 1;
            end
        end

        //=====================================================================
        // Summary
        //=====================================================================
        #1000;
        $display("\n============================================");
        $display("Test Summary: %0d errors", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("============================================");

        $finish;
    end

    //=========================================================================
    // Monitor - Display state changes
    //=========================================================================
    reg command_valid_prev;

    always @(posedge clk) begin
        command_valid_prev <= command_valid;

        if (command_valid && !command_valid_prev) begin
            $display("  [%0t] command_valid: cmd=%0d", $time, latched_command);
        end
    end

    //=========================================================================
    // Timeout watchdog
    //=========================================================================
    initial begin
        #50_000_000;  // 50ms simulation limit
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
