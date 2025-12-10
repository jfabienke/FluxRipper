// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// usb_logger_integration.v - USB Traffic Logger Integration Example
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 13:00
//
// Description:
//   Shows how to integrate usb_traffic_logger with usb_top_v2.
//   This module wraps usb_top_v2 and adds traffic logging capability.
//
// Integration Steps:
//   1. Instantiate usb_traffic_logger alongside usb_top_v2
//   2. Tap UTMI signals from ulpi_wrapper_v2
//   3. Connect AXI-Lite interface to MicroBlaze for firmware access
//   4. Export status signals for debugging
//
//-----------------------------------------------------------------------------

module usb_top_v2_with_logger #(
    parameter LOGGER_BUFFER_DEPTH_LOG2 = 13  // 8KB buffer
)(
    input         clk_sys,
    input         rst_n,

    //-------------------------------------------------------------------------
    // ULPI PHY Interface
    //-------------------------------------------------------------------------
    input         ulpi_clk,
    inout  [7:0]  ulpi_data,
    input         ulpi_dir,
    input         ulpi_nxt,
    output        ulpi_stp,
    output        ulpi_rst_n,

    //-------------------------------------------------------------------------
    // Personality Selection
    //-------------------------------------------------------------------------
    input  [2:0]  personality_sel,
    input         personality_switch,
    output        switch_complete,
    output [2:0]  active_personality,

    //-------------------------------------------------------------------------
    // Flux Capture Interface
    //-------------------------------------------------------------------------
    input  [31:0] flux_data,
    input         flux_valid,
    output        flux_ready,
    input         flux_index,
    output        flux_capture_start,
    output        flux_capture_stop,
    output [7:0]  flux_sample_rate,
    input         flux_capturing,

    //-------------------------------------------------------------------------
    // Drive Control
    //-------------------------------------------------------------------------
    output [3:0]  drive_select,
    output        motor_on,
    output        head_select,
    output [7:0]  track_target,
    output        step,
    output        step_dir,
    input  [7:0]  track_actual,
    input         track0,

    //-------------------------------------------------------------------------
    // CDC Debug Console FIFO Interface
    //-------------------------------------------------------------------------
    input  [7:0]  cdc_rx_data,
    input         cdc_rx_valid,
    output        cdc_rx_ready,
    output [7:0]  cdc_tx_data,
    output        cdc_tx_valid,
    input         cdc_tx_ready,

    //-------------------------------------------------------------------------
    // USB Logger AXI-Lite Interface (connect to MicroBlaze)
    //-------------------------------------------------------------------------
    input  [7:0]  logger_reg_addr,
    input  [31:0] logger_reg_wdata,
    input         logger_reg_we,
    input         logger_reg_re,
    output [31:0] logger_reg_rdata,
    output        logger_reg_rvalid,

    //-------------------------------------------------------------------------
    // Logger Status (directly exposed)
    //-------------------------------------------------------------------------
    output        logger_capture_active,
    output        logger_buffer_overflow,
    output [31:0] logger_transaction_count,

    //-------------------------------------------------------------------------
    // USB Status Outputs
    //-------------------------------------------------------------------------
    output        usb_connected,
    output        usb_configured,
    output        usb_suspended,
    output        usb_high_speed,
    output [3:0]  usb_ep_stall
);

    //=========================================================================
    // Internal UTMI signals (tapped for logger)
    //=========================================================================
    wire [7:0]  utmi_rx_data;
    wire        utmi_rx_valid;
    wire        utmi_rx_active;
    wire [7:0]  utmi_tx_data;
    wire        utmi_tx_valid;
    wire        utmi_tx_ready;
    wire [1:0]  utmi_line_state;

    //=========================================================================
    // USB Top Module (existing implementation)
    //=========================================================================
    // Note: usb_top_v2 needs modification to expose UTMI signals.
    // Add output ports for utmi_rx_data, utmi_rx_valid, utmi_rx_active,
    // utmi_tx_data, utmi_tx_valid, utmi_tx_ready, utmi_line_state.
    //
    // Example modification to usb_top_v2.v:
    //   // Add to module ports:
    //   output [7:0]  utmi_tap_rx_data,
    //   output        utmi_tap_rx_valid,
    //   output        utmi_tap_rx_active,
    //   output [7:0]  utmi_tap_tx_data,
    //   output        utmi_tap_tx_valid,
    //   output        utmi_tap_tx_ready,
    //   output [1:0]  utmi_tap_line_state,
    //
    //   // Add assignments after ulpi_wrapper_v2 instantiation:
    //   assign utmi_tap_rx_data   = utmi_data_rx;
    //   assign utmi_tap_rx_valid  = utmi_rxvalid;
    //   assign utmi_tap_rx_active = utmi_rxactive;
    //   assign utmi_tap_tx_data   = utmi_data_tx;
    //   assign utmi_tap_tx_valid  = utmi_txvalid;
    //   assign utmi_tap_tx_ready  = utmi_txready;
    //   assign utmi_tap_line_state = utmi_linestate;

    usb_top_v2 usb_core (
        .clk_sys            (clk_sys),
        .rst_n              (rst_n),

        // ULPI PHY
        .ulpi_clk           (ulpi_clk),
        .ulpi_data          (ulpi_data),
        .ulpi_dir           (ulpi_dir),
        .ulpi_nxt           (ulpi_nxt),
        .ulpi_stp           (ulpi_stp),
        .ulpi_rst_n         (ulpi_rst_n),

        // Personality
        .personality_sel    (personality_sel),
        .personality_switch (personality_switch),
        .switch_complete    (switch_complete),
        .active_personality (active_personality),

        // Flux
        .flux_data          (flux_data),
        .flux_valid         (flux_valid),
        .flux_ready         (flux_ready),
        .flux_index         (flux_index),
        .flux_capture_start (flux_capture_start),
        .flux_capture_stop  (flux_capture_stop),
        .flux_sample_rate   (flux_sample_rate),
        .flux_capturing     (flux_capturing),

        // Drive control
        .drive_select       (drive_select),
        .motor_on           (motor_on),
        .head_select        (head_select),
        .track_target       (track_target),
        .step               (step),
        .step_dir           (step_dir),
        .track_actual       (track_actual),
        .track0             (track0),

        // CDC debug console
        .cdc_rx_data        (cdc_rx_data),
        .cdc_rx_valid       (cdc_rx_valid),
        .cdc_rx_ready       (cdc_rx_ready),
        .cdc_tx_data        (cdc_tx_data),
        .cdc_tx_valid       (cdc_tx_valid),
        .cdc_tx_ready       (cdc_tx_ready),

        // UTMI tap outputs (need to add to usb_top_v2.v)
        .utmi_tap_rx_data   (utmi_rx_data),
        .utmi_tap_rx_valid  (utmi_rx_valid),
        .utmi_tap_rx_active (utmi_rx_active),
        .utmi_tap_tx_data   (utmi_tx_data),
        .utmi_tap_tx_valid  (utmi_tx_valid),
        .utmi_tap_tx_ready  (utmi_tx_ready),
        .utmi_tap_line_state(utmi_line_state),

        // Status
        .usb_connected      (usb_connected),
        .usb_configured     (usb_configured),
        .usb_suspended      (usb_suspended),
        .usb_high_speed     (usb_high_speed),
        .usb_ep_stall       (usb_ep_stall)
    );

    //=========================================================================
    // USB Traffic Logger
    //=========================================================================
    usb_traffic_logger #(
        .BUFFER_DEPTH_LOG2  (LOGGER_BUFFER_DEPTH_LOG2),
        .CLK_FREQ_HZ        (60000000)  // 60 MHz ULPI clock
    ) traffic_logger (
        .clk                (ulpi_clk),
        .rst_n              (rst_n),

        // UTMI tap (non-intrusive monitoring)
        .utmi_rx_data       (utmi_rx_data),
        .utmi_rx_valid      (utmi_rx_valid),
        .utmi_rx_active     (utmi_rx_active),
        .utmi_tx_data       (utmi_tx_data),
        .utmi_tx_valid      (utmi_tx_valid),
        .utmi_tx_ready      (utmi_tx_ready),
        .utmi_line_state    (utmi_line_state),

        // AXI-Lite register interface
        .reg_addr           (logger_reg_addr),
        .reg_wdata          (logger_reg_wdata),
        .reg_we             (logger_reg_we),
        .reg_re             (logger_reg_re),
        .reg_rdata          (logger_reg_rdata),
        .reg_rvalid         (logger_reg_rvalid),

        // Status outputs
        .capture_active     (logger_capture_active),
        .buffer_overflow    (logger_buffer_overflow),
        .transaction_count  (logger_transaction_count)
    );

