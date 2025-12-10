//==============================================================================
// WD Controller Command FSM
//==============================================================================
// File: wd_command_fsm.v
// Description: Command state machine for WD1002/WD1003/WD1006/WD1007 controller
//              emulation. Interprets AT-compatible commands and coordinates
//              with the HDD HAL (seek controller, track buffer).
//
// Transfer Modes:
//   - PIO Mode (AT): CPU-driven REP INSW/OUTSW transfers
//   - DMA Mode (XT): 8237 DMA channel 3 transfers (WD1002 compatible)
//
// Supported Commands:
//   0x10-0x1F: RESTORE (Recalibrate) - Seek to track 0
//   0x20:      READ_SECTORS         - Read sector(s) from disk
//   0x22:      READ_LONG            - Read sector + ECC (WD1006+)
//   0x30:      WRITE_SECTORS        - Write sector(s) to disk
//   0x32:      WRITE_LONG           - Write sector + ECC (WD1006+)
//   0x40:      VERIFY               - Verify sector(s) without data
//   0x50:      FORMAT_TRACK         - Format current track
//   0x70-0x7F: SEEK                 - Seek to cylinder
//   0x90:      GET_DIAG             - Run diagnostics (WD1006+)
//   0x91:      SET_PARAMS           - Set drive geometry (WD1006+)
//   0xEC:      GET_ID               - Identify drive (WD1007/ESDI)
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04
//==============================================================================

