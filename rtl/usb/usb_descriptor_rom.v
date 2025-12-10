// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// usb_descriptor_rom.v - USB Descriptor ROM with Multi-Personality Support
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
//
// Created: 2025-12-06 11:05:00
// Updated: 2025-12-06 22:15:00
//-----------------------------------------------------------------------------
// Stores USB descriptors for four device personalities:
//   0: Greaseweazle F7  (VID:1209 PID:4D69) - Greaseweazle compatibility
//   1: HxC Floppy       (VID:16D0 PID:0FD2) - HxC software compatibility
//   2: KryoFlux         (VID:03EB PID:6124) - DTC compatibility
//   3: FluxRipper       (VID:1209 PID:FB01) - Native + MSC + CDC composite
//
// Descriptors can be switched at runtime via personality_sel input.
//
// FluxRipper Native (Personality 3) - Full Composite Device:
//   This is the recommended default personality providing simultaneous access to:
//   - Mass Storage Class (MSC) for drag-and-drop disk image access
//   - Vendor interface for full FluxRipper native protocol
//   - CDC ACM for debug console
//
// Interface Layout (Personality 3 - FluxRipper):
//   Interface 0: Mass Storage Class (SCSI BBB)
//     EP1 OUT/IN: SCSI Bulk-Only Transport
//   Interface 1: Vendor (FluxRipper Native Protocol)
//     EP2 OUT/IN: Commands, responses, flux data
//   Interface 2: CDC Communication (control, no endpoints)
//   Interface 3: CDC Data
//     EP3 OUT/IN: Debug console serial data
//
// Endpoint Usage Summary:
//   Greaseweazle (P0), HxC (P1):
//     EP1 OUT/IN: Vendor protocol data
//     EP3 OUT/IN: CDC ACM serial data
//   KryoFlux (P2):
//     EP2 IN:     KryoFlux streaming data
//     EP3 OUT/IN: CDC ACM serial data
//   FluxRipper (P3):
//     EP1 OUT/IN: MSC SCSI Bulk-Only
//     EP2 OUT/IN: FluxRipper native protocol
//     EP3 OUT/IN: CDC ACM serial data
//-----------------------------------------------------------------------------