endmodule


//=============================================================================
// Alternative: Standalone Logger for External USB Analysis
//=============================================================================
// If you want to use FluxRipper as a USB analyzer for external devices,
// you would need additional hardware (second USB port). This module shows
// the concept:

module usb_passthrough_analyzer #(
    parameter LOGGER_BUFFER_DEPTH_LOG2 = 14  // 16KB buffer for analysis
)(
    input         clk,
    input         rst_n,

    //-------------------------------------------------------------------------
    // Upstream ULPI (to host PC)
    //-------------------------------------------------------------------------
    input         ulpi_host_clk,
    inout  [7:0]  ulpi_host_data,
    input         ulpi_host_dir,
    input         ulpi_host_nxt,
    output        ulpi_host_stp,

    //-------------------------------------------------------------------------
    // Downstream ULPI (to target device) - requires second PHY
    //-------------------------------------------------------------------------
    input         ulpi_dev_clk,
    inout  [7:0]  ulpi_dev_data,
    input         ulpi_dev_dir,
    input         ulpi_dev_nxt,
    output        ulpi_dev_stp,

    //-------------------------------------------------------------------------
    // Logger Interface
    //-------------------------------------------------------------------------
    input  [7:0]  logger_reg_addr,
    input  [31:0] logger_reg_wdata,
    input         logger_reg_we,
    input         logger_reg_re,
    output [31:0] logger_reg_rdata,
    output        logger_reg_rvalid,

    output        logger_capture_active,
    output        logger_buffer_overflow,
    output [31:0] logger_transaction_count
);

    // This would require:
    // 1. Second USB3320 PHY
    // 2. USB pass-through logic (transparent relay)
    // 3. Tapping the UTMI signals from both directions
    //
    // For now, FluxRipper focuses on self-monitoring its own USB traffic.
    // Full USB analyzer mode would be a future hardware revision.

    // Placeholder - actual implementation requires significant additional logic
    assign logger_reg_rdata = 32'd0;
    assign logger_reg_rvalid = 1'b0;
    assign logger_capture_active = 1'b0;
    assign logger_buffer_overflow = 1'b0;
    assign logger_transaction_count = 32'd0;

endmodule
