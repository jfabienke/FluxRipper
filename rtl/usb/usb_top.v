//-----------------------------------------------------------------------------
// usb_top.v
// FluxRipper USB Subsystem Top Level
//
// Created: 2025-12-05 18:35
// Modified: 2025-12-05 21:15 - Fixed MSC module wiring, added SCSI engine/buffer/mapper
//
// Integrates all USB components:
//   - FT601 interface (physical layer)
//   - Personality multiplexer (protocol routing)
//   - Protocol handlers (GW, HxC, KF, Native, MSC+Raw)
//
// Architecture:
//                                    ┌──────────────────┐
//   FT601 Chip ◄──────────────────► │ ft601_interface  │
//                                    └────────┬─────────┘
//                                             │ unified rx/tx
//                                    ┌────────▼─────────┐
//                                    │ personality_mux  │
//                                    └───┬───┬───┬───┬──┘
//                                        │   │   │   │
//            ┌───────────────────────────┘   │   │   └─────────────────────┐
//            ▼                               ▼   ▼                         ▼
//     ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐
//     │ gw_protocol │  │hfe_protocol │  │ kf_protocol │  │   native_protocol   │
//     │ (Pers 0)    │  │  (Pers 1)   │  │  (Pers 2)   │  │     (Pers 3)        │
//     └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘
//                                                              │
//                                         ┌────────────────────┴───────────────┐
//                                         ▼                                    ▼
//                                  ┌─────────────┐                    ┌─────────────┐
//                                  │msc_protocol │                    │raw_interface│
//                                  │  (MSC BBB)  │                    │ (Pers 4 Raw)│
//                                  └─────────────┘                    └─────────────┘
//
//-----------------------------------------------------------------------------

