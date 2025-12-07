//==============================================================================
// ISA Address Decoder
//==============================================================================
// File: isa_addr_decode.v
// Description: Configurable I/O port address decoder for ISA bus devices.
//              Supports FDC (0x3Fx), primary WD (0x1Fx), and secondary WD (0x17x).
//
// Features:
//   - Configurable base addresses for each device
//   - Enable/disable control for each device
//   - Support for primary and secondary controllers
//   - Address range validation
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 21:50
//==============================================================================

`timescale 1ns / 1ps

module isa_addr_decode (
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // ISA Address Input
    //=========================================================================
    input  wire [9:0]  isa_addr,          // I/O address (bits 9:0)
    input  wire        isa_aen,           // Address Enable (high during DMA)

    //=========================================================================
    // Device Enable Inputs
    //=========================================================================
    input  wire        fdc_enable,        // Enable FDC decode
    input  wire        wd_pri_enable,     // Enable primary WD decode
    input  wire        wd_sec_enable,     // Enable secondary WD decode

    //=========================================================================
    // Configurable Base Addresses
    //=========================================================================
    input  wire [9:0]  fdc_base,          // FDC base (default 0x3F0)
    input  wire [9:0]  wd_pri_base,       // WD primary base (default 0x1F0)
    input  wire [9:0]  wd_pri_alt,        // WD primary alt (default 0x3F6)
    input  wire [9:0]  wd_sec_base,       // WD secondary base (default 0x170)
    input  wire [9:0]  wd_sec_alt,        // WD secondary alt (default 0x376)

    //=========================================================================
    // Decode Outputs
    //=========================================================================
    output wire        fdc_cs,            // FDC chip select
    output wire [2:0]  fdc_reg,           // FDC register address (0-7)

    output wire        wd_pri_cs,         // WD primary chip select
    output wire        wd_pri_alt_cs,     // WD primary alternate select
    output wire [2:0]  wd_pri_reg,        // WD primary register (0-7)

    output wire        wd_sec_cs,         // WD secondary chip select
    output wire        wd_sec_alt_cs,     // WD secondary alternate select
    output wire [2:0]  wd_sec_reg,        // WD secondary register (0-7)

    //=========================================================================
    // Combined Outputs
    //=========================================================================
    output wire        any_select,        // Any device selected
    output wire        fdc_select,        // FDC selected (cs OR dma)
    output wire        wd_select,         // Any WD selected
    output wire [1:0]  device_id          // 0=none, 1=FDC, 2=WD_PRI, 3=WD_SEC
);

    //=========================================================================
    // Address Range Comparators
    //=========================================================================

    // FDC: base + 0x00 to base + 0x07
    wire fdc_in_range = (isa_addr[9:3] == fdc_base[9:3]);

    // WD Primary: base + 0x00 to base + 0x07
    wire wd_pri_in_range = (isa_addr[9:3] == wd_pri_base[9:3]);

    // WD Primary Alternate: alt base (typically just 2 registers: 0x3F6-0x3F7)
    wire wd_pri_alt_in_range = (isa_addr[9:1] == wd_pri_alt[9:1]);

    // WD Secondary: base + 0x00 to base + 0x07
    wire wd_sec_in_range = (isa_addr[9:3] == wd_sec_base[9:3]);

    // WD Secondary Alternate: alt base
    wire wd_sec_alt_in_range = (isa_addr[9:1] == wd_sec_alt[9:1]);

    //=========================================================================
    // Device Select Logic
    //=========================================================================

    // FDC chip select
    assign fdc_cs = fdc_enable && fdc_in_range && !isa_aen;
    assign fdc_reg = isa_addr[2:0];

    // WD primary selects
    assign wd_pri_cs = wd_pri_enable && wd_pri_in_range && !isa_aen;
    assign wd_pri_alt_cs = wd_pri_enable && wd_pri_alt_in_range && !isa_aen;
    assign wd_pri_reg = wd_pri_alt_cs ? {2'b0, isa_addr[0]} : isa_addr[2:0];

    // WD secondary selects
    assign wd_sec_cs = wd_sec_enable && wd_sec_in_range && !isa_aen;
    assign wd_sec_alt_cs = wd_sec_enable && wd_sec_alt_in_range && !isa_aen;
    assign wd_sec_reg = wd_sec_alt_cs ? {2'b0, isa_addr[0]} : isa_addr[2:0];

    //=========================================================================
    // Combined Outputs
    //=========================================================================

    assign fdc_select = fdc_cs;
    assign wd_select = wd_pri_cs || wd_pri_alt_cs || wd_sec_cs || wd_sec_alt_cs;
    assign any_select = fdc_select || wd_select;

    // Device ID encoder
    // Priority: FDC > WD_PRI > WD_SEC
    assign device_id = fdc_select ? 2'b01 :
                       (wd_pri_cs || wd_pri_alt_cs) ? 2'b10 :
                       (wd_sec_cs || wd_sec_alt_cs) ? 2'b11 :
                       2'b00;

endmodule

//==============================================================================
// ISA Address Decoder with Default Configuration
//==============================================================================
// Wrapper with standard PC/AT I/O port assignments.
//==============================================================================

module isa_addr_decode_default (
    input  wire        clk,
    input  wire        reset_n,

    input  wire [9:0]  isa_addr,
    input  wire        isa_aen,

    input  wire        fdc_enable,
    input  wire        wd_pri_enable,
    input  wire        wd_sec_enable,

    output wire        fdc_cs,
    output wire [2:0]  fdc_reg,
    output wire        wd_pri_cs,
    output wire        wd_pri_alt_cs,
    output wire [2:0]  wd_pri_reg,
    output wire        wd_sec_cs,
    output wire        wd_sec_alt_cs,
    output wire [2:0]  wd_sec_reg,
    output wire        any_select,
    output wire        fdc_select,
    output wire        wd_select,
    output wire [1:0]  device_id
);

    // Standard PC/AT I/O addresses
    localparam FDC_BASE     = 10'h3F0;   // 0x3F0-0x3F7 FDC
    localparam WD_PRI_BASE  = 10'h1F0;   // 0x1F0-0x1F7 Primary IDE
    localparam WD_PRI_ALT   = 10'h3F6;   // 0x3F6-0x3F7 Primary IDE Alt
    localparam WD_SEC_BASE  = 10'h170;   // 0x170-0x177 Secondary IDE
    localparam WD_SEC_ALT   = 10'h376;   // 0x376-0x377 Secondary IDE Alt

    isa_addr_decode u_decode (
        .clk            (clk),
        .reset_n        (reset_n),
        .isa_addr       (isa_addr),
        .isa_aen        (isa_aen),
        .fdc_enable     (fdc_enable),
        .wd_pri_enable  (wd_pri_enable),
        .wd_sec_enable  (wd_sec_enable),
        .fdc_base       (FDC_BASE),
        .wd_pri_base    (WD_PRI_BASE),
        .wd_pri_alt     (WD_PRI_ALT),
        .wd_sec_base    (WD_SEC_BASE),
        .wd_sec_alt     (WD_SEC_ALT),
        .fdc_cs         (fdc_cs),
        .fdc_reg        (fdc_reg),
        .wd_pri_cs      (wd_pri_cs),
        .wd_pri_alt_cs  (wd_pri_alt_cs),
        .wd_pri_reg     (wd_pri_reg),
        .wd_sec_cs      (wd_sec_cs),
        .wd_sec_alt_cs  (wd_sec_alt_cs),
        .wd_sec_reg     (wd_sec_reg),
        .any_select     (any_select),
        .fdc_select     (fdc_select),
        .wd_select      (wd_select),
        .device_id      (device_id)
    );

endmodule
