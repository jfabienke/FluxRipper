// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// fluxripper_debug_top.v - FluxRipper Unified Debug Subsystem
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 14:45
//
// Description:
//   Comprehensive debug interface designed for iterative bring-up.
//   Supports both JTAG (via BSCANE2 tunnel or external pins) and
//   text commands via CDC debug console.
//
//   This is the PRIMARY debug interface for FluxRipper development.
//
// Features:
//   - Dual JTAG input: BSCANE2 (shared with config) or external pins
//   - Black Magic Probe compatible JTAG protocol
//   - Full memory map access (read/write any address)
//   - RTL signal observation (configurable probe points)
//   - Trace buffer with programmable triggers
//   - CPU debug (halt/step/run/breakpoints)
//   - Text-based command interface via CDC console
//   - Self-describing capability queries
//
// Debug Layers (bring-up order):
//   Layer 0: JTAG IDCODE - verify TAP chain works
//   Layer 1: Memory read - verify bus connectivity
//   Layer 2: Memory write - verify write path
//   Layer 3: GPIO observe - verify I/O connectivity
//   Layer 4: Clock check - verify PLLs locked
//   Layer 5: USB PHY - verify ULPI communication
//   Layer 6: USB enum - verify device enumeration
//   Layer 7: CDC console - text commands available
//   Layer 8: Full system - all features operational
//
//-----------------------------------------------------------------------------

