// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// usb_top_v2.v - USB 2.0 High-Speed Top-Level Module
//
// Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
// Copyright (c) 2025 John Fabienke
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Created: 2025-12-06 12:50:00
// Updated: 2025-12-06 20:55:00
//
// Description:
//   Top-level USB 2.0 High-Speed device implementation using ULPI PHY.
//   Replaces FT601 FIFO bridge with native USB stack supporting:
//   - USB Control Transfers (for KryoFlux DTC compatibility)
//   - USB Bulk Transfers (for all personalities)
//   - Custom VID/PID enumeration per personality
//   - 480 Mbps High-Speed operation
//
// Module Hierarchy:
//   usb_top_v2
//   ├── ulpi_wrapper_v2 (ULPI ↔ UTMI translation, BSD-3-Clause)
//   ├── usb_hs_negotiator (HS chirp FSM)
//   ├── usb_device_core_v2 (packet handling)
//   ├── usb_control_ep (EP0, standard + vendor + CDC class requests)
//   ├── usb_bulk_ep (EP1 OUT - commands)
//   ├── usb_bulk_ep (EP1 IN - responses)
//   ├── usb_bulk_ep (EP2 IN - flux streaming)
//   └── usb_cdc_ep (EP3 IN/OUT - CDC ACM debug console)
//
//-----------------------------------------------------------------------------

module usb_top_v2 (
    input         clk_sys,           // System clock (for CDC if needed)
    input         rst_n,             // Active-low reset

    //-------------------------------------------------------------------------
    // ULPI PHY Interface (directly to USB3300/USB3320)
    //-------------------------------------------------------------------------
    input         ulpi_clk,          // 60 MHz from PHY
    inout  [7:0]  ulpi_data,         // Bidirectional data
    input         ulpi_dir,          // Direction: 1=PHY→FPGA
    input         ulpi_nxt,          // Next data
    output        ulpi_stp,          // Stop
    output        ulpi_rst_n,        // PHY reset (directly active-low)

    //-------------------------------------------------------------------------
    // Personality Selection
    //-------------------------------------------------------------------------
    input  [2:0]  personality_sel,   // 0=GW, 1=HxC, 2=KF, 3=Native, 4=MSC
    input         personality_switch, // Request personality switch
    output        switch_complete,    // Switch completed
    output [2:0]  active_personality, // Current active personality

    //-------------------------------------------------------------------------
    // Flux Capture Interface (directly to existing capture engine)
    //-------------------------------------------------------------------------
    input  [31:0] flux_data,         // [31]=INDEX, [27:0]=timestamp
    input         flux_valid,
    output        flux_ready,
    input         flux_index,        // Index pulse

    // Flux engine control
    output        flux_capture_start,
    output        flux_capture_stop,
    output [7:0]  flux_sample_rate,  // Sample rate selector
    input         flux_capturing,

    //-------------------------------------------------------------------------
    // Drive Control (directly to existing drive controller)
    //-------------------------------------------------------------------------
    output [3:0]  drive_select,      // One-hot drive select
    output        motor_on,
    output        head_select,       // 0=side0, 1=side1
    output [7:0]  track_target,
    output        seek_start,
    input         seek_complete,
    input  [7:0]  current_track,

    // Extended drive status
    input         disk_present,
    input         write_protect,
    input         track_00,
    input         motor_spinning,

    //-------------------------------------------------------------------------
    // Protocol Handler Interfaces (directly to existing handlers)
    //-------------------------------------------------------------------------
    // To personality mux / protocol handlers
    output [31:0] proto_rx_data,     // Commands from host
    output        proto_rx_valid,
    input         proto_rx_ready,
    input  [31:0] proto_tx_data,     // Data to host
    input         proto_tx_valid,
    output        proto_tx_ready,

    //-------------------------------------------------------------------------
    // KryoFlux Control Transfer Interface (when personality=2)
    //-------------------------------------------------------------------------
    output        kf_cmd_valid,
    output [7:0]  kf_cmd_request,
    output [15:0] kf_cmd_value,
    output [15:0] kf_cmd_index,
    output [15:0] kf_cmd_length,
    input  [7:0]  kf_response_data,
    input         kf_response_valid,
    input         kf_response_last,

    //-------------------------------------------------------------------------
    // MSC Block Device Interface (for Personality 4)
    //-------------------------------------------------------------------------
    output [3:0]  msc_lun,           // Logical Unit Number
    output [31:0] msc_lba,           // Logical Block Address
    output [15:0] msc_block_count,
    output        msc_read_start,
    output        msc_write_start,
    input         msc_ready,
    input         msc_error,

    // Sector data
    input  [31:0] msc_read_data,
    input         msc_read_valid,
    output        msc_read_ready,
    output [31:0] msc_write_data,
    output        msc_write_valid,
    input         msc_write_ready,

    //-------------------------------------------------------------------------
    // Diagnostics Interface
    //-------------------------------------------------------------------------
    output [31:0] diag_cmd,
    output        diag_cmd_valid,
    input  [31:0] diag_response,
    input         diag_response_valid,

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output        usb_connected,     // USB cable connected (VBUS)
    output        usb_configured,    // SET_CONFIGURATION received
    output        usb_suspended,     // Device in suspend
    output [1:0]  usb_speed,         // 00=HS, 01=FS, 10=LS
    output [10:0] usb_frame_number,  // Current frame number
    output        usb_sof_valid,     // SOF received

    // Extended status
    output        usb_error,
    output [7:0]  usb_state,
    output [7:0]  protocol_state,
    output [31:0] rx_byte_count,
    output [31:0] tx_byte_count,

    //-------------------------------------------------------------------------
    // MSC Configuration Interface (from msc_config_regs)
    //-------------------------------------------------------------------------
    input         msc_config_valid,
    input  [15:0] msc_fdd0_sectors,
    input  [15:0] msc_fdd1_sectors,
    input  [31:0] msc_hdd0_sectors,
    input  [31:0] msc_hdd1_sectors,
    input  [3:0]  msc_drive_ready_in,
    input  [3:0]  msc_drive_wp_in,

    // MSC Status Outputs (to msc_config_regs)
    output [3:0]  msc_drive_present_out,
    output [3:0]  msc_media_changed_out,

    //-------------------------------------------------------------------------
    // CDC Debug Console Interface (EP3)
    //-------------------------------------------------------------------------
    input  [7:0]  debug_tx_data,         // Debug data to send to host
    input         debug_tx_valid,        // Debug data valid
    output        debug_tx_ready,        // Ready to accept debug data
    output [7:0]  debug_rx_data,         // Command data from host
    output        debug_rx_valid,        // Command data valid
    input         debug_rx_ready,        // Ready to accept command data
    output        debug_dtr_active       // Terminal connected indicator
);

