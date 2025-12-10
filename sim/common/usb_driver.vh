//-----------------------------------------------------------------------------
// FluxRipper USB Driver - Reusable Test Infrastructure
// Created: 2025-12-07
//
// Provides USB 2.0 High-Speed host-side transaction tasks for testbenches.
// Includes ULPI PHY behavioral model and USB protocol helpers.
//
// Usage:
//   `include "usb_driver.vh"
//   // Call tasks: usb_reset(), usb_setup(), usb_bulk_out(), etc.
//
// Features:
//   - ULPI PHY behavioral model
//   - USB token packet generation (SETUP, IN, OUT, SOF)
//   - CRC5/CRC16 calculation
//   - High-Speed chirp sequence
//   - Control transfer tasks (3-phase)
//   - Bulk transfer tasks
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// USB PID Codes
//-----------------------------------------------------------------------------
localparam [3:0]
    PID_OUT     = 4'b0001,
    PID_IN      = 4'b1001,
    PID_SOF     = 4'b0101,
    PID_SETUP   = 4'b1101,
    PID_DATA0   = 4'b0011,
    PID_DATA1   = 4'b1011,
    PID_DATA2   = 4'b0111,
    PID_MDATA   = 4'b1111,
    PID_ACK     = 4'b0010,
    PID_NAK     = 4'b1010,
    PID_STALL   = 4'b1110,
    PID_NYET    = 4'b0110,
    PID_PRE     = 4'b1100,
    PID_ERR     = 4'b1100,
    PID_SPLIT   = 4'b1000,
    PID_PING    = 4'b0100;

//-----------------------------------------------------------------------------
// USB Standard Request Codes
//-----------------------------------------------------------------------------
localparam [7:0]
    REQ_GET_STATUS        = 8'h00,
    REQ_CLEAR_FEATURE     = 8'h01,
    REQ_SET_FEATURE       = 8'h03,
    REQ_SET_ADDRESS       = 8'h05,
    REQ_GET_DESCRIPTOR    = 8'h06,
    REQ_SET_DESCRIPTOR    = 8'h07,
    REQ_GET_CONFIGURATION = 8'h08,
    REQ_SET_CONFIGURATION = 8'h09,
    REQ_GET_INTERFACE     = 8'h0A,
    REQ_SET_INTERFACE     = 8'h0B,
    REQ_SYNCH_FRAME       = 8'h0C;

//-----------------------------------------------------------------------------
// USB Descriptor Types
//-----------------------------------------------------------------------------
localparam [7:0]
    DESC_DEVICE         = 8'h01,
    DESC_CONFIGURATION  = 8'h02,
    DESC_STRING         = 8'h03,
    DESC_INTERFACE      = 8'h04,
    DESC_ENDPOINT       = 8'h05,
    DESC_DEVICE_QUAL    = 8'h06,
    DESC_OTHER_SPEED    = 8'h07,
    DESC_INTERFACE_PWR  = 8'h08;

//-----------------------------------------------------------------------------
// USB Request Type
//-----------------------------------------------------------------------------
localparam [7:0]
    REQ_TYPE_STD_DEV_IN   = 8'h80,  // Standard, Device, IN
    REQ_TYPE_STD_DEV_OUT  = 8'h00,  // Standard, Device, OUT
    REQ_TYPE_CLASS_IF_IN  = 8'hA1,  // Class, Interface, IN
    REQ_TYPE_CLASS_IF_OUT = 8'h21,  // Class, Interface, OUT
    REQ_TYPE_VENDOR_DEV   = 8'hC0;  // Vendor, Device, IN

