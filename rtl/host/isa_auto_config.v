//-----------------------------------------------------------------------------
// isa_auto_config.v
// ISA Hardware Discovery & Auto-Configuration Controller
//
// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 FluxRipper Project
//
// Description:
//   Top-level controller for ISA hardware discovery implementing "Phase 0"
//   auto-configuration. This module coordinates:
//
//   1. Physical slot width detection (C18 pin sensing)
//   2. PnP initiation key sniffing
//   3. Controller personality selection (WD1002/1003/1006/1007)
//   4. Drive interface detection (ST-506 vs ESDI)
//   5. Encoding mode detection (MFM vs RLL)
//   6. Option ROM mapping (8-bit vs 16-bit)
//   7. Force mode overrides from flash configuration
//   8. User-configurable FDC/WD enable/disable via config registers
//
//   WD Controller Personalities:
//   - WD1002-WX1: 8-bit XT, MFM, ST-506, 5 Mbps
//   - WD1003-WAH: 16-bit AT, MFM, ST-506, 5 Mbps
//   - WD1006-WAH: 16-bit AT, RLL 2,7, ST-506, 7.5 Mbps
//   - WD1007-WAH: 16-bit AT, MFM/RLL, ESDI, 10-15 Mbps
//
//   Design Philosophy:
//   - Card starts ACTIVE in legacy mode (safe default for non-PnP systems)
//   - Slot width detected passively via C18 ground sense
//   - PnP detected by monitoring for 32-byte initiation key
//   - Drive interface probed after slot detection
//   - Configuration is automatic but can be overridden via USB tool
//   - User can enable/disable FDC/WD via Option ROM BIOS config menu
//
// Created: 2025-12-07
// Updated: 2025-12-07 - Added WD1006/WD1007 personality support
// Updated: 2025-12-08 - Added user config register integration
//-----------------------------------------------------------------------------

