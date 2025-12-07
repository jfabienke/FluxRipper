// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// signal_tap.v - FluxRipper Signal Tap Debug Capture
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 21:45
//
// Description:
//   Runtime signal capture for debugging via JTAG.
//   Captures selected probe signals into a circular buffer
//   when trigger conditions are met.
//
// Register Map (active addresses within 0x4003_0000 - 0x4003_00FF):
//   0x00: ID         - Module ID (RO)
//   0x04: STATUS     - Status register (RO)
//   0x08: CONTROL    - Control register (RW)
//   0x0C: TRIGGER    - Trigger value (RW)
//   0x10: TRIG_MASK  - Trigger mask (RW)
//   0x14: PROBE_SEL  - Probe selection (RW)
//   0x18: BUF_ADDR   - Buffer read address (RW)
//   0x1C: BUF_DATA   - Buffer read data (RO)
//   0x20: DEPTH      - Capture depth (RW)
//   0x24: POSITION   - Trigger position in buffer (RO)
//
//-----------------------------------------------------------------------------

module signal_tap #(
    parameter BUFFER_DEPTH = 256,
    parameter PROBE_WIDTH = 32
)(
    input         clk,
    input         rst_n,

    // Bus slave interface
    input  [7:0]  addr,
    input  [31:0] wdata,
    input         read,
    input         write,
    output reg [31:0] rdata,
    output        ready,

    // Probe inputs
    input  [PROBE_WIDTH-1:0] probes
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam [7:0]
        REG_ID        = 8'h00,
        REG_STATUS    = 8'h04,
        REG_CONTROL   = 8'h08,
        REG_TRIGGER   = 8'h0C,
        REG_TRIG_MASK = 8'h10,
        REG_PROBE_SEL = 8'h14,
        REG_BUF_ADDR  = 8'h18,
        REG_BUF_DATA  = 8'h1C,
        REG_DEPTH     = 8'h20,
        REG_POSITION  = 8'h24;

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [31:0] control_reg;
    reg [31:0] trigger_val;
    reg [31:0] trigger_mask;
    reg [31:0] probe_sel;
    reg [31:0] buf_addr;
    reg [31:0] capture_depth;

    // State machine
    reg [1:0] state;
    localparam [1:0]
        ST_IDLE     = 2'b00,
        ST_ARMED    = 2'b01,
        ST_CAPTURING = 2'b10,
        ST_DONE     = 2'b11;

    // Capture buffer
    reg [PROBE_WIDTH-1:0] buffer [0:BUFFER_DEPTH-1];
    reg [$clog2(BUFFER_DEPTH)-1:0] wr_ptr;
    reg [$clog2(BUFFER_DEPTH)-1:0] trigger_pos;
    reg [31:0] samples_after_trig;
    reg triggered;

    //=========================================================================
    // Bus Interface
    //=========================================================================
    assign ready = 1'b1;

    //=========================================================================
    // Register Read
    //=========================================================================
    always @(*) begin
        case (addr)
            REG_ID:        rdata = 32'h51670001;  // SigTap v1
            REG_STATUS:    rdata = {28'b0, triggered, (state == ST_DONE),
                                    (state == ST_CAPTURING), (state == ST_ARMED)};
            REG_CONTROL:   rdata = control_reg;
            REG_TRIGGER:   rdata = trigger_val;
            REG_TRIG_MASK: rdata = trigger_mask;
            REG_PROBE_SEL: rdata = probe_sel;
            REG_BUF_ADDR:  rdata = buf_addr;
            REG_BUF_DATA:  rdata = buffer[buf_addr[$clog2(BUFFER_DEPTH)-1:0]];
            REG_DEPTH:     rdata = capture_depth;
            REG_POSITION:  rdata = {24'b0, trigger_pos};
            default:       rdata = 32'h0;
        endcase
    end

    //=========================================================================
    // Register Write
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg <= 0;
            trigger_val <= 0;
            trigger_mask <= 32'hFFFFFFFF;
            probe_sel <= 0;
            buf_addr <= 0;
            capture_depth <= BUFFER_DEPTH;
        end else if (write) begin
            case (addr)
                REG_CONTROL:   control_reg <= wdata;
                REG_TRIGGER:   trigger_val <= wdata;
                REG_TRIG_MASK: trigger_mask <= wdata;
                REG_PROBE_SEL: probe_sel <= wdata;
                REG_BUF_ADDR:  buf_addr <= wdata;
                REG_DEPTH:     capture_depth <= (wdata > BUFFER_DEPTH) ?
                                                BUFFER_DEPTH : wdata;
            endcase
        end
    end

    //=========================================================================
    // Capture State Machine
    //=========================================================================
    wire trigger_match = ((probes & trigger_mask) == (trigger_val & trigger_mask));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            wr_ptr <= 0;
            trigger_pos <= 0;
            samples_after_trig <= 0;
            triggered <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (control_reg[0]) begin  // ARM bit
                        state <= ST_ARMED;
                        wr_ptr <= 0;
                        triggered <= 0;
                        samples_after_trig <= 0;
                    end
                end

                ST_ARMED: begin
                    // Continuous capture while waiting for trigger
                    buffer[wr_ptr] <= probes;
                    wr_ptr <= wr_ptr + 1;

                    if (trigger_match || control_reg[1]) begin  // Trigger or force
                        state <= ST_CAPTURING;
                        trigger_pos <= wr_ptr;
                        triggered <= 1;
                        samples_after_trig <= 0;
                    end

                    // Allow abort
                    if (!control_reg[0])
                        state <= ST_IDLE;
                end

                ST_CAPTURING: begin
                    // Continue capturing after trigger
                    buffer[wr_ptr] <= probes;
                    wr_ptr <= wr_ptr + 1;
                    samples_after_trig <= samples_after_trig + 1;

                    // Stop after capturing half buffer after trigger
                    if (samples_after_trig >= (capture_depth >> 1)) begin
                        state <= ST_DONE;
                        control_reg[0] <= 0;  // Clear ARM bit
                    end
                end

                ST_DONE: begin
                    // Wait for software to read and re-arm
                    if (control_reg[0])
                        state <= ST_ARMED;
                end
            endcase
        end
    end

    //=========================================================================
    // Initialize buffer for simulation
    //=========================================================================
    integer i;
    initial begin
        for (i = 0; i < BUFFER_DEPTH; i = i + 1)
            buffer[i] = 0;
    end

endmodule
