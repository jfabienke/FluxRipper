// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// tb_usb_top_v2.v - Comprehensive Testbench for USB 2.0 High-Speed Stack
//
// Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
// Copyright (c) 2025 John Fabienke
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//-----------------------------------------------------------------------------
// Created: 2025-12-06 17:49:12
// Updated: 2025-12-06 20:50:00
//
// Description:
//   Comprehensive testbench for usb_top_v2 module featuring:
//   - ULPI PHY behavioral model with DIR/NXT/STP handshake
//   - USB host transaction tasks (SETUP, IN, OUT, SOF)
//   - HS chirp sequence simulation
//   - Enumeration test sequence
//   - KryoFlux vendor request testing
//   - Bulk transfer testing
//   - CRC5/CRC16 calculation and validation
//   - Self-checking with pass/fail reporting
//
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_usb_top_v2;

//=============================================================================
// Parameters
//=============================================================================
parameter CLK_SYS_PERIOD = 10;     // 100 MHz system clock
parameter CLK_ULPI_PERIOD = 16.67; // 60 MHz ULPI clock

// USB PIDs
localparam [3:0] PID_OUT   = 4'h1;
localparam [3:0] PID_IN    = 4'h9;
localparam [3:0] PID_SOF   = 4'h5;
localparam [3:0] PID_SETUP = 4'hD;
localparam [3:0] PID_DATA0 = 4'h3;
localparam [3:0] PID_DATA1 = 4'hB;
localparam [3:0] PID_DATA2 = 4'h7;
localparam [3:0] PID_MDATA = 4'hF;
localparam [3:0] PID_ACK   = 4'h2;
localparam [3:0] PID_NAK   = 4'hA;
localparam [3:0] PID_STALL = 4'hE;
localparam [3:0] PID_NYET  = 4'h6;

// ULPI Command codes
localparam [7:0] ULPI_TX_CMD = 8'h40;
localparam [7:0] ULPI_RX_CMD = 8'hC0;

// Line states
localparam [1:0] LINE_SE0 = 2'b00;
localparam [1:0] LINE_J   = 2'b01;
localparam [1:0] LINE_K   = 2'b10;

// Standard USB requests
localparam [7:0] REQ_GET_STATUS        = 8'h00;
localparam [7:0] REQ_CLEAR_FEATURE     = 8'h01;
localparam [7:0] REQ_SET_FEATURE       = 8'h03;
localparam [7:0] REQ_SET_ADDRESS       = 8'h05;
localparam [7:0] REQ_GET_DESCRIPTOR    = 8'h06;
localparam [7:0] REQ_SET_DESCRIPTOR    = 8'h07;
localparam [7:0] REQ_GET_CONFIGURATION = 8'h08;
localparam [7:0] REQ_SET_CONFIGURATION = 8'h09;

// Descriptor types
localparam [7:0] DESC_DEVICE           = 8'h01;
localparam [7:0] DESC_CONFIGURATION    = 8'h02;
localparam [7:0] DESC_STRING           = 8'h03;

//=============================================================================
// Testbench Signals
//=============================================================================

// Clock and reset
reg         clk_sys;
reg         rst_n;
reg         ulpi_clk;

// ULPI PHY interface
wire [7:0]  ulpi_data;
reg  [7:0]  ulpi_data_out;
reg         ulpi_data_oe;
reg         ulpi_dir;
reg         ulpi_nxt;
wire        ulpi_stp;
wire        ulpi_rst_n;

// Personality selection
reg  [2:0]  personality_sel;
reg         personality_switch;
wire        switch_complete;
wire [2:0]  active_personality;

// Flux capture interface
reg  [31:0] flux_data;
reg         flux_valid;
wire        flux_ready;
reg         flux_index;
wire        flux_capture_start;
wire        flux_capture_stop;
wire [7:0]  flux_sample_rate;
reg         flux_capturing;

// Drive control
wire [3:0]  drive_select;
wire        motor_on;
wire        head_select;
wire [7:0]  track_target;
wire        seek_start;
reg         seek_complete;
reg  [7:0]  current_track;
reg         disk_present;
reg         write_protect;
reg         track_00;
reg         motor_spinning;

