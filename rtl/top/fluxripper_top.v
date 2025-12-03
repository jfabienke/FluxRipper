//-----------------------------------------------------------------------------
// FluxRipper Top Module
// FPGA-based Intel 82077AA Floppy Disk Controller Clone
//
// Based on CAPSImg CapsFDCEmulator
// Target: Xilinx Spartan UltraScale+ (UC+)
//
// Updated: 2025-12-02 17:00
//-----------------------------------------------------------------------------

module fluxripper_top (
    // System
    input  wire        clk_200mhz,      // 200 MHz system clock
    input  wire        reset_n,         // Active low reset

    // CPU Interface (directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly  directly directly-compatible)
    input  wire [2:0]  addr,            // A0-A2 register address
    input  wire        cs_n,            // Chip select
    input  wire        rd_n,            // Read strobe
    input  wire        wr_n,            // Write strobe
    inout  wire [7:0]  data,            // Bidirectional data bus
    output wire        irq,             // Interrupt request
    output wire        drq,             // DMA request

    // Drive 0 Interface
    output wire        drv0_step,       // Step pulse
    output wire        drv0_dir,        // Direction (1=in, 0=out)
    output wire        drv0_motor,      // Motor on
    output wire        drv0_head_sel,   // Head select (0=bottom, 1=top)
    output wire        drv0_write_gate, // Write gate
    output wire        drv0_write_data, // Write data
    input  wire        drv0_read_data,  // Read data (flux)
    input  wire        drv0_index,      // Index pulse
    input  wire        drv0_track0,     // Track 0 sensor
    input  wire        drv0_wp,         // Write protect
    input  wire        drv0_ready,      // Drive ready
    input  wire        drv0_dskchg,     // Disk change

    // Drive 1 Interface (active accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent-accent accent-same as drive 0)
    output wire        drv1_step,
    output wire        drv1_dir,
    output wire        drv1_motor,
    output wire        drv1_head_sel,
    output wire        drv1_write_gate,
    output wire        drv1_write_data,
    input  wire        drv1_read_data,
    input  wire        drv1_index,
    input  wire        drv1_track0,
    input  wire        drv1_wp,
    input  wire        drv1_ready,
    input  wire        drv1_dskchg,

    // Diagnostic outputs
    output wire        pll_locked,
    output wire [7:0]  lock_quality,
    output wire [7:0]  current_track,
    output wire        sync_acquired,

    // Status LEDs
    output wire        led_activity,
    output wire        led_error
);

    //-------------------------------------------------------------------------
    // Internal signals
    //-------------------------------------------------------------------------
    wire        reset = ~reset_n;
    wire        clk = clk_200mhz;

    // Data bus control
    reg  [7:0]  data_out;
    wire [7:0]  data_in = data;
    wire        data_oe;
    assign data = data_oe ? data_out : 8'hZZ;

    // Register interface signals
    wire [1:0]  data_rate;
    wire [3:0]  motor_on;
    wire [1:0]  drive_sel;
    wire        dma_enable;
    wire        sw_reset;
    wire [3:0]  precomp_delay;
    wire [3:0]  drive_ready_status;
    wire        fdc_busy;
    wire        fdc_ndma;
    wire [3:0]  fdc_dio;
    wire        fdc_rqm;

    // FIFO signals
    wire [7:0]  fifo_data_out;
    wire        fifo_write;
    wire [7:0]  fifo_data_in;
    wire        fifo_read;
    wire        fifo_empty;
    wire        fifo_full;

    // Drive mux signals
    wire        active_read_data;
    wire        active_index;
    wire        active_track0;
    wire        active_wp;
    wire        active_ready;
    wire        active_dskchg;

    // Command FSM signals
    wire        cmd_seek_start;
    wire [7:0]  cmd_seek_target;
    wire        cmd_restore;
    wire        cmd_read_enable;
    wire        cmd_write_enable;
    wire        cmd_crc_reset;
    wire [1:0]  cmd_head_select;

    // Step controller signals
    wire        step_pulse;
    wire        step_dir;
    wire        step_head_load;
    wire [7:0]  step_current_track;
    wire [7:0]  step_physical_track;
    wire        step_complete;
    wire        step_at_track0;
    wire        step_busy;

    // DPLL signals
    wire        dpll_data_bit;
    wire        dpll_data_ready;
    wire        dpll_bit_clk;
    wire        dpll_locked;
    wire [7:0]  dpll_quality;
    wire [1:0]  dpll_margin;

    // AM detector signals
    wire        am_a1_detected;
    wire        am_c2_detected;
    wire [1:0]  am_sync_count;
    wire        am_sync_acquired;
    wire [7:0]  am_data_byte;
    wire        am_byte_ready;

    // CRC signals
    wire        crc_enable;
    wire        crc_init;
    wire [7:0]  crc_data;
    wire [15:0] crc_value;
    wire        crc_valid;

    // Motor controller signals
    wire [3:0]  motor_running;
    wire [3:0]  motor_at_speed;

    // Status signals from command FSM
    wire [1:0]  st_int_code;
    wire        st_seek_end;
    wire        st_equipment_check;
    wire        st_end_of_cylinder;
    wire        st_data_error;
    wire        st_overrun;
    wire        st_no_data;
    wire        st_missing_am;

    //-------------------------------------------------------------------------
    // Drive multiplexer
    //-------------------------------------------------------------------------
    assign active_read_data = (drive_sel == 2'b00) ? drv0_read_data : drv1_read_data;
    assign active_index     = (drive_sel == 2'b00) ? drv0_index : drv1_index;
    assign active_track0    = (drive_sel == 2'b00) ? drv0_track0 : drv1_track0;
    assign active_wp        = (drive_sel == 2'b00) ? drv0_wp : drv1_wp;
    assign active_ready     = (drive_sel == 2'b00) ? drv0_ready : drv1_ready;
    assign active_dskchg    = (drive_sel == 2'b00) ? drv0_dskchg : drv1_dskchg;

    assign drive_ready_status = {drv1_ready, drv1_ready, drv0_ready, drv0_ready};

    //-------------------------------------------------------------------------
    // Register Interface
    //-------------------------------------------------------------------------
    fdc_registers u_registers (
        .clk(clk),
        .reset(reset || sw_reset),
        .addr(addr),
        .cs_n(cs_n),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .data_in(data_in),
        .data_out(data_out),
        .data_oe(data_oe),
        .data_rate(data_rate),
        .motor_on(motor_on),
        .drive_sel(drive_sel),
        .dma_enable(dma_enable),
        .reset_out(sw_reset),
        .precomp_delay(precomp_delay),
        .drive_ready(drive_ready_status),
        .busy(fdc_busy),
        .ndma(fdc_ndma),
        .dio(fdc_dio),
        .rqm(fdc_rqm),
        .fifo_data_out(fifo_data_out),
        .fifo_write(fifo_write),
        .fifo_data_in(fifo_data_in),
        .fifo_read(fifo_read),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full),
        .int_out(irq),
        .int_ack(1'b0)
    );

    //-------------------------------------------------------------------------
    // FIFO
    //-------------------------------------------------------------------------
    fdc_fifo u_fifo (
        .clk(clk),
        .reset(reset || sw_reset),
        .data_in(fifo_data_out),
        .write_en(fifo_write),
        .data_out(fifo_data_in),
        .read_en(fifo_read),
        .empty(fifo_empty),
        .full(fifo_full),
        .count(),
        .threshold(4'd1),
        .threshold_reached(drq)
    );

    //-------------------------------------------------------------------------
    // Command FSM
    //-------------------------------------------------------------------------
    command_fsm u_command_fsm (
        .clk(clk),
        .reset(reset || sw_reset),
        .enable(1'b1),
        .command_byte(fifo_data_out),
        .command_valid(fifo_write),
        .fifo_data(fifo_data_in),
        .fifo_empty(fifo_empty),
        .fifo_read(),
        .fifo_write_data(),
        .fifo_write(),
        .seek_start(cmd_seek_start),
        .seek_target(cmd_seek_target),
        .restore(cmd_restore),
        .seek_complete(step_complete),
        .current_track(step_current_track),
        .at_track0(step_at_track0),
        .read_enable(cmd_read_enable),
        .read_data(am_data_byte),
        .read_ready(am_byte_ready),
        .sync_acquired(am_sync_acquired),
        .a1_detected(am_a1_detected),
        .write_enable(cmd_write_enable),
        .write_data(),
        .write_valid(),
        .crc_reset(cmd_crc_reset),
        .crc_valid(crc_valid),
        .crc_value(crc_value),
        .head_select(cmd_head_select),
        .index_pulse(active_index),
        .write_protect(active_wp),
        .int_code(st_int_code),
        .seek_end(st_seek_end),
        .equipment_check(st_equipment_check),
        .end_of_cylinder(st_end_of_cylinder),
        .data_error(st_data_error),
        .overrun(st_overrun),
        .no_data(st_no_data),
        .missing_am(st_missing_am),
        .busy(fdc_busy),
        .dio(fdc_dio[0]),
        .rqm(fdc_rqm),
        .ndma(fdc_ndma),
        .interrupt()
    );

    //-------------------------------------------------------------------------
    // Step Controller
    //-------------------------------------------------------------------------
    step_controller u_step_ctrl (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),
        .step_rate_sel(2'b10),          // 2ms step rate
        .double_step(1'b0),             // Configurable
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
        .seek_complete(step_complete),
        .at_track0(step_at_track0),
        .busy(step_busy)
    );

    //-------------------------------------------------------------------------
    // Digital PLL (Data Separator)
    //-------------------------------------------------------------------------
    digital_pll u_dpll (
        .clk(clk),
        .reset(reset || sw_reset),
        .enable(cmd_read_enable),
        .data_rate(data_rate),
        .rpm_360(1'b0),                 // Configurable
        .lock_threshold(16'h1000),
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
        .reset(reset || sw_reset),
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
        .reset(reset || sw_reset),
        .enable(am_byte_ready),
        .init(cmd_crc_reset),
        .data_in(am_data_byte),
        .crc_out(crc_value),
        .crc_valid(crc_valid)
    );

    //-------------------------------------------------------------------------
    // Motor Controller
    //-------------------------------------------------------------------------
    motor_controller u_motor_ctrl (
        .clk(clk),
        .reset(reset || sw_reset),
        .clk_freq(32'd200_000_000),
        .motor_on_cmd(motor_on),
        .auto_off_enable(1'b1),
        .index_pulse(active_index),
        .motor_running(motor_running),
        .motor_at_speed(motor_at_speed),
        .revolution_count()
    );

    //-------------------------------------------------------------------------
    // Drive Output Assignments
    //-------------------------------------------------------------------------
    // Drive 0
    assign drv0_step       = (drive_sel == 2'b00) ? step_pulse : 1'b0;
    assign drv0_dir        = (drive_sel == 2'b00) ? step_dir : 1'b0;
    assign drv0_motor      = motor_running[0];
    assign drv0_head_sel   = (drive_sel == 2'b00) ? cmd_head_select[0] : 1'b0;
    assign drv0_write_gate = (drive_sel == 2'b00) ? cmd_write_enable : 1'b0;
    assign drv0_write_data = 1'b0;  // Connect to write path

    // Drive 1
    assign drv1_step       = (drive_sel == 2'b01) ? step_pulse : 1'b0;
    assign drv1_dir        = (drive_sel == 2'b01) ? step_dir : 1'b0;
    assign drv1_motor      = motor_running[1];
    assign drv1_head_sel   = (drive_sel == 2'b01) ? cmd_head_select[0] : 1'b0;
    assign drv1_write_gate = (drive_sel == 2'b01) ? cmd_write_enable : 1'b0;
    assign drv1_write_data = 1'b0;  // Connect to write path

    //-------------------------------------------------------------------------
    // Diagnostic Outputs
    //-------------------------------------------------------------------------
    assign pll_locked     = dpll_locked;
    assign lock_quality   = dpll_quality;
    assign current_track  = step_current_track;
    assign sync_acquired  = am_sync_acquired;

    //-------------------------------------------------------------------------
    // Status LEDs
    //-------------------------------------------------------------------------
    assign led_activity = motor_running[drive_sel] || fdc_busy;
    assign led_error    = st_data_error || st_missing_am || st_no_data;

endmodule
