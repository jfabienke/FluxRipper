/**
 * FluxRipper USB Traffic Logger
 *
 * Non-intrusive USB 2.0 traffic capture for debugging and diagnostics.
 * Captures tokens, data packets, and handshakes to a ring buffer in BRAM.
 * Compatible with PCAP export for analysis in Wireshark/Packetry.
 *
 * Architecture:
 *   - Taps UTMI+ signals from usb_device_core_v2 (non-intrusive)
 *   - 8KB ring buffer (configurable) stores compressed transactions
 *   - Hardware timestamps at 60 MHz (16.67 ns resolution)
 *   - Configurable filters by endpoint, direction, packet type
 *   - AXI-Lite register interface for firmware access
 *
 * Transaction Record Format (variable length, 4-32 bytes):
 *   [0]     : Header byte (type[3:0], dir[1], ep[3:0] >> 1, flags[2:0])
 *   [1-4]   : Timestamp (32-bit, relative to capture start)
 *   [5]     : Length (0-64 for data, 0 for tokens/handshakes)
 *   [6-69]  : Payload (for DATA packets only)
 *
 * Created: 2025-12-07 12:15
 * License: BSD-3-Clause
 */

module usb_traffic_logger #(
    parameter BUFFER_DEPTH_LOG2 = 13,   // 8KB buffer (2^13 bytes)
    parameter CLK_FREQ_HZ       = 60000000  // 60 MHz ULPI clock
)(
    input  wire        clk,              // ULPI clock (60 MHz)
    input  wire        rst_n,

    // =========================================================================
    // UTMI+ Tap Interface (directly from ulpi_wrapper or usb_device_core)
    // =========================================================================
    input  wire [7:0]  utmi_rx_data,     // Received data byte
    input  wire        utmi_rx_valid,    // RX data valid
    input  wire        utmi_rx_active,   // RX active (packet in progress)
    input  wire [7:0]  utmi_tx_data,     // Transmitted data byte
    input  wire        utmi_tx_valid,    // TX data valid
    input  wire        utmi_tx_ready,    // TX ready (data accepted)
    input  wire [1:0]  utmi_line_state,  // D+/D- state

    // =========================================================================
    // AXI-Lite Register Interface
    // =========================================================================
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_we,
    input  wire        reg_re,
    output reg  [31:0] reg_rdata,
    output reg         reg_rvalid,

    // =========================================================================
    // Status Outputs
    // =========================================================================
    output wire        capture_active,
    output wire        buffer_overflow,
    output wire [31:0] transaction_count
);

    // =========================================================================
    // Register Map
    // =========================================================================
    localparam REG_CONTROL      = 8'h00;  // [0]=enable, [1]=clear, [2]=wrap_mode
    localparam REG_STATUS       = 8'h04;  // [0]=active, [1]=overflow, [2]=wrapped
    localparam REG_FILTER       = 8'h08;  // [3:0]=ep_mask, [4]=dir_filter, [7:5]=type_mask
    localparam REG_WRITE_PTR    = 8'h0C;  // Current write pointer
    localparam REG_READ_PTR     = 8'h10;  // Current read pointer
    localparam REG_TRANS_COUNT  = 8'h14;  // Transaction counter
    localparam REG_TIMESTAMP_LO = 8'h18;  // Current timestamp low
    localparam REG_TIMESTAMP_HI = 8'h1C;  // Current timestamp high
    localparam REG_BUFFER_DATA  = 8'h20;  // Read buffer data (auto-increment)
    localparam REG_BUFFER_SIZE  = 8'h24;  // Buffer size in bytes
    localparam REG_TRIGGER      = 8'h28;  // [7:0]=trigger_pid, [8]=trigger_enable

    // =========================================================================
    // Packet Type Definitions (USB PIDs)
    // =========================================================================
    localparam PID_OUT   = 4'b0001;
    localparam PID_IN    = 4'b1001;
    localparam PID_SOF   = 4'b0101;
    localparam PID_SETUP = 4'b1101;
    localparam PID_DATA0 = 4'b0011;
    localparam PID_DATA1 = 4'b1011;
    localparam PID_DATA2 = 4'b0111;
    localparam PID_MDATA = 4'b1111;
    localparam PID_ACK   = 4'b0010;
    localparam PID_NAK   = 4'b1010;
    localparam PID_STALL = 4'b1110;
    localparam PID_NYET  = 4'b0110;
    localparam PID_PRE   = 4'b1100;
    localparam PID_SPLIT = 4'b1000;
    localparam PID_PING  = 4'b0100;

    // Internal record type encoding (compressed)
    localparam REC_TOKEN     = 3'd0;  // OUT/IN/SETUP/PING token
    localparam REC_SOF       = 3'd1;  // Start of Frame
    localparam REC_DATA      = 3'd2;  // DATA0/DATA1/DATA2/MDATA
    localparam REC_HANDSHAKE = 3'd3;  // ACK/NAK/STALL/NYET
    localparam REC_SPECIAL   = 3'd4;  // PRE/SPLIT/ERR
    localparam REC_BUS_EVENT = 3'd5;  // Reset/Suspend/Resume

    // =========================================================================
    // Control Registers
    // =========================================================================
    reg        ctrl_enable;
    reg        ctrl_wrap_mode;     // 0=stop on full, 1=wrap around
    reg [3:0]  filter_ep_mask;     // Which endpoints to capture (bitmask)
    reg        filter_dir;         // 0=both, 1=filter by filter_dir_val
    reg        filter_dir_val;     // 0=OUT only, 1=IN only
    reg [2:0]  filter_type_mask;   // [0]=tokens, [1]=data, [2]=handshakes
    reg [7:0]  trigger_pid;
    reg        trigger_enable;
    reg        triggered;

    // =========================================================================
    // Buffer Memory (Dual-Port BRAM)
    // =========================================================================
    localparam BUFFER_SIZE = (1 << BUFFER_DEPTH_LOG2);

    reg [7:0] buffer_mem [0:BUFFER_SIZE-1];

    reg [BUFFER_DEPTH_LOG2-1:0] write_ptr;
    reg [BUFFER_DEPTH_LOG2-1:0] read_ptr;
    reg                         overflow_flag;
    reg                         wrapped_flag;
    reg [31:0]                  trans_count;

    // =========================================================================
    // Timestamp Counter (free-running)
    // =========================================================================
    reg [47:0] timestamp;
    reg [31:0] capture_start_time;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timestamp <= 48'd0;
        end else begin
            timestamp <= timestamp + 1'b1;
        end
    end

    // =========================================================================
    // RX Packet State Machine
    // =========================================================================
    localparam RX_IDLE      = 3'd0;
    localparam RX_PID       = 3'd1;
    localparam RX_TOKEN     = 3'd2;
    localparam RX_DATA      = 3'd3;
    localparam RX_HANDSHAKE = 3'd4;
    localparam RX_SOF       = 3'd5;
    localparam RX_COMPLETE  = 3'd6;

    reg [2:0]  rx_state;
    reg [7:0]  rx_pid;
    reg [7:0]  rx_buffer [0:71];   // Max 64 data + 8 header
    reg [6:0]  rx_byte_count;
    reg [10:0] rx_token_data;      // addr[6:0] + ep[3:0]
    reg        rx_direction;       // 0=OUT, 1=IN
    reg [3:0]  rx_endpoint;
    reg [31:0] rx_timestamp;
    reg        rx_packet_valid;

    // PID decode
    wire [3:0] pid_type = rx_pid[3:0];
    wire       pid_valid = (rx_pid[3:0] == ~rx_pid[7:4]);

    wire is_token_pid = (pid_type == PID_OUT) || (pid_type == PID_IN) ||
                        (pid_type == PID_SETUP) || (pid_type == PID_PING);
    wire is_data_pid  = (pid_type == PID_DATA0) || (pid_type == PID_DATA1) ||
                        (pid_type == PID_DATA2) || (pid_type == PID_MDATA);
    wire is_hs_pid    = (pid_type == PID_ACK) || (pid_type == PID_NAK) ||
                        (pid_type == PID_STALL) || (pid_type == PID_NYET);
    wire is_sof_pid   = (pid_type == PID_SOF);

    // RX packet capture FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_pid <= 8'd0;
            rx_byte_count <= 7'd0;
            rx_packet_valid <= 1'b0;
            rx_timestamp <= 32'd0;
            rx_direction <= 1'b0;
            rx_endpoint <= 4'd0;
        end else begin
            rx_packet_valid <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (utmi_rx_active && utmi_rx_valid) begin
                        rx_pid <= utmi_rx_data;
                        rx_timestamp <= timestamp[31:0];
                        rx_byte_count <= 7'd0;
                        rx_state <= RX_PID;
                    end
                end

                RX_PID: begin
                    if (!utmi_rx_active) begin
                        // Single-byte packet (handshake)
                        if (pid_valid && is_hs_pid) begin
                            rx_packet_valid <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else if (utmi_rx_valid) begin
                        rx_buffer[0] <= utmi_rx_data;
                        rx_byte_count <= 7'd1;

                        if (is_token_pid || is_sof_pid) begin
                            rx_state <= RX_TOKEN;
                        end else if (is_data_pid) begin
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;  // Unknown, ignore
                        end
                    end
                end

                RX_TOKEN: begin
                    if (!utmi_rx_active) begin
                        // Token complete (3 bytes: PID + 2 payload)
                        if (rx_byte_count >= 2) begin
                            rx_token_data <= {rx_buffer[1][2:0], rx_buffer[0]};
                            rx_endpoint <= {rx_buffer[1][2:0], rx_buffer[0][7]};
                            rx_direction <= (pid_type == PID_IN);
                            rx_packet_valid <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else if (utmi_rx_valid && rx_byte_count < 7'd3) begin
                        rx_buffer[rx_byte_count] <= utmi_rx_data;
                        rx_byte_count <= rx_byte_count + 1'b1;
                    end
                end

                RX_DATA: begin
                    if (!utmi_rx_active) begin
                        // Data packet complete
                        rx_packet_valid <= 1'b1;
                        rx_state <= RX_IDLE;
                    end else if (utmi_rx_valid && rx_byte_count < 7'd66) begin
                        rx_buffer[rx_byte_count] <= utmi_rx_data;
                        rx_byte_count <= rx_byte_count + 1'b1;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // =========================================================================
    // TX Packet Capture (similar structure, captures what we send)
    // =========================================================================
    reg [2:0]  tx_state;
    reg [7:0]  tx_pid;
    reg [7:0]  tx_buffer [0:71];
    reg [6:0]  tx_byte_count;
    reg [31:0] tx_timestamp;
    reg        tx_packet_valid;
    reg        tx_active_prev;

    // Track TX packet boundaries
    wire tx_start = utmi_tx_valid && utmi_tx_ready && !tx_active_prev;
    wire tx_end   = tx_active_prev && !(utmi_tx_valid && utmi_tx_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= RX_IDLE;
            tx_pid <= 8'd0;
            tx_byte_count <= 7'd0;
            tx_packet_valid <= 1'b0;
            tx_active_prev <= 1'b0;
        end else begin
            tx_active_prev <= utmi_tx_valid && utmi_tx_ready;
            tx_packet_valid <= 1'b0;

            case (tx_state)
                RX_IDLE: begin
                    if (tx_start) begin
                        tx_pid <= utmi_tx_data;
                        tx_timestamp <= timestamp[31:0];
                        tx_byte_count <= 7'd0;
                        tx_state <= RX_PID;
                    end
                end

                RX_PID: begin
                    if (tx_end) begin
                        tx_packet_valid <= 1'b1;
                        tx_state <= RX_IDLE;
                    end else if (utmi_tx_valid && utmi_tx_ready) begin
                        if (tx_byte_count < 7'd66) begin
                            tx_buffer[tx_byte_count] <= utmi_tx_data;
                            tx_byte_count <= tx_byte_count + 1'b1;
                        end
                    end
                end

                default: tx_state <= RX_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Filter Logic
    // =========================================================================
    wire rx_pass_filter;
    wire tx_pass_filter;

    // Check if packet passes endpoint filter
    wire ep_match = (filter_ep_mask == 4'hF) ||  // All endpoints
                    ((1 << rx_endpoint[1:0]) & filter_ep_mask);

    // Check direction filter
    wire dir_match = !filter_dir || (rx_direction == filter_dir_val);

    // Check packet type filter
    wire type_match_rx = (is_token_pid && filter_type_mask[0]) ||
                         (is_data_pid && filter_type_mask[1]) ||
                         (is_hs_pid && filter_type_mask[2]) ||
                         (is_sof_pid && filter_type_mask[0]);

    assign rx_pass_filter = ep_match && dir_match && type_match_rx;
    assign tx_pass_filter = filter_type_mask[1] || filter_type_mask[2];  // TX is mostly data/HS

    // =========================================================================
    // Trigger Logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            triggered <= 1'b0;
        end else if (!ctrl_enable) begin
            triggered <= 1'b0;
        end else if (trigger_enable && !triggered) begin
            if ((rx_packet_valid && rx_pid == trigger_pid) ||
                (tx_packet_valid && tx_pid == trigger_pid)) begin
                triggered <= 1'b1;
                capture_start_time <= timestamp[31:0];
            end
        end else if (!trigger_enable) begin
            triggered <= 1'b1;  // No trigger = always armed
            if (!triggered) capture_start_time <= timestamp[31:0];
        end
    end

    // =========================================================================
    // Buffer Write Logic
    // =========================================================================
    reg [3:0]  wr_state;
    reg [6:0]  wr_byte_idx;
    reg [7:0]  wr_record [0:71];
    reg [6:0]  wr_record_len;
    reg        wr_pending;

    localparam WR_IDLE   = 4'd0;
    localparam WR_HEADER = 4'd1;
    localparam WR_TS0    = 4'd2;
    localparam WR_TS1    = 4'd3;
    localparam WR_TS2    = 4'd4;
    localparam WR_TS3    = 4'd5;
    localparam WR_LEN    = 4'd6;
    localparam WR_DATA   = 4'd7;
    localparam WR_DONE   = 4'd8;

    // Assemble record header byte
    // [7:5] = record type, [4] = direction, [3:0] = endpoint
    wire [7:0] rx_header = {is_hs_pid ? REC_HANDSHAKE :
                            is_data_pid ? REC_DATA :
                            is_sof_pid ? REC_SOF : REC_TOKEN,
                            rx_direction, rx_pid[3:0]};

    wire [7:0] tx_header = {REC_DATA, 1'b0, tx_pid[3:0]};  // TX is usually data/HS

    // Relative timestamp
    wire [31:0] rel_timestamp_rx = rx_timestamp - capture_start_time;
    wire [31:0] rel_timestamp_tx = tx_timestamp - capture_start_time;

    // Calculate bytes available in buffer
    wire [BUFFER_DEPTH_LOG2:0] bytes_used = write_ptr - read_ptr;
    wire [BUFFER_DEPTH_LOG2:0] bytes_free = BUFFER_SIZE - bytes_used;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
            write_ptr <= {BUFFER_DEPTH_LOG2{1'b0}};
            overflow_flag <= 1'b0;
            wrapped_flag <= 1'b0;
            trans_count <= 32'd0;
            wr_pending <= 1'b0;
        end else if (!ctrl_enable) begin
            // Capture disabled - can clear on rising edge
            wr_state <= WR_IDLE;
            wr_pending <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (ctrl_enable && triggered) begin
                        if (rx_packet_valid && rx_pass_filter) begin
                            // Start RX record
                            wr_record[0] <= rx_header;
                            wr_record[1] <= rel_timestamp_rx[7:0];
                            wr_record[2] <= rel_timestamp_rx[15:8];
                            wr_record[3] <= rel_timestamp_rx[23:16];
                            wr_record[4] <= rel_timestamp_rx[31:24];
                            wr_record[5] <= rx_byte_count;  // Payload length

                            // Copy payload for data packets
                            if (is_data_pid && rx_byte_count > 0) begin
                                wr_record_len <= 7'd6 + rx_byte_count;
                            end else begin
                                wr_record_len <= 7'd6;  // Header only
                            end

                            wr_byte_idx <= 7'd0;
                            wr_state <= WR_HEADER;
                            wr_pending <= 1'b1;
                        end else if (tx_packet_valid && tx_pass_filter) begin
                            // Start TX record
                            wr_record[0] <= tx_header | 8'h80;  // Bit 7 = TX direction
                            wr_record[1] <= rel_timestamp_tx[7:0];
                            wr_record[2] <= rel_timestamp_tx[15:8];
                            wr_record[3] <= rel_timestamp_tx[23:16];
                            wr_record[4] <= rel_timestamp_tx[31:24];
                            wr_record[5] <= tx_byte_count;

                            wr_record_len <= 7'd6 + tx_byte_count;
                            wr_byte_idx <= 7'd0;
                            wr_state <= WR_HEADER;
                            wr_pending <= 1'b1;
                        end
                    end
                end

                WR_HEADER, WR_TS0, WR_TS1, WR_TS2, WR_TS3, WR_LEN, WR_DATA: begin
                    // Check for buffer space
                    if (bytes_free < wr_record_len && !ctrl_wrap_mode) begin
                        overflow_flag <= 1'b1;
                        wr_state <= WR_IDLE;
                        wr_pending <= 1'b0;
                    end else begin
                        // Write byte to buffer
                        if (wr_byte_idx < 7'd6) begin
                            buffer_mem[write_ptr] <= wr_record[wr_byte_idx];
                        end else begin
                            // Write payload from rx_buffer or tx_buffer
                            buffer_mem[write_ptr] <= rx_packet_valid ?
                                rx_buffer[wr_byte_idx - 7'd6] :
                                tx_buffer[wr_byte_idx - 7'd6];
                        end

                        write_ptr <= write_ptr + 1'b1;

                        // Track wrap
                        if (write_ptr == {BUFFER_DEPTH_LOG2{1'b1}}) begin
                            wrapped_flag <= 1'b1;
                        end

                        wr_byte_idx <= wr_byte_idx + 1'b1;

                        if (wr_byte_idx + 1'b1 >= wr_record_len) begin
                            wr_state <= WR_DONE;
                        end
                    end
                end

                WR_DONE: begin
                    trans_count <= trans_count + 1'b1;
                    wr_pending <= 1'b0;
                    wr_state <= WR_IDLE;
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Register Interface
    // =========================================================================
    reg clear_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_enable <= 1'b0;
            ctrl_wrap_mode <= 1'b0;
            filter_ep_mask <= 4'hF;
            filter_dir <= 1'b0;
            filter_dir_val <= 1'b0;
            filter_type_mask <= 3'b111;
            trigger_pid <= 8'd0;
            trigger_enable <= 1'b0;
            read_ptr <= {BUFFER_DEPTH_LOG2{1'b0}};
            reg_rdata <= 32'd0;
            reg_rvalid <= 1'b0;
            clear_pending <= 1'b0;
        end else begin
            reg_rvalid <= 1'b0;

            // Handle clear
            if (clear_pending && !ctrl_enable) begin
                write_ptr <= {BUFFER_DEPTH_LOG2{1'b0}};
                read_ptr <= {BUFFER_DEPTH_LOG2{1'b0}};
                overflow_flag <= 1'b0;
                wrapped_flag <= 1'b0;
                trans_count <= 32'd0;
                clear_pending <= 1'b0;
            end

            // Register writes
            if (reg_we) begin
                case (reg_addr)
                    REG_CONTROL: begin
                        ctrl_enable <= reg_wdata[0];
                        if (reg_wdata[1]) clear_pending <= 1'b1;  // Clear request
                        ctrl_wrap_mode <= reg_wdata[2];
                    end

                    REG_FILTER: begin
                        filter_ep_mask <= reg_wdata[3:0];
                        filter_dir <= reg_wdata[4];
                        filter_dir_val <= reg_wdata[5];
                        filter_type_mask <= reg_wdata[8:6];
                    end

                    REG_READ_PTR: begin
                        read_ptr <= reg_wdata[BUFFER_DEPTH_LOG2-1:0];
                    end

                    REG_TRIGGER: begin
                        trigger_pid <= reg_wdata[7:0];
                        trigger_enable <= reg_wdata[8];
                    end
                endcase
            end

            // Register reads
            if (reg_re) begin
                reg_rvalid <= 1'b1;
                case (reg_addr)
                    REG_CONTROL:      reg_rdata <= {29'd0, ctrl_wrap_mode, 1'b0, ctrl_enable};
                    REG_STATUS:       reg_rdata <= {29'd0, wrapped_flag, overflow_flag,
                                                    ctrl_enable && triggered};
                    REG_FILTER:       reg_rdata <= {23'd0, filter_type_mask, filter_dir_val,
                                                    filter_dir, filter_ep_mask};
                    REG_WRITE_PTR:    reg_rdata <= {{(32-BUFFER_DEPTH_LOG2){1'b0}}, write_ptr};
                    REG_READ_PTR:     reg_rdata <= {{(32-BUFFER_DEPTH_LOG2){1'b0}}, read_ptr};
                    REG_TRANS_COUNT:  reg_rdata <= trans_count;
                    REG_TIMESTAMP_LO: reg_rdata <= timestamp[31:0];
                    REG_TIMESTAMP_HI: reg_rdata <= {16'd0, timestamp[47:32]};
                    REG_BUFFER_DATA: begin
                        reg_rdata <= {24'd0, buffer_mem[read_ptr]};
                        read_ptr <= read_ptr + 1'b1;  // Auto-increment
                    end
                    REG_BUFFER_SIZE:  reg_rdata <= BUFFER_SIZE;
                    REG_TRIGGER:      reg_rdata <= {23'd0, trigger_enable, trigger_pid};
                    default:          reg_rdata <= 32'd0;
                endcase
            end
        end
    end

    // =========================================================================
    // Status Outputs
    // =========================================================================
    assign capture_active = ctrl_enable && triggered;
    assign buffer_overflow = overflow_flag;
    assign transaction_count = trans_count;

endmodule