//-----------------------------------------------------------------------------
// Internal Signals
//-----------------------------------------------------------------------------

// ULPI bidirectional data
wire [7:0] ulpi_data_in;
wire [7:0] ulpi_data_out;
wire       ulpi_data_oe;

// UTMI interface (between ULPI wrapper and device core)
wire [7:0] utmi_data_in;
wire [7:0] utmi_data_out;
wire       utmi_txready;
wire       utmi_txvalid;
wire       utmi_rxvalid;
wire       utmi_rxactive;
wire       utmi_rxerror;
wire [1:0] utmi_linestate;

// HS negotiator control signals
wire [1:0] utmi_op_mode;
wire [1:0] utmi_xcvrselect;
wire       utmi_termselect;
wire       utmi_dppulldown;
wire       utmi_dmpulldown;
wire [1:0] current_speed;
wire       bus_reset;
wire       hs_negotiator_tx_valid;
wire [7:0] hs_negotiator_tx_data;

// Device address and configuration
wire [6:0] device_address;
wire       set_address;
wire [6:0] new_address;
wire       set_configured;
wire [7:0] device_config;

// Control endpoint signals
wire        setup_valid;
wire [63:0] setup_packet;
wire        ctrl_out_valid;
wire [7:0]  ctrl_out_data;
wire [7:0]  ctrl_in_data;
wire        ctrl_in_valid;
wire        ctrl_in_last;
wire        ctrl_stall;
wire        ctrl_ack;
wire        ctrl_phase_done;

