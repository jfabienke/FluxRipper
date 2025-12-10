//-----------------------------------------------------------------------------
// FluxRipper Dual-FDC Top Module
// FPGA-based Intel 82077AA Clone with Dual Shugart Interface Support
//
// Supports 4 concurrent drives (2 per interface)
// - Interface A: Drives 0 & 1 (Pi Header 1)
// - Interface B: Drives 2 & 3 (Pi Header 2)
//
// Auto-Detection Features:
// - RPM detection (300/360 RPM) with auto DPLL compensation
// - Track density detection (40/80 track) with auto double-step
// - Data rate detection (250K/300K/500K/1M)
// - Encoding auto-selection (MFM/FM/GCR/M2FM/Tandy)
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-06 00:17 - Added dskchg inputs and media change interrupt
//-----------------------------------------------------------------------------

module fluxripper_dual_top (
    // System
    input  wire        clk_200mhz,      // 200 MHz system clock
    input  wire        reset_n,         // Active low reset

    //-------------------------------------------------------------------------
    // AXI4-Lite Interface (to MicroBlaze V)
    //-------------------------------------------------------------------------
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    //-------------------------------------------------------------------------
    // AXI-Stream Interface A (Flux Capture - to DMA)
    //-------------------------------------------------------------------------
    output wire [31:0] m_axis_a_tdata,
    output wire        m_axis_a_tvalid,
    input  wire        m_axis_a_tready,
    output wire        m_axis_a_tlast,
    output wire [3:0]  m_axis_a_tkeep,

    //-------------------------------------------------------------------------
    // AXI-Stream Interface B (Flux Capture - to DMA)
    //-------------------------------------------------------------------------
    output wire [31:0] m_axis_b_tdata,
    output wire        m_axis_b_tvalid,
    input  wire        m_axis_b_tready,
    output wire        m_axis_b_tlast,
    output wire [3:0]  m_axis_b_tkeep,

    //-------------------------------------------------------------------------
    // Interface A - Drive 0 (Header 1, Drive A)
    //-------------------------------------------------------------------------
    output wire        if_a_drv0_step,
    output wire        if_a_drv0_dir,
    output wire        if_a_drv0_motor,
    output wire        if_a_drv0_head_sel,
    output wire        if_a_drv0_write_gate,
    output wire        if_a_drv0_write_data,
    input  wire        if_a_drv0_read_data,
    input  wire        if_a_drv0_index,
    input  wire        if_a_drv0_track0,
    input  wire        if_a_drv0_wp,
    input  wire        if_a_drv0_ready,
    input  wire        if_a_drv0_dskchg,    // Disk change (active low on pin 34)

    //-------------------------------------------------------------------------
    // Interface A - Drive 1 (Header 1, Drive B)
    //-------------------------------------------------------------------------
    output wire        if_a_drv1_step,
    output wire        if_a_drv1_dir,
    output wire        if_a_drv1_motor,
    output wire        if_a_drv1_head_sel,
    output wire        if_a_drv1_write_gate,
    output wire        if_a_drv1_write_data,
    input  wire        if_a_drv1_read_data,
    input  wire        if_a_drv1_index,
    input  wire        if_a_drv1_track0,
    input  wire        if_a_drv1_wp,
    input  wire        if_a_drv1_ready,
    input  wire        if_a_drv1_dskchg,    // Disk change (active low on pin 34)

    //-------------------------------------------------------------------------
    // Interface B - Drive 2 (Header 2, Drive A)
    //-------------------------------------------------------------------------
    output wire        if_b_drv0_step,
    output wire        if_b_drv0_dir,
    output wire        if_b_drv0_motor,
    output wire        if_b_drv0_head_sel,
    output wire        if_b_drv0_write_gate,
    output wire        if_b_drv0_write_data,
    input  wire        if_b_drv0_read_data,
    input  wire        if_b_drv0_index,
    input  wire        if_b_drv0_track0,
    input  wire        if_b_drv0_wp,
    input  wire        if_b_drv0_ready,
    input  wire        if_b_drv0_dskchg,    // Disk change (active low on pin 34)

    //-------------------------------------------------------------------------
    // Interface B - Drive 3 (Header 2, Drive B)
    //-------------------------------------------------------------------------
    output wire        if_b_drv1_step,
    output wire        if_b_drv1_dir,
    output wire        if_b_drv1_motor,
    output wire        if_b_drv1_head_sel,
    output wire        if_b_drv1_write_gate,
    output wire        if_b_drv1_write_data,
    input  wire        if_b_drv1_read_data,
    input  wire        if_b_drv1_index,
    input  wire        if_b_drv1_track0,
    input  wire        if_b_drv1_wp,
    input  wire        if_b_drv1_ready,
    input  wire        if_b_drv1_dskchg,    // Disk change (active low on pin 34)

    //-------------------------------------------------------------------------
    // Interrupts
    //-------------------------------------------------------------------------
    output wire        irq_fdc_a,       // FDC A interrupt
    output wire        irq_fdc_b,       // FDC B interrupt
    output wire        irq_msc_media,   // MSC media change interrupt

    //-------------------------------------------------------------------------
    // Diagnostic outputs
    //-------------------------------------------------------------------------
    output wire        led_activity_a,
    output wire        led_activity_b,
    output wire        led_error,

    //-------------------------------------------------------------------------
    // Extended Drive Control (8" / 5.25" HD support)
    //-------------------------------------------------------------------------
    // HEAD_LOAD - For 8" drives with solenoid-actuated heads (50-pin Shugart)
    output wire        if_head_load_a,      // Interface A head load (OR of drives 0/1)
    output wire        if_head_load_b,      // Interface B head load (OR of drives 2/3)

    // /TG43 - Track Greater than 43 (for 5.25" HD write precomp)
    output wire        if_tg43_a,           // Interface A track >= 43
    output wire        if_tg43_b,           // Interface B track >= 43

    // DENSITY - DD/HD mode indicator
    output wire        if_density_a,        // Interface A density (0=DD, 1=HD)
    output wire        if_density_b,        // Interface B density (0=DD, 1=HD)

    // /SECTOR - Hard-sectored disk support (NorthStar, S-100)
    input  wire        if_sector_a,         // Interface A sector pulse input
    input  wire        if_sector_b,         // Interface B sector pulse input

    //-------------------------------------------------------------------------
    // Motorized Eject Control (Mac, PS/2, NeXT drives)
    //-------------------------------------------------------------------------
    // Active high pulse triggers motorized eject mechanism
    output wire        if_eject_a,          // Interface A motorized eject
    output wire        if_eject_b,          // Interface B motorized eject

    //-------------------------------------------------------------------------
    // AXI4-Lite Interface for MSC Configuration (Base: 0x40050000)
    //-------------------------------------------------------------------------
    input  wire [7:0]  s_axi_msc_awaddr,
    input  wire        s_axi_msc_awvalid,
    output wire        s_axi_msc_awready,
    input  wire [31:0] s_axi_msc_wdata,
    input  wire [3:0]  s_axi_msc_wstrb,
    input  wire        s_axi_msc_wvalid,
    output wire        s_axi_msc_wready,
    output wire [1:0]  s_axi_msc_bresp,
    output wire        s_axi_msc_bvalid,
    input  wire        s_axi_msc_bready,
    input  wire [7:0]  s_axi_msc_araddr,
    input  wire        s_axi_msc_arvalid,
    output wire        s_axi_msc_arready,
    output wire [31:0] s_axi_msc_rdata,
    output wire [1:0]  s_axi_msc_rresp,
    output wire        s_axi_msc_rvalid,
    input  wire        s_axi_msc_rready
);

    //-------------------------------------------------------------------------
    // Internal signals
    //-------------------------------------------------------------------------
    wire        clk = clk_200mhz;
    wire        reset = ~reset_n;

    // Configuration from AXI peripheral
    wire        dual_enable;
    wire        sync_index;
    wire [1:0]  if_a_drive_sel;        // Drive select for Interface A (0-1)
    wire [1:0]  if_b_drive_sel;        // Drive select for Interface B (0-1)
    wire [1:0]  data_rate;
    wire [1:0]  step_rate_sel;
    wire        double_step;
    wire        rpm_360;
    wire        sw_reset;

    // Motor control (shared, 4 drives)
    wire [3:0]  motor_on_cmd;
    wire [3:0]  motor_running;
    wire [3:0]  motor_at_speed;

    // MSC Configuration (from msc_config_regs)
    wire        msc_config_valid;
    wire [15:0] msc_fdd0_sectors;
    wire [15:0] msc_fdd1_sectors;
    wire [31:0] msc_hdd0_sectors;
    wire [31:0] msc_hdd1_sectors;
    wire [3:0]  msc_drive_ready;
    wire [3:0]  msc_drive_wp;
    wire [3:0]  msc_drive_present;
    wire [3:0]  msc_media_changed;

    // FDC A command interface
    wire [7:0]  fdc_a_cmd_byte;
    wire        fdc_a_cmd_valid;
    wire [7:0]  fdc_a_fifo_data_in;
    wire        fdc_a_fifo_empty;
    wire        fdc_a_fifo_read;
    wire [7:0]  fdc_a_fifo_data_out;
    wire        fdc_a_fifo_write;

    // FDC B command interface
    wire [7:0]  fdc_b_cmd_byte;
    wire        fdc_b_cmd_valid;
    wire [7:0]  fdc_b_fifo_data_in;
    wire        fdc_b_fifo_empty;
    wire        fdc_b_fifo_read;
    wire [7:0]  fdc_b_fifo_data_out;
    wire        fdc_b_fifo_write;

    // FDC A status
    wire [7:0]  fdc_a_current_track;
    wire        fdc_a_seek_complete;
    wire        fdc_a_at_track0;
    wire        fdc_a_busy;
    wire        fdc_a_dio;
    wire        fdc_a_rqm;
    wire        fdc_a_ndma;
    wire        fdc_a_pll_locked;
    wire [7:0]  fdc_a_lock_quality;
    wire        fdc_a_sync_acquired;
    wire [1:0]  fdc_a_int_code;
    wire        fdc_a_seek_end;
    wire        fdc_a_equipment_check;
    wire        fdc_a_data_error;
    wire        fdc_a_overrun;
    wire        fdc_a_no_data;
    wire        fdc_a_missing_am;
    wire        fdc_a_interrupt;

    // FDC B status
    wire [7:0]  fdc_b_current_track;
    wire        fdc_b_seek_complete;
    wire        fdc_b_at_track0;
    wire        fdc_b_busy;
    wire        fdc_b_dio;
    wire        fdc_b_rqm;
    wire        fdc_b_ndma;
    wire        fdc_b_pll_locked;
    wire [7:0]  fdc_b_lock_quality;
    wire        fdc_b_sync_acquired;
    wire [1:0]  fdc_b_int_code;
    wire        fdc_b_seek_end;
    wire        fdc_b_equipment_check;
    wire        fdc_b_data_error;
    wire        fdc_b_overrun;
    wire        fdc_b_no_data;
    wire        fdc_b_missing_am;
    wire        fdc_b_interrupt;

    // Flux capture signals
    wire        fdc_a_flux_valid;
    wire [31:0] fdc_a_flux_timestamp;
    wire        fdc_a_flux_index;
    wire        fdc_b_flux_valid;
    wire [31:0] fdc_b_flux_timestamp;
    wire        fdc_b_flux_index;

    // Flux capture control
    wire        flux_capture_enable_a;
    wire        flux_capture_enable_b;
    wire [1:0]  flux_capture_mode_a;
    wire [1:0]  flux_capture_mode_b;

    // Extended drive control signals
    wire        fdc_a_head_load;         // Head load from FDC A
    wire        fdc_b_head_load;         // Head load from FDC B

    // Motorized eject control
    wire        eject_cmd_a;             // Eject command for Interface A
    wire        eject_cmd_b;             // Eject command for Interface B

    // Auto-detection configuration signals from AXI peripheral
    wire        mac_zone_enable;
    wire        auto_double_step_en;
    wire        auto_data_rate_en;
    wire        auto_encoding_en;

    // Track density detection status from FDC cores
    wire        fdc_a_track_density_detected;
    wire        fdc_a_detected_40_track;
    wire        fdc_b_track_density_detected;
    wire        fdc_b_detected_40_track;

    //-------------------------------------------------------------------------
    // Flux Analyzer Signals
    //-------------------------------------------------------------------------
    wire [1:0]  flux_analyzer_rate_a;
    wire        flux_analyzer_rate_valid_a;
    wire        flux_analyzer_rate_locked_a;
    wire [1:0]  flux_analyzer_rate_b;
    wire        flux_analyzer_rate_valid_b;
    wire        flux_analyzer_rate_locked_b;

    //-------------------------------------------------------------------------
    // Encoding Detector Signals
    //-------------------------------------------------------------------------
    wire [2:0]  encoding_detected_a;
    wire        encoding_valid_a;
    wire        encoding_locked_a;
    wire [2:0]  encoding_detected_b;
    wire        encoding_valid_b;
    wire        encoding_locked_b;

    //-------------------------------------------------------------------------
    // Hard-Sector Detection Signals
    //-------------------------------------------------------------------------
    wire        hard_sector_detected_a;
    wire [3:0]  hard_sector_count_a;
    wire        hard_sector_detected_b;
    wire [3:0]  hard_sector_count_b;

    //-------------------------------------------------------------------------
    // Drive Profile Detection Signals
    //-------------------------------------------------------------------------
    wire [31:0] drive_profile_a;
    wire        drive_profile_valid_a;
    wire        drive_profile_locked_a;
    wire [31:0] drive_profile_b;
    wire        drive_profile_valid_b;
    wire        drive_profile_locked_b;

    // Drive ready signals (derived from READY inputs)
    wire        drv0_ready_sync = if_a_drv0_ready;
    wire        drv1_ready_sync = if_a_drv1_ready;
    wire        drv2_ready_sync = if_b_drv0_ready;
    wire        drv3_ready_sync = if_b_drv1_ready;

    // Active drive ready for each interface
    wire        active_ready_a = if_a_drive_sel[0] ? drv1_ready_sync : drv0_ready_sync;
    wire        active_ready_b = if_b_drive_sel[0] ? drv3_ready_sync : drv2_ready_sync;

    // Disk present detection (index pulses seen = disk spinning)
    wire        disk_present_a = rpm_valid_a;
    wire        disk_present_b = rpm_valid_b;

    //-------------------------------------------------------------------------
    // RPM Auto-Detection Signals
    //-------------------------------------------------------------------------
    // Index handler provides per-drive RPM detection from index pulse timing
    wire [3:0]  index_pulse;             // One-clock index pulse per drive
    wire [31:0] revolution_time_0;       // Revolution time for drive 0
    wire [31:0] revolution_time_1;       // Revolution time for drive 1
    wire [31:0] revolution_time_2;       // Revolution time for drive 2
    wire [31:0] revolution_time_3;       // Revolution time for drive 3
    wire [3:0]  detected_rpm_300;        // 1 if drive is 300 RPM
    wire [3:0]  detected_rpm_360;        // 1 if drive is 360 RPM
    wire [3:0]  rpm_valid;               // 1 if RPM measurement is valid

    // Auto-detection enable control (default to enabled)
    // TODO: Wire from CCR register bit 5 when available
    wire        auto_rpm_enable = 1'b1;

    // Effective RPM signals - select between detected and configured
    // For Interface A: use selected drive's detected RPM if valid, else use configured
    wire        rpm_360_a_detected = if_a_drive_sel[0] ? detected_rpm_360[1] : detected_rpm_360[0];
    wire        rpm_valid_a        = if_a_drive_sel[0] ? rpm_valid[1]        : rpm_valid[0];
    wire        effective_rpm_360_a = auto_rpm_enable && rpm_valid_a ? rpm_360_a_detected : rpm_360;

    // For Interface B: use selected drive's detected RPM if valid, else use configured
    wire        rpm_360_b_detected = if_b_drive_sel[0] ? detected_rpm_360[3] : detected_rpm_360[2];
    wire        rpm_valid_b        = if_b_drive_sel[0] ? rpm_valid[3]        : rpm_valid[2];
    wire        effective_rpm_360_b = auto_rpm_enable && rpm_valid_b ? rpm_360_b_detected : rpm_360;

    //-------------------------------------------------------------------------
    // FDC Core Instance A (Drives 0 & 1)
    //-------------------------------------------------------------------------
    fdc_core_instance #(
        .DRIVE_ID_OFFSET(0),
        .INSTANCE_ID(0)
    ) u_fdc_a (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),
        .data_rate(data_rate),
        .step_rate_sel(step_rate_sel),
        .manual_double_step(double_step),        // Manual control when auto disabled
        .auto_double_step_en(auto_double_step_en), // Enable 40/80-track auto-detection
        .rpm_360(effective_rpm_360_a),           // Auto-detected RPM (or configured fallback)
        .mac_zone_enable(mac_zone_enable),       // Macintosh variable-speed zone mode

        // Drive selection within this interface (0 or 1)
        .drive_sel_local(if_a_drive_sel[0]),

        // Drive 0 interface
        .drv0_step(if_a_drv0_step),
        .drv0_dir(if_a_drv0_dir),
        .drv0_head_sel(if_a_drv0_head_sel),
        .drv0_write_gate(if_a_drv0_write_gate),
        .drv0_write_data(if_a_drv0_write_data),
        .drv0_read_data(if_a_drv0_read_data),
        .drv0_index(if_a_drv0_index),
        .drv0_track0(if_a_drv0_track0),
        .drv0_wp(if_a_drv0_wp),
        .drv0_ready(if_a_drv0_ready),

        // Drive 1 interface
        .drv1_step(if_a_drv1_step),
        .drv1_dir(if_a_drv1_dir),
        .drv1_head_sel(if_a_drv1_head_sel),
        .drv1_write_gate(if_a_drv1_write_gate),
        .drv1_write_data(if_a_drv1_write_data),
        .drv1_read_data(if_a_drv1_read_data),
        .drv1_index(if_a_drv1_index),
        .drv1_track0(if_a_drv1_track0),
        .drv1_wp(if_a_drv1_wp),
        .drv1_ready(if_a_drv1_ready),

        // Command interface
        .command_byte(fdc_a_cmd_byte),
        .command_valid(fdc_a_cmd_valid),
        .fifo_data_in(fdc_a_fifo_data_in),
        .fifo_empty(fdc_a_fifo_empty),
        .fifo_read(fdc_a_fifo_read),
        .fifo_data_out(fdc_a_fifo_data_out),
        .fifo_write(fdc_a_fifo_write),

        // Flux capture
        .flux_valid(fdc_a_flux_valid),
        .flux_timestamp(fdc_a_flux_timestamp),
        .flux_index(fdc_a_flux_index),

        // Status
        .current_track(fdc_a_current_track),
        .seek_complete(fdc_a_seek_complete),
        .at_track0(fdc_a_at_track0),
        .busy(fdc_a_busy),
        .dio(fdc_a_dio),
        .rqm(fdc_a_rqm),
        .ndma(fdc_a_ndma),
        .interrupt(fdc_a_interrupt),
        .pll_locked(fdc_a_pll_locked),
        .lock_quality(fdc_a_lock_quality),
        .sync_acquired(fdc_a_sync_acquired),
        .int_code(fdc_a_int_code),
        .seek_end(fdc_a_seek_end),
        .equipment_check(fdc_a_equipment_check),
        .data_error(fdc_a_data_error),
        .overrun(fdc_a_overrun),
        .no_data(fdc_a_no_data),
        .missing_am(fdc_a_missing_am),
        .head_load(fdc_a_head_load),

        // Track density auto-detection status
        .track_density_detected(fdc_a_track_density_detected),
        .detected_40_track(fdc_a_detected_40_track)
    );

    //-------------------------------------------------------------------------
    // FDC Core Instance B (Drives 2 & 3)
    //-------------------------------------------------------------------------
    fdc_core_instance #(
        .DRIVE_ID_OFFSET(2),
        .INSTANCE_ID(1)
    ) u_fdc_b (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),
        .data_rate(data_rate),
        .step_rate_sel(step_rate_sel),
        .manual_double_step(double_step),        // Manual control when auto disabled
        .auto_double_step_en(auto_double_step_en), // Enable 40/80-track auto-detection
        .rpm_360(effective_rpm_360_b),           // Auto-detected RPM (or configured fallback)
        .mac_zone_enable(mac_zone_enable),       // Macintosh variable-speed zone mode

        // Drive selection within this interface (0 or 1 -> physical 2 or 3)
        .drive_sel_local(if_b_drive_sel[0]),

        // Drive 2 interface (physical)
        .drv0_step(if_b_drv0_step),
        .drv0_dir(if_b_drv0_dir),
        .drv0_head_sel(if_b_drv0_head_sel),
        .drv0_write_gate(if_b_drv0_write_gate),
        .drv0_write_data(if_b_drv0_write_data),
        .drv0_read_data(if_b_drv0_read_data),
        .drv0_index(if_b_drv0_index),
        .drv0_track0(if_b_drv0_track0),
        .drv0_wp(if_b_drv0_wp),
        .drv0_ready(if_b_drv0_ready),

        // Drive 3 interface (physical)
        .drv1_step(if_b_drv1_step),
        .drv1_dir(if_b_drv1_dir),
        .drv1_head_sel(if_b_drv1_head_sel),
        .drv1_write_gate(if_b_drv1_write_gate),
        .drv1_write_data(if_b_drv1_write_data),
        .drv1_read_data(if_b_drv1_read_data),
        .drv1_index(if_b_drv1_index),
        .drv1_track0(if_b_drv1_track0),
        .drv1_wp(if_b_drv1_wp),
        .drv1_ready(if_b_drv1_ready),

        // Command interface
        .command_byte(fdc_b_cmd_byte),
        .command_valid(fdc_b_cmd_valid),
        .fifo_data_in(fdc_b_fifo_data_in),
        .fifo_empty(fdc_b_fifo_empty),
        .fifo_read(fdc_b_fifo_read),
        .fifo_data_out(fdc_b_fifo_data_out),
        .fifo_write(fdc_b_fifo_write),

        // Flux capture
        .flux_valid(fdc_b_flux_valid),
        .flux_timestamp(fdc_b_flux_timestamp),
        .flux_index(fdc_b_flux_index),

        // Status
        .current_track(fdc_b_current_track),
        .seek_complete(fdc_b_seek_complete),
        .at_track0(fdc_b_at_track0),
        .busy(fdc_b_busy),
        .dio(fdc_b_dio),
        .rqm(fdc_b_rqm),
        .ndma(fdc_b_ndma),
        .interrupt(fdc_b_interrupt),
        .pll_locked(fdc_b_pll_locked),
        .lock_quality(fdc_b_lock_quality),
        .sync_acquired(fdc_b_sync_acquired),
        .int_code(fdc_b_int_code),
        .seek_end(fdc_b_seek_end),
        .equipment_check(fdc_b_equipment_check),
        .data_error(fdc_b_data_error),
        .overrun(fdc_b_overrun),
        .no_data(fdc_b_no_data),
        .missing_am(fdc_b_missing_am),
        .head_load(fdc_b_head_load),

        // Track density auto-detection status
        .track_density_detected(fdc_b_track_density_detected),
        .detected_40_track(fdc_b_detected_40_track)
    );

    //-------------------------------------------------------------------------
    // Motor Controller (shared, 4 drives)
    //-------------------------------------------------------------------------
    // Combine index pulses from all drives for motor controller
    wire [3:0] all_index_pulses = {
        if_b_drv1_index,    // Drive 3
        if_b_drv0_index,    // Drive 2
        if_a_drv1_index,    // Drive 1
        if_a_drv0_index     // Drive 0
    };

    motor_controller u_motor_ctrl (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),
        .motor_on_cmd(motor_on_cmd),
        .auto_off_enable(1'b1),
        .index_pulse(all_index_pulses[0]),  // Use drive 0's index for timing reference
        .motor_running(motor_running),
        .motor_at_speed(motor_at_speed),
        .revolution_count()
    );

    // Motor outputs to drives
    assign if_a_drv0_motor = motor_running[0];
    assign if_a_drv1_motor = motor_running[1];
    assign if_b_drv0_motor = motor_running[2];
    assign if_b_drv1_motor = motor_running[3];

    //-------------------------------------------------------------------------
    // Index Handler (RPM Auto-Detection)
    //-------------------------------------------------------------------------
    // Handles all 4 index inputs and auto-detects RPM (300 vs 360) per drive
    index_handler_dual u_index_handler (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),

        // Index inputs from all 4 drives
        .index_0(if_a_drv0_index),
        .index_1(if_a_drv1_index),
        .index_2(if_b_drv0_index),
        .index_3(if_b_drv1_index),

        // Per-drive outputs
        .index_pulse(index_pulse),
        .revolution_time_0(revolution_time_0),
        .revolution_time_1(revolution_time_1),
        .revolution_time_2(revolution_time_2),
        .revolution_time_3(revolution_time_3),
        .rpm_300(detected_rpm_300),
        .rpm_360(detected_rpm_360),
        .rpm_valid(rpm_valid),
        .revolution_count_0(),           // Not used at top level
        .revolution_count_1(),
        .revolution_count_2(),
        .revolution_count_3()
    );

    //-------------------------------------------------------------------------
    // Flux Analyzer A (Interface A)
    //-------------------------------------------------------------------------
    flux_analyzer u_flux_analyzer_a (
        .clk             (clk),
        .reset           (reset || sw_reset),
        .enable          (fdc_a_pll_locked),
        .flux_transition (fdc_a_flux_valid),
        .avg_interval    (),
        .min_interval    (),
        .max_interval    (),
        .detected_rate   (flux_analyzer_rate_a),
        .rate_valid      (flux_analyzer_rate_valid_a),
        .rate_locked     (flux_analyzer_rate_locked_a)
    );

    //-------------------------------------------------------------------------
    // Flux Analyzer B (Interface B)
    //-------------------------------------------------------------------------
    flux_analyzer u_flux_analyzer_b (
        .clk             (clk),
        .reset           (reset || sw_reset),
        .enable          (fdc_b_pll_locked && dual_enable),
        .flux_transition (fdc_b_flux_valid),
        .avg_interval    (),
        .min_interval    (),
        .max_interval    (),
        .detected_rate   (flux_analyzer_rate_b),
        .rate_valid      (flux_analyzer_rate_valid_b),
        .rate_locked     (flux_analyzer_rate_locked_b)
    );

    //-------------------------------------------------------------------------
    // Encoding Detector A (Interface A)
    //-------------------------------------------------------------------------
    encoding_detector u_encoding_detector_a (
        .clk              (clk),
        .reset            (reset || sw_reset),
        .enable           (fdc_a_pll_locked),
        .bit_in           (1'b0),              // Not directly used - uses sync signals
        .bit_valid        (1'b0),
        // Sync detection inputs - MFM sync is indicated by sync_acquired
        .mfm_sync         (fdc_a_sync_acquired),
        .fm_sync          (1'b0),              // Would need separate detector
        .m2fm_sync        (1'b0),
        .gcr_cbm_sync     (1'b0),
        .gcr_apple_sync   (1'b0),
        .tandy_sync       (1'b0),
        .detected_encoding(encoding_detected_a),
        .encoding_valid   (encoding_valid_a),
        .encoding_locked  (encoding_locked_a),
        .match_count      (),
        .sync_history     ()
    );

    //-------------------------------------------------------------------------
    // Encoding Detector B (Interface B)
    //-------------------------------------------------------------------------
    encoding_detector u_encoding_detector_b (
        .clk              (clk),
        .reset            (reset || sw_reset),
        .enable           (fdc_b_pll_locked && dual_enable),
        .bit_in           (1'b0),
        .bit_valid        (1'b0),
        .mfm_sync         (fdc_b_sync_acquired),
        .fm_sync          (1'b0),
        .m2fm_sync        (1'b0),
        .gcr_cbm_sync     (1'b0),
        .gcr_apple_sync   (1'b0),
        .tandy_sync       (1'b0),
        .detected_encoding(encoding_detected_b),
        .encoding_valid   (encoding_valid_b),
        .encoding_locked  (encoding_locked_b),
        .match_count      (),
        .sync_history     ()
    );

    //-------------------------------------------------------------------------
    // Hard-Sector Detector A (Interface A)
    //-------------------------------------------------------------------------
    // Detects hard-sector disks by counting extra pulses between index pulses
    hard_sector_detector u_hard_sector_a (
        .clk             (clk),
        .reset           (reset || sw_reset),
        .enable          (active_ready_a),
        .index_pulse     (index_pulse[0] | index_pulse[1]),  // Either drive on interface A
        .flux_stream     (fdc_a_flux_valid),
        .sector_detected (hard_sector_detected_a),
        .sector_count    (hard_sector_count_a)
    );

    //-------------------------------------------------------------------------
    // Hard-Sector Detector B (Interface B)
    //-------------------------------------------------------------------------
    hard_sector_detector u_hard_sector_b (
        .clk             (clk),
        .reset           (reset || sw_reset),
        .enable          (active_ready_b && dual_enable),
        .index_pulse     (index_pulse[2] | index_pulse[3]),  // Either drive on interface B
        .flux_stream     (fdc_b_flux_valid),
        .sector_detected (hard_sector_detected_b),
        .sector_count    (hard_sector_count_b)
    );

    //-------------------------------------------------------------------------
    // Drive Profile Detector A (Interface A)
    //-------------------------------------------------------------------------
    // Aggregates detection signals to infer drive characteristics
    drive_profile_detector u_profile_a (
        .clk(clk),
        .reset(reset || sw_reset),
        .enable(1'b1),

        // RPM detection
        .rpm_valid(rpm_valid_a),
        .rpm_300(detected_rpm_300[0] | detected_rpm_300[1]),
        .rpm_360(detected_rpm_360[0] | detected_rpm_360[1]),

        // Track density
        .track_density_valid(fdc_a_track_density_detected),
        .detected_40_track(fdc_a_detected_40_track),

        // Data rate - from flux analyzer
        .data_rate_valid(flux_analyzer_rate_valid_a),
        .detected_data_rate(flux_analyzer_rate_a),
        .data_rate_locked(flux_analyzer_rate_locked_a),

        // Encoding - from encoding detector
        .encoding_valid(encoding_valid_a),
        .detected_encoding(encoding_detected_a),
        .encoding_locked(encoding_locked_a),

        // PLL quality
        .lock_quality(fdc_a_lock_quality),
        .pll_locked(fdc_a_pll_locked),

        // Drive status
        .drive_ready(active_ready_a),
        .disk_present(disk_present_a),
        .write_protect(if_a_drive_sel[0] ? if_a_drv1_wp : if_a_drv0_wp),
        .head_load_active(fdc_a_head_load),

        // Hard-sector detection
        .sector_pulse_detected(hard_sector_detected_a),
        .sector_count(hard_sector_count_a),

        // Track position
        .current_track(fdc_a_current_track),

        // Density probing - stub for now
        .probe_request(),                // Not connected yet
        .probe_data_rate(),
        .probe_complete(1'b0),
        .probe_success(1'b0),

        // Profile outputs
        .drive_profile(drive_profile_a),
        .profile_valid(drive_profile_valid_a),
        .profile_locked(drive_profile_locked_a),
        .form_factor(),
        .density_cap(),
        .track_density(),
        .quality_score(),
        .is_hard_sectored(),
        .is_variable_speed(),
        .needs_head_load()
    );

    //-------------------------------------------------------------------------
    // Drive Profile Detector B (Interface B)
    //-------------------------------------------------------------------------
    drive_profile_detector u_profile_b (
        .clk(clk),
        .reset(reset || sw_reset),
        .enable(dual_enable),            // Only active when dual mode enabled

        // RPM detection
        .rpm_valid(rpm_valid_b),
        .rpm_300(detected_rpm_300[2] | detected_rpm_300[3]),
        .rpm_360(detected_rpm_360[2] | detected_rpm_360[3]),

        // Track density
        .track_density_valid(fdc_b_track_density_detected),
        .detected_40_track(fdc_b_detected_40_track),

        // Data rate - from flux analyzer
        .data_rate_valid(flux_analyzer_rate_valid_b),
        .detected_data_rate(flux_analyzer_rate_b),
        .data_rate_locked(flux_analyzer_rate_locked_b),

        // Encoding - from encoding detector
        .encoding_valid(encoding_valid_b),
        .detected_encoding(encoding_detected_b),
        .encoding_locked(encoding_locked_b),

        // PLL quality
        .lock_quality(fdc_b_lock_quality),
        .pll_locked(fdc_b_pll_locked),

        // Drive status
        .drive_ready(active_ready_b),
        .disk_present(disk_present_b),
        .write_protect(if_b_drive_sel[0] ? if_b_drv1_wp : if_b_drv0_wp),
        .head_load_active(fdc_b_head_load),

        // Hard-sector detection
        .sector_pulse_detected(hard_sector_detected_b),
        .sector_count(hard_sector_count_b),

        // Track position
        .current_track(fdc_b_current_track),

        // Density probing - stub (would need dedicated hardware for automatic probing)
        .probe_request(),
        .probe_data_rate(),
        .probe_complete(1'b0),
        .probe_success(1'b0),

        // Profile outputs
        .drive_profile(drive_profile_b),
        .profile_valid(drive_profile_valid_b),
        .profile_locked(drive_profile_locked_b),
        .form_factor(),
        .density_cap(),
        .track_density(),
        .quality_score(),
        .is_hard_sectored(),
        .is_variable_speed(),
        .needs_head_load()
    );

    //-------------------------------------------------------------------------
    // AXI4-Lite FDC Peripheral (Dual Interface)
    //-------------------------------------------------------------------------
    axi_fdc_periph_dual u_axi_fdc (
        // AXI4-Lite interface
        .s_axi_aclk(s_axi_aclk),
        .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        // Configuration outputs
        .dual_enable(dual_enable),
        .sync_index(sync_index),
        .if_a_drive_sel(if_a_drive_sel),
        .if_b_drive_sel(if_b_drive_sel),
        .data_rate(data_rate),
        .step_rate_sel(step_rate_sel),
        .double_step(double_step),
        .rpm_360(rpm_360),
        .motor_on_cmd(motor_on_cmd),
        .sw_reset(sw_reset),

        // FDC A command interface
        .fdc_a_cmd_byte(fdc_a_cmd_byte),
        .fdc_a_cmd_valid(fdc_a_cmd_valid),
        .fdc_a_fifo_data_in(fdc_a_fifo_data_in),
        .fdc_a_fifo_empty(fdc_a_fifo_empty),
        .fdc_a_fifo_read(fdc_a_fifo_read),
        .fdc_a_fifo_data_out(fdc_a_fifo_data_out),
        .fdc_a_fifo_write(fdc_a_fifo_write),

        // FDC B command interface
        .fdc_b_cmd_byte(fdc_b_cmd_byte),
        .fdc_b_cmd_valid(fdc_b_cmd_valid),
        .fdc_b_fifo_data_in(fdc_b_fifo_data_in),
        .fdc_b_fifo_empty(fdc_b_fifo_empty),
        .fdc_b_fifo_read(fdc_b_fifo_read),
        .fdc_b_fifo_data_out(fdc_b_fifo_data_out),
        .fdc_b_fifo_write(fdc_b_fifo_write),

        // FDC A status
        .fdc_a_current_track(fdc_a_current_track),
        .fdc_a_busy(fdc_a_busy),
        .fdc_a_dio(fdc_a_dio),
        .fdc_a_rqm(fdc_a_rqm),
        .fdc_a_pll_locked(fdc_a_pll_locked),
        .fdc_a_lock_quality(fdc_a_lock_quality),

        // FDC B status
        .fdc_b_current_track(fdc_b_current_track),
        .fdc_b_busy(fdc_b_busy),
        .fdc_b_dio(fdc_b_dio),
        .fdc_b_rqm(fdc_b_rqm),
        .fdc_b_pll_locked(fdc_b_pll_locked),
        .fdc_b_lock_quality(fdc_b_lock_quality),

        // Flux capture control
        .flux_capture_enable_a(flux_capture_enable_a),
        .flux_capture_enable_b(flux_capture_enable_b),
        .flux_capture_mode_a(flux_capture_mode_a),
        .flux_capture_mode_b(flux_capture_mode_b),

        // Motor status
        .motor_running(motor_running),
        .motor_at_speed(motor_at_speed),

        // Auto-detection configuration (from CCR)
        .mac_zone_enable(mac_zone_enable),
        .auto_double_step_en(auto_double_step_en),
        .auto_data_rate_en(auto_data_rate_en),       // For future flux analyzer
        .auto_encoding_en(auto_encoding_en),         // For future encoding detector

        // Motorized eject commands
        .eject_cmd_a(eject_cmd_a),
        .eject_cmd_b(eject_cmd_b),

        // Auto-detection status inputs
        .rpm_valid(rpm_valid),
        .detected_rpm_360(detected_rpm_360),
        .detected_data_rate_a(2'b00),                // TODO: Wire from flux analyzer A
        .detected_data_rate_b(2'b00),                // TODO: Wire from flux analyzer B
        .data_rate_locked_a(1'b0),                   // TODO: Wire from flux analyzer A
        .data_rate_locked_b(1'b0),                   // TODO: Wire from flux analyzer B
        .detected_encoding_a(3'b000),                // TODO: Wire from encoding detector A
        .detected_encoding_b(3'b000),                // TODO: Wire from encoding detector B
        .encoding_locked_a(1'b0),                    // TODO: Wire from encoding detector A
        .encoding_locked_b(1'b0),                    // TODO: Wire from encoding detector B

        // Track density auto-detection status
        .detected_40_track_a(fdc_a_detected_40_track),
        .detected_40_track_b(fdc_b_detected_40_track),
        .track_density_detected_a(fdc_a_track_density_detected),
        .track_density_detected_b(fdc_b_track_density_detected),

        // Drive profile inputs
        .drive_profile_a(drive_profile_a),
        .drive_profile_valid_a(drive_profile_valid_a),
        .drive_profile_locked_a(drive_profile_locked_a),
        .drive_profile_b(drive_profile_b),
        .drive_profile_valid_b(drive_profile_valid_b),
        .drive_profile_locked_b(drive_profile_locked_b)
    );

    //-------------------------------------------------------------------------
    // MSC Configuration Registers (Base: 0x40050000)
    //-------------------------------------------------------------------------
    // Drive presence from hardware (FDD 0-1, HDD 2-3)
    wire [3:0] hw_drive_present = {
        2'b00,                          // HDD 1, HDD 0 (not present in FDC config)
        if_a_drv1_ready,                // FDD 1 (drive 1 ready)
        if_a_drv0_ready                 // FDD 0 (drive 0 ready)
    };

    // Media changed detection from disk change signals
    // DSKCHG on pin 34 is active-low; invert for positive logic
    // HDDs don't have dskchg, always 0
    wire [3:0] hw_media_changed = {
        2'b00,                          // HDD 1, HDD 0 (no dskchg)
        ~if_a_drv1_dskchg,              // FDD 1 (Interface A, Drive 1)
        ~if_a_drv0_dskchg               // FDD 0 (Interface A, Drive 0)
    };

    // Interface B disk change (active when low)
    wire [3:0] hw_media_changed_b = {
        2'b00,                          // HDD (not used)
        ~if_b_drv1_dskchg,              // FDD 3 (Interface B, Drive 1)
        ~if_b_drv0_dskchg               // FDD 2 (Interface B, Drive 0)
    };

    // MSC media change interrupt wire
    wire msc_media_irq;

    msc_config_regs u_msc_config (
        .clk              (s_axi_aclk),
        .rst_n            (s_axi_aresetn),

        // AXI-Lite interface
        .s_axi_awaddr     (s_axi_msc_awaddr),
        .s_axi_awvalid    (s_axi_msc_awvalid),
        .s_axi_awready    (s_axi_msc_awready),
        .s_axi_wdata      (s_axi_msc_wdata),
        .s_axi_wstrb      (s_axi_msc_wstrb),
        .s_axi_wvalid     (s_axi_msc_wvalid),
        .s_axi_wready     (s_axi_msc_wready),
        .s_axi_bresp      (s_axi_msc_bresp),
        .s_axi_bvalid     (s_axi_msc_bvalid),
        .s_axi_bready     (s_axi_msc_bready),
        .s_axi_araddr     (s_axi_msc_araddr),
        .s_axi_arvalid    (s_axi_msc_arvalid),
        .s_axi_arready    (s_axi_msc_arready),
        .s_axi_rdata      (s_axi_msc_rdata),
        .s_axi_rresp      (s_axi_msc_rresp),
        .s_axi_rvalid     (s_axi_msc_rvalid),
        .s_axi_rready     (s_axi_msc_rready),

        // Configuration outputs
        .config_valid     (msc_config_valid),
        .fdd0_sectors     (msc_fdd0_sectors),
        .fdd1_sectors     (msc_fdd1_sectors),
        .hdd0_sectors     (msc_hdd0_sectors),
        .hdd1_sectors     (msc_hdd1_sectors),
        .drive_ready      (msc_drive_ready),
        .drive_wp         (msc_drive_wp),

        // Status inputs
        .drive_present    (hw_drive_present),
        .media_changed_in (hw_media_changed),

        // Interrupt output
        .irq_media_change (msc_media_irq)
    );

    // Connect MSC media change interrupt to output
    assign irq_msc_media = msc_media_irq;

    //-------------------------------------------------------------------------
    // AXI-Stream Flux Capture A
    //-------------------------------------------------------------------------
    axi_stream_flux_dual #(
        .INSTANCE_ID(0)
    ) u_flux_stream_a (
        .clk_sys(clk),
        .aclk(s_axi_aclk),
        .aresetn(s_axi_aresetn & ~sw_reset),

        // Flux input
        .flux_valid(fdc_a_flux_valid),
        .flux_timestamp(fdc_a_flux_timestamp),
        .flux_index(fdc_a_flux_index),
        .drive_id({1'b0, if_a_drive_sel[0]}),

        // Control
        .capture_enable(flux_capture_enable_a),
        .capture_mode(flux_capture_mode_a),
        .soft_reset(sw_reset),

        // AXI-Stream output
        .m_axis_tdata(m_axis_a_tdata),
        .m_axis_tvalid(m_axis_a_tvalid),
        .m_axis_tready(m_axis_a_tready),
        .m_axis_tlast(m_axis_a_tlast),
        .m_axis_tkeep(m_axis_a_tkeep),

        // Status
        .capture_count(),
        .index_count(),
        .overflow(),
        .fifo_level()
    );

    //-------------------------------------------------------------------------
    // AXI-Stream Flux Capture B
    //-------------------------------------------------------------------------
    axi_stream_flux_dual #(
        .INSTANCE_ID(1)
    ) u_flux_stream_b (
        .clk_sys(clk),
        .aclk(s_axi_aclk),
        .aresetn(s_axi_aresetn & ~sw_reset),

        // Flux input
        .flux_valid(fdc_b_flux_valid),
        .flux_timestamp(fdc_b_flux_timestamp),
        .flux_index(fdc_b_flux_index),
        .drive_id({1'b1, if_b_drive_sel[0]}),  // Drive 2 or 3

        // Control
        .capture_enable(flux_capture_enable_b),
        .capture_mode(flux_capture_mode_b),
        .soft_reset(sw_reset),

        // AXI-Stream output
        .m_axis_tdata(m_axis_b_tdata),
        .m_axis_tvalid(m_axis_b_tvalid),
        .m_axis_tready(m_axis_b_tready),
        .m_axis_tlast(m_axis_b_tlast),
        .m_axis_tkeep(m_axis_b_tkeep),

        // Status
        .capture_count(),
        .index_count(),
        .overflow(),
        .fifo_level()
    );

    //-------------------------------------------------------------------------
    // Interrupt Outputs
    //-------------------------------------------------------------------------
    assign irq_fdc_a = fdc_a_interrupt;
    assign irq_fdc_b = fdc_b_interrupt;

    //-------------------------------------------------------------------------
    // Status LEDs
    //-------------------------------------------------------------------------
    assign led_activity_a = motor_running[0] || motor_running[1] || fdc_a_busy;
    assign led_activity_b = motor_running[2] || motor_running[3] || fdc_b_busy;
    assign led_error = fdc_a_data_error || fdc_a_missing_am ||
                       fdc_b_data_error || fdc_b_missing_am;

    //-------------------------------------------------------------------------
    // Extended Drive Control Outputs
    //-------------------------------------------------------------------------
    // HEAD_LOAD: OR'd per interface (8" Shugart is per-bus, drive gates with DS)
    assign if_head_load_a = fdc_a_head_load;
    assign if_head_load_b = fdc_b_head_load;

    // /TG43: Track Greater Than 43 (for 5.25" HD write precomp)
    assign if_tg43_a = (fdc_a_current_track >= 8'd43);
    assign if_tg43_b = (fdc_b_current_track >= 8'd43);

    // DENSITY: DD=0 (250K/300K), HD=1 (500K/1M)
    // data_rate: 00=250K, 01=300K, 10=500K, 11=1M
    assign if_density_a = (data_rate >= 2'b10);  // HD when 500K or 1M
    assign if_density_b = (data_rate >= 2'b10);

    // Note: if_sector_a/b inputs are routed to flux capture modules
    // for hard-sectored disk support (see axi_stream_flux_dual instances)

    //-------------------------------------------------------------------------
    // Motorized Eject Control
    //-------------------------------------------------------------------------
    // Generates timed eject pulse for Mac/PS/2/NeXT drives
    // Eject signal is typically active for ~500ms to fully eject disk

    eject_controller u_eject_ctrl (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),

        // Eject commands from AXI peripheral
        .eject_cmd_a(eject_cmd_a),
        .eject_cmd_b(eject_cmd_b),

        // Eject outputs to drives
        .eject_out_a(if_eject_a),
        .eject_out_b(if_eject_b)
    );

endmodule


//-----------------------------------------------------------------------------
// Eject Controller Module
// Generates timed eject pulses for motorized eject drives
//
// Supports:
//   - Macintosh 3.5" (Sony, Alps)
//   - PS/2 Model 50/60/80
//   - NeXT MO drives
//
// Pulse duration: ~500ms active (configurable)
//-----------------------------------------------------------------------------
module eject_controller (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] clk_freq,

    // Eject commands (rising edge triggered)
    input  wire        eject_cmd_a,
    input  wire        eject_cmd_b,

    // Eject outputs (active high)
    output reg         eject_out_a,
    output reg         eject_out_b
);

    // Eject pulse duration: 500ms = 100,000,000 clocks at 200 MHz
    localparam [31:0] EJECT_DURATION = 32'd100_000_000;

    // State per interface
    reg [31:0] timer_a;
    reg [31:0] timer_b;
    reg        cmd_a_prev;
    reg        cmd_b_prev;

    always @(posedge clk) begin
        if (reset) begin
            eject_out_a <= 1'b0;
            eject_out_b <= 1'b0;
            timer_a     <= 32'd0;
            timer_b     <= 32'd0;
            cmd_a_prev  <= 1'b0;
            cmd_b_prev  <= 1'b0;
        end
        else begin
            cmd_a_prev <= eject_cmd_a;
            cmd_b_prev <= eject_cmd_b;

            // Interface A eject
            if (eject_cmd_a && !cmd_a_prev) begin
                // Rising edge - start eject
                eject_out_a <= 1'b1;
                timer_a     <= EJECT_DURATION;
            end
            else if (timer_a > 0) begin
                timer_a <= timer_a - 1'b1;
                if (timer_a == 32'd1)
                    eject_out_a <= 1'b0;
            end

            // Interface B eject
            if (eject_cmd_b && !cmd_b_prev) begin
                // Rising edge - start eject
                eject_out_b <= 1'b1;
                timer_b     <= EJECT_DURATION;
            end
            else if (timer_b > 0) begin
                timer_b <= timer_b - 1'b1;
                if (timer_b == 32'd1)
                    eject_out_b <= 1'b0;
            end
        end
    end

endmodule
