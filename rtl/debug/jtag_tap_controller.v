// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// jtag_tap_controller.v - IEEE 1149.1 JTAG TAP Controller
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 14:50
//
// Description:
//   Standard JTAG TAP state machine with Black Magic Probe compatible
//   instruction set. Supports both standard RISC-V debug (DTMCS/DMI)
//   and FluxRipper-specific debug instructions.
//
// TAP State Machine:
//   Standard IEEE 1149.1 16-state FSM with TMS-driven transitions.
//
// Instruction Set:
//   Standard:
//     0x01 - IDCODE    (32-bit device ID)
//     0x1F - BYPASS    (1-bit bypass)
//   RISC-V Debug:
//     0x10 - DTMCS     (Debug Transport Module Control/Status)
//     0x11 - DMI       (Debug Module Interface)
//   FluxRipper:
//     0x02 - MEM_READ  (Memory read access)
//     0x03 - MEM_WRITE (Memory write access)
//     0x04 - SIG_TAP   (Signal tap observation)
//     0x05 - TRACE_CTL (Trace buffer control)
//     0x06 - TRACE_DAT (Trace data readout)
//     0x07 - STATUS    (System status)
//     0x08 - CAPS      (Capabilities query)
//
//-----------------------------------------------------------------------------

module jtag_tap_controller #(
    parameter IDCODE     = 32'hFB010001,  // FluxRipper Debug v1
    parameter IR_LENGTH  = 5              // 5-bit instruction register
)(
    //-------------------------------------------------------------------------
    // JTAG Interface
    //-------------------------------------------------------------------------
    input                   tck,          // Test clock
    input                   tms,          // Test mode select
    input                   tdi,          // Test data in
    output reg              tdo,          // Test data out
    input                   trst_n,       // Test reset (active low, optional)

    //-------------------------------------------------------------------------
    // Instruction Register Interface
    //-------------------------------------------------------------------------
    output [IR_LENGTH-1:0]  ir_value,     // Current instruction
    output                  ir_capture,   // IR capture strobe
    output                  ir_shift,     // IR shift strobe
    output                  ir_update,    // IR update strobe

    //-------------------------------------------------------------------------
    // Data Register Interface
    //-------------------------------------------------------------------------
    input  [63:0]           dr_capture_data, // Data to capture into DR
    input                   dr_shift_in,     // Serial data input
    output                  dr_shift_out,    // Serial data output
    output                  dr_capture,      // DR capture strobe
    output                  dr_shift,        // DR shift strobe
    output                  dr_update,       // DR update strobe
    output [6:0]            dr_length        // Current DR length (bits, max 64)
);

    //=========================================================================
    // TAP State Machine States (IEEE 1149.1)
    //=========================================================================

    localparam [3:0]
        TEST_LOGIC_RESET = 4'h0,
        RUN_TEST_IDLE    = 4'h1,
        SELECT_DR_SCAN   = 4'h2,
        CAPTURE_DR       = 4'h3,
        SHIFT_DR         = 4'h4,
        EXIT1_DR         = 4'h5,
        PAUSE_DR         = 4'h6,
        EXIT2_DR         = 4'h7,
        UPDATE_DR        = 4'h8,
        SELECT_IR_SCAN   = 4'h9,
        CAPTURE_IR       = 4'hA,
        SHIFT_IR         = 4'hB,
        EXIT1_IR         = 4'hC,
        PAUSE_IR         = 4'hD,
        EXIT2_IR         = 4'hE,
        UPDATE_IR        = 4'hF;

    reg [3:0] state;
    reg [3:0] next_state;

    //=========================================================================
    // Instruction Codes
    //=========================================================================

    localparam [IR_LENGTH-1:0]
        IR_BYPASS    = 5'h1F,
        IR_IDCODE    = 5'h01,
        IR_DTMCS     = 5'h10,
        IR_DMI       = 5'h11,
        IR_MEM_READ  = 5'h02,
        IR_MEM_WRITE = 5'h03,
        IR_SIG_TAP   = 5'h04,
        IR_TRACE_CTL = 5'h05,
        IR_TRACE_DAT = 5'h06,
        IR_STATUS    = 5'h07,
        IR_CAPS      = 5'h08;

    //=========================================================================
    // Registers
    //=========================================================================

    reg [IR_LENGTH-1:0] ir_shift_reg;
    reg [IR_LENGTH-1:0] ir_hold_reg;
    reg [63:0]          dr_shift_reg;
    reg                 bypass_reg;

    //=========================================================================
    // TAP State Machine
    //=========================================================================

    // State register with optional async reset
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            state <= TEST_LOGIC_RESET;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic (standard IEEE 1149.1 transitions)
    always @(*) begin
        case (state)
            TEST_LOGIC_RESET: next_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   next_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       next_state = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         next_state = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         next_state = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         next_state = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         next_state = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   next_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       next_state = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         next_state = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         next_state = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         next_state = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         next_state = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default:          next_state = TEST_LOGIC_RESET;
        endcase
    end

    //=========================================================================
    // Instruction Register
    //=========================================================================

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift_reg <= {IR_LENGTH{1'b1}};  // All ones = BYPASS
            ir_hold_reg  <= IR_IDCODE;          // Default to IDCODE after reset
        end else begin
            case (state)
                TEST_LOGIC_RESET: begin
                    ir_hold_reg <= IR_IDCODE;
                end

                CAPTURE_IR: begin
                    // Capture fixed pattern (LSB=1 required by spec)
                    ir_shift_reg <= 5'b00001;
                end

                SHIFT_IR: begin
                    ir_shift_reg <= {tdi, ir_shift_reg[IR_LENGTH-1:1]};
                end

                UPDATE_IR: begin
                    ir_hold_reg <= ir_shift_reg;
                end
            endcase
        end
    end

    assign ir_value   = ir_hold_reg;
    assign ir_capture = (state == CAPTURE_IR);
    assign ir_shift   = (state == SHIFT_IR);
    assign ir_update  = (state == UPDATE_IR);

    //=========================================================================
    // Data Register Length Selection
    //=========================================================================

    reg [6:0] current_dr_length;

    always @(*) begin
        case (ir_hold_reg)
            IR_BYPASS:    current_dr_length = 7'd1;
            IR_IDCODE:    current_dr_length = 7'd32;
            IR_DTMCS:     current_dr_length = 7'd32;
            IR_DMI:       current_dr_length = 7'd41;  // addr(7) + data(32) + op(2)
            IR_MEM_READ:  current_dr_length = 7'd64;  // addr(32) + data(32)
            IR_MEM_WRITE: current_dr_length = 7'd64;  // addr(32) + data(32)
            IR_SIG_TAP:   current_dr_length = 7'd40;  // group(8) + signals(32)
            IR_TRACE_CTL: current_dr_length = 7'd32;  // control word
            IR_TRACE_DAT: current_dr_length = 7'd64;  // trace entry
            IR_STATUS:    current_dr_length = 7'd32;  // status word
            IR_CAPS:      current_dr_length = 7'd64;  // capabilities
            default:      current_dr_length = 7'd1;   // BYPASS
        endcase
    end

    assign dr_length = current_dr_length;

    //=========================================================================
    // Data Register
    //=========================================================================

    always @(posedge tck) begin
        case (state)
            CAPTURE_DR: begin
                case (ir_hold_reg)
                    IR_BYPASS: begin
                        bypass_reg <= 1'b0;
                    end

                    IR_IDCODE: begin
                        dr_shift_reg[31:0] <= IDCODE;
                    end

                    default: begin
                        // Capture external data
                        dr_shift_reg <= dr_capture_data;
                    end
                endcase
            end

            SHIFT_DR: begin
                if (ir_hold_reg == IR_BYPASS) begin
                    bypass_reg <= tdi;
                end else begin
                    // Shift right, MSB gets TDI
                    dr_shift_reg <= {tdi, dr_shift_reg[63:1]};
                end
            end
        endcase
    end

    assign dr_shift_out = (ir_hold_reg == IR_BYPASS) ? bypass_reg : dr_shift_reg[0];
    assign dr_capture   = (state == CAPTURE_DR);
    assign dr_shift     = (state == SHIFT_DR);
    assign dr_update    = (state == UPDATE_DR);

    //=========================================================================
    // TDO Output Multiplexing
    //=========================================================================

    always @(negedge tck) begin
        case (state)
            SHIFT_IR: begin
                tdo <= ir_shift_reg[0];
            end

            SHIFT_DR: begin
                tdo <= dr_shift_out;
            end

            default: begin
                tdo <= 1'b0;
            end
        endcase
    end

endmodule


//=============================================================================
// JTAG Instruction Usage Notes (for debugging scripts)
//=============================================================================
//
// IDCODE (0x01):
//   - Shift out 32 bits to get device IDCODE
//   - Expected: 0xFB010001 for FluxRipper Debug v1
//   - Format: [31:28]=version, [27:12]=part, [11:1]=manufacturer, [0]=1
//
// MEM_READ (0x02):
//   - Shift in 32-bit address (LSB first)
//   - Shift out 32-bit data from previous read + current address
//   - Pipeline: address in DR_UPDATE triggers read, result in next CAPTURE
//
// MEM_WRITE (0x03):
//   - Shift in 64 bits: address[31:0], data[31:0]
//   - Write executed on DR_UPDATE
//
// SIG_TAP (0x04):
//   - Shift in 8-bit group select
//   - Shift out 32-bit probe values for selected group
//
// STATUS (0x07):
//   - No input required
//   - Shift out 32-bit status:
//     [3:0]   = current_layer (bring-up progress)
//     [4]     = cpu_halted
//     [5]     = cpu_running
//     [6]     = trace_triggered
//     [7]     = trace_wrapped
//     [15:8]  = error_code
//     [31:16] = uptime_seconds[15:0]
//
// CAPS (0x08):
//   - No input required
//   - Shift out 64-bit capabilities:
//     [7:0]   = num_probe_groups
//     [15:8]  = probe_width
//     [23:16] = trace_depth_log2
//     [31:24] = trace_width
//     [39:32] = num_breakpoints
//     [47:40] = mem_addr_width
//     [55:48] = features (bit flags)
//     [63:56] = version
//
//=============================================================================
