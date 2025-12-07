//-----------------------------------------------------------------------------
// kf_protocol.v
// KryoFlux Stream Format Encoder
//
// Created: 2025-12-05 18:25
// Updated: 2025-12-06 14:30 - Added control transfer support for DTC compatibility
//
// Stream format encoder for KryoFlux-compatible flux data output.
//
// IMPORTANT NOTES:
//   - Stream format is publicly documented (softpres.org/kryoflux:stream)
//   - USB command codes derived from OpenDTC reverse engineering project
//   - Supports BOTH bulk endpoints AND USB control transfers
//   - Control transfer support added for true KryoFlux DTC compatibility
//
// Protocol information derived from OpenDTC project:
//   https://github.com/zeldin/OpenDTC
//   (C) 2013 Marcus Comstedt, licensed under GPL v2
//
// KryoFlux Stream Format (publicly documented):
//   0x00-0x07: Flux2 (1 byte, value 0x00-0x07 adds to next)
//   0x08:      Nop1 (skip 1 byte)
//   0x09:      Nop2 (skip 2 bytes)
//   0x0A:      Nop3 (skip 3 bytes)
//   0x0B:      Ovl16 (overflow, 16-bit follows)
//   0x0C:      Flux3 (16-bit value follows)
//   0x0D:      OOB (Out-of-Band message follows)
//   0x0E-0xFF: Flux1 (value - 0x0E = flux timing)
//
// OOB Message Types:
//   0x01: Stream Info
//   0x02: Index
//   0x03: Stream End
//   0x0D: EOF
//-----------------------------------------------------------------------------

