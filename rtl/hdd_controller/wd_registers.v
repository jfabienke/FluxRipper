//==============================================================================
// WD Controller Task File Register Model
//==============================================================================
// File: wd_registers.v
// Description: Western Digital WD1003/WD1006/WD1007 compatible task file
//              register implementation for FluxRipper HDD controller emulation.
//
// Register Map (AT-compatible):
//   Offset 0x0: DATA        - Data register (R/W)
//   Offset 0x1: ERROR       - Error register (R) / Features (W)
//   Offset 0x2: SECCNT      - Sector count (R/W)
//   Offset 0x3: SECNUM      - Sector number (R/W)
//   Offset 0x4: CYL_LO      - Cylinder low byte (R/W)
//   Offset 0x5: CYL_HI      - Cylinder high byte (R/W)
//   Offset 0x6: SDH         - Size/Drive/Head (R/W)
//   Offset 0x7: STATUS      - Status register (R) / Command (W)
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04
//==============================================================================

`timescale 1ns / 1ps

module wd_registers (
    input  wire        clk,
    input  wire        reset_n,

    //--------------------------------------------------------------------------
    // Register Interface (from host: ISA, AXI, or PCIe)
    //--------------------------------------------------------------------------
    input  wire [2:0]  reg_addr,        // 3-bit register address (0-7)
    input  wire [7:0]  reg_wdata,       // Write data from host
    input  wire        reg_write,       // Write strobe
    input  wire        reg_read,        // Read strobe
    output reg  [7:0]  reg_rdata,       // Read data to host

    //--------------------------------------------------------------------------
    // Data FIFO Interface (for sector data transfers)
    //--------------------------------------------------------------------------
    input  wire [7:0]  fifo_rdata,      // Data from track buffer
    input  wire        fifo_empty,      // Track buffer empty
    output wire        fifo_rd,         // Read from track buffer
    output wire [7:0]  fifo_wdata,      // Data to track buffer
    input  wire        fifo_full,       // Track buffer full
    output wire        fifo_wr,         // Write to track buffer

    //--------------------------------------------------------------------------
    // Command Interface (to wd_command_fsm)
    //--------------------------------------------------------------------------
    output reg  [7:0]  cmd_code,        // Command code written to CMD register
    output reg         cmd_valid,       // Command valid strobe (1 clock)
    input  wire        cmd_busy,        // FSM is processing a command

    //--------------------------------------------------------------------------
    // Status Interface (from wd_command_fsm)
    //--------------------------------------------------------------------------
    input  wire        status_bsy,      // Busy - controller is executing
    input  wire        status_rdy,      // Ready - drive is ready
    input  wire        status_wf,       // Write Fault
    input  wire        status_sc,       // Seek Complete
    input  wire        status_drq,      // Data Request
    input  wire        status_corr,     // Corrected data (ECC)
    input  wire        status_idx,      // Index pulse
    input  wire        status_err,      // Error occurred

    //--------------------------------------------------------------------------
    // Error Register (from wd_command_fsm)
    //--------------------------------------------------------------------------
    input  wire [7:0]  error_code,      // Error code to report

    //--------------------------------------------------------------------------
    // Address/Geometry Outputs (to seek controller and buffer)
    //--------------------------------------------------------------------------
    output wire [15:0] cylinder,        // Combined CYL_HI:CYL_LO
    output wire [3:0]  head,            // Head from SDH register
    output wire        drive_sel,       // Drive select from SDH
    output wire [7:0]  sector_num,      // Sector number
    output wire [7:0]  sector_count,    // Sector count

    //--------------------------------------------------------------------------
    // Feature Configuration
    //--------------------------------------------------------------------------
    output wire [7:0]  features,        // Feature register value

    //--------------------------------------------------------------------------
    // Interrupt Control
    //--------------------------------------------------------------------------
    output wire        irq_request,     // Interrupt request to host
    input  wire        irq_ack,         // Interrupt acknowledged

    //--------------------------------------------------------------------------
    // Sector Count Control (from command FSM)
    //--------------------------------------------------------------------------
    input  wire        dec_sector_count // Decrement sector count after each sector
);

//==============================================================================
// Register Addresses
//==============================================================================
localparam REG_DATA    = 3'h0;  // Data register
localparam REG_ERROR   = 3'h1;  // Error (R) / Features (W)
localparam REG_SECCNT  = 3'h2;  // Sector count
localparam REG_SECNUM  = 3'h3;  // Sector number
localparam REG_CYL_LO  = 3'h4;  // Cylinder low
localparam REG_CYL_HI  = 3'h5;  // Cylinder high
localparam REG_SDH     = 3'h6;  // Size/Drive/Head
localparam REG_STATUS  = 3'h7;  // Status (R) / Command (W)

//==============================================================================
// Status Register Bit Positions
//==============================================================================
localparam STS_BSY  = 7;  // Busy
localparam STS_RDY  = 6;  // Ready
localparam STS_WF   = 5;  // Write Fault
localparam STS_SC   = 4;  // Seek Complete
localparam STS_DRQ  = 3;  // Data Request
localparam STS_CORR = 2;  // Corrected data
localparam STS_IDX  = 1;  // Index
localparam STS_ERR  = 0;  // Error

//==============================================================================
// SDH Register Bit Positions
//==============================================================================
// [7:5] = SIZE (sector size encoding, typically 010 = 512 bytes)
// [4]   = DRV (drive select: 0 = drive 0, 1 = drive 1)
// [3:0] = HEAD (head select 0-15)
localparam SDH_SIZE_HI = 7;
localparam SDH_SIZE_LO = 5;
localparam SDH_DRV     = 4;
localparam SDH_HEAD_HI = 3;
localparam SDH_HEAD_LO = 0;

//==============================================================================
// Internal Registers
//==============================================================================
reg [7:0] r_features;       // Features register (written via ERROR address)
reg [7:0] r_sector_count;   // Sector count register
reg [7:0] r_sector_num;     // Sector number register
reg [7:0] r_cyl_lo;         // Cylinder low byte
reg [7:0] r_cyl_hi;         // Cylinder high byte
reg [7:0] r_sdh;            // Size/Drive/Head register
reg       r_irq_pending;    // Interrupt pending flag

//==============================================================================
// Status Register Composition
//==============================================================================
wire [7:0] status_reg;
assign status_reg = {
    status_bsy,     // [7] BSY
    status_rdy,     // [6] RDY
    status_wf,      // [5] WF
    status_sc,      // [4] SC
    status_drq,     // [3] DRQ
    status_corr,    // [2] CORR
    status_idx,     // [1] IDX
    status_err      // [0] ERR
};

//==============================================================================
// Output Assignments
//==============================================================================
assign cylinder     = {r_cyl_hi, r_cyl_lo};
assign head         = r_sdh[SDH_HEAD_HI:SDH_HEAD_LO];
assign drive_sel    = r_sdh[SDH_DRV];
assign sector_num   = r_sector_num;
assign sector_count = r_sector_count;
assign features     = r_features;

// Data FIFO interface - directly connected to data register access
assign fifo_wdata = reg_wdata;
assign fifo_wr    = reg_write && (reg_addr == REG_DATA) && !fifo_full;
assign fifo_rd    = reg_read && (reg_addr == REG_DATA) && !fifo_empty;

// Interrupt request
assign irq_request = r_irq_pending;

//==============================================================================
// Register Write Logic
//==============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        r_features     <= 8'h00;
        r_sector_count <= 8'h01;  // Default 1 sector
        r_sector_num   <= 8'h01;  // Sector numbers start at 1
        r_cyl_lo       <= 8'h00;
        r_cyl_hi       <= 8'h00;
        r_sdh          <= 8'hA0;  // 512-byte sectors, drive 0, head 0
        cmd_code       <= 8'h00;
        cmd_valid      <= 1'b0;
    end else begin
        // Clear command valid after one clock
        cmd_valid <= 1'b0;

        if (reg_write && !status_bsy) begin
            case (reg_addr)
                REG_ERROR: begin
                    // Write to ERROR address sets Features register
                    r_features <= reg_wdata;
                end

                REG_SECCNT: begin
                    r_sector_count <= reg_wdata;
                end

                REG_SECNUM: begin
                    r_sector_num <= reg_wdata;
                end

                REG_CYL_LO: begin
                    r_cyl_lo <= reg_wdata;
                end

                REG_CYL_HI: begin
                    r_cyl_hi <= reg_wdata;
                end

                REG_SDH: begin
                    r_sdh <= reg_wdata;
                end

                REG_STATUS: begin
                    // Write to STATUS address issues a command
                    cmd_code  <= reg_wdata;
                    cmd_valid <= 1'b1;
                end

                // REG_DATA handled by FIFO interface
                default: ;
            endcase
        end

        // Sector count decrement (from command FSM after each sector transfer)
        if (dec_sector_count && r_sector_count != 8'h00) begin
            r_sector_count <= r_sector_count - 8'h01;
        end
    end
end

//==============================================================================
// Register Read Logic
//==============================================================================
always @(*) begin
    case (reg_addr)
        REG_DATA:   reg_rdata = fifo_rdata;
        REG_ERROR:  reg_rdata = error_code;
        REG_SECCNT: reg_rdata = r_sector_count;
        REG_SECNUM: reg_rdata = r_sector_num;
        REG_CYL_LO: reg_rdata = r_cyl_lo;
        REG_CYL_HI: reg_rdata = r_cyl_hi;
        REG_SDH:    reg_rdata = r_sdh;
        REG_STATUS: reg_rdata = status_reg;
        default:    reg_rdata = 8'h00;
    endcase
end

//==============================================================================
// Interrupt Logic
//==============================================================================
// WD controllers generate an interrupt when:
// 1. Command completes (BSY goes low)
// 2. DRQ is set (data ready for transfer)
// The interrupt is cleared when status is read

reg r_prev_bsy;
reg r_prev_drq;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        r_irq_pending <= 1'b0;
        r_prev_bsy    <= 1'b1;
        r_prev_drq    <= 1'b0;
    end else begin
        r_prev_bsy <= status_bsy;
        r_prev_drq <= status_drq;

        // Set interrupt on BSY falling edge or DRQ rising edge
        if ((r_prev_bsy && !status_bsy) || (!r_prev_drq && status_drq)) begin
            r_irq_pending <= 1'b1;
        end

        // Clear interrupt on status read or explicit ack
        if ((reg_read && reg_addr == REG_STATUS) || irq_ack) begin
            r_irq_pending <= 1'b0;
        end
    end
end

endmodule

