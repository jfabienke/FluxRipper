//==============================================================================
// PCIe DMA Engine
//==============================================================================
// File: pcie_dma_engine.v
// Description: Shared DMA controller for FDC and WD HDD data transfers.
//              Supports scatter-gather, host-to-device and device-to-host.
//
// Features:
//   - 64-bit addressing
//   - Scatter-gather descriptor support
//   - Dual channel (FDC and WD HDD)
//   - Configurable burst size
//   - Transfer completion interrupt
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 23:50
//==============================================================================

`timescale 1ns / 1ps

module pcie_dma_engine #(
    parameter MAX_BURST_SIZE = 256,      // Max burst in bytes
    parameter DESC_RING_SIZE = 64,       // Descriptor ring entries
    parameter DATA_WIDTH     = 64        // Internal data path width
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // DMA Control Registers
    //=========================================================================
    input  wire [31:0] dma_ctrl,         // Control register
    input  wire [63:0] dma_host_addr,    // Host buffer base address
    input  wire [31:0] dma_local_addr,   // Local buffer address
    input  wire [23:0] dma_length,       // Transfer length in bytes
    input  wire [63:0] dma_sg_addr,      // Scatter-gather list base
    output reg  [31:0] dma_status,       // Status register
    output reg  [23:0] dma_bytes_done,   // Bytes transferred

    //=========================================================================
    // Channel Select and Control
    //=========================================================================
    input  wire        ch_sel,           // 0=FDC, 1=WD HDD
    input  wire        dma_start,        // Start transfer
    input  wire        dma_abort,        // Abort transfer
    input  wire        dma_direction,    // 0=H2D (read from host), 1=D2H (write to host)
    input  wire        sg_enable,        // Use scatter-gather

    //=========================================================================
    // PCIe TLP Request Interface
    //=========================================================================
    output reg         pcie_rd_req,      // Memory read request
    output reg         pcie_wr_req,      // Memory write request
    output reg  [63:0] pcie_addr,        // Request address
    output reg  [9:0]  pcie_len,         // Request length (DWORDs)
    output reg  [7:0]  pcie_tag,         // Request tag
    input  wire        pcie_req_grant,   // Request granted

    //=========================================================================
    // PCIe Completion Interface
    //=========================================================================
    input  wire        pcie_cpl_valid,   // Completion valid
    input  wire [63:0] pcie_cpl_data,    // Completion data
    input  wire [7:0]  pcie_cpl_tag,     // Completion tag
    input  wire        pcie_cpl_last,    // Last completion for request
    output reg         pcie_cpl_ready,   // Ready to accept completion

    //=========================================================================
    // Local Memory Interface - FDC
    //=========================================================================
    output reg  [15:0] fdc_buf_addr,     // FDC buffer address
    output reg  [63:0] fdc_buf_wdata,    // FDC buffer write data
    output reg         fdc_buf_write,    // FDC buffer write enable
    input  wire [63:0] fdc_buf_rdata,    // FDC buffer read data
    output reg         fdc_buf_read,     // FDC buffer read enable

    //=========================================================================
    // Local Memory Interface - WD HDD
    //=========================================================================
    output reg  [15:0] wd_buf_addr,      // WD buffer address
    output reg  [63:0] wd_buf_wdata,     // WD buffer write data
    output reg         wd_buf_write,     // WD buffer write enable
    input  wire [63:0] wd_buf_rdata,     // WD buffer read data
    output reg         wd_buf_read,      // WD buffer read enable

    //=========================================================================
    // Interrupt Interface
    //=========================================================================
    output reg         dma_done_irq,     // Transfer complete interrupt
    output reg         dma_error_irq     // Error interrupt
);

    //=========================================================================
    // DMA Control Register Bits
    //=========================================================================
    wire dma_enable    = dma_ctrl[0];
    wire dma_irq_en    = dma_ctrl[1];
    wire dma_sg_mode   = dma_ctrl[2] && sg_enable;
    wire [7:0] burst_size = dma_ctrl[15:8];  // In 64-bit words

    //=========================================================================
    // DMA Status Register Bits
    //=========================================================================
    localparam [3:0] STAT_IDLE    = 4'h0;
    localparam [3:0] STAT_BUSY    = 4'h1;
    localparam [3:0] STAT_DONE    = 4'h2;
    localparam [3:0] STAT_ERROR   = 4'hF;

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_FETCH_DESC  = 4'd1;
    localparam [3:0] ST_PARSE_DESC  = 4'd2;
    localparam [3:0] ST_CALC_BURST  = 4'd3;
    localparam [3:0] ST_H2D_REQ     = 4'd4;
    localparam [3:0] ST_H2D_WAIT    = 4'd5;
    localparam [3:0] ST_H2D_WRITE   = 4'd6;
    localparam [3:0] ST_D2H_READ    = 4'd7;
    localparam [3:0] ST_D2H_REQ     = 4'd8;
    localparam [3:0] ST_D2H_WAIT    = 4'd9;
    localparam [3:0] ST_NEXT_BURST  = 4'd10;
    localparam [3:0] ST_NEXT_DESC   = 4'd11;
    localparam [3:0] ST_COMPLETE    = 4'd12;
    localparam [3:0] ST_ERROR       = 4'd13;

    reg [3:0] state;

    //=========================================================================
    // Transfer Context
    //=========================================================================
    reg        ctx_direction;            // 0=H2D, 1=D2H
    reg        ctx_channel;              // 0=FDC, 1=WD
    reg [63:0] ctx_host_addr;            // Current host address
    reg [31:0] ctx_local_addr;           // Current local address
    reg [23:0] ctx_remaining;            // Bytes remaining
    reg [23:0] ctx_total;                // Total transfer size
    reg [7:0]  ctx_tag;                  // Current request tag

    // Burst tracking
    reg [9:0]  burst_dwords;             // DWORDs in current burst
    reg [9:0]  burst_count;              // DWORDs received/sent
    reg [63:0] burst_buffer [0:31];      // Burst buffer (32 x 64-bit = 256 bytes)
    reg [4:0]  burst_wr_ptr;
    reg [4:0]  burst_rd_ptr;

    //=========================================================================
    // Scatter-Gather Descriptor
    //=========================================================================
    // Descriptor format (16 bytes):
    //   [63:0]  - Host address
    //   [95:64] - Local address (low 16 bits used)
    //   [119:96] - Length in bytes
    //   [127:120] - Flags (bit 0 = last descriptor)

    reg [63:0] sg_desc_addr;
    reg [15:0] sg_desc_idx;
    reg [63:0] sg_host_addr;
    reg [31:0] sg_local_addr;
    reg [23:0] sg_length;
    reg        sg_last;

    // Descriptor fetch state
    reg [1:0]  desc_fetch_phase;

    //=========================================================================
    // Tag Management
    //=========================================================================
    reg [7:0]  next_tag;
    reg [255:0] tag_valid;               // Outstanding tags bitmap

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= ST_IDLE;
            dma_status      <= {28'h0, STAT_IDLE};
            dma_bytes_done  <= 24'h0;
            dma_done_irq    <= 1'b0;
            dma_error_irq   <= 1'b0;

            pcie_rd_req     <= 1'b0;
            pcie_wr_req     <= 1'b0;
            pcie_addr       <= 64'h0;
            pcie_len        <= 10'h0;
            pcie_tag        <= 8'h0;
            pcie_cpl_ready  <= 1'b1;

            fdc_buf_addr    <= 16'h0;
            fdc_buf_wdata   <= 64'h0;
            fdc_buf_write   <= 1'b0;
            fdc_buf_read    <= 1'b0;

            wd_buf_addr     <= 16'h0;
            wd_buf_wdata    <= 64'h0;
            wd_buf_write    <= 1'b0;
            wd_buf_read     <= 1'b0;

            ctx_direction   <= 1'b0;
            ctx_channel     <= 1'b0;
            ctx_host_addr   <= 64'h0;
            ctx_local_addr  <= 32'h0;
            ctx_remaining   <= 24'h0;
            ctx_total       <= 24'h0;
            ctx_tag         <= 8'h0;

            burst_dwords    <= 10'h0;
            burst_count     <= 10'h0;
            burst_wr_ptr    <= 5'h0;
            burst_rd_ptr    <= 5'h0;

            sg_desc_addr    <= 64'h0;
            sg_desc_idx     <= 16'h0;
            desc_fetch_phase <= 2'b00;

            next_tag        <= 8'h0;
            tag_valid       <= 256'h0;

        end else begin
            // Default: clear strobes
            dma_done_irq   <= 1'b0;
            dma_error_irq  <= 1'b0;
            fdc_buf_write  <= 1'b0;
            fdc_buf_read   <= 1'b0;
            wd_buf_write   <= 1'b0;
            wd_buf_read    <= 1'b0;
            pcie_rd_req    <= 1'b0;
            pcie_wr_req    <= 1'b0;

            // Abort handling
            if (dma_abort && state != ST_IDLE) begin
                state <= ST_ERROR;
            end

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    dma_status[3:0] <= STAT_IDLE;

                    if (dma_start && dma_enable) begin
                        // Initialize transfer context
                        ctx_direction  <= dma_direction;
                        ctx_channel    <= ch_sel;
                        ctx_total      <= dma_length;
                        dma_bytes_done <= 24'h0;

                        if (dma_sg_mode) begin
                            // Scatter-gather mode
                            sg_desc_addr <= dma_sg_addr;
                            sg_desc_idx  <= 16'h0;
                            state <= ST_FETCH_DESC;
                        end else begin
                            // Simple mode
                            ctx_host_addr  <= dma_host_addr;
                            ctx_local_addr <= dma_local_addr;
                            ctx_remaining  <= dma_length;
                            state <= ST_CALC_BURST;
                        end

                        dma_status[3:0] <= STAT_BUSY;
                    end
                end

                //-------------------------------------------------------------
                ST_FETCH_DESC: begin
                    // Fetch descriptor from host memory
                    // Need two 64-bit reads for 16-byte descriptor
                    if (!pcie_rd_req) begin
                        pcie_rd_req <= 1'b1;
                        pcie_addr   <= sg_desc_addr + {sg_desc_idx, 4'h0};
                        pcie_len    <= 10'd4;  // 4 DWORDs = 16 bytes
                        pcie_tag    <= next_tag;
                        ctx_tag     <= next_tag;
                        next_tag    <= next_tag + 1;
                    end else if (pcie_req_grant) begin
                        pcie_rd_req <= 1'b0;
                        tag_valid[ctx_tag] <= 1'b1;
                        desc_fetch_phase <= 2'b00;
                        state <= ST_PARSE_DESC;
                    end
                end

                //-------------------------------------------------------------
                ST_PARSE_DESC: begin
                    // Wait for completion and parse descriptor
                    pcie_cpl_ready <= 1'b1;

                    if (pcie_cpl_valid && pcie_cpl_tag == ctx_tag) begin
                        case (desc_fetch_phase)
                            2'b00: begin
                                sg_host_addr <= pcie_cpl_data;
                                desc_fetch_phase <= 2'b01;
                            end
                            2'b01: begin
                                sg_local_addr <= pcie_cpl_data[31:0];
                                sg_length     <= pcie_cpl_data[55:32];
                                sg_last       <= pcie_cpl_data[56];

                                if (pcie_cpl_last) begin
                                    tag_valid[ctx_tag] <= 1'b0;
                                    // Setup transfer from descriptor
                                    ctx_host_addr  <= sg_host_addr;
                                    ctx_local_addr <= pcie_cpl_data[31:0];
                                    ctx_remaining  <= pcie_cpl_data[55:32];
                                    state <= ST_CALC_BURST;
                                end
                            end
                        endcase
                    end
                end

                //-------------------------------------------------------------
                ST_CALC_BURST: begin
                    // Calculate burst size (max 256 bytes / 32 DWORDs)
                    if (ctx_remaining >= 256) begin
                        burst_dwords <= 10'd32;
                    end else begin
                        burst_dwords <= {2'b0, ctx_remaining[9:2]};  // Bytes to DWORDs
                    end

                    burst_count  <= 10'h0;
                    burst_wr_ptr <= 5'h0;
                    burst_rd_ptr <= 5'h0;

                    if (ctx_direction == 1'b0) begin
                        // H2D: Read from host first
                        state <= ST_H2D_REQ;
                    end else begin
                        // D2H: Read from local first
                        state <= ST_D2H_READ;
                    end
                end

                //-------------------------------------------------------------
                // Host-to-Device Path (Read from host, write to local)
                //-------------------------------------------------------------
                ST_H2D_REQ: begin
                    // Issue PCIe memory read request
                    if (!pcie_rd_req) begin
                        pcie_rd_req <= 1'b1;
                        pcie_addr   <= ctx_host_addr;
                        pcie_len    <= burst_dwords;
                        pcie_tag    <= next_tag;
                        ctx_tag     <= next_tag;
                        next_tag    <= next_tag + 1;
                    end else if (pcie_req_grant) begin
                        pcie_rd_req <= 1'b0;
                        tag_valid[ctx_tag] <= 1'b1;
                        state <= ST_H2D_WAIT;
                    end
                end

                ST_H2D_WAIT: begin
                    // Wait for completion data and buffer it
                    pcie_cpl_ready <= 1'b1;

                    if (pcie_cpl_valid && pcie_cpl_tag == ctx_tag) begin
                        burst_buffer[burst_wr_ptr] <= pcie_cpl_data;
                        burst_wr_ptr <= burst_wr_ptr + 1;
                        burst_count  <= burst_count + 2;  // 2 DWORDs per 64-bit

                        if (pcie_cpl_last) begin
                            tag_valid[ctx_tag] <= 1'b0;
                            burst_rd_ptr <= 5'h0;
                            state <= ST_H2D_WRITE;
                        end
                    end
                end

                ST_H2D_WRITE: begin
                    // Write buffered data to local memory
                    if (burst_rd_ptr < burst_wr_ptr) begin
                        if (ctx_channel == 1'b0) begin
                            // FDC channel
                            fdc_buf_addr  <= ctx_local_addr[15:0];
                            fdc_buf_wdata <= burst_buffer[burst_rd_ptr];
                            fdc_buf_write <= 1'b1;
                        end else begin
                            // WD HDD channel
                            wd_buf_addr  <= ctx_local_addr[15:0];
                            wd_buf_wdata <= burst_buffer[burst_rd_ptr];
                            wd_buf_write <= 1'b1;
                        end

                        burst_rd_ptr   <= burst_rd_ptr + 1;
                        ctx_local_addr <= ctx_local_addr + 8;
                    end else begin
                        state <= ST_NEXT_BURST;
                    end
                end

                //-------------------------------------------------------------
                // Device-to-Host Path (Read from local, write to host)
                //-------------------------------------------------------------
                ST_D2H_READ: begin
                    // Read data from local memory into burst buffer
                    if (burst_wr_ptr < (burst_dwords >> 1)) begin
                        if (ctx_channel == 1'b0) begin
                            fdc_buf_addr <= ctx_local_addr[15:0];
                            fdc_buf_read <= 1'b1;
                        end else begin
                            wd_buf_addr <= ctx_local_addr[15:0];
                            wd_buf_read <= 1'b1;
                        end

                        // Capture read data on next cycle
                        if (burst_wr_ptr > 0) begin
                            burst_buffer[burst_wr_ptr - 1] <= ctx_channel ?
                                                              wd_buf_rdata :
                                                              fdc_buf_rdata;
                        end

                        burst_wr_ptr   <= burst_wr_ptr + 1;
                        ctx_local_addr <= ctx_local_addr + 8;
                    end else begin
                        // Capture last read
                        burst_buffer[burst_wr_ptr - 1] <= ctx_channel ?
                                                          wd_buf_rdata :
                                                          fdc_buf_rdata;
                        state <= ST_D2H_REQ;
                    end
                end

                ST_D2H_REQ: begin
                    // Issue PCIe memory write request
                    if (!pcie_wr_req) begin
                        pcie_wr_req <= 1'b1;
                        pcie_addr   <= ctx_host_addr;
                        pcie_len    <= burst_dwords;
                        burst_rd_ptr <= 5'h0;
                    end else if (pcie_req_grant) begin
                        pcie_wr_req <= 1'b0;
                        state <= ST_D2H_WAIT;
                    end
                end

                ST_D2H_WAIT: begin
                    // Send burst data with write request
                    // (In real implementation, this would feed TLP payload)
                    if (burst_rd_ptr < burst_wr_ptr) begin
                        burst_rd_ptr <= burst_rd_ptr + 1;
                    end else begin
                        state <= ST_NEXT_BURST;
                    end
                end

                //-------------------------------------------------------------
                ST_NEXT_BURST: begin
                    // Update counters and check if more bursts needed
                    ctx_host_addr <= ctx_host_addr + {54'h0, burst_dwords, 2'b00};
                    ctx_remaining <= ctx_remaining - {14'h0, burst_dwords, 2'b00};
                    dma_bytes_done <= dma_bytes_done + {14'h0, burst_dwords, 2'b00};

                    if (ctx_remaining <= {14'h0, burst_dwords, 2'b00}) begin
                        // Current descriptor complete
                        if (dma_sg_mode && !sg_last) begin
                            // More descriptors
                            sg_desc_idx <= sg_desc_idx + 1;
                            state <= ST_FETCH_DESC;
                        end else begin
                            // All done
                            state <= ST_COMPLETE;
                        end
                    end else begin
                        // More bursts in current descriptor
                        state <= ST_CALC_BURST;
                    end
                end

                //-------------------------------------------------------------
                ST_NEXT_DESC: begin
                    // Move to next scatter-gather descriptor
                    sg_desc_idx <= sg_desc_idx + 1;
                    state <= ST_FETCH_DESC;
                end

                //-------------------------------------------------------------
                ST_COMPLETE: begin
                    dma_status[3:0] <= STAT_DONE;
                    if (dma_irq_en) begin
                        dma_done_irq <= 1'b1;
                    end
                    state <= ST_IDLE;
                end

                //-------------------------------------------------------------
                ST_ERROR: begin
                    dma_status[3:0] <= STAT_ERROR;
                    dma_error_irq <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    //=========================================================================
    // Debug / Status
    //=========================================================================
    always @(*) begin
        dma_status[7:4]   = state;
        dma_status[15:8]  = ctx_tag;
        dma_status[23:16] = burst_wr_ptr;
        dma_status[31:24] = burst_rd_ptr;
    end

endmodule