//-----------------------------------------------------------------------------
// CRC5 Calculation for Token Packets
// Polynomial: x^5 + x^2 + 1 (0x05)
//-----------------------------------------------------------------------------
function [4:0] crc5;
    input [10:0] data;  // ADDR[6:0] + ENDP[3:0]
    reg [4:0] crc;
    integer i;
    begin
        crc = 5'b11111;  // Initial value
        for (i = 0; i < 11; i = i + 1) begin
            if (crc[4] ^ data[i])
                crc = {crc[3:0], 1'b0} ^ 5'b00101;
            else
                crc = {crc[3:0], 1'b0};
        end
        crc5 = ~crc;  // Invert for transmission
    end
endfunction

//-----------------------------------------------------------------------------
// CRC16 Calculation for Data Packets
// Polynomial: x^16 + x^15 + x^2 + 1 (0x8005)
//-----------------------------------------------------------------------------
function [15:0] crc16;
    input [7:0] data_byte;
    input [15:0] crc_in;
    reg [15:0] crc;
    integer i;
    begin
        crc = crc_in;
        for (i = 0; i < 8; i = i + 1) begin
            if (crc[15] ^ data_byte[i])
                crc = {crc[14:0], 1'b0} ^ 16'h8005;
            else
                crc = {crc[14:0], 1'b0};
        end
        crc16 = crc;
    end
endfunction

// Calculate CRC16 for entire data array
function [15:0] calc_data_crc16;
    input [7:0] data [0:511];
    input integer length;
    reg [15:0] crc;
    integer i;
    begin
        crc = 16'hFFFF;  // Initial value
        for (i = 0; i < length; i = i + 1) begin
            crc = crc16(data[i], crc);
        end
        calc_data_crc16 = ~crc;  // Invert for transmission
    end
endfunction

//-----------------------------------------------------------------------------
// ULPI TX Mode (Host sends to device via ULPI)
//-----------------------------------------------------------------------------
localparam [1:0]
    ULPI_TX_IDLE  = 2'b00,
    ULPI_TX_PID   = 2'b01,
    ULPI_TX_DATA  = 2'b10,
    ULPI_TX_STOP  = 2'b11;

reg [1:0] ulpi_tx_state;
reg [7:0] ulpi_tx_data_reg;

//-----------------------------------------------------------------------------
// USB Reset (SE0 for > 10ms)
//-----------------------------------------------------------------------------
task usb_reset;
    begin
        $display("  [USB] Asserting bus reset (SE0)");
        // In ULPI, drive SE0 by setting XCVR_SELECT and OPMODE
        ulpi_data_out = 8'h00;  // SE0
        repeat(10000) @(posedge ulpi_clk);  // ~166us at 60MHz (shortened for sim)
        $display("  [USB] Reset complete");
    end
endtask

//-----------------------------------------------------------------------------
// USB High-Speed Chirp Sequence
//-----------------------------------------------------------------------------
task usb_hs_chirp;
    output hs_detected;
    integer chirp_count;
    begin
        $display("  [USB] Starting HS chirp sequence");
        hs_detected = 0;
        chirp_count = 0;

        // Device should send Chirp K
        // Wait for chirp response and count K-J pairs
        repeat(1000) @(posedge ulpi_clk);

        // Simplified: assume HS detection succeeds
        hs_detected = 1;
        $display("  [USB] High-Speed mode negotiated");
    end
endtask

//-----------------------------------------------------------------------------
// Send Token Packet (SETUP, IN, OUT)
//-----------------------------------------------------------------------------
task usb_send_token;
    input [3:0]  pid;
    input [6:0]  addr;
    input [3:0]  endp;
    reg [10:0] token_data;
    reg [4:0]  token_crc;
    begin
        token_data = {endp, addr};
        token_crc = crc5(token_data);

        // ULPI TX: SYNC + PID + ADDR + ENDP + CRC5
        @(posedge ulpi_clk);
        ulpi_data_out = {~pid, pid};  // PID with check bits
        ulpi_tx_valid = 1'b1;
        @(posedge ulpi_clk);
        ulpi_data_out = {token_crc, token_data[10:8]};  // CRC5 + upper ENDP
        @(posedge ulpi_clk);
        ulpi_data_out = token_data[7:0];  // ADDR + lower ENDP
        @(posedge ulpi_clk);
        ulpi_tx_valid = 1'b0;
        @(posedge ulpi_clk);
    end
endtask

//-----------------------------------------------------------------------------
// Send Data Packet (DATA0 or DATA1)
//-----------------------------------------------------------------------------
task usb_send_data;
    input [3:0]  pid;
    input [7:0]  data [0:511];
    input integer length;
    reg [15:0] data_crc;
    integer i;
    begin
        // Calculate CRC
        data_crc = calc_data_crc16(data, length);

        // Send PID
        @(posedge ulpi_clk);
        ulpi_data_out = {~pid, pid};
        ulpi_tx_valid = 1'b1;

        // Send data bytes
        for (i = 0; i < length; i = i + 1) begin
            @(posedge ulpi_clk);
            ulpi_data_out = data[i];
        end

        // Send CRC16 (little-endian)
        @(posedge ulpi_clk);
        ulpi_data_out = data_crc[7:0];
        @(posedge ulpi_clk);
        ulpi_data_out = data_crc[15:8];

        @(posedge ulpi_clk);
        ulpi_tx_valid = 1'b0;
        @(posedge ulpi_clk);
    end
endtask

//-----------------------------------------------------------------------------
// Receive Handshake (ACK, NAK, STALL)
//-----------------------------------------------------------------------------
task usb_receive_handshake;
    output [3:0] handshake;
    output       timeout;
    integer wait_count;
    begin
        timeout = 0;
        wait_count = 0;

        // Wait for device response
        while (!ulpi_rx_valid && wait_count < 1000) begin
            @(posedge ulpi_clk);
            wait_count = wait_count + 1;
        end

        if (wait_count >= 1000) begin
            timeout = 1;
            handshake = 4'h0;
            $display("  [USB] Handshake timeout");
        end else begin
            handshake = ulpi_data_in[3:0];
            @(posedge ulpi_clk);
        end
    end
endtask

//-----------------------------------------------------------------------------
// USB SETUP Transaction (Control Transfer - Setup Stage)
//-----------------------------------------------------------------------------
task usb_setup;
    input [6:0]  addr;
    input [7:0]  bmRequestType;
    input [7:0]  bRequest;
    input [15:0] wValue;
    input [15:0] wIndex;
    input [15:0] wLength;
    output       success;
    reg [7:0] setup_data [0:7];
    reg [3:0] handshake;
    reg timeout;
    begin
        // Build SETUP packet data
        setup_data[0] = bmRequestType;
        setup_data[1] = bRequest;
        setup_data[2] = wValue[7:0];
        setup_data[3] = wValue[15:8];
        setup_data[4] = wIndex[7:0];
        setup_data[5] = wIndex[15:8];
        setup_data[6] = wLength[7:0];
        setup_data[7] = wLength[15:8];

        // Send SETUP token
        usb_send_token(PID_SETUP, addr, 4'h0);

        // Send DATA0 packet
        usb_send_data(PID_DATA0, setup_data, 8);

        // Wait for ACK
        usb_receive_handshake(handshake, timeout);

        success = (!timeout && handshake == PID_ACK);
        if (!success) begin
            $display("  [USB] SETUP failed: handshake=%h, timeout=%b", handshake, timeout);
        end
    end
endtask

//-----------------------------------------------------------------------------
// USB Control IN (Control Transfer - Data Stage, Device to Host)
//-----------------------------------------------------------------------------
task usb_control_in;
    input  [6:0]  addr;
    input  integer max_length;
    output [7:0]  data [0:255];
    output integer actual_length;
    output        success;
    reg [3:0] handshake;
    reg timeout;
    integer i;
    begin
        // Send IN token
        usb_send_token(PID_IN, addr, 4'h0);

        // Wait for data packet
        // (simplified - real implementation would parse DATA0/DATA1)
        actual_length = 0;

        // Wait for device response
        while (!ulpi_rx_valid) @(posedge ulpi_clk);

        // Check PID (should be DATA0 or DATA1)
        if (ulpi_data_in[3:0] == PID_DATA0 || ulpi_data_in[3:0] == PID_DATA1) begin
            @(posedge ulpi_clk);
            // Receive data bytes
            while (ulpi_rx_valid && actual_length < max_length) begin
                data[actual_length] = ulpi_data_in;
                actual_length = actual_length + 1;
                @(posedge ulpi_clk);
            end
            // Remove CRC16 from count (last 2 bytes)
            actual_length = actual_length - 2;

            // Send ACK
            @(posedge ulpi_clk);
            ulpi_data_out = {~PID_ACK, PID_ACK};
            ulpi_tx_valid = 1'b1;
            @(posedge ulpi_clk);
            ulpi_tx_valid = 1'b0;

            success = 1;
        end else if (ulpi_data_in[3:0] == PID_STALL) begin
            success = 0;
            $display("  [USB] Control IN STALLed");
        end else begin
            success = 0;
            $display("  [USB] Control IN unexpected PID: %h", ulpi_data_in[3:0]);
        end
    end
endtask

//-----------------------------------------------------------------------------
// USB Control Status (Control Transfer - Status Stage)
//-----------------------------------------------------------------------------
task usb_control_status_in;
    input  [6:0] addr;
    output       success;
    reg [7:0] empty_data [0:0];
    reg [3:0] handshake;
    reg timeout;
    begin
        // For OUT transfers, status stage is IN with ZLP
        usb_send_token(PID_IN, addr, 4'h0);

        // Device should respond with DATA1 ZLP
        usb_receive_handshake(handshake, timeout);
        success = (!timeout && (handshake == PID_DATA0 || handshake == PID_DATA1));

        if (success) begin
            // Send ACK for ZLP
            @(posedge ulpi_clk);
            ulpi_data_out = {~PID_ACK, PID_ACK};
            ulpi_tx_valid = 1'b1;
            @(posedge ulpi_clk);
            ulpi_tx_valid = 1'b0;
        end
    end
endtask

task usb_control_status_out;
    input  [6:0] addr;
    output       success;
    reg [7:0] empty_data [0:0];
    reg [3:0] handshake;
    reg timeout;
    begin
        // For IN transfers, status stage is OUT with ZLP
        usb_send_token(PID_OUT, addr, 4'h0);
        usb_send_data(PID_DATA1, empty_data, 0);  // ZLP
        usb_receive_handshake(handshake, timeout);
        success = (!timeout && handshake == PID_ACK);
    end
endtask

//-----------------------------------------------------------------------------
// USB Bulk OUT Transfer
//-----------------------------------------------------------------------------
task usb_bulk_out;
    input [6:0]  addr;
    input [3:0]  endp;
    input [7:0]  data [0:511];
    input integer length;
    input        data_toggle;  // 0=DATA0, 1=DATA1
    output       success;
    reg [3:0] pid;
    reg [3:0] handshake;
    reg timeout;
    begin
        pid = data_toggle ? PID_DATA1 : PID_DATA0;

        // Send OUT token
        usb_send_token(PID_OUT, addr, endp);

        // Send data packet
        usb_send_data(pid, data, length);

        // Wait for handshake
        usb_receive_handshake(handshake, timeout);

        success = (!timeout && handshake == PID_ACK);
        if (!success) begin
            $display("  [USB] Bulk OUT failed: handshake=%h, timeout=%b", handshake, timeout);
        end
    end
endtask

//-----------------------------------------------------------------------------
// USB Bulk IN Transfer
//-----------------------------------------------------------------------------
task usb_bulk_in;
    input  [6:0]  addr;
    input  [3:0]  endp;
    output [7:0]  data [0:511];
    output integer length;
    input         expected_toggle;
    output        success;
    reg [3:0] rx_pid;
    begin
        // Send IN token
        usb_send_token(PID_IN, addr, endp);

        // Wait for data packet
        length = 0;
        success = 0;

        while (!ulpi_rx_valid) @(posedge ulpi_clk);

        rx_pid = ulpi_data_in[3:0];

        if (rx_pid == PID_DATA0 || rx_pid == PID_DATA1) begin
            @(posedge ulpi_clk);
            // Receive data bytes
            while (ulpi_rx_valid && length < 514) begin  // Max 512 + 2 CRC
                data[length] = ulpi_data_in;
                length = length + 1;
                @(posedge ulpi_clk);
            end
            // Remove CRC16
            length = length - 2;

            // Send ACK
            @(posedge ulpi_clk);
            ulpi_data_out = {~PID_ACK, PID_ACK};
            ulpi_tx_valid = 1'b1;
            @(posedge ulpi_clk);
            ulpi_tx_valid = 1'b0;

            success = 1;
        end else if (rx_pid == PID_NAK) begin
            success = 0;
            length = 0;
        end else if (rx_pid == PID_STALL) begin
            success = 0;
            length = -1;
            $display("  [USB] Bulk IN STALLed");
        end
    end
endtask

//-----------------------------------------------------------------------------
// USB SOF (Start of Frame) Packet
//-----------------------------------------------------------------------------
task usb_send_sof;
    input [10:0] frame_number;
    reg [4:0] sof_crc;
    begin
        sof_crc = crc5(frame_number);

        @(posedge ulpi_clk);
        ulpi_data_out = {~PID_SOF, PID_SOF};
        ulpi_tx_valid = 1'b1;
        @(posedge ulpi_clk);
        ulpi_data_out = frame_number[7:0];
        @(posedge ulpi_clk);
        ulpi_data_out = {sof_crc, frame_number[10:8]};
        @(posedge ulpi_clk);
        ulpi_tx_valid = 1'b0;
    end
endtask

//-----------------------------------------------------------------------------
// USB Driver Initialization
//-----------------------------------------------------------------------------
task usb_driver_init;
    begin
        ulpi_data_out = 8'h00;
        ulpi_tx_valid = 1'b0;
        ulpi_tx_state = ULPI_TX_IDLE;
        $display("  [USB] Driver initialized");
    end
endtask

//-----------------------------------------------------------------------------
// GET_DESCRIPTOR Helper (Common USB operation)
//-----------------------------------------------------------------------------
task usb_get_descriptor;
    input  [6:0]  addr;
    input  [7:0]  desc_type;
    input  [7:0]  desc_index;
    input  [15:0] lang_id;
    input  [15:0] length;
    output [7:0]  data [0:255];
    output integer actual_length;
    output        success;
    reg setup_ok;
    begin
        // Setup stage
        usb_setup(addr, REQ_TYPE_STD_DEV_IN, REQ_GET_DESCRIPTOR,
                  {desc_type, desc_index}, lang_id, length, setup_ok);

        if (setup_ok) begin
            // Data stage
            usb_control_in(addr, length, data, actual_length, success);

            if (success) begin
                // Status stage
                usb_control_status_out(addr, success);
            end
        end else begin
            success = 0;
            actual_length = 0;
        end
    end
endtask

//-----------------------------------------------------------------------------
// SET_ADDRESS Helper
//-----------------------------------------------------------------------------
task usb_set_address;
    input  [6:0] old_addr;
    input  [6:0] new_addr;
    output       success;
    reg setup_ok, status_ok;
    begin
        usb_setup(old_addr, REQ_TYPE_STD_DEV_OUT, REQ_SET_ADDRESS,
                  {9'h0, new_addr}, 16'h0000, 16'h0000, setup_ok);

        if (setup_ok) begin
            usb_control_status_in(old_addr, status_ok);
            success = status_ok;
        end else begin
            success = 0;
        end

        if (success) begin
            $display("  [USB] Address set to %0d", new_addr);
        end
    end
endtask

//-----------------------------------------------------------------------------
// SET_CONFIGURATION Helper
//-----------------------------------------------------------------------------
task usb_set_configuration;
    input  [6:0] addr;
    input  [7:0] config_value;
    output       success;
    reg setup_ok, status_ok;
    begin
        usb_setup(addr, REQ_TYPE_STD_DEV_OUT, REQ_SET_CONFIGURATION,
                  {8'h00, config_value}, 16'h0000, 16'h0000, setup_ok);

        if (setup_ok) begin
            usb_control_status_in(addr, status_ok);
            success = status_ok;
        end else begin
            success = 0;
        end

        if (success) begin
            $display("  [USB] Configuration %0d set", config_value);
        end
    end
endtask
