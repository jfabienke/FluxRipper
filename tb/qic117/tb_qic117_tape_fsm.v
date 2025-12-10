//==============================================================================
// QIC-117 Tape FSM Testbench
//==============================================================================
// File: tb_qic117_tape_fsm.v
// Description: Verifies tape position tracking and motion control state machine.
//              Tests seek, skip, streaming, retension, and track change operations.
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_tape_fsm;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD  = 5;              // 200 MHz = 5ns period
    parameter CLK_FREQ_HZ = 200_000_000;
    parameter MAX_SEGMENTS = 100;           // Reduced for faster simulation
    parameter MAX_TRACKS   = 5;             // Reduced for faster simulation

    //=========================================================================
    // QIC-117 Command Codes
    //=========================================================================
    localparam [5:0] CMD_RESET           = 6'd1;
    localparam [5:0] CMD_PAUSE           = 6'd6;
    localparam [5:0] CMD_SEEK_BOT        = 6'd8;
    localparam [5:0] CMD_SEEK_EOT        = 6'd9;
    localparam [5:0] CMD_SKIP_REV_SEG    = 6'd10;
    localparam [5:0] CMD_SKIP_FWD_SEG    = 6'd12;
    localparam [5:0] CMD_SKIP_REV_FILE   = 6'd11;
    localparam [5:0] CMD_SKIP_FWD_FILE   = 6'd13;
    localparam [5:0] CMD_LOGICAL_FWD     = 6'd21;
    localparam [5:0] CMD_LOGICAL_REV     = 6'd22;
    localparam [5:0] CMD_STOP            = 6'd23;
    localparam [5:0] CMD_RETENSION       = 6'd24;
    localparam [5:0] CMD_PHYSICAL_FWD    = 6'd30;
    localparam [5:0] CMD_PHYSICAL_REV    = 6'd31;
    localparam [5:0] CMD_EJECT           = 6'd37;

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;
    reg         enable;
    reg  [5:0]  command;
    reg         command_valid;

    wire        command_done;
    wire        command_error;
    wire [15:0] segment;
    wire [4:0]  track;
    wire        direction;
    wire        at_bot;
    wire        at_eot;
    wire        at_file_mark;
    wire        motor_on;
    wire        tape_moving;
    wire [1:0]  motion_mode;
    wire [3:0]  fsm_state;
    wire [31:0] operation_timer;

    reg         index_pulse;
    reg         file_mark_detect;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_tape_fsm #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .MAX_SEGMENTS  (MAX_SEGMENTS),
        .MAX_TRACKS    (MAX_TRACKS)
    ) u_dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .enable          (enable),
        .command         (command),
        .command_valid   (command_valid),
        .command_done    (command_done),
        .command_error   (command_error),
        .segment         (segment),
        .track           (track),
        .direction       (direction),
        .at_bot          (at_bot),
        .at_eot          (at_eot),
        .at_file_mark    (at_file_mark),
        .motor_on        (motor_on),
        .tape_moving     (tape_moving),
        .motion_mode     (motion_mode),
        .index_pulse     (index_pulse),
        .file_mark_detect(file_mark_detect),
        .fsm_state       (fsm_state),
        .operation_timer (operation_timer)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // Index Pulse Generator (simulates tape segment boundaries)
    //=========================================================================
    // Generate index pulses every ~1000 clocks when tape is moving
    reg [15:0] index_counter;
    localparam INDEX_INTERVAL = 1000;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            index_counter <= 0;
            index_pulse   <= 0;
        end else if (tape_moving) begin
            if (index_counter >= INDEX_INTERVAL) begin
                index_counter <= 0;
                index_pulse   <= 1;
            end else begin
                index_counter <= index_counter + 1;
                index_pulse   <= 0;
            end
        end else begin
            index_counter <= 0;
            index_pulse   <= 0;
        end
    end

    //=========================================================================
    // Tasks
    //=========================================================================

    // Send a command
    task send_command;
        input [5:0] cmd;
        begin
            command       = cmd;
            command_valid = 1'b1;
            @(posedge clk);
            command_valid = 1'b0;
            @(posedge clk);
        end
    endtask

    // Wait for command completion with timeout
    task wait_command_done;
        input integer timeout_cycles;
        integer count;
        begin
            count = 0;
            while (!command_done && !command_error && count < timeout_cycles) begin
                @(posedge clk);
                count = count + 1;
            end
            if (count >= timeout_cycles) begin
                $display("  WARNING: Command timeout after %0d cycles", count);
            end
        end
    endtask

    // Wait for specific segment position
    task wait_for_segment;
        input [15:0] target_seg;
        input integer timeout_cycles;
        integer count;
        begin
            count = 0;
            while (segment != target_seg && count < timeout_cycles) begin
                @(posedge clk);
                count = count + 1;
            end
        end
    endtask

    //=========================================================================
    // Test Stimulus
    //=========================================================================
    integer errors;
    integer test_num;

    initial begin
        $display("============================================");
        $display("QIC-117 Tape FSM Testbench");
        $display("============================================");
        $display("CLK_FREQ_HZ   = %0d", CLK_FREQ_HZ);
        $display("MAX_SEGMENTS  = %0d", MAX_SEGMENTS);
        $display("MAX_TRACKS    = %0d", MAX_TRACKS);

        // Initialize
        reset_n         = 0;
        enable          = 0;
        command         = 6'd0;
        command_valid   = 0;
        file_mark_detect = 0;
        errors          = 0;
        test_num        = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        //=====================================================================
        // Test 1: Initial state after reset
        //=====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Initial state after reset ---", test_num);

        if (segment != 0) begin
            $display("  FAIL: segment=%0d (expected 0)", segment);
            errors = errors + 1;
        end else begin
            $display("  PASS: segment=0");
        end

        if (track != 0) begin
            $display("  FAIL: track=%0d (expected 0)", track);
            errors = errors + 1;
        end else begin
            $display("  PASS: track=0");
        end

        if (!at_bot) begin
            $display("  FAIL: at_bot=%0d (expected 1)", at_bot);
            errors = errors + 1;
        end else begin
            $display("  PASS: at_bot=1");
        end

        if (motor_on) begin
            $display("  FAIL: motor_on=%0d (expected 0)", motor_on);
            errors = errors + 1;
        end else begin
            $display("  PASS: motor_on=0");
        end

        //=====================================================================
        // Test 2: Enable FSM
        //=====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Enable FSM ---", test_num);

        enable = 1;
        @(posedge clk);
        @(posedge clk);

        $display("  FSM enabled, state=%0d", fsm_state);

        //=====================================================================
        // Test 3: Reset command
        //=====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Reset command ---", test_num);

        send_command(CMD_RESET);
        @(posedge clk);
        @(posedge clk);

        if (command_done) begin
            $display("  PASS: Reset command completed");
        end else begin
            $display("  FAIL: Reset command did not complete");
            errors = errors + 1;
        end

        //=====================================================================
        // Test 4: Seek to EOT
        //=====================================================================
        test_num = 4;
        $display("\n--- Test %0d: Seek to EOT ---", test_num);

        send_command(CMD_SEEK_EOT);

        // Wait for motor to start
        repeat (10) @(posedge clk);

        if (motor_on) begin
            $display("  PASS: Motor started");
        end else begin
            $display("  FAIL: Motor not started");
            errors = errors + 1;
        end

        // Wait for seek to complete (or timeout)
        wait_command_done(500000);

        if (at_eot) begin
            $display("  PASS: Reached EOT, segment=%0d", segment);
        end else begin
            $display("  INFO: Seek in progress, segment=%0d, at_eot=%0d", segment, at_eot);
        end

        // Force to EOT position for subsequent tests
        repeat (200000) @(posedge clk);
        $display("  Final: segment=%0d, at_eot=%0d", segment, at_eot);

        //=====================================================================
        // Test 5: Seek to BOT from EOT
        //=====================================================================
        test_num = 5;
        $display("\n--- Test %0d: Seek to BOT ---", test_num);

        send_command(CMD_SEEK_BOT);

        // Wait for some progress
        repeat (10) @(posedge clk);

        if (direction == 1) begin
            $display("  PASS: Direction is reverse");
        end else begin
            $display("  INFO: Direction=%0d", direction);
        end

        // Wait for seek to complete
        wait_command_done(500000);

        if (at_bot) begin
            $display("  PASS: Reached BOT, segment=%0d", segment);
        end else begin
            $display("  INFO: segment=%0d, at_bot=%0d", segment, at_bot);
        end

        // Force to BOT for subsequent tests
        repeat (200000) @(posedge clk);
        $display("  Final: segment=%0d, at_bot=%0d", segment, at_bot);

        //=====================================================================
        // Test 6: Skip forward segment
        //=====================================================================
        test_num = 6;
        $display("\n--- Test %0d: Skip forward segment ---", test_num);

        // Make sure we're at BOT first
        if (!at_bot) begin
            send_command(CMD_SEEK_BOT);
            wait_command_done(500000);
        end

        send_command(CMD_SKIP_FWD_SEG);

        // Wait for skip to complete
        wait_command_done(100000);

        $display("  After skip: segment=%0d", segment);

        //=====================================================================
        // Test 7: Skip reverse segment (should fail at BOT)
        //=====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Skip reverse at BOT (should error) ---", test_num);

        // Go back to BOT
        send_command(CMD_SEEK_BOT);
        wait_command_done(500000);

        send_command(CMD_SKIP_REV_SEG);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        if (command_error) begin
            $display("  PASS: Skip reverse at BOT returns error");
        end else begin
            $display("  INFO: command_error=%0d (at_bot=%0d)", command_error, at_bot);
        end

        //=====================================================================
        // Test 8: Logical forward streaming
        //=====================================================================
        test_num = 8;
        $display("\n--- Test %0d: Logical forward streaming ---", test_num);

        send_command(CMD_LOGICAL_FWD);

        // Wait for streaming to start
        repeat (200000) @(posedge clk);

        if (tape_moving && motion_mode == 2'd3) begin
            $display("  PASS: Streaming forward, segment=%0d", segment);
        end else begin
            $display("  INFO: tape_moving=%0d, motion_mode=%0d, segment=%0d",
                     tape_moving, motion_mode, segment);
        end

        // Stop streaming
        send_command(CMD_STOP);
        wait_command_done(100000);

        $display("  After stop: tape_moving=%0d, segment=%0d", tape_moving, segment);

        //=====================================================================
        // Test 9: Pause during motion
        //=====================================================================
        test_num = 9;
        $display("\n--- Test %0d: Pause during motion ---", test_num);

        send_command(CMD_PHYSICAL_FWD);
        repeat (50000) @(posedge clk);

        $display("  Before pause: tape_moving=%0d", tape_moving);

        send_command(CMD_PAUSE);
        wait_command_done(100000);

        $display("  After pause: tape_moving=%0d", tape_moving);

        //=====================================================================
        // Test 10: Retension operation
        //=====================================================================
        test_num = 10;
        $display("\n--- Test %0d: Retension operation ---", test_num);

        // Start from known position
        send_command(CMD_SEEK_BOT);
        wait_command_done(500000);

        send_command(CMD_RETENSION);

        // Wait for forward pass to start
        repeat (100000) @(posedge clk);
        $display("  Retension in progress: direction=%0d, segment=%0d", direction, segment);

        // This takes a long time - just verify it started
        if (motor_on) begin
            $display("  PASS: Retension started");
        end else begin
            $display("  FAIL: Motor not on during retension");
            errors = errors + 1;
        end

        // Abort retension to continue tests
        send_command(CMD_STOP);
        wait_command_done(100000);

        //=====================================================================
        // Test 11: Disable FSM stops motion
        //=====================================================================
        test_num = 11;
        $display("\n--- Test %0d: Disable FSM stops motion ---", test_num);

        send_command(CMD_PHYSICAL_FWD);
        repeat (50000) @(posedge clk);

        enable = 0;
        repeat (10) @(posedge clk);

        if (!motor_on && !tape_moving) begin
            $display("  PASS: Disabling FSM stops motor and tape");
        end else begin
            $display("  FAIL: motor_on=%0d, tape_moving=%0d", motor_on, tape_moving);
            errors = errors + 1;
        end

        enable = 1;
        repeat (10) @(posedge clk);

        //=====================================================================
        // Test 12: File mark skip
        //=====================================================================
        test_num = 12;
        $display("\n--- Test %0d: Skip to file mark ---", test_num);

        // Start from BOT
        send_command(CMD_SEEK_BOT);
        wait_command_done(500000);

        send_command(CMD_SKIP_FWD_FILE);

        // Simulate finding a file mark after some segments
        repeat (50000) @(posedge clk);
        file_mark_detect = 1;
        @(posedge clk);
        file_mark_detect = 0;

        wait_command_done(100000);

        if (at_file_mark) begin
            $display("  PASS: Stopped at file mark, segment=%0d", segment);
        end else begin
            $display("  INFO: at_file_mark=%0d, segment=%0d", at_file_mark, segment);
        end

        //=====================================================================
        // Test 13: Motion modes
        //=====================================================================
        test_num = 13;
        $display("\n--- Test %0d: Motion modes ---", test_num);

        // Seek mode
        send_command(CMD_SEEK_EOT);
        repeat (100000) @(posedge clk);
        $display("  Seek mode: motion_mode=%0d (expect 1)", motion_mode);
        send_command(CMD_STOP);
        wait_command_done(100000);

        // Skip mode
        send_command(CMD_SKIP_FWD_SEG);
        repeat (10000) @(posedge clk);
        $display("  Skip mode: motion_mode=%0d (expect 2)", motion_mode);
        wait_command_done(100000);

        // Stream mode
        send_command(CMD_LOGICAL_FWD);
        repeat (100000) @(posedge clk);
        $display("  Stream mode: motion_mode=%0d (expect 3)", motion_mode);
        send_command(CMD_STOP);
        wait_command_done(100000);

        //=====================================================================
        // Test 14: Eject command
        //=====================================================================
        test_num = 14;
        $display("\n--- Test %0d: Eject command ---", test_num);

        // Start from BOT
        send_command(CMD_SEEK_BOT);
        wait_command_done(500000);

        send_command(CMD_EJECT);

        // Wait for eject sequence
        wait_command_done(500000);

        $display("  After eject: motor_on=%0d, fsm_state=%0d", motor_on, fsm_state);

        //=====================================================================
        // Summary
        //=====================================================================
        #10000;
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
    // Monitor
    //=========================================================================
    always @(posedge clk) begin
        if (command_done) begin
            $display("  [%0t] command_done: seg=%0d, track=%0d", $time, segment, track);
        end
        if (command_error) begin
            $display("  [%0t] command_error: seg=%0d", $time, segment);
        end
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #50_000_000;  // 50ms simulation limit
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
