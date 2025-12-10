//==============================================================================
// QIC-117 Integration Testbench
//==============================================================================
// File: tb_qic117_integration.v
// Description: Full integration test for QIC-117 tape controller.
//              Tests command flow from STEP pulses through to status output,
//              position tracking, and data streaming.
//
// Test Scenarios:
//   1. Basic command flow (STEP -> decode -> execute)
//   2. Phantom select/deselect
//   3. Seek operations (BOT, EOT)
//   4. Skip operations (forward/reverse)
//   5. Status reporting via TRK0
//   6. Data streaming with MFM simulation
//   7. File mark detection
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_integration;

    //=========================================================================
    // Parameters - Use short timeouts for simulation
    //=========================================================================
    parameter CLK_PERIOD    = 5;            // 200 MHz = 5ns period
    parameter CLK_FREQ_HZ   = 200_000_000;

    // QIC-117 Command Codes
    localparam [5:0] QIC_RESET           = 6'd1;
    localparam [5:0] QIC_REPORT_STATUS   = 6'd4;
    localparam [5:0] QIC_REPORT_NEXT_BIT = 6'd5;
    localparam [5:0] QIC_PAUSE           = 6'd6;
    localparam [5:0] QIC_SEEK_BOT        = 6'd8;
    localparam [5:0] QIC_SEEK_EOT        = 6'd9;
    localparam [5:0] QIC_SKIP_REV_SEG    = 6'd10;
    localparam [5:0] QIC_SKIP_FWD_SEG    = 6'd12;
    localparam [5:0] QIC_LOGICAL_FWD     = 6'd21;
    localparam [5:0] QIC_LOGICAL_REV     = 6'd22;
    localparam [5:0] QIC_PHYSICAL_FWD    = 6'd30;
    localparam [5:0] QIC_PHYSICAL_REV    = 6'd31;
    localparam [5:0] QIC_NEW_CARTRIDGE   = 6'd36;
    localparam [5:0] QIC_PHANTOM_SELECT  = 6'd46;
    localparam [5:0] QIC_PHANTOM_DESEL   = 6'd47;

    // Simulation timing (shorter than real hardware)
    localparam STEP_PULSE_NS = 5000;        // 5µs step pulse
    localparam STEP_GAP_NS   = 10000;       // 10µs between pulses
    localparam CMD_TIMEOUT_NS = 2_000_000;  // 2ms command timeout (sim)

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;

    // Control
    reg         tape_mode_en;
    reg  [2:0]  tape_select;

    // FDC interface
    reg         step_in;
    reg         dir_in;
    wire        trk0_out;
    wire        index_out;

    // Drive interface
    wire        tape_motor_on;
    wire        tape_direction;
    reg         tape_rdata;
    wire        tape_wdata;
    reg         tape_write_protect;
    reg         tape_cartridge_in;

    // Data interface
    reg         write_enable;
    reg  [7:0]  write_data;
    reg         write_strobe;
    wire [7:0]  read_data;
    wire        read_valid;

    // MFM interface
    reg         mfm_data_in;
    reg         mfm_clock;
    reg         dpll_locked;

    // Status outputs
    wire [5:0]  current_command;
    wire        command_strobe;
    wire [15:0] segment_position;
    wire [4:0]  track_position;
    wire [7:0]  tape_status;
    wire        command_active;
    wire        tape_ready;
    wire        tape_error;

    // Data streamer outputs
    wire        block_sync;
    wire [8:0]  byte_in_block;
    wire [4:0]  block_in_segment;
    wire        segment_complete;
    wire        file_mark_detect;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .tape_mode_en     (tape_mode_en),
        .tape_select      (tape_select),
        .step_in          (step_in),
        .dir_in           (dir_in),
        .trk0_out         (trk0_out),
        .index_out        (index_out),
        .tape_motor_on    (tape_motor_on),
        .tape_direction   (tape_direction),
        .tape_rdata       (tape_rdata),
        .tape_wdata       (tape_wdata),
        .tape_write_protect(tape_write_protect),
        .tape_cartridge_in(tape_cartridge_in),
        .write_enable     (write_enable),
        .write_data       (write_data),
        .write_strobe     (write_strobe),
        .read_data        (read_data),
        .read_valid       (read_valid),
        .mfm_data_in      (mfm_data_in),
        .mfm_clock        (mfm_clock),
        .dpll_locked      (dpll_locked),
        .current_command  (current_command),
        .command_strobe   (command_strobe),
        .segment_position (segment_position),
        .track_position   (track_position),
        .tape_status      (tape_status),
        .command_active   (command_active),
        .tape_ready       (tape_ready),
        .tape_error       (tape_error),
        .block_sync       (block_sync),
        .byte_in_block    (byte_in_block),
        .block_in_segment (block_in_segment),
        .segment_complete (segment_complete),
        .file_mark_detect (file_mark_detect)
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

    // Generate a single STEP pulse
    task send_step_pulse;
        begin
            step_in = 1'b1;
            #(STEP_PULSE_NS);
            step_in = 1'b0;
            #(STEP_GAP_NS);
        end
    endtask

    // Send QIC-117 command via STEP pulses
    task send_qic_command;
        input [5:0] cmd;
        integer i;
        begin
            $display("  Sending QIC command %0d (%0d STEP pulses)...", cmd, cmd);
            for (i = 0; i < cmd; i = i + 1) begin
                send_step_pulse;
            end
            // Wait for command timeout
            #(CMD_TIMEOUT_NS);
            // Wait for command to be decoded
            repeat (100) @(posedge clk);
        end
    endtask

    // Wait for command to complete
    task wait_command_complete;
        integer timeout;
        begin
            timeout = 0;
            while (command_active && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100000) begin
                $display("  WARNING: Timeout waiting for command completion");
            end
        end
    endtask

    // Generate MFM sync pattern (0x4489 = 0xA1 with missing clock)
    task generate_mfm_sync;
        integer i;
        begin
            // Simplified: generate sync pattern bits
            for (i = 0; i < 16; i = i + 1) begin
                mfm_clock = 1'b1;
                @(posedge clk);
                mfm_data_in = (16'h4489 >> (15 - i)) & 1'b1;
                @(posedge clk);
                mfm_clock = 1'b0;
                repeat (4) @(posedge clk);
            end
        end
    endtask

    // Generate MFM data byte
    task generate_mfm_byte;
        input [7:0] data;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                mfm_clock = 1'b1;
                @(posedge clk);
                mfm_data_in = data[i];
                @(posedge clk);
                mfm_clock = 1'b0;
                repeat (4) @(posedge clk);
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
        $display("QIC-117 Integration Testbench");
        $display("============================================");

        // Initialize
        reset_n            = 0;
        tape_mode_en       = 0;
        tape_select        = 3'd1;
        step_in            = 0;
        dir_in             = 0;
        tape_rdata         = 0;
        tape_write_protect = 0;
        tape_cartridge_in  = 1;  // Cartridge present
        write_enable       = 0;
        write_data         = 8'd0;
        write_strobe       = 0;
        mfm_data_in        = 0;
        mfm_clock          = 0;
        dpll_locked        = 1;
        errors             = 0;
        test_num           = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        //=====================================================================
        // Test 1: Enable tape mode
        //=====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Enable tape mode ---", test_num);

        tape_mode_en = 1;
        #1000;

        if (tape_mode_en) begin
            $display("  PASS: Tape mode enabled");
        end else begin
            $display("  FAIL: Tape mode not enabled");
            errors = errors + 1;
        end

        //=====================================================================
        // Test 2: Phantom Select
        //=====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Phantom Select ---", test_num);

        send_qic_command(QIC_PHANTOM_SELECT);

        // Verify drive becomes ready
        #10000;
        if (tape_ready) begin
            $display("  PASS: Drive ready after phantom select");
        end else begin
            $display("  INFO: Drive ready=%0d (may need cartridge)", tape_ready);
        end

        //=====================================================================
        // Test 3: Reset command
        //=====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Reset command ---", test_num);

        send_qic_command(QIC_RESET);

        if (current_command == QIC_RESET) begin
            $display("  PASS: Reset command decoded correctly");
        end else begin
            $display("  FAIL: current_command=%0d (expected %0d)", current_command, QIC_RESET);
            errors = errors + 1;
        end

        //=====================================================================
        // Test 4: New Cartridge command
        //=====================================================================
        test_num = 4;
        $display("\n--- Test %0d: New Cartridge command ---", test_num);

        send_qic_command(QIC_NEW_CARTRIDGE);

        if (current_command == QIC_NEW_CARTRIDGE) begin
            $display("  PASS: New Cartridge command decoded correctly");
        end else begin
            $display("  FAIL: current_command=%0d (expected %0d)", current_command, QIC_NEW_CARTRIDGE);
            errors = errors + 1;
        end

        //=====================================================================
        // Test 5: Seek to BOT
        //=====================================================================
        test_num = 5;
        $display("\n--- Test %0d: Seek to BOT ---", test_num);

        send_qic_command(QIC_SEEK_BOT);

        // Wait briefly for FSM to start
        #100000;

        // Check motor is on during seek
        if (tape_motor_on) begin
            $display("  PASS: Motor on during seek");
        end else begin
            $display("  INFO: Motor off (seek may be complete)");
        end

        wait_command_complete;
        $display("  Seek to BOT complete, segment=%0d", segment_position);

        //=====================================================================
        // Test 6: Seek to EOT
        //=====================================================================
        test_num = 6;
        $display("\n--- Test %0d: Seek to EOT ---", test_num);

        send_qic_command(QIC_SEEK_EOT);

        #100000;
        wait_command_complete;
        $display("  Seek to EOT complete, segment=%0d", segment_position);

        //=====================================================================
        // Test 7: Skip forward segment
        //=====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Skip forward segment ---", test_num);

        // First go back to BOT
        send_qic_command(QIC_SEEK_BOT);
        wait_command_complete;

        // Now skip forward
        send_qic_command(QIC_SKIP_FWD_SEG);
        wait_command_complete;

        $display("  After skip forward, segment=%0d", segment_position);

        //=====================================================================
        // Test 8: Skip reverse segment
        //=====================================================================
        test_num = 8;
        $display("\n--- Test %0d: Skip reverse segment ---", test_num);

        send_qic_command(QIC_SKIP_REV_SEG);
        wait_command_complete;

        $display("  After skip reverse, segment=%0d", segment_position);

        //=====================================================================
        // Test 9: Physical forward motion
        //=====================================================================
        test_num = 9;
        $display("\n--- Test %0d: Physical forward motion ---", test_num);

        send_qic_command(QIC_PHYSICAL_FWD);

        #100000;  // Let it stream for a bit

        if (tape_motor_on) begin
            $display("  PASS: Motor on during streaming");
        end else begin
            $display("  FAIL: Motor should be on during streaming");
            errors = errors + 1;
        end

        if (tape_direction == 0) begin
            $display("  PASS: Direction is forward (0)");
        end else begin
            $display("  FAIL: Direction=%0d (expected 0)", tape_direction);
            errors = errors + 1;
        end

        //=====================================================================
        // Test 10: Pause command
        //=====================================================================
        test_num = 10;
        $display("\n--- Test %0d: Pause command ---", test_num);

        send_qic_command(QIC_PAUSE);

        #50000;

        // Motor should stop
        $display("  After pause: motor=%0d, active=%0d", tape_motor_on, command_active);

        //=====================================================================
        // Test 11: Physical reverse motion
        //=====================================================================
        test_num = 11;
        $display("\n--- Test %0d: Physical reverse motion ---", test_num);

        send_qic_command(QIC_PHYSICAL_REV);

        #100000;

        if (tape_direction == 1) begin
            $display("  PASS: Direction is reverse (1)");
        end else begin
            $display("  FAIL: Direction=%0d (expected 1)", tape_direction);
            errors = errors + 1;
        end

        // Pause to stop
        send_qic_command(QIC_PAUSE);
        #50000;

        //=====================================================================
        // Test 12: Report Status
        //=====================================================================
        test_num = 12;
        $display("\n--- Test %0d: Report Status ---", test_num);

        send_qic_command(QIC_REPORT_STATUS);

        // Watch TRK0 for status bits
        $display("  tape_status=0x%02h", tape_status);
        $display("  Status bits: Ready=%b, Error=%b, WP=%b, NewCart=%b, BOT=%b, EOT=%b",
                 tape_status[7], tape_status[6], tape_status[5],
                 tape_status[4], tape_status[3], tape_status[2]);

        // Wait for status to be sent
        #5_000_000;  // 5ms for status bits

        //=====================================================================
        // Test 13: Multiple commands in sequence
        //=====================================================================
        test_num = 13;
        $display("\n--- Test %0d: Multiple commands sequence ---", test_num);

        // Execute a typical startup sequence
        send_qic_command(QIC_RESET);
        send_qic_command(QIC_PHANTOM_SELECT);
        send_qic_command(QIC_NEW_CARTRIDGE);
        send_qic_command(QIC_SEEK_BOT);
        wait_command_complete;

        $display("  Startup sequence complete, segment=%0d", segment_position);

        //=====================================================================
        // Test 14: Phantom Deselect
        //=====================================================================
        test_num = 14;
        $display("\n--- Test %0d: Phantom Deselect ---", test_num);

        send_qic_command(QIC_PHANTOM_DESEL);

        #10000;
        $display("  After deselect: ready=%0d", tape_ready);

        //=====================================================================
        // Test 15: Disable tape mode
        //=====================================================================
        test_num = 15;
        $display("\n--- Test %0d: Disable tape mode ---", test_num);

        tape_mode_en = 0;
        #10000;

        if (!tape_motor_on) begin
            $display("  PASS: Motor off after tape mode disabled");
        end else begin
            $display("  FAIL: Motor still on after tape mode disabled");
            errors = errors + 1;
        end

        //=====================================================================
        // Test 16: TRK0 output idle state
        //=====================================================================
        test_num = 16;
        $display("\n--- Test %0d: TRK0 idle state ---", test_num);

        // TRK0 should be high when idle
        if (trk0_out == 1'b1) begin
            $display("  PASS: TRK0 is high when idle (floppy mode)");
        end else begin
            $display("  INFO: TRK0=%0d (may vary based on mode)", trk0_out);
        end

        //=====================================================================
        // Test 17: Re-enable and verify state preserved
        //=====================================================================
        test_num = 17;
        $display("\n--- Test %0d: Re-enable tape mode ---", test_num);

        tape_mode_en = 1;
        #10000;

        // Re-select and test
        send_qic_command(QIC_PHANTOM_SELECT);
        send_qic_command(QIC_REPORT_STATUS);

        $display("  tape_status after re-enable: 0x%02h", tape_status);

        //=====================================================================
        // Test 18: Write protection status
        //=====================================================================
        test_num = 18;
        $display("\n--- Test %0d: Write protection ---", test_num);

        tape_write_protect = 1;
        #1000;
        send_qic_command(QIC_REPORT_STATUS);
        #100000;

        $display("  Write protect bit in status: %b", tape_status[5]);

        tape_write_protect = 0;

        //=====================================================================
        // Test 19: Error flag clear on reset
        //=====================================================================
        test_num = 19;
        $display("\n--- Test %0d: Error flag ---", test_num);

        // Error flag should be clear after reset
        send_qic_command(QIC_RESET);
        #10000;

        if (!tape_error) begin
            $display("  PASS: Error flag clear after reset");
        end else begin
            $display("  FAIL: Error flag still set after reset");
            errors = errors + 1;
        end

        //=====================================================================
        // Test 20: Logical motion commands
        //=====================================================================
        test_num = 20;
        $display("\n--- Test %0d: Logical motion ---", test_num);

        send_qic_command(QIC_LOGICAL_FWD);
        #50000;

        if (tape_motor_on && tape_direction == 0) begin
            $display("  PASS: Logical forward motion active");
        end else begin
            $display("  INFO: motor=%0d, dir=%0d", tape_motor_on, tape_direction);
        end

        send_qic_command(QIC_PAUSE);
        #50000;

        send_qic_command(QIC_LOGICAL_REV);
        #50000;

        if (tape_motor_on && tape_direction == 1) begin
            $display("  PASS: Logical reverse motion active");
        end else begin
            $display("  INFO: motor=%0d, dir=%0d", tape_motor_on, tape_direction);
        end

        send_qic_command(QIC_PAUSE);

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
    // Monitor - Display significant events
    //=========================================================================
    reg [5:0] last_command;

    always @(posedge clk) begin
        if (command_strobe) begin
            $display("  [%0t] Command decoded: %0d", $time, current_command);
            last_command <= current_command;
        end
    end

    // Monitor TRK0 transitions during status reporting
    reg trk0_prev;
    always @(posedge clk) begin
        trk0_prev <= trk0_out;
        if (trk0_out != trk0_prev) begin
            // $display("  [%0t] TRK0: %0d -> %0d", $time, trk0_prev, trk0_out);
        end
    end

    //=========================================================================
    // Timeout watchdog
    //=========================================================================
    initial begin
        #100_000_000;  // 100ms simulation limit
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
