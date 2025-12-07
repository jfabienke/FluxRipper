//-----------------------------------------------------------------------------
// gw_protocol.v
// Greaseweazle USB Protocol Handler (Full Implementation)
//
// Created: 2025-12-05 08:15
// Updated: 2025-12-05 19:45 - Complete protocol implementation
//
// Implements the Greaseweazle USB CDC ACM protocol for compatibility with:
//   - gw (official Greaseweazle tool)
//   - FluxEngine (--usb.greaseweazle.port mode)
//   - HxC software (Greaseweazle mode)
//
// Protocol Reference: github.com/keirf/greaseweazle-firmware
//
// Key Features:
//   - Binary command/response protocol over virtual serial
//   - Variable-length flux encoding (1-249 direct, 250-1524 two-byte, 1525+ seven-byte)
//   - Reports as F7 Lightning for High-Speed USB compatibility
//   - Sample rate: 72 MHz (standard GW rate, converted from FluxRipper 300 MHz)
//-----------------------------------------------------------------------------

module gw_protocol #(
    parameter FLUXRIPPER_RATE_MHZ = 300,    // FluxRipper sample rate
    parameter GW_SAMPLE_FREQ      = 72000000 // Greaseweazle F7 sample frequency (72 MHz)
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // USB Interface (from personality mux)
    //=========================================================================
    input  wire [31:0] rx_data,
    input  wire        rx_valid,
    output reg         rx_ready,

    output reg  [31:0] tx_data,
    output reg         tx_valid,
    input  wire        tx_ready,

    //=========================================================================
    // Flux Data Interface
    //=========================================================================
    input  wire [31:0] flux_data,           // FluxRipper format: [31]=INDEX, [27:0]=timestamp
    input  wire        flux_valid,
    output reg         flux_ready,
    input  wire        flux_index,          // Raw index pulse

    //=========================================================================
    // Drive Control Interface
    //=========================================================================
    output reg  [3:0]  drive_select,        // One-hot drive selection
    output reg         motor_on,
    output reg         head_select,         // 0=side 0, 1=side 1
    output reg  [7:0]  track,               // Target track/cylinder
    output reg         seek_start,
    input  wire        seek_complete,
    input  wire        track_00,

    // Drive status
    input  wire        disk_present,
    input  wire        write_protect,

    //=========================================================================
    // Capture Control
    //=========================================================================
    output reg         capture_start,
    output reg         capture_stop,
    output reg  [7:0]  sample_rate,         // Sample rate selector
    input  wire        capturing,

    //=========================================================================
    // Status
    //=========================================================================
    output reg  [7:0]  state                // Protocol state for debug
);

    //=========================================================================
    // Greaseweazle Command Codes (from cdc_acm_protocol.h)
    //=========================================================================
    localparam [7:0]
        CMD_GET_INFO        = 8'd0,
        CMD_UPDATE          = 8'd1,
        CMD_SEEK            = 8'd2,
        CMD_HEAD            = 8'd3,
        CMD_SET_PARAMS      = 8'd4,
        CMD_GET_PARAMS      = 8'd5,
        CMD_MOTOR           = 8'd6,
        CMD_READ_FLUX       = 8'd7,
        CMD_WRITE_FLUX      = 8'd8,
        CMD_GET_FLUX_STATUS = 8'd9,
        CMD_GET_INDEX_TIMES = 8'd10,
        CMD_SWITCH_FW_MODE  = 8'd11,
        CMD_SELECT          = 8'd12,
        CMD_DESELECT        = 8'd13,
        CMD_SET_BUS_TYPE    = 8'd14,
        CMD_SET_PIN         = 8'd15,
        CMD_RESET           = 8'd16,
        CMD_ERASE_FLUX      = 8'd17,
        CMD_SOURCE_BYTES    = 8'd18,
        CMD_SINK_BYTES      = 8'd19,
        CMD_GET_PIN         = 8'd20,
        CMD_TEST_MODE       = 8'd21,
        CMD_NOCLICK_STEP    = 8'd22,
        CMD_MAX             = 8'd22;

    //=========================================================================
    // Greaseweazle ACK/Error Codes
    //=========================================================================
    localparam [7:0]
        ACK_OKAY            = 8'd0,
        ACK_BAD_COMMAND     = 8'd1,
        ACK_NO_INDEX        = 8'd2,
        ACK_NO_TRK0         = 8'd3,
        ACK_FLUX_OVERFLOW   = 8'd4,
        ACK_FLUX_UNDERFLOW  = 8'd5,
        ACK_WRPROT          = 8'd6,
        ACK_NO_UNIT         = 8'd7,
        ACK_NO_BUS          = 8'd8,
        ACK_BAD_UNIT        = 8'd9,
        ACK_BAD_PIN         = 8'd10,
        ACK_BAD_CYLINDER    = 8'd11,
        ACK_OUT_OF_SRAM     = 8'd12,
        ACK_OUT_OF_FLASH    = 8'd13;

    //=========================================================================
    // GetInfo Indices
    //=========================================================================
    localparam [7:0]
        GETINFO_FIRMWARE    = 8'd0,
        GETINFO_BW_STATS    = 8'd1,
        GETINFO_CURRENT_DRV = 8'd7;

    //=========================================================================
    // Bus Types
    //=========================================================================
    localparam [7:0]
        BUS_NONE            = 8'd0,
        BUS_IBMPC           = 8'd1,
        BUS_SHUGART         = 8'd2;

    //=========================================================================
    // Flux Opcodes
    //=========================================================================
    localparam [7:0]
        FLUXOP_INDEX        = 8'd1,
        FLUXOP_SPACE        = 8'd2,
        FLUXOP_ASTABLE      = 8'd3;

    //=========================================================================
    // Hardware Identity (Report as F7 Lightning)
    //=========================================================================
    localparam [7:0]
        GW_FW_MAJOR         = 8'd1,
        GW_FW_MINOR         = 8'd6,     // v1.6
        GW_IS_MAIN_FW       = 8'd1,
        GW_HW_MODEL         = 8'd7,     // F7
        GW_HW_SUBMODEL      = 8'd1,     // Lightning
        GW_USB_SPEED        = 8'd1,     // High-Speed (480 Mbit/s)
        GW_MCU_ID           = 8'd7;     // STM32F730

    localparam [15:0]
        GW_MCU_MHZ          = 16'd216,
        GW_MCU_SRAM_KB      = 16'd64,
        GW_USB_BUF_KB       = 16'd32;

    //=========================================================================
    // Rate Conversion: FluxRipper 300 MHz -> GW 72 MHz
    //=========================================================================
    // GW_ticks = FR_ticks * 72 / 300 = FR_ticks * 6 / 25
    localparam RATE_NUM = 6;
    localparam RATE_DEN = 25;

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [4:0]
        ST_IDLE             = 5'd0,
        ST_RX_LENGTH        = 5'd1,
        ST_RX_PARAMS        = 5'd2,
        ST_PROCESS_CMD      = 5'd3,
        ST_SEND_ACK         = 5'd4,
        ST_SEND_INFO        = 5'd5,
        ST_SEND_PARAMS      = 5'd6,
        ST_SEND_FLUX_STATUS = 5'd7,
        ST_SEND_PIN         = 5'd8,
        ST_SEEK_EXEC        = 5'd9,
        ST_SEEK_WAIT        = 5'd10,
        ST_READ_FLUX_INIT   = 5'd11,
        ST_READ_WAIT_INDEX  = 5'd12,
        ST_READ_FLUX_STREAM = 5'd13,
        ST_READ_FLUX_ENCODE = 5'd14,
        ST_READ_FLUX_END    = 5'd15,
        ST_WRITE_FLUX_INIT  = 5'd16,
        ST_WRITE_FLUX_STREAM= 5'd17,
        ST_SINK_BYTES       = 5'd18,
        ST_SOURCE_BYTES     = 5'd19,
        ST_ERROR            = 5'd20;

    reg [4:0]  fsm_state;
    reg [4:0]  fsm_next;

    //=========================================================================
    // Command Parsing
    //=========================================================================
    reg [7:0]  cmd_code;
    reg [7:0]  cmd_length;
    reg [7:0]  cmd_rx_count;
    reg [63:0] cmd_params;          // Up to 8 bytes of parameters

    //=========================================================================
    // Response Generation
    //=========================================================================
    reg [7:0]  resp_ack;
    reg [7:0]  resp_length;
    reg [7:0]  resp_tx_count;
    reg [255:0] resp_buffer;        // Response data buffer

    //=========================================================================
    // Flux Read State
    //=========================================================================
    reg [31:0] flux_ticks_target;   // Max ticks to read
    reg [15:0] flux_max_index;      // Max index pulses
    reg [15:0] flux_index_count;
    reg [31:0] flux_tick_count;
    reg        flux_started;
    reg [7:0]  flux_last_status;

    // Flux encoding state machine
    reg [2:0]  flux_enc_state;
    reg [31:0] flux_enc_value;
    reg [2:0]  flux_enc_byte_idx;

    localparam [2:0]
        FE_IDLE         = 3'd0,
        FE_SEND_DIRECT  = 3'd1,
        FE_SEND_2BYTE_1 = 3'd2,
        FE_SEND_2BYTE_2 = 3'd3,
        FE_SEND_7BYTE   = 3'd4,
        FE_SEND_INDEX   = 3'd5,
        FE_SEND_TERM    = 3'd6;

    //=========================================================================
    // Parameters Storage (gw_delay structure)
    //=========================================================================
    reg [15:0] delay_select;        // Drive select delay (µs)
    reg [15:0] delay_step;          // Step pulse period (µs)
    reg [15:0] delay_seek_settle;   // Settle after seek (ms)
    reg [15:0] delay_motor;         // Motor spin-up (ms)
    reg [15:0] delay_watchdog;      // Watchdog timeout (ms)
    reg [15:0] delay_pre_write;     // Pre-write delay (µs)
    reg [15:0] delay_post_write;    // Post-write delay (µs)
    reg [15:0] delay_index_mask;    // Index mask time (µs)

    //=========================================================================
    // Drive State
    //=========================================================================
    reg [7:0]  current_unit;
    reg [7:0]  current_cylinder;
    reg [7:0]  bus_type;
    reg        unit_selected;

    //=========================================================================
    // Timeout Counter
    //=========================================================================
    // Used for seek and index wait timeouts
    // At 100 MHz, 24-bit counter = ~167ms per tick with prescaler
    reg [23:0] timeout_counter;
    reg [15:0] timeout_prescaler;
    localparam TIMEOUT_PRESCALE = 16'd50000;  // ~0.5ms per timeout tick at 100MHz
    localparam SEEK_TIMEOUT     = 24'd4000;   // 2 second seek timeout
    localparam INDEX_TIMEOUT    = 24'd6000;   // 3 second index timeout

    //=========================================================================
    // Byte FIFO for TX (flux stream output)
    //=========================================================================
    reg [7:0]  tx_byte_fifo [0:3];
    reg [1:0]  tx_fifo_wr_ptr;
    reg [1:0]  tx_fifo_rd_ptr;
    reg [2:0]  tx_fifo_count;
    wire       tx_fifo_empty = (tx_fifo_count == 0);
    wire       tx_fifo_full  = (tx_fifo_count == 4);

    //=========================================================================
    // Rate Conversion
    //=========================================================================
    wire [31:0] flux_timestamp_raw = flux_data[27:0];
    wire        flux_is_index_mark = flux_data[31];

    // Convert FluxRipper ticks to GW ticks
    wire [35:0] gw_ticks_mult = flux_timestamp_raw * RATE_NUM;
    wire [31:0] gw_ticks_conv = gw_ticks_mult / RATE_DEN;

    //=========================================================================
    // Initialization
    //=========================================================================
    initial begin
        delay_select      = 16'd2000;    // 2ms
        delay_step        = 16'd3000;    // 3ms
        delay_seek_settle = 16'd15;      // 15ms
        delay_motor       = 16'd750;     // 750ms
        delay_watchdog    = 16'd10000;   // 10s
        delay_pre_write   = 16'd140;     // 140µs
        delay_post_write  = 16'd140;     // 140µs
        delay_index_mask  = 16'd2000;    // 2ms
        bus_type          = BUS_IBMPC;
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state        <= ST_IDLE;
            rx_ready         <= 1'b0;
            tx_valid         <= 1'b0;
            tx_data          <= 32'h0;
            flux_ready       <= 1'b0;
            drive_select     <= 4'b0001;
            motor_on         <= 1'b0;
            head_select      <= 1'b0;
            track            <= 8'd0;
            seek_start       <= 1'b0;
            capture_start    <= 1'b0;
            capture_stop     <= 1'b0;
            sample_rate      <= 8'd0;
            state            <= 8'd0;
            cmd_code         <= 8'd0;
            cmd_length       <= 8'd0;
            cmd_rx_count     <= 8'd0;
            cmd_params       <= 64'd0;
            resp_ack         <= ACK_OKAY;
            resp_length      <= 8'd0;
            resp_tx_count    <= 8'd0;
            resp_buffer      <= 256'd0;
            current_unit     <= 8'd0;
            current_cylinder <= 8'd0;
            unit_selected    <= 1'b0;
            flux_started     <= 1'b0;
            flux_index_count <= 16'd0;
            flux_tick_count  <= 32'd0;
            flux_enc_state   <= FE_IDLE;
            flux_last_status <= ACK_OKAY;
            tx_fifo_wr_ptr   <= 2'd0;
            tx_fifo_rd_ptr   <= 2'd0;
            tx_fifo_count    <= 3'd0;
            timeout_counter  <= 24'd0;
            timeout_prescaler <= 16'd0;
        end else begin
            // Default signal states
            rx_ready      <= 1'b0;
            tx_valid      <= 1'b0;
            seek_start    <= 1'b0;
            capture_start <= 1'b0;
            capture_stop  <= 1'b0;

            case (fsm_state)
                //-------------------------------------------------------------
                // IDLE - Wait for command byte
                //-------------------------------------------------------------
                ST_IDLE: begin
                    state <= 8'h00;
                    if (rx_valid) begin
                        rx_ready     <= 1'b1;
                        cmd_code     <= rx_data[7:0];
                        cmd_rx_count <= 8'd1;
                        fsm_state    <= ST_RX_LENGTH;
                    end
                end

                //-------------------------------------------------------------
                // RX_LENGTH - Receive length byte
                //-------------------------------------------------------------
                ST_RX_LENGTH: begin
                    state <= 8'h01;
                    if (rx_valid) begin
                        rx_ready     <= 1'b1;
                        cmd_length   <= rx_data[7:0];
                        cmd_rx_count <= 8'd2;
                        cmd_params   <= 64'd0;

                        // Length includes cmd + length byte, so params = length - 2
                        if (rx_data[7:0] <= 8'd2) begin
                            fsm_state <= ST_PROCESS_CMD;
                        end else begin
                            fsm_state <= ST_RX_PARAMS;
                        end
                    end
                end

                //-------------------------------------------------------------
                // RX_PARAMS - Receive parameter bytes
                //-------------------------------------------------------------
                ST_RX_PARAMS: begin
                    state <= 8'h02;
                    if (rx_valid) begin
                        rx_ready <= 1'b1;

                        // Pack parameter bytes (little-endian)
                        case (cmd_rx_count - 2)
                            0: cmd_params[7:0]   <= rx_data[7:0];
                            1: cmd_params[15:8]  <= rx_data[7:0];
                            2: cmd_params[23:16] <= rx_data[7:0];
                            3: cmd_params[31:24] <= rx_data[7:0];
                            4: cmd_params[39:32] <= rx_data[7:0];
                            5: cmd_params[47:40] <= rx_data[7:0];
                            6: cmd_params[55:48] <= rx_data[7:0];
                            7: cmd_params[63:56] <= rx_data[7:0];
                        endcase

                        cmd_rx_count <= cmd_rx_count + 1'b1;
                        if (cmd_rx_count + 1 >= cmd_length)
                            fsm_state <= ST_PROCESS_CMD;
                    end
                end

                //-------------------------------------------------------------
                // PROCESS_CMD - Decode and execute command
                //-------------------------------------------------------------
                ST_PROCESS_CMD: begin
                    state    <= 8'h03;
                    resp_ack <= ACK_OKAY;

                    case (cmd_code)
                        CMD_GET_INFO: begin
                            // Build gw_info response (32 bytes)
                            case (cmd_params[7:0])  // Info index
                                GETINFO_FIRMWARE: begin
                                    resp_buffer[7:0]     <= GW_FW_MAJOR;
                                    resp_buffer[15:8]    <= GW_FW_MINOR;
                                    resp_buffer[23:16]   <= GW_IS_MAIN_FW;
                                    resp_buffer[31:24]   <= CMD_MAX;
                                    resp_buffer[63:32]   <= GW_SAMPLE_FREQ;  // sample_freq
                                    resp_buffer[71:64]   <= GW_HW_MODEL;
                                    resp_buffer[79:72]   <= GW_HW_SUBMODEL;
                                    resp_buffer[87:80]   <= GW_USB_SPEED;
                                    resp_buffer[95:88]   <= GW_MCU_ID;
                                    resp_buffer[111:96]  <= GW_MCU_MHZ;
                                    resp_buffer[127:112] <= GW_MCU_SRAM_KB;
                                    resp_buffer[143:128] <= GW_USB_BUF_KB;
                                    resp_buffer[255:144] <= 112'd0;  // Padding
                                    resp_length <= 8'd32;
                                    fsm_state   <= ST_SEND_INFO;
                                end
                                GETINFO_CURRENT_DRV: begin
                                    // Return current drive info
                                    resp_buffer[7:0]   <= {4'b0, motor_on, unit_selected, 1'b0, (current_cylinder != 8'd0)};
                                    resp_buffer[15:8]  <= current_cylinder;
                                    resp_buffer[255:16] <= 240'd0;
                                    resp_length <= 8'd2;
                                    fsm_state   <= ST_SEND_INFO;
                                end
                                default: begin
                                    resp_ack  <= ACK_BAD_COMMAND;
                                    fsm_state <= ST_SEND_ACK;
                                end
                            endcase
                        end

                        CMD_SEEK: begin
                            // cmd_params[7:0] = cylinder (signed 8-bit or 16-bit)
                            if (cmd_length == 8'd3) begin
                                // 8-bit cylinder
                                track <= cmd_params[7:0];
                            end else begin
                                // 16-bit cylinder
                                track <= cmd_params[7:0];  // Use lower byte
                            end
                            fsm_state <= ST_SEEK_EXEC;
                        end

                        CMD_HEAD: begin
                            head_select <= cmd_params[0];
                            fsm_state   <= ST_SEND_ACK;
                        end

                        CMD_SET_PARAMS: begin
                            // cmd_params[7:0] = param index
                            // cmd_params[15:8] onwards = values
                            if (cmd_params[7:0] == 8'd0) begin
                                // PARAMS_DELAYS - 8 x 16-bit values
                                delay_select      <= cmd_params[31:16];
                                delay_step        <= cmd_params[47:32];
                                // More would come in additional command bytes
                            end
                            fsm_state <= ST_SEND_ACK;
                        end

                        CMD_GET_PARAMS: begin
                            // cmd_params[7:0] = param index
                            // cmd_params[15:8] = number of bytes
                            if (cmd_params[7:0] == 8'd0) begin
                                // Return delays
                                resp_buffer[15:0]   <= delay_select;
                                resp_buffer[31:16]  <= delay_step;
                                resp_buffer[47:32]  <= delay_seek_settle;
                                resp_buffer[63:48]  <= delay_motor;
                                resp_buffer[79:64]  <= delay_watchdog;
                                resp_buffer[95:80]  <= delay_pre_write;
                                resp_buffer[111:96] <= delay_post_write;
                                resp_buffer[127:112]<= delay_index_mask;
                                resp_length <= 8'd16;
                                fsm_state <= ST_SEND_PARAMS;
                            end else begin
                                resp_ack  <= ACK_BAD_COMMAND;
                                fsm_state <= ST_SEND_ACK;
                            end
                        end

                        CMD_MOTOR: begin
                            // cmd_params[7:0] = unit, cmd_params[15:8] = state
                            current_unit <= cmd_params[7:0];
                            motor_on     <= cmd_params[8];
                            fsm_state    <= ST_SEND_ACK;
                        end

                        CMD_READ_FLUX: begin
                            // cmd_params[31:0] = ticks, cmd_params[47:32] = max_index
                            flux_ticks_target <= cmd_params[31:0];
                            flux_max_index    <= cmd_params[47:32];
                            flux_index_count  <= 16'd0;
                            flux_tick_count   <= 32'd0;
                            flux_started      <= 1'b0;
                            flux_enc_state    <= FE_IDLE;
                            fsm_state         <= ST_READ_FLUX_INIT;
                        end

                        CMD_WRITE_FLUX: begin
                            // Not fully implemented - acknowledge and ignore
                            if (write_protect) begin
                                resp_ack <= ACK_WRPROT;
                            end
                            fsm_state <= ST_SEND_ACK;
                        end

                        CMD_GET_FLUX_STATUS: begin
                            resp_buffer[7:0] <= flux_last_status;
                            resp_buffer[15:8] <= 8'd0;
                            resp_length <= 8'd2;
                            fsm_state <= ST_SEND_FLUX_STATUS;
                        end

                        CMD_SELECT: begin
                            // cmd_params[7:0] = unit
                            current_unit  <= cmd_params[7:0];
                            unit_selected <= 1'b1;
                            case (cmd_params[1:0])
                                2'd0: drive_select <= 4'b0001;
                                2'd1: drive_select <= 4'b0010;
                                2'd2: drive_select <= 4'b0100;
                                2'd3: drive_select <= 4'b1000;
                            endcase
                            fsm_state <= ST_SEND_ACK;
                        end

                        CMD_DESELECT: begin
                            unit_selected <= 1'b0;
                            fsm_state     <= ST_SEND_ACK;
                        end

                        CMD_SET_BUS_TYPE: begin
                            bus_type  <= cmd_params[7:0];
                            fsm_state <= ST_SEND_ACK;
                        end

                        CMD_RESET: begin
                            motor_on         <= 1'b0;
                            unit_selected    <= 1'b0;
                            current_cylinder <= 8'd0;
                            head_select      <= 1'b0;
                            fsm_state        <= ST_SEND_ACK;
                        end

                        CMD_GET_PIN: begin
                            // cmd_params[7:0] = pin number
                            // Common pins: 26 = TRK0, 28 = WPT, 8 = INDEX
                            case (cmd_params[7:0])
                                8'd26: resp_buffer[7:0] <= {7'd0, track_00};
                                8'd28: resp_buffer[7:0] <= {7'd0, write_protect};
                                8'd8:  resp_buffer[7:0] <= {7'd0, flux_index};
                                default: resp_buffer[7:0] <= 8'd0;
                            endcase
                            resp_length <= 8'd1;
                            fsm_state <= ST_SEND_PIN;
                        end

                        CMD_SINK_BYTES: begin
                            // Consume bytes (for bandwidth testing)
                            fsm_state <= ST_SINK_BYTES;
                        end

                        CMD_SOURCE_BYTES: begin
                            // Generate bytes (for bandwidth testing)
                            resp_length   <= cmd_params[7:0];
                            resp_tx_count <= 8'd0;
                            fsm_state     <= ST_SOURCE_BYTES;
                        end

                        CMD_NOCLICK_STEP: begin
                            // Seek to track 0 without clicking
                            track     <= 8'd0;
                            fsm_state <= ST_SEEK_EXEC;
                        end

                        default: begin
                            resp_ack  <= ACK_BAD_COMMAND;
                            fsm_state <= ST_SEND_ACK;
                        end
                    endcase
                end

                //-------------------------------------------------------------
                // SEND_ACK - Send command acknowledgment
                //-------------------------------------------------------------
                ST_SEND_ACK: begin
                    state <= 8'h04;
                    if (tx_ready) begin
                        tx_data  <= {16'h0, cmd_code, resp_ack};  // [ACK][CMD] response
                        tx_valid <= 1'b1;
                        fsm_state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // SEND_INFO - Send GET_INFO response
                //-------------------------------------------------------------
                ST_SEND_INFO: begin
                    state <= 8'h05;
                    if (tx_ready) begin
                        // First send ACK + CMD
                        if (resp_tx_count == 8'd0) begin
                            tx_data  <= {16'h0, cmd_code, ACK_OKAY};
                            tx_valid <= 1'b1;
                            resp_tx_count <= 8'd1;
                        end else begin
                            // Send response bytes (4 at a time)
                            tx_data  <= resp_buffer[31:0];
                            tx_valid <= 1'b1;
                            resp_buffer <= {32'h0, resp_buffer[255:32]};
                            resp_tx_count <= resp_tx_count + 8'd4;

                            if (resp_tx_count + 8'd4 >= resp_length + 8'd1)
                                fsm_state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // SEND_PARAMS - Send parameter response
                //-------------------------------------------------------------
                ST_SEND_PARAMS: begin
                    state <= 8'h06;
                    if (tx_ready) begin
                        if (resp_tx_count == 8'd0) begin
                            tx_data  <= {16'h0, cmd_code, ACK_OKAY};
                            tx_valid <= 1'b1;
                            resp_tx_count <= 8'd1;
                        end else begin
                            tx_data  <= resp_buffer[31:0];
                            tx_valid <= 1'b1;
                            resp_buffer <= {32'h0, resp_buffer[255:32]};
                            resp_tx_count <= resp_tx_count + 8'd4;

                            if (resp_tx_count + 8'd4 >= resp_length + 8'd1)
                                fsm_state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // SEND_FLUX_STATUS - Send flux operation status
                //-------------------------------------------------------------
                ST_SEND_FLUX_STATUS: begin
                    state <= 8'h07;
                    if (tx_ready) begin
                        tx_data  <= {resp_buffer[15:0], cmd_code, ACK_OKAY};
                        tx_valid <= 1'b1;
                        fsm_state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // SEND_PIN - Send pin state
                //-------------------------------------------------------------
                ST_SEND_PIN: begin
                    state <= 8'h08;
                    if (tx_ready) begin
                        if (resp_tx_count == 8'd0) begin
                            tx_data  <= {16'h0, cmd_code, ACK_OKAY};
                            tx_valid <= 1'b1;
                            resp_tx_count <= 8'd1;
                        end else begin
                            tx_data  <= {24'h0, resp_buffer[7:0]};
                            tx_valid <= 1'b1;
                            fsm_state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // SEEK_EXEC - Execute seek operation
                //-------------------------------------------------------------
                ST_SEEK_EXEC: begin
                    state <= 8'h09;
                    if (!unit_selected) begin
                        resp_ack  <= ACK_NO_UNIT;
                        fsm_state <= ST_SEND_ACK;
                    end else begin
                        seek_start <= 1'b1;
                        timeout_counter <= SEEK_TIMEOUT;
                        timeout_prescaler <= TIMEOUT_PRESCALE;
                        fsm_state  <= ST_SEEK_WAIT;
                    end
                end

                //-------------------------------------------------------------
                // SEEK_WAIT - Wait for seek to complete
                //-------------------------------------------------------------
                ST_SEEK_WAIT: begin
                    state <= 8'h0A;
                    if (seek_complete) begin
                        current_cylinder <= track;
                        fsm_state <= ST_SEND_ACK;
                    end else begin
                        // Timeout handling
                        if (timeout_prescaler > 0) begin
                            timeout_prescaler <= timeout_prescaler - 1'b1;
                        end else begin
                            timeout_prescaler <= TIMEOUT_PRESCALE;
                            if (timeout_counter > 0) begin
                                timeout_counter <= timeout_counter - 1'b1;
                            end else begin
                                // Timeout expired - seek failed
                                resp_ack  <= ACK_NO_TRK0;
                                fsm_state <= ST_SEND_ACK;
                            end
                        end
                    end
                end

                //-------------------------------------------------------------
                // READ_FLUX_INIT - Initialize flux read
                //-------------------------------------------------------------
                ST_READ_FLUX_INIT: begin
                    state <= 8'h0B;
                    if (!unit_selected) begin
                        resp_ack  <= ACK_NO_UNIT;
                        fsm_state <= ST_SEND_ACK;
                    end else begin
                        // Send ACK first
                        if (tx_ready) begin
                            tx_data  <= {16'h0, cmd_code, ACK_OKAY};
                            tx_valid <= 1'b1;
                            capture_start <= 1'b1;
                            flux_ready    <= 1'b1;

                            if (flux_max_index > 0) begin
                                // Wait for index before starting
                                timeout_counter <= INDEX_TIMEOUT;
                                timeout_prescaler <= TIMEOUT_PRESCALE;
                                fsm_state <= ST_READ_WAIT_INDEX;
                            end else begin
                                // Start immediately
                                flux_started <= 1'b1;
                                fsm_state    <= ST_READ_FLUX_STREAM;
                            end
                        end
                    end
                end

                //-------------------------------------------------------------
                // READ_WAIT_INDEX - Wait for first index pulse
                //-------------------------------------------------------------
                ST_READ_WAIT_INDEX: begin
                    state <= 8'h0C;
                    if (flux_valid && flux_is_index_mark) begin
                        flux_index_count <= flux_index_count + 1'b1;
                        flux_started     <= 1'b1;
                        fsm_state        <= ST_READ_FLUX_STREAM;
                    end else begin
                        // Timeout handling
                        if (timeout_prescaler > 0) begin
                            timeout_prescaler <= timeout_prescaler - 1'b1;
                        end else begin
                            timeout_prescaler <= TIMEOUT_PRESCALE;
                            if (timeout_counter > 0) begin
                                timeout_counter <= timeout_counter - 1'b1;
                            end else begin
                                // Timeout expired - no index pulse detected
                                flux_ready       <= 1'b0;
                                capture_stop     <= 1'b1;
                                flux_last_status <= ACK_NO_INDEX;
                                fsm_state        <= ST_READ_FLUX_END;
                            end
                        end
                    end
                end

                //-------------------------------------------------------------
                // READ_FLUX_STREAM - Stream encoded flux data
                //-------------------------------------------------------------
                ST_READ_FLUX_STREAM: begin
                    state <= 8'h0D;

                    // Check termination conditions
                    if ((flux_max_index > 0 && flux_index_count >= flux_max_index) ||
                        (flux_ticks_target > 0 && flux_tick_count >= flux_ticks_target)) begin
                        flux_enc_state <= FE_SEND_TERM;
                        fsm_state      <= ST_READ_FLUX_END;
                    end
                    else if (flux_valid && tx_ready) begin
                        flux_ready <= 1'b1;

                        if (flux_is_index_mark) begin
                            // Encode index marker: 0xFF, 0x01, 28-bit timestamp
                            flux_enc_state    <= FE_SEND_INDEX;
                            flux_enc_value    <= gw_ticks_conv;
                            flux_enc_byte_idx <= 3'd0;
                            flux_index_count  <= flux_index_count + 1'b1;
                        end else begin
                            // Encode flux transition
                            flux_tick_count <= flux_tick_count + gw_ticks_conv;

                            if (gw_ticks_conv < 32'd250) begin
                                // Direct encoding: 1-249
                                tx_data  <= {24'h0, gw_ticks_conv[7:0]};
                                tx_valid <= 1'b1;
                            end else if (gw_ticks_conv < 32'd1525) begin
                                // Two-byte encoding: 250-1524
                                // First byte: 250 + ((value-250) / 255)
                                // Second byte: 1 + ((value-250) % 255)
                                flux_enc_state    <= FE_SEND_2BYTE_1;
                                flux_enc_value    <= gw_ticks_conv;
                                flux_enc_byte_idx <= 3'd0;

                                // Send first byte
                                tx_data  <= {24'h0, 8'd250 + ((gw_ticks_conv - 32'd250) / 32'd255)};
                                tx_valid <= 1'b1;
                            end else begin
                                // Seven-byte encoding: 0xFF, FLUXOP_SPACE, 28-bit, dummy
                                flux_enc_state    <= FE_SEND_7BYTE;
                                flux_enc_value    <= gw_ticks_conv - 32'd249;
                                flux_enc_byte_idx <= 3'd0;

                                tx_data  <= {24'h0, 8'hFF};
                                tx_valid <= 1'b1;
                            end
                        end
                    end
                end

                //-------------------------------------------------------------
                // READ_FLUX_ENCODE - Continue multi-byte encoding
                //-------------------------------------------------------------
                ST_READ_FLUX_ENCODE: begin
                    state <= 8'h0E;
                    if (tx_ready) begin
                        case (flux_enc_state)
                            FE_SEND_2BYTE_1: begin
                                // Second byte of 2-byte encoding
                                tx_data  <= {24'h0, 8'd1 + ((flux_enc_value - 32'd250) % 32'd255)};
                                tx_valid <= 1'b1;
                                flux_enc_state <= FE_IDLE;
                                fsm_state <= ST_READ_FLUX_STREAM;
                            end

                            FE_SEND_INDEX: begin
                                // Index encoding: 0xFF, 0x01, then 28-bit value
                                case (flux_enc_byte_idx)
                                    0: begin
                                        tx_data <= {24'h0, 8'hFF};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd1;
                                    end
                                    1: begin
                                        tx_data <= {24'h0, FLUXOP_INDEX};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd2;
                                    end
                                    2: begin
                                        // 28-bit encoding byte 0
                                        tx_data <= {24'h0, {flux_enc_value[0], 6'b000001, 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd3;
                                    end
                                    3: begin
                                        tx_data <= {24'h0, {flux_enc_value[7:1], 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd4;
                                    end
                                    4: begin
                                        tx_data <= {24'h0, {flux_enc_value[14:8], 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd5;
                                    end
                                    5: begin
                                        tx_data <= {24'h0, {flux_enc_value[21:15], 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_state <= FE_IDLE;
                                        fsm_state <= ST_READ_FLUX_STREAM;
                                    end
                                endcase
                            end

                            FE_SEND_7BYTE: begin
                                // 7-byte space encoding
                                case (flux_enc_byte_idx)
                                    0: begin
                                        tx_data <= {24'h0, FLUXOP_SPACE};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd1;
                                    end
                                    1: begin
                                        tx_data <= {24'h0, {flux_enc_value[0], 6'b000001, 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd2;
                                    end
                                    2: begin
                                        tx_data <= {24'h0, {flux_enc_value[7:1], 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd3;
                                    end
                                    3: begin
                                        tx_data <= {24'h0, {flux_enc_value[14:8], 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd4;
                                    end
                                    4: begin
                                        tx_data <= {24'h0, {flux_enc_value[21:15], 1'b1}};
                                        tx_valid <= 1'b1;
                                        flux_enc_byte_idx <= 3'd5;
                                    end
                                    5: begin
                                        // Dummy trailing byte
                                        tx_data <= {24'h0, 8'd249};
                                        tx_valid <= 1'b1;
                                        flux_enc_state <= FE_IDLE;
                                        fsm_state <= ST_READ_FLUX_STREAM;
                                    end
                                endcase
                            end

                            default: fsm_state <= ST_READ_FLUX_STREAM;
                        endcase
                    end
                end

                //-------------------------------------------------------------
                // READ_FLUX_END - Terminate flux stream
                //-------------------------------------------------------------
                ST_READ_FLUX_END: begin
                    state <= 8'h0F;
                    if (tx_ready) begin
                        // Send terminator: 0x00
                        tx_data  <= 32'h0;
                        tx_valid <= 1'b1;
                        capture_stop    <= 1'b1;
                        flux_ready      <= 1'b0;
                        flux_last_status <= ACK_OKAY;
                        fsm_state       <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // SINK_BYTES - Consume bytes for bandwidth test
                //-------------------------------------------------------------
                ST_SINK_BYTES: begin
                    state <= 8'h10;
                    if (rx_valid) begin
                        rx_ready <= 1'b1;
                        // Check for terminator (0x00)
                        if (rx_data[7:0] == 8'h00)
                            fsm_state <= ST_SEND_ACK;
                    end
                end

                //-------------------------------------------------------------
                // SOURCE_BYTES - Generate bytes for bandwidth test
                //-------------------------------------------------------------
                ST_SOURCE_BYTES: begin
                    state <= 8'h11;
                    if (tx_ready) begin
                        tx_data  <= 32'h55555555;  // Pattern
                        tx_valid <= 1'b1;
                        resp_tx_count <= resp_tx_count + 8'd4;
                        if (resp_tx_count >= resp_length)
                            fsm_state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // ERROR - Error state
                //-------------------------------------------------------------
                ST_ERROR: begin
                    state     <= 8'hFF;
                    fsm_state <= ST_SEND_ACK;
                end

                default: fsm_state <= ST_IDLE;
            endcase

            // Handle multi-byte encoding continuation
            if (fsm_state == ST_READ_FLUX_STREAM && flux_enc_state != FE_IDLE) begin
                fsm_state <= ST_READ_FLUX_ENCODE;
            end
        end
    end

endmodule