module usb_top #(
    parameter SYS_CLK_FREQ      = 100_000_000,
    parameter FIFO_DEPTH        = 512,
    parameter DEFAULT_PERS      = 4,               // MSC+Raw as default
    parameter NUM_PERSONALITIES = 5
)(
    // System
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // FT601 Physical Interface (directly to chip)
    //=========================================================================
    input  wire        ft_clk,
    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    input  wire        ft_rxf_n,
    input  wire        ft_txe_n,
    output wire        ft_rd_n,
    output wire        ft_wr_n,
    output wire        ft_oe_n,
    output wire        ft_siwu_n,
    input  wire        ft_wakeup_n,

    //=========================================================================
    // Personality Selection
    //=========================================================================
    input  wire [2:0]  personality_sel,          // Requested personality
    input  wire        personality_switch,       // Request switch
    output wire        switch_complete,          // Switch completed
    output wire [2:0]  active_personality,       // Current active personality

    //=========================================================================
    // Flux Engine Interface (shared across personalities)
    //=========================================================================
    // Flux capture data from hardware
    input  wire [31:0] flux_data,
    input  wire        flux_valid,
    output wire        flux_ready,
    input  wire        flux_index,               // Index pulse

    // Flux engine control
    output wire        flux_capture_start,
    output wire        flux_capture_stop,
    output wire [7:0]  flux_sample_rate,         // Sample rate selector
    input  wire        flux_capturing,

    //=========================================================================
    // Drive Interface
    //=========================================================================
    output wire [3:0]  drive_select,             // Drive 0-3 selection
    output wire        motor_on,
    output wire        head_select,              // 0=side 0, 1=side 1
    output wire [7:0]  track_target,
    output wire        seek_start,
    input  wire        seek_complete,
    input  wire [7:0]  current_track,

    // Drive status
    input  wire        disk_present,
    input  wire        write_protect,
    input  wire        track_00,
    input  wire        motor_spinning,

    //=========================================================================
    // MSC Block Device Interface (for Personality 4)
    //=========================================================================
    output wire [3:0]  msc_lun,                  // Logical Unit Number
    output wire [31:0] msc_lba,                  // Logical Block Address
    output wire [15:0] msc_block_count,
    output wire        msc_read_start,
    output wire        msc_write_start,
    input  wire        msc_ready,
    input  wire        msc_error,

    // Sector data
    input  wire [31:0] msc_read_data,
    input  wire        msc_read_valid,
    output wire        msc_read_ready,
    output wire [31:0] msc_write_data,
    output wire        msc_write_valid,
    input  wire        msc_write_ready,

    //=========================================================================
    // Diagnostics Interface
    //=========================================================================
    output wire [31:0] diag_cmd,
    output wire        diag_cmd_valid,
    input  wire [31:0] diag_response,
    input  wire        diag_response_valid,

    //=========================================================================
    // Status
    //=========================================================================
    output wire        usb_connected,
    output wire        usb_error,
    output wire [7:0]  usb_state,
    output wire [7:0]  protocol_state,
    output wire [31:0] rx_byte_count,
    output wire [31:0] tx_byte_count,

    //=========================================================================
    // MSC Configuration Interface (from msc_config_regs)
    //=========================================================================
    input  wire        msc_config_valid,
    input  wire [15:0] msc_fdd0_sectors,
    input  wire [15:0] msc_fdd1_sectors,
    input  wire [31:0] msc_hdd0_sectors,
    input  wire [31:0] msc_hdd1_sectors,
    input  wire [3:0]  msc_drive_ready_in,
    input  wire [3:0]  msc_drive_wp_in,

    // MSC Status Outputs (to msc_config_regs)
    output wire [3:0]  msc_drive_present_out,
    output wire [3:0]  msc_media_changed_out
);

    //=========================================================================
    // Internal Wires
    //=========================================================================

    // FT601 interface outputs
    wire [31:0] ep0_rx_data, ep1_rx_data;
    wire        ep0_rx_valid, ep1_rx_valid;
    wire        ep0_rx_ready, ep1_rx_ready;
    wire [31:0] ep0_tx_data;
    wire        ep0_tx_valid, ep0_tx_ready;
    wire [31:0] ep2_tx_data_int, ep3_tx_data;
    wire        ep2_tx_valid_int, ep3_tx_valid;
    wire        ep2_tx_ready, ep3_tx_ready;

    // Unified personality mux interface
    wire [31:0] unified_rx_data;
    wire        unified_rx_valid;
    wire        unified_rx_ready;
    wire [31:0] unified_tx_data;
    wire        unified_tx_valid;
    wire        unified_tx_ready;

    // Personality mux <-> protocol handler interfaces
    // Greaseweazle (Personality 0)
    wire [31:0] gw_rx_data, gw_tx_data;
    wire        gw_rx_valid, gw_tx_valid;
    wire        gw_rx_ready, gw_tx_ready;
    wire [7:0]  gw_state;

    // HxC (Personality 1)
    wire [31:0] hfe_rx_data, hfe_tx_data;
    wire        hfe_rx_valid, hfe_tx_valid;
    wire        hfe_rx_ready, hfe_tx_ready;
    wire [7:0]  hfe_state;

    // KryoFlux (Personality 2)
    wire [31:0] kf_rx_data, kf_tx_data;
    wire        kf_rx_valid, kf_tx_valid;
    wire        kf_rx_ready, kf_tx_ready;
    wire [7:0]  kf_state;

    // Native FluxRipper (Personality 3)
    wire [31:0] native_rx_data, native_tx_data;
    wire        native_rx_valid, native_tx_valid;
    wire        native_rx_ready, native_tx_ready;
    wire [7:0]  native_state;

    // MSC + Raw (Personality 4)
    wire [31:0] msc_rx_data, msc_tx_data;
    wire        msc_rx_valid, msc_tx_valid;
    wire        msc_rx_ready, msc_tx_ready;
    wire [7:0]  msc_state;

    // Personality mux status
    wire [7:0]  mux_state;
    wire        personality_valid;
    wire [7:0]  active_protocol_state;

    // Statistics
    wire [31:0] ft_rx_count, ft_tx_count;
    wire [8:0]  rx_fifo_level, tx_fifo_level;

    //=========================================================================
    // MSC Subsystem Internal Wires
    //=========================================================================

    // msc_protocol <-> msc_scsi_engine
    wire [127:0] msc_scsi_cdb;
    wire [7:0]   msc_scsi_cdb_length;
    wire [2:0]   msc_scsi_lun;
    wire         msc_scsi_cmd_valid;
    wire         msc_scsi_cmd_ready;
    wire [7:0]   msc_scsi_status;
    wire         msc_scsi_status_valid;
    wire         msc_scsi_status_ready;
    wire         msc_scsi_data_out;
    wire         msc_scsi_data_in;
    wire [31:0]  msc_scsi_xfer_length;
    wire         msc_scsi_xfer_done;
    wire [31:0]  msc_scsi_residue;

    // msc_protocol <-> msc_sector_buffer
    wire [31:0]  msc_buf_wr_data;
    wire         msc_buf_wr_valid;
    wire         msc_buf_wr_ready;
    wire [31:0]  msc_buf_rd_data;
    wire         msc_buf_rd_valid;
    wire         msc_buf_rd_ready;

    // msc_scsi_engine -> response data (for INQUIRY, READ_CAPACITY, etc.)
    wire [31:0]  msc_resp_data;
    wire         msc_resp_valid;
    wire         msc_resp_ready;
    wire [15:0]  msc_resp_length;

    // msc_scsi_engine <-> drive_lun_mapper
    wire [2:0]   msc_drive_lun;
    wire         msc_drive_read_req;
    wire         msc_drive_write_req;
    wire [31:0]  msc_drive_lba;
    wire [15:0]  msc_drive_sector_count;
    wire         msc_drive_ready;
    wire         msc_drive_done;
    wire         msc_drive_error;
    wire         msc_drive_motor_on;
    wire         msc_drive_motor_off;

    // drive_lun_mapper -> FDD HAL
    wire [1:0]   msc_fdd_select;
    wire [31:0]  msc_fdd_lba;
    wire [15:0]  msc_fdd_count;
    wire         msc_fdd_read;
    wire         msc_fdd_write;

    // drive_lun_mapper -> HDD HAL
    wire [1:0]   msc_hdd_select;
    wire [31:0]  msc_hdd_lba;
    wire [15:0]  msc_hdd_count;
    wire         msc_hdd_read;
    wire         msc_hdd_write;

    // LUN configuration (drive_lun_mapper -> scsi_engine)
    wire [3:0]   msc_lun_present;
    wire [3:0]   msc_lun_removable;
    wire [3:0]   msc_lun_readonly;
    wire [31:0]  msc_lun_capacity [0:3];
    wire [15:0]  msc_lun_block_size [0:3];

    // Sector buffer control
    wire         msc_transfer_start;
    wire         msc_transfer_dir;
    wire [15:0]  msc_sector_count_buf;
    wire         msc_transfer_done_buf;
    wire [15:0]  msc_sectors_completed;

    // MSC status outputs
    wire         msc_transfer_active;
    wire         msc_transfer_done_proto;
    wire [31:0]  msc_cbw_count;
    wire [31:0]  msc_csw_count;
    wire [7:0]   msc_last_error;
    wire [7:0]   msc_scsi_engine_state;
    wire [7:0]   msc_mapper_state;

    //=========================================================================
    // FT601 Interface Instance
    //=========================================================================

    ft601_interface #(
        .SYS_CLK_FREQ  (SYS_CLK_FREQ),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .NUM_ENDPOINTS (4)
    ) u_ft601 (
        .sys_clk       (clk),
        .sys_rst_n     (rst_n),

        // FT601 physical pins
        .ft_clk        (ft_clk),
        .ft_data       (ft_data),
        .ft_be         (ft_be),
        .ft_rxf_n      (ft_rxf_n),
        .ft_txe_n      (ft_txe_n),
        .ft_rd_n       (ft_rd_n),
        .ft_wr_n       (ft_wr_n),
        .ft_oe_n       (ft_oe_n),
        .ft_siwu_n     (ft_siwu_n),
        .ft_wakeup_n   (ft_wakeup_n),

        // Endpoint 0 - Control
        .ep0_rx_data   (ep0_rx_data),
        .ep0_rx_valid  (ep0_rx_valid),
        .ep0_rx_ready  (ep0_rx_ready),
        .ep0_tx_data   (ep0_tx_data),
        .ep0_tx_valid  (ep0_tx_valid),
        .ep0_tx_ready  (ep0_tx_ready),

        // Endpoint 1 - Bulk OUT (commands)
        .ep1_rx_data   (ep1_rx_data),
        .ep1_rx_valid  (ep1_rx_valid),
        .ep1_rx_ready  (unified_rx_ready),  // Controlled by personality mux

        // Endpoint 2 - Bulk IN (flux data)
        .ep2_tx_data   (unified_tx_data),   // From personality mux
        .ep2_tx_valid  (unified_tx_valid),
        .ep2_tx_ready  (ep2_tx_ready),

        // Endpoint 3 - Bulk IN (status/aux)
        .ep3_tx_data   (ep3_tx_data),
        .ep3_tx_valid  (ep3_tx_valid),
        .ep3_tx_ready  (ep3_tx_ready),

        // Status
        .usb_connected (usb_connected),
        .usb_suspended (),
        .active_endpoint(),
        .rx_count      (ft_rx_count),
        .tx_count      (ft_tx_count),

        // Composite device tracking
        .usb_interface_num  (),
        .usb_interface_valid(),
        .rx_fifo_level (rx_fifo_level),
        .tx_fifo_level (tx_fifo_level),

        // Personality integration
        .personality_sel   (active_personality),
        .personality_valid (personality_valid),
        .unified_rx_data   (unified_rx_data),
        .unified_rx_valid  (unified_rx_valid),
        .unified_rx_ready  (unified_rx_ready),
        .unified_tx_data   (),              // We drive ep2 directly
        .unified_tx_valid  (),
        .unified_tx_ready  (unified_tx_ready)
    );

    //=========================================================================
    // USB Personality Multiplexer
    //=========================================================================

    usb_personality_mux #(
        .NUM_PERSONALITIES   (NUM_PERSONALITIES),
        .DEFAULT_PERSONALITY (DEFAULT_PERS)
    ) u_personality_mux (
        .clk               (clk),
        .rst_n             (rst_n),

        // Personality selection
        .personality_sel   (personality_sel),
        .personality_switch(personality_switch),
        .switch_complete   (switch_complete),
        .active_personality(active_personality),

        // FT601 interface (unified paths)
        .usb_rx_data       (unified_rx_data),
        .usb_rx_valid      (unified_rx_valid),
        .usb_rx_ready      (unified_rx_ready),
        .usb_tx_data       (unified_tx_data),
        .usb_tx_valid      (unified_tx_valid),
        .usb_tx_ready      (unified_tx_ready),

        // Greaseweazle (Personality 0)
        .gw_rx_data        (gw_rx_data),
        .gw_rx_valid       (gw_rx_valid),
        .gw_rx_ready       (gw_rx_ready),
        .gw_tx_data        (gw_tx_data),
        .gw_tx_valid       (gw_tx_valid),
        .gw_tx_ready       (gw_tx_ready),
        .gw_state          (gw_state),

        // HxC (Personality 1)
        .hfe_rx_data       (hfe_rx_data),
        .hfe_rx_valid      (hfe_rx_valid),
        .hfe_rx_ready      (hfe_rx_ready),
        .hfe_tx_data       (hfe_tx_data),
        .hfe_tx_valid      (hfe_tx_valid),
        .hfe_tx_ready      (hfe_tx_ready),
        .hfe_state         (hfe_state),

        // KryoFlux (Personality 2)
        .kf_rx_data        (kf_rx_data),
        .kf_rx_valid       (kf_rx_valid),
        .kf_rx_ready       (kf_rx_ready),
        .kf_tx_data        (kf_tx_data),
        .kf_tx_valid       (kf_tx_valid),
        .kf_tx_ready       (kf_tx_ready),
        .kf_state          (kf_state),

        // Native FluxRipper (Personality 3)
        .native_rx_data    (native_rx_data),
        .native_rx_valid   (native_rx_valid),
        .native_rx_ready   (native_rx_ready),
        .native_tx_data    (native_tx_data),
        .native_tx_valid   (native_tx_valid),
        .native_tx_ready   (native_tx_ready),
        .native_state      (native_state),

        // MSC + Raw (Personality 4)
        .msc_rx_data       (msc_rx_data),
        .msc_rx_valid      (msc_rx_valid),
        .msc_rx_ready      (msc_rx_ready),
        .msc_tx_data       (msc_tx_data),
        .msc_tx_valid      (msc_tx_valid),
        .msc_tx_ready      (msc_tx_ready),
        .msc_state         (msc_state),

        // Status
        .mux_state         (mux_state),
        .personality_valid (personality_valid),
        .active_protocol_state(active_protocol_state)
    );

    //=========================================================================
    // Greaseweazle Protocol Handler (Personality 0)
    //=========================================================================

    // Internal signals for GW drive control
    wire [3:0]  gw_drive_select;
    wire        gw_motor_on;
    wire        gw_head_select;
    wire [7:0]  gw_track_target;
    wire        gw_seek_start;
    wire        gw_capture_start, gw_capture_stop;
    wire [7:0]  gw_sample_rate;

    gw_protocol u_gw_protocol (
        .clk           (clk),
        .rst_n         (rst_n),

        // USB interface
        .rx_data       (gw_rx_data),
        .rx_valid      (gw_rx_valid),
        .rx_ready      (gw_rx_ready),
        .tx_data       (gw_tx_data),
        .tx_valid      (gw_tx_valid),
        .tx_ready      (gw_tx_ready),

        // Flux interface
        .flux_data     (flux_data),
        .flux_valid    (flux_valid && (active_personality == 3'd0)),
        .flux_ready    (),
        .flux_index    (flux_index),

        // Drive control
        .drive_select  (gw_drive_select),
        .motor_on      (gw_motor_on),
        .head_select   (gw_head_select),
        .track         (gw_track_target),
        .seek_start    (gw_seek_start),
        .seek_complete (seek_complete),
        .track_00      (track_00),

        // Drive status
        .disk_present  (disk_present),
        .write_protect (write_protect),

        // Capture control
        .capture_start (gw_capture_start),
        .capture_stop  (gw_capture_stop),
        .sample_rate   (gw_sample_rate),
        .capturing     (flux_capturing),

        // Status
        .state         (gw_state)
    );

    //=========================================================================
    // HxC Protocol Handler (Personality 1)
    //=========================================================================

    wire [3:0]  hfe_drive_select;
    wire        hfe_motor_on;
    wire        hfe_head_select;
    wire [7:0]  hfe_track_target;
    wire        hfe_seek_start;
    wire        hfe_capture_start, hfe_capture_stop;
    wire [7:0]  hfe_sample_rate;

    hfe_protocol u_hfe_protocol (
        .clk           (clk),
        .rst_n         (rst_n),

        // USB interface
        .rx_data       (hfe_rx_data),
        .rx_valid      (hfe_rx_valid),
        .rx_ready      (hfe_rx_ready),
        .tx_data       (hfe_tx_data),
        .tx_valid      (hfe_tx_valid),
        .tx_ready      (hfe_tx_ready),

        // Flux interface
        .flux_data     (flux_data),
        .flux_valid    (flux_valid && (active_personality == 3'd1)),
        .flux_ready    (),
        .flux_index    (flux_index),

        // Drive control
        .drive_select  (hfe_drive_select),
        .motor_on      (hfe_motor_on),
        .head_select   (hfe_head_select),
        .track         (hfe_track_target),
        .seek_start    (hfe_seek_start),
        .seek_complete (seek_complete),
        .track_00      (track_00),

        // Drive status
        .disk_present  (disk_present),
        .write_protect (write_protect),

        // Capture control
        .capture_start (hfe_capture_start),
        .capture_stop  (hfe_capture_stop),
        .sample_rate   (hfe_sample_rate),
        .capturing     (flux_capturing),

        // Status
        .state         (hfe_state)
    );

    //=========================================================================
    // KryoFlux Protocol Handler (Personality 2)
    //=========================================================================

    wire [3:0]  kf_drive_select;
    wire        kf_motor_on;
    wire        kf_head_select;
    wire [7:0]  kf_track_target;
    wire        kf_seek_start;
    wire        kf_capture_start, kf_capture_stop;
    wire [7:0]  kf_sample_rate;

    kf_protocol u_kf_protocol (
        .clk           (clk),
        .rst_n         (rst_n),

        // USB interface
        .rx_data       (kf_rx_data),
        .rx_valid      (kf_rx_valid),
        .rx_ready      (kf_rx_ready),
        .tx_data       (kf_tx_data),
        .tx_valid      (kf_tx_valid),
        .tx_ready      (kf_tx_ready),

        // Flux interface (300 MHz timestamps)
        .flux_data     (flux_data),
        .flux_valid    (flux_valid && (active_personality == 3'd2)),
        .flux_ready    (),
        .flux_index    (flux_index),

        // Drive control
        .drive_select  (kf_drive_select),
        .motor_on      (kf_motor_on),
        .head_select   (kf_head_select),
        .track         (kf_track_target),
        .seek_start    (kf_seek_start),
        .seek_complete (seek_complete),
        .current_track (current_track),
        .track_00      (track_00),

        // Drive status
        .disk_present  (disk_present),
        .write_protect (write_protect),

        // Capture control
        .capture_start (kf_capture_start),
        .capture_stop  (kf_capture_stop),
        .capturing     (flux_capturing),

        // Status
        .state         (kf_state)
    );

    //=========================================================================
    // Native FluxRipper Protocol Handler (Personality 3)
    //=========================================================================

    wire [3:0]  native_drive_select;
    wire        native_motor_on;
    wire        native_head_select;
    wire [7:0]  native_track_target;
    wire        native_seek_start;
    wire        native_capture_start, native_capture_stop;
    wire [7:0]  native_sample_rate;

    native_protocol u_native_protocol (
        .clk           (clk),
        .rst_n         (rst_n),

        // USB interface
        .rx_data       (native_rx_data),
        .rx_valid      (native_rx_valid),
        .rx_ready      (native_rx_ready),
        .tx_data       (native_tx_data),
        .tx_valid      (native_tx_valid),
        .tx_ready      (native_tx_ready),

        // Flux interface (full 300 MHz resolution)
        .flux_data     (flux_data),
        .flux_valid    (flux_valid && (active_personality == 3'd3)),
        .flux_ready    (),
        .flux_index    (flux_index),

        // Drive control
        .drive_select  (native_drive_select),
        .motor_on      (native_motor_on),
        .head_select   (native_head_select),
        .track         (native_track_target),
        .seek_start    (native_seek_start),
        .seek_complete (seek_complete),
        .current_track (current_track),
        .track_00      (track_00),

        // Drive status
        .disk_present  (disk_present),
        .write_protect (write_protect),
        .motor_spinning(motor_spinning),

        // Capture control
        .capture_start (native_capture_start),
        .capture_stop  (native_capture_stop),
        .capturing     (flux_capturing),

        // Diagnostics
        .diag_cmd          (diag_cmd),
        .diag_cmd_valid    (diag_cmd_valid),
        .diag_response     (diag_response),
        .diag_response_valid(diag_response_valid),

        // Status
        .state         (native_state)
    );

    //=========================================================================
    // MSC + Raw Protocol Handler (Personality 4)
    //=========================================================================
    //
    // Data Flow:
    //   USB <-> msc_protocol <-> msc_scsi_engine <-> drive_lun_mapper <-> HAL
    //                   |
    //                   +---> msc_sector_buffer <-> HAL
    //

    wire [3:0]  msc_drive_select_int;
    wire        msc_motor_on;
    wire        msc_head_select;
    wire [7:0]  msc_track_target;
    wire        msc_seek_start;
    wire        msc_capture_start, msc_capture_stop;
    wire [7:0]  msc_sample_rate;

    //-------------------------------------------------------------------------
    // MSC Protocol Handler (BBB - Bulk Only Transport)
    // Receives CBW from USB, sends CSW to USB
    // Routes SCSI commands to SCSI engine
    //-------------------------------------------------------------------------

    msc_protocol u_msc_protocol (
        .clk              (clk),
        .rst_n            (rst_n),

        // USB interface (from personality mux)
        .usb_rx_data      (msc_rx_data),
        .usb_rx_valid     (msc_rx_valid),
        .usb_rx_ready     (msc_rx_ready),
        .usb_tx_data      (msc_tx_data),
        .usb_tx_valid     (msc_tx_valid),
        .usb_tx_ready     (msc_tx_ready),

        // SCSI Engine Interface
        .scsi_cdb         (msc_scsi_cdb),
        .scsi_cdb_length  (msc_scsi_cdb_length),
        .scsi_lun         (msc_scsi_lun),
        .scsi_cmd_valid   (msc_scsi_cmd_valid),
        .scsi_cmd_ready   (msc_scsi_cmd_ready),
        .scsi_status      (msc_scsi_status),
        .scsi_status_valid(msc_scsi_status_valid),
        .scsi_status_ready(msc_scsi_status_ready),
        .scsi_data_out    (msc_scsi_data_out),
        .scsi_data_in     (msc_scsi_data_in),
        .scsi_xfer_length (msc_scsi_xfer_length),
        .scsi_xfer_done   (msc_scsi_xfer_done),
        .scsi_residue     (msc_scsi_residue),

        // Sector Buffer Interface
        .buf_wr_data      (msc_buf_wr_data),
        .buf_wr_valid     (msc_buf_wr_valid),
        .buf_wr_ready     (msc_buf_wr_ready),
        .buf_rd_data      (msc_buf_rd_data),
        .buf_rd_valid     (msc_buf_rd_valid),
        .buf_rd_ready     (msc_buf_rd_ready),

        // Status
        .transfer_active  (msc_transfer_active),
        .transfer_done    (msc_transfer_done_proto),
        .msc_state        (msc_state),
        .cbw_count        (msc_cbw_count),
        .csw_count        (msc_csw_count),
        .last_error       (msc_last_error)
    );

    //-------------------------------------------------------------------------
    // SCSI Engine - Decodes SCSI commands and executes them
    //-------------------------------------------------------------------------

    msc_scsi_engine #(
        .MAX_LUNS         (4)
    ) u_msc_scsi_engine (
        .clk              (clk),
        .rst_n            (rst_n),

        // Command Interface (from msc_protocol)
        .scsi_cdb         (msc_scsi_cdb),
        .scsi_cdb_length  (msc_scsi_cdb_length),
        .scsi_lun         (msc_scsi_lun),
        .scsi_cmd_valid   (msc_scsi_cmd_valid),
        .scsi_cmd_ready   (msc_scsi_cmd_ready),

        // Status output (to msc_protocol)
        .scsi_status      (msc_scsi_status),
        .scsi_status_valid(msc_scsi_status_valid),
        .scsi_status_ready(msc_scsi_status_ready),

        // Data transfer signaling
        .scsi_data_out    (msc_scsi_data_out),
        .scsi_data_in     (msc_scsi_data_in),
        .scsi_xfer_length (msc_scsi_xfer_length),
        .scsi_xfer_done   (msc_scsi_xfer_done),
        .scsi_residue     (msc_scsi_residue),

        // Response Data Interface (for INQUIRY, READ_CAPACITY, etc.)
        .resp_data        (msc_resp_data),
        .resp_valid       (msc_resp_valid),
        .resp_ready       (msc_resp_ready),
        .resp_length      (msc_resp_length),

        // Drive Control Interface (to drive_lun_mapper)
        .drive_lun        (msc_drive_lun),
        .drive_read_req   (msc_drive_read_req),
        .drive_write_req  (msc_drive_write_req),
        .drive_lba        (msc_drive_lba),
        .drive_sector_count(msc_drive_sector_count),
        .drive_ready      (msc_drive_ready),
        .drive_done       (msc_drive_done),
        .drive_error      (msc_drive_error),

        // Motor control
        .drive_motor_on   (msc_drive_motor_on),
        .drive_motor_off  (msc_drive_motor_off),

        // LUN Configuration (from drive_lun_mapper)
        .lun_present      (msc_lun_present),
        .lun_removable    (msc_lun_removable),
        .lun_readonly     (msc_lun_readonly),
        .lun_capacity     (msc_lun_capacity),
        .lun_block_size   (msc_lun_block_size),

        // Status
        .engine_state     (msc_scsi_engine_state),
        .last_opcode      (),
        .sense_key        (),
        .asc              (),
        .ascq             ()
    );

    //-------------------------------------------------------------------------
    // Sector Buffer - Double-buffered FIFO for sector streaming
    //-------------------------------------------------------------------------

    msc_sector_buffer #(
        .SECTOR_SIZE      (512),
        .BUFFER_COUNT     (2),
        .WORD_WIDTH       (32)
    ) u_msc_sector_buffer (
        .clk              (clk),
        .rst_n            (rst_n),

        // USB Side Interface (from/to msc_protocol)
        .usb_wr_data      (msc_buf_wr_data),
        .usb_wr_valid     (msc_buf_wr_valid),
        .usb_wr_ready     (msc_buf_wr_ready),
        .usb_rd_data      (msc_buf_rd_data),
        .usb_rd_valid     (msc_buf_rd_valid),
        .usb_rd_ready     (msc_buf_rd_ready),

        // HAL/Drive Side Interface
        // For WRITE commands: HAL reads data from buffer to write to drive
        .hal_rd_data      (msc_write_data),     // OUTPUT to HAL - data to drive
        .hal_rd_valid     (msc_write_valid),    // OUTPUT to HAL - valid signal
        .hal_rd_ready     (msc_write_ready),    // INPUT from HAL - ready signal
        .hal_sector_ready (),

        // For READ commands: HAL writes data to buffer after reading from drive
        .hal_wr_data      (msc_read_data),      // INPUT from HAL - data from drive
        .hal_wr_valid     (msc_read_valid),     // INPUT from HAL - valid signal
        .hal_wr_ready     (msc_read_ready),     // OUTPUT to HAL - ready signal

        // Control
        .transfer_start   (msc_transfer_start),
        .transfer_dir     (msc_transfer_dir),
        .sector_count     (msc_sector_count_buf),
        .transfer_done    (msc_transfer_done_buf),
        .sectors_completed(msc_sectors_completed),

        // Status
        .usb_fifo_level   (),
        .hal_fifo_level   (),
        .buffer_empty     (),
        .buffer_full      ()
    );

    //-------------------------------------------------------------------------
    // Drive LUN Mapper - Maps LUNs to physical FDD/HDD drives
    //-------------------------------------------------------------------------

    // FDD geometry - use config if valid, else default to 1.44MB
    wire [15:0] fdd_capacity_arr [0:1];
    wire [15:0] fdd_block_size_arr [0:1];
    assign fdd_capacity_arr[0] = msc_config_valid ? msc_fdd0_sectors : 16'd2880;
    assign fdd_capacity_arr[1] = msc_config_valid ? msc_fdd1_sectors : 16'd2880;
    assign fdd_block_size_arr[0] = 16'd512;
    assign fdd_block_size_arr[1] = 16'd512;

    // HDD geometry - use config if valid, else 0 (not present)
    wire [31:0] hdd_capacity_arr [0:1];
    wire [15:0] hdd_block_size_arr [0:1];
    assign hdd_capacity_arr[0] = msc_config_valid ? msc_hdd0_sectors : 32'd0;
    assign hdd_capacity_arr[1] = msc_config_valid ? msc_hdd1_sectors : 32'd0;
    assign hdd_block_size_arr[0] = 16'd512;
    assign hdd_block_size_arr[1] = 16'd512;

    // Drive ready signals - use config if valid, else default ready
    wire [1:0] fdd_ready_signals = msc_config_valid ? msc_drive_ready_in[1:0] : 2'b11;
    wire [1:0] hdd_ready_signals = msc_config_valid ? msc_drive_ready_in[3:2] : 2'b11;

    // Drive write protect - use config if valid, else use direct signals
    wire [1:0] fdd_wp_signals = msc_config_valid ? msc_drive_wp_in[1:0] : {1'b0, write_protect};
    wire [1:0] hdd_wp_signals = msc_config_valid ? msc_drive_wp_in[3:2] : 2'b00;

    // Drive presence - combine hardware detect with config ready
    wire [1:0] fdd_present_signals = {1'b0, disk_present};
    wire [1:0] hdd_present_signals = msc_config_valid ? msc_drive_ready_in[3:2] : 2'b00;

    drive_lun_mapper #(
        .MAX_LUNS         (4),
        .MAX_FDDS         (2),
        .MAX_HDDS         (2)
    ) u_drive_lun_mapper (
        .clk              (clk),
        .rst_n            (rst_n),

        // SCSI Engine Interface
        .lun_select       (msc_drive_lun),
        .read_req         (msc_drive_read_req),
        .write_req        (msc_drive_write_req),
        .lba              (msc_drive_lba),
        .sector_count     (msc_drive_sector_count),
        .ready            (msc_drive_ready),
        .done             (msc_drive_done),
        .error            (msc_drive_error),

        // FDD HAL Interface
        .fdd_select       (msc_fdd_select),
        .fdd_lba          (msc_fdd_lba),
        .fdd_count        (msc_fdd_count),
        .fdd_read         (msc_fdd_read),
        .fdd_write        (msc_fdd_write),
        .fdd_ready        (fdd_ready_signals[0]),
        .fdd_done         (msc_fdd_read | msc_fdd_write), // Immediate for now
        .fdd_error        (1'b0),

        // HDD HAL Interface
        .hdd_select       (msc_hdd_select),
        .hdd_lba          (msc_hdd_lba),
        .hdd_count        (msc_hdd_count),
        .hdd_read         (msc_hdd_read),
        .hdd_write        (msc_hdd_write),
        .hdd_ready        (hdd_ready_signals[0]),
        .hdd_done         (1'b0),
        .hdd_error        (1'b0),

        // Drive Presence and Status
        .fdd_present      (fdd_present_signals),
        .fdd_write_prot   (fdd_wp_signals),
        .fdd_capacity     (fdd_capacity_arr),
        .fdd_block_size   (fdd_block_size_arr),

        .hdd_present      (hdd_present_signals),
        .hdd_write_prot   (hdd_wp_signals),
        .hdd_capacity     (hdd_capacity_arr),
        .hdd_block_size   (hdd_block_size_arr),

        // LUN Configuration Outputs (to SCSI engine)
        .lun_present      (msc_lun_present),
        .lun_removable    (msc_lun_removable),
        .lun_readonly     (msc_lun_readonly),
        .lun_capacity     (msc_lun_capacity),
        .lun_block_size   (msc_lun_block_size),

        // Status
        .mapper_state     (msc_mapper_state),
        .active_lun       (),
        .is_fdd_op        (),
        .is_hdd_op        ()
    );

    //-------------------------------------------------------------------------
    // MSC Control Logic
    //-------------------------------------------------------------------------

    // Transfer control - start sector buffer when SCSI engine initiates READ/WRITE
    assign msc_transfer_start = msc_drive_read_req || msc_drive_write_req;
    assign msc_transfer_dir = msc_drive_read_req;  // 1=READ (drive->host), 0=WRITE
    assign msc_sector_count_buf = msc_drive_sector_count;

    // Response data routing - INQUIRY/READ_CAPACITY responses go through buffer
    assign msc_resp_ready = msc_buf_wr_ready;

    // Drive select for MSC operations (FDD only for now)
    assign msc_drive_select_int = {2'b00, msc_fdd_select};

    // Motor control from SCSI engine START_STOP_UNIT command
    assign msc_motor_on = msc_drive_motor_on && (active_personality == 3'd4);

    // MSC block device control outputs (directly from mapper for FDD operations)
    assign msc_lun = {1'b0, msc_drive_lun};
    assign msc_lba = msc_fdd_lba;
    assign msc_block_count = msc_fdd_count;
    assign msc_read_start = msc_fdd_read;
    assign msc_write_start = msc_fdd_write;

    // MSC doesn't do flux capture, tie off these signals
    assign msc_head_select = 1'b0;
    assign msc_track_target = 8'd0;
    assign msc_seek_start = 1'b0;
    assign msc_capture_start = 1'b0;
    assign msc_capture_stop = 1'b0;
    assign msc_sample_rate = 8'd0;

    //=========================================================================
    // Drive Control Mux (based on active personality)
    //=========================================================================

    reg [3:0]  drive_select_mux;
    reg        motor_on_mux;
    reg        head_select_mux;
    reg [7:0]  track_target_mux;
    reg        seek_start_mux;
    reg        capture_start_mux, capture_stop_mux;
    reg [7:0]  sample_rate_mux;

    always @(*) begin
        case (active_personality)
            3'd0: begin  // Greaseweazle
                drive_select_mux  = gw_drive_select;
                motor_on_mux      = gw_motor_on;
                head_select_mux   = gw_head_select;
                track_target_mux  = gw_track_target;
                seek_start_mux    = gw_seek_start;
                capture_start_mux = gw_capture_start;
                capture_stop_mux  = gw_capture_stop;
                sample_rate_mux   = gw_sample_rate;
            end
            3'd1: begin  // HxC
                drive_select_mux  = hfe_drive_select;
                motor_on_mux      = hfe_motor_on;
                head_select_mux   = hfe_head_select;
                track_target_mux  = hfe_track_target;
                seek_start_mux    = hfe_seek_start;
                capture_start_mux = hfe_capture_start;
                capture_stop_mux  = hfe_capture_stop;
                sample_rate_mux   = hfe_sample_rate;
            end
            3'd2: begin  // KryoFlux
                drive_select_mux  = kf_drive_select;
                motor_on_mux      = kf_motor_on;
                head_select_mux   = kf_head_select;
                track_target_mux  = kf_track_target;
                seek_start_mux    = kf_seek_start;
                capture_start_mux = kf_capture_start;
                capture_stop_mux  = kf_capture_stop;
                sample_rate_mux   = 8'd0;  // KF uses fixed rate
            end
            3'd3: begin  // Native
                drive_select_mux  = native_drive_select;
                motor_on_mux      = native_motor_on;
                head_select_mux   = native_head_select;
                track_target_mux  = native_track_target;
                seek_start_mux    = native_seek_start;
                capture_start_mux = native_capture_start;
                capture_stop_mux  = native_capture_stop;
                sample_rate_mux   = native_sample_rate;
            end
            3'd4: begin  // MSC + Raw
                drive_select_mux  = msc_drive_select_int;
                motor_on_mux      = msc_motor_on;
                head_select_mux   = msc_head_select;
                track_target_mux  = msc_track_target;
                seek_start_mux    = msc_seek_start;
                capture_start_mux = msc_capture_start;
                capture_stop_mux  = msc_capture_stop;
                sample_rate_mux   = msc_sample_rate;
            end
            default: begin
                drive_select_mux  = 4'b0001;
                motor_on_mux      = 1'b0;
                head_select_mux   = 1'b0;
                track_target_mux  = 8'd0;
                seek_start_mux    = 1'b0;
                capture_start_mux = 1'b0;
                capture_stop_mux  = 1'b0;
                sample_rate_mux   = 8'd0;
            end
        endcase
    end

    // Output assignments
    assign drive_select       = drive_select_mux;
    assign motor_on           = motor_on_mux;
    assign head_select        = head_select_mux;
    assign track_target       = track_target_mux;
    assign seek_start         = seek_start_mux;
    assign flux_capture_start = capture_start_mux;
    assign flux_capture_stop  = capture_stop_mux;
    assign flux_sample_rate   = sample_rate_mux;

    // Flux ready - active for current personality
    assign flux_ready = (active_personality == 3'd0) ? 1'b1 :  // GW always ready
                        (active_personality == 3'd1) ? 1'b1 :  // HxC always ready
                        (active_personality == 3'd2) ? 1'b1 :  // KF always ready
                        (active_personality == 3'd3) ? 1'b1 :  // Native always ready
                        1'b0;

    //=========================================================================
    // Status Outputs
    //=========================================================================

    assign usb_state        = mux_state;
    assign protocol_state   = active_protocol_state;
    // Aggregate error signals from USB subsystem
    assign usb_error        = msc_error |              // External MSC error input
                              msc_drive_error |        // Drive operation error
                              (|msc_last_error);       // SCSI error (any bit set)
    assign rx_byte_count    = ft_rx_count << 2;  // Words to bytes
    assign tx_byte_count    = ft_tx_count << 2;

    //=========================================================================
    // MSC Configuration Status Outputs
    //=========================================================================

    // Drive presence (combine FDD and HDD)
    assign msc_drive_present_out = {hdd_present_signals, fdd_present_signals};

    // Media changed detection (directly from hardware signals, active-high pulse)
    // FDD media change is detected via disk_present transition
    // For now, tie to 0 - proper implementation needs edge detection
    assign msc_media_changed_out = 4'b0000;

    //=========================================================================
    // Endpoint 0 Control Handler (shared, not personality-specific)
    //=========================================================================
    // EP0 handles USB control transfers (enumeration, etc.)
    // For now, tie off - FT601 handles enumeration internally

    assign ep0_rx_ready = 1'b1;
    assign ep0_tx_data  = 32'h0;
    assign ep0_tx_valid = 1'b0;

    //=========================================================================
    // Endpoint 3 - Status/Auxiliary (not used currently)
    //=========================================================================

    assign ep3_tx_data  = 32'h0;
    assign ep3_tx_valid = 1'b0;

endmodule