module fluxripper_debug_top #(
    // JTAG Configuration
    parameter JTAG_IDCODE       = 32'hFB010001,  // FluxRipper Debug v1
    parameter USE_BSCANE2       = 1,             // Use Xilinx BSCANE2 tunnel
    parameter BSCANE2_USER      = 2,             // USER2 instruction

    // Memory Access
    parameter MEM_ADDR_WIDTH    = 32,
    parameter MEM_DATA_WIDTH    = 32,

    // Signal Tap
    parameter SIGNAL_TAP_WIDTH  = 128,           // Probe signals
    parameter SIGNAL_TAP_GROUPS = 4,             // Probe groups

    // Trace Buffer
    parameter TRACE_DEPTH_LOG2  = 12,            // 4096 entries
    parameter TRACE_WIDTH       = 64,            // 64-bit trace words

    // System
    parameter CLK_FREQ_HZ       = 100_000_000
)(
    //-------------------------------------------------------------------------
    // System Interface
    //-------------------------------------------------------------------------
    input                       clk,
    input                       rst_n,

    //-------------------------------------------------------------------------
    // External JTAG Interface (directly to Black Magic Probe)
    //-------------------------------------------------------------------------
    input                       ext_tck,
    input                       ext_tms,
    input                       ext_tdi,
    output                      ext_tdo,
    output                      ext_tdo_oe,
    input                       ext_trst_n,      // Optional

    //-------------------------------------------------------------------------
    // BSCANE2 Interface (directly from Xilinx primitive)
    //-------------------------------------------------------------------------
    input                       bscan_tck,
    input                       bscan_tms,
    input                       bscan_tdi,
    output                      bscan_tdo,
    input                       bscan_sel,       // USER instruction selected
    input                       bscan_drck,      // Data register clock
    input                       bscan_capture,
    input                       bscan_shift,
    input                       bscan_update,
    input                       bscan_reset,

    //-------------------------------------------------------------------------
    // Debug Memory Port (AXI-Lite Master)
    //-------------------------------------------------------------------------
    output [MEM_ADDR_WIDTH-1:0] m_axi_awaddr,
    output                      m_axi_awvalid,
    input                       m_axi_awready,
    output [MEM_DATA_WIDTH-1:0] m_axi_wdata,
    output [3:0]                m_axi_wstrb,
    output                      m_axi_wvalid,
    input                       m_axi_wready,
    input  [1:0]                m_axi_bresp,
    input                       m_axi_bvalid,
    output                      m_axi_bready,
    output [MEM_ADDR_WIDTH-1:0] m_axi_araddr,
    output                      m_axi_arvalid,
    input                       m_axi_arready,
    input  [MEM_DATA_WIDTH-1:0] m_axi_rdata,
    input  [1:0]                m_axi_rresp,
    input                       m_axi_rvalid,
    output                      m_axi_rready,

    //-------------------------------------------------------------------------
    // Signal Tap Probes (directly connected to RTL signals)
    //-------------------------------------------------------------------------
    input  [SIGNAL_TAP_WIDTH-1:0] probe_signals,
    input  [7:0]                  probe_group_sel, // Which group to observe

    //-------------------------------------------------------------------------
    // CPU Debug Interface (VexRiscv compatible)
    //-------------------------------------------------------------------------
    output                      cpu_halt_req,
    output                      cpu_resume_req,
    output                      cpu_reset_req,
    input                       cpu_halted,
    input                       cpu_running,
    input  [31:0]               cpu_pc,          // Program counter
    output [4:0]                cpu_reg_addr,    // Register to read
    input  [31:0]               cpu_reg_data,    // Register value
    output [31:0]               cpu_bp_addr,     // Breakpoint address
    output                      cpu_bp_enable,
    input                       cpu_bp_hit,

    //-------------------------------------------------------------------------
    // Trace Trigger Inputs
    //-------------------------------------------------------------------------
    input  [31:0]               trace_trigger_data,
    input                       trace_trigger_valid,

    //-------------------------------------------------------------------------
    // CDC Console Interface (directly to CLI)
    //-------------------------------------------------------------------------
    // Command input (from CDC RX)
    input  [7:0]                cmd_data,
    input                       cmd_valid,
    output                      cmd_ready,

    // Response output (to CDC TX)
    output [7:0]                rsp_data,
    output                      rsp_valid,
    input                       rsp_ready,

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output                      debug_active,    // Debug session active
    output                      jtag_connected,  // JTAG probe detected
    output [3:0]                current_layer,   // Bring-up layer achieved
    output [31:0]               last_error       // Last error code
);

    //=========================================================================
    // JTAG Source Selection
    //=========================================================================

    wire        jtag_tck;
    wire        jtag_tms;
    wire        jtag_tdi;
    wire        jtag_tdo;
    wire        jtag_sel;

    generate
        if (USE_BSCANE2) begin : gen_bscane2
            // BSCANE2 tunnel - shares JTAG with FPGA config
            assign jtag_tck = bscan_drck;
            assign jtag_tms = bscan_tms;
            assign jtag_tdi = bscan_tdi;
            assign bscan_tdo = jtag_tdo;
            assign jtag_sel = bscan_sel;
        end else begin : gen_external
            // External JTAG pins - dedicated debug port
            assign jtag_tck = ext_tck;
            assign jtag_tms = ext_tms;
            assign jtag_tdi = ext_tdi;
            assign ext_tdo = jtag_tdo;
            assign ext_tdo_oe = 1'b1;
            assign jtag_sel = 1'b1;  // Always selected
        end
    endgenerate

    //=========================================================================
    // JTAG TAP Controller
    //=========================================================================

    // TAP instruction register
    wire [4:0]  ir_value;
    wire        ir_capture;
    wire        ir_shift;
    wire        ir_update;

    // Data register interface
    wire [63:0] dr_capture_data;
    wire [63:0] dr_shift_data;
    wire        dr_capture;
    wire        dr_shift;
    wire        dr_update;
    wire [5:0]  dr_length;

    jtag_tap_controller #(
        .IDCODE         (JTAG_IDCODE)
    ) tap_ctrl (
        .tck            (jtag_tck),
        .tms            (jtag_tms),
        .tdi            (jtag_tdi),
        .tdo            (jtag_tdo),
        .trst_n         (ext_trst_n),

        .ir_value       (ir_value),
        .ir_capture     (ir_capture),
        .ir_shift       (ir_shift),
        .ir_update      (ir_update),

        .dr_capture_data(dr_capture_data),
        .dr_shift_in    (jtag_tdi),
        .dr_shift_out   (dr_shift_data[0]),
        .dr_capture     (dr_capture),
        .dr_shift       (dr_shift),
        .dr_update      (dr_update),
        .dr_length      (dr_length)
    );

    //=========================================================================
    // Debug Command Decoder (JTAG Instructions)
    //=========================================================================

    // JTAG Instructions (Black Magic Probe compatible + FluxRipper extensions)
    localparam IR_BYPASS        = 5'h1F;
    localparam IR_IDCODE        = 5'h01;
    localparam IR_DTMCS         = 5'h10;  // Debug Transport Module Control/Status
    localparam IR_DMI           = 5'h11;  // Debug Module Interface
    localparam IR_MEM_READ      = 5'h02;  // FluxRipper: Memory read
    localparam IR_MEM_WRITE     = 5'h03;  // FluxRipper: Memory write
    localparam IR_SIGNAL_TAP    = 5'h04;  // FluxRipper: Signal observation
    localparam IR_TRACE_CTRL    = 5'h05;  // FluxRipper: Trace control
    localparam IR_TRACE_DATA    = 5'h06;  // FluxRipper: Trace readout
    localparam IR_STATUS        = 5'h07;  // FluxRipper: System status
    localparam IR_CAPS          = 5'h08;  // FluxRipper: Capabilities query

    //=========================================================================
    // Debug Register Bank (accessible via JTAG and CDC console)
    //=========================================================================

    wire [31:0] dbg_reg_addr;
    wire [31:0] dbg_reg_wdata;
    wire [31:0] dbg_reg_rdata;
    wire        dbg_reg_we;
    wire        dbg_reg_re;
    wire        dbg_reg_ready;

    debug_register_bank #(
        .ADDR_WIDTH     (8),
        .CLK_FREQ_HZ    (CLK_FREQ_HZ)
    ) dbg_regs (
        .clk            (clk),
        .rst_n          (rst_n),

        // Register access
        .reg_addr       (dbg_reg_addr[7:0]),
        .reg_wdata      (dbg_reg_wdata),
        .reg_rdata      (dbg_reg_rdata),
        .reg_we         (dbg_reg_we),
        .reg_re         (dbg_reg_re),
        .reg_ready      (dbg_reg_ready),

        // Memory access results
        .mem_read_data  (m_axi_rdata),
        .mem_read_valid (m_axi_rvalid),
        .mem_write_done (m_axi_bvalid),
        .mem_error      (m_axi_rresp[1] | m_axi_bresp[1]),

        // Signal tap
        .probe_signals  (probe_signals),
        .probe_group_sel(probe_group_sel),

        // CPU status
        .cpu_halted     (cpu_halted),
        .cpu_running    (cpu_running),
        .cpu_pc         (cpu_pc),
        .cpu_reg_data   (cpu_reg_data),

        // Trace status
        .trace_count    (trace_count),
        .trace_wrapped  (trace_wrapped),
        .trace_triggered(trace_triggered),

        // System status outputs
        .current_layer  (current_layer),
        .last_error     (last_error)
    );

    //=========================================================================
    // Debug Memory Access Port
    //=========================================================================

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;
    wire        mem_read_req;
    wire        mem_write_req;
    wire        mem_ready;

    debug_mem_port #(
        .ADDR_WIDTH     (MEM_ADDR_WIDTH),
        .DATA_WIDTH     (MEM_DATA_WIDTH)
    ) mem_port (
        .clk            (clk),
        .rst_n          (rst_n),

        // Command interface
        .addr           (mem_addr),
        .wdata          (mem_wdata),
        .rdata          (mem_rdata),
        .read_req       (mem_read_req),
        .write_req      (mem_write_req),
        .ready          (mem_ready),

        // AXI-Lite Master
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    //=========================================================================
    // RTL Signal Tap
    //=========================================================================

    wire [SIGNAL_TAP_WIDTH-1:0] tap_captured;
    wire [31:0]                  tap_trigger_mask;
    wire [31:0]                  tap_trigger_value;
    wire                         tap_triggered;

    rtl_signal_tap #(
        .WIDTH          (SIGNAL_TAP_WIDTH),
        .GROUPS         (SIGNAL_TAP_GROUPS)
    ) signal_tap (
        .clk            (clk),
        .rst_n          (rst_n),

        // Probe input
        .probe_in       (probe_signals),
        .group_sel      (probe_group_sel),

        // Capture output
        .captured       (tap_captured),

        // Trigger
        .trigger_mask   (tap_trigger_mask),
        .trigger_value  (tap_trigger_value),
        .triggered      (tap_triggered)
    );

    //=========================================================================
    // Trace Buffer
    //=========================================================================

    wire [TRACE_WIDTH-1:0]       trace_data_in;
    wire                         trace_write;
    wire [TRACE_WIDTH-1:0]       trace_data_out;
    wire [TRACE_DEPTH_LOG2-1:0]  trace_read_addr;
    wire [TRACE_DEPTH_LOG2-1:0]  trace_count;
    wire                         trace_wrapped;
    wire                         trace_triggered;
    wire                         trace_enable;
    wire                         trace_clear;

    trace_buffer #(
        .DEPTH_LOG2     (TRACE_DEPTH_LOG2),
        .WIDTH          (TRACE_WIDTH)
    ) trace_buf (
        .clk            (clk),
        .rst_n          (rst_n),

        // Control
        .enable         (trace_enable),
        .clear          (trace_clear),

        // Data input
        .data_in        (trace_data_in),
        .write          (trace_write),

        // Trigger
        .trigger_in     (trace_trigger_valid),
        .trigger_data   (trace_trigger_data),

        // Readout
        .read_addr      (trace_read_addr),
        .data_out       (trace_data_out),
        .count          (trace_count),
        .wrapped        (trace_wrapped),
        .triggered      (trace_triggered)
    );

    //=========================================================================
    // CDC Console Command Parser
    //=========================================================================

    // This provides text-based access to all debug features
    // Commands are simple: "r ADDR" (read), "w ADDR DATA" (write), etc.

    debug_console_parser #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ)
    ) console (
        .clk            (clk),
        .rst_n          (rst_n),

        // CDC interface
        .cmd_data       (cmd_data),
        .cmd_valid      (cmd_valid),
        .cmd_ready      (cmd_ready),
        .rsp_data       (rsp_data),
        .rsp_valid      (rsp_valid),
        .rsp_ready      (rsp_ready),

        // Register access
        .reg_addr       (dbg_reg_addr),
        .reg_wdata      (dbg_reg_wdata),
        .reg_rdata      (dbg_reg_rdata),
        .reg_we         (dbg_reg_we),
        .reg_re         (dbg_reg_re),
        .reg_ready      (dbg_reg_ready),

        // Memory access
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_rdata      (mem_rdata),
        .mem_read_req   (mem_read_req),
        .mem_write_req  (mem_write_req),
        .mem_ready      (mem_ready),

        // Signal tap
        .tap_captured   (tap_captured),
        .tap_trigger_mask(tap_trigger_mask),
        .tap_trigger_value(tap_trigger_value),

        // Trace control
        .trace_enable   (trace_enable),
        .trace_clear    (trace_clear),
        .trace_read_addr(trace_read_addr),
        .trace_data_out (trace_data_out),
        .trace_count    (trace_count),

        // CPU control
        .cpu_halt_req   (cpu_halt_req),
        .cpu_resume_req (cpu_resume_req),
        .cpu_reset_req  (cpu_reset_req),
        .cpu_reg_addr   (cpu_reg_addr),
        .cpu_bp_addr    (cpu_bp_addr),
        .cpu_bp_enable  (cpu_bp_enable),

        // Status
        .debug_active   (debug_active),
        .current_layer  (current_layer)
    );

    //=========================================================================
    // JTAG Activity Detection
    //=========================================================================

    reg [15:0] jtag_activity_cnt;
    reg        jtag_connected_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            jtag_activity_cnt <= 16'd0;
            jtag_connected_r <= 1'b0;
        end else begin
            // Detect JTAG activity by watching for state machine transitions
            if (ir_update || dr_update) begin
                jtag_activity_cnt <= 16'hFFFF;
                jtag_connected_r <= 1'b1;
            end else if (jtag_activity_cnt > 0) begin
                jtag_activity_cnt <= jtag_activity_cnt - 1;
            end else begin
                jtag_connected_r <= 1'b0;
            end
        end
    end

    assign jtag_connected = jtag_connected_r;

