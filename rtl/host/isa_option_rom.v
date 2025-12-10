//==============================================================================
// ISA Option ROM Controller
//==============================================================================
// File: isa_option_rom.v
// Description: Option ROM interface for ISA bus memory reads.
//              Provides BIOS-level boot support for FluxRipper.
//
// Features:
//   - Configurable base address (C8000h default)
//   - 8KB/16KB/32KB ROM size options
//   - Single-cycle access (no wait states needed)
//   - Address decode with AEN check (ignores DMA cycles)
//   - Direct BRAM interface for ROM storage
//
// Memory Map:
//   C8000h-CBFFFh (16KB default) - FluxRipper Option ROM
//
// ROM Header Requirements:
//   Offset 0x00: 0x55 (signature low)
//   Offset 0x01: 0xAA (signature high)
//   Offset 0x02: Size in 512-byte blocks
//   Offset 0x03: JMP instruction to init routine
//   Checksum: All bytes must sum to 0x00
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-07 14:35
//==============================================================================

`timescale 1ns / 1ps

module isa_option_rom #(
    parameter [23:0] ROM_BASE_ADDR = 24'hC8000,  // Default: C8000h
    parameter        ROM_SIZE_KB   = 16,         // 8, 16, or 32 KB
    parameter        USE_BRAM      = 1           // 1=BRAM, 0=external
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // ISA Memory Bus Interface
    //=========================================================================
    // Address bus (directly from ISA connector)
    input  wire [19:0] isa_sa,            // System Address SA[19:0] (directly from ISA SA0-SA19)
    input  wire [6:0]  isa_la,            // Latched Address LA[23:17] (directly from ISA LA17-LA23)

    // Control signals (directly from ISA connector)
    input  wire        isa_memr_n,        // Memory Read strobe (active low)
    input  wire        isa_aen,           // Address Enable (high during DMA)
    input  wire        isa_refresh_n,     // Refresh cycle (ignore when low)

    // Data bus (directly from ISA connector)
    output wire [7:0]  isa_data_out,      // Data to ISA bus
    output wire        isa_data_oe,       // Output enable for data bus tristate

    // Ready signal (directly from ISA connector)
    output wire        isa_mem_ready,     // I/O Channel Ready (active high)

    //=========================================================================
    // ROM Data Interface (directly from internal BRAM)
    //=========================================================================
    output wire [14:0] rom_addr,          // ROM address (directly from 32KB max = 15 bits)
    input  wire [7:0]  rom_data,          // ROM data (directly from BRAM)

    //=========================================================================
    // Configuration
    //=========================================================================
    input  wire        rom_enable,        // Enable ROM decode
    input  wire [2:0]  rom_base_sel       // Base address select (0=C8000, 1=CA000, etc.)
);

    //=========================================================================
    // Address Decode Parameters
    //=========================================================================
    // ROM size in bytes
    localparam ROM_SIZE = ROM_SIZE_KB * 1024;

    // Address bits needed for ROM
    localparam ROM_ADDR_BITS = (ROM_SIZE_KB == 8)  ? 13 :
                               (ROM_SIZE_KB == 16) ? 14 :
                               (ROM_SIZE_KB == 32) ? 15 : 14;

    //=========================================================================
    // Base Address Selection
    //=========================================================================
    // Selectable base addresses for conflict resolution
    reg [23:0] active_base;

    always @(*) begin
        case (rom_base_sel)
            3'b000: active_base = 24'hC8000;  // Default HDD ROM location
            3'b001: active_base = 24'hCA000;  // Alternative 1
            3'b010: active_base = 24'hCC000;  // Alternative 2
            3'b011: active_base = 24'hCE000;  // Alternative 3
            3'b100: active_base = 24'hD0000;  // UMB region
            3'b101: active_base = 24'hD8000;  // UMB region
            3'b110: active_base = 24'hE0000;  // System extension area
            3'b111: active_base = ROM_BASE_ADDR; // Parameter default
            default: active_base = 24'hC8000;
        endcase
    end

    //=========================================================================
    // Full Address Reconstruction
    //=========================================================================
    // Combine latched address (upper bits) with system address (lower bits)
    // LA[23:17] provides A23-A17, SA[19:0] provides A19-A0
    // Note: LA[23:20] and SA[19:17] overlap - use LA for upper, SA for lower
    wire [23:0] full_addr = {isa_la[6:0], isa_sa[16:0]};

    //=========================================================================
    // Address Range Detection
    //=========================================================================
    // Check if address falls within ROM range
    wire addr_in_range = (full_addr >= active_base) &&
                         (full_addr < (active_base + ROM_SIZE));

    //=========================================================================
    // Chip Select Logic
    //=========================================================================
    // ROM is selected when:
    // - Address is in range
    // - Memory read is active (MEMR# low)
    // - Not a DMA cycle (AEN low)
    // - Not a refresh cycle (REFRESH# high)
    // - ROM is enabled
    wire rom_selected = rom_enable &&
                        addr_in_range &&
                        !isa_memr_n &&
                        !isa_aen &&
                        isa_refresh_n;

    //=========================================================================
    // ROM Address Calculation
    //=========================================================================
    // Extract offset within ROM from full address
    wire [14:0] rom_offset = full_addr[14:0] - active_base[14:0];

    assign rom_addr = rom_offset[ROM_ADDR_BITS-1:0];

    //=========================================================================
    // Data Output
    //=========================================================================
    // ROM data is directly from BRAM (combinatorial path for speed)
    assign isa_data_out = rom_data;

    // Output enable when ROM is selected
    assign isa_data_oe = rom_selected;

    //=========================================================================
    // Ready Signal
    //=========================================================================
    // BRAM is fast enough for single-cycle access at ISA speeds
    // Always ready (no wait states needed)
    assign isa_mem_ready = 1'b1;

    //=========================================================================
    // Debug/Status (optional, directly for simulation)
    //=========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (rom_selected) begin
            $display("[ROM] Read: Addr=%h Data=%h", full_addr, rom_data);
        end
    end
    `endif

