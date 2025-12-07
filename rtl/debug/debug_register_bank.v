// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// debug_register_bank.v - Debug Configuration and Status Registers
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 15:10
//
// Description:
//   Central register bank for debug configuration and status readback.
//   Accessible via both JTAG and CDC console. Provides unified interface
//   for all debug features.
//
// Register Map (32-bit aligned):
//   0x00: CTRL      - Control register
//   0x04: STATUS    - Status register (read-only)
//   0x08: CAPS_LO   - Capabilities low (read-only)
//   0x0C: CAPS_HI   - Capabilities high (read-only)
//   0x10: MEM_ADDR  - Memory access address
//   0x14: MEM_DATA  - Memory access data
//   0x18: MEM_CTRL  - Memory access control
//   0x1C: MEM_STAT  - Memory access status (read-only)
//   0x20: TAP_SEL   - Signal tap group select
//   0x24: TAP_DATA  - Signal tap data (read-only)
//   0x28: TAP_TRIG_MASK  - Trigger mask
//   0x2C: TAP_TRIG_VAL   - Trigger value
//   0x30: TRACE_CTRL     - Trace control
//   0x34: TRACE_STAT     - Trace status (read-only)
//   0x38: TRACE_ADDR     - Trace read address
//   0x3C: TRACE_DATA_LO  - Trace data low (read-only)
//   0x40: TRACE_DATA_HI  - Trace data high (read-only)
//   0x44: CPU_CTRL       - CPU control
//   0x48: CPU_STAT       - CPU status (read-only)
//   0x4C: CPU_PC         - CPU program counter (read-only)
//   0x50: CPU_REG_ADDR   - CPU register address
//   0x54: CPU_REG_DATA   - CPU register data (read-only)
//   0x58: CPU_BP_ADDR    - Breakpoint address
//   0x5C: CPU_BP_CTRL    - Breakpoint control
//   0x60: ERROR          - Error register
//   0x64: UPTIME_LO      - Uptime low (read-only)
//   0x68: UPTIME_HI      - Uptime high (read-only)
//   0x6C: SCRATCH        - Scratch register (for testing)
//   0x70: IDCODE         - JTAG IDCODE (read-only)
//   0x74: LAYER          - Current bring-up layer (read-only)
//
//-----------------------------------------------------------------------------