module isa_auto_config (
    input  wire        clk,              // System clock (200 MHz typical)
    input  wire        rst_n,            // Active-low reset

    //=========================================================================
    // Physical Sense Input
    //=========================================================================
    input  wire        slot_sense_n,     // C18 pin: LOW=16-bit, HIGH=8-bit

    //=========================================================================
    // ISA Bus Monitor (for PnP sniffer)
    //=========================================================================
    input  wire [9:0]  isa_addr,         // I/O address SA[9:0]
    input  wire [7:0]  isa_data_in,      // Data bus SD[7:0]
    input  wire        isa_iow_n,        // I/O Write strobe
    input  wire        isa_aen,          // Address Enable (high during DMA)

    //=========================================================================
    // Flash Configuration (from SPI flash / USB tool)
    //=========================================================================
    input  wire [1:0]  cfg_force_mode,   // 00=AUTO, 01=FORCE_8BIT, 10=FORCE_16BIT
    input  wire        cfg_force_legacy, // Force legacy mode (no PnP)
    input  wire [9:0]  cfg_fdc_base,     // Default FDC I/O base (0x3F0)
    input  wire [9:0]  cfg_wd_base,      // Default WD I/O base (0x1F0)
    input  wire [3:0]  cfg_fdc_irq,      // Default FDC IRQ (6)
    input  wire [3:0]  cfg_wd_irq,       // Default WD IRQ (14)
    input  wire [2:0]  cfg_fdc_dma,      // Default FDC DMA (2)
    input  wire [2:0]  cfg_wd_dma,       // Default WD DMA (3 for XT)
    input  wire [1:0]  cfg_wd_personality, // Force WD personality (00=auto)

    //=========================================================================
    // Drive Interface Detection Inputs (from HDD subsystem)
    //=========================================================================
    input  wire        hdd_probe_done,    // Drive probe complete
    input  wire        hdd_esdi_detected, // ESDI interface detected
    input  wire        hdd_rll_detected,  // RLL encoding detected (flux analysis)
    input  wire [15:0] hdd_drive_id,      // Drive identification word

    //=========================================================================
    // Detection Status
    //=========================================================================
    output wire        detection_complete,  // Hardware detection finished
    output wire        slot_is_8bit,        // Detected 8-bit XT slot
    output wire        slot_is_16bit,       // Detected 16-bit AT slot
    output wire        pnp_detected,        // PnP initiation key received
    output wire [4:0]  pnp_key_progress,    // Key match progress (debug)
    output wire        esdi_detected,       // ESDI interface detected
    output wire        rll_detected,        // RLL encoding detected

    //=========================================================================
    // Mode Outputs
    //=========================================================================
    output wire        mode_xt,             // XT mode active (WD1002 personality)
    output wire        mode_at,             // AT mode active (WD1003/1006/1007)
    output wire        mode_legacy,         // Legacy I/O mode (non-PnP)
    output wire        mode_pnp,            // PnP configuration mode

    //=========================================================================
    // Hardware Control Outputs
    //=========================================================================
    output wire        enable_d8_d15,       // Enable high byte transceivers
    output wire        enable_16bit_dma,    // Enable 16-bit DMA transfers
    output wire        enable_mem16,        // Assert MEM16# for ROM access

    //=========================================================================
    // Personality Selection
    //=========================================================================
    output wire [1:0]  wd_personality,      // 00=WD1002, 01=WD1003, 10=WD1006, 11=WD1007
    output wire        option_rom_8bit,     // Use 8-bit Option ROM
    output wire        option_rom_16bit,    // Use 16-bit Option ROM

    //=========================================================================
    // Resource Configuration (active values)
    //=========================================================================
    output wire [9:0]  active_fdc_base,     // Active FDC I/O base
    output wire [9:0]  active_wd_base,      // Active WD primary I/O base
    output wire [9:0]  active_wd_alt,       // Active WD alternate I/O
    output wire [3:0]  active_fdc_irq,      // Active FDC IRQ
    output wire [3:0]  active_wd_irq,       // Active WD IRQ
    output wire [2:0]  active_fdc_dma,      // Active FDC DMA channel
    output wire [2:0]  active_wd_dma,       // Active WD DMA channel (XT mode)

    //=========================================================================
    // PnP Controller Interface
    //=========================================================================
    output wire        pnp_sniffer_active,  // Sniffer is monitoring
    input  wire        pnp_config_active,   // PnP controller in config mode
    input  wire        pnp_return_legacy,   // PnP controller requests legacy return
    input  wire [9:0]  pnp_fdc_base,        // PnP-assigned FDC base
    input  wire [9:0]  pnp_wd_base,         // PnP-assigned WD base
    input  wire [3:0]  pnp_fdc_irq,         // PnP-assigned FDC IRQ
    input  wire [3:0]  pnp_wd_irq,          // PnP-assigned WD IRQ
    input  wire [2:0]  pnp_fdc_dma,         // PnP-assigned FDC DMA
    input  wire [2:0]  pnp_wd_dma,          // PnP-assigned WD DMA

    //=========================================================================
    // User Configuration Register Interface (from isa_config_regs)
    //=========================================================================
    input  wire        user_fdc_enable,     // User FDC enable setting
    input  wire        user_wd_enable,      // User WD enable setting
    input  wire        user_fdc_dma_enable, // User FDC DMA enable
    input  wire        user_wd_dma_enable,  // User WD DMA enable (XT)
    input  wire [3:0]  user_fdc_irq,        // User FDC IRQ override
    input  wire [3:0]  user_wd_irq,         // User WD IRQ override
    input  wire [2:0]  user_fdc_dma,        // User FDC DMA channel override
    input  wire [2:0]  user_wd_dma,         // User WD DMA channel override

    //=========================================================================
    // Controller Enable Outputs (final gated enable signals)
    //=========================================================================
    output wire        fdc_enabled,         // FDC controller enabled (gated)
    output wire        wd_enabled,          // WD HDD controller enabled (gated)
    output wire        fdc_dma_enabled,     // FDC DMA enabled (gated)
    output wire        wd_dma_enabled       // WD DMA enabled (gated, XT mode)
);

    //=========================================================================
    // Internal Wires
    //=========================================================================
    wire        slot_detect_valid;
    wire        slot_8bit_detected;
    wire        slot_16bit_detected;
    wire        slot_enable_high;
    wire        slot_use_xt;

    wire        pnp_key_detected;
    wire        pnp_mode_active;
    wire        sniffer_legacy_mode;
    wire        sniffer_config_mode;

    //=========================================================================
    // Slot Width Detection
    //=========================================================================
    isa_slot_detect #(
        .DEBOUNCE_CYCLES (10000),        // ~50us at 200MHz
        .SAMPLE_COUNT    (8)
    ) u_slot_detect (
        .clk             (clk),
        .rst_n           (rst_n),
        .slot_sense_n    (slot_sense_n),
        .force_mode      (cfg_force_mode),
        .detection_valid (slot_detect_valid),
        .is_8bit_slot    (slot_8bit_detected),
        .is_16bit_slot   (slot_16bit_detected),
        .enable_high_byte(slot_enable_high),
        .use_xt_mode     (slot_use_xt)
    );

    //=========================================================================
    // PnP Initiation Key Sniffer
    //=========================================================================
    // Only enabled in 16-bit mode (XT systems don't have PnP)
    wire sniffer_enable = slot_16bit_detected & slot_detect_valid & ~cfg_force_legacy;

    isa_pnp_sniffer u_pnp_sniffer (
        .clk             (clk),
        .rst_n           (rst_n),
        .isa_addr        (isa_addr),
        .isa_data        (isa_data_in),
        .isa_iow_n       (isa_iow_n),
        .isa_aen         (isa_aen),
        .sniffer_enable  (sniffer_enable),
        .force_legacy    (cfg_force_legacy | pnp_return_legacy),
        .pnp_key_detected(pnp_key_detected),
        .pnp_mode_active (pnp_mode_active),
        .key_match_count (pnp_key_progress),
        .legacy_mode     (sniffer_legacy_mode),
        .config_mode     (sniffer_config_mode)
    );

    //=========================================================================
    // Status Outputs
    //=========================================================================
    assign detection_complete = slot_detect_valid;
    assign slot_is_8bit       = slot_8bit_detected;
    assign slot_is_16bit      = slot_16bit_detected;
    assign pnp_detected       = pnp_key_detected;
    assign pnp_sniffer_active = sniffer_enable;

    //=========================================================================
    // Mode Determination
    //=========================================================================
    // XT mode: 8-bit slot OR forced 8-bit
    assign mode_xt = slot_use_xt;

    // AT mode: 16-bit slot AND NOT forced 8-bit
    assign mode_at = ~slot_use_xt & slot_detect_valid;

    // Legacy mode: XT mode OR (AT mode AND no PnP detected) OR force_legacy
    assign mode_legacy = mode_xt | sniffer_legacy_mode | cfg_force_legacy;

    // PnP mode: AT mode AND PnP detected AND NOT force_legacy
    assign mode_pnp = mode_at & pnp_mode_active & ~cfg_force_legacy;

    //=========================================================================
    // Hardware Control
    //=========================================================================
    // Enable D8-D15 only in 16-bit mode
    assign enable_d8_d15    = slot_enable_high;

    // 16-bit DMA only in AT mode with 16-bit transfers
    assign enable_16bit_dma = mode_at;

    // MEM16# assertion for Option ROM (16-bit memory access)
    assign enable_mem16     = mode_at;

    //=========================================================================
    // Personality Selection
    //=========================================================================
    // WD Personality Encoding:
    //   2'b00 = WD1002-WX1: 8-bit XT, MFM, ST-506
    //   2'b01 = WD1003-WAH: 16-bit AT, MFM, ST-506
    //   2'b10 = WD1006-WAH: 16-bit AT, RLL 2,7, ST-506
    //   2'b11 = WD1007-WAH: 16-bit AT, ESDI (MFM or RLL)
    //
    // Selection Priority:
    //   1. Force mode from flash config (if non-zero)
    //   2. Slot width (8-bit forces WD1002)
    //   3. Interface detection (ESDI -> WD1007)
    //   4. Encoding detection (RLL -> WD1006)
    //   5. Default to WD1003 for 16-bit MFM ST-506

    localparam WD_1002 = 2'b00;  // XT MFM
    localparam WD_1003 = 2'b01;  // AT MFM
    localparam WD_1006 = 2'b10;  // AT RLL
    localparam WD_1007 = 2'b11;  // AT ESDI

    // Auto-detected personality based on drive probing
    wire [1:0] auto_personality;

    assign auto_personality = mode_xt           ? WD_1002 :  // 8-bit slot -> WD1002
                              hdd_esdi_detected ? WD_1007 :  // ESDI interface -> WD1007
                              hdd_rll_detected  ? WD_1006 :  // RLL encoding -> WD1006
                                                  WD_1003;   // Default AT MFM -> WD1003

    // Apply force override if configured
    assign wd_personality = (cfg_wd_personality != 2'b00) ? cfg_wd_personality :
                                                            auto_personality;

    // Option ROM selection
    assign option_rom_8bit  = mode_xt;
    assign option_rom_16bit = mode_at;

    // Export detection status
    assign esdi_detected = hdd_esdi_detected & hdd_probe_done;
    assign rll_detected  = hdd_rll_detected & hdd_probe_done;

    //=========================================================================
    // Resource Configuration Multiplexing
    //=========================================================================
    // Priority: PnP mode > User config > Flash defaults
    // User config registers (from isa_config_regs) can override flash defaults
    // PnP mode takes precedence when active

    // I/O bases: PnP mode uses PnP-assigned, legacy uses flash defaults
    // (User config doesn't override I/O bases - those are fixed)
    assign active_fdc_base = mode_pnp ? pnp_fdc_base : cfg_fdc_base;
    assign active_wd_base  = mode_pnp ? pnp_wd_base  : cfg_wd_base;

    // IRQ: PnP mode > User config > Flash defaults
    assign active_fdc_irq  = mode_pnp ? pnp_fdc_irq  :
                             (user_fdc_irq != 4'h0) ? user_fdc_irq : cfg_fdc_irq;
    assign active_wd_irq   = mode_pnp ? pnp_wd_irq   :
                             (user_wd_irq != 4'h0) ? user_wd_irq : cfg_wd_irq;

    // DMA channels: PnP mode > User config > Flash defaults
    assign active_fdc_dma  = mode_pnp ? pnp_fdc_dma  :
                             (user_fdc_dma != 3'h0) ? user_fdc_dma : cfg_fdc_dma;

    // WD DMA only used in XT mode (AT uses PIO)
    // In XT mode, always use configured DMA (no PnP on XT)
    // In AT/PnP mode, still provide the value for compatibility
    assign active_wd_dma   = mode_pnp ? pnp_wd_dma   :
                             (user_wd_dma != 3'h0) ? user_wd_dma : cfg_wd_dma;

    // WD alternate base (fixed offset from primary in AT mode)
    // Primary: 0x1F0-0x1F7, Alternate: 0x3F6-0x3F7
    assign active_wd_alt   = mode_xt ? 10'h000 :  // No alternate in XT mode
                                       10'h3F6;   // Standard AT alternate

    //=========================================================================
    // Controller Enable Gating
    //=========================================================================
    // Final enable signals combine auto-detection with user configuration
    // User can disable either controller via the config registers
    // Note: In PnP mode, the PnP controller manages activation separately

    // FDC enabled: Must be enabled in user config AND detection complete
    // (user_fdc_enable defaults to 1 from isa_config_regs)
    assign fdc_enabled = user_fdc_enable & slot_detect_valid;

    // WD HDD enabled: Must be enabled in user config AND detection complete
    // (user_wd_enable defaults to 1 from isa_config_regs)
    assign wd_enabled = user_wd_enable & slot_detect_valid;

    // FDC DMA enabled: User setting AND FDC is enabled
    assign fdc_dma_enabled = user_fdc_dma_enable & fdc_enabled;

    // WD DMA enabled: User setting AND WD is enabled AND in XT mode
    // (AT mode uses PIO, not DMA)
    assign wd_dma_enabled = user_wd_dma_enable & wd_enabled & mode_xt;

endmodule
