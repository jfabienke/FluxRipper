// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// disk_controller.v - FluxRipper Disk Controller
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 21:35
//
// Description:
//   Floppy disk flux capture controller. Samples flux transitions from
//   the drive and stores timing data in memory via DMA.
//
// Register Map (active addresses within 0x4001_0000 - 0x4001_00FF):
//   0x00: STATUS    - Status register (RO)
//   0x04: CONTROL   - Control register (RW)
//   0x08: DMA_ADDR  - DMA base address (RW)
//   0x0C: DMA_LEN   - DMA transfer length (RW)
//   0x10: INDEX_CNT - Index pulse counter (RO)
//   0x14: RPM       - Measured RPM (RO)
//   0x18: FLUX_CNT  - Captured flux count (RO)
//
//-----------------------------------------------------------------------------

module disk_controller (
    input         clk,
    input         rst_n,

    // Bus slave interface
    input  [7:0]  addr,
    input  [31:0] wdata,
    input         read,
    input         write,
    output reg [31:0] rdata,
    output        ready,

    // DMA master interface
    output reg [31:0] dma_addr,
    output reg [31:0] dma_wdata,
    output reg        dma_write,
    input             dma_ready,

    // Disk interface
    input         flux_in,       // Flux transition input
    input         index_in,      // Index pulse input
    output reg    motor_on,      // Motor enable
    output reg    head_sel,      // Head select (0=bottom, 1=top)
    output reg    dir,           // Step direction
    output reg    step           // Step pulse
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam [7:0]
        REG_STATUS    = 8'h00,
        REG_CONTROL   = 8'h04,
        REG_DMA_ADDR  = 8'h08,
        REG_DMA_LEN   = 8'h0C,
        REG_INDEX_CNT = 8'h10,
        REG_RPM       = 8'h14,
        REG_FLUX_CNT  = 8'h18;

    //=========================================================================
    // Control Register Bits
    //=========================================================================
    // [0]  = START    - Start capture
    // [1]  = STOP     - Stop capture (write 1 to stop)
    // [2]  = MOTOR    - Motor enable
    // [3]  = HEAD_SEL - Head select
    // [4]  = DIR      - Step direction
    // [5]  = STEP     - Step pulse (auto-clears)
    // [7:6] = MODE    - Capture mode (0=raw flux, 1=MFM, 2=GCR)

    //=========================================================================
    // Status Register Bits
    //=========================================================================
    // [0]  = READY    - Controller ready
    // [1]  = CAPTURING - Capture in progress
    // [2]  = DMA_BUSY - DMA transfer pending
    // [3]  = INDEX    - Index pulse detected (sticky, clear on read)
    // [4]  = OVERFLOW - Buffer overflow occurred
    // [7:5] = reserved

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [31:0] control_reg;
    reg [31:0] dma_base;
    reg [31:0] dma_len;
    reg [31:0] dma_offset;

    reg        capturing;
    reg        dma_busy;
    reg        index_sticky;
    reg        overflow;

    reg [31:0] index_counter;
    reg [31:0] flux_counter;
    reg [31:0] rpm_value;

    // Flux timing capture
    reg [31:0] flux_timer;
    reg        flux_prev;
    reg [31:0] flux_buffer [0:15];  // Small FIFO for simulation
    reg [3:0]  flux_wr_ptr;
    reg [3:0]  flux_rd_ptr;

    // RPM measurement
    reg [31:0] rpm_timer;
    reg [31:0] last_rpm_timer;
    reg        index_prev;

    //=========================================================================
    // Bus Interface - Always Ready
    //=========================================================================
    assign ready = 1'b1;

    //=========================================================================
    // Register Read
    //=========================================================================
    always @(*) begin
        case (addr)
            REG_STATUS: begin
                rdata = {24'b0,
                         3'b0,
                         overflow,
                         index_sticky,
                         dma_busy,
                         capturing,
                         1'b1};  // READY always 1
            end
            REG_CONTROL:   rdata = control_reg;
            REG_DMA_ADDR:  rdata = dma_base;
            REG_DMA_LEN:   rdata = dma_len;
            REG_INDEX_CNT: rdata = index_counter;
            REG_RPM:       rdata = rpm_value;
            REG_FLUX_CNT:  rdata = flux_counter;
            default:       rdata = 32'h0;
        endcase
    end

    //=========================================================================
    // Register Write
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg <= 0;
            dma_base <= 0;
            dma_len <= 0;
            motor_on <= 0;
            head_sel <= 0;
            dir <= 0;
            step <= 0;
        end else if (write) begin
            case (addr)
                REG_CONTROL: begin
                    control_reg <= wdata;
                    motor_on <= wdata[2];
                    head_sel <= wdata[3];
                    dir <= wdata[4];
                    step <= wdata[5];  // Will auto-clear
                end
                REG_DMA_ADDR: dma_base <= wdata;
                REG_DMA_LEN:  dma_len <= wdata;
            endcase
        end else begin
            // Auto-clear step pulse
            step <= 0;
        end
    end

    //=========================================================================
    // Clear Index Sticky on Status Read
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            index_sticky <= 0;
        else if (read && addr == REG_STATUS)
            index_sticky <= 0;
        else if (index_in && !index_prev)
            index_sticky <= 1;
    end

    //=========================================================================
    // Capture State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capturing <= 0;
            dma_offset <= 0;
            flux_counter <= 0;
            overflow <= 0;
            flux_wr_ptr <= 0;
            flux_rd_ptr <= 0;
        end else begin
            // Start capture
            if (control_reg[0] && !capturing) begin
                capturing <= 1;
                dma_offset <= 0;
                flux_counter <= 0;
                overflow <= 0;
                flux_wr_ptr <= 0;
                flux_rd_ptr <= 0;
            end

            // Stop capture
            if (control_reg[1] && capturing) begin
                capturing <= 0;
                control_reg[1] <= 0;  // Auto-clear stop bit
                control_reg[0] <= 0;  // Clear start bit
            end

            // Check for buffer overflow
            if (capturing && (flux_wr_ptr + 1 == flux_rd_ptr))
                overflow <= 1;
        end
    end

    //=========================================================================
    // Flux Timing Capture
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flux_timer <= 0;
            flux_prev <= 0;
        end else begin
            flux_prev <= flux_in;
            flux_timer <= flux_timer + 1;

            // Detect flux transition
            if (flux_in != flux_prev && capturing) begin
                // Store timing value in FIFO
                flux_buffer[flux_wr_ptr] <= flux_timer;
                flux_wr_ptr <= flux_wr_ptr + 1;
                flux_timer <= 0;
                flux_counter <= flux_counter + 1;
            end
        end
    end

    //=========================================================================
    // DMA Engine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_write <= 0;
            dma_addr <= 0;
            dma_wdata <= 0;
            dma_busy <= 0;
        end else begin
            dma_write <= 0;

            // Transfer data from FIFO to memory
            if (flux_rd_ptr != flux_wr_ptr && !dma_write && dma_offset < dma_len) begin
                dma_addr <= dma_base + dma_offset;
                dma_wdata <= flux_buffer[flux_rd_ptr];
                dma_write <= 1;
                flux_rd_ptr <= flux_rd_ptr + 1;
                dma_offset <= dma_offset + 4;
                dma_busy <= 1;
            end else if (dma_write && dma_ready) begin
                dma_busy <= 0;
            end
        end
    end

    //=========================================================================
    // Index Pulse Counter and RPM Measurement
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index_counter <= 0;
            index_prev <= 0;
            rpm_timer <= 0;
            last_rpm_timer <= 0;
            rpm_value <= 0;
        end else begin
            index_prev <= index_in;
            rpm_timer <= rpm_timer + 1;

            // Detect index pulse rising edge
            if (index_in && !index_prev) begin
                index_counter <= index_counter + 1;

                // Calculate RPM: clk_freq / timer_ticks * 60
                // For 50 MHz clock: RPM = 3_000_000_000 / timer_ticks
                // Simplified: rpm_value stores raw timer for software calculation
                last_rpm_timer <= rpm_timer;
                rpm_timer <= 0;

                // Approximate RPM for 50 MHz clock
                // 300 RPM = 200ms = 10M ticks, so RPM ≈ 3B / ticks
                if (rpm_timer > 0)
                    rpm_value <= 32'd3000000000 / rpm_timer;
            end
        end
    end

endmodule
