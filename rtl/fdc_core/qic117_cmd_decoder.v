//==============================================================================
// QIC-117 Command Decoder
//==============================================================================
// File: qic117_cmd_decoder.v
// Description: Decodes QIC-117 command codes from STEP pulse counts.
//              QIC tape drives encode commands as the number of STEP pulses
//              received within a timeout window.
//
// QIC-117 Protocol:
//   - Host sends N STEP pulses (1-48)
//   - After timeout (~100ms with no STEP), pulse count = command code
//   - Drive executes command and reports status via TRK0/INDEX
//
// Reference: QIC-117 Revision G (floppy tape interface standard)
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_cmd_decoder (
    input  wire        clk,
    input  wire        reset_n,

    // Command input
    input  wire [5:0]  pulse_count,       // Number of STEP pulses received
    input  wire        command_valid,     // Pulse when command ready

    // Decoded command outputs
    output reg  [5:0]  command_code,      // Latched command code
    output reg         command_strobe,    // Single-cycle pulse on new command

    // Command type classification
    output wire        cmd_is_reset,
    output wire        cmd_is_seek,
    output wire        cmd_is_skip,
    output wire        cmd_is_motion,
    output wire        cmd_is_status,
    output wire        cmd_is_config,
    output wire        cmd_is_valid,

    // Specific command flags (active high when command matches)
    output wire        cmd_reset,
    output wire        cmd_seek_bot,
    output wire        cmd_seek_eot,
    output wire        cmd_skip_fwd_seg,
    output wire        cmd_skip_rev_seg,
    output wire        cmd_skip_fwd_file,
    output wire        cmd_skip_rev_file,
    output wire        cmd_physical_fwd,
    output wire        cmd_physical_rev,
    output wire        cmd_logical_fwd,
    output wire        cmd_logical_rev,
    output wire        cmd_pause,
    output wire        cmd_report_status,
    output wire        cmd_report_next_bit,
    output wire        cmd_new_cartridge,
    output wire        cmd_select_rate,
    output wire        cmd_phantom_select,
    output wire        cmd_phantom_deselect
);

    //=========================================================================
    // QIC-117 Command Code Definitions
    //=========================================================================
    // Commands are encoded as STEP pulse counts (1-48)

    // Reset Commands
    localparam [5:0] QIC_RESET_1            = 6'd1;   // Soft reset
    localparam [5:0] QIC_RESET_2            = 6'd2;   // Hard reset

    // Status Commands
    localparam [5:0] QIC_REPORT_STATUS      = 6'd4;   // Report drive status
    localparam [5:0] QIC_REPORT_NEXT_BIT    = 6'd5;   // Report next status bit

    // Motion Control
    localparam [5:0] QIC_PAUSE              = 6'd6;   // Pause tape motion
    localparam [5:0] QIC_MICRO_STEP_PAUSE   = 6'd7;   // Micro-step pause

    // Seek Commands
    localparam [5:0] QIC_SEEK_LOAD_POINT    = 6'd8;   // Seek to BOT (beginning of tape)
    localparam [5:0] QIC_SEEK_EOT           = 6'd9;   // Seek to EOT (end of tape)

    // Skip Commands
    localparam [5:0] QIC_SKIP_REV_SEG       = 6'd10;  // Skip 1 segment reverse
    localparam [5:0] QIC_SKIP_REV_FILE      = 6'd11;  // Skip to previous file mark
    localparam [5:0] QIC_SKIP_FWD_SEG       = 6'd12;  // Skip 1 segment forward
    localparam [5:0] QIC_SKIP_FWD_FILE      = 6'd13;  // Skip to next file mark

    // Extended Skip (with count parameter)
    localparam [5:0] QIC_SKIP_REV_EXT       = 6'd14;  // Skip N segments reverse
    localparam [5:0] QIC_SKIP_FWD_EXT       = 6'd15;  // Skip N segments forward

    // Read/Write Commands
    localparam [5:0] QIC_READ_DATA          = 6'd16;  // Start reading data
    localparam [5:0] QIC_WRITE_DATA         = 6'd17;  // Start writing data

    // Position Commands
    localparam [5:0] QIC_SEEK_TRACK         = 6'd18;  // Seek to track N
    localparam [5:0] QIC_SEEK_SEGMENT       = 6'd19;  // Seek to segment N

    // Logical Motion
    localparam [5:0] QIC_LOGICAL_FWD        = 6'd21;  // Enter logical forward mode
    localparam [5:0] QIC_LOGICAL_REV        = 6'd22;  // Enter logical reverse mode
    localparam [5:0] QIC_STOP_TAPE          = 6'd23;  // Stop tape motion

    // Retension/Format
    localparam [5:0] QIC_RETENSION          = 6'd24;  // Retension tape
    localparam [5:0] QIC_FORMAT_TAPE        = 6'd25;  // Format tape (low-level)

    // Diagnostic Commands
    localparam [5:0] QIC_VERIFY_FWD         = 6'd26;  // Verify forward
    localparam [5:0] QIC_VERIFY_REV         = 6'd27;  // Verify reverse

    // Physical Motion
    localparam [5:0] QIC_PHYSICAL_FWD       = 6'd30;  // Physical forward motion
    localparam [5:0] QIC_PHYSICAL_REV       = 6'd31;  // Physical reverse motion

    // Configuration Commands
    localparam [5:0] QIC_SET_SPEED          = 6'd32;  // Set tape speed
    localparam [5:0] QIC_SET_FORMAT         = 6'd33;  // Set format type

    // Cartridge Commands
    localparam [5:0] QIC_NEW_CARTRIDGE      = 6'd36;  // New cartridge inserted
    localparam [5:0] QIC_EJECT              = 6'd37;  // Eject cartridge

    // Report Commands
    localparam [5:0] QIC_REPORT_VENDOR      = 6'd38;  // Report vendor ID
    localparam [5:0] QIC_REPORT_MODEL       = 6'd39;  // Report model ID
    localparam [5:0] QIC_REPORT_ROM_VER     = 6'd40;  // Report ROM version
    localparam [5:0] QIC_REPORT_DRIVE_CFG   = 6'd41;  // Report drive config

    // Rate Selection
    localparam [5:0] QIC_SELECT_RATE        = 6'd45;  // Select data rate

    // Phantom Select/Deselect
    localparam [5:0] QIC_PHANTOM_SELECT     = 6'd46;  // Enable drive (phantom select)
    localparam [5:0] QIC_PHANTOM_DESELECT   = 6'd47;  // Disable drive

    // Reserved
    localparam [5:0] QIC_DIAGNOSTIC_1       = 6'd48;  // Diagnostic command 1

    //=========================================================================
    // Command Latching
    //=========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            command_code   <= 6'd0;
            command_strobe <= 1'b0;
        end else begin
            command_strobe <= 1'b0;  // Default: single-cycle pulse

            if (command_valid) begin
                command_code   <= pulse_count;
                command_strobe <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Command Validity Check
    //=========================================================================
    // Valid commands are 1-48, but not all codes are defined

    assign cmd_is_valid = (command_code >= 6'd1) && (command_code <= 6'd48);

    //=========================================================================
    // Individual Command Matching
    //=========================================================================

    // Reset
    assign cmd_reset            = (command_code == QIC_RESET_1) ||
                                  (command_code == QIC_RESET_2);

    // Seek
    assign cmd_seek_bot         = (command_code == QIC_SEEK_LOAD_POINT);
    assign cmd_seek_eot         = (command_code == QIC_SEEK_EOT);

    // Skip
    assign cmd_skip_fwd_seg     = (command_code == QIC_SKIP_FWD_SEG);
    assign cmd_skip_rev_seg     = (command_code == QIC_SKIP_REV_SEG);
    assign cmd_skip_fwd_file    = (command_code == QIC_SKIP_FWD_FILE);
    assign cmd_skip_rev_file    = (command_code == QIC_SKIP_REV_FILE);

    // Physical Motion
    assign cmd_physical_fwd     = (command_code == QIC_PHYSICAL_FWD);
    assign cmd_physical_rev     = (command_code == QIC_PHYSICAL_REV);

    // Logical Motion
    assign cmd_logical_fwd      = (command_code == QIC_LOGICAL_FWD);
    assign cmd_logical_rev      = (command_code == QIC_LOGICAL_REV);

    // Control
    assign cmd_pause            = (command_code == QIC_PAUSE) ||
                                  (command_code == QIC_MICRO_STEP_PAUSE);

    // Status
    assign cmd_report_status    = (command_code == QIC_REPORT_STATUS);
    assign cmd_report_next_bit  = (command_code == QIC_REPORT_NEXT_BIT);

    // Configuration
    assign cmd_new_cartridge    = (command_code == QIC_NEW_CARTRIDGE);
    assign cmd_select_rate      = (command_code == QIC_SELECT_RATE);
    assign cmd_phantom_select   = (command_code == QIC_PHANTOM_SELECT);
    assign cmd_phantom_deselect = (command_code == QIC_PHANTOM_DESELECT);

    //=========================================================================
    // Command Type Classification
    //=========================================================================

    assign cmd_is_reset = cmd_reset;

    assign cmd_is_seek = cmd_seek_bot || cmd_seek_eot ||
                         (command_code == QIC_SEEK_TRACK) ||
                         (command_code == QIC_SEEK_SEGMENT);

    assign cmd_is_skip = cmd_skip_fwd_seg || cmd_skip_rev_seg ||
                         cmd_skip_fwd_file || cmd_skip_rev_file ||
                         (command_code == QIC_SKIP_FWD_EXT) ||
                         (command_code == QIC_SKIP_REV_EXT);

    assign cmd_is_motion = cmd_physical_fwd || cmd_physical_rev ||
                           cmd_logical_fwd || cmd_logical_rev ||
                           cmd_pause ||
                           (command_code == QIC_STOP_TAPE) ||
                           (command_code == QIC_RETENSION);

    assign cmd_is_status = cmd_report_status || cmd_report_next_bit ||
                           (command_code == QIC_REPORT_VENDOR) ||
                           (command_code == QIC_REPORT_MODEL) ||
                           (command_code == QIC_REPORT_ROM_VER) ||
                           (command_code == QIC_REPORT_DRIVE_CFG);

    assign cmd_is_config = cmd_new_cartridge || cmd_select_rate ||
                           cmd_phantom_select || cmd_phantom_deselect ||
                           (command_code == QIC_SET_SPEED) ||
                           (command_code == QIC_SET_FORMAT);

endmodule