// Bulk endpoint signals
wire [3:0]  token_ep;
wire        token_in;
wire        token_out;
wire        rx_data_valid;
wire [7:0]  rx_data;
wire        rx_last;
wire        rx_crc_ok;
wire [7:0]  tx_data;
wire        tx_valid;
wire        tx_last;
wire        tx_ready;
wire        ep_stall;
wire        ep_nak;
wire        ep1_out_ack, ep1_out_nak, ep1_out_stall;
wire        ep1_in_ack, ep1_in_nak, ep1_in_stall;
wire        ep2_in_ack, ep2_in_nak, ep2_in_stall;
wire        ep3_ack, ep3_nak, ep3_stall;

// Descriptor ROM interface
wire [7:0]  desc_type;
wire [7:0]  desc_index;
wire [15:0] desc_length;
wire        desc_request;
wire [7:0]  desc_data;
wire        desc_valid;
wire        desc_last;

// Combined TX mux for IN endpoints
wire [7:0]  ep1_in_tx_data, ep2_in_tx_data, ep3_tx_data;
wire        ep1_in_tx_valid, ep2_in_tx_valid, ep3_tx_valid;
wire        ep1_in_tx_last, ep2_in_tx_last, ep3_tx_last;

// FIFO interfaces
wire [31:0] ep1_out_fifo_data;
wire        ep1_out_fifo_valid;
wire        ep1_out_fifo_ready;
wire [31:0] ep1_in_fifo_data;
wire        ep1_in_fifo_valid;
wire        ep1_in_fifo_ready;
wire [31:0] ep2_in_fifo_data;
wire        ep2_in_fifo_valid;
wire        ep2_in_fifo_ready;

// CDC endpoint signals
wire [7:0]  cdc_ctrl_response_data;
wire        cdc_ctrl_response_valid;
wire        cdc_ctrl_response_last;
wire        cdc_ctrl_request_handled;
wire        cdc_send_ack;
wire        cdc_send_nak;
wire        cdc_dtr_active;
wire        cdc_rts_active;
wire        cdc_configured;
wire [31:0] cdc_line_coding_baud;

// Address register
reg [6:0] address_reg;
reg [7:0] config_reg;
reg       configured_reg;

// PHY reset
reg [15:0] phy_reset_cnt;
reg        phy_reset_done;

// Personality switching (TODO: Implement actual switching logic)
wire       switch_complete_int;
wire [2:0] active_personality_int;

// Flux engine control (TODO: Wire from protocol handlers)
wire       flux_capture_start_int;
wire       flux_capture_stop_int;
wire [7:0] flux_sample_rate_int;

// Drive control outputs (TODO: Wire from protocol handlers)
wire [3:0] drive_select_int;
wire       motor_on_int;
wire       head_select_int;
wire [7:0] track_target_int;
wire       seek_start_int;

// MSC block device interface (TODO: Wire from MSC protocol handler)
wire [3:0]  msc_lun_int;
wire [31:0] msc_lba_int;
wire [15:0] msc_block_count_int;
wire        msc_read_start_int;
wire        msc_write_start_int;
wire        msc_read_ready_int;
wire [31:0] msc_write_data_int;
wire        msc_write_valid_int;

// Diagnostics interface (TODO: Wire from Native protocol handler)
wire [31:0] diag_cmd_int;
wire        diag_cmd_valid_int;

// Extended status (TODO: Implement proper status tracking)
wire        usb_error_int;
wire [7:0]  usb_state_int;
wire [7:0]  protocol_state_int;
wire [31:0] rx_byte_count_int;
wire [31:0] tx_byte_count_int;

// MSC configuration status (TODO: Implement when MSC is integrated)
wire [3:0]  msc_drive_present_int;
wire [3:0]  msc_media_changed_int;

//-----------------------------------------------------------------------------
// ULPI Bidirectional Data Handling
//-----------------------------------------------------------------------------
assign ulpi_data = ulpi_data_oe ? ulpi_data_out : 8'bz;
assign ulpi_data_in = ulpi_data;

