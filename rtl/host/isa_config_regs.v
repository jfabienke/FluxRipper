//==============================================================================
// ISA Configuration Registers
//==============================================================================
// File: isa_config_regs.v
// Description: User-accessible configuration registers for enabling/disabling
//              FDC and HDD controllers. Accessible from Option ROM BIOS for
//              non-PnP systems.
//
// Register Map (offset from config base, typically WD_BASE + 0xD0):
//   0x00: CONFIG_CTRL      - Global control register
//   0x01: CONFIG_FDC       - FDC configuration
//   0x02: CONFIG_WD        - WD HDD configuration
//   0x03: CONFIG_DMA       - DMA configuration
//   0x04: CONFIG_IRQ       - IRQ configuration
//   0x05: CONFIG_STATUS    - Status register (read-only)
//   0x06: CONFIG_SCRATCH   - Scratch register (for BIOS use)
//   0x07: CONFIG_MAGIC     - Magic number for validation
//   0x08: CONFIG_INTLV_CTRL - Interleave control (0=auto, 1-8=override)
//   0x09: CONFIG_INTLV_STAT - Detected interleave (read-only)
//   0x0E: CONFIG_SAVE      - Write 0x5A to save to flash
//   0x0F: CONFIG_RESTORE   - Write 0xA5 to restore defaults
//
// Access from BIOS:
//   MOV DX, WD_BASE + 0xD0   ; Config base
//   IN  AL, DX               ; Read CONFIG_CTRL
//   OR  AL, 0x01             ; Enable FDC
//   OUT DX, AL               ; Write CONFIG_CTRL
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-08
//==============================================================================