`timescale 1ns / 1ps

module wd_command_fsm (
    input  wire        clk,
    input  wire        reset_n,

    //-------------------------------------------------------------------------
    // Command Interface (from wd_registers)
    //-------------------------------------------------------------------------
    input  wire [7:0]  cmd_code,          // Command code
    input  wire        cmd_valid,         // Command valid pulse

    //-------------------------------------------------------------------------
    // Address/Geometry (from wd_registers)
    //-------------------------------------------------------------------------
    input  wire [15:0] cylinder,          // Target cylinder
    input  wire [3:0]  head,              // Target head
    input  wire [7:0]  sector_num,        // Starting sector number
    input  wire [7:0]  sector_count,      // Number of sectors
    input  wire        drive_sel,         // Selected drive

    //-------------------------------------------------------------------------
    // Status Outputs (to wd_registers)
    //-------------------------------------------------------------------------
    output reg         status_bsy,        // Busy
    output reg         status_rdy,        // Ready
    output reg         status_wf,         // Write Fault
    output reg         status_sc,         // Seek Complete
    output reg         status_drq,        // Data Request
    output reg         status_corr,       // Corrected data
    output reg         status_idx,        // Index pulse
    output reg         status_err,        // Error occurred
    output reg  [7:0]  error_code,        // Error register value

    //-------------------------------------------------------------------------
    // Sector Count Control
    //-------------------------------------------------------------------------
    output reg         dec_sector_count,  // Decrement sector count

    //-------------------------------------------------------------------------
    // Seek Controller Interface
    //-------------------------------------------------------------------------
    output reg         seek_start,        // Start seek operation
    output reg         recalibrate,       // Recalibrate (seek to 0)
    output reg  [15:0] target_cylinder,   // Target cylinder for seek
    input  wire        seek_busy,         // Seek in progress
    input  wire        seek_done,         // Seek completed
    input  wire        seek_error,        // Seek failed
    input  wire        track00,           // At track 0

    //-------------------------------------------------------------------------
    // Track Buffer Interface
    //-------------------------------------------------------------------------
    output reg         buf_fill_start,    // Start filling buffer from disk
    output reg         buf_flush_start,   // Start flushing buffer to disk
    output reg  [7:0]  buf_target_sector, // Sector to read/write
    output reg  [3:0]  buf_target_head,   // Head for buffer operation
    input  wire        buf_ready,         // Buffer operation complete
    input  wire        buf_error,         // Buffer operation failed

    //-------------------------------------------------------------------------
    // Data Transfer Interface
    //-------------------------------------------------------------------------
    output reg         data_xfer_start,   // Start data transfer to/from host
    output reg         data_xfer_dir,     // 0=read(disk→host), 1=write(host→disk)
    input  wire        data_xfer_done,    // Transfer complete
    input  wire        data_xfer_count,   // Bytes transferred

    //-------------------------------------------------------------------------
    // Feature Configuration
    //-------------------------------------------------------------------------
    input  wire [2:0]  wd_variant,        // 0=WD1003, 1=WD1006, 2=WD1007
    input  wire [31:0] wd_features,       // Feature flags

    //-------------------------------------------------------------------------
    // DMA Mode (XT compatibility)
    //-------------------------------------------------------------------------
    input  wire        dma_mode,          // DMA mode enabled (XT uses DMA ch.3)

    //-------------------------------------------------------------------------
    // Drive Status
    //-------------------------------------------------------------------------
    input  wire        drive_ready,       // Drive is ready
    input  wire        write_fault,       // Write fault from drive
    input  wire        index_pulse        // Index pulse from drive
);

    //=========================================================================
    // Command Codes
    //=========================================================================
    localparam CMD_RESTORE      = 4'h1;   // 0x10-0x1F (upper nibble)
    localparam CMD_READ         = 8'h20;
    localparam CMD_READ_LONG    = 8'h22;
    localparam CMD_WRITE        = 8'h30;
    localparam CMD_WRITE_LONG   = 8'h32;
    localparam CMD_VERIFY       = 8'h40;
    localparam CMD_FORMAT       = 8'h50;
    localparam CMD_SEEK         = 4'h7;   // 0x70-0x7F (upper nibble)
    localparam CMD_DIAG         = 8'h90;
    localparam CMD_SET_PARAMS   = 8'h91;
    localparam CMD_GET_ID       = 8'hEC;

    //=========================================================================
    // Error Codes
    //=========================================================================
    localparam ERR_NONE     = 8'h00;
    localparam ERR_AMNF     = 8'h01;  // Address Mark Not Found
    localparam ERR_TK0NF    = 8'h02;  // Track 0 Not Found
    localparam ERR_ABRT     = 8'h04;  // Command Aborted
    localparam ERR_IDNF     = 8'h10;  // ID Not Found
    localparam ERR_UNC      = 8'h40;  // Uncorrectable error
    localparam ERR_BBK      = 8'h80;  // Bad Block

    //=========================================================================
    // FSM States
    //=========================================================================
    localparam [4:0] ST_IDLE         = 5'd0;
    localparam [4:0] ST_CMD_DECODE   = 5'd1;
    localparam [4:0] ST_RESTORE      = 5'd2;
    localparam [4:0] ST_RECAL_WAIT   = 5'd3;
    localparam [4:0] ST_SEEK         = 5'd4;
    localparam [4:0] ST_SEEK_WAIT    = 5'd5;
    localparam [4:0] ST_READ_SETUP   = 5'd6;
    localparam [4:0] ST_READ_FILL    = 5'd7;
    localparam [4:0] ST_READ_XFER    = 5'd8;
    localparam [4:0] ST_READ_NEXT    = 5'd9;
    localparam [4:0] ST_WRITE_SETUP  = 5'd10;
    localparam [4:0] ST_WRITE_WAIT   = 5'd11;
    localparam [4:0] ST_WRITE_FLUSH  = 5'd12;
    localparam [4:0] ST_WRITE_NEXT   = 5'd13;
    localparam [4:0] ST_VERIFY_SETUP = 5'd14;
    localparam [4:0] ST_VERIFY_CHK   = 5'd15;
    localparam [4:0] ST_FORMAT       = 5'd16;
    localparam [4:0] ST_DIAG         = 5'd17;
    localparam [4:0] ST_SET_PARAMS   = 5'd18;
    localparam [4:0] ST_GET_ID       = 5'd19;
    localparam [4:0] ST_COMPLETE     = 5'd20;
    localparam [4:0] ST_ERROR        = 5'd21;

    reg [4:0] state;
    reg [4:0] next_state;

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [7:0]  r_current_sector;     // Current sector being processed
    reg [7:0]  r_sectors_remaining;  // Sectors left to process
    reg [7:0]  r_cmd_code;           // Latched command code
    reg        r_read_long;          // Read long (with ECC)
    reg        r_write_long;         // Write long (with ECC)

    //=========================================================================
    // Index Pulse Edge Detection (for IDX status bit)
    //=========================================================================
    reg r_index_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            r_index_prev <= 1'b0;
        else
            r_index_prev <= index_pulse;
    end
    wire index_edge = index_pulse && !r_index_prev;

    //=========================================================================
    // Status Index Bit (set on index pulse, cleared on status read)
    //=========================================================================
    // Note: This is managed externally or we just pass through index_pulse
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            status_idx <= 1'b0;
        else if (index_edge)
            status_idx <= 1'b1;
        else if (state == ST_IDLE)
            status_idx <= 1'b0;  // Clear when idle
    end

    //=========================================================================
    // Main FSM
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state              <= ST_IDLE;
            status_bsy         <= 1'b0;
            status_rdy         <= 1'b1;
            status_wf          <= 1'b0;
            status_sc          <= 1'b1;
            status_drq         <= 1'b0;
            status_corr        <= 1'b0;
            status_err         <= 1'b0;
            error_code         <= ERR_NONE;
            seek_start         <= 1'b0;
            recalibrate        <= 1'b0;
            target_cylinder    <= 16'h0000;
            buf_fill_start     <= 1'b0;
            buf_flush_start    <= 1'b0;
            buf_target_sector  <= 8'h00;
            buf_target_head    <= 4'h0;
            data_xfer_start    <= 1'b0;
            data_xfer_dir      <= 1'b0;
            dec_sector_count   <= 1'b0;
            r_current_sector   <= 8'h01;
            r_sectors_remaining<= 8'h00;
            r_cmd_code         <= 8'h00;
            r_read_long        <= 1'b0;
            r_write_long       <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            seek_start       <= 1'b0;
            recalibrate      <= 1'b0;
            buf_fill_start   <= 1'b0;
            buf_flush_start  <= 1'b0;
            data_xfer_start  <= 1'b0;
            dec_sector_count <= 1'b0;

            // Update write fault from drive
            status_wf <= write_fault;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    status_bsy <= 1'b0;
                    status_rdy <= drive_ready;
                    status_drq <= 1'b0;
                    status_err <= 1'b0;

                    if (cmd_valid) begin
                        r_cmd_code <= cmd_code;
                        status_bsy <= 1'b1;
                        status_rdy <= 1'b0;
                        state      <= ST_CMD_DECODE;
                    end
                end

                //-------------------------------------------------------------
                ST_CMD_DECODE: begin
                    // Latch parameters
                    r_current_sector    <= sector_num;
                    r_sectors_remaining <= sector_count;
                    r_read_long         <= 1'b0;
                    r_write_long        <= 1'b0;

                    // Decode command
                    casez (r_cmd_code)
                        8'h1?: begin  // RESTORE (0x10-0x1F)
                            state <= ST_RESTORE;
                        end

                        8'h20: begin  // READ_SECTORS
                            state <= ST_READ_SETUP;
                        end

                        8'h22: begin  // READ_LONG
                            if (wd_variant >= 3'd1) begin  // WD1006+
                                r_read_long <= 1'b1;
                                state <= ST_READ_SETUP;
                            end else begin
                                error_code <= ERR_ABRT;
                                state      <= ST_ERROR;
                            end
                        end

                        8'h30: begin  // WRITE_SECTORS
                            state <= ST_WRITE_SETUP;
                        end

                        8'h32: begin  // WRITE_LONG
                            if (wd_variant >= 3'd1) begin
                                r_write_long <= 1'b1;
                                state <= ST_WRITE_SETUP;
                            end else begin
                                error_code <= ERR_ABRT;
                                state      <= ST_ERROR;
                            end
                        end

                        8'h40: begin  // VERIFY
                            state <= ST_VERIFY_SETUP;
                        end

                        8'h50: begin  // FORMAT_TRACK
                            state <= ST_FORMAT;
                        end

                        8'h7?: begin  // SEEK (0x70-0x7F)
                            state <= ST_SEEK;
                        end

                        8'h90: begin  // GET_DIAG
                            if (wd_variant >= 3'd1) begin
                                state <= ST_DIAG;
                            end else begin
                                error_code <= ERR_ABRT;
                                state      <= ST_ERROR;
                            end
                        end

                        8'h91: begin  // SET_PARAMS
                            if (wd_variant >= 3'd1) begin
                                state <= ST_SET_PARAMS;
                            end else begin
                                error_code <= ERR_ABRT;
                                state      <= ST_ERROR;
                            end
                        end

                        8'hEC: begin  // GET_ID (Identify)
                            if (wd_variant >= 3'd2) begin  // WD1007/ESDI
                                state <= ST_GET_ID;
                            end else begin
                                error_code <= ERR_ABRT;
                                state      <= ST_ERROR;
                            end
                        end

                        default: begin
                            error_code <= ERR_ABRT;
                            state      <= ST_ERROR;
                        end
                    endcase
                end

                //-------------------------------------------------------------
                // RESTORE (Recalibrate)
                //-------------------------------------------------------------
                ST_RESTORE: begin
                    status_sc   <= 1'b0;
                    recalibrate <= 1'b1;
                    seek_start  <= 1'b1;
                    state       <= ST_RECAL_WAIT;
                end

                ST_RECAL_WAIT: begin
                    if (seek_done) begin
                        if (track00) begin
                            status_sc <= 1'b1;
                            state     <= ST_COMPLETE;
                        end else begin
                            error_code <= ERR_TK0NF;
                            state      <= ST_ERROR;
                        end
                    end else if (seek_error) begin
                        error_code <= ERR_TK0NF;
                        state      <= ST_ERROR;
                    end
                end

                //-------------------------------------------------------------
                // SEEK
                //-------------------------------------------------------------
                ST_SEEK: begin
                    status_sc       <= 1'b0;
                    target_cylinder <= cylinder;
                    seek_start      <= 1'b1;
                    state           <= ST_SEEK_WAIT;
                end

                ST_SEEK_WAIT: begin
                    if (seek_done) begin
                        status_sc <= 1'b1;
                        state     <= ST_COMPLETE;
                    end else if (seek_error) begin
                        error_code <= ERR_IDNF;  // Seek failed
                        state      <= ST_ERROR;
                    end
                end

                //-------------------------------------------------------------
                // READ_SECTORS / READ_LONG
                //-------------------------------------------------------------
                ST_READ_SETUP: begin
                    // Seek to target cylinder first
                    target_cylinder <= cylinder;
                    seek_start      <= 1'b1;
                    status_sc       <= 1'b0;
                    state           <= ST_READ_FILL;
                end

                ST_READ_FILL: begin
                    // Wait for seek, then fill buffer with sector data
                    if (seek_done || status_sc) begin
                        status_sc        <= 1'b1;
                        buf_target_sector<= r_current_sector;
                        buf_target_head  <= head;
                        buf_fill_start   <= 1'b1;
                        state            <= ST_READ_XFER;
                    end else if (seek_error) begin
                        error_code <= ERR_IDNF;
                        state      <= ST_ERROR;
                    end
                end

                ST_READ_XFER: begin
                    // Wait for buffer fill, then transfer to host
                    if (buf_ready) begin
                        status_drq      <= 1'b1;  // Request host to read
                        data_xfer_dir   <= 1'b0;  // Disk to host
                        data_xfer_start <= 1'b1;
                        state           <= ST_READ_NEXT;
                    end else if (buf_error) begin
                        error_code <= ERR_AMNF;
                        state      <= ST_ERROR;
                    end
                end

                ST_READ_NEXT: begin
                    // Wait for data transfer to complete
                    if (data_xfer_done) begin
                        status_drq       <= 1'b0;
                        dec_sector_count <= 1'b1;

                        if (r_sectors_remaining > 8'h01) begin
                            r_sectors_remaining <= r_sectors_remaining - 1'b1;
                            r_current_sector    <= r_current_sector + 1'b1;
                            state               <= ST_READ_FILL;
                        end else begin
                            state <= ST_COMPLETE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // WRITE_SECTORS / WRITE_LONG
                //-------------------------------------------------------------
                ST_WRITE_SETUP: begin
                    // Seek to target cylinder first
                    target_cylinder <= cylinder;
                    seek_start      <= 1'b1;
                    status_sc       <= 1'b0;
                    state           <= ST_WRITE_WAIT;
                end

                ST_WRITE_WAIT: begin
                    // Wait for seek, then request data from host
                    if (seek_done || status_sc) begin
                        status_sc       <= 1'b1;
                        status_drq      <= 1'b1;  // Request host to write
                        data_xfer_dir   <= 1'b1;  // Host to disk
                        data_xfer_start <= 1'b1;
                        state           <= ST_WRITE_FLUSH;
                    end else if (seek_error) begin
                        error_code <= ERR_IDNF;
                        state      <= ST_ERROR;
                    end
                end

                ST_WRITE_FLUSH: begin
                    // Wait for host data, then flush to disk
                    if (data_xfer_done) begin
                        status_drq       <= 1'b0;
                        buf_target_sector<= r_current_sector;
                        buf_target_head  <= head;
                        buf_flush_start  <= 1'b1;
                        state            <= ST_WRITE_NEXT;
                    end
                end

                ST_WRITE_NEXT: begin
                    // Wait for buffer flush to complete
                    if (buf_ready) begin
                        dec_sector_count <= 1'b1;

                        if (r_sectors_remaining > 8'h01) begin
                            r_sectors_remaining <= r_sectors_remaining - 1'b1;
                            r_current_sector    <= r_current_sector + 1'b1;
                            state               <= ST_WRITE_WAIT;
                        end else begin
                            state <= ST_COMPLETE;
                        end
                    end else if (buf_error) begin
                        error_code <= ERR_AMNF;
                        state      <= ST_ERROR;
                    end
                end

                //-------------------------------------------------------------
                // VERIFY
                //-------------------------------------------------------------
                ST_VERIFY_SETUP: begin
                    target_cylinder <= cylinder;
                    seek_start      <= 1'b1;
                    status_sc       <= 1'b0;
                    state           <= ST_VERIFY_CHK;
                end

                ST_VERIFY_CHK: begin
                    // Verify just checks that sectors exist (no data transfer)
                    if (seek_done || status_sc) begin
                        status_sc <= 1'b1;
                        // In emulation, we assume verify always passes
                        // Real implementation would read and check CRC
                        if (r_sectors_remaining > 8'h01) begin
                            r_sectors_remaining <= r_sectors_remaining - 1'b1;
                            r_current_sector    <= r_current_sector + 1'b1;
                            dec_sector_count    <= 1'b1;
                            // Stay in this state for simplicity
                        end else begin
                            dec_sector_count <= 1'b1;
                            state            <= ST_COMPLETE;
                        end
                    end else if (seek_error) begin
                        error_code <= ERR_IDNF;
                        state      <= ST_ERROR;
                    end
                end

                //-------------------------------------------------------------
                // FORMAT_TRACK
                //-------------------------------------------------------------
                ST_FORMAT: begin
                    // Format track - in emulation, this is a no-op
                    // Real implementation would write sector headers
                    status_sc <= 1'b1;
                    state     <= ST_COMPLETE;
                end

                //-------------------------------------------------------------
                // GET_DIAG (Diagnostics)
                //-------------------------------------------------------------
                ST_DIAG: begin
                    // Run diagnostics - always pass in emulation
                    error_code <= ERR_NONE;  // 0x01 would indicate pass
                    state      <= ST_COMPLETE;
                end

                //-------------------------------------------------------------
                // SET_PARAMS (Set Drive Parameters)
                //-------------------------------------------------------------
                ST_SET_PARAMS: begin
                    // Parameters already latched by wd_registers
                    // Just acknowledge success
                    state <= ST_COMPLETE;
                end

                //-------------------------------------------------------------
                // GET_ID (Identify Drive)
                //-------------------------------------------------------------
                ST_GET_ID: begin
                    // Fill buffer with identify data and transfer to host
                    status_drq      <= 1'b1;
                    data_xfer_dir   <= 1'b0;  // Disk to host
                    data_xfer_start <= 1'b1;
                    // Note: The identify data should be pre-loaded in buffer
                    state           <= ST_COMPLETE;
                end

                //-------------------------------------------------------------
                // COMPLETE - Command finished successfully
                //-------------------------------------------------------------
                ST_COMPLETE: begin
                    status_bsy <= 1'b0;
                    status_rdy <= drive_ready;
                    status_drq <= 1'b0;
                    status_err <= 1'b0;
                    error_code <= ERR_NONE;
                    state      <= ST_IDLE;
                end

                //-------------------------------------------------------------
                // ERROR - Command failed
                //-------------------------------------------------------------
                ST_ERROR: begin
                    status_bsy <= 1'b0;
                    status_rdy <= drive_ready;
                    status_drq <= 1'b0;
                    status_err <= 1'b1;
                    // error_code already set
                    state      <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
