// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// trace_buffer.v - Event Trace Capture Buffer
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 15:05
//
// Description:
//   Circular trace buffer for capturing timestamped events. Essential for
//   debugging timing-sensitive issues and understanding system behavior.
//   Can be triggered on specific conditions and captures pre/post-trigger data.
//
// Trace Entry Format (64 bits):
//   [63:48] - Timestamp (16 bits, wraps at 65536 cycles)
//   [47:40] - Event type (8 bits)
//   [39:32] - Event source (8 bits)
//   [31:0]  - Event data (32 bits)
//
// Event Types:
//   0x00 - Idle (no event)
//   0x01 - State change
//   0x02 - Register write
//   0x03 - Register read
//   0x04 - Interrupt
//   0x05 - Error
//   0x06 - USB packet
//   0x07 - FDC command
//   0x08 - HDD command
//   0x09 - Memory access
//   0x0A - DMA transfer
//   0x0B - PLL event
//   0x0C - Power event
//   0x0D - User-defined 1
//   0x0E - User-defined 2
//   0x0F - Trigger hit
//
// Event Sources:
//   0x00 - System
//   0x01 - USB core
//   0x02 - FDC 0
//   0x03 - FDC 1
//   0x04 - HDD 0
//   0x05 - HDD 1
//   0x06 - Power
//   0x07 - Clock
//   0x08 - CPU
//   0x09 - Debug
//
//-----------------------------------------------------------------------------

