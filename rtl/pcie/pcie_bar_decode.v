//==============================================================================
// PCIe BAR Address Decoder
//==============================================================================
// File: pcie_bar_decode.v
// Description: Base Address Register decoder for multi-function PCIe endpoint.
//              Routes memory-mapped accesses to FDC or WD HDD controllers.
//
// BAR Layout:
//   BAR0: FDC registers (4KB)  - 0x0000-0x0FFF
//   BAR1: WD HDD registers (4KB) - 0x0000-0x0FFF
//   BAR2: Shared DMA buffer (64KB) - 0x0000-0xFFFF
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 23:35
//==============================================================================

`timescale 1ns / 1ps

module pcie_bar_decode #(
    parameter BAR0_SIZE = 12,    // 4KB for FDC (2^12)
    parameter BAR1_SIZE = 12,    // 4KB for WD HDD (2^12)
    parameter BAR2_SIZE = 16     // 64KB for DMA (2^16)
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // PCIe TLP Address Input
    //=========================================================================
    input  wire [63:0] tlp_addr,         // Full 64-bit address from TLP
    input  wire [2:0]  tlp_bar_hit,      // BAR hit indicator from PCIe core
    input  wire        tlp_valid,        // TLP is valid
    input  wire        tlp_is_write,     // 1=write, 0=read
    input  wire [31:0] tlp_data,         // Write data
    input  wire [3:0]  tlp_be,           // Byte enables

    //=========================================================================
    // BAR Base Addresses (from config space)
    //=========================================================================
    input  wire [31:0] bar0_base,        // FDC BAR base
    input  wire [31:0] bar1_base,        // WD HDD BAR base
    input  wire [31:0] bar2_base,        // DMA buffer BAR base

    //=========================================================================
    // Decoded Outputs - FDC (BAR0)
    //=========================================================================
    output reg         fdc_sel,          // FDC selected
    output reg  [11:0] fdc_addr,         // FDC register address
    output reg  [31:0] fdc_wdata,        // FDC write data
    output reg  [3:0]  fdc_be,           // FDC byte enables
    output reg         fdc_write,        // FDC write strobe
    output reg         fdc_read,         // FDC read strobe

    //=========================================================================
    // Decoded Outputs - WD HDD (BAR1)
    //=========================================================================
    output reg         wd_sel,           // WD selected
    output reg  [11:0] wd_addr,          // WD register address
    output reg  [31:0] wd_wdata,         // WD write data
    output reg  [3:0]  wd_be,            // WD byte enables
    output reg         wd_write,         // WD write strobe
    output reg         wd_read,          // WD read strobe

    //=========================================================================
    // Decoded Outputs - DMA Buffer (BAR2)
    //=========================================================================
    output reg         dma_sel,          // DMA buffer selected
    output reg  [15:0] dma_addr,         // DMA buffer address
    output reg  [31:0] dma_wdata,        // DMA write data
    output reg  [3:0]  dma_be,           // DMA byte enables
    output reg         dma_write,        // DMA write strobe
    output reg         dma_read,         // DMA read strobe

    //=========================================================================
    // Status
    //=========================================================================
    output wire        any_hit,          // Any BAR hit
    output reg  [1:0]  active_bar        // Which BAR is active (0-2)
);

    //=========================================================================
    // BAR Hit Detection
    //=========================================================================
    // Use bar_hit from PCIe core if available, otherwise decode from address

    wire bar0_hit = tlp_bar_hit[0];
    wire bar1_hit = tlp_bar_hit[1];
    wire bar2_hit = tlp_bar_hit[2];

    assign any_hit = |tlp_bar_hit && tlp_valid;

    //=========================================================================
    // Address Offset Calculation
    //=========================================================================
    // Extract offset within each BAR

    wire [11:0] bar0_offset = tlp_addr[11:0];
    wire [11:0] bar1_offset = tlp_addr[11:0];
    wire [15:0] bar2_offset = tlp_addr[15:0];

    //=========================================================================
    // Decode Logic
    //=========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // FDC outputs
            fdc_sel   <= 1'b0;
            fdc_addr  <= 12'h0;
            fdc_wdata <= 32'h0;
            fdc_be    <= 4'h0;
            fdc_write <= 1'b0;
            fdc_read  <= 1'b0;

            // WD outputs
            wd_sel    <= 1'b0;
            wd_addr   <= 12'h0;
            wd_wdata  <= 32'h0;
            wd_be     <= 4'h0;
            wd_write  <= 1'b0;
            wd_read   <= 1'b0;

            // DMA outputs
            dma_sel   <= 1'b0;
            dma_addr  <= 16'h0;
            dma_wdata <= 32'h0;
            dma_be    <= 4'h0;
            dma_write <= 1'b0;
            dma_read  <= 1'b0;

            active_bar <= 2'b00;

        end else begin
            // Default: clear all strobes
            fdc_write <= 1'b0;
            fdc_read  <= 1'b0;
            wd_write  <= 1'b0;
            wd_read   <= 1'b0;
            dma_write <= 1'b0;
            dma_read  <= 1'b0;
            fdc_sel   <= 1'b0;
            wd_sel    <= 1'b0;
            dma_sel   <= 1'b0;

            if (tlp_valid) begin
                //-------------------------------------------------------------
                // BAR0: FDC Registers
                //-------------------------------------------------------------
                if (bar0_hit) begin
                    fdc_sel   <= 1'b1;
                    fdc_addr  <= bar0_offset;
                    fdc_wdata <= tlp_data;
                    fdc_be    <= tlp_be;
                    fdc_write <= tlp_is_write;
                    fdc_read  <= !tlp_is_write;
                    active_bar <= 2'b00;
                end

                //-------------------------------------------------------------
                // BAR1: WD HDD Registers
                //-------------------------------------------------------------
                else if (bar1_hit) begin
                    wd_sel    <= 1'b1;
                    wd_addr   <= bar1_offset;
                    wd_wdata  <= tlp_data;
                    wd_be     <= tlp_be;
                    wd_write  <= tlp_is_write;
                    wd_read   <= !tlp_is_write;
                    active_bar <= 2'b01;
                end

                //-------------------------------------------------------------
                // BAR2: DMA Buffer
                //-------------------------------------------------------------
                else if (bar2_hit) begin
                    dma_sel   <= 1'b1;
                    dma_addr  <= bar2_offset;
                    dma_wdata <= tlp_data;
                    dma_be    <= tlp_be;
                    dma_write <= tlp_is_write;
                    dma_read  <= !tlp_is_write;
                    active_bar <= 2'b10;
                end
            end
        end
    end

    //=========================================================================
    // FDC Register Sub-Decode
    //=========================================================================
    // BAR0 layout:
    //   0x000-0x03F: FDC task file registers
    //   0x040-0x07F: FDC extended registers
    //   0x080-0x0FF: FDC DMA control
    //   0x100-0x1FF: FDC status/interrupt
    //   0x200-0xFFF: Reserved

    wire fdc_taskfile_sel = fdc_sel && (fdc_addr[11:6] == 6'h00);
    wire fdc_extended_sel = fdc_sel && (fdc_addr[11:6] == 6'h01);
    wire fdc_dma_ctrl_sel = fdc_sel && (fdc_addr[11:7] == 5'h01);
    wire fdc_status_sel   = fdc_sel && (fdc_addr[11:8] == 4'h1);

    //=========================================================================
    // WD Register Sub-Decode
    //=========================================================================
    // BAR1 layout:
    //   0x000-0x03F: WD task file registers
    //   0x040-0x07F: WD extended registers
    //   0x080-0x0FF: WD DMA control
    //   0x100-0x1FF: WD status/interrupt
    //   0x200-0x3FF: WD track buffer access
    //   0x400-0xFFF: Reserved

    wire wd_taskfile_sel = wd_sel && (wd_addr[11:6] == 6'h00);
    wire wd_extended_sel = wd_sel && (wd_addr[11:6] == 6'h01);
    wire wd_dma_ctrl_sel = wd_sel && (wd_addr[11:7] == 5'h01);
    wire wd_status_sel   = wd_sel && (wd_addr[11:8] == 4'h1);
    wire wd_buffer_sel   = wd_sel && (wd_addr[11:9] == 3'h1);

    //=========================================================================
    // DMA Buffer Sub-Decode
    //=========================================================================
    // BAR2 layout:
    //   0x0000-0x21FF: FDC track buffer (8.5KB)
    //   0x2200-0x43FF: WD track buffer (8.5KB)
    //   0x4400-0xBFFF: Scatter-gather tables (31KB)
    //   0xC000-0xFFFF: DMA descriptor ring (16KB)

    wire dma_fdc_buf_sel = dma_sel && (dma_addr[15:13] == 3'h0);
    wire dma_wd_buf_sel  = dma_sel && (dma_addr[15:13] == 3'h1);
    wire dma_sg_sel      = dma_sel && (dma_addr[15:14] == 2'h1);
    wire dma_desc_sel    = dma_sel && (dma_addr[15:14] == 2'h3);

endmodule

//==============================================================================
// PCIe BAR Decoder with Address Matching (no bar_hit input)
//==============================================================================
// Alternative version that decodes BARs from address comparison.
//==============================================================================

module pcie_bar_decode_addr #(
    parameter BAR0_SIZE = 12,
    parameter BAR1_SIZE = 12,
    parameter BAR2_SIZE = 16
)(
    input  wire        clk,
    input  wire        reset_n,

    // TLP Address
    input  wire [63:0] tlp_addr,
    input  wire        tlp_valid,
    input  wire        tlp_is_write,
    input  wire [31:0] tlp_data,
    input  wire [3:0]  tlp_be,

    // BAR Base Addresses
    input  wire [31:0] bar0_base,
    input  wire [31:0] bar1_base,
    input  wire [31:0] bar2_base,

    // Output selects (directly computed)
    output wire        bar0_hit,
    output wire        bar1_hit,
    output wire        bar2_hit,
    output wire [11:0] bar0_offset,
    output wire [11:0] bar1_offset,
    output wire [15:0] bar2_offset
);

    // Mask for BAR size comparison
    localparam [31:0] BAR0_MASK = ~((1 << BAR0_SIZE) - 1);
    localparam [31:0] BAR1_MASK = ~((1 << BAR1_SIZE) - 1);
    localparam [31:0] BAR2_MASK = ~((1 << BAR2_SIZE) - 1);

    // Address comparison
    wire [31:0] addr_32 = tlp_addr[31:0];

    assign bar0_hit = tlp_valid && ((addr_32 & BAR0_MASK) == (bar0_base & BAR0_MASK));
    assign bar1_hit = tlp_valid && ((addr_32 & BAR1_MASK) == (bar1_base & BAR1_MASK));
    assign bar2_hit = tlp_valid && ((addr_32 & BAR2_MASK) == (bar2_base & BAR2_MASK));

    // Offset extraction
    assign bar0_offset = tlp_addr[BAR0_SIZE-1:0];
    assign bar1_offset = tlp_addr[BAR1_SIZE-1:0];
    assign bar2_offset = tlp_addr[BAR2_SIZE-1:0];

endmodule