//-----------------------------------------------------------------------------
// PHY Reset Sequence (hold reset for ~1ms after power-up)
//-----------------------------------------------------------------------------
always @(posedge ulpi_clk or negedge rst_n) begin
    if (!rst_n) begin
        phy_reset_cnt <= 16'd0;
        phy_reset_done <= 1'b0;
    end else if (!phy_reset_done) begin
        if (phy_reset_cnt == 16'd60000) begin  // ~1ms at 60MHz
            phy_reset_done <= 1'b1;
        end else begin
            phy_reset_cnt <= phy_reset_cnt + 1'b1;
        end
    end
end

assign ulpi_rst_n = phy_reset_done;

//-----------------------------------------------------------------------------
// Address and Configuration Management
//-----------------------------------------------------------------------------
always @(posedge ulpi_clk or negedge rst_n) begin
    if (!rst_n) begin
        address_reg <= 7'd0;
        config_reg <= 8'd0;
        configured_reg <= 1'b0;
    end else if (bus_reset) begin
        address_reg <= 7'd0;
        config_reg <= 8'd0;
        configured_reg <= 1'b0;
    end else begin
        if (set_address)
            address_reg <= new_address;
        if (set_configured) begin
            config_reg <= device_config;
            configured_reg <= (device_config != 8'd0);
        end
    end
end

assign device_address = address_reg;
assign usb_configured = configured_reg;

//-----------------------------------------------------------------------------
// ULPI Wrapper (ULPI ↔ UTMI translation)
// Using BSD-3-Clause licensed ulpi_wrapper_v2 (clean-room implementation)
//-----------------------------------------------------------------------------
ulpi_wrapper_v2 u_ulpi_wrapper (
    .ulpi_clk60_i       (ulpi_clk),
    .ulpi_rst_i         (~rst_n | ~phy_reset_done),

    // ULPI PHY interface
    .ulpi_data_out_i    (ulpi_data_in),
    .ulpi_data_in_o     (ulpi_data_out),
    .ulpi_dir_i         (ulpi_dir),
    .ulpi_nxt_i         (ulpi_nxt),
    .ulpi_stp_o         (ulpi_stp),

    // UTMI interface
    .utmi_data_in_o     (utmi_data_in),
    .utmi_data_out_i    (utmi_data_out),
    .utmi_txready_o     (utmi_txready),
    .utmi_txvalid_i     (utmi_txvalid),
    .utmi_rxvalid_o     (utmi_rxvalid),
    .utmi_rxactive_o    (utmi_rxactive),
    .utmi_rxerror_o     (utmi_rxerror),
    .utmi_linestate_o   (utmi_linestate),

    // Mode control
    .utmi_op_mode_i     (utmi_op_mode),
    .utmi_xcvrselect_i  (utmi_xcvrselect),
    .utmi_termselect_i  (utmi_termselect),
    .utmi_dppulldown_i  (utmi_dppulldown),
    .utmi_dmpulldown_i  (utmi_dmpulldown)
);

// Output enable for bidirectional data (drive when not receiving)
assign ulpi_data_oe = ~ulpi_dir;

//-----------------------------------------------------------------------------
// USB HS Negotiator (chirp FSM, bus reset detection)
// Clean-room MIT-licensed implementation per USB 2.0 spec 7.1.7.5
//-----------------------------------------------------------------------------
wire hs_enabled;
wire chirp_complete;

usb_hs_negotiator u_hs_negotiator (
    .clk                (ulpi_clk),
    .rst_n              (rst_n & phy_reset_done),

    // Configuration
    .enable             (1'b1),           // Always enabled
    .force_fs           (1'b0),           // Allow HS negotiation

    // UTMI Status
    .line_state         (utmi_linestate),
    .rx_active          (utmi_rxactive),

    // UTMI Control outputs
    .xcvr_select        (utmi_xcvrselect),
    .term_select        (utmi_termselect),
    .op_mode            (utmi_op_mode),
    .tx_valid           (hs_negotiator_tx_valid),
    .tx_data            (hs_negotiator_tx_data),

    // Status outputs
    .bus_reset          (bus_reset),
    .hs_enabled         (hs_enabled),
    .chirp_complete     (chirp_complete),
    .suspended          (usb_suspended)
);

// Speed output: 2'b00 = HS, 2'b01 = FS
assign current_speed = hs_enabled ? 2'b00 : 2'b01;
assign usb_speed = current_speed;
assign usb_connected = chirp_complete;  // Connected once negotiation complete

// D+/D- pulldowns (disabled for device mode)
assign utmi_dppulldown = 1'b0;
assign utmi_dmpulldown = 1'b0;

//-----------------------------------------------------------------------------
// USB Device Core (packet handling, endpoint routing)
//-----------------------------------------------------------------------------
usb_device_core_v2 u_device_core (
    .clk                (ulpi_clk),
    .rst_n              (rst_n & phy_reset_done & ~bus_reset),

    // UTMI interface
    .utmi_data_in       (utmi_data_in),
    .utmi_data_out      (utmi_data_out),
    .utmi_txready       (utmi_txready),
    .utmi_txvalid       (utmi_txvalid),
    .utmi_rxvalid       (utmi_rxvalid),
    .utmi_rxactive      (utmi_rxactive),

    // Configuration
    .device_address     (device_address),
    .high_speed         (current_speed == 2'b00),

    // Address/config changes
    .set_address        (set_address),
    .new_address        (new_address),
    .set_configured     (set_configured),
    .new_config         (device_config),

    // Control endpoint
    .setup_valid        (setup_valid),
    .setup_packet       (setup_packet),
    .ctrl_out_valid     (ctrl_out_valid),
    .ctrl_out_data      (ctrl_out_data),
    .ctrl_in_data       (ctrl_in_data),
    .ctrl_in_valid      (ctrl_in_valid),
    .ctrl_in_last       (ctrl_in_last),
    .ctrl_stall         (ctrl_stall),
    .ctrl_ack           (ctrl_ack),
    .ctrl_phase_done    (ctrl_phase_done),

    // Bulk endpoints
    .token_ep           (token_ep),
    .token_in           (token_in),
    .token_out          (token_out),
    .rx_data_valid      (rx_data_valid),
    .rx_data            (rx_data),
    .rx_last            (rx_last),
    .rx_crc_ok          (rx_crc_ok),
    .tx_data            (tx_data),
    .tx_valid           (tx_valid),
    .tx_last            (tx_last),
    .tx_ready           (tx_ready),
    .ep_stall           (ep_stall),
    .ep_nak             (ep_nak),

    // Frame info
    .frame_number       (usb_frame_number),
    .sof_valid          (usb_sof_valid)
);

// Mux handshakes from all bulk endpoints
assign ep_stall = (token_ep == 4'd1) ? (ep1_out_stall | ep1_in_stall) :
                  (token_ep == 4'd2) ? ep2_in_stall :
                  (token_ep == 4'd3) ? ep3_stall : 1'b0;
assign ep_nak = (token_ep == 4'd1) ? (ep1_out_nak | ep1_in_nak) :
                (token_ep == 4'd2) ? ep2_in_nak :
                (token_ep == 4'd3) ? ep3_nak : 1'b0;

// Mux TX data from IN endpoints
assign tx_data = (token_ep == 4'd1) ? ep1_in_tx_data :
                 (token_ep == 4'd2) ? ep2_in_tx_data :
                 (token_ep == 4'd3) ? ep3_tx_data : 8'd0;
assign tx_valid = (token_ep == 4'd1) ? ep1_in_tx_valid :
                  (token_ep == 4'd2) ? ep2_in_tx_valid :
                  (token_ep == 4'd3) ? ep3_tx_valid : 1'b0;
assign tx_last = (token_ep == 4'd1) ? ep1_in_tx_last :
                 (token_ep == 4'd2) ? ep2_in_tx_last :
                 (token_ep == 4'd3) ? ep3_tx_last : 1'b0;

//-----------------------------------------------------------------------------
// USB Control Endpoint (EP0)
//-----------------------------------------------------------------------------
usb_control_ep u_control_ep (
    .clk                (ulpi_clk),
    .rst_n              (rst_n & phy_reset_done & ~bus_reset),

    // From device core
    .setup_valid        (setup_valid),
    .setup_packet       (setup_packet),
    .out_valid          (ctrl_out_valid),
    .out_data           (ctrl_out_data),
    .in_data            (ctrl_in_data),
    .in_valid           (ctrl_in_valid),
    .in_last            (ctrl_in_last),
    .in_ready           (1'b1),  // TODO: proper flow control

    // Handshake
    .send_ack           (ctrl_ack),
    .send_stall         (ctrl_stall),
    .phase_done         (ctrl_phase_done),

    // Address/config
    .new_address        (new_address),
    .address_valid      (set_address),
    .new_config         (device_config),
    .config_valid       (set_configured),
    .current_address    (device_address),
    .current_config     (config_reg),

    // Descriptor ROM
    .desc_type          (desc_type),
    .desc_index         (desc_index),
    .desc_length        (desc_length),
    .desc_request       (desc_request),
    .desc_data          (desc_data),
    .desc_valid         (desc_valid),
    .desc_last          (desc_last),

    // KryoFlux vendor requests
    .personality        (personality_sel),
    .kf_cmd_valid       (kf_cmd_valid),
    .kf_cmd_request     (kf_cmd_request),
    .kf_cmd_value       (kf_cmd_value),
    .kf_cmd_index       (kf_cmd_index),
    .kf_cmd_length      (kf_cmd_length),
    .kf_response_data   (kf_response_data),
    .kf_response_valid  (kf_response_valid),
    .kf_response_last   (kf_response_last),
    .kf_out_data_valid  (),  // TODO: KF data out
    .kf_out_data        ()
);

//-----------------------------------------------------------------------------
// USB Descriptor ROM (5-personality)
//-----------------------------------------------------------------------------
usb_descriptor_rom u_descriptor_rom (
    .clk                (ulpi_clk),
    .rst_n              (rst_n),

    // Personality selection
    .personality        (personality_sel),

    // Request interface
    .desc_type          (desc_type),
    .desc_index         (desc_index),
    .desc_length        (desc_length),
    .desc_request       (desc_request),

    // Response interface
    .desc_data          (desc_data),
    .desc_valid         (desc_valid),
    .desc_last          (desc_last)
);

//-----------------------------------------------------------------------------
// USB Bulk Endpoint 1 OUT (Commands from host)
//-----------------------------------------------------------------------------
usb_bulk_ep #(
    .EP_NUM             (4'd1),
    .DIR_IN             (1'b0),      // OUT endpoint
    .MAX_PKT_HS         (512),
    .MAX_PKT_FS         (64)
) u_ep1_out (
    .clk                (ulpi_clk),
    .rst_n              (rst_n & ~bus_reset),

    .high_speed         (current_speed == 2'b00),

    .token_valid        (token_out),
    .token_in           (1'b0),
    .token_out          (token_out),
    .token_ep           (token_ep),

    .rx_data_valid      (rx_data_valid),
    .rx_data            (rx_data),
    .rx_last            (rx_last),
    .rx_crc_ok          (rx_crc_ok),
    .tx_data            (),
    .tx_valid           (),
    .tx_last            (),
    .tx_ready           (1'b0),

    .send_ack           (ep1_out_ack),
    .send_nak           (ep1_out_nak),
    .send_stall         (ep1_out_stall),
    .stall_ep           (1'b0),

    .fifo_rx_data       (ep1_out_fifo_data),
    .fifo_rx_valid      (ep1_out_fifo_valid),
    .fifo_rx_ready      (ep1_out_fifo_ready),
    .fifo_tx_data       (32'd0),
    .fifo_tx_valid      (1'b0),
    .fifo_tx_ready      (),

    .ep_busy            (),
    .bytes_pending      ()
);

//-----------------------------------------------------------------------------
// USB Bulk Endpoint 1 IN (Responses to host)
//-----------------------------------------------------------------------------
usb_bulk_ep #(
    .EP_NUM             (4'd1),
    .DIR_IN             (1'b1),      // IN endpoint
    .MAX_PKT_HS         (512),
    .MAX_PKT_FS         (64)
) u_ep1_in (
    .clk                (ulpi_clk),
    .rst_n              (rst_n & ~bus_reset),

    .high_speed         (current_speed == 2'b00),

    .token_valid        (token_in),
    .token_in           (token_in),
    .token_out          (1'b0),
    .token_ep           (token_ep),

    .rx_data_valid      (1'b0),
    .rx_data            (8'd0),
    .rx_last            (1'b0),
    .rx_crc_ok          (1'b0),
    .tx_data            (ep1_in_tx_data),
    .tx_valid           (ep1_in_tx_valid),
    .tx_last            (ep1_in_tx_last),
    .tx_ready           (tx_ready),

    .send_ack           (ep1_in_ack),
    .send_nak           (ep1_in_nak),
    .send_stall         (ep1_in_stall),
    .stall_ep           (1'b0),

    .fifo_rx_data       (),
    .fifo_rx_valid      (),
    .fifo_rx_ready      (1'b0),
    .fifo_tx_data       (ep1_in_fifo_data),
    .fifo_tx_valid      (ep1_in_fifo_valid),
    .fifo_tx_ready      (ep1_in_fifo_ready),

    .ep_busy            (),
    .bytes_pending      ()
);

//-----------------------------------------------------------------------------
// USB Bulk Endpoint 2 IN (Flux data streaming to host)
//-----------------------------------------------------------------------------
usb_bulk_ep #(
    .EP_NUM             (4'd2),
    .DIR_IN             (1'b1),      // IN endpoint
    .MAX_PKT_HS         (512),
    .MAX_PKT_FS         (64)
) u_ep2_in (
    .clk                (ulpi_clk),
    .rst_n              (rst_n & ~bus_reset),

    .high_speed         (current_speed == 2'b00),

    .token_valid        (token_in),
    .token_in           (token_in),
    .token_out          (1'b0),
    .token_ep           (token_ep),

    .rx_data_valid      (1'b0),
    .rx_data            (8'd0),
    .rx_last            (1'b0),
    .rx_crc_ok          (1'b0),
    .tx_data            (ep2_in_tx_data),
    .tx_valid           (ep2_in_tx_valid),
    .tx_last            (ep2_in_tx_last),
    .tx_ready           (tx_ready),

    .send_ack           (ep2_in_ack),
    .send_nak           (ep2_in_nak),
    .send_stall         (ep2_in_stall),
    .stall_ep           (1'b0),

    .fifo_rx_data       (),
    .fifo_rx_valid      (),
    .fifo_rx_ready      (1'b0),
    .fifo_tx_data       (ep2_in_fifo_data),
    .fifo_tx_valid      (ep2_in_fifo_valid),
    .fifo_tx_ready      (ep2_in_fifo_ready),

    .ep_busy            (),
    .bytes_pending      ()
);

//-----------------------------------------------------------------------------
// Protocol Handler Interface
//-----------------------------------------------------------------------------
// EP1 OUT → Protocol RX (commands from host)
assign proto_rx_data = ep1_out_fifo_data;
assign proto_rx_valid = ep1_out_fifo_valid;
assign ep1_out_fifo_ready = proto_rx_ready;

// Protocol TX → EP1 IN (responses to host)
assign ep1_in_fifo_data = proto_tx_data;
assign ep1_in_fifo_valid = proto_tx_valid;
assign proto_tx_ready = ep1_in_fifo_ready;

// Flux data → EP2 IN (streaming to host)
assign ep2_in_fifo_data = flux_data;
assign ep2_in_fifo_valid = flux_valid;
assign flux_ready = ep2_in_fifo_ready;

//-----------------------------------------------------------------------------
// USB CDC ACM Debug Console (EP3 IN/OUT)
//-----------------------------------------------------------------------------
usb_cdc_ep u_cdc_ep (
    .clk                    (ulpi_clk),
    .rst_n                  (rst_n & ~bus_reset),

    .high_speed             (current_speed == 2'b00),

    // Control interface - CDC class requests
    .ctrl_setup_valid       (setup_valid),
    .ctrl_request           (setup_packet[55:48]),  // bRequest
    .ctrl_value             ({setup_packet[39:32], setup_packet[47:40]}),
    .ctrl_index             ({setup_packet[23:16], setup_packet[31:24]}),
    .ctrl_length            ({setup_packet[7:0], setup_packet[15:8]}),
    .ctrl_response_data     (cdc_ctrl_response_data),
    .ctrl_response_valid    (cdc_ctrl_response_valid),
    .ctrl_response_last     (cdc_ctrl_response_last),
    .ctrl_out_valid         (ctrl_out_valid),
    .ctrl_out_data          (ctrl_out_data),
    .ctrl_request_handled   (cdc_ctrl_request_handled),

    // Bulk data interface
    .token_in               (token_in),
    .token_out              (token_out),
    .token_ep               (token_ep),
    .rx_data                (rx_data),
    .rx_valid               (rx_data_valid),
    .rx_last                (rx_last),
    .tx_data                (ep3_tx_data),
    .tx_valid               (ep3_tx_valid),
    .tx_last                (ep3_tx_last),
    .tx_ready               (tx_ready),
    .send_ack               (cdc_send_ack),
    .send_nak               (cdc_send_nak),

    // Debug FIFO interface (directly to top-level ports)
    .debug_tx_data          (debug_tx_data),
    .debug_tx_valid         (debug_tx_valid),
    .debug_tx_ready         (debug_tx_ready),
    .debug_rx_data          (debug_rx_data),
    .debug_rx_valid         (debug_rx_valid),
    .debug_rx_ready         (debug_rx_ready),

    // Status
    .dtr_active             (cdc_dtr_active),
    .rts_active             (cdc_rts_active),
    .cdc_configured         (cdc_configured),
    .line_coding_baud       (cdc_line_coding_baud)
);

// Route CDC status to outputs
assign debug_dtr_active = cdc_dtr_active;

// CDC endpoint handshakes (combined for bidirectional EP3)
assign ep3_ack = cdc_send_ack;
assign ep3_nak = cdc_send_nak;
assign ep3_stall = 1'b0;  // No STALL support in CDC endpoint

//-----------------------------------------------------------------------------
// Output Assignments
//-----------------------------------------------------------------------------

// Personality switching
// For now, personality is static (no dynamic switching implemented)
assign switch_complete_int = 1'b1;  // Always complete (no switching delay)
assign active_personality_int = personality_sel;  // Direct passthrough
assign switch_complete = switch_complete_int;
assign active_personality = active_personality_int;

// Flux engine control
// TODO: Wire these from the active protocol handler based on personality
assign flux_capture_start_int = 1'b0;
assign flux_capture_stop_int = 1'b0;
assign flux_sample_rate_int = 8'd0;
assign flux_capture_start = flux_capture_start_int;
assign flux_capture_stop = flux_capture_stop_int;
assign flux_sample_rate = flux_sample_rate_int;

// Drive control outputs
// TODO: Implement personality mux to route from active protocol handler
assign drive_select_int = 4'b0001;  // Default to drive 0
assign motor_on_int = 1'b0;
assign head_select_int = 1'b0;
assign track_target_int = 8'd0;
assign seek_start_int = 1'b0;
assign drive_select = drive_select_int;
assign motor_on = motor_on_int;
assign head_select = head_select_int;
assign track_target = track_target_int;
assign seek_start = seek_start_int;

// MSC Block Device Interface
// TODO: Wire from msc_protocol handler when personality == 4
assign msc_lun_int = 4'd0;
assign msc_lba_int = 32'd0;
assign msc_block_count_int = 16'd0;
assign msc_read_start_int = 1'b0;
assign msc_write_start_int = 1'b0;
assign msc_read_ready_int = 1'b0;
assign msc_write_data_int = 32'd0;
assign msc_write_valid_int = 1'b0;
assign msc_lun = msc_lun_int;
assign msc_lba = msc_lba_int;
assign msc_block_count = msc_block_count_int;
assign msc_read_start = msc_read_start_int;
assign msc_write_start = msc_write_start_int;
assign msc_read_ready = msc_read_ready_int;
assign msc_write_data = msc_write_data_int;
assign msc_write_valid = msc_write_valid_int;

// Diagnostics Interface
// TODO: Wire from native_protocol handler when personality == 3
assign diag_cmd_int = 32'd0;
assign diag_cmd_valid_int = 1'b0;
assign diag_cmd = diag_cmd_int;
assign diag_cmd_valid = diag_cmd_valid_int;

// Extended Status
// TODO: Implement proper error detection and byte counting
assign usb_error_int = 1'b0;  // No errors yet
assign usb_state_int = {6'b0, usb_configured, usb_connected};  // Basic state
assign protocol_state_int = 8'd0;  // TODO: Get from active protocol handler
assign rx_byte_count_int = 32'd0;  // TODO: Implement RX byte counter
assign tx_byte_count_int = 32'd0;  // TODO: Implement TX byte counter
assign usb_error = usb_error_int;
assign usb_state = usb_state_int;
assign protocol_state = protocol_state_int;
assign rx_byte_count = rx_byte_count_int;
assign tx_byte_count = tx_byte_count_int;

// MSC Configuration Status
// TODO: Wire from drive_lun_mapper when MSC is integrated
assign msc_drive_present_int = 4'b0001;  // Default: FDD0 present
assign msc_media_changed_int = 4'b0000;  // No media changes yet
assign msc_drive_present_out = msc_drive_present_int;
assign msc_media_changed_out = msc_media_changed_int;

endmodule
