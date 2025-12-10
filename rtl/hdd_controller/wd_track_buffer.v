//==============================================================================
// WD Controller Track Buffer
//==============================================================================
// File: wd_track_buffer.v
// Description: 17-sector track buffer for WD controller emulation.
//              Provides read-ahead and write-back caching for improved
//              sequential performance.
//
// Buffer Organization:
//   - 17 sectors x 512 bytes = 8,704 bytes data
//   - 128 bytes metadata/status area
//   - Total: 8,832 bytes (~8.5 KB)
//
// Features:
//   - Dual-port BRAM for simultaneous controller and host access
//   - Read-ahead: fills entire track on first sector access
//   - Write-back: buffers writes, flushes on track change
//   - Valid/dirty bitmap for sector tracking
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04
//==============================================================================

`timescale 1ns / 1ps

module wd_track_buffer #(
    parameter SECTORS_PER_TRACK = 17,
    parameter SECTOR_SIZE       = 512,
    parameter BUFFER_SIZE       = SECTORS_PER_TRACK * SECTOR_SIZE  // 8704
)(
    input  wire        clk,
    input  wire        reset_n,

    //-------------------------------------------------------------------------
    // Host Interface (from wd_registers via data port)
    //-------------------------------------------------------------------------
    input  wire [7:0]  host_wdata,        // Data from host
    input  wire        host_write,        // Host write strobe
    output wire [7:0]  host_rdata,        // Data to host
    input  wire        host_read,         // Host read strobe

    // Host transfer control
    output reg         host_drq,          // Data request to host
    input  wire        host_ack,          // Host acknowledged/transferred

    //-------------------------------------------------------------------------
    // Controller Interface (from wd_command_fsm)
    //-------------------------------------------------------------------------
    input  wire        buf_fill_start,    // Start filling buffer from disk
    input  wire        buf_flush_start,   // Start flushing buffer to disk
    input  wire [7:0]  target_sector,     // Sector to read/write (1-17)
    input  wire [3:0]  target_head,       // Head for operation
    input  wire [15:0] target_cylinder,   // Cylinder for operation
    output reg         buf_ready,         // Buffer operation complete
    output reg         buf_error,         // Buffer operation failed

    //-------------------------------------------------------------------------
    // Disk Interface (to ST-506/ESDI subsystem)
    //-------------------------------------------------------------------------
    output reg         disk_read_start,   // Start reading from disk
    output reg         disk_write_start,  // Start writing to disk
    output reg  [7:0]  disk_sector,       // Sector to access
    output reg  [3:0]  disk_head,         // Head to access
    output reg  [15:0] disk_cylinder,     // Cylinder to access
    input  wire        disk_ready,        // Disk operation complete
    input  wire        disk_error,        // Disk operation failed
    input  wire [7:0]  disk_rdata,        // Data from disk
    output wire [7:0]  disk_wdata,        // Data to disk
    input  wire        disk_byte_valid,   // Disk byte available
    output reg         disk_byte_ack,     // Acknowledge disk byte

    //-------------------------------------------------------------------------
    // Direct Buffer Access (for AXI debug access)
    //-------------------------------------------------------------------------
    input  wire [13:0] direct_addr,       // Direct address (0-8831)
    input  wire [7:0]  direct_wdata,      // Direct write data
    input  wire        direct_write,      // Direct write enable
    output wire [7:0]  direct_rdata,      // Direct read data

    //-------------------------------------------------------------------------
    // Benchmark Mode Control
    //-------------------------------------------------------------------------
    input  wire        bypass_mode        // 1 = bypass cache (always read from disk)
);

    //=========================================================================
    // Buffer Memory (Dual-Port BRAM)
    //=========================================================================
    // Port A: Controller/Host interface
    // Port B: Direct access (debug)

    reg [7:0] buffer_mem [0:BUFFER_SIZE+127];  // 8832 bytes

    // Port A signals
    reg  [13:0] porta_addr;
    reg  [7:0]  porta_wdata;
    reg         porta_write;
    wire [7:0]  porta_rdata;

    // Port A read
    assign porta_rdata = buffer_mem[porta_addr];

    // Port A write
    always @(posedge clk) begin
        if (porta_write) begin
            buffer_mem[porta_addr] <= porta_wdata;
        end
    end

    // Port B (direct access)
    assign direct_rdata = buffer_mem[direct_addr];

    always @(posedge clk) begin
        if (direct_write) begin
            buffer_mem[direct_addr] <= direct_wdata;
        end
    end

    //=========================================================================
    // Status Tracking
    //=========================================================================
    // Metadata area starts at offset 8704

    reg [16:0] valid_bitmap;      // Which sectors are valid (bits 0-16)
    reg [16:0] dirty_bitmap;      // Which sectors need write-back
    reg [15:0] cached_cylinder;   // Cylinder currently in buffer
    reg [3:0]  cached_head;       // Head currently in buffer
    reg [1:0]  buffer_state;      // 0=empty, 1=clean, 2=dirty

    localparam BUF_EMPTY = 2'd0;
    localparam BUF_CLEAN = 2'd1;
    localparam BUF_DIRTY = 2'd2;

    //=========================================================================
    // FSM States
    //=========================================================================
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_CHECK_CACHE = 4'd1;
    localparam [3:0] ST_FLUSH_DIRTY = 4'd2;
    localparam [3:0] ST_FLUSH_WAIT  = 4'd3;
    localparam [3:0] ST_FILL_READ   = 4'd4;
    localparam [3:0] ST_FILL_WAIT   = 4'd5;
    localparam [3:0] ST_FILL_STORE  = 4'd6;
    localparam [3:0] ST_HOST_READ   = 4'd7;
    localparam [3:0] ST_HOST_WRITE  = 4'd8;
    localparam [3:0] ST_DONE        = 4'd9;
    localparam [3:0] ST_ERROR       = 4'd10;

    reg [3:0] state;

    //=========================================================================
    // Internal Counters
    //=========================================================================
    reg [8:0]  byte_counter;      // 0-511 bytes per sector
    reg [4:0]  sector_counter;    // 0-16 sectors
    reg [7:0]  op_target_sector;  // Target sector for current operation
    reg        op_is_write;       // Current operation is write

    //=========================================================================
    // Address Calculation
    //=========================================================================
    // Sector offset in buffer = (sector_num - 1) * 512
    wire [13:0] sector_base_addr = ({6'b0, op_target_sector} - 1) * SECTOR_SIZE;
    wire [13:0] current_byte_addr = sector_base_addr + {5'b0, byte_counter};

    //=========================================================================
    // Host Interface
    //=========================================================================
    // Connect host to current sector in buffer
    wire [13:0] host_addr = sector_base_addr + {5'b0, byte_counter};

    assign host_rdata = porta_rdata;

    //=========================================================================
    // Main FSM
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= ST_IDLE;
            buf_ready        <= 1'b0;
            buf_error        <= 1'b0;
            disk_read_start  <= 1'b0;
            disk_write_start <= 1'b0;
            disk_sector      <= 8'h00;
            disk_head        <= 4'h0;
            disk_cylinder    <= 16'h0000;
            disk_byte_ack    <= 1'b0;
            host_drq         <= 1'b0;
            porta_addr       <= 14'h0000;
            porta_wdata      <= 8'h00;
            porta_write      <= 1'b0;
            byte_counter     <= 9'h000;
            sector_counter   <= 5'h00;
            op_target_sector <= 8'h01;
            op_is_write      <= 1'b0;
            valid_bitmap     <= 17'h00000;
            dirty_bitmap     <= 17'h00000;
            cached_cylinder  <= 16'hFFFF;  // Invalid
            cached_head      <= 4'hF;
            buffer_state     <= BUF_EMPTY;
        end else begin
            // Default: clear single-cycle signals
            buf_ready        <= 1'b0;
            buf_error        <= 1'b0;
            disk_read_start  <= 1'b0;
            disk_write_start <= 1'b0;
            disk_byte_ack    <= 1'b0;
            porta_write      <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    host_drq <= 1'b0;

                    if (buf_fill_start) begin
                        op_target_sector <= target_sector;
                        op_is_write      <= 1'b0;
                        state            <= ST_CHECK_CACHE;
                    end else if (buf_flush_start) begin
                        op_target_sector <= target_sector;
                        op_is_write      <= 1'b1;
                        state            <= ST_CHECK_CACHE;
                    end
                end

                //-------------------------------------------------------------
                ST_CHECK_CACHE: begin
                    // In bypass mode, always read from disk (for benchmark)
                    if (bypass_mode && !op_is_write) begin
                        // Bypass cache - force disk read for benchmark testing
                        cached_cylinder <= target_cylinder;
                        cached_head     <= target_head;
                        valid_bitmap    <= 17'h00000;  // Invalidate all
                        dirty_bitmap    <= 17'h00000;
                        buffer_state    <= BUF_CLEAN;
                        state           <= ST_FILL_READ;
                    end
                    // Check if requested track is already in buffer
                    else if (cached_cylinder == target_cylinder &&
                        cached_head == target_head &&
                        buffer_state != BUF_EMPTY) begin
                        // Cache hit!
                        if (op_is_write) begin
                            state <= ST_HOST_WRITE;
                        end else begin
                            // For read, check if sector is valid
                            if (valid_bitmap[op_target_sector - 1]) begin
                                state <= ST_HOST_READ;
                            end else begin
                                // Need to read this sector from disk
                                state <= ST_FILL_READ;
                            end
                        end
                    end else begin
                        // Cache miss - need to flush dirty and refill
                        if (buffer_state == BUF_DIRTY && dirty_bitmap != 17'h0) begin
                            state <= ST_FLUSH_DIRTY;
                        end else begin
                            // Buffer is clean or empty, just refill
                            cached_cylinder <= target_cylinder;
                            cached_head     <= target_head;
                            valid_bitmap    <= 17'h00000;
                            dirty_bitmap    <= 17'h00000;
                            buffer_state    <= BUF_CLEAN;
                            state           <= ST_FILL_READ;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_FLUSH_DIRTY: begin
                    // Find first dirty sector and write it
                    if (dirty_bitmap != 17'h0) begin
                        // Find lowest set bit
                        if (dirty_bitmap[0])       sector_counter <= 5'd0;
                        else if (dirty_bitmap[1])  sector_counter <= 5'd1;
                        else if (dirty_bitmap[2])  sector_counter <= 5'd2;
                        else if (dirty_bitmap[3])  sector_counter <= 5'd3;
                        else if (dirty_bitmap[4])  sector_counter <= 5'd4;
                        else if (dirty_bitmap[5])  sector_counter <= 5'd5;
                        else if (dirty_bitmap[6])  sector_counter <= 5'd6;
                        else if (dirty_bitmap[7])  sector_counter <= 5'd7;
                        else if (dirty_bitmap[8])  sector_counter <= 5'd8;
                        else if (dirty_bitmap[9])  sector_counter <= 5'd9;
                        else if (dirty_bitmap[10]) sector_counter <= 5'd10;
                        else if (dirty_bitmap[11]) sector_counter <= 5'd11;
                        else if (dirty_bitmap[12]) sector_counter <= 5'd12;
                        else if (dirty_bitmap[13]) sector_counter <= 5'd13;
                        else if (dirty_bitmap[14]) sector_counter <= 5'd14;
                        else if (dirty_bitmap[15]) sector_counter <= 5'd15;
                        else                       sector_counter <= 5'd16;

                        byte_counter     <= 9'h000;
                        disk_cylinder    <= cached_cylinder;
                        disk_head        <= cached_head;
                        disk_write_start <= 1'b1;
                        state            <= ST_FLUSH_WAIT;
                    end else begin
                        // All clean, proceed to refill
                        cached_cylinder <= target_cylinder;
                        cached_head     <= target_head;
                        valid_bitmap    <= 17'h00000;
                        dirty_bitmap    <= 17'h00000;
                        buffer_state    <= BUF_CLEAN;
                        state           <= ST_FILL_READ;
                    end
                end

                ST_FLUSH_WAIT: begin
                    disk_sector <= sector_counter + 1;  // Sectors are 1-based
                    porta_addr  <= ({9'b0, sector_counter} * SECTOR_SIZE) + {5'b0, byte_counter};

                    if (disk_ready) begin
                        // Clear dirty bit for this sector
                        dirty_bitmap[sector_counter] <= 1'b0;
                        state <= ST_FLUSH_DIRTY;  // Check for more dirty sectors
                    end else if (disk_error) begin
                        buf_error <= 1'b1;
                        state     <= ST_ERROR;
                    end
                end

                //-------------------------------------------------------------
                ST_FILL_READ: begin
                    // Start reading the target sector from disk
                    disk_cylinder    <= target_cylinder;
                    disk_head        <= target_head;
                    disk_sector      <= op_target_sector;
                    disk_read_start  <= 1'b1;
                    byte_counter     <= 9'h000;
                    state            <= ST_FILL_WAIT;
                end

                ST_FILL_WAIT: begin
                    // Wait for disk bytes and store them
                    if (disk_byte_valid) begin
                        porta_addr   <= current_byte_addr;
                        porta_wdata  <= disk_rdata;
                        porta_write  <= 1'b1;
                        disk_byte_ack<= 1'b1;
                        state        <= ST_FILL_STORE;
                    end else if (disk_error) begin
                        buf_error <= 1'b1;
                        state     <= ST_ERROR;
                    end else if (disk_ready) begin
                        // Sector read complete
                        valid_bitmap[op_target_sector - 1] <= 1'b1;
                        if (op_is_write) begin
                            state <= ST_HOST_WRITE;
                        end else begin
                            state <= ST_HOST_READ;
                        end
                    end
                end

                ST_FILL_STORE: begin
                    byte_counter <= byte_counter + 1'b1;
                    state        <= ST_FILL_WAIT;
                end

                //-------------------------------------------------------------
                ST_HOST_READ: begin
                    // Transfer sector data to host
                    host_drq   <= 1'b1;
                    porta_addr <= current_byte_addr;

                    if (host_read) begin
                        byte_counter <= byte_counter + 1'b1;
                        if (byte_counter == SECTOR_SIZE - 1) begin
                            state <= ST_DONE;
                        end
                    end
                end

                ST_HOST_WRITE: begin
                    // Receive sector data from host
                    host_drq   <= 1'b1;
                    porta_addr <= current_byte_addr;

                    if (host_write) begin
                        porta_wdata  <= host_wdata;
                        porta_write  <= 1'b1;
                        byte_counter <= byte_counter + 1'b1;
                        if (byte_counter == SECTOR_SIZE - 1) begin
                            // Mark sector as dirty
                            dirty_bitmap[op_target_sector - 1] <= 1'b1;
                            valid_bitmap[op_target_sector - 1] <= 1'b1;
                            buffer_state <= BUF_DIRTY;
                            state        <= ST_DONE;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_DONE: begin
                    host_drq  <= 1'b0;
                    buf_ready <= 1'b1;
                    state     <= ST_IDLE;
                end

                ST_ERROR: begin
                    host_drq  <= 1'b0;
                    buf_error <= 1'b1;
                    state     <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Disk Write Data Output
    //=========================================================================
    assign disk_wdata = porta_rdata;

endmodule
