//==============================================================================
// ISA Bus to AXI Bridge
//==============================================================================
// File: isa_bus_bridge.v
// Description: ISA bus bridge providing legacy PC/AT compatibility.
//              Supports both FDC (0x3Fx) and WD HDD (0x1Fx) controllers.
//              Directly interfaces with AXI4-Lite peripheral registers.
//
// Features:
//   - 8-bit ISA data bus
//   - I/O port decode for FDC (0x3F0-0x3F7) and WD (0x1F0-0x1F7, 0x3F6)
//   - IRQ generation (IRQ6 for FDC, IRQ14/15 for WD)
//   - DMA request generation (DRQ2 for FDC)
//   - Wait state insertion via IOCHRDY
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 21:45
//==============================================================================

`timescale 1ns / 1ps

module isa_bus_bridge #(
    parameter FDC_AXI_BASE = 32'h80006000,  // FDC AXI base address
    parameter WD_AXI_BASE  = 32'h80007100   // WD controller AXI base address
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // ISA Bus Interface
    //=========================================================================
    input  wire [9:0]  isa_addr,          // I/O address (bits 9:0)
    input  wire [7:0]  isa_data_in,       // Data from ISA bus
    output reg  [7:0]  isa_data_out,      // Data to ISA bus
    output wire        isa_data_oe,       // Output enable for data bus
    input  wire        isa_ior_n,         // I/O Read strobe (active low)
    input  wire        isa_iow_n,         // I/O Write strobe (active low)
    input  wire        isa_aen,           // Address Enable (high during DMA)
    output wire        isa_iochrdy,       // I/O Channel Ready (active high)

    // Interrupt outputs
    output wire        isa_irq6,          // IRQ6 - FDC interrupt
    output wire        isa_irq14,         // IRQ14 - Primary HDD interrupt
    output wire        isa_irq15,         // IRQ15 - Secondary HDD interrupt

    // DMA signals
    output wire        isa_drq2,          // DRQ2 - FDC DMA request
    input  wire        isa_dack2_n,       // DACK2 - FDC DMA acknowledge
    output wire        isa_tc,            // Terminal Count

    //=========================================================================
    // AXI4-Lite Master Interface (to FDC/WD peripherals)
    //=========================================================================
    output reg  [31:0] m_axi_awaddr,      // Write address
    output reg         m_axi_awvalid,     // Write address valid
    input  wire        m_axi_awready,     // Write address ready

    output reg  [31:0] m_axi_wdata,       // Write data
    output reg  [3:0]  m_axi_wstrb,       // Write strobes
    output reg         m_axi_wvalid,      // Write valid
    input  wire        m_axi_wready,      // Write ready

    input  wire [1:0]  m_axi_bresp,       // Write response
    input  wire        m_axi_bvalid,      // Write response valid
    output reg         m_axi_bready,      // Write response ready

    output reg  [31:0] m_axi_araddr,      // Read address
    output reg         m_axi_arvalid,     // Read address valid
    input  wire        m_axi_arready,     // Read address ready

    input  wire [31:0] m_axi_rdata,       // Read data
    input  wire [1:0]  m_axi_rresp,       // Read response
    input  wire        m_axi_rvalid,      // Read valid
    output reg         m_axi_rready,      // Read ready

    //=========================================================================
    // Interrupt/Status Inputs (from peripherals)
    //=========================================================================
    input  wire        fdc_irq,           // FDC interrupt request
    input  wire        fdc_drq,           // FDC DMA request
    input  wire        wd_irq_pri,        // WD primary interrupt
    input  wire        wd_irq_sec,        // WD secondary interrupt
    input  wire        wd_drq,            // WD data request (for PIO)

    //=========================================================================
    // Configuration
    //=========================================================================
    input  wire        fdc_enable,        // Enable FDC decode
    input  wire        wd_enable,         // Enable WD decode
    input  wire [9:0]  wd_io_base,        // WD I/O base (default 0x1F0)
    input  wire [9:0]  wd_alt_base        // WD alternate base (default 0x3F6)
);

    //=========================================================================
    // Address Decode
    //=========================================================================
    // FDC: 0x3F0-0x3F7 (primary)
    // WD:  0x1F0-0x1F7 (primary), 0x3F6-0x3F7 (alternate)
    //      0x170-0x177 (secondary), 0x376-0x377 (alternate)

    wire fdc_select;
    wire wd_primary_select;
    wire wd_alt_select;
    wire wd_select;

    // FDC decode: 0x3F0-0x3F7
    assign fdc_select = fdc_enable &&
                        (isa_addr[9:3] == 7'b0111111) &&  // 0x3F0-0x3F7
                        !isa_aen;

    // WD primary decode: typically 0x1F0-0x1F7
    assign wd_primary_select = wd_enable &&
                               (isa_addr[9:3] == wd_io_base[9:3]) &&
                               !isa_aen;

    // WD alternate decode: typically 0x3F6-0x3F7
    assign wd_alt_select = wd_enable &&
                           (isa_addr[9:1] == wd_alt_base[9:1]) &&
                           !isa_aen;

    assign wd_select = wd_primary_select || wd_alt_select;

    // Combined device select
    wire device_select = fdc_select || wd_select;

    // Register offset within device
    wire [2:0] fdc_reg_offset = isa_addr[2:0];
    wire [2:0] wd_reg_offset = wd_alt_select ? 3'h7 : isa_addr[2:0];

    //=========================================================================
    // ISA Bus State Machine
    //=========================================================================
    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_AXI_ADDR = 3'd1;
    localparam [2:0] ST_AXI_DATA = 3'd2;
    localparam [2:0] ST_AXI_RESP = 3'd3;
    localparam [2:0] ST_COMPLETE = 3'd4;

    reg [2:0] state;
    reg       is_read;
    reg       is_fdc;
    reg [2:0] reg_offset;
    reg [7:0] read_data_latch;
    reg       ready_out;

    // Edge detection for ISA strobes
    reg isa_ior_n_d, isa_iow_n_d;
    wire isa_read_start  = isa_ior_n_d && !isa_ior_n && device_select;
    wire isa_write_start = isa_iow_n_d && !isa_iow_n && device_select;
    wire isa_cycle_end   = (!isa_ior_n_d && isa_ior_n) ||
                           (!isa_iow_n_d && isa_iow_n);

    always @(posedge clk) begin
        isa_ior_n_d <= isa_ior_n;
        isa_iow_n_d <= isa_iow_n;
    end

    //=========================================================================
    // AXI Address Calculation
    //=========================================================================
    function [31:0] calc_axi_addr;
        input        is_fdc;
        input [2:0]  reg_off;
        input        is_alt;
        begin
            if (is_fdc) begin
                // FDC registers are at 4-byte aligned offsets
                calc_axi_addr = FDC_AXI_BASE + ({29'b0, reg_off} << 2);
            end else begin
                // WD registers: primary 0x00-0x1C, alt at 0x20
                if (is_alt) begin
                    calc_axi_addr = WD_AXI_BASE + 32'h20;  // Alt status/control
                end else begin
                    calc_axi_addr = WD_AXI_BASE + ({29'b0, reg_off} << 2);
                end
            end
        end
    endfunction

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= ST_IDLE;
            is_read         <= 1'b0;
            is_fdc          <= 1'b0;
            reg_offset      <= 3'b0;
            read_data_latch <= 8'h00;
            ready_out       <= 1'b1;

            m_axi_awaddr    <= 32'h0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= 32'h0;
            m_axi_wstrb     <= 4'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            m_axi_araddr    <= 32'h0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
        end else begin
            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    ready_out <= 1'b1;

                    if (isa_read_start) begin
                        // ISA read cycle starting
                        is_read    <= 1'b1;
                        is_fdc     <= fdc_select;
                        reg_offset <= fdc_select ? fdc_reg_offset : wd_reg_offset;
                        ready_out  <= 1'b0;  // Insert wait states

                        // Issue AXI read
                        m_axi_araddr  <= calc_axi_addr(fdc_select,
                                                       fdc_select ? fdc_reg_offset : wd_reg_offset,
                                                       wd_alt_select);
                        m_axi_arvalid <= 1'b1;
                        state         <= ST_AXI_ADDR;

                    end else if (isa_write_start) begin
                        // ISA write cycle starting
                        is_read    <= 1'b0;
                        is_fdc     <= fdc_select;
                        reg_offset <= fdc_select ? fdc_reg_offset : wd_reg_offset;
                        ready_out  <= 1'b0;

                        // Issue AXI write address
                        m_axi_awaddr  <= calc_axi_addr(fdc_select,
                                                       fdc_select ? fdc_reg_offset : wd_reg_offset,
                                                       wd_alt_select);
                        m_axi_awvalid <= 1'b1;

                        // Write data (8-bit value in low byte)
                        m_axi_wdata   <= {24'h0, isa_data_in};
                        m_axi_wstrb   <= 4'b0001;  // Only low byte
                        m_axi_wvalid  <= 1'b1;

                        state <= ST_AXI_ADDR;
                    end
                end

                //-------------------------------------------------------------
                ST_AXI_ADDR: begin
                    // Wait for address acceptance
                    if (is_read) begin
                        if (m_axi_arready) begin
                            m_axi_arvalid <= 1'b0;
                            m_axi_rready  <= 1'b1;
                            state         <= ST_AXI_DATA;
                        end
                    end else begin
                        // Write - address and data can be accepted independently
                        if (m_axi_awready) begin
                            m_axi_awvalid <= 1'b0;
                        end
                        if (m_axi_wready) begin
                            m_axi_wvalid <= 1'b0;
                        end
                        // Both accepted - wait for response
                        if (!m_axi_awvalid && !m_axi_wvalid) begin
                            m_axi_bready <= 1'b1;
                            state        <= ST_AXI_RESP;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_AXI_DATA: begin
                    // Read data phase
                    if (m_axi_rvalid) begin
                        read_data_latch <= m_axi_rdata[7:0];  // Capture low byte
                        m_axi_rready    <= 1'b0;
                        state           <= ST_COMPLETE;
                    end
                end

                //-------------------------------------------------------------
                ST_AXI_RESP: begin
                    // Write response phase
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        state        <= ST_COMPLETE;
                    end
                end

                //-------------------------------------------------------------
                ST_COMPLETE: begin
                    // Release wait state
                    ready_out <= 1'b1;

                    // Wait for ISA cycle to end
                    if (isa_cycle_end) begin
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Output Generation
    //=========================================================================

    // Data bus output
    always @(*) begin
        if (is_read && (state == ST_COMPLETE || state == ST_AXI_DATA)) begin
            isa_data_out = read_data_latch;
        end else begin
            isa_data_out = 8'hFF;  // Default pullup value
        end
    end

    // Output enable - active when reading from this device
    assign isa_data_oe = device_select && !isa_ior_n && !isa_aen;

    // IOCHRDY - low to insert wait states
    assign isa_iochrdy = ready_out;

    //=========================================================================
    // Interrupt and DMA Outputs
    //=========================================================================

    // Pass through interrupt signals
    assign isa_irq6  = fdc_irq && fdc_enable;
    assign isa_irq14 = wd_irq_pri && wd_enable;
    assign isa_irq15 = wd_irq_sec && wd_enable;

    // FDC DMA request
    assign isa_drq2 = fdc_drq && fdc_enable;

    // Terminal count (directly from system)
    assign isa_tc = 1'b0;  // Directly tied or from DMA controller

endmodule
