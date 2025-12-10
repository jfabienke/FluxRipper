//-----------------------------------------------------------------------------
// FDC Core Instance Wrapper
// Encapsulates a complete FDC data path for dual-interface support
//
// Contains: DPLL, AM Detector, Step Controller, Command FSM, CRC, Zone Calculator,
//           Track Width Analyzer (for 40/80-track auto-detection),
//           QIC-117 Tape Controller (for floppy-interface tape drives)
// Parameterized for drive ID offset (0 for Interface A, 2 for Interface B)
//
// Supports Macintosh variable-speed GCR with automatic zone-based data rates
// Supports automatic double-step detection for 40-track disks in 80-track drives
// Supports QIC-40/80/3010/3020 floppy-interface tape drives via TDR register
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-10 - Added QIC-117 tape controller integration
//-----------------------------------------------------------------------------

module fdc_core_instance #(
    parameter DRIVE_ID_OFFSET = 0,      // 0 for drives 0/1, 2 for drives 2/3
    parameter INSTANCE_ID     = 0       // Instance identifier for debugging
) (
    // Clock and reset
    input  wire        clk,             // 200 MHz system clock
    input  wire        reset,

    // Configuration
    input  wire [31:0] clk_freq,        // System clock frequency
    input  wire [1:0]  data_rate,       // 00=250K, 01=300K, 10=500K, 11=1M
    input  wire [1:0]  step_rate_sel,   // Step rate selection
    input  wire        manual_double_step, // Manual double-step control (when auto disabled)
    input  wire        auto_double_step_en, // Enable auto 40/80-track detection
    input  wire        rpm_360,         // 360 RPM drive mode
    input  wire        mac_zone_enable, // Macintosh variable-speed zone mode

    //-------------------------------------------------------------------------
    // Drive Interface (active drive, selected via drive_sel_local)
    //-------------------------------------------------------------------------
    input  wire        drive_sel_local, // 0=Drive A (offset+0), 1=Drive B (offset+1)

    // Drive 0 (offset+0) signals
    output wire        drv0_step,
    output wire        drv0_dir,
    output wire        drv0_head_sel,
    output wire        drv0_write_gate,
    output wire        drv0_write_data,
    input  wire        drv0_read_data,
    input  wire        drv0_index,
    input  wire        drv0_track0,
    input  wire        drv0_wp,
    input  wire        drv0_ready,

    // Drive 1 (offset+1) signals
    output wire        drv1_step,
    output wire        drv1_dir,
    output wire        drv1_head_sel,
    output wire        drv1_write_gate,
    output wire        drv1_write_data,
    input  wire        drv1_read_data,
    input  wire        drv1_index,
    input  wire        drv1_track0,
    input  wire        drv1_wp,
    input  wire        drv1_ready,

    //-------------------------------------------------------------------------
    // Command Interface (from AXI peripheral or host)
    //-------------------------------------------------------------------------
    input  wire [7:0]  command_byte,
    input  wire        command_valid,
    input  wire [7:0]  fifo_data_in,
    input  wire        fifo_empty,
    output wire        fifo_read,
    output wire [7:0]  fifo_data_out,
    output wire        fifo_write,

    //-------------------------------------------------------------------------
    // Flux Capture Interface (to AXI-Stream)
    //-------------------------------------------------------------------------
    output wire        flux_valid,       // Flux transition detected
    output wire [31:0] flux_timestamp,   // Timestamp of transition
    output wire        flux_index,       // Index pulse marker

    //-------------------------------------------------------------------------
    // Status Interface
    //-------------------------------------------------------------------------
    output wire [7:0]  current_track,    // Current head position
    output wire        seek_complete,
    output wire        at_track0,
    output wire        busy,
    output wire        dio,
    output wire        rqm,
    output wire        ndma,
    output wire        interrupt,

    // DPLL status
    output wire        pll_locked,
    output wire [7:0]  lock_quality,
    output wire        sync_acquired,

    // Error flags
    output wire [1:0]  int_code,
    output wire        seek_end,
    output wire        equipment_check,
    output wire        data_error,
    output wire        overrun,
    output wire        no_data,
    output wire        missing_am,

    // 8" drive support signals
    output wire        head_load,           // Head load solenoid control (for 8" drives)

    // Track density auto-detection status
    output wire        track_density_detected, // Track analysis complete
    output wire        detected_40_track,      // 1 if 40-track disk detected

    //-------------------------------------------------------------------------
    // QIC-117 Tape Mode Control (directly from TDR register)
    //-------------------------------------------------------------------------
    input  wire        tape_mode_en,          // Tape mode enable (TDR[7])
    input  wire [2:0]  tape_select,           // Tape drive select (TDR[2:0])
    input  wire        tape_cartridge_in,     // Cartridge present sensor
    input  wire        tape_write_protect,    // Write protect sensor

    //-------------------------------------------------------------------------
    // QIC-117 Tape Status Outputs
    //-------------------------------------------------------------------------
    output wire [7:0]  tape_status,           // Tape status byte
    output wire [15:0] tape_segment,          // Current segment position
    output wire [4:0]  tape_track,            // Current track position
    output wire [5:0]  tape_last_command,     // Last decoded command
    output wire        tape_command_active,   // Command in progress
    output wire        tape_ready,            // Tape drive ready
    output wire        tape_error             // Tape error condition
);

    //-------------------------------------------------------------------------
    // Internal signals
    //-------------------------------------------------------------------------

    // Drive multiplexer signals
    wire        active_read_data;
    wire        active_index;
    wire        active_track0;
    wire        active_wp;
    wire        active_ready;

    // Step controller signals
    wire        step_pulse;
    wire        step_dir;
    wire        step_head_load;
    wire [7:0]  step_current_track;
    wire [7:0]  step_physical_track;
    wire        step_seek_complete;
    wire        step_at_track0;
    wire        step_busy;

    // Command FSM signals
    wire        cmd_seek_start;
    wire [7:0]  cmd_seek_target;
    wire        cmd_restore;
    wire        cmd_read_enable;
    wire        cmd_write_enable;
    wire        cmd_crc_reset;
    wire [1:0]  cmd_head_select;

    // ID field signals from Command FSM (for track density detection)
    wire [7:0]  cmd_id_cylinder;
    wire        cmd_id_valid;

    // Track width analyzer signals
    wire        analyzer_double_step;
    wire        analyzer_complete;

    // Dynamic double_step control
    // If auto enabled and detection complete → use auto-detected value
    // Otherwise → use manual register value
    wire effective_double_step = auto_double_step_en ?
        (analyzer_complete ? analyzer_double_step : manual_double_step) :
        manual_double_step;

    // DPLL signals
    wire        dpll_data_bit;
    wire        dpll_data_ready;
    wire        dpll_bit_clk;
    wire        dpll_locked;
    wire [7:0]  dpll_quality;
    wire [1:0]  dpll_margin;

    // Mac zone calculator signals
    wire [2:0]  mac_zone;
    wire        zone_changed;

    // AM detector signals
    wire        am_a1_detected;
    wire        am_c2_detected;
    wire [1:0]  am_sync_count;
    wire        am_sync_acquired;
    wire [7:0]  am_data_byte;
    wire        am_byte_ready;

    // CRC signals
    wire [15:0] crc_value;
    wire        crc_valid;

    // Edge detector for flux capture
    wire        edge_detected;
    wire [31:0] edge_timestamp;

    // Write path signals
    wire [7:0]  cmd_write_data;
    wire        cmd_write_valid;
    wire        write_encoder_flux;
    wire        write_encoder_valid;
    wire        write_encoder_ready;
    wire        write_encoder_done;

    // Bit clock for write encoder (derived from data rate)
    // 250K=4us/bit=800clk, 300K=3.33us=666clk, 500K=2us=400clk, 1M=1us=200clk
    reg [9:0]   write_bit_clk_counter;
    reg         write_bit_clk;
    wire [9:0]  write_bit_clk_period;

    // Data rate to bit clock period (for 200MHz clock, MFM needs 2x bit rate)
    // MFM cell is half of bit period
    assign write_bit_clk_period = (data_rate == 2'b00) ? 10'd400 :  // 250Kbps -> 400 clks
                                   (data_rate == 2'b01) ? 10'd333 :  // 300Kbps -> 333 clks
                                   (data_rate == 2'b10) ? 10'd200 :  // 500Kbps -> 200 clks
                                                          10'd100;   // 1Mbps -> 100 clks

    // Generate write bit clock
    always @(posedge clk) begin
        if (reset || !cmd_write_enable) begin
            write_bit_clk_counter <= 10'd0;
            write_bit_clk <= 1'b0;
        end else begin
            if (write_bit_clk_counter >= write_bit_clk_period - 1) begin
                write_bit_clk_counter <= 10'd0;
                write_bit_clk <= 1'b1;
            end else begin
                write_bit_clk_counter <= write_bit_clk_counter + 1'b1;
                write_bit_clk <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // QIC-117 Tape Controller Signals
    //-------------------------------------------------------------------------
    wire        qic_trk0_out;
    wire        qic_index_out;
    wire        qic_motor_on;
    wire        qic_direction;
    wire [7:0]  qic_read_data;
    wire        qic_read_valid;
    wire [5:0]  qic_current_command;
    wire        qic_command_strobe;
    wire        qic_block_sync;
    wire [8:0]  qic_byte_in_block;
    wire [4:0]  qic_block_in_segment;
    wire        qic_segment_complete;
    wire        qic_file_mark;

    //-------------------------------------------------------------------------
    // Drive Multiplexer
    //-------------------------------------------------------------------------
    assign active_read_data = drive_sel_local ? drv1_read_data : drv0_read_data;
    assign active_index     = drive_sel_local ? drv1_index     : drv0_index;
    assign active_track0    = drive_sel_local ? drv1_track0    : drv0_track0;
    assign active_wp        = drive_sel_local ? drv1_wp        : drv0_wp;
    assign active_ready     = drive_sel_local ? drv1_ready     : drv0_ready;

    //-------------------------------------------------------------------------
    // Drive Output Demux
    //-------------------------------------------------------------------------
    // Drive 0 outputs (active when drive_sel_local == 0)
    assign drv0_step       = ~drive_sel_local ? step_pulse : 1'b0;
    assign drv0_dir        = ~drive_sel_local ? step_dir : 1'b0;
    assign drv0_head_sel   = ~drive_sel_local ? cmd_head_select[0] : 1'b0;
    assign drv0_write_gate = ~drive_sel_local ? cmd_write_enable : 1'b0;
    assign drv0_write_data = ~drive_sel_local ? (write_encoder_flux & write_encoder_valid) : 1'b0;

    // Drive 1 outputs (active when drive_sel_local == 1)
    assign drv1_step       = drive_sel_local ? step_pulse : 1'b0;
    assign drv1_dir        = drive_sel_local ? step_dir : 1'b0;
    assign drv1_head_sel   = drive_sel_local ? cmd_head_select[0] : 1'b0;
    assign drv1_write_gate = drive_sel_local ? cmd_write_enable : 1'b0;
    assign drv1_write_data = drive_sel_local ? (write_encoder_flux & write_encoder_valid) : 1'b0;

    //-------------------------------------------------------------------------
    // Macintosh Zone Calculator
    //-------------------------------------------------------------------------
    // Calculates data rate zone based on current track for Mac GCR disks
    zone_calculator #(
        .ZONE_MODE(0)                       // 0 = Mac/Lisa (5 zones)
    ) u_zone_calc (
        .clk(clk),
        .reset(reset),
        .current_track(step_current_track),
        .mac_mode_enable(mac_zone_enable),
        .zone(mac_zone),
        .zone_changed(zone_changed)
    );

    //-------------------------------------------------------------------------
    // Digital PLL (Data Separator)
    //-------------------------------------------------------------------------
    // Supports standard rates and Macintosh variable-speed zones
    digital_pll u_dpll (
        .clk(clk),
        .reset(reset),
        .enable(cmd_read_enable),
        .data_rate(data_rate),
        .rpm_360(rpm_360),
        .lock_threshold(16'h1000),
        .mac_zone_enable(mac_zone_enable),  // Mac variable-speed mode
        .mac_zone(mac_zone),                // Current zone (0-4)
        .rate_change(zone_changed),         // Force re-lock on zone transition
        .flux_in(active_read_data),
        .data_bit(dpll_data_bit),
        .data_ready(dpll_data_ready),
        .bit_clk(dpll_bit_clk),
        .pll_locked(dpll_locked),
        .lock_quality(dpll_quality),
        .margin_zone(dpll_margin),
        .phase_accum(),
        .phase_error(),
        .bandwidth()
    );

    //-------------------------------------------------------------------------
    // Address Mark Detector
    //-------------------------------------------------------------------------
    am_detector_with_shifter u_am_detector (
        .clk(clk),
        .reset(reset),
        .enable(cmd_read_enable),
        .bit_in(dpll_data_bit),
        .bit_valid(dpll_data_ready),
        .a1_detected(am_a1_detected),
        .c2_detected(am_c2_detected),
        .sync_count(am_sync_count),
        .sync_acquired(am_sync_acquired),
        .data_byte(am_data_byte),
        .byte_ready(am_byte_ready),
        .raw_shift()
    );

    //-------------------------------------------------------------------------
    // CRC Calculator
    //-------------------------------------------------------------------------
    crc16_ccitt u_crc (
        .clk(clk),
        .reset(reset),
        .enable(am_byte_ready),
        .init(cmd_crc_reset),
        .data_in(am_data_byte),
        .crc_out(crc_value),
        .crc_valid(crc_valid)
    );

    //-------------------------------------------------------------------------
    // MFM Write Encoder
    //-------------------------------------------------------------------------
    // Converts parallel bytes from command FSM to serial MFM-encoded flux stream
    mfm_encoder_serial u_write_encoder (
        .clk           (clk),
        .reset         (reset),
        .enable        (cmd_write_enable),
        .bit_clk       (write_bit_clk),
        .data_in       (cmd_write_data),
        .data_valid    (cmd_write_valid),
        .flux_out      (write_encoder_flux),
        .flux_valid    (write_encoder_valid),
        .byte_complete (write_encoder_done),
        .ready         (write_encoder_ready)
    );

    //-------------------------------------------------------------------------
    // Step Controller
    //-------------------------------------------------------------------------
    step_controller u_step_ctrl (
        .clk(clk),
        .reset(reset),
        .clk_freq(clk_freq),
        .step_rate_sel(step_rate_sel),
        .double_step(effective_double_step),  // Dynamic: auto-detected or manual
        .seek_start(cmd_seek_start),
        .target_track(cmd_seek_target),
        .step_in(1'b0),
        .step_out(1'b0),
        .restore(cmd_restore),
        .step_pulse(step_pulse),
        .direction(step_dir),
        .head_load(step_head_load),
        .current_track(step_current_track),
        .physical_track(step_physical_track),
        .seek_complete(step_seek_complete),
        .at_track0(step_at_track0),
        .busy(step_busy)
    );

    //-------------------------------------------------------------------------
    // Track Width Analyzer (40/80-track auto-detection)
    //-------------------------------------------------------------------------
    // Compares logical cylinder from ID field with physical track position
    // to detect 40-track disks being read in 80-track drives
    track_width_analyzer u_track_analyzer (
        .clk(clk),
        .reset(reset),
        .enable(cmd_read_enable),           // Active during reads
        .id_cylinder(cmd_id_cylinder),
        .id_valid(cmd_id_valid),
        .physical_track(step_physical_track),
        .double_step_recommended(analyzer_double_step),
        .analysis_complete(analyzer_complete),
        .detected_tracks()                  // Not used at top level
    );

    //-------------------------------------------------------------------------
    // Command FSM
    //-------------------------------------------------------------------------
    command_fsm u_command_fsm (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),
        .command_byte(command_byte),
        .command_valid(command_valid),
        .fifo_data(fifo_data_in),
        .fifo_empty(fifo_empty),
        .fifo_read(fifo_read),
        .fifo_write_data(fifo_data_out),
        .fifo_write(fifo_write),
        .seek_start(cmd_seek_start),
        .seek_target(cmd_seek_target),
        .restore(cmd_restore),
        .seek_complete(step_seek_complete),
        .current_track(step_current_track),
        .at_track0(step_at_track0),
        .read_enable(cmd_read_enable),
        .read_data(am_data_byte),
        .read_ready(am_byte_ready),
        .sync_acquired(am_sync_acquired),
        .a1_detected(am_a1_detected),
        .write_enable(cmd_write_enable),
        .write_data(cmd_write_data),
        .write_valid(cmd_write_valid),
        .crc_reset(cmd_crc_reset),
        .crc_valid(crc_valid),
        .crc_value(crc_value),
        .head_select(cmd_head_select),
        .index_pulse(active_index),
        .write_protect(active_wp),
        .int_code(int_code),
        .seek_end(seek_end),
        .equipment_check(equipment_check),
        .end_of_cylinder(),
        .data_error(data_error),
        .overrun(overrun),
        .no_data(no_data),
        .missing_am(missing_am),
        .busy(busy),
        .dio(dio),
        .rqm(rqm),
        .ndma(ndma),
        .interrupt(interrupt),
        // ID field outputs for track density detection
        .id_cylinder_out(cmd_id_cylinder),
        .id_field_valid(cmd_id_valid)
    );

    //-------------------------------------------------------------------------
    // Flux Capture Edge Detector
    //-------------------------------------------------------------------------
    // Simple edge detector for flux capture timestamping
    reg [2:0]  flux_sync;
    reg [31:0] timestamp_counter;
    reg        flux_edge_detected;

    always @(posedge clk) begin
        if (reset) begin
            flux_sync <= 3'b000;
            timestamp_counter <= 32'd0;
            flux_edge_detected <= 1'b0;
        end else begin
            flux_sync <= {flux_sync[1:0], active_read_data};
            timestamp_counter <= timestamp_counter + 1'b1;

            // Detect rising edge
            flux_edge_detected <= (flux_sync[2:1] == 2'b01);
        end
    end

    //-------------------------------------------------------------------------
    // QIC-117 Tape Controller
    //-------------------------------------------------------------------------
    // Instantiated for QIC-40/80/3010/3020 floppy-interface tape drive support
    // In tape mode, STEP pulses become command bits, TRK0 becomes status output
    qic117_controller #(
        .CLK_FREQ_HZ(200_000_000)
    ) u_qic117 (
        .clk               (clk),
        .reset_n           (~reset),
        .tape_mode_en      (tape_mode_en),
        .tape_select       (tape_select),
        // FDC signal intercept
        .step_in           (step_pulse),              // STEP from step controller
        .dir_in            (step_dir),
        .trk0_out          (qic_trk0_out),
        .index_out         (qic_index_out),
        // Drive interface
        .tape_motor_on     (qic_motor_on),
        .tape_direction    (qic_direction),
        .tape_rdata        (active_read_data),
        .tape_wdata        (),                        // Not connected yet
        .tape_write_protect(tape_write_protect),
        .tape_cartridge_in (tape_cartridge_in),
        // Data interface
        .write_enable      (1'b0),
        .write_data        (8'd0),
        .write_strobe      (1'b0),
        .read_data         (qic_read_data),
        .read_valid        (qic_read_valid),
        // MFM data from DPLL
        .mfm_data_in       (dpll_data_bit),
        .mfm_clock         (dpll_data_ready),
        .dpll_locked       (dpll_locked),
        // Status outputs
        .current_command   (qic_current_command),
        .command_strobe    (qic_command_strobe),
        .segment_position  (tape_segment),
        .track_position    (tape_track),
        .tape_status       (tape_status),
        .command_active    (tape_command_active),
        .tape_ready        (tape_ready),
        .tape_error        (tape_error),
        // Data streamer status
        .block_sync        (qic_block_sync),
        .byte_in_block     (qic_byte_in_block),
        .block_in_segment  (qic_block_in_segment),
        .segment_complete  (qic_segment_complete),
        .file_mark_detect  (qic_file_mark)
    );

    // Assign tape last command output
    assign tape_last_command = qic_current_command;

    //-------------------------------------------------------------------------
    // Output Assignments
    //-------------------------------------------------------------------------
    assign current_track  = step_current_track;
    assign seek_complete  = step_seek_complete;
    assign at_track0      = tape_mode_en ? qic_trk0_out : step_at_track0;  // In tape mode, TRK0 is status
    assign pll_locked     = dpll_locked;
    assign lock_quality   = dpll_quality;
    assign sync_acquired  = am_sync_acquired;

    // Flux capture outputs
    assign flux_valid     = flux_edge_detected;
    assign flux_timestamp = timestamp_counter;
    assign flux_index     = tape_mode_en ? qic_index_out : active_index;  // In tape mode, INDEX is segment marker

    // 8" drive support - head load solenoid control
    assign head_load      = step_head_load;

    // Track density detection status outputs
    assign track_density_detected = analyzer_complete;
    assign detected_40_track      = analyzer_double_step;

endmodule
