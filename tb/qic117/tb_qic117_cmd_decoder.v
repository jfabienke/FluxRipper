//==============================================================================
// QIC-117 Command Decoder Testbench
//==============================================================================
// File: tb_qic117_cmd_decoder.v
// Description: Verifies command decoding for all QIC-117 command codes.
//              Tests command classification, individual command flags,
//              and validity checking.
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_cmd_decoder;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 5;  // 200 MHz = 5ns period

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;
    reg  [5:0]  pulse_count;
    reg         command_valid;

    wire [5:0]  command_code;
    wire        command_strobe;

    // Command type classification
    wire        cmd_is_reset;
    wire        cmd_is_seek;
    wire        cmd_is_skip;
    wire        cmd_is_motion;
    wire        cmd_is_status;
    wire        cmd_is_config;
    wire        cmd_is_data;
    wire        cmd_is_diagnostic;
    wire        cmd_is_valid;

    // Specific command flags
    wire        cmd_reset;
    wire        cmd_seek_bot;
    wire        cmd_seek_eot;
    wire        cmd_skip_fwd_seg;
    wire        cmd_skip_rev_seg;
    wire        cmd_skip_fwd_file;
    wire        cmd_skip_rev_file;
    wire        cmd_skip_fwd_ext;
    wire        cmd_skip_rev_ext;
    wire        cmd_physical_fwd;
    wire        cmd_physical_rev;
    wire        cmd_logical_fwd;
    wire        cmd_logical_rev;
    wire        cmd_pause;
    wire        cmd_stop;
    wire        cmd_report_status;
    wire        cmd_report_next_bit;
    wire        cmd_report_vendor;
    wire        cmd_report_model;
    wire        cmd_report_rom_ver;
    wire        cmd_report_drive_cfg;
    wire        cmd_new_cartridge;
    wire        cmd_eject;
    wire        cmd_select_rate;
    wire        cmd_phantom_select;
    wire        cmd_phantom_deselect;
    wire        cmd_read_data;
    wire        cmd_write_data;
    wire        cmd_seek_track;
    wire        cmd_seek_segment;
    wire        cmd_retension;
    wire        cmd_format_tape;
    wire        cmd_verify_fwd;
    wire        cmd_verify_rev;
    wire        cmd_set_speed;
    wire        cmd_set_format;
    wire        cmd_diagnostic;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_cmd_decoder u_dut (
        .clk(clk),
        .reset_n(reset_n),
        .pulse_count(pulse_count),
        .command_valid(command_valid),
        .command_code(command_code),
        .command_strobe(command_strobe),
        .cmd_is_reset(cmd_is_reset),
        .cmd_is_seek(cmd_is_seek),
        .cmd_is_skip(cmd_is_skip),
        .cmd_is_motion(cmd_is_motion),
        .cmd_is_status(cmd_is_status),
        .cmd_is_config(cmd_is_config),
        .cmd_is_data(cmd_is_data),
        .cmd_is_diagnostic(cmd_is_diagnostic),
        .cmd_is_valid(cmd_is_valid),
        .cmd_reset(cmd_reset),
        .cmd_seek_bot(cmd_seek_bot),
        .cmd_seek_eot(cmd_seek_eot),
        .cmd_skip_fwd_seg(cmd_skip_fwd_seg),
        .cmd_skip_rev_seg(cmd_skip_rev_seg),
        .cmd_skip_fwd_file(cmd_skip_fwd_file),
        .cmd_skip_rev_file(cmd_skip_rev_file),
        .cmd_skip_fwd_ext(cmd_skip_fwd_ext),
        .cmd_skip_rev_ext(cmd_skip_rev_ext),
        .cmd_physical_fwd(cmd_physical_fwd),
        .cmd_physical_rev(cmd_physical_rev),
        .cmd_logical_fwd(cmd_logical_fwd),
        .cmd_logical_rev(cmd_logical_rev),
        .cmd_pause(cmd_pause),
        .cmd_stop(cmd_stop),
        .cmd_report_status(cmd_report_status),
        .cmd_report_next_bit(cmd_report_next_bit),
        .cmd_report_vendor(cmd_report_vendor),
        .cmd_report_model(cmd_report_model),
        .cmd_report_rom_ver(cmd_report_rom_ver),
        .cmd_report_drive_cfg(cmd_report_drive_cfg),
        .cmd_new_cartridge(cmd_new_cartridge),
        .cmd_eject(cmd_eject),
        .cmd_select_rate(cmd_select_rate),
        .cmd_phantom_select(cmd_phantom_select),
        .cmd_phantom_deselect(cmd_phantom_deselect),
        .cmd_read_data(cmd_read_data),
        .cmd_write_data(cmd_write_data),
        .cmd_seek_track(cmd_seek_track),
        .cmd_seek_segment(cmd_seek_segment),
        .cmd_retension(cmd_retension),
        .cmd_format_tape(cmd_format_tape),
        .cmd_verify_fwd(cmd_verify_fwd),
        .cmd_verify_rev(cmd_verify_rev),
        .cmd_set_speed(cmd_set_speed),
        .cmd_set_format(cmd_set_format),
        .cmd_diagnostic(cmd_diagnostic)
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

    // Send a command with given pulse count
    task send_command;
        input [5:0] count;
        begin
            pulse_count   = count;
            command_valid = 1'b1;
            @(posedge clk);
            command_valid = 1'b0;
            @(posedge clk);
            @(posedge clk);  // Allow time for decoding
        end
    endtask

    // Check a specific command flag
    task check_flag;
        input [5:0]     cmd_num;
        input           flag_value;
        input           expected;
        input [8*32-1:0] flag_name;
        begin
            if (flag_value !== expected) begin
                $display("  FAIL: cmd=%0d, %0s=%0d (expected %0d)",
                         cmd_num, flag_name, flag_value, expected);
                errors = errors + 1;
            end
        end
    endtask

    //=========================================================================
    // Test Stimulus
    //=========================================================================
    integer errors;
    integer test_num;
    integer i;

    initial begin
        $display("============================================");
        $display("QIC-117 Command Decoder Testbench");
        $display("============================================");

        // Initialize
        reset_n       = 0;
        pulse_count   = 6'd0;
        command_valid = 0;
        errors        = 0;
        test_num      = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        //=====================================================================
        // Test 1: Reset commands (1-2)
        //=====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Reset commands ---", test_num);

        send_command(6'd1);
        check_flag(1, cmd_reset, 1, "cmd_reset");
        check_flag(1, cmd_is_reset, 1, "cmd_is_reset");
        check_flag(1, cmd_is_valid, 1, "cmd_is_valid");
        $display("  Command 1 (RESET_1): cmd_reset=%0d", cmd_reset);

        send_command(6'd2);
        check_flag(2, cmd_reset, 1, "cmd_reset");
        check_flag(2, cmd_is_reset, 1, "cmd_is_reset");
        $display("  Command 2 (RESET_2): cmd_reset=%0d", cmd_reset);

        //=====================================================================
        // Test 2: Status commands (4-5)
        //=====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Status commands ---", test_num);

        send_command(6'd4);
        check_flag(4, cmd_report_status, 1, "cmd_report_status");
        check_flag(4, cmd_is_status, 1, "cmd_is_status");
        $display("  Command 4 (REPORT_STATUS): cmd_report_status=%0d", cmd_report_status);

        send_command(6'd5);
        check_flag(5, cmd_report_next_bit, 1, "cmd_report_next_bit");
        check_flag(5, cmd_is_status, 1, "cmd_is_status");
        $display("  Command 5 (REPORT_NEXT_BIT): cmd_report_next_bit=%0d", cmd_report_next_bit);

        //=====================================================================
        // Test 3: Motion control commands (6-7)
        //=====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Motion control commands ---", test_num);

        send_command(6'd6);
        check_flag(6, cmd_pause, 1, "cmd_pause");
        check_flag(6, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 6 (PAUSE): cmd_pause=%0d", cmd_pause);

        send_command(6'd7);
        check_flag(7, cmd_pause, 1, "cmd_pause");
        check_flag(7, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 7 (MICRO_STEP_PAUSE): cmd_pause=%0d", cmd_pause);

        //=====================================================================
        // Test 4: Seek commands (8-9)
        //=====================================================================
        test_num = 4;
        $display("\n--- Test %0d: Seek commands ---", test_num);

        send_command(6'd8);
        check_flag(8, cmd_seek_bot, 1, "cmd_seek_bot");
        check_flag(8, cmd_is_seek, 1, "cmd_is_seek");
        $display("  Command 8 (SEEK_LOAD_POINT/BOT): cmd_seek_bot=%0d", cmd_seek_bot);

        send_command(6'd9);
        check_flag(9, cmd_seek_eot, 1, "cmd_seek_eot");
        check_flag(9, cmd_is_seek, 1, "cmd_is_seek");
        $display("  Command 9 (SEEK_EOT): cmd_seek_eot=%0d", cmd_seek_eot);

        //=====================================================================
        // Test 5: Skip commands (10-13)
        //=====================================================================
        test_num = 5;
        $display("\n--- Test %0d: Skip commands ---", test_num);

        send_command(6'd10);
        check_flag(10, cmd_skip_rev_seg, 1, "cmd_skip_rev_seg");
        check_flag(10, cmd_is_skip, 1, "cmd_is_skip");
        $display("  Command 10 (SKIP_REV_SEG): cmd_skip_rev_seg=%0d", cmd_skip_rev_seg);

        send_command(6'd11);
        check_flag(11, cmd_skip_rev_file, 1, "cmd_skip_rev_file");
        check_flag(11, cmd_is_skip, 1, "cmd_is_skip");
        $display("  Command 11 (SKIP_REV_FILE): cmd_skip_rev_file=%0d", cmd_skip_rev_file);

        send_command(6'd12);
        check_flag(12, cmd_skip_fwd_seg, 1, "cmd_skip_fwd_seg");
        check_flag(12, cmd_is_skip, 1, "cmd_is_skip");
        $display("  Command 12 (SKIP_FWD_SEG): cmd_skip_fwd_seg=%0d", cmd_skip_fwd_seg);

        send_command(6'd13);
        check_flag(13, cmd_skip_fwd_file, 1, "cmd_skip_fwd_file");
        check_flag(13, cmd_is_skip, 1, "cmd_is_skip");
        $display("  Command 13 (SKIP_FWD_FILE): cmd_skip_fwd_file=%0d", cmd_skip_fwd_file);

        //=====================================================================
        // Test 6: Logical motion commands (21-22)
        //=====================================================================
        test_num = 6;
        $display("\n--- Test %0d: Logical motion commands ---", test_num);

        send_command(6'd21);
        check_flag(21, cmd_logical_fwd, 1, "cmd_logical_fwd");
        check_flag(21, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 21 (LOGICAL_FWD): cmd_logical_fwd=%0d", cmd_logical_fwd);

        send_command(6'd22);
        check_flag(22, cmd_logical_rev, 1, "cmd_logical_rev");
        check_flag(22, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 22 (LOGICAL_REV): cmd_logical_rev=%0d", cmd_logical_rev);

        //=====================================================================
        // Test 7: Physical motion commands (30-31)
        //=====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Physical motion commands ---", test_num);

        send_command(6'd30);
        check_flag(30, cmd_physical_fwd, 1, "cmd_physical_fwd");
        check_flag(30, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 30 (PHYSICAL_FWD): cmd_physical_fwd=%0d", cmd_physical_fwd);

        send_command(6'd31);
        check_flag(31, cmd_physical_rev, 1, "cmd_physical_rev");
        check_flag(31, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 31 (PHYSICAL_REV): cmd_physical_rev=%0d", cmd_physical_rev);

        //=====================================================================
        // Test 8: Configuration commands (36, 45-47)
        //=====================================================================
        test_num = 8;
        $display("\n--- Test %0d: Configuration commands ---", test_num);

        send_command(6'd36);
        check_flag(36, cmd_new_cartridge, 1, "cmd_new_cartridge");
        check_flag(36, cmd_is_config, 1, "cmd_is_config");
        $display("  Command 36 (NEW_CARTRIDGE): cmd_new_cartridge=%0d", cmd_new_cartridge);

        send_command(6'd45);
        check_flag(45, cmd_select_rate, 1, "cmd_select_rate");
        check_flag(45, cmd_is_config, 1, "cmd_is_config");
        $display("  Command 45 (SELECT_RATE): cmd_select_rate=%0d", cmd_select_rate);

        send_command(6'd46);
        check_flag(46, cmd_phantom_select, 1, "cmd_phantom_select");
        check_flag(46, cmd_is_config, 1, "cmd_is_config");
        $display("  Command 46 (PHANTOM_SELECT): cmd_phantom_select=%0d", cmd_phantom_select);

        send_command(6'd47);
        check_flag(47, cmd_phantom_deselect, 1, "cmd_phantom_deselect");
        check_flag(47, cmd_is_config, 1, "cmd_is_config");
        $display("  Command 47 (PHANTOM_DESELECT): cmd_phantom_deselect=%0d", cmd_phantom_deselect);

        send_command(6'd37);
        check_flag(37, cmd_eject, 1, "cmd_eject");
        check_flag(37, cmd_is_config, 1, "cmd_is_config");
        $display("  Command 37 (EJECT): cmd_eject=%0d", cmd_eject);

        //=====================================================================
        // Test 9: Data commands (16-17)
        //=====================================================================
        test_num = 9;
        $display("\n--- Test %0d: Data commands ---", test_num);

        send_command(6'd16);
        check_flag(16, cmd_read_data, 1, "cmd_read_data");
        check_flag(16, cmd_is_data, 1, "cmd_is_data");
        $display("  Command 16 (READ_DATA): cmd_read_data=%0d", cmd_read_data);

        send_command(6'd17);
        check_flag(17, cmd_write_data, 1, "cmd_write_data");
        check_flag(17, cmd_is_data, 1, "cmd_is_data");
        $display("  Command 17 (WRITE_DATA): cmd_write_data=%0d", cmd_write_data);

        //=====================================================================
        // Test 10: Extended skip commands (14-15)
        //=====================================================================
        test_num = 10;
        $display("\n--- Test %0d: Extended skip commands ---", test_num);

        send_command(6'd14);
        check_flag(14, cmd_skip_rev_ext, 1, "cmd_skip_rev_ext");
        check_flag(14, cmd_is_skip, 1, "cmd_is_skip");
        $display("  Command 14 (SKIP_REV_EXT): cmd_skip_rev_ext=%0d", cmd_skip_rev_ext);

        send_command(6'd15);
        check_flag(15, cmd_skip_fwd_ext, 1, "cmd_skip_fwd_ext");
        check_flag(15, cmd_is_skip, 1, "cmd_is_skip");
        $display("  Command 15 (SKIP_FWD_EXT): cmd_skip_fwd_ext=%0d", cmd_skip_fwd_ext);

        //=====================================================================
        // Test 11: Seek commands (18-19)
        //=====================================================================
        test_num = 11;
        $display("\n--- Test %0d: Extended seek commands ---", test_num);

        send_command(6'd18);
        check_flag(18, cmd_seek_track, 1, "cmd_seek_track");
        check_flag(18, cmd_is_seek, 1, "cmd_is_seek");
        $display("  Command 18 (SEEK_TRACK): cmd_seek_track=%0d", cmd_seek_track);

        send_command(6'd19);
        check_flag(19, cmd_seek_segment, 1, "cmd_seek_segment");
        check_flag(19, cmd_is_seek, 1, "cmd_is_seek");
        $display("  Command 19 (SEEK_SEGMENT): cmd_seek_segment=%0d", cmd_seek_segment);

        //=====================================================================
        // Test 12: Tape maintenance commands (23-25)
        //=====================================================================
        test_num = 12;
        $display("\n--- Test %0d: Tape maintenance commands ---", test_num);

        send_command(6'd23);
        check_flag(23, cmd_stop, 1, "cmd_stop");
        check_flag(23, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 23 (STOP): cmd_stop=%0d", cmd_stop);

        send_command(6'd24);
        check_flag(24, cmd_retension, 1, "cmd_retension");
        check_flag(24, cmd_is_motion, 1, "cmd_is_motion");
        $display("  Command 24 (RETENSION): cmd_retension=%0d", cmd_retension);

        send_command(6'd25);
        check_flag(25, cmd_format_tape, 1, "cmd_format_tape");
        check_flag(25, cmd_is_diagnostic, 1, "cmd_is_diagnostic");
        $display("  Command 25 (FORMAT_TAPE): cmd_format_tape=%0d", cmd_format_tape);

        //=====================================================================
        // Test 13: Verify and diagnostic commands (26-27, 48)
        //=====================================================================
        test_num = 13;
        $display("\n--- Test %0d: Verify and diagnostic commands ---", test_num);

        send_command(6'd26);
        check_flag(26, cmd_verify_fwd, 1, "cmd_verify_fwd");
        check_flag(26, cmd_is_diagnostic, 1, "cmd_is_diagnostic");
        $display("  Command 26 (VERIFY_FWD): cmd_verify_fwd=%0d", cmd_verify_fwd);

        send_command(6'd27);
        check_flag(27, cmd_verify_rev, 1, "cmd_verify_rev");
        check_flag(27, cmd_is_diagnostic, 1, "cmd_is_diagnostic");
        $display("  Command 27 (VERIFY_REV): cmd_verify_rev=%0d", cmd_verify_rev);

        send_command(6'd48);
        check_flag(48, cmd_diagnostic, 1, "cmd_diagnostic");
        check_flag(48, cmd_is_diagnostic, 1, "cmd_is_diagnostic");
        $display("  Command 48 (DIAGNOSTIC_1): cmd_diagnostic=%0d", cmd_diagnostic);

        //=====================================================================
        // Test 14: Extended report commands (38-41)
        //=====================================================================
        test_num = 14;
        $display("\n--- Test %0d: Extended report commands ---", test_num);

        send_command(6'd38);
        check_flag(38, cmd_report_vendor, 1, "cmd_report_vendor");
        check_flag(38, cmd_is_status, 1, "cmd_is_status");
        $display("  Command 38 (REPORT_VENDOR): cmd_report_vendor=%0d", cmd_report_vendor);

        send_command(6'd39);
        check_flag(39, cmd_report_model, 1, "cmd_report_model");
        check_flag(39, cmd_is_status, 1, "cmd_is_status");
        $display("  Command 39 (REPORT_MODEL): cmd_report_model=%0d", cmd_report_model);

        send_command(6'd40);
        check_flag(40, cmd_report_rom_ver, 1, "cmd_report_rom_ver");
        check_flag(40, cmd_is_status, 1, "cmd_is_status");
        $display("  Command 40 (REPORT_ROM_VER): cmd_report_rom_ver=%0d", cmd_report_rom_ver);

        send_command(6'd41);
        check_flag(41, cmd_report_drive_cfg, 1, "cmd_report_drive_cfg");
        check_flag(41, cmd_is_status, 1, "cmd_is_status");
        $display("  Command 41 (REPORT_DRIVE_CFG): cmd_report_drive_cfg=%0d", cmd_report_drive_cfg);

        //=====================================================================
        // Test 15: Command validity range
        //=====================================================================
        test_num = 15;
        $display("\n--- Test %0d: Command validity range ---", test_num);

        // Test command 0 (invalid)
        send_command(6'd0);
        check_flag(0, cmd_is_valid, 0, "cmd_is_valid");
        $display("  Command 0: cmd_is_valid=%0d (expected 0)", cmd_is_valid);

        // Test command 48 (valid - diagnostic)
        send_command(6'd48);
        check_flag(48, cmd_is_valid, 1, "cmd_is_valid");
        $display("  Command 48: cmd_is_valid=%0d (expected 1)", cmd_is_valid);

        // Test command 49 (invalid - out of range)
        send_command(6'd49);
        check_flag(49, cmd_is_valid, 0, "cmd_is_valid");
        $display("  Command 49: cmd_is_valid=%0d (expected 0)", cmd_is_valid);

        // Test command 63 (invalid - max value)
        send_command(6'd63);
        check_flag(63, cmd_is_valid, 0, "cmd_is_valid");
        $display("  Command 63: cmd_is_valid=%0d (expected 0)", cmd_is_valid);

        //=====================================================================
        // Test 16: Command strobe is single-cycle
        //=====================================================================
        test_num = 16;
        $display("\n--- Test %0d: Command strobe pulse width ---", test_num);

        begin : check_strobe_width
            integer strobe_cycles;
            strobe_cycles = 0;

            pulse_count   = 6'd8;
            command_valid = 1'b1;
            @(posedge clk);
            command_valid = 1'b0;

            repeat (10) begin
                @(posedge clk);
                if (command_strobe) strobe_cycles = strobe_cycles + 1;
            end

            if (strobe_cycles == 1) begin
                $display("  PASS: command_strobe is single-cycle pulse");
            end else begin
                $display("  FAIL: command_strobe high for %0d cycles (expected 1)",
                         strobe_cycles);
                errors = errors + 1;
            end
        end

        //=====================================================================
        // Test 17: Mutual exclusivity of command flags
        //=====================================================================
        test_num = 17;
        $display("\n--- Test %0d: Mutual exclusivity of flags ---", test_num);

        // cmd_seek_bot should not trigger skip flags
        send_command(6'd8);
        check_flag(8, cmd_skip_fwd_seg, 0, "cmd_skip_fwd_seg");
        check_flag(8, cmd_skip_rev_seg, 0, "cmd_skip_rev_seg");
        check_flag(8, cmd_reset, 0, "cmd_reset");
        $display("  Command 8: only cmd_seek_bot set (no other flags)");

        // cmd_reset should not trigger motion flags
        send_command(6'd1);
        check_flag(1, cmd_is_motion, 0, "cmd_is_motion");
        check_flag(1, cmd_is_seek, 0, "cmd_is_seek");
        check_flag(1, cmd_is_skip, 0, "cmd_is_skip");
        $display("  Command 1: only cmd_reset set (no motion/seek/skip)");

        //=====================================================================
        // Test 18: All valid commands 1-48
        //=====================================================================
        test_num = 18;
        $display("\n--- Test %0d: All valid commands (1-48) ---", test_num);

        for (i = 1; i <= 48; i = i + 1) begin
            send_command(i[5:0]);
            if (!cmd_is_valid) begin
                $display("  FAIL: Command %0d reported as invalid", i);
                errors = errors + 1;
            end
            if (command_code != i[5:0]) begin
                $display("  FAIL: Command %0d latched as %0d", i, command_code);
                errors = errors + 1;
            end
        end
        $display("  Verified all 48 commands are valid and latch correctly");

        //=====================================================================
        // Test 19: Reset behavior
        //=====================================================================
        test_num = 19;
        $display("\n--- Test %0d: Reset clears command_code ---", test_num);

        send_command(6'd30);
        if (command_code != 6'd30) begin
            $display("  FAIL: Command not latched before reset");
            errors = errors + 1;
        end

        reset_n = 0;
        @(posedge clk);
        @(posedge clk);
        reset_n = 1;
        @(posedge clk);

        if (command_code == 6'd0) begin
            $display("  PASS: command_code cleared to 0 after reset");
        end else begin
            $display("  FAIL: command_code=%0d after reset (expected 0)", command_code);
            errors = errors + 1;
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
    // Monitor - Display command changes
    //=========================================================================
    always @(posedge clk) begin
        if (command_strobe) begin
            $display("  [%0t] command_strobe: code=%0d", $time, command_code);
        end
    end

    //=========================================================================
    // Timeout watchdog
    //=========================================================================
    initial begin
        #1_000_000;  // 1ms simulation limit
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
