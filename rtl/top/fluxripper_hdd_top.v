//-----------------------------------------------------------------------------
// FluxRipper HDD Top Module
// FPGA-based ST-506 MFM/RLL/ESDI Hard Drive Interface
//
// ST-506 Dual-Drive Topology (CORRECT):
//   - 1x 34-pin control cable (daisy-chained to both drives)
//   - 2x 20-pin data cables (one per drive, directly to FPGA)
//
// The 34-pin cable is shared between both drives. Drive selection is via
// DS0/DS1 signals. Only the selected drive responds to control signals
// and provides status. Both drives share the same seek controller logic,
// but have separate position tracking.
//
// Each drive has its own dedicated 20-pin data cable providing independent
// read/write data paths. This allows capturing flux from either drive
// without cable swapping.
//
// Clock Domain: 300 MHz (HDD domain)
// Supported: MFM (5 Mbps), RLL (7.5 Mbps), ESDI (10-15 Mbps)
//
// Created: 2025-12-03 16:30
// Updated: 2025-12-05 00:20 - Corrected dual-HDD topology (1x34 + 2x20)
//-----------------------------------------------------------------------------

module fluxripper_hdd_top (
    //-------------------------------------------------------------------------
    // System
    //-------------------------------------------------------------------------
    input  wire        clk_200mhz,       // Input clock from system
    input  wire        clk_300mhz,       // HDD domain clock (from clk_wizard_hdd)
    input  wire        clk_300mhz_valid, // 300 MHz clock is stable
    input  wire        reset_n,          // Active low reset

    //-------------------------------------------------------------------------
    // CPU/AXI Interface (directly to AXI-Lite peripheral)
    //-------------------------------------------------------------------------
    input  wire [7:0]  axi_addr,         // Register address
    input  wire        axi_write,        // Write strobe
    input  wire        axi_read,         // Read strobe
    input  wire [31:0] axi_wdata,        // Write data
    output reg  [31:0] axi_rdata,        // Read data
    output wire        axi_ready,        // Transaction complete
    output wire        irq_hdd,          // HDD interrupt

    //-------------------------------------------------------------------------
    // ST-506 34-pin Control Cable (SHARED - daisy-chained to both drives)
    //-------------------------------------------------------------------------
    // Active-low outputs to cable
    output wire [3:0]  st506_head_sel_n,  // Pins 2,4,14,18 - Head select
    output wire        st506_step_n,      // Pin 24 - Step pulse
    output wire        st506_dir_n,       // Pin 34 - Direction (0=in, 1=out)
    output wire        st506_write_gate_n,// Pin 6 - Write gate
    output wire        st506_ds0_n,       // Pin 26 - Drive Select 0
    output wire        st506_ds1_n,       // Pin 28 - Drive Select 1

    // Active-low inputs from cable (directly from selected drive)
    input  wire        st506_seek_complete_n, // Pin 8 - Seek complete
    input  wire        st506_track00_n,       // Pin 10 - Track 0
    input  wire        st506_write_fault_n,   // Pin 12 - Write fault
    input  wire        st506_index_n,         // Pin 20 - Index pulse
    input  wire        st506_ready_n,         // Pin 22 - Drive ready

    //-------------------------------------------------------------------------
    // ST-506 20-pin Data Cable 0 (Drive 0 - dedicated)
    //-------------------------------------------------------------------------
    output wire        data0_write,       // Pin 13 - Write Data (SE)
    input  wire        data0_read,        // Pin 17 - Read Data (SE)
    output wire        data0_write_p,     // Pin 13 - Write Data + (ESDI)
    output wire        data0_write_n,     // Pin 14 - Write Data - (ESDI)
    input  wire        data0_read_p,      // Pin 17 - Read Data + (ESDI)
    input  wire        data0_read_n,      // Pin 18 - Read Data - (ESDI)

    //-------------------------------------------------------------------------
    // ST-506 20-pin Data Cable 1 (Drive 1 - dedicated)
    //-------------------------------------------------------------------------
    output wire        data1_write,       // Pin 13 - Write Data (SE)
    input  wire        data1_read,        // Pin 17 - Read Data (SE)
    output wire        data1_write_p,     // Pin 13 - Write Data + (ESDI)
    output wire        data1_write_n,     // Pin 14 - Write Data - (ESDI)
    input  wire        data1_read_p,      // Pin 17 - Read Data + (ESDI)
    input  wire        data1_read_n,      // Pin 18 - Read Data - (ESDI)

    //-------------------------------------------------------------------------
    // Flux Capture AXI-Stream Output (to DMA)
    //-------------------------------------------------------------------------
    output wire [31:0] m_axis_flux_tdata,
    output wire        m_axis_flux_tvalid,
    input  wire        m_axis_flux_tready,
    output wire        m_axis_flux_tlast,

    //-------------------------------------------------------------------------
    // Diagnostic Outputs
    //-------------------------------------------------------------------------
    output wire        hdd_pll_locked,
    output wire [7:0]  hdd_lock_quality,
    output wire [15:0] hdd_current_cylinder,
    output wire [2:0]  hdd_current_head,
    output wire [2:0]  hdd_mode,         // 0=MFM, 1=RLL, 2=ESDI
    output wire        hdd_busy,
    output wire        hdd_error
);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    wire reset = ~reset_n;
    wire clk_hdd = clk_300mhz;

    // Active drive selection
    reg         active_drive;             // 0 = Drive 0, 1 = Drive 1
    reg         drive0_enable;            // Drive 0 enabled
    reg         drive1_enable;            // Drive 1 enabled

    // Mode configuration (shared)
    reg  [2:0]  hdd_data_rate;            // Data rate selection
    reg         differential_mode;        // ESDI differential mode

    //-------------------------------------------------------------------------
    // Per-Drive State
    //-------------------------------------------------------------------------
    // Drive 0 state
    reg  [3:0]  reg_head_0;               // Head selection
    reg  [15:0] reg_target_cyl_0;         // Target cylinder
    reg  [15:0] current_cylinder_0;       // Current cylinder position
    reg         cmd_seek_0;
    reg         cmd_recal_0;
    reg         cmd_read_0;
    reg         cmd_write_0;

    // Drive 1 state
    reg  [3:0]  reg_head_1;
    reg  [15:0] reg_target_cyl_1;
    reg  [15:0] current_cylinder_1;
    reg         cmd_seek_1;
    reg         cmd_recal_1;
    reg         cmd_read_1;
    reg         cmd_write_1;

    // Per-drive status (sampled from shared cable)
    wire        drive0_seek_complete, drive0_track00, drive0_write_fault;
    wire        drive0_index, drive0_ready;
    wire        drive1_seek_complete, drive1_track00, drive1_write_fault;
    wire        drive1_index, drive1_ready;

    // Active drive status (real-time from cable)
    wire        active_seek_complete, active_track00, active_write_fault;
    wire        active_index, active_ready;

    //-------------------------------------------------------------------------
    // Control Registers
    //-------------------------------------------------------------------------
    reg  [31:0] reg_ctrl;
    reg  [31:0] reg_timing;

    wire ctrl_enable        = reg_ctrl[0];
    wire [1:0] ctrl_mode    = reg_ctrl[2:1];
    wire ctrl_diff_mode     = reg_ctrl[5];
    wire ctrl_flux_capture  = reg_ctrl[12];
    wire ctrl_discovery     = reg_ctrl[13];

    //-------------------------------------------------------------------------
    // Seek Controller (shared, operates on active drive)
    //-------------------------------------------------------------------------
    // The seek controller drives the shared 34-pin cable. It issues step
    // pulses to whichever drive is currently selected via DS0/DS1.

    wire        seek_busy;
    wire        seek_done;
    wire        seek_error;
    wire        step_request;
    wire        step_direction;
    wire        step_done;

    // Active drive's target and current position
    wire [15:0] active_target_cyl = active_drive ? reg_target_cyl_1 : reg_target_cyl_0;
    wire [15:0] active_current_cyl = active_drive ? current_cylinder_1 : current_cylinder_0;
    wire        active_cmd_seek = active_drive ? cmd_seek_1 : cmd_seek_0;
    wire        active_cmd_recal = active_drive ? cmd_recal_1 : cmd_recal_0;
    wire [3:0]  active_head_sel = active_drive ? reg_head_1 : reg_head_0;

    hdd_seek_controller u_seek_ctrl (
        .clk(clk_hdd),
        .reset_n(reset_n),
        .seek_start(active_cmd_seek),
        .target_cylinder(active_target_cyl),
        .recalibrate(active_cmd_recal),
        .seek_busy(seek_busy),
        .seek_done(seek_done),
        .seek_error(seek_error),
        .current_cylinder(),              // Not used - tracked per-drive
        .at_track00(),
        .step_pulse_width(reg_timing[15:0]),
        .step_rate(reg_timing[23:0]),
        .settle_time(24'd4500000),        // 15ms @ 300 MHz
        .seek_timeout(24'd150000000),     // 500ms @ 300 MHz
        .step_request(step_request),
        .step_direction(step_direction),
        .step_done_in(step_done),
        .seek_complete(active_seek_complete),
        .track00(active_track00),
        .drive_fault(active_write_fault),
        .drive_ready(active_ready)
    );

    // Step done acknowledgment (directly from seek_complete timing)
    assign step_done = active_seek_complete;

    //-------------------------------------------------------------------------
    // Per-Drive Cylinder Tracking
    //-------------------------------------------------------------------------
    // Each drive maintains its own cylinder position, updated when steps
    // are issued while that drive is selected.

    always @(posedge clk_hdd or negedge reset_n) begin
        if (!reset_n) begin
            current_cylinder_0 <= 16'd0;
            current_cylinder_1 <= 16'd0;
        end else begin
            // Drive 0 position tracking
            if (!active_drive && step_request) begin
                if (step_direction)
                    current_cylinder_0 <= (current_cylinder_0 > 0) ?
                                          current_cylinder_0 - 1 : 16'd0;
                else
                    current_cylinder_0 <= current_cylinder_0 + 1;
            end
            if (!active_drive && cmd_recal_0 && drive0_track00)
                current_cylinder_0 <= 16'd0;

            // Drive 1 position tracking
            if (active_drive && step_request) begin
                if (step_direction)
                    current_cylinder_1 <= (current_cylinder_1 > 0) ?
                                          current_cylinder_1 - 1 : 16'd0;
                else
                    current_cylinder_1 <= current_cylinder_1 + 1;
            end
            if (active_drive && cmd_recal_1 && drive1_track00)
                current_cylinder_1 <= 16'd0;
        end
    end

    //-------------------------------------------------------------------------
    // 34-pin Control Cable Multiplexer
    //-------------------------------------------------------------------------
    hdd_drive_mux u_drive_mux (
        .clk(clk_hdd),
        .reset_n(reset_n),

        .drive_sel(active_drive),
        .drive0_enable(drive0_enable),
        .drive1_enable(drive1_enable),

        .ctrl_head_sel(active_head_sel),
        .ctrl_step(step_request),
        .ctrl_direction(step_direction),
        .ctrl_write_gate(active_drive ? cmd_write_1 : cmd_write_0),

        // 34-pin cable outputs
        .st506_head_sel_n(st506_head_sel_n),
        .st506_step_n(st506_step_n),
        .st506_dir_n(st506_dir_n),
        .st506_write_gate_n(st506_write_gate_n),
        .st506_ds0_n(st506_ds0_n),
        .st506_ds1_n(st506_ds1_n),

        // 34-pin cable inputs
        .st506_seek_complete_n(st506_seek_complete_n),
        .st506_track00_n(st506_track00_n),
        .st506_write_fault_n(st506_write_fault_n),
        .st506_index_n(st506_index_n),
        .st506_ready_n(st506_ready_n),

        // Per-drive status (sampled)
        .drive0_seek_complete(drive0_seek_complete),
        .drive0_track00(drive0_track00),
        .drive0_write_fault(drive0_write_fault),
        .drive0_index(drive0_index),
        .drive0_ready(drive0_ready),

        .drive1_seek_complete(drive1_seek_complete),
        .drive1_track00(drive1_track00),
        .drive1_write_fault(drive1_write_fault),
        .drive1_index(drive1_index),
        .drive1_ready(drive1_ready),

        // Active drive status (real-time)
        .active_seek_complete(active_seek_complete),
        .active_track00(active_track00),
        .active_write_fault(active_write_fault),
        .active_index(active_index),
        .active_ready(active_ready)
    );

    //-------------------------------------------------------------------------
    // 20-pin Data Path Multiplexer
    //-------------------------------------------------------------------------
    wire        active_read_data;
    wire        active_read_data_p;
    wire        active_read_data_n;
    wire        ctrl_write_data = 1'b0;   // TODO: Connect to encoder
    wire        ctrl_write_data_p = 1'b0;
    wire        ctrl_write_data_n = 1'b1;

    hdd_data_mux u_data_mux (
        .clk(clk_hdd),
        .reset_n(reset_n),

        .drive_sel(active_drive),
        .differential_mode(differential_mode),

        .ctrl_write_data(ctrl_write_data),
        .ctrl_write_data_p(ctrl_write_data_p),
        .ctrl_write_data_n(ctrl_write_data_n),

        // 20-pin data cable 0
        .data0_write(data0_write),
        .data0_read(data0_read),
        .data0_write_p(data0_write_p),
        .data0_write_n(data0_write_n),
        .data0_read_p(data0_read_p),
        .data0_read_n(data0_read_n),

        // 20-pin data cable 1
        .data1_write(data1_write),
        .data1_read(data1_read),
        .data1_write_p(data1_write_p),
        .data1_write_n(data1_write_n),
        .data1_read_p(data1_read_p),
        .data1_read_n(data1_read_n),

        // Selected read data output
        .active_read_data(active_read_data),
        .active_read_data_p(active_read_data_p),
        .active_read_data_n(active_read_data_n)
    );

    //-------------------------------------------------------------------------
    // HDD NCO (300 MHz domain) - Shared
    //-------------------------------------------------------------------------
    wire        nco_bit_clk;
    wire [31:0] nco_phase_accum;
    wire        nco_sample_point;
    wire [15:0] nco_phase_adj = 16'd0;
    wire        nco_phase_adj_valid = 1'b0;

    wire nco_enable = cmd_read_0 || cmd_read_1 || ctrl_flux_capture;

    nco_hdd_multirate u_nco (
        .clk(clk_hdd),
        .reset(reset),
        .enable(nco_enable),
        .data_rate(hdd_data_rate),
        .phase_adj(nco_phase_adj),
        .phase_adj_valid(nco_phase_adj_valid),
        .bit_clk(nco_bit_clk),
        .phase_accum(nco_phase_accum),
        .sample_point(nco_sample_point)
    );

    //-------------------------------------------------------------------------
    // RLL Decoder (300 MHz domain) - Shared
    //-------------------------------------------------------------------------
    wire [7:0]  rll_data_byte;
    wire        rll_data_valid;
    wire        rll_sync_detected;
    wire        rll_decode_error;

    wire rll_enable = (active_drive ? cmd_read_1 : cmd_read_0) &&
                      (hdd_data_rate == 3'b001);

    rll_2_7_decoder u_rll_decoder (
        .clk(clk_hdd),
        .reset(reset),
        .enable(rll_enable),
        .code_bit(active_read_data),
        .code_valid(nco_sample_point),
        .data_out(rll_data_byte),
        .data_valid(rll_data_valid),
        .sync_detected(rll_sync_detected),
        .decode_error(rll_decode_error)
    );

    //-------------------------------------------------------------------------
    // Per-Drive Status Registers
    //-------------------------------------------------------------------------
    wire [31:0] reg_status_0 = {
        current_cylinder_0,               // [31:16]
        5'd0,                             // [15:11]
        seek_error && !active_drive,      // [10]
        seek_done && !active_drive,       // [9]
        seek_busy && !active_drive,       // [8]
        3'd0,                             // [7:5]
        drive0_index,                     // [4]
        drive0_write_fault,               // [3]
        drive0_track00,                   // [2]
        drive0_seek_complete,             // [1]
        drive0_ready                      // [0]
    };

    wire [31:0] reg_status_1 = {
        current_cylinder_1,               // [31:16]
        5'd0,                             // [15:11]
        seek_error && active_drive,       // [10]
        seek_done && active_drive,        // [9]
        seek_busy && active_drive,        // [8]
        3'd0,                             // [7:5]
        drive1_index,                     // [4]
        drive1_write_fault,               // [3]
        drive1_track00,                   // [2]
        drive1_seek_complete,             // [1]
        drive1_ready                      // [0]
    };

    //-------------------------------------------------------------------------
    // Register Read/Write Logic
    //-------------------------------------------------------------------------
    assign axi_ready = 1'b1;

    always @(posedge clk_200mhz) begin
        if (reset) begin
            reg_ctrl <= 32'd0;
            reg_timing <= {8'd0, 24'd2400000};
            hdd_data_rate <= 3'b000;
            differential_mode <= 1'b0;
            active_drive <= 1'b0;
            drive0_enable <= 1'b0;
            drive1_enable <= 1'b0;

            reg_head_0 <= 4'd0;
            reg_target_cyl_0 <= 16'd0;
            cmd_seek_0 <= 1'b0;
            cmd_recal_0 <= 1'b0;
            cmd_read_0 <= 1'b0;
            cmd_write_0 <= 1'b0;

            reg_head_1 <= 4'd0;
            reg_target_cyl_1 <= 16'd0;
            cmd_seek_1 <= 1'b0;
            cmd_recal_1 <= 1'b0;
            cmd_read_1 <= 1'b0;
            cmd_write_1 <= 1'b0;
        end else begin
            // Auto-clear single-shot commands
            cmd_seek_0 <= 1'b0;
            cmd_recal_0 <= 1'b0;
            cmd_seek_1 <= 1'b0;
            cmd_recal_1 <= 1'b0;

            if (axi_write) begin
                case (axi_addr[7:2])
                    6'h00: begin  // HDD_CTRL (0x00)
                        reg_ctrl <= axi_wdata;
                        active_drive <= axi_wdata[8];
                        drive0_enable <= axi_wdata[16];
                        drive1_enable <= axi_wdata[17];
                    end
                    6'h01: reg_timing <= axi_wdata;
                    6'h02: begin
                        hdd_data_rate <= axi_wdata[2:0];
                        differential_mode <= axi_wdata[5];
                    end

                    // Drive 0
                    6'h05: begin
                        cmd_seek_0 <= axi_wdata[0];
                        cmd_recal_0 <= axi_wdata[1];
                        cmd_read_0 <= axi_wdata[2];
                        cmd_write_0 <= axi_wdata[3];
                        reg_head_0 <= axi_wdata[7:4];
                    end
                    6'h06: reg_target_cyl_0 <= axi_wdata[15:0];

                    // Drive 1
                    6'h0D: begin
                        cmd_seek_1 <= axi_wdata[0];
                        cmd_recal_1 <= axi_wdata[1];
                        cmd_read_1 <= axi_wdata[2];
                        cmd_write_1 <= axi_wdata[3];
                        reg_head_1 <= axi_wdata[7:4];
                    end
                    6'h0E: reg_target_cyl_1 <= axi_wdata[15:0];
                endcase
            end

            // Clear commands on completion
            if (seek_done || seek_error) begin
                if (!active_drive) begin
                    cmd_read_0 <= 1'b0;
                    cmd_write_0 <= 1'b0;
                end else begin
                    cmd_read_1 <= 1'b0;
                    cmd_write_1 <= 1'b0;
                end
            end
        end
    end

    always @(*) begin
        case (axi_addr[7:2])
            6'h00: axi_rdata = reg_ctrl;
            6'h01: axi_rdata = reg_timing;
            6'h02: axi_rdata = {26'd0, differential_mode, 2'd0, hdd_data_rate};
            6'h04: axi_rdata = reg_status_0;
            6'h05: axi_rdata = {24'd0, reg_head_0, cmd_write_0, cmd_read_0, cmd_recal_0, cmd_seek_0};
            6'h06: axi_rdata = {16'd0, reg_target_cyl_0};
            6'h0C: axi_rdata = reg_status_1;
            6'h0D: axi_rdata = {24'd0, reg_head_1, cmd_write_1, cmd_read_1, cmd_recal_1, cmd_seek_1};
            6'h0E: axi_rdata = {16'd0, reg_target_cyl_1};
            default: axi_rdata = 32'd0;
        endcase
    end

    //-------------------------------------------------------------------------
    // Outputs
    //-------------------------------------------------------------------------
    assign m_axis_flux_tdata = 32'd0;
    assign m_axis_flux_tvalid = 1'b0;
    assign m_axis_flux_tlast = 1'b0;

    assign hdd_pll_locked = clk_300mhz_valid;
    assign hdd_lock_quality = 8'd200;
    assign hdd_current_cylinder = active_drive ? current_cylinder_1 : current_cylinder_0;
    assign hdd_current_head = active_drive ? reg_head_1[2:0] : reg_head_0[2:0];
    assign hdd_mode = hdd_data_rate;
    assign hdd_busy = seek_busy || cmd_read_0 || cmd_read_1 || cmd_write_0 || cmd_write_1;
    assign hdd_error = seek_error || rll_decode_error ||
                       drive0_write_fault || drive1_write_fault;

    //-------------------------------------------------------------------------
    // Interrupt
    //-------------------------------------------------------------------------
    reg irq_reg;
    always @(posedge clk_200mhz) begin
        if (reset)
            irq_reg <= 1'b0;
        else
            irq_reg <= seek_done || seek_error || rll_data_valid;
    end
    assign irq_hdd = irq_reg;

endmodule