endmodule

//==============================================================================
// Option ROM Block RAM
//==============================================================================
// Dedicated BRAM for storing Option ROM contents.
// Initialize from .mem file or embed in bitstream.
//==============================================================================

module option_rom_bram #(
    parameter ROM_SIZE_KB = 16,
    parameter ROM_FILE    = "fluxripper_rom.mem"
)(
    input  wire        clk,
    input  wire [14:0] addr,
    output reg  [7:0]  data
);

    // ROM size
    localparam ROM_SIZE = ROM_SIZE_KB * 1024;

    // ROM storage
    (* ram_style = "block" *) reg [7:0] rom [0:ROM_SIZE-1];

    // Loop variable for initialization
    integer rom_init_i;

    // Initialize ROM from file
    initial begin
        // Default: fill with 0xFF (empty EPROM state)
        for (rom_init_i = 0; rom_init_i < ROM_SIZE; rom_init_i = rom_init_i + 1) begin
            rom[rom_init_i] = 8'hFF;
        end

        // Load ROM contents if file exists
        $readmemh(ROM_FILE, rom);

        // Verify signature (simulation only)
        `ifdef SIMULATION
        if (rom[0] == 8'h55 && rom[1] == 8'hAA) begin
            $display("[ROM] Valid Option ROM signature detected");
            $display("[ROM] ROM size: %d KB (%d blocks)",
                     rom[2] * 512 / 1024, rom[2]);
        end else begin
            $display("[ROM] WARNING: Invalid ROM signature: %02X %02X",
                     rom[0], rom[1]);
        end
        `endif
    end

    // Synchronous read
    always @(posedge clk) begin
        data <= rom[addr];
    end

endmodule

//==============================================================================
// Option ROM with Asynchronous Read
//==============================================================================
// Alternative implementation with async read for fastest access.
// Uses distributed RAM (LUTs) for small ROMs.
//==============================================================================

module option_rom_async #(
    parameter ROM_SIZE_KB = 8,
    parameter ROM_FILE    = "fluxripper_rom.mem"
)(
    input  wire [12:0] addr,          // 8KB = 13 bits
    output wire [7:0]  data
);

    localparam ROM_SIZE = ROM_SIZE_KB * 1024;

    (* ram_style = "distributed" *) reg [7:0] rom [0:ROM_SIZE-1];

    initial begin
        $readmemh(ROM_FILE, rom);
    end

    // Asynchronous (combinatorial) read
    assign data = rom[addr];

endmodule