module kf_protocol #(
    parameter SAMPLE_RATE_MHZ   = 300,   // FluxRipper sample rate
    parameter KF_RATE_HZ        = 24027428, // KryoFlux sample rate (~24.027 MHz)
    parameter OOB_BUFFER_SIZE   = 256
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // USB Bulk Endpoint Interface (backward compatible)
    //=========================================================================

    input  wire [31:0] cmd_rx_data,
    input  wire        cmd_rx_valid,
    output reg         cmd_rx_ready,

    output reg  [31:0] resp_tx_data,
    output reg         resp_tx_valid,
    input  wire        resp_tx_ready,

    //=========================================================================
    // USB Control Transfer Interface (for true DTC compatibility)
    //=========================================================================

    input  wire        ctrl_cmd_valid,
    input  wire [7:0]  ctrl_cmd_request,   // bRequest
    input  wire [15:0] ctrl_cmd_value,     // wValue
    input  wire [15:0] ctrl_cmd_index,     // wIndex
    input  wire [15:0] ctrl_cmd_length,    // wLength
    output reg  [7:0]  ctrl_response_data,
    output reg         ctrl_response_valid,
    output reg         ctrl_response_last,
    input  wire        ctrl_out_valid,     // Data from host (OUT phase)
    input  wire [7:0]  ctrl_out_data,

    //=========================================================================
    // Flux Data Interface (from FluxRipper capture)
    //=========================================================================

    input  wire [31:0] flux_in_data,      // [31]=INDEX, [26:0]=timestamp
    input  wire        flux_in_valid,
    output reg         flux_in_ready,

    //=========================================================================
    // Stream Output (KryoFlux format)
    //=========================================================================

    output reg  [7:0]  stream_out_data,
    output reg         stream_out_valid,
    input  wire        stream_out_ready,

    //=========================================================================
    // Drive Control Interface
    //=========================================================================

    output reg         drv_motor_on,
    output reg  [7:0]  drv_cylinder,
    output reg         drv_head,
    output reg         drv_step_dir,
    output reg         drv_step_pulse,
    output reg         drv_select,

    input  wire        drv_ready,
    input  wire        drv_track00,
    input  wire        drv_write_protect,
    input  wire        drv_index,

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  kf_state,
    output reg  [15:0] hw_version,
    output reg  [31:0] fw_version,
    output reg         stream_active,
    output reg  [31:0] stream_position,
    output reg  [15:0] revolution_count,

    //=========================================================================
    // Configuration (optional external control)
    //=========================================================================

    input  wire [15:0] cfg_step_time_us,     // Step pulse width (1-20 µs)
    input  wire [15:0] cfg_settle_time_ms,   // Head settle time (1-50 ms)
    input  wire [15:0] cfg_step_rate_us      // Step rate (500-20000 µs)
);

    //=========================================================================
    // KryoFlux Command Codes (from OpenDTC reverse engineering)
    //=========================================================================

    localparam CMD_RESET            = 8'h05;  // Device reset
    localparam CMD_DEVICE           = 8'h06;  // Device selection
    localparam CMD_MOTOR            = 8'h07;  // Motor control
    localparam CMD_DENSITY          = 8'h08;  // Density setting
    localparam CMD_SIDE             = 8'h09;  // Side selection
    localparam CMD_TRACK            = 8'h0A;  // Track positioning
    localparam CMD_STREAM           = 8'h0B;  // Data streaming
    localparam CMD_MIN_TRACK        = 8'h0C;  // Minimum track bound
    localparam CMD_MAX_TRACK        = 8'h0D;  // Maximum track bound
    localparam CMD_STATUS           = 8'h80;  // Status query
    localparam CMD_INFO             = 8'h81;  // Device information

    //=========================================================================
    // Stream Encoding Constants
    //=========================================================================

    localparam FLUX2_MAX     = 8'h07;
    localparam NOP1          = 8'h08;
    localparam NOP2          = 8'h09;
    localparam NOP3          = 8'h0A;
    localparam OVL16         = 8'h0B;
    localparam FLUX3         = 8'h0C;
    localparam OOB           = 8'h0D;
    localparam FLUX1_MIN     = 8'h0E;

    //=========================================================================
    // OOB Message Types
    //=========================================================================

    localparam OOB_INVALID   = 8'h00;
    localparam OOB_STREAM_INFO = 8'h01;
    localparam OOB_INDEX     = 8'h02;
    localparam OOB_STREAM_END= 8'h03;
    localparam OOB_KF_INFO   = 8'h04;
    localparam OOB_EOF       = 8'h0D;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE           = 4'd0;
    localparam ST_CMD_PARSE      = 4'd1;
    localparam ST_CMD_EXECUTE    = 4'd2;
    localparam ST_RESPONSE       = 4'd3;
    localparam ST_STREAMING      = 4'd4;
    localparam ST_STREAM_OOB     = 4'd5;
    localparam ST_STREAM_FLUX    = 4'd6;
    localparam ST_SEEK           = 4'd7;
    localparam ST_SEEK_WAIT      = 4'd8;
    localparam ST_FLUX3_BYTE1    = 4'd9;    // FLUX3 low byte
    localparam ST_FLUX3_BYTE2    = 4'd10;   // FLUX3 high byte

    reg [3:0] state;

    //=========================================================================
    // Step Timing Configuration
    //=========================================================================

    // Default step timing at 300 MHz clock
    // step_time_clocks = cfg_step_time_us * 300 (for µs to clocks at 300 MHz)
    // settle_time_clocks = cfg_settle_time_ms * 300000 (for ms to clocks)
    // step_rate_clocks = cfg_step_rate_us * 300

    localparam DEFAULT_STEP_TIME_US   = 16'd3;      // 3 µs step pulse
    localparam DEFAULT_SETTLE_TIME_MS = 16'd15;     // 15 ms head settle
    localparam DEFAULT_STEP_RATE_US   = 16'd3000;   // 3 ms step rate

    reg [23:0] step_timer;           // Countdown timer for step operations
    reg [23:0] step_time_clocks;     // Step pulse width in clocks
    reg [23:0] settle_time_clocks;   // Head settle time in clocks
    reg [23:0] step_rate_clocks;     // Time between steps in clocks
    reg [7:0]  steps_remaining;      // Steps left in seek operation
    reg        seek_direction;       // 0=out (lower track), 1=in (higher track)
    reg [7:0]  target_track;         // Target track for seek

    //=========================================================================
    // Density Configuration
    //=========================================================================

    reg [7:0]  density_mode;         // 0=DD, 1=HD, 2=ED
    localparam DENSITY_DD = 8'h00;   // Double density (250 kbit/s)
    localparam DENSITY_HD = 8'h01;   // High density (500 kbit/s)
    localparam DENSITY_ED = 8'h02;   // Extended density (1 Mbit/s)

    //=========================================================================
    // Track Limits (CMD_TRK_MIN_MAX)
    //=========================================================================

    reg [7:0]  track_min;            // Minimum track number
    reg [7:0]  track_max;            // Maximum track number

    //=========================================================================
    // FLUX2 Accumulator
    //=========================================================================

    // FLUX2 (0x00-0x07) values accumulate and add to the next sample
    reg [15:0] flux2_accumulator;    // Accumulated FLUX2 value
    reg        flux2_pending;        // Have accumulated value to add

    //=========================================================================
    // Command Parsing
    //=========================================================================

    reg [7:0]  cmd_code;
    reg [31:0] cmd_param;
    reg [7:0]  response_code;
    reg [31:0] response_data;
    reg        cmd_from_ctrl;        // Flag: command came from control transfer
    reg [3:0]  ctrl_resp_byte_count; // Control response byte counter (max 4 bytes)

    //=========================================================================
    // Rate Conversion
    //=========================================================================

    // FluxRipper runs at 300 MHz, KryoFlux expects ~24.027 MHz timing
    // Conversion factor: 300/24.027 ≈ 12.49
    // We'll use fixed-point: multiply by 24027428, divide by 300000000
    // Simplified: divide by 12.49 ≈ multiply by 524 and shift right by 13

    localparam RATE_MULT = 16'd524;
    localparam RATE_SHIFT = 4'd13;

    reg [31:0] flux_accumulator;
    reg [31:0] kf_sample;

    //=========================================================================
    // Stream State
    //=========================================================================

    reg [31:0] stream_sample_count;
    reg [31:0] index_sample_count;
    reg        prev_index;
    reg [7:0]  oob_buffer [0:OOB_BUFFER_SIZE-1];
    reg [7:0]  oob_length;
    reg [7:0]  oob_index;

    //=========================================================================
    // Initialization
    //=========================================================================

    initial begin
        hw_version = 16'h0100;      // v1.0 (FluxRipper emulating KF)
        fw_version = 32'h02000000;  // Firmware 2.0
    end

    //=========================================================================
    // Rate Conversion Function
    //=========================================================================

    function [15:0] convert_rate;
        input [31:0] fr_sample;
        reg [47:0] temp;
        begin
            // Convert FluxRipper 300MHz sample to KryoFlux ~24MHz
            temp = fr_sample * RATE_MULT;
            convert_rate = temp[28:13];
        end
    endfunction

    //=========================================================================
    // Main State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            kf_state <= 8'h0;

            cmd_rx_ready <= 1'b1;
            resp_tx_data <= 32'h0;
            resp_tx_valid <= 1'b0;
            flux_in_ready <= 1'b0;
            stream_out_data <= 8'h0;
            stream_out_valid <= 1'b0;

            ctrl_response_data <= 8'h0;
            ctrl_response_valid <= 1'b0;
            ctrl_response_last <= 1'b0;

            drv_motor_on <= 1'b0;
            drv_cylinder <= 8'h0;
            drv_head <= 1'b0;
            drv_step_dir <= 1'b0;
            drv_step_pulse <= 1'b0;
            drv_select <= 1'b0;

            stream_active <= 1'b0;
            stream_position <= 32'h0;
            revolution_count <= 16'h0;

            cmd_code <= 8'h0;
            cmd_param <= 32'h0;
            response_code <= 8'h0;
            response_data <= 32'h0;
            cmd_from_ctrl <= 1'b0;
            ctrl_resp_byte_count <= 4'h0;

            flux_accumulator <= 32'h0;
            stream_sample_count <= 32'h0;
            index_sample_count <= 32'h0;
            prev_index <= 1'b0;
            oob_length <= 8'h0;
            oob_index <= 8'h0;

            // Step timing (use config or defaults)
            step_timer <= 24'h0;
            step_time_clocks <= (cfg_step_time_us != 16'h0) ?
                                {8'h0, cfg_step_time_us} * 24'd300 :
                                DEFAULT_STEP_TIME_US * 24'd300;
            settle_time_clocks <= (cfg_settle_time_ms != 16'h0) ?
                                  {8'h0, cfg_settle_time_ms} * 24'd300000 :
                                  DEFAULT_SETTLE_TIME_MS * 24'd300000;
            step_rate_clocks <= (cfg_step_rate_us != 16'h0) ?
                                {8'h0, cfg_step_rate_us} * 24'd300 :
                                DEFAULT_STEP_RATE_US * 24'd300;
            steps_remaining <= 8'h0;
            seek_direction <= 1'b0;
            target_track <= 8'h0;

            // Density
            density_mode <= DENSITY_DD;

            // Track limits
            track_min <= 8'h00;
            track_max <= 8'h53;  // Default 83 tracks (0-82)

            // FLUX2 accumulator
            flux2_accumulator <= 16'h0;
            flux2_pending <= 1'b0;
        end else begin
            kf_state <= {4'h0, state};
            drv_step_pulse <= 1'b0;
            resp_tx_valid <= 1'b0;
            stream_out_valid <= 1'b0;
            ctrl_response_valid <= 1'b0;
            ctrl_response_last <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // IDLE - Wait for command from bulk OR control interface
                //-------------------------------------------------------------
                ST_IDLE: begin
                    cmd_rx_ready <= 1'b1;

                    // Priority: Control transfer takes precedence
                    if (ctrl_cmd_valid) begin
                        // Control transfer command
                        cmd_code <= ctrl_cmd_request;
                        cmd_param <= {16'h0, ctrl_cmd_value};  // wValue contains parameters
                        cmd_from_ctrl <= 1'b1;
                        ctrl_resp_byte_count <= 4'h0;
                        state <= ST_CMD_PARSE;
                    end
                    else if (cmd_rx_valid) begin
                        // Bulk endpoint command (legacy)
                        cmd_code <= cmd_rx_data[7:0];
                        cmd_param <= cmd_rx_data;
                        cmd_from_ctrl <= 1'b0;
                        cmd_rx_ready <= 1'b0;
                        state <= ST_CMD_PARSE;
                    end
                end

                //-------------------------------------------------------------
                // CMD_PARSE - Decode command (OpenDTC command codes)
                //-------------------------------------------------------------
                ST_CMD_PARSE: begin
                    case (cmd_code)
                        CMD_INFO: begin
                            // Return device information
                            response_code <= 8'h00;  // OK
                            response_data <= {hw_version, 16'h0001};
                            state <= ST_RESPONSE;
                        end

                        CMD_RESET: begin
                            // Device reset
                            drv_motor_on <= 1'b0;
                            drv_select <= 1'b0;
                            stream_active <= 1'b0;
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_DEVICE: begin
                            // Device selection
                            drv_select <= cmd_param[8];
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_MOTOR: begin
                            // Motor control
                            drv_motor_on <= cmd_param[8];
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_DENSITY: begin
                            // Density setting
                            density_mode <= cmd_param[15:8];
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_SIDE: begin
                            // Side selection
                            drv_head <= cmd_param[8];
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_TRACK: begin
                            // Track positioning - validate against limits
                            if (cmd_param[15:8] >= track_min && cmd_param[15:8] <= track_max) begin
                                target_track <= cmd_param[15:8];
                                seek_direction <= (cmd_param[15:8] > drv_cylinder);
                                if (cmd_param[15:8] != drv_cylinder) begin
                                    steps_remaining <= (cmd_param[15:8] > drv_cylinder) ?
                                                       (cmd_param[15:8] - drv_cylinder) :
                                                       (drv_cylinder - cmd_param[15:8]);
                                    step_timer <= step_time_clocks;
                                    drv_step_dir <= (cmd_param[15:8] > drv_cylinder);
                                    state <= ST_SEEK;
                                end else begin
                                    response_code <= 8'h00;
                                    state <= ST_RESPONSE;
                                end
                            end else begin
                                response_code <= 8'h01;  // Track out of range
                                state <= ST_RESPONSE;
                            end
                        end

                        CMD_STREAM: begin
                            // Start/stop streaming
                            if (stream_active) begin
                                // Stop streaming
                                stream_active <= 1'b0;
                                flux_in_ready <= 1'b0;
                                // Send stream end OOB
                                state <= ST_STREAM_OOB;
                                oob_buffer[0] <= OOB;
                                oob_buffer[1] <= OOB_STREAM_END;
                                oob_buffer[2] <= 8'h03;
                                oob_buffer[3] <= 8'h00;
                                oob_buffer[4] <= stream_position[7:0];
                                oob_buffer[5] <= stream_position[15:8];
                                oob_buffer[6] <= stream_position[23:16];
                                oob_buffer[7] <= stream_position[31:24];
                                oob_length <= 8'd8;
                                oob_index <= 8'd0;
                            end else begin
                                // Start streaming
                                stream_active <= 1'b1;
                                stream_sample_count <= 32'h0;
                                index_sample_count <= 32'h0;
                                revolution_count <= 16'h0;
                                state <= ST_STREAMING;
                            end
                        end

                        CMD_MIN_TRACK: begin
                            // Set minimum track bound
                            track_min <= cmd_param[15:8];
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_MAX_TRACK: begin
                            // Set maximum track bound
                            track_max <= cmd_param[15:8];
                            response_code <= 8'h00;
                            state <= ST_RESPONSE;
                        end

                        CMD_STATUS: begin
                            // Return status
                            response_code <= 8'h00;
                            response_data <= {8'h0, drv_track00, drv_write_protect, drv_ready, 5'h0,
                                             drv_cylinder, revolution_count[7:0]};
                            state <= ST_RESPONSE;
                        end

                        default: begin
                            response_code <= 8'hFF;  // Unknown command
                            state <= ST_RESPONSE;
                        end
                    endcase
                end

                //-------------------------------------------------------------
                // RESPONSE - Send response via bulk or control endpoint
                //-------------------------------------------------------------
                ST_RESPONSE: begin
                    if (cmd_from_ctrl) begin
                        // Send response via control transfer (byte by byte)
                        case (ctrl_resp_byte_count)
                            4'h0: ctrl_response_data <= response_code;
                            4'h1: ctrl_response_data <= response_data[7:0];
                            4'h2: ctrl_response_data <= response_data[15:8];
                            4'h3: ctrl_response_data <= response_data[23:16];
                            default: ctrl_response_data <= 8'h00;
                        endcase

                        ctrl_response_valid <= 1'b1;
                        ctrl_response_last <= (ctrl_resp_byte_count == 4'h3);

                        if (ctrl_resp_byte_count == 4'h3) begin
                            // Last byte sent
                            state <= ST_IDLE;
                        end else begin
                            ctrl_resp_byte_count <= ctrl_resp_byte_count + 1'b1;
                        end
                    end
                    else begin
                        // Send response via bulk endpoint (legacy)
                        if (resp_tx_ready || !resp_tx_valid) begin
                            resp_tx_data <= {response_data[23:0], response_code};
                            resp_tx_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // SEEK - Perform track seek with configurable timing
                //-------------------------------------------------------------
                // Step sequence:
                // 1. Assert step pulse for step_time_clocks
                // 2. Wait for step_rate_clocks - step_time_clocks
                // 3. Repeat until all steps complete
                // 4. Wait settle_time_clocks after final step
                //-------------------------------------------------------------
                ST_SEEK: begin
                    if (steps_remaining > 8'h0) begin
                        // Generate step pulse
                        drv_step_pulse <= 1'b1;
                        step_timer <= step_time_clocks;
                        state <= ST_SEEK_WAIT;
                    end else begin
                        // All steps complete - wait for head settle
                        step_timer <= settle_time_clocks;
                        drv_cylinder <= target_track;
                        state <= ST_SEEK_WAIT;
                    end
                end

                ST_SEEK_WAIT: begin
                    // Countdown timer
                    if (step_timer > 24'h1) begin
                        step_timer <= step_timer - 24'h1;

                        // Release step pulse after step_time expires
                        if (step_timer == step_rate_clocks - step_time_clocks) begin
                            drv_step_pulse <= 1'b0;
                        end
                    end else begin
                        // Timer expired
                        drv_step_pulse <= 1'b0;

                        if (steps_remaining > 8'h0) begin
                            // More steps to go
                            steps_remaining <= steps_remaining - 8'h1;
                            if (seek_direction)
                                drv_cylinder <= drv_cylinder + 1'b1;
                            else
                                drv_cylinder <= drv_cylinder - 1'b1;
                            step_timer <= step_rate_clocks;
                            state <= ST_SEEK;
                        end else begin
                            // Seek complete (settle time elapsed)
                            response_code <= 8'h00;
                            response_data <= {24'h0, drv_cylinder};
                            state <= ST_RESPONSE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // STREAMING - Main streaming state
                //-------------------------------------------------------------
                ST_STREAMING: begin
                    flux_in_ready <= 1'b1;

                    // Check for index pulse
                    if (drv_index && !prev_index) begin
                        // Send index OOB
                        state <= ST_STREAM_OOB;
                        oob_buffer[0] <= OOB;
                        oob_buffer[1] <= OOB_INDEX;
                        oob_buffer[2] <= 8'h0C;  // Size (12 bytes)
                        oob_buffer[3] <= 8'h00;
                        oob_buffer[4] <= stream_sample_count[7:0];
                        oob_buffer[5] <= stream_sample_count[15:8];
                        oob_buffer[6] <= stream_sample_count[23:16];
                        oob_buffer[7] <= stream_sample_count[31:24];
                        oob_buffer[8] <= index_sample_count[7:0];
                        oob_buffer[9] <= index_sample_count[15:8];
                        oob_buffer[10] <= index_sample_count[23:16];
                        oob_buffer[11] <= index_sample_count[31:24];
                        oob_buffer[12] <= revolution_count[7:0];
                        oob_buffer[13] <= revolution_count[15:8];
                        oob_buffer[14] <= 8'h00;
                        oob_buffer[15] <= 8'h00;
                        oob_length <= 8'd16;
                        oob_index <= 8'd0;
                        revolution_count <= revolution_count + 1'b1;
                        index_sample_count <= 32'h0;
                    end
                    // Process flux data
                    else if (flux_in_valid) begin
                        state <= ST_STREAM_FLUX;
                    end

                    prev_index <= drv_index;
                end

                //-------------------------------------------------------------
                // STREAM_OOB - Send OOB message
                //-------------------------------------------------------------
                ST_STREAM_OOB: begin
                    if (stream_out_ready || !stream_out_valid) begin
                        if (oob_index < oob_length) begin
                            stream_out_data <= oob_buffer[oob_index];
                            stream_out_valid <= 1'b1;
                            oob_index <= oob_index + 1'b1;
                            stream_position <= stream_position + 1'b1;
                        end else begin
                            if (stream_active)
                                state <= ST_STREAMING;
                            else
                                state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // STREAM_FLUX - Encode and send flux sample
                //-------------------------------------------------------------
                // KryoFlux stream encoding:
                //   0x00-0x07: FLUX2 - adds value to next flux sample
                //   0x0E-0xFF: FLUX1 - single byte (value - 0x0E)
                //   0x0C:      FLUX3 - followed by 16-bit value
                //   0x0B:      OVL16 - overflow marker
                //-------------------------------------------------------------
                ST_STREAM_FLUX: begin
                    if (stream_out_ready || !stream_out_valid) begin
                        // Convert sample rate and add any accumulated FLUX2
                        kf_sample <= convert_rate(flux_in_data[26:0]) +
                                    (flux2_pending ? flux2_accumulator : 16'h0);

                        // Reset FLUX2 accumulator after use
                        if (flux2_pending) begin
                            flux2_accumulator <= 16'h0;
                            flux2_pending <= 1'b0;
                        end

                        // Encode based on value
                        if (kf_sample <= FLUX2_MAX) begin
                            // Very small value: use FLUX2 encoding
                            // FLUX2 accumulates and adds to next sample
                            stream_out_data <= kf_sample[2:0];
                            stream_out_valid <= 1'b1;
                            stream_position <= stream_position + 1'b1;
                            flux2_accumulator <= flux2_accumulator + kf_sample[15:0];
                            flux2_pending <= 1'b1;
                            // Don't count as sample yet - will be counted with next
                            state <= ST_STREAMING;
                        end else if (kf_sample < (256 - FLUX1_MIN)) begin
                            // Single byte: 0x0E + value
                            stream_out_data <= FLUX1_MIN + kf_sample[7:0];
                            stream_out_valid <= 1'b1;
                            stream_position <= stream_position + 1'b1;
                            stream_sample_count <= stream_sample_count + 1'b1;
                            index_sample_count <= index_sample_count + 1'b1;
                            state <= ST_STREAMING;
                        end else if (kf_sample < 16'hFFFF) begin
                            // Three bytes: 0x0C + 16-bit value
                            stream_out_data <= FLUX3;
                            stream_out_valid <= 1'b1;
                            stream_position <= stream_position + 1'b1;
                            state <= ST_FLUX3_BYTE1;
                        end else begin
                            // Overflow (>65535)
                            stream_out_data <= OVL16;
                            stream_out_valid <= 1'b1;
                            stream_position <= stream_position + 1'b1;
                            stream_sample_count <= stream_sample_count + 1'b1;
                            index_sample_count <= index_sample_count + 1'b1;
                            state <= ST_STREAMING;
                        end
                    end
                end

                //-------------------------------------------------------------
                // FLUX3_BYTE1 - Send low byte of 16-bit flux value
                //-------------------------------------------------------------
                ST_FLUX3_BYTE1: begin
                    if (stream_out_ready || !stream_out_valid) begin
                        stream_out_data <= kf_sample[7:0];
                        stream_out_valid <= 1'b1;
                        stream_position <= stream_position + 1'b1;
                        state <= ST_FLUX3_BYTE2;
                    end
                end

                //-------------------------------------------------------------
                // FLUX3_BYTE2 - Send high byte of 16-bit flux value
                //-------------------------------------------------------------
                ST_FLUX3_BYTE2: begin
                    if (stream_out_ready || !stream_out_valid) begin
                        stream_out_data <= kf_sample[15:8];
                        stream_out_valid <= 1'b1;
                        stream_position <= stream_position + 1'b1;
                        stream_sample_count <= stream_sample_count + 1'b1;
                        index_sample_count <= index_sample_count + 1'b1;
                        state <= ST_STREAMING;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