module debug_register_bank #(
    parameter ADDR_WIDTH  = 8,
    parameter CLK_FREQ_HZ = 100_000_000
)(
    input                   clk,
    input                   rst_n,

    //-------------------------------------------------------------------------
    // Register Interface
    //-------------------------------------------------------------------------
    input  [ADDR_WIDTH-1:0] reg_addr,
    input  [31:0]           reg_wdata,
    output reg [31:0]       reg_rdata,
    input                   reg_we,
    input                   reg_re,
    output                  reg_ready,

    //-------------------------------------------------------------------------
    // Memory Access Interface
    //-------------------------------------------------------------------------
    input  [31:0]           mem_read_data,
    input                   mem_read_valid,
    input                   mem_write_done,
    input                   mem_error,

    //-------------------------------------------------------------------------
    // Signal Tap Interface
    //-------------------------------------------------------------------------
    input  [127:0]          probe_signals,
    input  [7:0]            probe_group_sel,

    //-------------------------------------------------------------------------
    // CPU Debug Interface
    //-------------------------------------------------------------------------
    input                   cpu_halted,
    input                   cpu_running,
    input  [31:0]           cpu_pc,
    input  [31:0]           cpu_reg_data,

    //-------------------------------------------------------------------------
    // Trace Interface
    //-------------------------------------------------------------------------
    input  [11:0]           trace_count,
    input                   trace_wrapped,
    input                   trace_triggered,

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output [3:0]            current_layer,
    output [31:0]           last_error
);

    //=========================================================================
    // Register Address Decode
    //=========================================================================

    localparam
        REG_CTRL          = 8'h00,
        REG_STATUS        = 8'h04,
        REG_CAPS_LO       = 8'h08,
        REG_CAPS_HI       = 8'h0C,
        REG_MEM_ADDR      = 8'h10,
        REG_MEM_DATA      = 8'h14,
        REG_MEM_CTRL      = 8'h18,
        REG_MEM_STAT      = 8'h1C,
        REG_TAP_SEL       = 8'h20,
        REG_TAP_DATA      = 8'h24,
        REG_TAP_TRIG_MASK = 8'h28,
        REG_TAP_TRIG_VAL  = 8'h2C,
        REG_TRACE_CTRL    = 8'h30,
        REG_TRACE_STAT    = 8'h34,
        REG_TRACE_ADDR    = 8'h38,
        REG_TRACE_DATA_LO = 8'h3C,
        REG_TRACE_DATA_HI = 8'h40,
        REG_CPU_CTRL      = 8'h44,
        REG_CPU_STAT      = 8'h48,
        REG_CPU_PC        = 8'h4C,
        REG_CPU_REG_ADDR  = 8'h50,
        REG_CPU_REG_DATA  = 8'h54,
        REG_CPU_BP_ADDR   = 8'h58,
        REG_CPU_BP_CTRL   = 8'h5C,
        REG_ERROR         = 8'h60,
        REG_UPTIME_LO     = 8'h64,
        REG_UPTIME_HI     = 8'h68,
        REG_SCRATCH       = 8'h6C,
        REG_IDCODE        = 8'h70,
        REG_LAYER         = 8'h74;

    //=========================================================================
    // Registers
    //=========================================================================

    reg [31:0] ctrl_reg;
    reg [31:0] mem_addr_reg;
    reg [31:0] mem_data_reg;
    reg [31:0] mem_ctrl_reg;
    reg [31:0] tap_sel_reg;
    reg [31:0] tap_trig_mask_reg;
    reg [31:0] tap_trig_val_reg;
    reg [31:0] trace_ctrl_reg;
    reg [31:0] trace_addr_reg;
    reg [31:0] cpu_ctrl_reg;
    reg [31:0] cpu_reg_addr_reg;
    reg [31:0] cpu_bp_addr_reg;
    reg [31:0] cpu_bp_ctrl_reg;
    reg [31:0] error_reg;
    reg [31:0] scratch_reg;

    //=========================================================================
    // Uptime Counter
    //=========================================================================

    reg [63:0] uptime_cnt;
    reg [31:0] second_divider;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uptime_cnt <= 64'd0;
            second_divider <= 32'd0;
        end else begin
            if (second_divider >= CLK_FREQ_HZ - 1) begin
                second_divider <= 32'd0;
                uptime_cnt <= uptime_cnt + 1;
            end else begin
                second_divider <= second_divider + 1;
            end
        end
    end

    //=========================================================================
    // Bring-up Layer Detection
    //=========================================================================

    reg [3:0] layer_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            layer_reg <= 4'd0;
        end else begin
            // Layer detection based on system state
            // Layer 0: Reset complete
            // Layer 1: Memory accessible (scratch register works)
            // Layer 2: PLLs locked
            // Layer 3: USB PHY responding
            // Layer 4: USB enumerated
            // Layer 5: CDC console active
            // etc.
            if (scratch_reg == 32'hDEADBEEF) begin
                layer_reg <= 4'd1;  // Memory works
            end
            // Additional layer detection would check other subsystems
        end
    end

    //=========================================================================
    // Signal Tap Data Selection
    //=========================================================================

    reg [31:0] tap_data;

    always @(*) begin
        case (tap_sel_reg[1:0])
            2'd0: tap_data = probe_signals[31:0];
            2'd1: tap_data = probe_signals[63:32];
            2'd2: tap_data = probe_signals[95:64];
            2'd3: tap_data = probe_signals[127:96];
        endcase
    end

    //=========================================================================
    // Register Write Logic
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg         <= 32'd0;
            mem_addr_reg     <= 32'd0;
            mem_data_reg     <= 32'd0;
            mem_ctrl_reg     <= 32'd0;
            tap_sel_reg      <= 32'd0;
            tap_trig_mask_reg <= 32'd0;
            tap_trig_val_reg <= 32'd0;
            trace_ctrl_reg   <= 32'd0;
            trace_addr_reg   <= 32'd0;
            cpu_ctrl_reg     <= 32'd0;
            cpu_reg_addr_reg <= 32'd0;
            cpu_bp_addr_reg  <= 32'd0;
            cpu_bp_ctrl_reg  <= 32'd0;
            error_reg        <= 32'd0;
            scratch_reg      <= 32'd0;
        end else if (reg_we) begin
            case (reg_addr)
                REG_CTRL:          ctrl_reg <= reg_wdata;
                REG_MEM_ADDR:      mem_addr_reg <= reg_wdata;
                REG_MEM_DATA:      mem_data_reg <= reg_wdata;
                REG_MEM_CTRL:      mem_ctrl_reg <= reg_wdata;
                REG_TAP_SEL:       tap_sel_reg <= reg_wdata;
                REG_TAP_TRIG_MASK: tap_trig_mask_reg <= reg_wdata;
                REG_TAP_TRIG_VAL:  tap_trig_val_reg <= reg_wdata;
                REG_TRACE_CTRL:    trace_ctrl_reg <= reg_wdata;
                REG_TRACE_ADDR:    trace_addr_reg <= reg_wdata;
                REG_CPU_CTRL:      cpu_ctrl_reg <= reg_wdata;
                REG_CPU_REG_ADDR:  cpu_reg_addr_reg <= reg_wdata;
                REG_CPU_BP_ADDR:   cpu_bp_addr_reg <= reg_wdata;
                REG_CPU_BP_CTRL:   cpu_bp_ctrl_reg <= reg_wdata;
                REG_ERROR:         error_reg <= reg_wdata;
                REG_SCRATCH:       scratch_reg <= reg_wdata;
            endcase
        end

        // Update error register on memory errors
        if (mem_error) begin
            error_reg[0] <= 1'b1;
        end
    end

    //=========================================================================
    // Register Read Logic
    //=========================================================================

    always @(*) begin
        case (reg_addr)
            REG_CTRL:          reg_rdata = ctrl_reg;
            REG_STATUS:        reg_rdata = {24'd0, cpu_running, cpu_halted, trace_triggered, trace_wrapped, layer_reg};
            REG_CAPS_LO:       reg_rdata = 32'h04800C80;  // 4 groups, 128-bit width, 4096 trace, 64-bit trace
            REG_CAPS_HI:       reg_rdata = 32'h01200101;  // 1 BP, 32-bit addr, features, version
            REG_MEM_ADDR:      reg_rdata = mem_addr_reg;
            REG_MEM_DATA:      reg_rdata = mem_read_valid ? mem_read_data : mem_data_reg;
            REG_MEM_CTRL:      reg_rdata = mem_ctrl_reg;
            REG_MEM_STAT:      reg_rdata = {29'd0, mem_error, mem_write_done, mem_read_valid};
            REG_TAP_SEL:       reg_rdata = tap_sel_reg;
            REG_TAP_DATA:      reg_rdata = tap_data;
            REG_TAP_TRIG_MASK: reg_rdata = tap_trig_mask_reg;
            REG_TAP_TRIG_VAL:  reg_rdata = tap_trig_val_reg;
            REG_TRACE_CTRL:    reg_rdata = trace_ctrl_reg;
            REG_TRACE_STAT:    reg_rdata = {16'd0, trace_wrapped, trace_triggered, 2'd0, trace_count};
            REG_TRACE_ADDR:    reg_rdata = trace_addr_reg;
            REG_TRACE_DATA_LO: reg_rdata = 32'd0;  // Would come from trace buffer
            REG_TRACE_DATA_HI: reg_rdata = 32'd0;
            REG_CPU_CTRL:      reg_rdata = cpu_ctrl_reg;
            REG_CPU_STAT:      reg_rdata = {30'd0, cpu_running, cpu_halted};
            REG_CPU_PC:        reg_rdata = cpu_pc;
            REG_CPU_REG_ADDR:  reg_rdata = cpu_reg_addr_reg;
            REG_CPU_REG_DATA:  reg_rdata = cpu_reg_data;
            REG_CPU_BP_ADDR:   reg_rdata = cpu_bp_addr_reg;
            REG_CPU_BP_CTRL:   reg_rdata = cpu_bp_ctrl_reg;
            REG_ERROR:         reg_rdata = error_reg;
            REG_UPTIME_LO:     reg_rdata = uptime_cnt[31:0];
            REG_UPTIME_HI:     reg_rdata = uptime_cnt[63:32];
            REG_SCRATCH:       reg_rdata = scratch_reg;
            REG_IDCODE:        reg_rdata = 32'hFB010001;
            REG_LAYER:         reg_rdata = {28'd0, layer_reg};
            default:           reg_rdata = 32'hDEADDEAD;
        endcase
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign reg_ready     = 1'b1;  // Always ready (combinational read)
    assign current_layer = layer_reg;
    assign last_error    = error_reg;

endmodule