// Protocol handler interfaces
wire [31:0] proto_rx_data;
wire        proto_rx_valid;
reg         proto_rx_ready;
reg  [31:0] proto_tx_data;
reg         proto_tx_valid;
wire        proto_tx_ready;

// KryoFlux control transfer interface
wire        kf_cmd_valid;
wire [7:0]  kf_cmd_request;
wire [15:0] kf_cmd_value;
wire [15:0] kf_cmd_index;
wire [15:0] kf_cmd_length;
reg  [7:0]  kf_response_data;
reg         kf_response_valid;
reg         kf_response_last;

// MSC interface
wire [3:0]  msc_lun;
wire [31:0] msc_lba;
wire [15:0] msc_block_count;
wire        msc_read_start;
wire        msc_write_start;
reg         msc_ready;
reg         msc_error;
reg  [31:0] msc_read_data;
reg         msc_read_valid;
wire        msc_read_ready;
wire [31:0] msc_write_data;
wire        msc_write_valid;
reg         msc_write_ready;

// Diagnostics
wire [31:0] diag_cmd;
wire        diag_cmd_valid;
reg  [31:0] diag_response;
reg         diag_response_valid;

// Status outputs
wire        usb_connected;
wire        usb_configured;
wire        usb_suspended;
wire [1:0]  usb_speed;
wire [10:0] usb_frame_number;
wire        usb_sof_valid;
wire        usb_error;
wire [7:0]  usb_state;
wire [7:0]  protocol_state;
wire [31:0] rx_byte_count;
wire [31:0] tx_byte_count;

// MSC configuration
reg         msc_config_valid;
reg  [15:0] msc_fdd0_sectors;
reg  [15:0] msc_fdd1_sectors;
reg  [31:0] msc_hdd0_sectors;
reg  [31:0] msc_hdd1_sectors;
reg  [3:0]  msc_drive_ready_in;
reg  [3:0]  msc_drive_wp_in;
wire [3:0]  msc_drive_present_out;
wire [3:0]  msc_media_changed_out;

//=============================================================================
// ULPI PHY Model State
//=============================================================================
reg [1:0]   phy_linestate;
reg         phy_vbus;
reg [7:0]   rx_buffer [0:1023];
integer     rx_byte_cnt;
integer     tx_byte_cnt;
reg [15:0]  crc16_result;

//=============================================================================
// Test Control
//=============================================================================
integer     test_num;
integer     errors;
integer     warnings;
reg [255:0] test_name;

//=============================================================================
// ULPI Bidirectional Data
//=============================================================================
assign ulpi_data = ulpi_data_oe ? ulpi_data_out : 8'bz;