module trace_buffer #(
    parameter DEPTH_LOG2 = 12,           // 4096 entries
    parameter WIDTH      = 64            // 64-bit trace words
)(
    input                       clk,
    input                       rst_n,

    //-------------------------------------------------------------------------
    // Control
    //-------------------------------------------------------------------------
    input                       enable,          // Enable trace capture
    input                       clear,           // Clear buffer
    input  [1:0]                mode,            // 0=continuous, 1=pre-trigger, 2=post-trigger
    input  [DEPTH_LOG2-1:0]     pre_trigger_cnt, // Samples to keep before trigger

    //-------------------------------------------------------------------------
    // Data Input (directly from trace sources)
    //-------------------------------------------------------------------------
    input  [WIDTH-1:0]          data_in,
    input                       write,           // Write strobe

    //-------------------------------------------------------------------------
    // Trigger
    //-------------------------------------------------------------------------
    input                       trigger_in,      // External trigger input
    input  [31:0]               trigger_data,    // Data that caused trigger
    input  [7:0]                trigger_type,    // Type filter (match any bit)
    input  [7:0]                trigger_source,  // Source filter (match any bit)

    //-------------------------------------------------------------------------
    // Readout Interface
    //-------------------------------------------------------------------------
    input  [DEPTH_LOG2-1:0]     read_addr,       // Read address (relative to start)
    output [WIDTH-1:0]          data_out,        // Read data
    output [DEPTH_LOG2-1:0]     count,           // Number of entries captured
    output [DEPTH_LOG2-1:0]     trigger_pos,     // Position of trigger in buffer
    output                      wrapped,         // Buffer has wrapped
    output                      triggered,       // Trigger has occurred
    output                      full             // Buffer is full (post-trigger mode)
);

    //=========================================================================
    // Parameters
    //=========================================================================

    localparam DEPTH = 1 << DEPTH_LOG2;

    //=========================================================================
    // Buffer Memory
    //=========================================================================

    reg [WIDTH-1:0] buffer [0:DEPTH-1];

    //=========================================================================
    // Pointers and Status
    //=========================================================================

    reg [DEPTH_LOG2-1:0] write_ptr;
    reg [DEPTH_LOG2-1:0] count_reg;
    reg [DEPTH_LOG2-1:0] trigger_pos_reg;
    reg [DEPTH_LOG2-1:0] post_trigger_cnt;
    reg                  wrapped_reg;
    reg                  triggered_reg;
    reg                  full_reg;
    reg [15:0]           timestamp;

    //=========================================================================
    // Timestamp Counter
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timestamp <= 16'd0;
        end else if (clear) begin
            timestamp <= 16'd0;
        end else if (enable) begin
            timestamp <= timestamp + 1;
        end
    end

    //=========================================================================
    // Trigger Detection
    //=========================================================================

    wire [7:0] event_type   = data_in[47:40];
    wire [7:0] event_source = data_in[39:32];

    // Type and source filtering
    wire type_match   = (trigger_type == 8'h00) || ((event_type & trigger_type) != 8'h00);
    wire source_match = (trigger_source == 8'h00) || ((event_source & trigger_source) != 8'h00);

    wire internal_trigger = trigger_in || (write && type_match && source_match);

    //=========================================================================
    // Write Logic
    //=========================================================================

    wire do_write = enable && write && !full_reg;

    // Add timestamp to incoming data
    wire [WIDTH-1:0] timestamped_data = {timestamp, data_in[47:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr       <= {DEPTH_LOG2{1'b0}};
            count_reg       <= {DEPTH_LOG2{1'b0}};
            trigger_pos_reg <= {DEPTH_LOG2{1'b0}};
            post_trigger_cnt <= {DEPTH_LOG2{1'b0}};
            wrapped_reg     <= 1'b0;
            triggered_reg   <= 1'b0;
            full_reg        <= 1'b0;
        end else if (clear) begin
            write_ptr       <= {DEPTH_LOG2{1'b0}};
            count_reg       <= {DEPTH_LOG2{1'b0}};
            trigger_pos_reg <= {DEPTH_LOG2{1'b0}};
            post_trigger_cnt <= {DEPTH_LOG2{1'b0}};
            wrapped_reg     <= 1'b0;
            triggered_reg   <= 1'b0;
            full_reg        <= 1'b0;
        end else begin

            // Handle trigger
            if (internal_trigger && !triggered_reg) begin
                triggered_reg <= 1'b1;
                trigger_pos_reg <= write_ptr;
                post_trigger_cnt <= {DEPTH_LOG2{1'b0}};
            end

            // Write data
            if (do_write) begin
                buffer[write_ptr] <= timestamped_data;

                // Update write pointer
                write_ptr <= write_ptr + 1;

                // Update count
                if (!wrapped_reg) begin
                    count_reg <= count_reg + 1;
                end

                // Check for wrap
                if (write_ptr == {DEPTH_LOG2{1'b1}}) begin
                    wrapped_reg <= 1'b1;
                end

                // Post-trigger counting
                if (triggered_reg && mode == 2'b10) begin
                    post_trigger_cnt <= post_trigger_cnt + 1;

                    // Check if post-trigger capture complete
                    if (post_trigger_cnt >= (DEPTH - pre_trigger_cnt - 1)) begin
                        full_reg <= 1'b1;
                    end
                end
            end
        end
    end

    //=========================================================================
    // Read Logic
    //=========================================================================

    // Calculate actual read address (handle wrap-around)
    wire [DEPTH_LOG2-1:0] actual_read_addr;

    generate
        if (DEPTH_LOG2 > 1) begin : gen_read_addr
            assign actual_read_addr = wrapped_reg ?
                (write_ptr + read_addr) :
                read_addr;
        end else begin : gen_read_addr_simple
            assign actual_read_addr = read_addr;
        end
    endgenerate

    // Registered read output
    reg [WIDTH-1:0] data_out_reg;

    always @(posedge clk) begin
        data_out_reg <= buffer[actual_read_addr];
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign data_out    = data_out_reg;
    assign count       = wrapped_reg ? {DEPTH_LOG2{1'b1}} : count_reg;
    assign trigger_pos = trigger_pos_reg;
    assign wrapped     = wrapped_reg;
    assign triggered   = triggered_reg;
    assign full        = full_reg;

endmodule


//=============================================================================
// Trace Event Formatting (for debug console output)
//=============================================================================
//
// When dumping trace, format as:
//
//   Time(us)  Type         Source      Data
//   --------  -----------  ----------  --------------------------------
//   0000.016  STATE_CHG    USB_CORE    old=0x00 new=0x01
//   0000.032  USB_PACKET   USB_CORE    SETUP EP0 len=8
//   0000.048  REG_WRITE    USB_CORE    addr=0x04 data=0x00000001
//   0000.064  STATE_CHG    USB_CORE    old=0x01 new=0x02
//   0000.080  INTERRUPT    SYSTEM      irq=0x02 (USB)
//   ...
//
// Timestamp conversion (assuming 100 MHz clock):
//   raw_timestamp * 10 = nanoseconds
//   raw_timestamp / 100 = microseconds
//
//=============================================================================
