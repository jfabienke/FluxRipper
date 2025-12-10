//==============================================================================
// QIC-117 Tape Controller
//==============================================================================
// File: qic117_controller.v
// Description: Main QIC-117 floppy-interface tape drive controller.
//              Intercepts FDC signals when in tape mode and implements
//              QIC-117 command protocol for controlling tape drives.
//
// Features:
//   - STEP pulse command decoding (1-48 pulses = command codes)
//   - TRK0 status bit encoding (via qic117_status_encoder)
//   - INDEX pulse generation at segment boundaries
//   - Position tracking via qic117_tape_fsm
//   - Block/segment detection via qic117_data_streamer
//   - Support for QIC-40/80/3010/3020 drives
//
// Signal Reinterpretation (Tape Mode):
//   STEP  -> Command bits (count of pulses = command)
//   DIR   -> Unused (tape handles direction internally)
//   TRK0  -> Status bit stream output (time-encoded)
//   INDEX -> Segment boundary marker
//   RDATA -> MFM data from tape
//   WDATA -> MFM data to tape
//
// Submodules:
//   - qic117_step_counter   : STEP pulse counting with timeout
//   - qic117_cmd_decoder    : Command code decoding
//   - qic117_status_encoder : TRK0 status bit encoding
//   - qic117_tape_fsm       : Position tracking state machine
//   - qic117_data_streamer  : Block boundary detection
//   - qic117_drive_detect   : Automatic drive detection
//   - qic117_trk0_decoder   : TRK0 response capture
//
// Reference: QIC-117 Revision G
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_controller #(
    parameter CLK_FREQ_HZ = 200_000_000   // 200 MHz FDC clock
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Mode Control (from TDR register)
    //=========================================================================
    input  wire        tape_mode_en,      // 1 = tape mode, 0 = floppy mode
    input  wire [2:0]  tape_select,       // Tape drive select (1-3)

    //=========================================================================
    // FDC Interface (directly intercept these in tape mode)
    //=========================================================================
    input  wire        step_in,           // STEP from FDC command FSM
    input  wire        dir_in,            // DIR from FDC (unused in tape mode)
    output wire        trk0_out,          // TRK0 to FDC (status bits)
    output wire        index_out,         // INDEX to FDC (segment markers)

    //=========================================================================
    // Drive Interface (directly control tape drive)
    //=========================================================================
    output reg         tape_motor_on,     // Motor control
    output wire        tape_direction,    // Direction to drive (0=fwd, 1=rev)
    input  wire        tape_rdata,        // MFM read data from tape
    output wire        tape_wdata,        // MFM write data to tape
    input  wire        tape_write_protect,// Write protect sensor
    input  wire        tape_cartridge_in, // Cartridge present sensor

    //=========================================================================
    // Data Interface
    //=========================================================================
    input  wire        write_enable,      // Enable write operations
    input  wire [7:0]  write_data,        // Data to write
    input  wire        write_strobe,      // Write data strobe
    output wire [7:0]  read_data,         // Data read from tape
    output wire        read_valid,        // Read data valid

    //=========================================================================
    // MFM Data Interface (from/to DPLL)
    //=========================================================================
    input  wire        mfm_data_in,       // Decoded MFM data from DPLL
    input  wire        mfm_clock,         // MFM data clock
    input  wire        dpll_locked,       // DPLL lock status

    //=========================================================================
    // Status and Debug
    //=========================================================================
    output wire [5:0]  current_command,   // Last decoded command
    output wire        command_strobe,    // Pulse when command decoded
    output wire [15:0] segment_position,  // Current segment number
    output wire [4:0]  track_position,    // Current track number
    output wire [7:0]  tape_status,       // Status register
    output wire        command_active,    // Command in progress
    output wire        tape_ready,        // Drive ready
    output wire        tape_error,        // Error condition

    //=========================================================================
    // Data Streamer Status
    //=========================================================================
    output wire        block_sync,        // Block sync detected
    output wire [8:0]  byte_in_block,     // Byte position in current block
    output wire [4:0]  block_in_segment,  // Block number in segment
    output wire        segment_complete,  // Segment complete pulse
    output wire        file_mark_detect,  // File mark detected

    //=========================================================================
    // Drive Detection Control
    //=========================================================================
    input  wire        start_detect,      // Start auto-detection
    input  wire        abort_detect,      // Abort detection

    //=========================================================================
    // Drive Detection Results
    //=========================================================================
    output wire        detect_complete,   // Detection finished
    output wire        detect_error,      // Detection failed
    output wire        detect_in_progress,// Detection running
    output wire        drive_detected,    // Drive present and responding
    output wire [7:0]  detected_vendor,   // Vendor ID
    output wire [7:0]  detected_model,    // Model ID
    output wire [7:0]  detected_config,   // Drive configuration
    output wire [3:0]  detected_type,     // Drive type enum
    output wire [4:0]  detected_max_tracks,// Max tracks supported
    output wire [1:0]  detected_rates     // Supported data rates
);

    //=========================================================================
    // Internal Signals
    //=========================================================================

    // Step counter outputs
    wire [5:0]  pulse_count;
    wire        count_valid;
    wire [5:0]  latched_command;
    wire        counting;
    wire        timeout_pending;

    // Command decoder outputs
    wire [5:0]  decoded_command;
    wire        cmd_strobe;
    wire        cmd_is_reset;
    wire        cmd_is_seek;
    wire        cmd_is_skip;
    wire        cmd_is_motion;
    wire        cmd_is_status;
    wire        cmd_is_config;
    wire        cmd_is_valid;

    // Individual command flags
    wire        cmd_reset;
    wire        cmd_seek_bot;
    wire        cmd_seek_eot;
    wire        cmd_skip_fwd_seg;
    wire        cmd_skip_rev_seg;
    wire        cmd_skip_fwd_file;
    wire        cmd_skip_rev_file;
    wire        cmd_physical_fwd;
    wire        cmd_physical_rev;
    wire        cmd_logical_fwd;
    wire        cmd_logical_rev;
    wire        cmd_pause;
    wire        cmd_report_status;
    wire        cmd_report_next_bit;
    wire        cmd_new_cartridge;
    wire        cmd_select_rate;
    wire        cmd_phantom_select;
    wire        cmd_phantom_deselect;

    //=========================================================================
    // Tape FSM Signals
    //=========================================================================
    wire        fsm_command_done;
    wire        fsm_command_error;
    wire [15:0] fsm_segment;
    wire [4:0]  fsm_track;
    wire        fsm_direction;
    wire        fsm_at_bot;
    wire        fsm_at_eot;
    wire        fsm_at_file_mark;
    wire        fsm_motor_on;
    wire        fsm_tape_moving;
    wire [1:0]  fsm_motion_mode;
    wire [3:0]  fsm_state_debug;
    wire [31:0] fsm_op_timer;

    //=========================================================================
    // Status Encoder Signals
    //=========================================================================
    wire        status_trk0;
    wire        status_busy;
    wire [3:0]  status_current_bit;
    wire [7:0]  status_word;

    //=========================================================================
    // Data Streamer Signals
    //=========================================================================
    wire        streamer_block_sync;
    wire [8:0]  streamer_byte_in_block;
    wire        streamer_block_start;
    wire        streamer_block_complete;
    wire [4:0]  streamer_block_in_segment;
    wire [7:0]  streamer_block_header;
    wire        streamer_segment_start;
    wire        streamer_segment_complete;
    wire [15:0] streamer_segment_count;
    wire        streamer_irg_detected;
    wire [7:0]  streamer_data_byte;
    wire        streamer_data_valid;
    wire        streamer_data_is_header;
    wire        streamer_data_is_ecc;
    wire [23:0] streamer_ecc_bytes;
    wire        streamer_ecc_valid;
    wire        streamer_is_data_block;
    wire        streamer_file_mark;
    wire        streamer_is_eod_mark;
    wire        streamer_is_bad_block;
    wire        streamer_sync_lost;
    wire        streamer_overrun;
    wire        streamer_preamble_error;
    wire [15:0] streamer_error_count;
    wire [15:0] streamer_good_block_count;
    wire [2:0]  streamer_state;
    wire [7:0]  streamer_preamble_count;

    //=========================================================================
    // Drive Detection Signals
    //=========================================================================
    wire [5:0]  detect_cmd_code;
    wire        detect_cmd_send;
    wire        detect_cmd_done;
    wire        detect_trk0_capture_start;
    wire [3:0]  detect_trk0_expected_bytes;
    wire [63:0] detect_trk0_response;
    wire [3:0]  detect_trk0_bytes_rcvd;
    wire        detect_trk0_complete;
    wire        detect_trk0_error;

    // TRK0 Decoder Signals
    wire        trk0_decoder_enable;
    wire        trk0_capture_active;
    wire [2:0]  trk0_bit_count;
    wire [19:0] trk0_pulse_width;

    // Detection result wires (directly connected to outputs)
    wire        detect_drive_present;
    wire        detect_cartridge_present;
    wire        detect_write_protected;
    wire [7:0]  detect_vendor_id;
    wire [7:0]  detect_model_id;
    wire [7:0]  detect_rom_version;
    wire [7:0]  detect_drive_config;
    wire [3:0]  detect_drive_type;
    wire [4:0]  detect_max_tracks;
    wire [1:0]  detect_supported_rates;
    wire        detect_detecting;
    wire [3:0]  detect_phase;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam [3:0] ST_IDLE           = 4'd0;   // Waiting for command
    localparam [3:0] ST_RESET          = 4'd1;   // Performing reset
    localparam [3:0] ST_SEEK_BOT       = 4'd2;   // Seeking to BOT
    localparam [3:0] ST_SEEK_EOT       = 4'd3;   // Seeking to EOT
    localparam [3:0] ST_SKIP_FWD       = 4'd4;   // Skipping forward
    localparam [3:0] ST_SKIP_REV       = 4'd5;   // Skipping reverse
    localparam [3:0] ST_STREAMING_FWD  = 4'd6;   // Streaming forward
    localparam [3:0] ST_STREAMING_REV  = 4'd7;   // Streaming reverse
    localparam [3:0] ST_PAUSE          = 4'd8;   // Paused
    localparam [3:0] ST_REPORT_STATUS  = 4'd9;   // Reporting status bits
    localparam [3:0] ST_ERROR          = 4'd10;  // Error state

    reg [3:0]  state;
    reg [3:0]  next_state;

    //=========================================================================
    // Position Tracking
    //=========================================================================

    reg [15:0] segment_reg;           // Current segment (0-4095)
    reg [4:0]  track_reg;             // Current track (0-27 for QIC-80)
    reg        direction_reg;         // 0 = forward, 1 = reverse
    reg        at_bot_reg;            // At beginning of tape
    reg        at_eot_reg;            // At end of tape

    //=========================================================================
    // Status Bits
    //=========================================================================

    reg        ready_reg;             // Drive ready
    reg        error_reg;             // Error condition
    reg        new_cartridge_reg;     // New cartridge detected
    reg        phantom_selected;      // Drive phantom selected

    //=========================================================================
    // Timing
    //=========================================================================

    // Operation timer for seek/skip operations
    reg [31:0] op_timer;
    reg        op_timer_running;
    wire       op_timer_done;

    // Simulated seek times (in clock cycles)
    localparam SEEK_BOT_CLKS = CLK_FREQ_HZ * 30;    // 30 seconds max
    localparam SEEK_EOT_CLKS = CLK_FREQ_HZ * 30;    // 30 seconds max
    localparam SKIP_SEG_CLKS = CLK_FREQ_HZ / 10;    // 100ms per segment

    //=========================================================================
    // Status Encoder
    //=========================================================================

    reg [7:0]  status_shift_reg;      // Status bits to send
    reg [3:0]  status_bit_cnt;        // Current bit being sent
    reg        status_sending;        // Currently sending status
    reg        trk0_reg;              // TRK0 output register

    // Status bit timing (TRK0 pulse widths)
    localparam STATUS_BIT0_CLKS = CLK_FREQ_HZ / 2000;   // 500µs for bit=0
    localparam STATUS_BIT1_CLKS = CLK_FREQ_HZ / 667;    // 1500µs for bit=1
    localparam STATUS_GAP_CLKS  = CLK_FREQ_HZ / 1000;   // 1ms gap between bits

    reg [19:0] status_timer;
    reg [1:0]  status_phase;  // 0=low, 1=gap

    //=========================================================================
    // INDEX Generation
    //=========================================================================

    reg        index_reg;
    reg [19:0] index_timer;
    localparam INDEX_PULSE_CLKS = CLK_FREQ_HZ / 10000;  // 100µs pulse

    //=========================================================================
    // Module Instantiations
    //=========================================================================

    // STEP pulse counter
    qic117_step_counter #(
        .CLK_FREQ_HZ  (CLK_FREQ_HZ),
        .TIMEOUT_MS   (100),
        .DEBOUNCE_US  (10)
    ) u_step_counter (
        .clk            (clk),
        .reset_n        (reset_n),
        .tape_mode_en   (tape_mode_en),
        .step_in        (step_in),
        .pulse_count    (pulse_count),
        .command_valid  (count_valid),
        .latched_command(latched_command),
        .counting       (counting),
        .timeout_pending(timeout_pending)
    );

    // Extended command decoder signals (used by status encoder and FSM)
    wire cmd_skip_fwd_ext;
    wire cmd_skip_rev_ext;
    wire cmd_stop;
    wire cmd_read_data;
    wire cmd_write_data;
    wire cmd_seek_track;
    wire cmd_seek_segment;
    wire cmd_retension;
    wire cmd_format_tape;
    wire cmd_verify_fwd;
    wire cmd_verify_rev;
    wire cmd_eject;
    wire cmd_set_speed;
    wire cmd_set_format;
    wire cmd_diagnostic;
    wire cmd_is_data;
    wire cmd_is_diagnostic;

    // Command decoder
    qic117_cmd_decoder u_cmd_decoder (
        .clk                (clk),
        .reset_n            (reset_n),
        .pulse_count        (latched_command),
        .command_valid      (count_valid),
        .command_code       (decoded_command),
        .command_strobe     (cmd_strobe),
        .cmd_is_reset       (cmd_is_reset),
        .cmd_is_seek        (cmd_is_seek),
        .cmd_is_skip        (cmd_is_skip),
        .cmd_is_motion      (cmd_is_motion),
        .cmd_is_status      (cmd_is_status),
        .cmd_is_config      (cmd_is_config),
        .cmd_is_valid       (cmd_is_valid),
        .cmd_reset          (cmd_reset),
        .cmd_seek_bot       (cmd_seek_bot),
        .cmd_seek_eot       (cmd_seek_eot),
        .cmd_skip_fwd_seg   (cmd_skip_fwd_seg),
        .cmd_skip_rev_seg   (cmd_skip_rev_seg),
        .cmd_skip_fwd_file  (cmd_skip_fwd_file),
        .cmd_skip_rev_file  (cmd_skip_rev_file),
        .cmd_physical_fwd   (cmd_physical_fwd),
        .cmd_physical_rev   (cmd_physical_rev),
        .cmd_logical_fwd    (cmd_logical_fwd),
        .cmd_logical_rev    (cmd_logical_rev),
        .cmd_pause          (cmd_pause),
        .cmd_report_status  (cmd_report_status),
        .cmd_report_next_bit(cmd_report_next_bit),
        .cmd_new_cartridge  (cmd_new_cartridge),
        .cmd_select_rate    (cmd_select_rate),
        .cmd_phantom_select (cmd_phantom_select),
        .cmd_phantom_deselect(cmd_phantom_deselect),
        // Extended commands (Phase 4)
        .cmd_skip_fwd_ext   (cmd_skip_fwd_ext),
        .cmd_skip_rev_ext   (cmd_skip_rev_ext),
        .cmd_stop           (cmd_stop),
        .cmd_read_data      (cmd_read_data),
        .cmd_write_data     (cmd_write_data),
        .cmd_seek_track     (cmd_seek_track),
        .cmd_seek_segment   (cmd_seek_segment),
        .cmd_retension      (cmd_retension),
        .cmd_format_tape    (cmd_format_tape),
        .cmd_verify_fwd     (cmd_verify_fwd),
        .cmd_verify_rev     (cmd_verify_rev),
        .cmd_eject          (cmd_eject),
        .cmd_report_vendor  (cmd_report_vendor),
        .cmd_report_model   (cmd_report_model),
        .cmd_report_rom_ver (cmd_report_rom_ver),
        .cmd_report_drive_cfg(cmd_report_drive_cfg),
        .cmd_set_speed      (cmd_set_speed),
        .cmd_set_format     (cmd_set_format),
        .cmd_diagnostic     (cmd_diagnostic),
        .cmd_is_data        (cmd_is_data),
        .cmd_is_diagnostic  (cmd_is_diagnostic)
    );

    //=========================================================================
    // Tape Position FSM
    //=========================================================================
    qic117_tape_fsm #(
        .CLK_FREQ_HZ  (CLK_FREQ_HZ),
        .MAX_SEGMENTS (4095),
        .MAX_TRACKS   (27)
    ) u_tape_fsm (
        .clk              (clk),
        .reset_n          (reset_n),
        .enable           (tape_mode_en),
        .command          (decoded_command),
        .command_valid    (cmd_strobe),
        .command_done     (fsm_command_done),
        .command_error    (fsm_command_error),
        .segment          (fsm_segment),
        .track            (fsm_track),
        .direction        (fsm_direction),
        .at_bot           (fsm_at_bot),
        .at_eot           (fsm_at_eot),
        .at_file_mark     (fsm_at_file_mark),
        .motor_on         (fsm_motor_on),
        .tape_moving      (fsm_tape_moving),
        .motion_mode      (fsm_motion_mode),
        .index_pulse      (streamer_segment_complete),  // INDEX from segment boundaries
        .file_mark_detect (streamer_file_mark),
        .fsm_state        (fsm_state_debug),
        .operation_timer  (fsm_op_timer)
    );

    //=========================================================================
    // Status Encoder
    //=========================================================================

    // Extended report command signals from decoder
    wire cmd_report_vendor;
    wire cmd_report_model;
    wire cmd_report_rom_ver;
    wire cmd_report_drive_cfg;
    wire [2:0] status_current_byte;

    qic117_status_encoder #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_status_encoder (
        .clk            (clk),
        .reset_n        (reset_n),
        .enable         (tape_mode_en),
        .send_status    (cmd_strobe && cmd_report_status),
        .send_next_bit  (cmd_strobe && cmd_report_next_bit),
        .send_vendor    (cmd_strobe && cmd_report_vendor),
        .send_model     (cmd_strobe && cmd_report_model),
        .send_rom_ver   (cmd_strobe && cmd_report_rom_ver),
        .send_drive_cfg (cmd_strobe && cmd_report_drive_cfg),
        .stat_ready     (ready_reg),
        .stat_error     (error_reg),
        .stat_cartridge (tape_cartridge_in),
        .stat_write_prot(tape_write_protect),
        .stat_new_cart  (new_cartridge_reg),
        .stat_at_bot    (fsm_at_bot),
        .stat_at_eot    (fsm_at_eot),
        // Drive identity from detection results
        .vendor_id      (detect_vendor_id),
        .model_id       (detect_model_id),
        .rom_version    (detect_rom_version),
        .drive_config   (detect_drive_config),
        .trk0_out       (status_trk0),
        .busy           (status_busy),
        .current_bit    (status_current_bit),
        .status_word    (status_word),
        .current_byte   (status_current_byte)
    );

    //=========================================================================
    // Data Streamer (Block Boundary Detector)
    //=========================================================================
    qic117_data_streamer #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_data_streamer (
        .clk              (clk),
        .reset_n          (reset_n),
        // Control
        .enable           (tape_mode_en),
        .streaming        (fsm_tape_moving),
        .direction        (fsm_direction),
        .clear_counters   (cmd_strobe && cmd_reset),
        // MFM data interface
        .mfm_data         (mfm_data_in),
        .mfm_clock        (mfm_clock),
        .dpll_locked      (dpll_locked),
        // Block detection outputs
        .block_sync       (streamer_block_sync),
        .byte_in_block    (streamer_byte_in_block),
        .block_start      (streamer_block_start),
        .block_complete   (streamer_block_complete),
        .block_in_segment (streamer_block_in_segment),
        .block_header     (streamer_block_header),
        // Segment tracking
        .segment_start    (streamer_segment_start),
        .segment_complete (streamer_segment_complete),
        .segment_count    (streamer_segment_count),
        .irg_detected     (streamer_irg_detected),
        // Data output
        .data_byte        (streamer_data_byte),
        .data_valid       (streamer_data_valid),
        .data_is_header   (streamer_data_is_header),
        .data_is_ecc      (streamer_data_is_ecc),
        // ECC output
        .ecc_bytes        (streamer_ecc_bytes),
        .ecc_valid        (streamer_ecc_valid),
        // Block type detection
        .is_data_block    (streamer_is_data_block),
        .is_file_mark     (streamer_file_mark),
        .is_eod_mark      (streamer_is_eod_mark),
        .is_bad_block     (streamer_is_bad_block),
        // Error detection
        .sync_lost        (streamer_sync_lost),
        .overrun_error    (streamer_overrun),
        .preamble_error   (streamer_preamble_error),
        .error_count      (streamer_error_count),
        .good_block_count (streamer_good_block_count),
        // Debug
        .state_out        (streamer_state),
        .preamble_count   (streamer_preamble_count)
    );

    //=========================================================================
    // TRK0 Response Decoder (for drive detection)
    //=========================================================================
    // Enable decoder during detection or when not sending status
    assign trk0_decoder_enable = tape_mode_en && (detect_detecting || !status_busy);

    qic117_trk0_decoder #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_trk0_decoder (
        .clk              (clk),
        .reset_n          (reset_n),
        .enable           (trk0_decoder_enable),
        .start_capture    (detect_trk0_capture_start),
        .expected_bytes   (detect_trk0_expected_bytes),
        .trk0_in          (tape_rdata),  // TRK0 from drive (active low pulses)
        .response_data    (detect_trk0_response),
        .bytes_received   (detect_trk0_bytes_rcvd),
        .capture_complete (detect_trk0_complete),
        .capture_error    (detect_trk0_error),
        .capture_active   (trk0_capture_active),
        .bit_count        (trk0_bit_count),
        .pulse_width      (trk0_pulse_width)
    );

    //=========================================================================
    // Drive Auto-Detection
    //=========================================================================
    // Command done signal for detection - command completes after timeout
    assign detect_cmd_done = cmd_strobe;  // Each command triggers strobe when done

    qic117_drive_detect #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_drive_detect (
        .clk                 (clk),
        .reset_n             (reset_n),
        .enable              (tape_mode_en),
        .start_detect        (start_detect),
        .abort_detect        (abort_detect),
        // Command interface - detection sends commands directly
        .cmd_code            (detect_cmd_code),
        .cmd_send            (detect_cmd_send),
        .cmd_done            (detect_cmd_done),
        // TRK0 decoder interface
        .trk0_capture_start  (detect_trk0_capture_start),
        .trk0_expected_bytes (detect_trk0_expected_bytes),
        .trk0_response       (detect_trk0_response),
        .trk0_bytes_rcvd     (detect_trk0_bytes_rcvd),
        .trk0_complete       (detect_trk0_complete),
        .trk0_error          (detect_trk0_error),
        // Detection results
        .detect_complete     (detect_complete),
        .detect_error        (detect_error),
        .drive_present       (detect_drive_present),
        .cartridge_present   (detect_cartridge_present),
        .write_protected     (detect_write_protected),
        .vendor_id           (detect_vendor_id),
        .model_id            (detect_model_id),
        .rom_version         (detect_rom_version),
        .drive_config        (detect_drive_config),
        .drive_type          (detect_drive_type),
        .max_tracks          (detect_max_tracks),
        .supported_rates     (detect_supported_rates),
        .detecting           (detect_detecting),
        .detect_phase        (detect_phase)
    );

    // Map detection results to outputs
    assign detect_in_progress   = detect_detecting;
    assign drive_detected       = detect_drive_present;
    assign detected_vendor      = detect_vendor_id;
    assign detected_model       = detect_model_id;
    assign detected_config      = detect_drive_config;
    assign detected_type        = detect_drive_type;
    assign detected_max_tracks  = detect_max_tracks;
    assign detected_rates       = detect_supported_rates;

    //=========================================================================
    // Operation Timer
    //=========================================================================

    assign op_timer_done = (op_timer == 0) && !op_timer_running;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            op_timer <= 32'd0;
            op_timer_running <= 1'b0;
        end else if (!tape_mode_en) begin
            op_timer <= 32'd0;
            op_timer_running <= 1'b0;
        end else if (op_timer_running) begin
            if (op_timer > 0) begin
                op_timer <= op_timer - 1'b1;
            end else begin
                op_timer_running <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
        end else if (!tape_mode_en) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (cmd_strobe && cmd_is_valid) begin
                    if (cmd_reset)
                        next_state = ST_RESET;
                    else if (cmd_seek_bot)
                        next_state = ST_SEEK_BOT;
                    else if (cmd_seek_eot)
                        next_state = ST_SEEK_EOT;
                    else if (cmd_skip_fwd_seg || cmd_skip_fwd_file)
                        next_state = ST_SKIP_FWD;
                    else if (cmd_skip_rev_seg || cmd_skip_rev_file)
                        next_state = ST_SKIP_REV;
                    else if (cmd_physical_fwd || cmd_logical_fwd)
                        next_state = ST_STREAMING_FWD;
                    else if (cmd_physical_rev || cmd_logical_rev)
                        next_state = ST_STREAMING_REV;
                    else if (cmd_pause)
                        next_state = ST_PAUSE;
                    else if (cmd_report_status || cmd_report_next_bit)
                        next_state = ST_REPORT_STATUS;
                end
            end

            ST_RESET: begin
                // Reset completes immediately
                next_state = ST_IDLE;
            end

            ST_SEEK_BOT: begin
                if (at_bot_reg || !op_timer_running)
                    next_state = ST_IDLE;
            end

            ST_SEEK_EOT: begin
                if (at_eot_reg || !op_timer_running)
                    next_state = ST_IDLE;
            end

            ST_SKIP_FWD: begin
                if (!op_timer_running)
                    next_state = ST_IDLE;
            end

            ST_SKIP_REV: begin
                if (!op_timer_running)
                    next_state = ST_IDLE;
            end

            ST_STREAMING_FWD, ST_STREAMING_REV: begin
                if (cmd_strobe && cmd_pause)
                    next_state = ST_PAUSE;
            end

            ST_PAUSE: begin
                if (cmd_strobe) begin
                    if (cmd_physical_fwd || cmd_logical_fwd)
                        next_state = ST_STREAMING_FWD;
                    else if (cmd_physical_rev || cmd_logical_rev)
                        next_state = ST_STREAMING_REV;
                end
            end

            ST_REPORT_STATUS: begin
                if (!status_sending)
                    next_state = ST_IDLE;
            end

            ST_ERROR: begin
                if (cmd_strobe && cmd_reset)
                    next_state = ST_RESET;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    //=========================================================================
    // State Machine Outputs
    //=========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            segment_reg       <= 16'd0;
            track_reg         <= 5'd0;
            direction_reg     <= 1'b0;
            at_bot_reg        <= 1'b1;    // Start at BOT
            at_eot_reg        <= 1'b0;
            ready_reg         <= 1'b0;
            error_reg         <= 1'b0;
            new_cartridge_reg <= 1'b0;
            phantom_selected  <= 1'b0;
            tape_motor_on     <= 1'b0;
        end else if (!tape_mode_en) begin
            // Reset all state when leaving tape mode
            tape_motor_on     <= 1'b0;
            ready_reg         <= 1'b0;
        end else begin
            // Default: motor off
            tape_motor_on <= 1'b0;

            case (state)
                ST_IDLE: begin
                    ready_reg <= tape_cartridge_in && phantom_selected;

                    // Handle configuration commands in IDLE
                    if (cmd_strobe) begin
                        if (cmd_phantom_select)
                            phantom_selected <= 1'b1;
                        else if (cmd_phantom_deselect)
                            phantom_selected <= 1'b0;
                        else if (cmd_new_cartridge) begin
                            new_cartridge_reg <= 1'b1;
                            segment_reg <= 16'd0;
                            track_reg <= 5'd0;
                            at_bot_reg <= 1'b1;
                            at_eot_reg <= 1'b0;
                        end
                    end
                end

                ST_RESET: begin
                    // Clear error flags
                    error_reg <= 1'b0;
                    new_cartridge_reg <= 1'b0;
                end

                ST_SEEK_BOT: begin
                    tape_motor_on <= 1'b1;
                    direction_reg <= 1'b1;  // Reverse

                    // Start timer on entry
                    if (state != ST_SEEK_BOT) begin
                        // Handled by separate always block
                    end

                    // Simulate reaching BOT
                    if (!op_timer_running) begin
                        at_bot_reg <= 1'b1;
                        at_eot_reg <= 1'b0;
                        segment_reg <= 16'd0;
                        track_reg <= 5'd0;
                    end
                end

                ST_SEEK_EOT: begin
                    tape_motor_on <= 1'b1;
                    direction_reg <= 1'b0;  // Forward

                    // Simulate reaching EOT
                    if (!op_timer_running) begin
                        at_bot_reg <= 1'b0;
                        at_eot_reg <= 1'b1;
                        segment_reg <= 16'd4095;  // Max segment
                    end
                end

                ST_SKIP_FWD: begin
                    tape_motor_on <= 1'b1;
                    direction_reg <= 1'b0;
                    at_bot_reg <= 1'b0;

                    // Increment segment when skip completes
                    if (!op_timer_running && segment_reg < 16'd4095) begin
                        segment_reg <= segment_reg + 1'b1;
                    end
                end

                ST_SKIP_REV: begin
                    tape_motor_on <= 1'b1;
                    direction_reg <= 1'b1;
                    at_eot_reg <= 1'b0;

                    // Decrement segment when skip completes
                    if (!op_timer_running && segment_reg > 0) begin
                        segment_reg <= segment_reg - 1'b1;
                    end

                    if (segment_reg == 0) begin
                        at_bot_reg <= 1'b1;
                    end
                end

                ST_STREAMING_FWD: begin
                    tape_motor_on <= 1'b1;
                    direction_reg <= 1'b0;
                    at_bot_reg <= 1'b0;
                end

                ST_STREAMING_REV: begin
                    tape_motor_on <= 1'b1;
                    direction_reg <= 1'b1;
                    at_eot_reg <= 1'b0;
                end

                ST_PAUSE: begin
                    tape_motor_on <= 1'b0;
                end

                ST_REPORT_STATUS: begin
                    // Status sending handled separately
                end

                ST_ERROR: begin
                    error_reg <= 1'b1;
                    tape_motor_on <= 1'b0;
                end
            endcase
        end
    end

    //=========================================================================
    // Operation Timer Start
    //=========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Timer cleared by reset in main timer block
        end else if (tape_mode_en && cmd_strobe) begin
            // Start timers based on command
            if (cmd_seek_bot) begin
                op_timer <= SEEK_BOT_CLKS;
                op_timer_running <= 1'b1;
            end else if (cmd_seek_eot) begin
                op_timer <= SEEK_EOT_CLKS;
                op_timer_running <= 1'b1;
            end else if (cmd_skip_fwd_seg || cmd_skip_rev_seg) begin
                op_timer <= SKIP_SEG_CLKS;
                op_timer_running <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Status Encoder (TRK0 Output)
    //=========================================================================

    // Build status byte
    wire [7:0] status_byte = {
        ready_reg,            // Bit 7: Ready
        error_reg,            // Bit 6: Error
        tape_write_protect,   // Bit 5: Write protected
        new_cartridge_reg,    // Bit 4: New cartridge
        at_bot_reg,           // Bit 3: At BOT
        at_eot_reg,           // Bit 2: At EOT
        tape_motor_on,        // Bit 1: Tape moving
        direction_reg         // Bit 0: Direction
    };

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            status_shift_reg <= 8'd0;
            status_bit_cnt   <= 4'd0;
            status_sending   <= 1'b0;
            status_timer     <= 20'd0;
            status_phase     <= 2'd0;
            trk0_reg         <= 1'b1;  // TRK0 normally high
        end else if (!tape_mode_en) begin
            status_sending <= 1'b0;
            trk0_reg <= 1'b1;
        end else begin
            if (cmd_strobe && cmd_report_status) begin
                // Start sending full status
                status_shift_reg <= status_byte;
                status_bit_cnt <= 4'd8;
                status_sending <= 1'b1;
                status_phase <= 2'd0;
                trk0_reg <= 1'b0;  // Start first bit
                // Set timer based on bit value
                status_timer <= status_byte[7] ? STATUS_BIT1_CLKS : STATUS_BIT0_CLKS;
            end else if (cmd_strobe && cmd_report_next_bit) begin
                // Send next bit (continue from current position)
                if (status_bit_cnt > 0) begin
                    status_sending <= 1'b1;
                    status_phase <= 2'd0;
                    trk0_reg <= 1'b0;
                    status_timer <= status_shift_reg[7] ? STATUS_BIT1_CLKS : STATUS_BIT0_CLKS;
                end
            end else if (status_sending) begin
                if (status_timer > 0) begin
                    status_timer <= status_timer - 1'b1;
                end else begin
                    case (status_phase)
                        2'd0: begin
                            // End of low pulse, start gap
                            trk0_reg <= 1'b1;
                            status_timer <= STATUS_GAP_CLKS;
                            status_phase <= 2'd1;
                        end

                        2'd1: begin
                            // End of gap, shift to next bit
                            status_shift_reg <= {status_shift_reg[6:0], 1'b0};
                            status_bit_cnt <= status_bit_cnt - 1'b1;

                            if (status_bit_cnt > 1) begin
                                // More bits to send
                                trk0_reg <= 1'b0;
                                status_timer <= status_shift_reg[6] ? STATUS_BIT1_CLKS : STATUS_BIT0_CLKS;
                                status_phase <= 2'd0;
                            end else begin
                                // Done sending
                                status_sending <= 1'b0;
                                trk0_reg <= 1'b1;
                            end
                        end

                        default: begin
                            status_phase <= 2'd0;
                        end
                    endcase
                end
            end
        end
    end

    //=========================================================================
    // INDEX Generation
    //=========================================================================

    // Generate INDEX pulse at segment boundaries during streaming
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            index_reg <= 1'b0;
            index_timer <= 20'd0;
        end else if (!tape_mode_en) begin
            index_reg <= 1'b0;
        end else begin
            // TODO: Generate INDEX at actual segment boundaries
            // For now, just keep it low
            if (index_timer > 0) begin
                index_timer <= index_timer - 1'b1;
                index_reg <= 1'b1;
            end else begin
                index_reg <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================

    // TRK0 output - use status encoder when sending status, otherwise idle high
    assign trk0_out  = tape_mode_en ? status_trk0 : 1'b1;

    // INDEX output - pulse on segment boundaries
    assign index_out = tape_mode_en ? index_reg : 1'b0;

    // Direction output - from FSM
    assign tape_direction = fsm_direction;

    // Motor control - driven by state machine in main always block above
    // (tape_motor_on is already assigned in the ST_* cases)

    // Data passthrough - from streamer
    assign tape_wdata = 1'b0;  // TODO: Connect to write path
    assign read_data  = streamer_data_byte;
    assign read_valid = streamer_data_valid;

    // Status outputs
    assign current_command  = decoded_command;
    assign command_strobe   = cmd_strobe;
    assign segment_position = fsm_segment;
    assign track_position   = fsm_track;
    assign tape_status      = status_word;
    assign command_active   = (state != ST_IDLE) || status_busy || fsm_tape_moving;
    assign tape_ready       = ready_reg;
    assign tape_error       = error_reg || fsm_command_error;

    // Data streamer status outputs
    assign block_sync       = streamer_block_sync;
    assign byte_in_block    = streamer_byte_in_block;
    assign block_in_segment = streamer_block_in_segment;
    assign segment_complete = streamer_segment_complete;
    assign file_mark_detect = streamer_file_mark;

endmodule