endmodule


//=============================================================================
// Debug Console Command Reference
//=============================================================================
//
// Text commands available via CDC console once USB is enumerated:
//
// MEMORY ACCESS:
//   r <addr>              - Read 32-bit word from address (hex)
//   r <addr> <count>      - Read multiple words
//   w <addr> <data>       - Write 32-bit word to address
//   dump <addr> <len>     - Hex dump of memory region
//   fill <addr> <len> <v> - Fill memory with value
//
// SIGNAL TAP:
//   probe                 - Show current probe values
//   probe <group>         - Select probe group (0-3)
//   trigger <mask> <val>  - Set trigger condition
//   watch <signal>        - Continuous signal display
//
// TRACE:
//   trace start           - Start trace capture
//   trace stop            - Stop trace capture
//   trace clear           - Clear trace buffer
//   trace dump [n]        - Dump last n trace entries
//   trace trigger <cond>  - Set trace trigger
//
// CPU CONTROL:
//   halt                  - Halt CPU
//   run                   - Resume CPU
//   step                  - Single step
//   reg                   - Show all registers
//   reg <n>               - Show register n
//   pc                    - Show program counter
//   bp <addr>             - Set breakpoint
//   bp clear              - Clear breakpoint
//
// SYSTEM:
//   status                - Show system status
//   layer                 - Show current bring-up layer
//   caps                  - Show debug capabilities
//   id                    - Show JTAG IDCODE
//   clocks                - Show clock status
//   reset                 - Reset CPU (not FPGA)
//   help                  - Show this help
//
// BATCH/SCRIPT:
//   ; <cmd>               - Comment (ignored)
//   @<file>               - Execute commands from file (host-side)
//   ! <n>                 - Repeat last command n times
//   delay <ms>            - Wait milliseconds
//
//=============================================================================