module usb_descriptor_rom #(
    parameter NUM_PERSONALITIES = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    // Personality Selection
    input  wire [2:0]  personality,        // 0-4 (alias: personality_sel)

    // Descriptor Read Interface
    input  wire [7:0]  desc_type,         // Descriptor type (1=Device, 2=Config, 3=String)
    input  wire [7:0]  desc_index,        // Descriptor index (for strings)
    input  wire [15:0] desc_length,       // Requested length
    input  wire        desc_request,      // Request strobe (alias: desc_read)

    output reg  [7:0]  desc_data,         // Descriptor byte
    output reg         desc_valid,        // Data valid
    output reg         desc_last,         // Last byte of descriptor

    // Device Information (active personality)
    output reg  [15:0] vid,               // Vendor ID
    output reg  [15:0] pid,               // Product ID
    output reg  [7:0]  device_class,      // Device class
    output reg  [7:0]  device_subclass,
    output reg  [7:0]  device_protocol
);

    //=========================================================================
    // Descriptor Types
    //=========================================================================

    localparam DESC_DEVICE        = 8'h01;
    localparam DESC_CONFIGURATION = 8'h02;
    localparam DESC_STRING        = 8'h03;
    localparam DESC_INTERFACE     = 8'h04;
    localparam DESC_ENDPOINT      = 8'h05;
    localparam DESC_QUALIFIER     = 8'h06;
    localparam DESC_OTHER_SPEED   = 8'h07;
    localparam DESC_IAD           = 8'h0B;  // Interface Association Descriptor
    localparam DESC_CS_INTERFACE  = 8'h24;  // Class-Specific Interface

    //=========================================================================
    // Personality Parameters
    //=========================================================================

    // VID/PID for each personality
    localparam [15:0] VID_GW   = 16'h1209;  // pid.codes
    localparam [15:0] PID_GW   = 16'h4D69;  // Greaseweazle

    localparam [15:0] VID_HXC  = 16'h16D0;  // MCS Electronics
    localparam [15:0] PID_HXC  = 16'h0FD2;  // HxC Floppy Emulator

    localparam [15:0] VID_KF   = 16'h03EB;  // Atmel
    localparam [15:0] PID_KF   = 16'h6124;  // KryoFlux

    localparam [15:0] VID_FR   = 16'h1209;  // pid.codes
    localparam [15:0] PID_FR   = 16'hFB01;  // FluxRipper Native + MSC + CDC

    //=========================================================================
    // Device Descriptors (18 bytes each)
    //=========================================================================

    // Device descriptor structure:
    // [0]  bLength = 18
    // [1]  bDescriptorType = 1
    // [2-3]  bcdUSB = 0x0200 (USB 2.0)
    // [4]  bDeviceClass
    // [5]  bDeviceSubClass
    // [6]  bDeviceProtocol
    // [7]  bMaxPacketSize0 = 64
    // [8-9]  idVendor
    // [10-11] idProduct
    // [12-13] bcdDevice
    // [14] iManufacturer
    // [15] iProduct
    // [16] iSerialNumber
    // [17] bNumConfigurations = 1

    reg [7:0] device_desc [0:3][0:17];

    initial begin
        // Greaseweazle F7
        // Using IAD composite device class for proper Windows driver binding
        device_desc[0][0]  = 8'd18;        // bLength
        device_desc[0][1]  = 8'h01;        // bDescriptorType
        device_desc[0][2]  = 8'h00;        // bcdUSB LSB
        device_desc[0][3]  = 8'h02;        // bcdUSB MSB (2.00)
        device_desc[0][4]  = 8'hEF;        // bDeviceClass (Misc - IAD composite)
        device_desc[0][5]  = 8'h02;        // bDeviceSubClass (Common Class)
        device_desc[0][6]  = 8'h01;        // bDeviceProtocol (IAD)
        device_desc[0][7]  = 8'd64;        // bMaxPacketSize0
        device_desc[0][8]  = VID_GW[7:0];  // idVendor LSB
        device_desc[0][9]  = VID_GW[15:8]; // idVendor MSB
        device_desc[0][10] = PID_GW[7:0];  // idProduct LSB
        device_desc[0][11] = PID_GW[15:8]; // idProduct MSB
        device_desc[0][12] = 8'h00;        // bcdDevice LSB
        device_desc[0][13] = 8'h01;        // bcdDevice MSB (1.00)
        device_desc[0][14] = 8'd1;         // iManufacturer
        device_desc[0][15] = 8'd2;         // iProduct
        device_desc[0][16] = 8'd3;         // iSerialNumber
        device_desc[0][17] = 8'd1;         // bNumConfigurations

        // HxC Floppy Emulator (IAD composite)
        device_desc[1][0]  = 8'd18;
        device_desc[1][1]  = 8'h01;
        device_desc[1][2]  = 8'h00;
        device_desc[1][3]  = 8'h02;
        device_desc[1][4]  = 8'hEF;        // bDeviceClass (Misc - IAD composite)
        device_desc[1][5]  = 8'h02;        // bDeviceSubClass (Common Class)
        device_desc[1][6]  = 8'h01;        // bDeviceProtocol (IAD)
        device_desc[1][7]  = 8'd64;
        device_desc[1][8]  = VID_HXC[7:0];
        device_desc[1][9]  = VID_HXC[15:8];
        device_desc[1][10] = PID_HXC[7:0];
        device_desc[1][11] = PID_HXC[15:8];
        device_desc[1][12] = 8'h00;
        device_desc[1][13] = 8'h01;
        device_desc[1][14] = 8'd1;
        device_desc[1][15] = 8'd2;
        device_desc[1][16] = 8'd3;
        device_desc[1][17] = 8'd1;

        // KryoFlux (IAD composite)
        device_desc[2][0]  = 8'd18;
        device_desc[2][1]  = 8'h01;
        device_desc[2][2]  = 8'h00;
        device_desc[2][3]  = 8'h02;
        device_desc[2][4]  = 8'hEF;        // bDeviceClass (Misc - IAD composite)
        device_desc[2][5]  = 8'h02;        // bDeviceSubClass (Common Class)
        device_desc[2][6]  = 8'h01;        // bDeviceProtocol (IAD)
        device_desc[2][7]  = 8'd64;
        device_desc[2][8]  = VID_KF[7:0];
        device_desc[2][9]  = VID_KF[15:8];
        device_desc[2][10] = PID_KF[7:0];
        device_desc[2][11] = PID_KF[15:8];
        device_desc[2][12] = 8'h00;
        device_desc[2][13] = 8'h01;
        device_desc[2][14] = 8'd1;
        device_desc[2][15] = 8'd2;
        device_desc[2][16] = 8'd3;
        device_desc[2][17] = 8'd1;

        // FluxRipper Native + MSC + CDC (Full Composite - RECOMMENDED DEFAULT)
        // This personality provides simultaneous access to:
        // - Mass Storage for drag-and-drop disk images
        // - Vendor interface for full FluxRipper protocol
        // - CDC ACM for debug console
        device_desc[3][0]  = 8'd18;
        device_desc[3][1]  = 8'h01;
        device_desc[3][2]  = 8'h00;
        device_desc[3][3]  = 8'h02;
        device_desc[3][4]  = 8'hEF;        // bDeviceClass (Misc - IAD composite)
        device_desc[3][5]  = 8'h02;        // bDeviceSubClass (Common Class)
        device_desc[3][6]  = 8'h01;        // bDeviceProtocol (IAD)
        device_desc[3][7]  = 8'd64;
        device_desc[3][8]  = VID_FR[7:0];
        device_desc[3][9]  = VID_FR[15:8];
        device_desc[3][10] = PID_FR[7:0];
        device_desc[3][11] = PID_FR[15:8];
        device_desc[3][12] = 8'h00;
        device_desc[3][13] = 8'h01;
        device_desc[3][14] = 8'd1;         // iManufacturer
        device_desc[3][15] = 8'd2;         // iProduct
        device_desc[3][16] = 8'd3;         // iSerialNumber
        device_desc[3][17] = 8'd1;         // bNumConfigurations
    end

    //=========================================================================
    // Configuration Descriptors
    //=========================================================================

    // Configuration descriptor sizes:
    // - Personalities 0,1 (GW, HxC): Vendor + CDC = 91 bytes
    // - Personality 2 (KryoFlux): Vendor (EP2 IN only) + CDC = 84 bytes
    // - Personality 3 (FluxRipper): MSC + Vendor + CDC = 114 bytes
    //
    // FluxRipper (P3) breakdown:
    // - Config descriptor: 9 bytes
    // - Interface 0 (MSC): 9 + 7 + 7 = 23 bytes
    // - Interface 1 (Vendor): 9 + 7 + 7 = 23 bytes
    // - IAD (CDC): 8 bytes
    // - Interface 2 (CDC Comm): 9 + 5 + 5 + 4 + 5 = 28 bytes
    // - Interface 3 (CDC Data): 9 + 7 + 7 = 23 bytes
    // Total: 9 + 23 + 23 + 8 + 28 + 23 = 114 bytes
    //
    // Array size: 128 bytes to allow for future expansion

    reg [7:0] config_desc [0:3][0:127];

    initial begin
        //=====================================================================
        // Greaseweazle Configuration with CDC ACM
        //=====================================================================

        // Configuration descriptor
        config_desc[0][0]  = 8'd9;         // bLength
        config_desc[0][1]  = 8'h02;        // bDescriptorType
        config_desc[0][2]  = 8'd91;        // wTotalLength LSB (91 bytes total)
        config_desc[0][3]  = 8'd0;         // wTotalLength MSB
        config_desc[0][4]  = 8'd3;         // bNumInterfaces (0: Vendor, 1: CDC Comm, 2: CDC Data)
        config_desc[0][5]  = 8'd1;         // bConfigurationValue
        config_desc[0][6]  = 8'd0;         // iConfiguration
        config_desc[0][7]  = 8'h80;        // bmAttributes (bus powered)
        config_desc[0][8]  = 8'd250;       // bMaxPower (500mA)

        // Interface 0: Vendor-specific (Greaseweazle protocol)
        config_desc[0][9]  = 8'd9;         // bLength
        config_desc[0][10] = 8'h04;        // bDescriptorType
        config_desc[0][11] = 8'd0;         // bInterfaceNumber
        config_desc[0][12] = 8'd0;         // bAlternateSetting
        config_desc[0][13] = 8'd2;         // bNumEndpoints
        config_desc[0][14] = 8'hFF;        // bInterfaceClass (Vendor)
        config_desc[0][15] = 8'h00;        // bInterfaceSubClass
        config_desc[0][16] = 8'h00;        // bInterfaceProtocol
        config_desc[0][17] = 8'd0;         // iInterface

        // EP1 OUT (Bulk)
        config_desc[0][18] = 8'd7;         // bLength
        config_desc[0][19] = 8'h05;        // bDescriptorType
        config_desc[0][20] = 8'h01;        // bEndpointAddress (EP1 OUT)
        config_desc[0][21] = 8'h02;        // bmAttributes (Bulk)
        config_desc[0][22] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[0][23] = 8'h02;        // wMaxPacketSize MSB
        config_desc[0][24] = 8'd0;         // bInterval

        // EP1 IN (Bulk)
        config_desc[0][25] = 8'd7;         // bLength
        config_desc[0][26] = 8'h05;        // bDescriptorType
        config_desc[0][27] = 8'h81;        // bEndpointAddress (EP1 IN)
        config_desc[0][28] = 8'h02;        // bmAttributes (Bulk)
        config_desc[0][29] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[0][30] = 8'h02;        // wMaxPacketSize MSB
        config_desc[0][31] = 8'd0;         // bInterval

        // Interface Association Descriptor (IAD) for CDC
        config_desc[0][32] = 8'd8;         // bLength
        config_desc[0][33] = 8'h0B;        // bDescriptorType (IAD)
        config_desc[0][34] = 8'd1;         // bFirstInterface (CDC starts at interface 1)
        config_desc[0][35] = 8'd2;         // bInterfaceCount (Comm + Data)
        config_desc[0][36] = 8'h02;        // bFunctionClass (CDC)
        config_desc[0][37] = 8'h02;        // bFunctionSubClass (ACM)
        config_desc[0][38] = 8'h00;        // bFunctionProtocol
        config_desc[0][39] = 8'd0;         // iFunction

        // Interface 1: CDC Communication Interface
        config_desc[0][40] = 8'd9;         // bLength
        config_desc[0][41] = 8'h04;        // bDescriptorType
        config_desc[0][42] = 8'd1;         // bInterfaceNumber
        config_desc[0][43] = 8'd0;         // bAlternateSetting
        config_desc[0][44] = 8'd0;         // bNumEndpoints (no interrupt endpoint)
        config_desc[0][45] = 8'h02;        // bInterfaceClass (CDC)
        config_desc[0][46] = 8'h02;        // bInterfaceSubClass (ACM)
        config_desc[0][47] = 8'h00;        // bInterfaceProtocol
        config_desc[0][48] = 8'd0;         // iInterface

        // CDC Header Functional Descriptor
        config_desc[0][49] = 8'd5;         // bLength
        config_desc[0][50] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[0][51] = 8'h00;        // bDescriptorSubtype (Header)
        config_desc[0][52] = 8'h10;        // bcdCDC LSB (1.10)
        config_desc[0][53] = 8'h01;        // bcdCDC MSB

        // CDC Call Management Functional Descriptor
        config_desc[0][54] = 8'd5;         // bLength
        config_desc[0][55] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[0][56] = 8'h01;        // bDescriptorSubtype (Call Management)
        config_desc[0][57] = 8'h00;        // bmCapabilities (no call management)
        config_desc[0][58] = 8'd2;         // bDataInterface (interface 2)

        // CDC ACM Functional Descriptor
        config_desc[0][59] = 8'd4;         // bLength
        config_desc[0][60] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[0][61] = 8'h02;        // bDescriptorSubtype (ACM)
        config_desc[0][62] = 8'h02;        // bmCapabilities (supports line coding + serial state)

        // CDC Union Functional Descriptor
        config_desc[0][63] = 8'd5;         // bLength
        config_desc[0][64] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[0][65] = 8'h06;        // bDescriptorSubtype (Union)
        config_desc[0][66] = 8'd1;         // bMasterInterface (comm interface 1)
        config_desc[0][67] = 8'd2;         // bSlaveInterface0 (data interface 2)

        // Interface 2: CDC Data Interface
        config_desc[0][68] = 8'd9;         // bLength
        config_desc[0][69] = 8'h04;        // bDescriptorType
        config_desc[0][70] = 8'd2;         // bInterfaceNumber
        config_desc[0][71] = 8'd0;         // bAlternateSetting
        config_desc[0][72] = 8'd2;         // bNumEndpoints
        config_desc[0][73] = 8'h0A;        // bInterfaceClass (CDC Data)
        config_desc[0][74] = 8'h00;        // bInterfaceSubClass
        config_desc[0][75] = 8'h00;        // bInterfaceProtocol
        config_desc[0][76] = 8'd0;         // iInterface

        // EP3 OUT (Bulk) - CDC Data
        config_desc[0][77] = 8'd7;         // bLength
        config_desc[0][78] = 8'h05;        // bDescriptorType
        config_desc[0][79] = 8'h03;        // bEndpointAddress (EP3 OUT)
        config_desc[0][80] = 8'h02;        // bmAttributes (Bulk)
        config_desc[0][81] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[0][82] = 8'h02;        // wMaxPacketSize MSB
        config_desc[0][83] = 8'd0;         // bInterval

        // EP3 IN (Bulk) - CDC Data
        config_desc[0][84] = 8'd7;         // bLength
        config_desc[0][85] = 8'h05;        // bDescriptorType
        config_desc[0][86] = 8'h83;        // bEndpointAddress (EP3 IN)
        config_desc[0][87] = 8'h02;        // bmAttributes (Bulk)
        config_desc[0][88] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[0][89] = 8'h02;        // wMaxPacketSize MSB
        config_desc[0][90] = 8'd0;         // bInterval

        // Zero-fill remaining bytes (91-127)
        config_desc[0][91] = 8'd0; config_desc[0][92] = 8'd0; config_desc[0][93] = 8'd0;
        config_desc[0][94] = 8'd0; config_desc[0][95] = 8'd0; config_desc[0][96] = 8'd0;
        config_desc[0][97] = 8'd0;

        //=====================================================================
        // HxC Configuration (same as Greaseweazle)
        // Note: Copying config_desc[0] element by element for Verilog compatibility
        //=====================================================================
        config_desc[1][0] = config_desc[0][0];
        config_desc[1][1] = config_desc[0][1];
        config_desc[1][2] = config_desc[0][2];
        config_desc[1][3] = config_desc[0][3];
        config_desc[1][4] = config_desc[0][4];
        config_desc[1][5] = config_desc[0][5];
        config_desc[1][6] = config_desc[0][6];
        config_desc[1][7] = config_desc[0][7];
        config_desc[1][8] = config_desc[0][8];
        config_desc[1][9] = config_desc[0][9];
        config_desc[1][10] = config_desc[0][10];
        config_desc[1][11] = config_desc[0][11];
        config_desc[1][12] = config_desc[0][12];
        config_desc[1][13] = config_desc[0][13];
        config_desc[1][14] = config_desc[0][14];
        config_desc[1][15] = config_desc[0][15];
        config_desc[1][16] = config_desc[0][16];
        config_desc[1][17] = config_desc[0][17];
        config_desc[1][18] = config_desc[0][18];
        config_desc[1][19] = config_desc[0][19];
        config_desc[1][20] = config_desc[0][20];
        config_desc[1][21] = config_desc[0][21];
        config_desc[1][22] = config_desc[0][22];
        config_desc[1][23] = config_desc[0][23];
        config_desc[1][24] = config_desc[0][24];
        config_desc[1][25] = config_desc[0][25];
        config_desc[1][26] = config_desc[0][26];
        config_desc[1][27] = config_desc[0][27];
        config_desc[1][28] = config_desc[0][28];
        config_desc[1][29] = config_desc[0][29];
        config_desc[1][30] = config_desc[0][30];
        config_desc[1][31] = config_desc[0][31];

        //=====================================================================
        // KryoFlux Configuration with CDC ACM
        //=====================================================================
        // KryoFlux only uses EP2 IN for streaming

        // Configuration descriptor
        config_desc[2][0]  = 8'd9;         // bLength
        config_desc[2][1]  = 8'h02;        // bDescriptorType
        config_desc[2][2]  = 8'd84;        // wTotalLength LSB (84 bytes total)
        config_desc[2][3]  = 8'd0;         // wTotalLength MSB
        config_desc[2][4]  = 8'd3;         // bNumInterfaces (0: Vendor, 1: CDC Comm, 2: CDC Data)
        config_desc[2][5]  = 8'd1;         // bConfigurationValue
        config_desc[2][6]  = 8'd0;         // iConfiguration
        config_desc[2][7]  = 8'h80;        // bmAttributes (bus powered)
        config_desc[2][8]  = 8'd250;       // bMaxPower (500mA)

        // Interface 0: Vendor-specific (KryoFlux protocol)
        config_desc[2][9]  = 8'd9;         // bLength
        config_desc[2][10] = 8'h04;        // bDescriptorType
        config_desc[2][11] = 8'd0;         // bInterfaceNumber
        config_desc[2][12] = 8'd0;         // bAlternateSetting
        config_desc[2][13] = 8'd1;         // bNumEndpoints (1 endpoint for KryoFlux)
        config_desc[2][14] = 8'hFF;        // bInterfaceClass (Vendor)
        config_desc[2][15] = 8'h00;        // bInterfaceSubClass
        config_desc[2][16] = 8'h00;        // bInterfaceProtocol
        config_desc[2][17] = 8'd0;         // iInterface

        // EP2 IN (Bulk) - KryoFlux uses EP2 for data streaming
        config_desc[2][18] = 8'd7;         // bLength
        config_desc[2][19] = 8'h05;        // bDescriptorType
        config_desc[2][20] = 8'h82;        // bEndpointAddress (EP2 IN)
        config_desc[2][21] = 8'h02;        // bmAttributes (Bulk)
        config_desc[2][22] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[2][23] = 8'h02;        // wMaxPacketSize MSB
        config_desc[2][24] = 8'd0;         // bInterval

        // Interface Association Descriptor (IAD) for CDC
        config_desc[2][25] = 8'd8;         // bLength
        config_desc[2][26] = 8'h0B;        // bDescriptorType (IAD)
        config_desc[2][27] = 8'd1;         // bFirstInterface (CDC starts at interface 1)
        config_desc[2][28] = 8'd2;         // bInterfaceCount (Comm + Data)
        config_desc[2][29] = 8'h02;        // bFunctionClass (CDC)
        config_desc[2][30] = 8'h02;        // bFunctionSubClass (ACM)
        config_desc[2][31] = 8'h00;        // bFunctionProtocol
        config_desc[2][32] = 8'd0;         // iFunction

        // Interface 1: CDC Communication Interface
        config_desc[2][33] = 8'd9;         // bLength
        config_desc[2][34] = 8'h04;        // bDescriptorType
        config_desc[2][35] = 8'd1;         // bInterfaceNumber
        config_desc[2][36] = 8'd0;         // bAlternateSetting
        config_desc[2][37] = 8'd0;         // bNumEndpoints (no interrupt endpoint)
        config_desc[2][38] = 8'h02;        // bInterfaceClass (CDC)
        config_desc[2][39] = 8'h02;        // bInterfaceSubClass (ACM)
        config_desc[2][40] = 8'h00;        // bInterfaceProtocol
        config_desc[2][41] = 8'd0;         // iInterface

        // CDC Header Functional Descriptor
        config_desc[2][42] = 8'd5;         // bLength
        config_desc[2][43] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[2][44] = 8'h00;        // bDescriptorSubtype (Header)
        config_desc[2][45] = 8'h10;        // bcdCDC LSB (1.10)
        config_desc[2][46] = 8'h01;        // bcdCDC MSB

        // CDC Call Management Functional Descriptor
        config_desc[2][47] = 8'd5;         // bLength
        config_desc[2][48] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[2][49] = 8'h01;        // bDescriptorSubtype (Call Management)
        config_desc[2][50] = 8'h00;        // bmCapabilities (no call management)
        config_desc[2][51] = 8'd2;         // bDataInterface (interface 2)

        // CDC ACM Functional Descriptor
        config_desc[2][52] = 8'd4;         // bLength
        config_desc[2][53] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[2][54] = 8'h02;        // bDescriptorSubtype (ACM)
        config_desc[2][55] = 8'h02;        // bmCapabilities (supports line coding + serial state)

        // CDC Union Functional Descriptor
        config_desc[2][56] = 8'd5;         // bLength
        config_desc[2][57] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[2][58] = 8'h06;        // bDescriptorSubtype (Union)
        config_desc[2][59] = 8'd1;         // bMasterInterface (comm interface 1)
        config_desc[2][60] = 8'd2;         // bSlaveInterface0 (data interface 2)

        // Interface 2: CDC Data Interface
        config_desc[2][61] = 8'd9;         // bLength
        config_desc[2][62] = 8'h04;        // bDescriptorType
        config_desc[2][63] = 8'd2;         // bInterfaceNumber
        config_desc[2][64] = 8'd0;         // bAlternateSetting
        config_desc[2][65] = 8'd2;         // bNumEndpoints
        config_desc[2][66] = 8'h0A;        // bInterfaceClass (CDC Data)
        config_desc[2][67] = 8'h00;        // bInterfaceSubClass
        config_desc[2][68] = 8'h00;        // bInterfaceProtocol
        config_desc[2][69] = 8'd0;         // iInterface

        // EP3 OUT (Bulk) - CDC Data
        config_desc[2][70] = 8'd7;         // bLength
        config_desc[2][71] = 8'h05;        // bDescriptorType
        config_desc[2][72] = 8'h03;        // bEndpointAddress (EP3 OUT)
        config_desc[2][73] = 8'h02;        // bmAttributes (Bulk)
        config_desc[2][74] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[2][75] = 8'h02;        // wMaxPacketSize MSB
        config_desc[2][76] = 8'd0;         // bInterval

        // EP3 IN (Bulk) - CDC Data
        config_desc[2][77] = 8'd7;         // bLength
        config_desc[2][78] = 8'h05;        // bDescriptorType
        config_desc[2][79] = 8'h83;        // bEndpointAddress (EP3 IN)
        config_desc[2][80] = 8'h02;        // bmAttributes (Bulk)
        config_desc[2][81] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[2][82] = 8'h02;        // wMaxPacketSize MSB
        config_desc[2][83] = 8'd0;         // bInterval

        // Zero-fill remaining bytes (84-127)
        config_desc[2][84] = 8'd0; config_desc[2][85] = 8'd0; config_desc[2][86] = 8'd0;
        config_desc[2][87] = 8'd0; config_desc[2][88] = 8'd0; config_desc[2][89] = 8'd0;
        config_desc[2][90] = 8'd0;

        //=====================================================================
        // FluxRipper Native + MSC + CDC (Full Composite)
        // Interface 0: MSC, Interface 1: Vendor, Interface 2: CDC Comm, Interface 3: CDC Data
        //=====================================================================

        // Configuration descriptor
        config_desc[3][0]  = 8'd9;         // bLength
        config_desc[3][1]  = 8'h02;        // bDescriptorType
        config_desc[3][2]  = 8'd114;       // wTotalLength LSB (114 bytes total)
        config_desc[3][3]  = 8'd0;         // wTotalLength MSB
        config_desc[3][4]  = 8'd4;         // bNumInterfaces (MSC, Vendor, CDC Comm, CDC Data)
        config_desc[3][5]  = 8'd1;         // bConfigurationValue
        config_desc[3][6]  = 8'd0;         // iConfiguration
        config_desc[3][7]  = 8'h80;        // bmAttributes (bus powered)
        config_desc[3][8]  = 8'd250;       // bMaxPower (500mA)

        // Interface 0: Mass Storage Class
        config_desc[3][9]  = 8'd9;         // bLength
        config_desc[3][10] = 8'h04;        // bDescriptorType
        config_desc[3][11] = 8'd0;         // bInterfaceNumber
        config_desc[3][12] = 8'd0;         // bAlternateSetting
        config_desc[3][13] = 8'd2;         // bNumEndpoints
        config_desc[3][14] = 8'h08;        // bInterfaceClass (Mass Storage)
        config_desc[3][15] = 8'h06;        // bInterfaceSubClass (SCSI transparent)
        config_desc[3][16] = 8'h50;        // bInterfaceProtocol (Bulk-Only Transport)
        config_desc[3][17] = 8'd0;         // iInterface

        // EP1 OUT (Bulk) - MSC
        config_desc[3][18] = 8'd7;         // bLength
        config_desc[3][19] = 8'h05;        // bDescriptorType
        config_desc[3][20] = 8'h01;        // bEndpointAddress (EP1 OUT)
        config_desc[3][21] = 8'h02;        // bmAttributes (Bulk)
        config_desc[3][22] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[3][23] = 8'h02;        // wMaxPacketSize MSB
        config_desc[3][24] = 8'd0;         // bInterval

        // EP1 IN (Bulk) - MSC
        config_desc[3][25] = 8'd7;         // bLength
        config_desc[3][26] = 8'h05;        // bDescriptorType
        config_desc[3][27] = 8'h81;        // bEndpointAddress (EP1 IN)
        config_desc[3][28] = 8'h02;        // bmAttributes (Bulk)
        config_desc[3][29] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[3][30] = 8'h02;        // wMaxPacketSize MSB
        config_desc[3][31] = 8'd0;         // bInterval

        // Interface 1: Vendor (FluxRipper Native Protocol)
        config_desc[3][32] = 8'd9;         // bLength
        config_desc[3][33] = 8'h04;        // bDescriptorType
        config_desc[3][34] = 8'd1;         // bInterfaceNumber
        config_desc[3][35] = 8'd0;         // bAlternateSetting
        config_desc[3][36] = 8'd2;         // bNumEndpoints
        config_desc[3][37] = 8'hFF;        // bInterfaceClass (Vendor)
        config_desc[3][38] = 8'h00;        // bInterfaceSubClass
        config_desc[3][39] = 8'h00;        // bInterfaceProtocol
        config_desc[3][40] = 8'd0;         // iInterface

        // EP2 OUT (Bulk) - FluxRipper Commands
        config_desc[3][41] = 8'd7;         // bLength
        config_desc[3][42] = 8'h05;        // bDescriptorType
        config_desc[3][43] = 8'h02;        // bEndpointAddress (EP2 OUT)
        config_desc[3][44] = 8'h02;        // bmAttributes (Bulk)
        config_desc[3][45] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[3][46] = 8'h02;        // wMaxPacketSize MSB
        config_desc[3][47] = 8'd0;         // bInterval

        // EP2 IN (Bulk) - FluxRipper Responses + Flux Data
        config_desc[3][48] = 8'd7;         // bLength
        config_desc[3][49] = 8'h05;        // bDescriptorType
        config_desc[3][50] = 8'h82;        // bEndpointAddress (EP2 IN)
        config_desc[3][51] = 8'h02;        // bmAttributes (Bulk)
        config_desc[3][52] = 8'h00;        // wMaxPacketSize LSB (512)
        config_desc[3][53] = 8'h02;        // wMaxPacketSize MSB
        config_desc[3][54] = 8'd0;         // bInterval

        // Interface Association Descriptor (IAD) for CDC
        config_desc[3][55] = 8'd8;         // bLength
        config_desc[3][56] = 8'h0B;        // bDescriptorType (IAD)
        config_desc[3][57] = 8'd2;         // bFirstInterface (CDC starts at interface 2)
        config_desc[3][58] = 8'd2;         // bInterfaceCount (Comm + Data)
        config_desc[3][59] = 8'h02;        // bFunctionClass (CDC)
        config_desc[3][60] = 8'h02;        // bFunctionSubClass (ACM)
        config_desc[3][61] = 8'h00;        // bFunctionProtocol
        config_desc[3][62] = 8'd0;         // iFunction

        // Interface 2: CDC Communication Interface
        config_desc[3][63] = 8'd9;         // bLength
        config_desc[3][64] = 8'h04;        // bDescriptorType
        config_desc[3][65] = 8'd2;         // bInterfaceNumber
        config_desc[3][66] = 8'd0;         // bAlternateSetting
        config_desc[3][67] = 8'd0;         // bNumEndpoints (no interrupt endpoint)
        config_desc[3][68] = 8'h02;        // bInterfaceClass (CDC)
        config_desc[3][69] = 8'h02;        // bInterfaceSubClass (ACM)
        config_desc[3][70] = 8'h00;        // bInterfaceProtocol
        config_desc[3][71] = 8'd0;         // iInterface

        // CDC Header Functional Descriptor
        config_desc[3][72] = 8'd5;         // bLength
        config_desc[3][73] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[3][74] = 8'h00;        // bDescriptorSubtype (Header)
        config_desc[3][75] = 8'h10;        // bcdCDC LSB (1.10)
        config_desc[3][76] = 8'h01;        // bcdCDC MSB

        // CDC Call Management Functional Descriptor
        config_desc[3][77] = 8'd5;         // bLength
        config_desc[3][78] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[3][79] = 8'h01;        // bDescriptorSubtype (Call Management)
        config_desc[3][80] = 8'h00;        // bmCapabilities (no call management)
        config_desc[3][81] = 8'd3;         // bDataInterface (interface 3)

        // CDC ACM Functional Descriptor
        config_desc[3][82] = 8'd4;         // bLength
        config_desc[3][83] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[3][84] = 8'h02;        // bDescriptorSubtype (ACM)
        config_desc[3][85] = 8'h02;        // bmCapabilities (supports line coding + serial state)

        // CDC Union Functional Descriptor
        config_desc[3][86] = 8'd5;         // bLength
        config_desc[3][87] = 8'h24;        // bDescriptorType (CS_INTERFACE)
        config_desc[3][88] = 8'h06;        // bDescriptorSubtype (Union)
        config_desc[3][89] = 8'd2;         // bMasterInterface (comm interface 2)
        config_desc[3][90] = 8'd3;         // bSlaveInterface0 (data interface 3)

        // Interface 3: CDC Data Interface
        config_desc[3][91] = 8'd9;         // bLength
        config_desc[3][92] = 8'h04;        // bDescriptorType
        config_desc[3][93] = 8'd3;         // bInterfaceNumber
        config_desc[3][94] = 8'd0;         // bAlternateSetting
        config_desc[3][95] = 8'd2;         // bNumEndpoints
        config_desc[3][96] = 8'h0A;        // bInterfaceClass (CDC Data)
        config_desc[3][97] = 8'h00;        // bInterfaceSubClass
        config_desc[3][98] = 8'h00;        // bInterfaceProtocol
        config_desc[3][99] = 8'd0;         // iInterface

        // EP3 OUT (Bulk) - CDC Data
        config_desc[3][100] = 8'd7;        // bLength
        config_desc[3][101] = 8'h05;       // bDescriptorType
        config_desc[3][102] = 8'h03;       // bEndpointAddress (EP3 OUT)
        config_desc[3][103] = 8'h02;       // bmAttributes (Bulk)
        config_desc[3][104] = 8'h00;       // wMaxPacketSize LSB (512)
        config_desc[3][105] = 8'h02;       // wMaxPacketSize MSB
        config_desc[3][106] = 8'd0;        // bInterval

        // EP3 IN (Bulk) - CDC Data
        config_desc[3][107] = 8'd7;        // bLength
        config_desc[3][108] = 8'h05;       // bDescriptorType
        config_desc[3][109] = 8'h83;       // bEndpointAddress (EP3 IN)
        config_desc[3][110] = 8'h02;       // bmAttributes (Bulk)
        config_desc[3][111] = 8'h00;       // wMaxPacketSize LSB (512)
        config_desc[3][112] = 8'h02;       // wMaxPacketSize MSB
        config_desc[3][113] = 8'd0;        // bInterval

        // Zero-fill remaining bytes (114-127)
        config_desc[3][114] = 8'd0; config_desc[3][115] = 8'd0;
        config_desc[3][116] = 8'd0; config_desc[3][117] = 8'd0;
        config_desc[3][118] = 8'd0; config_desc[3][119] = 8'd0;
        config_desc[3][120] = 8'd0; config_desc[3][121] = 8'd0;
        config_desc[3][122] = 8'd0; config_desc[3][123] = 8'd0;
        config_desc[3][124] = 8'd0; config_desc[3][125] = 8'd0;
        config_desc[3][126] = 8'd0; config_desc[3][127] = 8'd0;
    end

    //=========================================================================
    // String Descriptors
    //=========================================================================

    // String 0: Language ID
    // String 1: Manufacturer
    // String 2: Product (per personality)
    // String 3: Serial Number

    reg [7:0] string0 [0:3];   // Language descriptor
    reg [7:0] string1 [0:31];  // Manufacturer
    reg [7:0] string2 [0:3][0:63];  // Product (per personality)
    reg [7:0] string3 [0:31];  // Serial

    initial begin
        // String 0: Language ID (English US = 0x0409)
        string0[0] = 8'd4;         // bLength
        string0[1] = 8'h03;        // bDescriptorType
        string0[2] = 8'h09;        // English
        string0[3] = 8'h04;        // US

        // String 1: Manufacturer "FluxRipper"
        string1[0]  = 8'd22;       // bLength (2 + 10*2)
        string1[1]  = 8'h03;       // bDescriptorType
        string1[2]  = "F"; string1[3]  = 8'h00;
        string1[4]  = "l"; string1[5]  = 8'h00;
        string1[6]  = "u"; string1[7]  = 8'h00;
        string1[8]  = "x"; string1[9]  = 8'h00;
        string1[10] = "R"; string1[11] = 8'h00;
        string1[12] = "i"; string1[13] = 8'h00;
        string1[14] = "p"; string1[15] = 8'h00;
        string1[16] = "p"; string1[17] = 8'h00;
        string1[18] = "e"; string1[19] = 8'h00;
        string1[20] = "r"; string1[21] = 8'h00;

        // String 2[0]: Product "Greaseweazle F7"
        string2[0][0]  = 8'd32;
        string2[0][1]  = 8'h03;
        string2[0][2]  = "G"; string2[0][3]  = 8'h00;
        string2[0][4]  = "r"; string2[0][5]  = 8'h00;
        string2[0][6]  = "e"; string2[0][7]  = 8'h00;
        string2[0][8]  = "a"; string2[0][9]  = 8'h00;
        string2[0][10] = "s"; string2[0][11] = 8'h00;
        string2[0][12] = "e"; string2[0][13] = 8'h00;
        string2[0][14] = "w"; string2[0][15] = 8'h00;
        string2[0][16] = "e"; string2[0][17] = 8'h00;
        string2[0][18] = "a"; string2[0][19] = 8'h00;
        string2[0][20] = "z"; string2[0][21] = 8'h00;
        string2[0][22] = "l"; string2[0][23] = 8'h00;
        string2[0][24] = "e"; string2[0][25] = 8'h00;
        string2[0][26] = " "; string2[0][27] = 8'h00;
        string2[0][28] = "F"; string2[0][29] = 8'h00;
        string2[0][30] = "7"; string2[0][31] = 8'h00;

        // String 2[1]: Product "HxC Floppy"
        string2[1][0]  = 8'd22;
        string2[1][1]  = 8'h03;
        string2[1][2]  = "H"; string2[1][3]  = 8'h00;
        string2[1][4]  = "x"; string2[1][5]  = 8'h00;
        string2[1][6]  = "C"; string2[1][7]  = 8'h00;
        string2[1][8]  = " "; string2[1][9]  = 8'h00;
        string2[1][10] = "F"; string2[1][11] = 8'h00;
        string2[1][12] = "l"; string2[1][13] = 8'h00;
        string2[1][14] = "o"; string2[1][15] = 8'h00;
        string2[1][16] = "p"; string2[1][17] = 8'h00;
        string2[1][18] = "p"; string2[1][19] = 8'h00;
        string2[1][20] = "y"; string2[1][21] = 8'h00;

        // String 2[2]: Product "KryoFlux"
        string2[2][0]  = 8'd18;
        string2[2][1]  = 8'h03;
        string2[2][2]  = "K"; string2[2][3]  = 8'h00;
        string2[2][4]  = "r"; string2[2][5]  = 8'h00;
        string2[2][6]  = "y"; string2[2][7]  = 8'h00;
        string2[2][8]  = "o"; string2[2][9]  = 8'h00;
        string2[2][10] = "F"; string2[2][11] = 8'h00;
        string2[2][12] = "l"; string2[2][13] = 8'h00;
        string2[2][14] = "u"; string2[2][15] = 8'h00;
        string2[2][16] = "x"; string2[2][17] = 8'h00;

        // String 2[3]: Product "FluxRipper" (Native + MSC + CDC composite)
        string2[3][0]  = 8'd22;
        string2[3][1]  = 8'h03;
        string2[3][2]  = "F"; string2[3][3]  = 8'h00;
        string2[3][4]  = "l"; string2[3][5]  = 8'h00;
        string2[3][6]  = "u"; string2[3][7]  = 8'h00;
        string2[3][8]  = "x"; string2[3][9]  = 8'h00;
        string2[3][10] = "R"; string2[3][11] = 8'h00;
        string2[3][12] = "i"; string2[3][13] = 8'h00;
        string2[3][14] = "p"; string2[3][15] = 8'h00;
        string2[3][16] = "p"; string2[3][17] = 8'h00;
        string2[3][18] = "e"; string2[3][19] = 8'h00;
        string2[3][20] = "r"; string2[3][21] = 8'h00;

        // String 3: Serial Number "00000001"
        string3[0]  = 8'd18;
        string3[1]  = 8'h03;
        string3[2]  = "0"; string3[3]  = 8'h00;
        string3[4]  = "0"; string3[5]  = 8'h00;
        string3[6]  = "0"; string3[7]  = 8'h00;
        string3[8]  = "0"; string3[9]  = 8'h00;
        string3[10] = "0"; string3[11] = 8'h00;
        string3[12] = "0"; string3[13] = 8'h00;
        string3[14] = "0"; string3[15] = 8'h00;
        string3[16] = "1"; string3[17] = 8'h00;
    end

    //=========================================================================
    // Descriptor Read Logic
    //=========================================================================

    reg [2:0]  pers_idx;
    reg [15:0] byte_offset;       // Current byte offset
    reg [15:0] total_len;         // Total descriptor length
    reg        active;            // Descriptor transfer active

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            desc_data   <= 8'd0;
            desc_valid  <= 1'b0;
            desc_last   <= 1'b0;
            vid         <= 16'd0;
            pid         <= 16'd0;
            device_class    <= 8'd0;
            device_subclass <= 8'd0;
            device_protocol <= 8'd0;
            pers_idx    <= 3'd0;
            byte_offset <= 16'd0;
            total_len   <= 16'd0;
            active      <= 1'b0;
        end else begin
            desc_valid <= 1'b0;
            desc_last  <= 1'b0;

            // Clamp personality index
            pers_idx <= (personality < NUM_PERSONALITIES) ? personality : 3'd0;

            // Update active VID/PID
            vid <= {device_desc[pers_idx][9], device_desc[pers_idx][8]};
            pid <= {device_desc[pers_idx][11], device_desc[pers_idx][10]};
            device_class    <= device_desc[pers_idx][4];
            device_subclass <= device_desc[pers_idx][5];
            device_protocol <= device_desc[pers_idx][6];

            if (desc_request) begin
                // Start new descriptor transfer
                byte_offset <= 16'd0;
                active <= 1'b1;

                case (desc_type)
                    DESC_DEVICE: begin
                        total_len <= 16'd18;
                    end
                    DESC_CONFIGURATION: begin
                        total_len <= {config_desc[pers_idx][3], config_desc[pers_idx][2]};
                    end
                    DESC_STRING: begin
                        case (desc_index)
                            8'd0: total_len <= 16'd4;
                            8'd1: total_len <= {8'd0, string1[0]};
                            8'd2: total_len <= {8'd0, string2[pers_idx][0]};
                            8'd3: total_len <= {8'd0, string3[0]};
                            default: total_len <= 16'd0;
                        endcase
                    end
                    default: begin
                        total_len <= 16'd0;
                        active <= 1'b0;
                    end
                endcase
            end
            else if (active) begin
                desc_valid <= 1'b1;

                case (desc_type)
                    DESC_DEVICE: begin
                        if (byte_offset < 18)
                            desc_data <= device_desc[pers_idx][byte_offset[4:0]];
                        else
                            desc_data <= 8'd0;
                    end
                    DESC_CONFIGURATION: begin
                        if (byte_offset < 128)
                            desc_data <= config_desc[pers_idx][byte_offset[6:0]];
                        else
                            desc_data <= 8'd0;
                    end
                    DESC_STRING: begin
                        case (desc_index)
                            8'd0: desc_data <= (byte_offset < 4) ? string0[byte_offset[1:0]] : 8'd0;
                            8'd1: desc_data <= (byte_offset < 32) ? string1[byte_offset[4:0]] : 8'd0;
                            8'd2: desc_data <= (byte_offset < 64) ? string2[pers_idx][byte_offset[5:0]] : 8'd0;
                            8'd3: desc_data <= (byte_offset < 32) ? string3[byte_offset[4:0]] : 8'd0;
                            default: desc_data <= 8'd0;
                        endcase
                    end
                    default: desc_data <= 8'd0;
                endcase

                byte_offset <= byte_offset + 1'b1;

                // Check if this is the last byte
                if (byte_offset + 1'b1 >= total_len || byte_offset + 1'b1 >= desc_length) begin
                    desc_last <= 1'b1;
                    active <= 1'b0;
                end
            end
        end
    end

endmodule