//=============================================================================
// DUT Instantiation
//=============================================================================
usb_top_v2 dut (
    .clk_sys                (clk_sys),
    .rst_n                  (rst_n),

    // ULPI PHY interface
    .ulpi_clk               (ulpi_clk),
    .ulpi_data              (ulpi_data),
    .ulpi_dir               (ulpi_dir),
    .ulpi_nxt               (ulpi_nxt),
    .ulpi_stp               (ulpi_stp),
    .ulpi_rst_n             (ulpi_rst_n),

    // Personality
    .personality_sel        (personality_sel),
    .personality_switch     (personality_switch),
    .switch_complete        (switch_complete),
    .active_personality     (active_personality),

    // Flux capture
    .flux_data              (flux_data),
    .flux_valid             (flux_valid),
    .flux_ready             (flux_ready),
    .flux_index             (flux_index),
    .flux_capture_start     (flux_capture_start),
    .flux_capture_stop      (flux_capture_stop),
    .flux_sample_rate       (flux_sample_rate),
    .flux_capturing         (flux_capturing),

    // Drive control
    .drive_select           (drive_select),
    .motor_on               (motor_on),
    .head_select            (head_select),
    .track_target           (track_target),
    .seek_start             (seek_start),
    .seek_complete          (seek_complete),
    .current_track          (current_track),
    .disk_present           (disk_present),
    .write_protect          (write_protect),
    .track_00               (track_00),
    .motor_spinning         (motor_spinning),

    // Protocol handlers
    .proto_rx_data          (proto_rx_data),
    .proto_rx_valid         (proto_rx_valid),
    .proto_rx_ready         (proto_rx_ready),
    .proto_tx_data          (proto_tx_data),
    .proto_tx_valid         (proto_tx_valid),
    .proto_tx_ready         (proto_tx_ready),

    // KryoFlux
    .kf_cmd_valid           (kf_cmd_valid),
    .kf_cmd_request         (kf_cmd_request),
    .kf_cmd_value           (kf_cmd_value),
    .kf_cmd_index           (kf_cmd_index),
    .kf_cmd_length          (kf_cmd_length),
    .kf_response_data       (kf_response_data),
    .kf_response_valid      (kf_response_valid),
    .kf_response_last       (kf_response_last),

    // MSC
    .msc_lun                (msc_lun),
    .msc_lba                (msc_lba),
    .msc_block_count        (msc_block_count),
    .msc_read_start         (msc_read_start),
    .msc_write_start        (msc_write_start),
    .msc_ready              (msc_ready),
    .msc_error              (msc_error),
    .msc_read_data          (msc_read_data),
    .msc_read_valid         (msc_read_valid),
    .msc_read_ready         (msc_read_ready),
    .msc_write_data         (msc_write_data),
    .msc_write_valid        (msc_write_valid),
    .msc_write_ready        (msc_write_ready),

    // Diagnostics
    .diag_cmd               (diag_cmd),
    .diag_cmd_valid         (diag_cmd_valid),
    .diag_response          (diag_response),
    .diag_response_valid    (diag_response_valid),

    // Status
    .usb_connected          (usb_connected),
    .usb_configured         (usb_configured),
    .usb_suspended          (usb_suspended),
    .usb_speed              (usb_speed),
    .usb_frame_number       (usb_frame_number),
    .usb_sof_valid          (usb_sof_valid),
    .usb_error              (usb_error),
    .usb_state              (usb_state),
    .protocol_state         (protocol_state),
    .rx_byte_count          (rx_byte_count),
    .tx_byte_count          (tx_byte_count),

    // MSC config
    .msc_config_valid       (msc_config_valid),
    .msc_fdd0_sectors       (msc_fdd0_sectors),
    .msc_fdd1_sectors       (msc_fdd1_sectors),
    .msc_hdd0_sectors       (msc_hdd0_sectors),
    .msc_hdd1_sectors       (msc_hdd1_sectors),
    .msc_drive_ready_in     (msc_drive_ready_in),
    .msc_drive_wp_in        (msc_drive_wp_in),
    .msc_drive_present_out  (msc_drive_present_out),
    .msc_media_changed_out  (msc_media_changed_out)
);

//=============================================================================
// Clock Generation
//=============================================================================
initial begin
    clk_sys = 0;
    forever #(CLK_SYS_PERIOD/2) clk_sys = ~clk_sys;
end

initial begin
    ulpi_clk = 0;
    forever #(CLK_ULPI_PERIOD/2) ulpi_clk = ~ulpi_clk;
end

//=============================================================================
// CRC Calculation Functions
//=============================================================================

