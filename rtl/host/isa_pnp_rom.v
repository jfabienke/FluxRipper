//==============================================================================
// ISA Plug-and-Play Resource ROM
//==============================================================================
// File: isa_pnp_rom.v
// Description: Resource descriptor ROM for PnP configuration.
//              Contains device identification and resource requirements
//              for FDC and WD HDD logical devices.
//
// Resource Descriptors (per PnP spec):
//   - Small tags: 1-7 byte items
//   - Large tags: Multi-byte items with length field
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 22:00
//==============================================================================

`timescale 1ns / 1ps

module isa_pnp_rom #(
    parameter [31:0] VENDOR_ID  = 32'h0C1F1234,  // EISA Vendor ID
    parameter [31:0] SERIAL_NUM = 32'h00000001   // Serial number
)(
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [7:0]  data
);

    //=========================================================================
    // Resource Descriptor Tags (Small Resource)
    //=========================================================================
    localparam TAG_PNP_VERSION       = 8'h0A;  // PnP version
    localparam TAG_LOG_DEV_ID        = 8'h15;  // Logical device ID (5 bytes)
    localparam TAG_COMPAT_DEV_ID     = 8'h1C;  // Compatible device ID
    localparam TAG_IRQ_FORMAT        = 8'h22;  // IRQ format (2 bytes)
    localparam TAG_IRQ_FORMAT_3      = 8'h23;  // IRQ format (3 bytes)
    localparam TAG_DMA_FORMAT        = 8'h2A;  // DMA format (2 bytes)
    localparam TAG_START_DEP_FUNC    = 8'h30;  // Start dependent function
    localparam TAG_END_DEP_FUNC      = 8'h38;  // End dependent function
    localparam TAG_IO_PORT           = 8'h47;  // I/O port (7 bytes)
    localparam TAG_FIXED_IO          = 8'h4B;  // Fixed I/O (3 bytes)
    localparam TAG_END               = 8'h79;  // End tag

    //=========================================================================
    // Resource Data ROM
    //=========================================================================
    // ROM contains descriptors for:
    //   - Card identification (Vendor ID, Serial, etc.)
    //   - Logical Device 0: FDC (0x3F0-0x3F7, IRQ6, DRQ2)
    //   - Logical Device 1: WD HDD (0x1F0-0x1F7, 0x3F6-0x3F7, IRQ14)

    always @(posedge clk) begin
        case (addr)
            //=================================================================
            // Card-Level Identification (9 bytes)
            //=================================================================
            // Vendor ID (4 bytes, compressed EISA format)
            8'h00: data <= VENDOR_ID[7:0];
            8'h01: data <= VENDOR_ID[15:8];
            8'h02: data <= VENDOR_ID[23:16];
            8'h03: data <= VENDOR_ID[31:24];

            // Serial Number (4 bytes)
            8'h04: data <= SERIAL_NUM[7:0];
            8'h05: data <= SERIAL_NUM[15:8];
            8'h06: data <= SERIAL_NUM[23:16];
            8'h07: data <= SERIAL_NUM[31:24];

            // Checksum (placeholder - computed by firmware)
            8'h08: data <= 8'h00;

            //=================================================================
            // PnP Version Tag
            //=================================================================
            8'h09: data <= TAG_PNP_VERSION;
            8'h0A: data <= 8'h10;  // PnP version 1.0
            8'h0B: data <= 8'h00;  // Vendor version

            //=================================================================
            // Logical Device 0: FDC (Floppy Disk Controller)
            //=================================================================
            // Logical Device ID: PNP0700 (Standard FDC)
            8'h0C: data <= TAG_LOG_DEV_ID;
            8'h0D: data <= 8'h41;  // 'P' compressed
            8'h0E: data <= 8'hD0;  // 'N' + 'P' compressed
            8'h0F: data <= 8'h07;  // Device 07
            8'h10: data <= 8'h00;  // 00

            // FDC I/O Port Descriptor: 0x3F0-0x3F7
            8'h11: data <= TAG_IO_PORT;
            8'h12: data <= 8'h01;  // Decode 10-bit
            8'h13: data <= 8'hF0;  // Min base low (0x3F0)
            8'h14: data <= 8'h03;  // Min base high
            8'h15: data <= 8'hF0;  // Max base low (0x3F0)
            8'h16: data <= 8'h03;  // Max base high
            8'h17: data <= 8'h01;  // Alignment
            8'h18: data <= 8'h08;  // Range length (8 ports)

            // FDC IRQ Descriptor: IRQ6
            8'h19: data <= TAG_IRQ_FORMAT;
            8'h1A: data <= 8'h40;  // IRQ6 (bit 6)
            8'h1B: data <= 8'h00;  // IRQ8-15 (none)

            // FDC DMA Descriptor: DRQ2
            8'h1C: data <= TAG_DMA_FORMAT;
            8'h1D: data <= 8'h04;  // DMA2 (bit 2)
            8'h1E: data <= 8'h00;  // 8-bit, compatibility mode

            //=================================================================
            // Logical Device 1: WD HDD (Hard Disk Controller)
            //=================================================================
            // Logical Device ID: PNP0600 (Standard IDE)
            8'h1F: data <= TAG_LOG_DEV_ID;
            8'h20: data <= 8'h41;  // 'P' compressed
            8'h21: data <= 8'hD0;  // 'N' + 'P' compressed
            8'h22: data <= 8'h06;  // Device 06
            8'h23: data <= 8'h00;  // 00

            // WD Primary I/O Port: 0x1F0-0x1F7
            8'h24: data <= TAG_IO_PORT;
            8'h25: data <= 8'h01;  // Decode 10-bit
            8'h26: data <= 8'hF0;  // Min base low (0x1F0)
            8'h27: data <= 8'h01;  // Min base high
            8'h28: data <= 8'hF0;  // Max base low (0x1F0)
            8'h29: data <= 8'h01;  // Max base high
            8'h2A: data <= 8'h01;  // Alignment
            8'h2B: data <= 8'h08;  // Range length (8 ports)

            // WD Alternate I/O Port: 0x3F6-0x3F7
            8'h2C: data <= TAG_FIXED_IO;
            8'h2D: data <= 8'hF6;  // Base low (0x3F6)
            8'h2E: data <= 8'h03;  // Base high
            8'h2F: data <= 8'h02;  // Range length (2 ports)

            // WD IRQ Descriptor: IRQ14 (AT) / IRQ5 (XT)
            8'h30: data <= TAG_IRQ_FORMAT;
            8'h31: data <= 8'h20;  // IRQ5 (bit 5) for XT compatibility
            8'h32: data <= 8'h40;  // IRQ14 (bit 6 of high byte) for AT

            // WD DMA Descriptor: DRQ3 (XT mode)
            8'h33: data <= TAG_DMA_FORMAT;
            8'h34: data <= 8'h08;  // DMA3 (bit 3)
            8'h35: data <= 8'h00;  // 8-bit, compatibility mode

            //=================================================================
            // End Tag
            //=================================================================
            8'h36: data <= TAG_END;
            8'h37: data <= 8'h00;  // Checksum (placeholder)

            //=================================================================
            // Padding / Default
            //=================================================================
            default: data <= 8'hFF;
        endcase
    end

endmodule

//==============================================================================
// Extended PnP ROM with ANSI Identifier Strings
//==============================================================================
// Optional module with human-readable device names.
//==============================================================================

module isa_pnp_rom_extended #(
    parameter [31:0] VENDOR_ID  = 32'h0C1F1234,
    parameter [31:0] SERIAL_NUM = 32'h00000001
)(
    input  wire        clk,
    input  wire [8:0]  addr,      // 9-bit address for larger ROM
    output reg  [7:0]  data
);

    // Large resource tag for ANSI identifier
    localparam TAG_ANSI_ID = 8'h82;

    always @(posedge clk) begin
        case (addr)
            //=================================================================
            // Card-Level Identification (same as basic ROM)
            //=================================================================
            9'h000: data <= VENDOR_ID[7:0];
            9'h001: data <= VENDOR_ID[15:8];
            9'h002: data <= VENDOR_ID[23:16];
            9'h003: data <= VENDOR_ID[31:24];
            9'h004: data <= SERIAL_NUM[7:0];
            9'h005: data <= SERIAL_NUM[15:8];
            9'h006: data <= SERIAL_NUM[23:16];
            9'h007: data <= SERIAL_NUM[31:24];
            9'h008: data <= 8'h00;  // Checksum

            // PnP Version
            9'h009: data <= 8'h0A;  // TAG_PNP_VERSION
            9'h00A: data <= 8'h10;  // Version 1.0
            9'h00B: data <= 8'h01;  // Vendor version

            //=================================================================
            // Card ANSI Identifier String
            //=================================================================
            9'h00C: data <= TAG_ANSI_ID;
            9'h00D: data <= 8'h18;  // Length low (24 bytes)
            9'h00E: data <= 8'h00;  // Length high

            // "FluxRipper Universal I/O"
            9'h00F: data <= "F";
            9'h010: data <= "l";
            9'h011: data <= "u";
            9'h012: data <= "x";
            9'h013: data <= "R";
            9'h014: data <= "i";
            9'h015: data <= "p";
            9'h016: data <= "p";
            9'h017: data <= "e";
            9'h018: data <= "r";
            9'h019: data <= " ";
            9'h01A: data <= "U";
            9'h01B: data <= "n";
            9'h01C: data <= "i";
            9'h01D: data <= "v";
            9'h01E: data <= "e";
            9'h01F: data <= "r";
            9'h020: data <= "s";
            9'h021: data <= "a";
            9'h022: data <= "l";
            9'h023: data <= " ";
            9'h024: data <= "I";
            9'h025: data <= "/";
            9'h026: data <= "O";

            //=================================================================
            // Logical Device 0: FDC
            //=================================================================
            9'h027: data <= 8'h15;  // TAG_LOG_DEV_ID
            9'h028: data <= 8'h41;  // PNP
            9'h029: data <= 8'hD0;
            9'h02A: data <= 8'h07;  // 0700
            9'h02B: data <= 8'h00;

            // FDC ANSI name
            9'h02C: data <= TAG_ANSI_ID;
            9'h02D: data <= 8'h11;  // Length (17 bytes)
            9'h02E: data <= 8'h00;
            // "Floppy Controller"
            9'h02F: data <= "F";
            9'h030: data <= "l";
            9'h031: data <= "o";
            9'h032: data <= "p";
            9'h033: data <= "p";
            9'h034: data <= "y";
            9'h035: data <= " ";
            9'h036: data <= "C";
            9'h037: data <= "o";
            9'h038: data <= "n";
            9'h039: data <= "t";
            9'h03A: data <= "r";
            9'h03B: data <= "o";
            9'h03C: data <= "l";
            9'h03D: data <= "l";
            9'h03E: data <= "e";
            9'h03F: data <= "r";

            // FDC I/O, IRQ, DMA (same as basic)
            9'h040: data <= 8'h47;  // TAG_IO_PORT
            9'h041: data <= 8'h01;
            9'h042: data <= 8'hF0;
            9'h043: data <= 8'h03;
            9'h044: data <= 8'hF0;
            9'h045: data <= 8'h03;
            9'h046: data <= 8'h01;
            9'h047: data <= 8'h08;

            9'h048: data <= 8'h22;  // TAG_IRQ_FORMAT
            9'h049: data <= 8'h40;
            9'h04A: data <= 8'h00;

            9'h04B: data <= 8'h2A;  // TAG_DMA_FORMAT
            9'h04C: data <= 8'h04;
            9'h04D: data <= 8'h00;

            //=================================================================
            // Logical Device 1: WD HDD
            //=================================================================
            9'h04E: data <= 8'h15;  // TAG_LOG_DEV_ID
            9'h04F: data <= 8'h41;  // PNP
            9'h050: data <= 8'hD0;
            9'h051: data <= 8'h06;  // 0600
            9'h052: data <= 8'h00;

            // WD ANSI name
            9'h053: data <= TAG_ANSI_ID;
            9'h054: data <= 8'h0E;  // Length (14 bytes)
            9'h055: data <= 8'h00;
            // "HDD Controller"
            9'h056: data <= "H";
            9'h057: data <= "D";
            9'h058: data <= "D";
            9'h059: data <= " ";
            9'h05A: data <= "C";
            9'h05B: data <= "o";
            9'h05C: data <= "n";
            9'h05D: data <= "t";
            9'h05E: data <= "r";
            9'h05F: data <= "o";
            9'h060: data <= "l";
            9'h061: data <= "l";
            9'h062: data <= "e";
            9'h063: data <= "r";

            // WD Primary I/O
            9'h064: data <= 8'h47;
            9'h065: data <= 8'h01;
            9'h066: data <= 8'hF0;
            9'h067: data <= 8'h01;
            9'h068: data <= 8'hF0;
            9'h069: data <= 8'h01;
            9'h06A: data <= 8'h01;
            9'h06B: data <= 8'h08;

            // WD Alternate I/O
            9'h06C: data <= 8'h4B;  // TAG_FIXED_IO
            9'h06D: data <= 8'hF6;
            9'h06E: data <= 8'h03;
            9'h06F: data <= 8'h02;

            // WD IRQ14 (AT) / IRQ5 (XT)
            9'h070: data <= 8'h22;
            9'h071: data <= 8'h20;  // IRQ5 (bit 5) for XT
            9'h072: data <= 8'h40;  // IRQ14 (bit 6 high byte) for AT

            // WD DMA3 (XT mode)
            9'h073: data <= 8'h2A;  // TAG_DMA_FORMAT
            9'h074: data <= 8'h08;  // DMA3 (bit 3)
            9'h075: data <= 8'h00;  // 8-bit, compatibility mode

            //=================================================================
            // End Tag
            //=================================================================
            9'h076: data <= 8'h79;  // TAG_END
            9'h077: data <= 8'h00;

            default: data <= 8'hFF;
        endcase
    end

endmodule
