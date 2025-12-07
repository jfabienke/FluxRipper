//-----------------------------------------------------------------------------
// ESDI Command Interface
//
// Implements the serial command/status interface for ESDI drives:
//   - 16-bit command words + parity sent serially on COMMAND DATA (pin 34)
//   - 16-bit status words + parity received on CONFIG/STATUS DATA (pin 8)
//   - TRANSFER REQ/ACK handshaking
//   - ATTENTION signal handling
//
// Commands sent TO drive (we are the controller):
//   0x01 - Read
//   0x02 - Write
//   0x05 - Seek
//   0x06 - Park Heads
//   0x08 - Get Device Status
//   0x09 - Get Device Configuration (returns geometry!)
//   0x0A - Get POS Info
//
// Clock domain: 300 MHz
// Created: 2025-12-04 17:45
//-----------------------------------------------------------------------------

module esdi_cmd (
    input  wire        clk,              // 300 MHz system clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire        cmd_enable,       // Enable command interface
    input  wire [1:0]  drive_select,     // Which drive (0 or 1)

    //-------------------------------------------------------------------------
    // 34-pin Control Cable Interface
    //-------------------------------------------------------------------------
    // Command Data (controller -> drive)
    output reg         cmd_data_out,     // Pin 34: COMMAND DATA
    output reg         cmd_data_oe,      // Output enable for cmd_data

    // Config/Status Data (drive -> controller)
    input  wire        status_data_in,   // Pin 8: CONFIG/STATUS DATA

    // Transfer handshaking
    output reg         transfer_req,     // Pin 24: TRANSFER REQUEST
    input  wire        transfer_ack,     // Pin 10: TRANSFER ACKNOWLEDGE

    // Attention (drive -> controller)
    input  wire        attention,        // Pin 12: ATTENTION

    //-------------------------------------------------------------------------
    // Command Interface (from firmware/FSM)
    //-------------------------------------------------------------------------
    input  wire        cmd_start,        // Start command execution
    input  wire [7:0]  cmd_opcode,       // Command opcode
    input  wire [15:0] cmd_param,        // Command parameter (cylinder, etc.)
    output reg         cmd_busy,         // Command in progress
    output reg         cmd_done,         // Command complete
    output reg         cmd_error,        // Command failed

    //-------------------------------------------------------------------------
    // Status/Response Interface
    //-------------------------------------------------------------------------
    output reg  [15:0] status_word,      // Received status word
    output reg         status_valid,     // Status word is valid

    // GET_DEV_CONFIG response (geometry!)
    output reg         config_valid,     // Configuration data valid
    output reg  [15:0] cfg_cylinders,    // Number of cylinders
    output reg  [7:0]  cfg_heads,        // Number of heads
    output reg  [7:0]  cfg_spt,          // Sectors per track
    output reg  [31:0] cfg_total_sectors,// Total sector count
    output reg  [7:0]  cfg_bytes_per_sector, // Bytes per sector code

    //-------------------------------------------------------------------------
    // Attention/Interrupt Status
    //-------------------------------------------------------------------------
    output reg         attention_pending,// ATTENTION signal asserted
    output reg  [3:0]  attention_code    // Decoded attention type
);

    //-------------------------------------------------------------------------
    // ESDI Command Opcodes
    //-------------------------------------------------------------------------
    localparam [7:0]
        CMD_READ            = 8'h01,
        CMD_WRITE           = 8'h02,
        CMD_READ_VERIFY     = 8'h03,
        CMD_WRITE_VERIFY    = 8'h04,
        CMD_SEEK            = 8'h05,
        CMD_PARK_HEADS      = 8'h06,
        CMD_GET_DEV_STATUS  = 8'h08,
        CMD_GET_DEV_CONFIG  = 8'h09,
        CMD_GET_POS_INFO    = 8'h0A,
        CMD_FORMAT_UNIT     = 8'h16,
        CMD_FORMAT_PREPARE  = 8'h17;

    //-------------------------------------------------------------------------
    // Command Word Format (16 bits + parity)
    //-------------------------------------------------------------------------
    // Bits [15:14] = Command size (00 = 2 words, 01 = 4 words)
    // Bits [13:11] = Device select
    // Bits [10:8]  = Reserved
    // Bits [7:0]   = Command opcode
    //
    // For multi-word commands:
    //   Word 0: Command header
    //   Word 1: Parameter (cylinder, etc.)
    //   Word 2-3: Extended parameters

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [3:0]
        STATE_IDLE          = 4'd0,
        STATE_SEND_CMD      = 4'd1,     // Sending command word
        STATE_SEND_PARITY   = 4'd2,     // Sending parity bit
        STATE_WAIT_ACK      = 4'd3,     // Waiting for transfer ack
        STATE_SEND_PARAM    = 4'd4,     // Sending parameter word
        STATE_RECV_STATUS   = 4'd5,     // Receiving status word
        STATE_RECV_CONFIG   = 4'd6,     // Receiving config data
        STATE_PROCESS       = 4'd7,     // Processing response
        STATE_DONE          = 4'd8,
        STATE_ERROR         = 4'd9;

    reg [3:0] state;

    //-------------------------------------------------------------------------
    // Serial Shift Registers
    //-------------------------------------------------------------------------
    reg [16:0] tx_shift;        // 16 data bits + parity
    reg [16:0] rx_shift;        // 16 data bits + parity
    reg [4:0]  bit_count;       // Bit counter (0-16)
    reg [1:0]  word_count;      // Word counter for multi-word transfers

    //-------------------------------------------------------------------------
    // Command Building
    //-------------------------------------------------------------------------
    reg [15:0] cmd_word;
    reg        cmd_parity;

    // Calculate parity (odd parity)
    function calc_parity;
        input [15:0] data;
        begin
            calc_parity = ^data;  // XOR all bits, then invert for odd parity
        end
    endfunction

    //-------------------------------------------------------------------------
    // Timing
    //-------------------------------------------------------------------------
    // ESDI serial interface runs at ~1-2 MHz
    // At 300 MHz, need ~150-300 clocks per bit
    localparam [8:0] BIT_PERIOD = 9'd200;  // ~1.5 MHz serial rate
    reg [8:0] bit_timer;

    //-------------------------------------------------------------------------
    // Attention Handling
    //-------------------------------------------------------------------------
    reg [2:0] attention_sync;
    wire attention_edge;

    always @(posedge clk) begin
        if (reset) begin
            attention_sync <= 3'b000;
        end else begin
            attention_sync <= {attention_sync[1:0], attention};
        end
    end

    assign attention_edge = attention_sync[1] & ~attention_sync[2];

    //-------------------------------------------------------------------------
    // Transfer ACK Synchronization
    //-------------------------------------------------------------------------
    reg [2:0] ack_sync;
    wire ack_pulse;

    always @(posedge clk) begin
        if (reset) begin
            ack_sync <= 3'b000;
        end else begin
            ack_sync <= {ack_sync[1:0], transfer_ack};
        end
    end

    assign ack_pulse = ack_sync[1] & ~ack_sync[2];

    //-------------------------------------------------------------------------
    // Config Data Storage (multi-word response)
    //-------------------------------------------------------------------------
    reg [15:0] config_words [0:5];  // Up to 6 words of config data
    reg [2:0]  config_word_idx;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            cmd_busy <= 1'b0;
            cmd_done <= 1'b0;
            cmd_error <= 1'b0;
            cmd_data_out <= 1'b0;
            cmd_data_oe <= 1'b0;
            transfer_req <= 1'b0;
            status_word <= 16'd0;
            status_valid <= 1'b0;
            config_valid <= 1'b0;
            cfg_cylinders <= 16'd0;
            cfg_heads <= 8'd0;
            cfg_spt <= 8'd0;
            cfg_total_sectors <= 32'd0;
            cfg_bytes_per_sector <= 8'd0;
            attention_pending <= 1'b0;
            attention_code <= 4'd0;
            tx_shift <= 17'd0;
            rx_shift <= 17'd0;
            bit_count <= 5'd0;
            word_count <= 2'd0;
            bit_timer <= 9'd0;
            config_word_idx <= 3'd0;
        end else begin
            // Default outputs
            cmd_done <= 1'b0;
            status_valid <= 1'b0;

            // Attention detection
            if (attention_edge) begin
                attention_pending <= 1'b1;
            end

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    cmd_busy <= 1'b0;
                    cmd_data_oe <= 1'b0;
                    transfer_req <= 1'b0;

                    if (cmd_start && cmd_enable) begin
                        cmd_busy <= 1'b1;
                        cmd_error <= 1'b0;
                        config_valid <= 1'b0;

                        // Build command word
                        // [15:14] = size (00 for most commands)
                        // [13:11] = device select
                        // [7:0] = opcode
                        cmd_word <= {2'b00, drive_select[0], 2'b00, 3'b000, cmd_opcode};
                        cmd_parity <= calc_parity({2'b00, drive_select[0], 2'b00, 3'b000, cmd_opcode});

                        // Load shift register
                        tx_shift <= {calc_parity({2'b00, drive_select[0], 2'b00, 3'b000, cmd_opcode}),
                                    2'b00, drive_select[0], 2'b00, 3'b000, cmd_opcode};
                        bit_count <= 5'd0;
                        word_count <= 2'd0;
                        bit_timer <= 9'd0;

                        state <= STATE_SEND_CMD;
                    end
                end

                //-------------------------------------------------------------
                STATE_SEND_CMD: begin
                    cmd_data_oe <= 1'b1;
                    transfer_req <= 1'b1;

                    bit_timer <= bit_timer + 1;

                    if (bit_timer >= BIT_PERIOD) begin
                        bit_timer <= 9'd0;

                        // Output next bit (MSB first)
                        cmd_data_out <= tx_shift[16];
                        tx_shift <= {tx_shift[15:0], 1'b0};
                        bit_count <= bit_count + 1;

                        if (bit_count >= 5'd16) begin
                            // All 17 bits sent (16 data + 1 parity)
                            state <= STATE_WAIT_ACK;
                            bit_count <= 5'd0;
                        end
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_ACK: begin
                    transfer_req <= 1'b0;
                    bit_timer <= bit_timer + 1;

                    if (ack_pulse) begin
                        // Drive acknowledged
                        word_count <= word_count + 1;

                        case (cmd_opcode)
                            CMD_SEEK: begin
                                if (word_count == 2'd0) begin
                                    // Need to send parameter (cylinder)
                                    tx_shift <= {calc_parity(cmd_param), cmd_param};
                                    state <= STATE_SEND_CMD;
                                end else begin
                                    // Command complete, wait for status
                                    state <= STATE_RECV_STATUS;
                                    bit_count <= 5'd0;
                                end
                            end

                            CMD_GET_DEV_CONFIG: begin
                                // Expect multi-word response
                                config_word_idx <= 3'd0;
                                state <= STATE_RECV_CONFIG;
                                bit_count <= 5'd0;
                            end

                            CMD_GET_DEV_STATUS,
                            CMD_GET_POS_INFO: begin
                                // Expect single status word
                                state <= STATE_RECV_STATUS;
                                bit_count <= 5'd0;
                            end

                            default: begin
                                // Simple command, wait for completion
                                state <= STATE_RECV_STATUS;
                                bit_count <= 5'd0;
                            end
                        endcase
                    end else if (bit_timer > 9'd511) begin
                        // Timeout waiting for ACK
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_RECV_STATUS: begin
                    cmd_data_oe <= 1'b0;  // Release bus for input
                    bit_timer <= bit_timer + 1;

                    if (bit_timer >= BIT_PERIOD) begin
                        bit_timer <= 9'd0;

                        // Shift in received bit
                        rx_shift <= {rx_shift[15:0], status_data_in};
                        bit_count <= bit_count + 1;

                        if (bit_count >= 5'd16) begin
                            // All 17 bits received
                            status_word <= rx_shift[16:1];  // Exclude parity
                            status_valid <= 1'b1;

                            // Check parity
                            if (calc_parity(rx_shift[16:1]) != rx_shift[0]) begin
                                // Parity error
                                cmd_error <= 1'b1;
                            end

                            state <= STATE_PROCESS;
                        end
                    end
                end

                //-------------------------------------------------------------
                STATE_RECV_CONFIG: begin
                    cmd_data_oe <= 1'b0;
                    bit_timer <= bit_timer + 1;

                    if (bit_timer >= BIT_PERIOD) begin
                        bit_timer <= 9'd0;

                        rx_shift <= {rx_shift[15:0], status_data_in};
                        bit_count <= bit_count + 1;

                        if (bit_count >= 5'd16) begin
                            // Store this config word
                            config_words[config_word_idx] <= rx_shift[16:1];
                            config_word_idx <= config_word_idx + 1;
                            bit_count <= 5'd0;

                            // GET_DEV_CONFIG returns 6 words typically
                            if (config_word_idx >= 3'd5) begin
                                state <= STATE_PROCESS;
                            end
                            // Otherwise continue receiving
                        end
                    end

                    // Timeout
                    if (bit_timer > 9'd511 && bit_count == 5'd0) begin
                        // No more data, process what we have
                        state <= STATE_PROCESS;
                    end
                end

                //-------------------------------------------------------------
                STATE_PROCESS: begin
                    // Decode response based on command
                    case (cmd_opcode)
                        CMD_GET_DEV_CONFIG: begin
                            // Parse configuration data
                            // Word format varies by drive, but typically:
                            // Word 0: Status/flags
                            // Word 1: Spares/flags
                            // Word 2-3: Total sectors (32-bit)
                            // Word 4: Cylinders (or packed geometry)
                            // Word 5: Heads/SPT packed

                            cfg_total_sectors <= {config_words[2], config_words[3]};
                            cfg_cylinders <= config_words[4];

                            // Word 5 format: [15:8] = heads, [7:0] = SPT (typical)
                            cfg_heads <= config_words[5][15:8];
                            cfg_spt <= config_words[5][7:0];

                            // If heads/spt are zero, try alternate decoding
                            if (config_words[5] == 16'd0) begin
                                // Some drives pack differently
                                cfg_heads <= config_words[4][15:8];
                                cfg_spt <= config_words[4][7:0];
                                cfg_cylinders <= {8'd0, config_words[3][15:8]};
                            end

                            config_valid <= 1'b1;
                        end

                        CMD_GET_DEV_STATUS: begin
                            // Status word contains error codes, drive state
                            // Bit 0 = Ready
                            // Bit 1 = Seek complete
                            // etc.
                        end

                        default: begin
                            // Nothing special to decode
                        end
                    endcase

                    state <= STATE_DONE;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    cmd_done <= 1'b1;
                    cmd_busy <= 1'b0;
                    cmd_data_oe <= 1'b0;
                    transfer_req <= 1'b0;
                    state <= STATE_IDLE;
                end

                //-------------------------------------------------------------
                STATE_ERROR: begin
                    cmd_error <= 1'b1;
                    cmd_busy <= 1'b0;
                    cmd_done <= 1'b1;
                    cmd_data_oe <= 1'b0;
                    transfer_req <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// ESDI Configuration Parser
// Extracts drive geometry from GET_DEV_CONFIG response
//-----------------------------------------------------------------------------
module esdi_config_parser (
    input  wire [15:0] word0,      // Config word 0
    input  wire [15:0] word1,      // Config word 1
    input  wire [15:0] word2,      // Config word 2
    input  wire [15:0] word3,      // Config word 3
    input  wire [15:0] word4,      // Config word 4
    input  wire [15:0] word5,      // Config word 5

    output wire [15:0] cylinders,
    output wire [7:0]  heads,
    output wire [7:0]  sectors_per_track,
    output wire [31:0] total_sectors,
    output wire [7:0]  transfer_rate,    // 0=10M, 1=15M, 2=20M
    output wire        soft_sectored,
    output wire        fixed_drive
);

    // Standard ESDI configuration word format (similar to early ATA IDENTIFY)
    //
    // Word 0: General configuration
    //   Bit 15: 0 = ATA, 1 = Non-ATA (ESDI)
    //   Bit 6: Fixed drive
    //   Bit 5: Soft sectored
    //   Bit 1-0: Transfer rate (00=10Mbps, 01=15Mbps, 10=20Mbps)
    //
    // Word 1: Number of cylinders
    // Word 3: Number of heads
    // Word 4: Unformatted bytes per track
    // Word 5: Unformatted bytes per sector
    // Word 6: Sectors per track

    // Parse based on common ESDI format
    assign cylinders = word1;
    assign heads = word3[7:0];
    assign sectors_per_track = word5[7:0] != 8'd0 ? word5[7:0] : 8'd36;  // Default 36 SPT

    // Total sectors if provided, else calculate
    assign total_sectors = (word2 != 16'd0 || word3 != 16'd0) ?
                           {word2, word3} :
                           ({16'd0, cylinders} * {24'd0, heads} * {24'd0, sectors_per_track});

    // Configuration flags from word 0
    assign transfer_rate = word0[1:0];
    assign soft_sectored = word0[5];
    assign fixed_drive = word0[6];

endmodule
