//==============================================================================
// HDD Drive Multiplexer
//==============================================================================
// File: hdd_drive_mux.v
// Description: Multiplexes control signals between two drives on a shared
//              34-pin ST-506 control cable. Each drive has its own 20-pin
//              data cable but shares the control cable via DS0/DS1 selection.
//
// ST-506 Dual-Drive Topology:
//   - 1x 34-pin control cable (daisy-chained to both drives)
//   - 2x 20-pin data cables (one per drive)
//
// The 34-pin cable carries:
//   - Drive Select (DS0/DS1) - selects which drive responds
//   - Step, Direction, Write Gate - active only when drive is selected
//   - Head Select - active only when drive is selected
//   - Status signals (SEEK_COMPLETE, TRACK00, etc.) - from selected drive
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-05 00:15
//==============================================================================

`timescale 1ns / 1ps

module hdd_drive_mux (
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Drive Selection
    //=========================================================================
    input  wire        drive_sel,         // 0 = Drive 0, 1 = Drive 1
    input  wire        drive0_enable,     // Drive 0 enabled
    input  wire        drive1_enable,     // Drive 1 enabled

    //=========================================================================
    // Controller Outputs (active drive's commands)
    //=========================================================================
    input  wire [3:0]  ctrl_head_sel,     // Head select from controller
    input  wire        ctrl_step,         // Step pulse from seek controller
    input  wire        ctrl_direction,    // Step direction
    input  wire        ctrl_write_gate,   // Write gate

    //=========================================================================
    // 34-pin Control Cable Outputs (directly to connector)
    //=========================================================================
    output wire [3:0]  st506_head_sel_n,  // Pins 2, 4, 14, 18 (active low)
    output wire        st506_step_n,      // Pin 24 (active low)
    output wire        st506_dir_n,       // Pin 34 (active low)
    output wire        st506_write_gate_n,// Pin 6 (active low)
    output wire        st506_ds0_n,       // Pin 26 (Drive Select 0, active low)
    output wire        st506_ds1_n,       // Pin 28 (Drive Select 1, active low)
    // Note: Some controllers use reduced write current on Pin 2 for DS2/DS3

    //=========================================================================
    // 34-pin Control Cable Inputs (directly from connector)
    //=========================================================================
    input  wire        st506_seek_complete_n, // Pin 8 (active low)
    input  wire        st506_track00_n,       // Pin 10 (active low)
    input  wire        st506_write_fault_n,   // Pin 12 (active low)
    input  wire        st506_index_n,         // Pin 20 (active low)
    input  wire        st506_ready_n,         // Pin 22 (active low)

    //=========================================================================
    // Per-Drive Status Outputs (directly from selected drive)
    //=========================================================================
    output wire        drive0_seek_complete,
    output wire        drive0_track00,
    output wire        drive0_write_fault,
    output wire        drive0_index,
    output wire        drive0_ready,

    output wire        drive1_seek_complete,
    output wire        drive1_track00,
    output wire        drive1_write_fault,
    output wire        drive1_index,
    output wire        drive1_ready,

    //=========================================================================
    // Active Drive Status (directly from currently selected drive)
    //=========================================================================
    output wire        active_seek_complete,
    output wire        active_track00,
    output wire        active_write_fault,
    output wire        active_index,
    output wire        active_ready
);

    //=========================================================================
    // Drive Select Logic
    //=========================================================================
    // On a real ST-506 system, only one DS line is active at a time.
    // The selected drive responds to control signals and provides status.
    // Unselected drives ignore control signals but may still be spinning.

    // DS0/DS1 directly from selection
    assign st506_ds0_n = ~(~drive_sel && drive0_enable);  // Active low when drive_sel=0
    assign st506_ds1_n = ~(drive_sel && drive1_enable);   // Active low when drive_sel=1

    // Both disabled - neither drive selected (for safety during initialization)
    wire any_drive_active = (drive0_enable && !drive_sel) || (drive1_enable && drive_sel);

    //=========================================================================
    // Control Signal Routing
    //=========================================================================
    // Control signals are active only when a drive is selected.
    // All active-low on the 34-pin cable.

    // Head select (directly passed, active-low)
    assign st506_head_sel_n = any_drive_active ? ~ctrl_head_sel : 4'hF;

    // Step pulse (active-low, only when drive selected)
    assign st506_step_n = any_drive_active ? ~ctrl_step : 1'b1;

    // Direction (active-low, 0=in, 1=out)
    assign st506_dir_n = any_drive_active ? ~ctrl_direction : 1'b1;

    // Write gate (active-low)
    assign st506_write_gate_n = any_drive_active ? ~ctrl_write_gate : 1'b1;

    //=========================================================================
    // Status Signal Routing
    //=========================================================================
    // Status signals come from the cable and are valid for the selected drive.
    // Since both drives share the cable, we sample when the appropriate DS is active.

    // Convert active-low inputs to active-high
    wire seek_complete_raw = ~st506_seek_complete_n;
    wire track00_raw       = ~st506_track00_n;
    wire write_fault_raw   = ~st506_write_fault_n;
    wire index_raw         = ~st506_index_n;
    wire ready_raw         = ~st506_ready_n;

    //=========================================================================
    // Per-Drive Status Sampling
    //=========================================================================
    // Each drive's status is captured when that drive is selected.
    // This allows reading both drives' status even with a shared cable.

    reg drive0_seek_complete_r, drive0_track00_r, drive0_write_fault_r;
    reg drive0_index_r, drive0_ready_r;
    reg drive1_seek_complete_r, drive1_track00_r, drive1_write_fault_r;
    reg drive1_index_r, drive1_ready_r;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            drive0_seek_complete_r <= 1'b0;
            drive0_track00_r       <= 1'b0;
            drive0_write_fault_r   <= 1'b0;
            drive0_index_r         <= 1'b0;
            drive0_ready_r         <= 1'b0;

            drive1_seek_complete_r <= 1'b0;
            drive1_track00_r       <= 1'b0;
            drive1_write_fault_r   <= 1'b0;
            drive1_index_r         <= 1'b0;
            drive1_ready_r         <= 1'b0;
        end else begin
            // Sample Drive 0 status when DS0 is active
            if (!st506_ds0_n) begin
                drive0_seek_complete_r <= seek_complete_raw;
                drive0_track00_r       <= track00_raw;
                drive0_write_fault_r   <= write_fault_raw;
                drive0_index_r         <= index_raw;
                drive0_ready_r         <= ready_raw;
            end

            // Sample Drive 1 status when DS1 is active
            if (!st506_ds1_n) begin
                drive1_seek_complete_r <= seek_complete_raw;
                drive1_track00_r       <= track00_raw;
                drive1_write_fault_r   <= write_fault_raw;
                drive1_index_r         <= index_raw;
                drive1_ready_r         <= ready_raw;
            end
        end
    end

    // Output registered per-drive status
    assign drive0_seek_complete = drive0_seek_complete_r;
    assign drive0_track00       = drive0_track00_r;
    assign drive0_write_fault   = drive0_write_fault_r;
    assign drive0_index         = drive0_index_r;
    assign drive0_ready         = drive0_ready_r;

    assign drive1_seek_complete = drive1_seek_complete_r;
    assign drive1_track00       = drive1_track00_r;
    assign drive1_write_fault   = drive1_write_fault_r;
    assign drive1_index         = drive1_index_r;
    assign drive1_ready         = drive1_ready_r;

    // Active drive status (directly from cable, real-time)
    assign active_seek_complete = seek_complete_raw;
    assign active_track00       = track00_raw;
    assign active_write_fault   = write_fault_raw;
    assign active_index         = index_raw;
    assign active_ready         = ready_raw;

endmodule

//==============================================================================
// HDD Data Path Multiplexer
//==============================================================================
// Manages the two separate 20-pin data cables for dual-drive configuration.
// Each drive has its own data path; this module selects which one is active.
//==============================================================================

module hdd_data_mux (
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Drive Selection
    //=========================================================================
    input  wire        drive_sel,         // 0 = Drive 0, 1 = Drive 1
    input  wire        differential_mode, // ESDI differential mode

    //=========================================================================
    // Controller Write Data (to active drive)
    //=========================================================================
    input  wire        ctrl_write_data,   // Write data from encoder
    input  wire        ctrl_write_data_p, // Differential write data +
    input  wire        ctrl_write_data_n, // Differential write data -

    //=========================================================================
    // 20-pin Data Cable 0 (Drive 0)
    //=========================================================================
    output wire        data0_write,       // Pin 13 (Write Data, SE)
    input  wire        data0_read,        // Pin 17 (Read Data, SE)
    output wire        data0_write_p,     // Pin 13 (Write Data +, ESDI)
    output wire        data0_write_n,     // Pin 14 (Write Data -, ESDI)
    input  wire        data0_read_p,      // Pin 17 (Read Data +, ESDI)
    input  wire        data0_read_n,      // Pin 18 (Read Data -, ESDI)

    //=========================================================================
    // 20-pin Data Cable 1 (Drive 1)
    //=========================================================================
    output wire        data1_write,       // Pin 13 (Write Data, SE)
    input  wire        data1_read,        // Pin 17 (Read Data, SE)
    output wire        data1_write_p,     // Pin 13 (Write Data +, ESDI)
    output wire        data1_write_n,     // Pin 14 (Write Data -, ESDI)
    input  wire        data1_read_p,      // Pin 17 (Read Data +, ESDI)
    input  wire        data1_read_n,      // Pin 18 (Read Data -, ESDI)

    //=========================================================================
    // Selected Read Data Output (to decoder)
    //=========================================================================
    output wire        active_read_data,     // SE read data from active drive
    output wire        active_read_data_p,   // Differential + from active drive
    output wire        active_read_data_n    // Differential - from active drive
);

    //=========================================================================
    // Write Data Routing
    //=========================================================================
    // Route write data only to the selected drive

    // Single-ended write
    assign data0_write = !drive_sel ? ctrl_write_data : 1'b0;
    assign data1_write = drive_sel  ? ctrl_write_data : 1'b0;

    // Differential write (ESDI)
    assign data0_write_p = !drive_sel ? ctrl_write_data_p : 1'b0;
    assign data0_write_n = !drive_sel ? ctrl_write_data_n : 1'b1;
    assign data1_write_p = drive_sel  ? ctrl_write_data_p : 1'b0;
    assign data1_write_n = drive_sel  ? ctrl_write_data_n : 1'b1;

    //=========================================================================
    // Read Data Selection
    //=========================================================================
    // Select read data from the active drive

    // Single-ended read
    wire se_read = drive_sel ? data1_read : data0_read;

    // Differential read (ESDI)
    wire diff_read_p = drive_sel ? data1_read_p : data0_read_p;
    wire diff_read_n = drive_sel ? data1_read_n : data0_read_n;

    // Output based on mode
    assign active_read_data   = differential_mode ? (diff_read_p & ~diff_read_n) : se_read;
    assign active_read_data_p = diff_read_p;
    assign active_read_data_n = diff_read_n;

endmodule