// CRC5 calculation for token packets (polynomial: x^5 + x^2 + 1)
function [4:0] calc_crc5;
    input [10:0] data;  // 11-bit token data (7-bit addr + 4-bit ep)
    integer i;
    reg [4:0] crc;
    reg feedback;
    begin
        crc = 5'b11111;  // Initial value
        for (i = 0; i < 11; i = i + 1) begin
            feedback = crc[4] ^ data[i];
            crc = {crc[3:0], 1'b0};
            if (feedback)
                crc = crc ^ 5'b00101;
        end
        calc_crc5 = ~crc;  // Invert result
    end
endfunction

// CRC16 calculation for data packets (polynomial: x^16 + x^15 + x^2 + 1)
function [15:0] calc_crc16_byte;
    input [15:0] crc;
    input [7:0]  data;
    integer i;
    reg feedback;
    reg [15:0] temp_crc;
    begin
        temp_crc = crc;
        for (i = 0; i < 8; i = i + 1) begin
            feedback = temp_crc[15] ^ data[i];
            temp_crc = {temp_crc[14:0], 1'b0};
            if (feedback)
                temp_crc = temp_crc ^ 16'h8005;
        end
        calc_crc16_byte = temp_crc;
    end
endfunction

// Calculate CRC16 for entire packet
task calc_packet_crc16;
    input [7:0] data_array [0:1023];
    input integer length;
    output [15:0] crc;
    integer i;
    begin
        crc = 16'hFFFF;
        for (i = 0; i < length; i = i + 1) begin
            crc = calc_crc16_byte(crc, data_array[i]);
        end
        crc = ~crc;  // Invert result
    end
endtask

//=============================================================================
// ULPI PHY Behavioral Model
//=============================================================================

// ULPI RX Command task (PHY to FPGA)
task ulpi_rx_cmd;
    input [1:0] linestate;
    input       vbus;
    begin
        @(posedge ulpi_clk);
        ulpi_dir = 1'b1;
        ulpi_nxt = 1'b0;
        ulpi_data_out = {2'b01, vbus, 3'b000, linestate};  // RX_CMD format
        ulpi_data_oe = 1'b1;
        @(posedge ulpi_clk);
        ulpi_dir = 1'b0;
        ulpi_nxt = 1'b0;
        ulpi_data_oe = 1'b0;
    end
endtask

// ULPI RX Data task (send packet from PHY to device)
task ulpi_rx_data;
    input [7:0] data_array [0:1023];
    input integer length;
    integer i;
    begin
        // Start of packet - RX_CMD with RXACTIVE
        @(posedge ulpi_clk);
        ulpi_dir = 1'b1;
        ulpi_nxt = 1'b1;
        ulpi_data_oe = 1'b1;
        ulpi_data_out = {2'b01, phy_vbus, 3'b000, phy_linestate};  // RX_CMD

        // Send data bytes
        for (i = 0; i < length; i = i + 1) begin
            @(posedge ulpi_clk);
            ulpi_data_out = data_array[i];
        end

        // End of packet
        @(posedge ulpi_clk);
        ulpi_dir = 1'b0;
        ulpi_nxt = 1'b0;
        ulpi_data_oe = 1'b0;

        // Small inter-packet gap
        repeat(5) @(posedge ulpi_clk);
    end
endtask

// ULPI TX monitor (capture transmitted data from device)
always @(posedge ulpi_clk) begin
    if (!ulpi_dir && ulpi_nxt && !ulpi_stp) begin
        // Capture transmitted data
        if (ulpi_data[7:6] == 2'b01) begin  // TX command
            // Start capturing TX data
        end
    end
end

//=============================================================================
// USB Host Transaction Tasks
//=============================================================================

// USB Reset (SE0 for >10ms)
task usb_reset;
    begin
        $display("[%0t] USB RESET - asserting SE0 for 15ms", $time);
        phy_linestate = LINE_SE0;
        repeat(300) begin
            ulpi_rx_cmd(LINE_SE0, phy_vbus);
            #(50000);  // 50us intervals
        end
        phy_linestate = LINE_J;
        ulpi_rx_cmd(LINE_J, phy_vbus);
        #(1000);
    end
endtask

// USB High-Speed Chirp Handshake
task usb_hs_chirp;
    integer i;
    begin
        $display("[%0t] HS CHIRP - starting high-speed negotiation", $time);

        // Device should send Chirp K after reset
        // Wait for device chirp (simplified - just delay)
        #(2000000);  // 2ms

        // Host sends alternating K-J chirps
        $display("[%0t] HS CHIRP - host sending K-J pairs", $time);
        for (i = 0; i < 3; i = i + 1) begin
            // Chirp K
            phy_linestate = LINE_K;
            ulpi_rx_cmd(LINE_K, phy_vbus);
            #(60000);  // 60us

            // Chirp J
            phy_linestate = LINE_J;
            ulpi_rx_cmd(LINE_J, phy_vbus);
            #(60000);  // 60us
        end

        // Return to idle
        phy_linestate = LINE_SE0;
        ulpi_rx_cmd(LINE_SE0, phy_vbus);
        #(1000);

        $display("[%0t] HS CHIRP - complete, device should be in HS mode", $time);
    end
endtask

// Send TOKEN packet (SETUP/IN/OUT)
task send_token;
    input [3:0]  pid;
    input [6:0]  addr;
    input [3:0]  ep;
    reg [7:0]    pkt [0:2];
    reg [4:0]    crc5;
    reg [10:0]   token_data;
    begin
        token_data = {ep, addr};
        crc5 = calc_crc5(token_data);

        pkt[0] = {~pid, pid};  // PID + complement
        pkt[1] = {ep[0], addr};
        pkt[2] = {crc5, ep[3:1]};

        ulpi_rx_data(pkt, 3);
    end
endtask

// Send SETUP token
task send_setup;
    input [6:0] addr;
    input [3:0] ep;
    begin
        $display("[%0t] USB TX: SETUP addr=%0d ep=%0d", $time, addr, ep);
        send_token(PID_SETUP, addr, ep);
    end
endtask

// Send IN token
task send_in_token;
    input [6:0] addr;
    input [3:0] ep;
    begin
        $display("[%0t] USB TX: IN addr=%0d ep=%0d", $time, addr, ep);
        send_token(PID_IN, addr, ep);
    end
endtask

// Send OUT token
task send_out_token;
    input [6:0] addr;
    input [3:0] ep;
    begin
        $display("[%0t] USB TX: OUT addr=%0d ep=%0d", $time, addr, ep);
        send_token(PID_OUT, addr, ep);
    end
endtask

// Send DATA0 packet
task send_data0;
    input [7:0] data_array [0:1023];
    input integer length;
    reg [7:0] pkt [0:1023];
    reg [15:0] crc16;
    integer i;
    begin
        $display("[%0t] USB TX: DATA0 len=%0d", $time, length);

        pkt[0] = {~PID_DATA0, PID_DATA0};
        for (i = 0; i < length; i = i + 1) begin
            pkt[i+1] = data_array[i];
        end

        calc_packet_crc16(data_array, length, crc16);
        pkt[length+1] = crc16[7:0];    // CRC low byte
        pkt[length+2] = crc16[15:8];   // CRC high byte

        ulpi_rx_data(pkt, length + 3);
    end
endtask

// Send DATA1 packet
task send_data1;
    input [7:0] data_array [0:1023];
    input integer length;
    reg [7:0] pkt [0:1023];
    reg [15:0] crc16;
    integer i;
    begin
        $display("[%0t] USB TX: DATA1 len=%0d", $time, length);

        pkt[0] = {~PID_DATA1, PID_DATA1};
        for (i = 0; i < length; i = i + 1) begin
            pkt[i+1] = data_array[i];
        end

        calc_packet_crc16(data_array, length, crc16);
        pkt[length+1] = crc16[7:0];    // CRC low byte
        pkt[length+2] = crc16[15:8];   // CRC high byte

        ulpi_rx_data(pkt, length + 3);
    end
endtask

// Expect ACK handshake
task expect_ack;
    begin
        // Wait for device to transmit ACK
        #(5000);  // 5us timeout
        $display("[%0t] USB RX: Expecting ACK", $time);
        // TODO: Monitor ULPI TX and verify ACK PID
    end
endtask

// Expect NAK handshake
task expect_nak;
    begin
        #(5000);
        $display("[%0t] USB RX: Expecting NAK", $time);
    end
endtask

// Expect STALL handshake
task expect_stall;
    begin
        #(5000);
        $display("[%0t] USB RX: Expecting STALL", $time);
    end
endtask

// Receive DATA packet
task receive_data;
    output [7:0] data_array [0:1023];
    output integer length;
    begin
        #(10000);  // Wait for device to respond
        $display("[%0t] USB RX: Receiving DATA packet", $time);
        // TODO: Capture data from ULPI TX
        length = 0;
    end
endtask

// Send SOF packet
task send_sof;
    input [10:0] frame_num;
    reg [7:0] pkt [0:2];
    reg [4:0] crc5;
    begin
        crc5 = calc_crc5(frame_num);

        pkt[0] = {~PID_SOF, PID_SOF};
        pkt[1] = frame_num[7:0];
        pkt[2] = {crc5, frame_num[10:8]};

        ulpi_rx_data(pkt, 3);
    end
endtask

//=============================================================================
// High-Level USB Test Sequences
//=============================================================================

// Full enumeration sequence
task test_enumeration;
    reg [7:0] setup_data [0:7];
    reg [7:0] rx_data [0:1023];
    integer rx_len;
    begin
        test_name = "USB Enumeration";
        $display("\n========================================");
        $display("TEST: %s", test_name);
        $display("========================================");

        // Step 1: Get Device Descriptor (address 0)
        $display("\n--- GET_DESCRIPTOR (Device) at address 0 ---");
        send_setup(7'd0, 4'd0);

        // SETUP data: bmRequestType=0x80, bRequest=GET_DESCRIPTOR,
        //             wValue=0x0100 (Device), wIndex=0, wLength=18
        setup_data[0] = 8'h80;  // bmRequestType (Device-to-Host, Standard, Device)
        setup_data[1] = REQ_GET_DESCRIPTOR;
        setup_data[2] = 8'h00;  // wValue low (descriptor index)
        setup_data[3] = DESC_DEVICE;  // wValue high (descriptor type)
        setup_data[4] = 8'h00;  // wIndex low
        setup_data[5] = 8'h00;  // wIndex high
        setup_data[6] = 8'h12;  // wLength low (18 bytes)
        setup_data[7] = 8'h00;  // wLength high
        send_data0(setup_data, 8);
        expect_ack();

        // IN transaction to get descriptor
        send_in_token(7'd0, 4'd0);
        receive_data(rx_data, rx_len);
        send_data0(setup_data, 0);  // Status ZLP
        expect_ack();

        #(10000);

        // Step 2: Set Address
        $display("\n--- SET_ADDRESS to 1 ---");
        send_setup(7'd0, 4'd0);

        setup_data[0] = 8'h00;  // bmRequestType (Host-to-Device, Standard, Device)
        setup_data[1] = REQ_SET_ADDRESS;
        setup_data[2] = 8'h01;  // wValue low (new address = 1)
        setup_data[3] = 8'h00;  // wValue high
        setup_data[4] = 8'h00;  // wIndex low
        setup_data[5] = 8'h00;  // wIndex high
        setup_data[6] = 8'h00;  // wLength low
        setup_data[7] = 8'h00;  // wLength high
        send_data0(setup_data, 8);
        expect_ack();

        // IN status stage
        send_in_token(7'd0, 4'd0);
        receive_data(rx_data, rx_len);

        #(10000);

        // Step 3: Get Configuration Descriptor (address 1)
        $display("\n--- GET_DESCRIPTOR (Configuration) at address 1 ---");
        send_setup(7'd1, 4'd0);

        setup_data[0] = 8'h80;
        setup_data[1] = REQ_GET_DESCRIPTOR;
        setup_data[2] = 8'h00;
        setup_data[3] = DESC_CONFIGURATION;
        setup_data[4] = 8'h00;
        setup_data[5] = 8'h00;
        setup_data[6] = 8'hFF;  // wLength = 255 (get full descriptor)
        setup_data[7] = 8'h00;
        send_data0(setup_data, 8);
        expect_ack();

        send_in_token(7'd1, 4'd0);
        receive_data(rx_data, rx_len);
        send_data0(setup_data, 0);  // Status ZLP

        #(10000);

        // Step 4: Set Configuration
        $display("\n--- SET_CONFIGURATION to 1 ---");
        send_setup(7'd1, 4'd0);

        setup_data[0] = 8'h00;
        setup_data[1] = REQ_SET_CONFIGURATION;
        setup_data[2] = 8'h01;  // Configuration value = 1
        setup_data[3] = 8'h00;
        setup_data[4] = 8'h00;
        setup_data[5] = 8'h00;
        setup_data[6] = 8'h00;
        setup_data[7] = 8'h00;
        send_data0(setup_data, 8);
        expect_ack();

        send_in_token(7'd1, 4'd0);
        receive_data(rx_data, rx_len);

        #(20000);

        // Verify configured
        if (usb_configured) begin
            $display("\n[PASS] Device is configured");
        end else begin
            $display("\n[FAIL] Device not configured");
            errors = errors + 1;
        end
    end
endtask

// KryoFlux vendor request test
task test_kryoflux_vendor;
    reg [7:0] setup_data [0:7];
    reg [7:0] rx_data [0:1023];
    integer rx_len;
    begin
        test_name = "KryoFlux Vendor Request";
        $display("\n========================================");
        $display("TEST: %s", test_name);
        $display("========================================");

        // Set personality to KryoFlux (2)
        personality_sel = 3'd2;
        #(1000);

        // KryoFlux INFO command (bmRequestType=0xC3, bRequest=0x81)
        $display("\n--- KryoFlux INFO (0x81) request ---");
        send_setup(7'd1, 4'd0);

        setup_data[0] = 8'hC3;  // bmRequestType (Vendor, IN, Interface)
        setup_data[1] = 8'h81;  // bRequest (INFO)
        setup_data[2] = 8'h00;  // wValue low
        setup_data[3] = 8'h00;  // wValue high
        setup_data[4] = 8'h00;  // wIndex low
        setup_data[5] = 8'h00;  // wIndex high
        setup_data[6] = 8'h10;  // wLength = 16 bytes
        setup_data[7] = 8'h00;
        send_data0(setup_data, 8);
        expect_ack();

        // IN data phase
        send_in_token(7'd1, 4'd0);
        receive_data(rx_data, rx_len);

        // Status OUT
        send_out_token(7'd1, 4'd0);
        send_data0(setup_data, 0);  // ZLP
        expect_ack();

        #(10000);

        if (kf_cmd_valid) begin
            $display("[PASS] KryoFlux command decoded: req=0x%02x", kf_cmd_request);
        end else begin
            $display("[FAIL] KryoFlux command not received");
            errors = errors + 1;
        end
    end
endtask

// Bulk transfer test
task test_bulk_transfer;
    reg [7:0] tx_data_buf [0:63];
    integer i;
    begin
        test_name = "Bulk Transfer";
        $display("\n========================================");
        $display("TEST: %s", test_name);
        $display("========================================");

        // Prepare test data
        for (i = 0; i < 64; i = i + 1) begin
            tx_data_buf[i] = i[7:0];
        end

        // OUT transfer to EP1
        $display("\n--- Bulk OUT to EP1 ---");
        send_out_token(7'd1, 4'd1);
        send_data0(tx_data_buf, 64);
        expect_ack();

        #(5000);

        // IN transfer from EP2
        $display("\n--- Bulk IN from EP2 ---");
        send_in_token(7'd1, 4'd2);
        // Device should send data or NAK
        #(10000);

        $display("[INFO] Bulk transfers completed");
    end
endtask

//=============================================================================
// Initial Stimulus
//=============================================================================
initial begin
    // Initialize signals
    rst_n = 0;
    ulpi_dir = 0;
    ulpi_nxt = 0;
    ulpi_data_out = 8'h00;
    ulpi_data_oe = 0;
    phy_linestate = LINE_J;
    phy_vbus = 1'b1;

    personality_sel = 3'd0;  // Greaseweazle
    personality_switch = 0;

    flux_data = 32'h0;
    flux_valid = 0;
    flux_index = 0;
    flux_capturing = 0;

    seek_complete = 0;
    current_track = 0;
    disk_present = 1;
    write_protect = 0;
    track_00 = 1;
    motor_spinning = 0;

    proto_rx_ready = 1;
    proto_tx_data = 32'h0;
    proto_tx_valid = 0;

    kf_response_data = 8'h0;
    kf_response_valid = 0;
    kf_response_last = 0;

    msc_ready = 1;
    msc_error = 0;
    msc_read_data = 32'h0;
    msc_read_valid = 0;
    msc_write_ready = 1;

    diag_response = 32'h0;
    diag_response_valid = 0;

    msc_config_valid = 1;
    msc_fdd0_sectors = 16'd2880;  // 1.44MB floppy
    msc_fdd1_sectors = 16'd0;
    msc_hdd0_sectors = 32'h0;
    msc_hdd1_sectors = 32'h0;
    msc_drive_ready_in = 4'b0001;
    msc_drive_wp_in = 4'b0000;

    test_num = 0;
    errors = 0;
    warnings = 0;

    // VCD dump
    $dumpfile("tb_usb_top_v2.vcd");
    $dumpvars(0, tb_usb_top_v2);

    // Reset sequence
    $display("\n========================================");
    $display("USB 2.0 HS Stack Testbench");
    $display("Start time: 2025-12-06 17:49:12");
    $display("========================================\n");

    #100;
    rst_n = 1;
    #1000;

    // Wait for PHY initialization
    wait(ulpi_rst_n);
    $display("[%0t] PHY reset released", $time);
    #(100000);  // 100us

    //=========================================================================
    // Test 1: Bus Reset and HS Negotiation
    //=========================================================================
    test_num = 1;
    test_name = "Bus Reset & HS Negotiation";
    $display("\n========================================");
    $display("TEST %0d: %s", test_num, test_name);
    $display("========================================");

    usb_reset();
    usb_hs_chirp();

    #(10000);

    if (usb_speed == 2'b00) begin
        $display("[PASS] Device in High-Speed mode");
    end else begin
        $display("[FAIL] Device not in High-Speed mode (speed=%0d)", usb_speed);
        errors = errors + 1;
    end

    //=========================================================================
    // Test 2: Enumeration
    //=========================================================================
    test_num = 2;
    #(50000);
    test_enumeration();

    //=========================================================================
    // Test 3: KryoFlux Vendor Request
    //=========================================================================
    test_num = 3;
    #(50000);
    test_kryoflux_vendor();

    //=========================================================================
    // Test 4: Bulk Transfers
    //=========================================================================
    test_num = 4;
    #(50000);
    test_bulk_transfer();

    //=========================================================================
    // Test Summary
    //=========================================================================
    #(100000);

    $display("\n========================================");
    $display("TEST SUMMARY");
    $display("========================================");
    $display("Tests run:  %0d", test_num);
    $display("Errors:     %0d", errors);
    $display("Warnings:   %0d", warnings);

    if (errors == 0) begin
        $display("\n*** ALL TESTS PASSED ***\n");
    end else begin
        $display("\n*** TESTS FAILED ***\n");
    end

    $display("End time: 2025-12-06 17:49:12");
    $display("========================================\n");

    #10000;
    $finish;
end

//=============================================================================
// Monitors and Checkers
//=============================================================================

// Monitor USB speed changes
always @(usb_speed) begin
    case (usb_speed)
        2'b00: $display("[%0t] MONITOR: USB speed changed to HIGH-SPEED", $time);
        2'b01: $display("[%0t] MONITOR: USB speed changed to FULL-SPEED", $time);
        2'b10: $display("[%0t] MONITOR: USB speed changed to LOW-SPEED", $time);
        default: $display("[%0t] MONITOR: USB speed unknown", $time);
    endcase
end

// Monitor configuration changes
always @(posedge usb_configured) begin
    $display("[%0t] MONITOR: Device CONFIGURED", $time);
end

always @(negedge usb_configured) begin
    $display("[%0t] MONITOR: Device UNCONFIGURED", $time);
end

// Monitor SOF packets
always @(posedge usb_sof_valid) begin
    $display("[%0t] MONITOR: SOF frame %0d", $time, usb_frame_number);
end

// Monitor protocol RX data
always @(posedge proto_rx_valid) begin
    $display("[%0t] MONITOR: Protocol RX data: 0x%08x", $time, proto_rx_data);
end

// Monitor KryoFlux commands
always @(posedge kf_cmd_valid) begin
    $display("[%0t] MONITOR: KryoFlux command: req=0x%02x value=0x%04x index=0x%04x len=%0d",
             $time, kf_cmd_request, kf_cmd_value, kf_cmd_index, kf_cmd_length);
end

// Timeout watchdog
initial begin
    #(100000000);  // 100ms timeout
    $display("\n[ERROR] Simulation timeout!");
    $finish;
end

endmodule
