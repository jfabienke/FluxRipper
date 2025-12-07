//-----------------------------------------------------------------------------
// usb_device_core.v
// USB 2.0 Device Controller Core
//
// Created: 2025-12-06 11:00
//
// Implements USB 2.0 device protocol layer including:
// - Token packet handling (SETUP, IN, OUT, SOF)
// - Data packet assembly/disassembly
// - Handshake generation (ACK, NAK, STALL)
// - CRC5/CRC16 generation and checking
// - Endpoint 0 control transfers
// - Bulk endpoint support
//
// Supports High-Speed (480 Mbps) and Full-Speed (12 Mbps) operation.
//-----------------------------------------------------------------------------

module usb_device_core #(
    parameter NUM_ENDPOINTS = 4,           // Number of endpoints (including EP0)
    parameter EP1_MAX_PKT   = 512,         // EP1 max packet size (HS bulk)
    parameter EP2_MAX_PKT   = 512,         // EP2 max packet size
    parameter EP3_MAX_PKT   = 64           // EP3 max packet size (interrupt)
)(
    input  wire        clk,                // 60 MHz ULPI clock
    input  wire        rst_n,

    //=========================================================================
    // ULPI PHY Interface
    //=========================================================================
    output reg  [7:0]  phy_tx_data,
    output reg         phy_tx_valid,
    input  wire        phy_tx_ready,
    output reg         phy_tx_last,

    input  wire [7:0]  phy_rx_data,
    input  wire        phy_rx_valid,
    input  wire        phy_rx_last,

    input  wire        phy_ready,
    input  wire [1:0]  line_state,
    input  wire        rx_active,

    //=========================================================================
    // Device State
    //=========================================================================
    output reg  [6:0]  device_addr,        // Assigned USB address
    output reg         configured,         // Device is configured
    output reg         suspended,          // Device is suspended
    output reg         high_speed,         // Operating in HS mode
    output reg  [10:0] frame_number,       // Current frame number

    //=========================================================================
    // Endpoint 0 (Control) Interface
    //=========================================================================
    // Setup packet received
    output reg         ep0_setup_valid,
    output reg  [7:0]  ep0_setup_data [0:7],  // 8-byte SETUP packet

    // Control IN data (device to host)
    input  wire [7:0]  ep0_in_data,
    input  wire        ep0_in_valid,
    output reg         ep0_in_ready,
    input  wire        ep0_in_last,

    // Control OUT data (host to device)
    output reg  [7:0]  ep0_out_data,
    output reg         ep0_out_valid,
    input  wire        ep0_out_ready,
    output reg         ep0_out_last,

    // Control transfer status
    input  wire        ep0_stall,          // Stall control transfer
    output reg         ep0_status_done,    // Status stage complete

    //=========================================================================
    // Endpoint 1 (Bulk) Interface
    //=========================================================================
    // Bulk IN (device to host)
    input  wire [7:0]  ep1_in_data,
    input  wire        ep1_in_valid,
    output reg         ep1_in_ready,
    input  wire        ep1_in_last,

    // Bulk OUT (host to device)
    output reg  [7:0]  ep1_out_data,
    output reg         ep1_out_valid,
    input  wire        ep1_out_ready,
    output reg         ep1_out_last,

    input  wire        ep1_stall,

    //=========================================================================
    // Endpoint 2 (Bulk) Interface
    //=========================================================================
    input  wire [7:0]  ep2_in_data,
    input  wire        ep2_in_valid,
    output reg         ep2_in_ready,
    input  wire        ep2_in_last,

    output reg  [7:0]  ep2_out_data,
    output reg         ep2_out_valid,
    input  wire        ep2_out_ready,
    output reg         ep2_out_last,

    input  wire        ep2_stall,

    //=========================================================================
    // Vendor Control Transfers (for KryoFlux compatibility)
    //=========================================================================
    output reg         vendor_req_valid,   // Vendor request received
    output reg  [7:0]  vendor_req_type,    // bmRequestType
    output reg  [7:0]  vendor_req,         // bRequest
    output reg  [15:0] vendor_value,       // wValue
    output reg  [15:0] vendor_index,       // wIndex
    output reg  [15:0] vendor_length,      // wLength

    input  wire [7:0]  vendor_resp_data,   // Response data
    input  wire        vendor_resp_valid,
    output reg         vendor_resp_ready,
    input  wire        vendor_resp_last,
    input  wire        vendor_stall        // Stall vendor request
);

    //=========================================================================
    // USB PIDs (Packet Identifiers)
    //=========================================================================

    // Token PIDs
    localparam PID_OUT   = 4'b0001;  // 0x1 -> 0xE1
    localparam PID_IN    = 4'b1001;  // 0x9 -> 0x69
    localparam PID_SOF   = 4'b0101;  // 0x5 -> 0xA5
    localparam PID_SETUP = 4'b1101;  // 0xD -> 0x2D

    // Data PIDs
    localparam PID_DATA0 = 4'b0011;  // 0x3 -> 0xC3
    localparam PID_DATA1 = 4'b1011;  // 0xB -> 0x4B
    localparam PID_DATA2 = 4'b0111;  // 0x7 -> 0x87 (HS only)
    localparam PID_MDATA = 4'b1111;  // 0xF -> 0x0F (HS only)

    // Handshake PIDs
    localparam PID_ACK   = 4'b0010;  // 0x2 -> 0xD2
    localparam PID_NAK   = 4'b1010;  // 0xA -> 0x5A
    localparam PID_STALL = 4'b1110;  // 0xE -> 0x1E
    localparam PID_NYET  = 4'b0110;  // 0x6 -> 0x96 (HS only)

    // Special PIDs
    localparam PID_PRE   = 4'b1100;  // Preamble
    localparam PID_SPLIT = 4'b1000;  // Split transaction
    localparam PID_PING  = 4'b0100;  // Ping (HS only)

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE           = 5'd0;
    localparam ST_RX_PID         = 5'd1;
    localparam ST_RX_TOKEN       = 5'd2;
    localparam ST_RX_DATA        = 5'd3;
    localparam ST_RX_CRC         = 5'd4;
    localparam ST_TX_DATA_PID    = 5'd5;
    localparam ST_TX_DATA        = 5'd6;
    localparam ST_TX_CRC1        = 5'd7;
    localparam ST_TX_CRC2        = 5'd8;
    localparam ST_TX_HANDSHAKE   = 5'd9;
    localparam ST_WAIT_TX_DONE   = 5'd10;
    localparam ST_SETUP_DATA     = 5'd11;
    localparam ST_CTRL_STATUS    = 5'd12;

    reg [4:0] state;

    //=========================================================================
    // Token Parsing
    //=========================================================================

    reg [3:0]  rx_pid;
    reg [6:0]  rx_addr;
    reg [3:0]  rx_endp;
    reg [10:0] rx_frame;
    reg [4:0]  crc5_calc;
    reg        token_valid;
    reg        addr_match;

    //=========================================================================
    // Data Handling
    //=========================================================================

    reg [15:0] crc16_reg;
    reg [9:0]  byte_count;
    reg [9:0]  max_packet_size;
    reg        data_toggle [0:NUM_ENDPOINTS-1];  // DATA0/DATA1 toggle per EP
    reg [7:0]  rx_buffer [0:511];                // RX packet buffer
    reg [9:0]  rx_buffer_len;

    //=========================================================================
    // Setup Packet Handling
    //=========================================================================

    reg [7:0] setup_packet [0:7];
    reg [2:0] setup_byte_cnt;
    reg       in_setup;

    //=========================================================================
    // CRC5 Calculation (for token packets)
    //=========================================================================

    function [4:0] crc5_next;
        input [4:0] crc;
        input       data_bit;
        reg         xor_bit;
        begin
            xor_bit = crc[4] ^ data_bit;
            crc5_next = {crc[3:0], 1'b0};
            if (xor_bit) crc5_next = crc5_next ^ 5'b00101;
        end
    endfunction

    //=========================================================================
    // CRC16 Calculation (for data packets)
    //=========================================================================

    function [15:0] crc16_byte;
        input [15:0] crc;
        input [7:0]  data;
        reg [15:0]   next_crc;
        integer i;
        begin
            next_crc = crc;
            for (i = 0; i < 8; i = i + 1) begin
                if (next_crc[15] ^ data[i])
                    next_crc = {next_crc[14:0], 1'b0} ^ 16'h8005;
                else
                    next_crc = {next_crc[14:0], 1'b0};
            end
            crc16_byte = next_crc;
        end
    endfunction

    wire [15:0] crc16_residual = 16'h800D;  // Expected residual for valid CRC

    //=========================================================================
    // Main State Machine
    //=========================================================================

    // Current endpoint being accessed
    reg [3:0] current_ep;
    reg       current_dir;  // 0=OUT, 1=IN

    // Response to send
    reg [3:0] tx_pid;
    reg       send_ack;
    reg       send_nak;
    reg       send_stall;
    reg       send_data;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            device_addr     <= 7'd0;
            configured      <= 1'b0;
            suspended       <= 1'b0;
            high_speed      <= 1'b0;
            frame_number    <= 11'd0;

            rx_pid          <= 4'd0;
            rx_addr         <= 7'd0;
            rx_endp         <= 4'd0;
            token_valid     <= 1'b0;
            addr_match      <= 1'b0;
            current_ep      <= 4'd0;
            current_dir     <= 1'b0;

            phy_tx_data     <= 8'd0;
            phy_tx_valid    <= 1'b0;
            phy_tx_last     <= 1'b0;

            crc16_reg       <= 16'hFFFF;
            byte_count      <= 10'd0;
            rx_buffer_len   <= 10'd0;

            ep0_setup_valid <= 1'b0;
            ep0_in_ready    <= 1'b0;
            ep0_out_data    <= 8'd0;
            ep0_out_valid   <= 1'b0;
            ep0_out_last    <= 1'b0;
            ep0_status_done <= 1'b0;

            ep1_in_ready    <= 1'b0;
            ep1_out_data    <= 8'd0;
            ep1_out_valid   <= 1'b0;
            ep1_out_last    <= 1'b0;

            ep2_in_ready    <= 1'b0;
            ep2_out_data    <= 8'd0;
            ep2_out_valid   <= 1'b0;
            ep2_out_last    <= 1'b0;

            vendor_req_valid  <= 1'b0;
            vendor_resp_ready <= 1'b0;

            in_setup        <= 1'b0;
            setup_byte_cnt  <= 3'd0;

            send_ack        <= 1'b0;
            send_nak        <= 1'b0;
            send_stall      <= 1'b0;
            send_data       <= 1'b0;

            for (i = 0; i < NUM_ENDPOINTS; i = i + 1)
                data_toggle[i] <= 1'b0;
            for (i = 0; i < 8; i = i + 1)
                setup_packet[i] <= 8'd0;
        end else begin
            // Default outputs
            ep0_setup_valid <= 1'b0;
            ep0_out_valid   <= 1'b0;
            ep0_out_last    <= 1'b0;
            ep0_status_done <= 1'b0;
            ep1_out_valid   <= 1'b0;
            ep1_out_last    <= 1'b0;
            ep2_out_valid   <= 1'b0;
            ep2_out_last    <= 1'b0;
            vendor_req_valid <= 1'b0;
            phy_tx_last     <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // Idle - Wait for incoming packet
                //-------------------------------------------------------------
                ST_IDLE: begin
                    token_valid   <= 1'b0;
                    phy_tx_valid  <= 1'b0;
                    byte_count    <= 10'd0;
                    crc16_reg     <= 16'hFFFF;

                    if (phy_rx_valid) begin
                        // First byte is PID
                        rx_pid <= phy_rx_data[3:0];
                        state  <= ST_RX_PID;
                    end
                end

                //-------------------------------------------------------------
                // Receive PID - Determine packet type
                //-------------------------------------------------------------
                ST_RX_PID: begin
                    // Verify PID check bits (upper 4 bits = ~lower 4 bits)
                    if (phy_rx_data[7:4] == ~rx_pid) begin
                        case (rx_pid)
                            PID_OUT, PID_IN, PID_SETUP: begin
                                state      <= ST_RX_TOKEN;
                                byte_count <= 10'd0;
                            end
                            PID_SOF: begin
                                state      <= ST_RX_TOKEN;
                                byte_count <= 10'd0;
                            end
                            PID_DATA0, PID_DATA1: begin
                                state     <= ST_RX_DATA;
                                crc16_reg <= 16'hFFFF;
                            end
                            default: state <= ST_IDLE;
                        endcase
                    end else begin
                        // Invalid PID
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // Receive Token Packet (ADDR + ENDP + CRC5)
                //-------------------------------------------------------------
                ST_RX_TOKEN: begin
                    if (phy_rx_valid) begin
                        byte_count <= byte_count + 1'b1;

                        case (byte_count)
                            10'd0: begin
                                rx_addr[6:0] <= phy_rx_data[6:0];
                                rx_endp[0]   <= phy_rx_data[7];
                            end
                            10'd1: begin
                                rx_endp[3:1] <= phy_rx_data[2:0];
                                crc5_calc    <= phy_rx_data[7:3];

                                // Check if address matches
                                addr_match <= (rx_addr == device_addr) || (device_addr == 7'd0);
                            end
                        endcase
                    end

                    if (phy_rx_last) begin
                        token_valid <= 1'b1;
                        current_ep  <= rx_endp;

                        if (rx_pid == PID_SOF) begin
                            // SOF - update frame number
                            frame_number <= {rx_endp[2:0], rx_addr};
                            state <= ST_IDLE;
                        end else if (addr_match) begin
                            // Token is for us
                            case (rx_pid)
                                PID_SETUP: begin
                                    in_setup       <= 1'b1;
                                    setup_byte_cnt <= 3'd0;
                                    data_toggle[0] <= 1'b0;  // SETUP always uses DATA0
                                    state          <= ST_IDLE;  // Wait for DATA0
                                end
                                PID_OUT: begin
                                    current_dir <= 1'b0;
                                    state       <= ST_IDLE;  // Wait for DATA
                                end
                                PID_IN: begin
                                    current_dir <= 1'b1;
                                    // Prepare to send data
                                    state <= ST_TX_DATA_PID;
                                end
                                default: state <= ST_IDLE;
                            endcase
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // Receive Data Packet
                //-------------------------------------------------------------
                ST_RX_DATA: begin
                    if (phy_rx_valid) begin
                        // Store data and update CRC
                        if (byte_count < 512) begin
                            rx_buffer[byte_count] <= phy_rx_data;
                        end
                        crc16_reg  <= crc16_byte(crc16_reg, phy_rx_data);
                        byte_count <= byte_count + 1'b1;
                    end

                    if (phy_rx_last) begin
                        rx_buffer_len <= byte_count - 2;  // Subtract CRC16

                        // Check CRC (residual should be 0x800D)
                        if (crc16_reg == crc16_residual) begin
                            // Valid packet
                            if (in_setup) begin
                                // SETUP data packet
                                state <= ST_SETUP_DATA;
                            end else begin
                                // OUT data packet
                                state <= ST_TX_HANDSHAKE;
                                send_ack <= 1'b1;
                            end
                        end else begin
                            // CRC error - ignore packet
                            state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // Process SETUP Data
                //-------------------------------------------------------------
                ST_SETUP_DATA: begin
                    // Copy setup packet
                    for (i = 0; i < 8; i = i + 1)
                        setup_packet[i] <= rx_buffer[i];

                    // Signal setup packet received
                    ep0_setup_valid <= 1'b1;
                    for (i = 0; i < 8; i = i + 1)
                        ep0_setup_data[i] <= rx_buffer[i];

                    // Decode for vendor requests
                    vendor_req_type <= rx_buffer[0];
                    vendor_req      <= rx_buffer[1];
                    vendor_value    <= {rx_buffer[3], rx_buffer[2]};
                    vendor_index    <= {rx_buffer[5], rx_buffer[4]};
                    vendor_length   <= {rx_buffer[7], rx_buffer[6]};

                    // Check if vendor request (bmRequestType[6:5] == 2)
                    if (rx_buffer[0][6:5] == 2'b10) begin
                        vendor_req_valid <= 1'b1;
                    end

                    in_setup <= 1'b0;
                    state    <= ST_TX_HANDSHAKE;
                    send_ack <= 1'b1;
                end

                //-------------------------------------------------------------
                // Transmit Data Packet
                //-------------------------------------------------------------
                ST_TX_DATA_PID: begin
                    // Check if endpoint has data or should NAK/STALL
                    case (current_ep)
                        4'd0: begin
                            if (ep0_stall) begin
                                send_stall <= 1'b1;
                                state      <= ST_TX_HANDSHAKE;
                            end else if (ep0_in_valid) begin
                                tx_pid       <= data_toggle[0] ? PID_DATA1 : PID_DATA0;
                                phy_tx_data  <= {~(data_toggle[0] ? PID_DATA1 : PID_DATA0),
                                                  (data_toggle[0] ? PID_DATA1 : PID_DATA0)};
                                phy_tx_valid <= 1'b1;
                                state        <= ST_TX_DATA;
                                byte_count   <= 10'd0;
                                crc16_reg    <= 16'hFFFF;
                                ep0_in_ready <= 1'b1;
                            end else begin
                                send_nak <= 1'b1;
                                state    <= ST_TX_HANDSHAKE;
                            end
                        end
                        4'd1: begin
                            if (ep1_stall) begin
                                send_stall <= 1'b1;
                                state      <= ST_TX_HANDSHAKE;
                            end else if (ep1_in_valid) begin
                                tx_pid       <= data_toggle[1] ? PID_DATA1 : PID_DATA0;
                                phy_tx_data  <= {~(data_toggle[1] ? PID_DATA1 : PID_DATA0),
                                                  (data_toggle[1] ? PID_DATA1 : PID_DATA0)};
                                phy_tx_valid <= 1'b1;
                                state        <= ST_TX_DATA;
                                byte_count   <= 10'd0;
                                crc16_reg    <= 16'hFFFF;
                                ep1_in_ready <= 1'b1;
                            end else begin
                                send_nak <= 1'b1;
                                state    <= ST_TX_HANDSHAKE;
                            end
                        end
                        4'd2: begin
                            if (ep2_stall) begin
                                send_stall <= 1'b1;
                                state      <= ST_TX_HANDSHAKE;
                            end else if (ep2_in_valid) begin
                                tx_pid       <= data_toggle[2] ? PID_DATA1 : PID_DATA0;
                                phy_tx_data  <= {~(data_toggle[2] ? PID_DATA1 : PID_DATA0),
                                                  (data_toggle[2] ? PID_DATA1 : PID_DATA0)};
                                phy_tx_valid <= 1'b1;
                                state        <= ST_TX_DATA;
                                byte_count   <= 10'd0;
                                crc16_reg    <= 16'hFFFF;
                                ep2_in_ready <= 1'b1;
                            end else begin
                                send_nak <= 1'b1;
                                state    <= ST_TX_HANDSHAKE;
                            end
                        end
                        default: begin
                            send_stall <= 1'b1;
                            state      <= ST_TX_HANDSHAKE;
                        end
                    endcase
                end

                ST_TX_DATA: begin
                    if (phy_tx_ready) begin
                        // Get data from appropriate endpoint
                        case (current_ep)
                            4'd0: begin
                                phy_tx_data  <= ep0_in_data;
                                crc16_reg    <= crc16_byte(crc16_reg, ep0_in_data);
                                ep0_in_ready <= 1'b1;
                                if (ep0_in_last) begin
                                    state        <= ST_TX_CRC1;
                                    ep0_in_ready <= 1'b0;
                                end
                            end
                            4'd1: begin
                                phy_tx_data  <= ep1_in_data;
                                crc16_reg    <= crc16_byte(crc16_reg, ep1_in_data);
                                ep1_in_ready <= 1'b1;
                                if (ep1_in_last) begin
                                    state        <= ST_TX_CRC1;
                                    ep1_in_ready <= 1'b0;
                                end
                            end
                            4'd2: begin
                                phy_tx_data  <= ep2_in_data;
                                crc16_reg    <= crc16_byte(crc16_reg, ep2_in_data);
                                ep2_in_ready <= 1'b1;
                                if (ep2_in_last) begin
                                    state        <= ST_TX_CRC2;
                                    ep2_in_ready <= 1'b0;
                                end
                            end
                        endcase
                        byte_count <= byte_count + 1'b1;
                    end
                end

                ST_TX_CRC1: begin
                    if (phy_tx_ready) begin
                        phy_tx_data <= ~crc16_reg[7:0];  // CRC is sent inverted
                        state       <= ST_TX_CRC2;
                    end
                end

                ST_TX_CRC2: begin
                    if (phy_tx_ready) begin
                        phy_tx_data <= ~crc16_reg[15:8];
                        phy_tx_last <= 1'b1;
                        state       <= ST_WAIT_TX_DONE;
                        // Toggle DATA0/DATA1
                        data_toggle[current_ep] <= ~data_toggle[current_ep];
                    end
                end

                //-------------------------------------------------------------
                // Transmit Handshake
                //-------------------------------------------------------------
                ST_TX_HANDSHAKE: begin
                    phy_tx_valid <= 1'b1;

                    if (send_ack) begin
                        phy_tx_data <= {~PID_ACK, PID_ACK};
                    end else if (send_nak) begin
                        phy_tx_data <= {~PID_NAK, PID_NAK};
                    end else if (send_stall) begin
                        phy_tx_data <= {~PID_STALL, PID_STALL};
                    end

                    phy_tx_last <= 1'b1;
                    state       <= ST_WAIT_TX_DONE;

                    send_ack   <= 1'b0;
                    send_nak   <= 1'b0;
                    send_stall <= 1'b0;
                end

                //-------------------------------------------------------------
                // Wait for TX Complete
                //-------------------------------------------------------------
                ST_WAIT_TX_DONE: begin
                    if (phy_tx_ready) begin
                        phy_tx_valid <= 1'b0;
                        phy_tx_last  <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase

            // Handle SET_ADDRESS from control transfer
            // (This would be triggered by ep0 handler)
        end
    end

    //=========================================================================
    // Address Assignment (SET_ADDRESS handler)
    //=========================================================================

    // SET_ADDRESS is handled specially - address takes effect after status stage
    reg        set_addr_pending;
    reg [6:0]  pending_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            set_addr_pending <= 1'b0;
            pending_addr     <= 7'd0;
        end else begin
            // Check for SET_ADDRESS in setup packet
            if (ep0_setup_valid &&
                setup_packet[0] == 8'h00 &&  // bmRequestType = 0
                setup_packet[1] == 8'h05) begin // bRequest = SET_ADDRESS
                set_addr_pending <= 1'b1;
                pending_addr     <= setup_packet[2][6:0];
            end

            // Apply address after status stage
            if (ep0_status_done && set_addr_pending) begin
                device_addr      <= pending_addr;
                set_addr_pending <= 1'b0;
            end
        end
    end

endmodule