`timescale 1ns / 1ps

module isa_config_regs #(
    parameter MAGIC_NUMBER = 8'hFB      // FluxRipper magic byte
)(
    input  wire        clk,
    input  wire        rst_n,

    //-------------------------------------------------------------------------
    // Register Interface (directly from ISA decode)
    //-------------------------------------------------------------------------
    input  wire [3:0]  reg_addr,        // 4-bit register address (0x0-0xF)
    input  wire [7:0]  reg_wdata,       // Write data
    input  wire        reg_write,       // Write strobe
    input  wire        reg_read,        // Read strobe
    output reg  [7:0]  reg_rdata,       // Read data

    //-------------------------------------------------------------------------
    // Flash Interface (for persistent storage)
    //-------------------------------------------------------------------------
    output reg         flash_save_req,  // Request to save config to flash
    output reg         flash_restore_req, // Request to restore from flash
    input  wire        flash_busy,      // Flash operation in progress
    input  wire        flash_done,      // Flash operation complete

    // Data to/from flash
    output wire [63:0] flash_wdata,     // Config data to save
    input  wire [63:0] flash_rdata,     // Config data from flash
    input  wire        flash_valid,     // Flash data is valid

    //-------------------------------------------------------------------------
    // Configuration Outputs
    //-------------------------------------------------------------------------
    output wire        fdc_enable,      // FDC controller enabled
    output wire        wd_enable,       // WD HDD controller enabled
    output wire        fdc_dma_enable,  // FDC DMA enabled
    output wire        wd_dma_enable,   // WD DMA enabled (XT mode)
    output wire [3:0]  fdc_irq_sel,     // FDC IRQ selection
    output wire [3:0]  wd_irq_sel,      // WD IRQ selection
    output wire [2:0]  fdc_dma_sel,     // FDC DMA channel selection
    output wire [2:0]  wd_dma_sel,      // WD DMA channel selection

    //-------------------------------------------------------------------------
    // Status Inputs
    //-------------------------------------------------------------------------
    input  wire        slot_is_8bit,    // 8-bit XT slot detected
    input  wire        slot_is_16bit,   // 16-bit AT slot detected
    input  wire        pnp_active,      // PnP mode active
    input  wire [1:0]  wd_personality,  // Current WD personality

    //-------------------------------------------------------------------------
    // Controller Presence (for UI display)
    //-------------------------------------------------------------------------
    input  wire        fdc_present,     // FDC hardware is installed
    input  wire        wd_present,      // WD hardware is installed

    //-------------------------------------------------------------------------
    // Interleave Control/Status
    //-------------------------------------------------------------------------
    output wire [3:0]  interleave_target,    // Target interleave (0=auto, 1-8=override)
    output wire        interleave_override,  // 1 = use target, 0 = auto-match
    input  wire [3:0]  interleave_detected,  // Last detected interleave (from track buffer)

    //-------------------------------------------------------------------------
    // Track Buffer Control
    //-------------------------------------------------------------------------
    output wire        track_buf_bypass      // 1 = bypass track buffer caching (for benchmark)
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam REG_CTRL     = 4'h0;     // Global control
    localparam REG_FDC      = 4'h1;     // FDC configuration
    localparam REG_WD       = 4'h2;     // WD HDD configuration
    localparam REG_DMA      = 4'h3;     // DMA configuration
    localparam REG_IRQ      = 4'h4;     // IRQ configuration
    localparam REG_STATUS   = 4'h5;     // Status (read-only)
    localparam REG_SCRATCH  = 4'h6;     // Scratch register
    localparam REG_MAGIC    = 4'h7;     // Magic number
    localparam REG_INTLV_CTRL = 4'h8;   // Interleave control
    localparam REG_INTLV_STAT = 4'h9;   // Interleave status (read-only)
    localparam REG_SAVE     = 4'hE;     // Save to flash
    localparam REG_RESTORE  = 4'hF;     // Restore defaults

    // Magic values for save/restore
    localparam MAGIC_SAVE    = 8'h5A;
    localparam MAGIC_RESTORE = 8'hA5;

    //=========================================================================
    // Configuration Registers
    //=========================================================================
    // CONFIG_CTRL (0x00)
    //   [0] FDC Enable
    //   [1] WD Enable
    //   [2] Reserved
    //   [3] Reserved
    //   [4] Config locked (write protect)
    //   [7:5] Reserved
    reg [7:0] r_ctrl;

    // CONFIG_FDC (0x01)
    //   [0] FDC DMA Enable
    //   [1] FDC Secondary Enable (0x370)
    //   [7:2] Reserved
    reg [7:0] r_fdc;

    // CONFIG_WD (0x02)
    //   [0] WD DMA Enable (XT mode)
    //   [1] WD Secondary Enable (0x170)
    //   [6:2] Reserved
    //   [7] Track Buffer Bypass (for benchmark - disables caching)
    reg [7:0] r_wd;

    // CONFIG_DMA (0x03)
    //   [2:0] FDC DMA Channel (default 2)
    //   [3]   Reserved
    //   [6:4] WD DMA Channel (default 3)
    //   [7]   Reserved
    reg [7:0] r_dma;

    // CONFIG_IRQ (0x04)
    //   [3:0] FDC IRQ (default 6)
    //   [7:4] WD IRQ (default 14 for AT, 5 for XT)
    reg [7:0] r_irq;

    // CONFIG_SCRATCH (0x06) - general purpose
    reg [7:0] r_scratch;

    // CONFIG_INTLV_CTRL (0x08) - Interleave control
    //   [3:0] Target interleave (0 = auto-match, 1-8 = override)
    //   [7:4] Reserved
    reg [7:0] r_intlv_ctrl;

    //=========================================================================
    // Default Values
    //=========================================================================
    localparam DEFAULT_CTRL = 8'b0000_0011;  // FDC + WD enabled
    localparam DEFAULT_FDC  = 8'b0000_0001;  // FDC DMA enabled
    localparam DEFAULT_WD   = 8'b0000_0001;  // WD DMA enabled (for XT)
    localparam DEFAULT_DMA  = 8'b0011_0010;  // WD=3, FDC=2
    localparam DEFAULT_IRQ  = 8'b1110_0110;  // WD=14, FDC=6
    localparam DEFAULT_INTLV = 8'b0000_0000; // Interleave auto-match (0)

    //=========================================================================
    // Status Register Composition (read-only)
    //=========================================================================
    // CONFIG_STATUS (0x05)
    //   [0] Slot is 8-bit
    //   [1] Slot is 16-bit
    //   [2] PnP mode active
    //   [3] Flash busy
    //   [5:4] WD Personality
    //   [6] FDC hardware present
    //   [7] WD hardware present
    wire [7:0] status_reg;
    assign status_reg = {
        wd_present,         // [7] WD hardware present
        fdc_present,        // [6] FDC hardware present
        wd_personality,     // [5:4] WD Personality
        flash_busy,         // [3] Flash busy
        pnp_active,         // [2] PnP mode active
        slot_is_16bit,      // [1] 16-bit slot
        slot_is_8bit        // [0] 8-bit slot
    };

    //=========================================================================
    // Output Assignments
    //=========================================================================
    assign fdc_enable     = r_ctrl[0];
    assign wd_enable      = r_ctrl[1];
    assign fdc_dma_enable = r_fdc[0];
    assign wd_dma_enable  = r_wd[0];
    assign fdc_dma_sel    = r_dma[2:0];
    assign wd_dma_sel     = r_dma[6:4];
    assign fdc_irq_sel    = r_irq[3:0];
    assign wd_irq_sel     = r_irq[7:4];

    // Interleave outputs
    assign interleave_target   = r_intlv_ctrl[3:0];
    assign interleave_override = (r_intlv_ctrl[3:0] != 4'h0);  // Non-zero = override

    // Track buffer bypass (bit 7 of CONFIG_WD)
    assign track_buf_bypass = r_wd[7];

    // Flash data packing
    assign flash_wdata = {
        8'h00,          // [63:56] Reserved
        r_scratch,      // [55:48] Scratch
        r_irq,          // [47:40] IRQ config
        r_dma,          // [39:32] DMA config
        r_wd,           // [31:24] WD config
        r_fdc,          // [23:16] FDC config
        r_ctrl,         // [15:8]  Control
        MAGIC_NUMBER    // [7:0]   Magic (validation)
    };

    //=========================================================================
    // Write Logic
    //=========================================================================
    wire config_locked = r_ctrl[4];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset to defaults
            r_ctrl       <= DEFAULT_CTRL;
            r_fdc        <= DEFAULT_FDC;
            r_wd         <= DEFAULT_WD;
            r_dma        <= DEFAULT_DMA;
            r_irq        <= DEFAULT_IRQ;
            r_scratch    <= 8'h00;
            r_intlv_ctrl <= DEFAULT_INTLV;
            flash_save_req    <= 1'b0;
            flash_restore_req <= 1'b0;
        end else begin
            // Clear single-cycle requests
            flash_save_req    <= 1'b0;
            flash_restore_req <= 1'b0;

            // Handle flash restore completion
            if (flash_valid) begin
                // Validate magic number before loading
                if (flash_rdata[7:0] == MAGIC_NUMBER) begin
                    r_ctrl    <= flash_rdata[15:8];
                    r_fdc     <= flash_rdata[23:16];
                    r_wd      <= flash_rdata[31:24];
                    r_dma     <= flash_rdata[39:32];
                    r_irq     <= flash_rdata[47:40];
                    r_scratch <= flash_rdata[55:48];
                end
                // If magic doesn't match, keep defaults
            end

            // Register writes
            if (reg_write && !config_locked) begin
                case (reg_addr)
                    REG_CTRL: begin
                        r_ctrl <= reg_wdata;
                    end

                    REG_FDC: begin
                        r_fdc <= reg_wdata;
                    end

                    REG_WD: begin
                        r_wd <= reg_wdata;
                    end

                    REG_DMA: begin
                        r_dma <= reg_wdata;
                    end

                    REG_IRQ: begin
                        r_irq <= reg_wdata;
                    end

                    REG_SCRATCH: begin
                        r_scratch <= reg_wdata;
                    end

                    REG_INTLV_CTRL: begin
                        // Only allow values 0-8 (0=auto, 1-8=override)
                        if (reg_wdata[3:0] <= 4'd8) begin
                            r_intlv_ctrl <= {4'h0, reg_wdata[3:0]};
                        end
                    end

                    REG_SAVE: begin
                        if (reg_wdata == MAGIC_SAVE && !flash_busy) begin
                            flash_save_req <= 1'b1;
                        end
                    end

                    REG_RESTORE: begin
                        if (reg_wdata == MAGIC_RESTORE && !flash_busy) begin
                            flash_restore_req <= 1'b1;
                        end
                    end

                    // REG_STATUS and REG_MAGIC are read-only
                    default: ;
                endcase
            end

            // Allow unlocking even when locked (write 0 to bit 4)
            if (reg_write && reg_addr == REG_CTRL && config_locked) begin
                if ((reg_wdata & 8'h10) == 8'h00) begin
                    r_ctrl[4] <= 1'b0;  // Unlock
                end
            end
        end
    end

    //=========================================================================
    // Read Logic
    //=========================================================================
    always @(*) begin
        case (reg_addr)
            REG_CTRL:       reg_rdata = r_ctrl;
            REG_FDC:        reg_rdata = r_fdc;
            REG_WD:         reg_rdata = r_wd;
            REG_DMA:        reg_rdata = r_dma;
            REG_IRQ:        reg_rdata = r_irq;
            REG_STATUS:     reg_rdata = status_reg;
            REG_SCRATCH:    reg_rdata = r_scratch;
            REG_MAGIC:      reg_rdata = MAGIC_NUMBER;
            REG_INTLV_CTRL: reg_rdata = r_intlv_ctrl;
            REG_INTLV_STAT: reg_rdata = {4'h0, interleave_detected};  // Read-only
            REG_SAVE:       reg_rdata = flash_busy ? 8'hFF : 8'h00;
            REG_RESTORE:    reg_rdata = flash_busy ? 8'hFF : 8'h00;
            default:        reg_rdata = 8'hFF;
        endcase
    end

endmodule
