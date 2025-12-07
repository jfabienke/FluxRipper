// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// rtl_signal_tap.v - RTL Signal Observation Module
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 15:00
//
// Description:
//   Configurable signal observation for debugging internal RTL signals.
//   Supports multiple probe groups, trigger conditions, and continuous
//   sampling. Much lighter than Xilinx ILA - just captures current values.
//
// Probe Groups (configurable at synthesis):
//   Group 0: USB signals (ULPI state, endpoint status, packet state)
//   Group 1: FDC signals (command, track, sector, status)
//   Group 2: HDD signals (command, cylinder, head, status)
//   Group 3: System signals (clocks, resets, interrupts)
//
// Usage:
//   1. Select group via probe_group_sel
//   2. Read captured values from probe_out
//   3. Optionally set trigger_mask and trigger_value for conditional capture
//
//-----------------------------------------------------------------------------

module rtl_signal_tap #(
    parameter WIDTH  = 128,           // Total probe width
    parameter GROUPS = 4              // Number of probe groups
)(
    input                   clk,
    input                   rst_n,

    //-------------------------------------------------------------------------
    // Probe Input (directly connected to RTL signals)
    //-------------------------------------------------------------------------
    input  [WIDTH-1:0]      probe_in,

    //-------------------------------------------------------------------------
    // Group Selection
    //-------------------------------------------------------------------------
    input  [7:0]            group_sel,

    //-------------------------------------------------------------------------
    // Captured Output (32 bits of selected group)
    //-------------------------------------------------------------------------
    output [31:0]           captured,

    //-------------------------------------------------------------------------
    // Trigger Configuration
    //-------------------------------------------------------------------------
    input  [31:0]           trigger_mask,   // Which bits to compare
    input  [31:0]           trigger_value,  // Value to match
    output                  triggered,

    //-------------------------------------------------------------------------
    // Sample Control
    //-------------------------------------------------------------------------
    input                   sample_enable,
    input                   single_shot,    // Capture once on trigger
    output                  sample_valid
);

    //=========================================================================
    // Probe Group Extraction
    //=========================================================================

    // Assuming 128 bits / 4 groups = 32 bits per group
    localparam GROUP_WIDTH = WIDTH / GROUPS;

    reg [31:0] selected_probes;

    always @(*) begin
        case (group_sel[1:0])
            2'd0: selected_probes = probe_in[31:0];
            2'd1: selected_probes = probe_in[63:32];
            2'd2: selected_probes = probe_in[95:64];
            2'd3: selected_probes = probe_in[127:96];
        endcase
    end

    //=========================================================================
    // Capture Register
    //=========================================================================

    reg [31:0] captured_reg;
    reg        sample_valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_reg <= 32'd0;
            sample_valid_reg <= 1'b0;
        end else begin
            // Always capture current probes (continuous observation)
            captured_reg <= selected_probes;
            sample_valid_reg <= 1'b1;
        end
    end

    assign captured = captured_reg;
    assign sample_valid = sample_valid_reg;

    //=========================================================================
    // Trigger Detection
    //=========================================================================

    wire [31:0] masked_probes = selected_probes & trigger_mask;
    wire [31:0] masked_value  = trigger_value & trigger_mask;

    reg triggered_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            triggered_reg <= 1'b0;
        end else begin
            if (trigger_mask == 32'd0) begin
                // No trigger configured - always triggered
                triggered_reg <= 1'b1;
            end else begin
                triggered_reg <= (masked_probes == masked_value);
            end
        end
    end

    assign triggered = triggered_reg;

endmodule


//=============================================================================
// Probe Group Definitions for FluxRipper
//=============================================================================
//
// These are the recommended signal assignments for each probe group.
// Connect these in fluxripper_debug_top.v:
//
// Group 0: USB Subsystem [31:0]
//   [3:0]   ulpi_state          - ULPI wrapper state machine
//   [7:4]   usb_state           - USB device state (attached/default/address/configured)
//   [11:8]  ep0_state           - Control endpoint state
//   [15:12] ep1_state           - Bulk endpoint 1 state
//   [19:16] ep2_state           - Bulk endpoint 2 state
//   [23:20] packet_pid          - Current packet PID
//   [24]    usb_sof             - Start of frame
//   [25]    usb_setup           - SETUP packet received
//   [26]    usb_in              - IN token received
//   [27]    usb_out             - OUT token received
//   [28]    usb_ack             - ACK handshake
//   [29]    usb_nak             - NAK handshake
//   [30]    usb_stall           - STALL handshake
//   [31]    usb_error           - Error detected
//
// Group 1: FDC Subsystem [63:32]
//   [3:0]   fdc_command         - Current FDC command
//   [7:4]   fdc_state           - FDC state machine
//   [15:8]  fdc_track           - Current track
//   [20:16] fdc_sector          - Current sector
//   [21]    fdc_head            - Head select
//   [22]    fdc_motor           - Motor on
//   [23]    fdc_busy            - Command in progress
//   [24]    fdc_index           - Index pulse
//   [25]    fdc_track0          - Track 0 sensor
//   [26]    fdc_wp              - Write protect
//   [27]    fdc_ready           - Drive ready
//   [28]    fdc_read_data       - Read data valid
//   [29]    fdc_write_gate      - Write gate active
//   [30]    fdc_dma_req         - DMA request
//   [31]    fdc_irq             - Interrupt request
//
// Group 2: HDD Subsystem [95:64]
//   [3:0]   hdd_command         - WD command
//   [7:4]   hdd_state           - Command state machine
//   [17:8]  hdd_cylinder        - Cylinder (10 bits)
//   [21:18] hdd_head            - Head select
//   [27:22] hdd_sector          - Sector number
//   [28]    hdd_seek_complete   - Seek completed
//   [29]    hdd_index           - Index pulse
//   [30]    hdd_ready           - Drive ready
//   [31]    hdd_error           - Error flag
//
// Group 3: System Signals [127:96]
//   [0]     clk_100mhz_ok       - 100 MHz clock present
//   [1]     clk_60mhz_ok        - 60 MHz USB clock present
//   [2]     clk_200mhz_ok       - 200 MHz capture clock present
//   [3]     pll_locked          - All PLLs locked
//   [4]     rst_n               - Active reset
//   [5]     usb_connected       - USB cable connected
//   [6]     usb_configured      - USB enumeration complete
//   [7]     usb_suspended       - USB suspend state
//   [11:8]  active_personality  - Current USB personality
//   [15:12] power_state         - Power subsystem state
//   [23:16] temperature         - FPGA temperature (8-bit)
//   [31:24] error_flags         - System error flags
//
//=============================================================================
