//-----------------------------------------------------------------------------
// HDD Geometry Scanner - Automatic Geometry Detection
//
// Discovers drive geometry by probing:
//   - Number of heads (0-15)
//   - Number of cylinders (seek until error)
//   - Sectors per track (count sector marks)
//   - Interleave factor
//   - Track skew
//
// Works with decoded sector headers from MFM/RLL decoder
//
// Created: 2025-12-03 22:00
//-----------------------------------------------------------------------------

module hdd_geometry_scanner (
    input  wire        clk,              // 300 MHz HDD clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        scan_start,       // Start geometry scan
    input  wire        scan_abort,       // Abort scan
    output reg         scan_done,        // Scan complete
    output reg         scan_busy,        // Scan in progress
    output reg  [3:0]  scan_stage,       // Current scan stage

    //-------------------------------------------------------------------------
    // Seek Controller Interface
    //-------------------------------------------------------------------------
    output reg         seek_start,       // Request seek
    output reg  [15:0] seek_cylinder,    // Target cylinder
    input  wire        seek_done,        // Seek complete
    input  wire        seek_error,       // Seek failed
    input  wire [15:0] current_cylinder, // Current position

    //-------------------------------------------------------------------------
    // Head Select Interface
    //-------------------------------------------------------------------------
    output reg  [3:0]  head_select,      // Head to select
    input  wire        head_selected,    // Head selection complete

    //-------------------------------------------------------------------------
    // Data Path Interface (from decoder)
    //-------------------------------------------------------------------------
    input  wire        sector_header_valid,  // Valid sector header decoded
    input  wire [15:0] sector_cylinder,      // Cylinder from header
    input  wire [3:0]  sector_head,          // Head from header
    input  wire [7:0]  sector_number,        // Sector number from header
    input  wire        sector_crc_ok,        // Header CRC valid
    input  wire        index_pulse,          // Index pulse

    //-------------------------------------------------------------------------
    // Drive Status
    //-------------------------------------------------------------------------
    input  wire        drive_ready,
    input  wire        drive_fault,
    input  wire        track00,

    //-------------------------------------------------------------------------
    // Discovered Geometry (Output)
    //-------------------------------------------------------------------------
    output reg  [3:0]  num_heads,        // Number of heads (1-16)
    output reg  [15:0] num_cylinders,    // Number of cylinders
    output reg  [7:0]  sectors_per_track,// Sectors per track
    output reg  [7:0]  interleave,       // Interleave factor (1 = sequential)
    output reg  [7:0]  track_skew,       // Track-to-track skew
    output reg         geometry_valid    // Geometry successfully detected
);

    //-------------------------------------------------------------------------
    // Scan Stages
    //-------------------------------------------------------------------------
    localparam [3:0]
        STAGE_IDLE          = 4'd0,
        STAGE_INIT          = 4'd1,
        STAGE_HEAD_SCAN     = 4'd2,   // Count valid heads
        STAGE_SPT_SCAN      = 4'd3,   // Sectors per track
        STAGE_CYL_BINARY    = 4'd4,   // Binary search for max cylinder
        STAGE_CYL_VERIFY    = 4'd5,   // Verify max cylinder
        STAGE_INTERLEAVE    = 4'd6,   // Determine interleave
        STAGE_SKEW          = 4'd7,   // Measure track skew
        STAGE_COMPLETE      = 4'd8,
        STAGE_ERROR         = 4'd9;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [3:0]
        STATE_IDLE          = 4'd0,
        STATE_SEEK          = 4'd1,
        STATE_WAIT_SEEK     = 4'd2,
        STATE_SELECT_HEAD   = 4'd3,
        STATE_WAIT_HEAD     = 4'd4,
        STATE_READ_TRACK    = 4'd5,
        STATE_PROCESS       = 4'd6,
        STATE_NEXT          = 4'd7,
        STATE_DONE          = 4'd8;

    reg [3:0] state;

    //-------------------------------------------------------------------------
    // Scan Parameters
    //-------------------------------------------------------------------------
    localparam [23:0] ROTATION_TIMEOUT  = 24'd6_000_000;  // 20ms @ 300 MHz (> 1 rotation)
    localparam [15:0] MAX_CYLINDERS = 16'd4096;          // Max cylinders to try
    localparam [3:0]  MAX_HEADS = 4'd15;                 // Max heads to try

    //-------------------------------------------------------------------------
    // Timing and Counters
    //-------------------------------------------------------------------------
    reg [23:0] timeout_counter;
    reg [7:0]  rotation_count;
    reg        index_prev;

    //-------------------------------------------------------------------------
    // Head Scan Variables
    //-------------------------------------------------------------------------
    reg [3:0]  head_probe_idx;
    reg [15:0] head_valid_mask;       // Bit mask of valid heads
    reg [3:0]  last_valid_head;

    //-------------------------------------------------------------------------
    // SPT Scan Variables
    //-------------------------------------------------------------------------
    reg [7:0]  sector_count;
    reg [7:0]  max_sector_seen;
    reg [7:0]  min_sector_seen;
    reg [255:0] sector_seen_mask;     // Bit per sector

    //-------------------------------------------------------------------------
    // Cylinder Scan Variables (binary search)
    //-------------------------------------------------------------------------
    reg [15:0] cyl_low;               // Known good cylinder
    reg [15:0] cyl_high;              // Known bad or untested
    reg [15:0] cyl_mid;               // Current test cylinder
    reg [15:0] max_good_cylinder;

    //-------------------------------------------------------------------------
    // Interleave Detection
    //-------------------------------------------------------------------------
    reg [7:0]  sector_order [0:63];   // Order sectors appear
    reg [5:0]  order_idx;
    reg [7:0]  prev_sector;

    //-------------------------------------------------------------------------
    // Skew Detection
    //-------------------------------------------------------------------------
    reg [15:0] track0_first_sector_time;
    reg [15:0] track1_first_sector_time;
    reg [15:0] sector_time_counter;
    reg        first_sector_captured;

    //-------------------------------------------------------------------------
    // Index Edge Detection
    //-------------------------------------------------------------------------
    wire index_edge;
    assign index_edge = index_pulse && !index_prev;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            scan_stage <= STAGE_IDLE;
            scan_done <= 1'b0;
            scan_busy <= 1'b0;
            seek_start <= 1'b0;
            seek_cylinder <= 16'd0;
            head_select <= 4'd0;
            num_heads <= 4'd0;
            num_cylinders <= 16'd0;
            sectors_per_track <= 8'd0;
            interleave <= 8'd1;
            track_skew <= 8'd0;
            geometry_valid <= 1'b0;
            timeout_counter <= 24'd0;
            rotation_count <= 8'd0;
            index_prev <= 1'b0;
            head_probe_idx <= 4'd0;
            head_valid_mask <= 16'd0;
            last_valid_head <= 4'd0;
            sector_count <= 8'd0;
            max_sector_seen <= 8'd0;
            min_sector_seen <= 8'hFF;
            sector_seen_mask <= 256'd0;
            cyl_low <= 16'd0;
            cyl_high <= MAX_CYLINDERS;
            cyl_mid <= 16'd0;
            max_good_cylinder <= 16'd0;
            order_idx <= 6'd0;
            prev_sector <= 8'd0;
            track0_first_sector_time <= 16'd0;
            track1_first_sector_time <= 16'd0;
            sector_time_counter <= 16'd0;
            first_sector_captured <= 1'b0;
        end else begin
            // Default outputs
            scan_done <= 1'b0;
            seek_start <= 1'b0;
            index_prev <= index_pulse;

            // Timeout counter
            if (state != STATE_IDLE) begin
                timeout_counter <= timeout_counter + 1;
            end

            // Sector time counter
            if (scan_stage == STAGE_SKEW) begin
                sector_time_counter <= sector_time_counter + 1;
            end

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    scan_busy <= 1'b0;
                    if (scan_start && drive_ready && !drive_fault) begin
                        scan_busy <= 1'b1;
                        scan_stage <= STAGE_INIT;
                        geometry_valid <= 1'b0;
                        state <= STATE_SEEK;
                        // Start by seeking to cylinder 0
                        seek_cylinder <= 16'd0;
                        seek_start <= 1'b1;
                    end
                end

                //-------------------------------------------------------------
                STATE_SEEK: begin
                    seek_start <= 1'b0;
                    state <= STATE_WAIT_SEEK;
                    timeout_counter <= 24'd0;
                end

                //-------------------------------------------------------------
                STATE_WAIT_SEEK: begin
                    if (seek_done) begin
                        if (seek_error) begin
                            // Seek failed - handle based on stage
                            case (scan_stage)
                                STAGE_CYL_BINARY: begin
                                    // This cylinder is bad - search lower
                                    cyl_high <= cyl_mid;
                                    state <= STATE_NEXT;
                                end
                                default: begin
                                    scan_stage <= STAGE_ERROR;
                                    state <= STATE_DONE;
                                end
                            endcase
                        end else begin
                            // Seek succeeded
                            state <= STATE_SELECT_HEAD;
                        end
                    end else if (timeout_counter > 24'd100_000_000) begin
                        // 250ms timeout
                        scan_stage <= STAGE_ERROR;
                        state <= STATE_DONE;
                    end
                end

                //-------------------------------------------------------------
                STATE_SELECT_HEAD: begin
                    case (scan_stage)
                        STAGE_INIT: begin
                            head_select <= 4'd0;
                            scan_stage <= STAGE_HEAD_SCAN;
                            head_probe_idx <= 4'd0;
                            head_valid_mask <= 16'd0;
                        end
                        STAGE_HEAD_SCAN: begin
                            head_select <= head_probe_idx;
                        end
                        STAGE_SPT_SCAN: begin
                            head_select <= 4'd0;  // Use head 0
                        end
                        STAGE_SKEW: begin
                            head_select <= 4'd0;
                        end
                        default: begin
                            head_select <= 4'd0;
                        end
                    endcase
                    state <= STATE_WAIT_HEAD;
                    timeout_counter <= 24'd0;
                end

                //-------------------------------------------------------------
                STATE_WAIT_HEAD: begin
                    // Brief delay for head settling
                    if (timeout_counter > 24'd4000) begin  // 10us
                        state <= STATE_READ_TRACK;
                        timeout_counter <= 24'd0;
                        rotation_count <= 8'd0;
                        sector_count <= 8'd0;
                        first_sector_captured <= 1'b0;

                        if (scan_stage == STAGE_SPT_SCAN) begin
                            sector_seen_mask <= 256'd0;
                            max_sector_seen <= 8'd0;
                            min_sector_seen <= 8'hFF;
                        end
                        if (scan_stage == STAGE_INTERLEAVE) begin
                            order_idx <= 6'd0;
                        end
                        if (scan_stage == STAGE_SKEW) begin
                            sector_time_counter <= 16'd0;
                        end
                    end
                end

                //-------------------------------------------------------------
                STATE_READ_TRACK: begin
                    // Count rotations via index
                    if (index_edge) begin
                        rotation_count <= rotation_count + 1;

                        if (scan_stage == STAGE_SKEW && rotation_count == 8'd0) begin
                            sector_time_counter <= 16'd0;
                        end
                    end

                    // Process sector headers
                    if (sector_header_valid && sector_crc_ok) begin
                        case (scan_stage)
                            STAGE_HEAD_SCAN: begin
                                // Check if header cylinder/head matches expected
                                if (sector_cylinder == current_cylinder &&
                                    sector_head == head_probe_idx) begin
                                    // Valid head
                                    head_valid_mask[head_probe_idx] <= 1'b1;
                                    last_valid_head <= head_probe_idx;
                                end
                                sector_count <= sector_count + 1;
                            end

                            STAGE_SPT_SCAN: begin
                                sector_count <= sector_count + 1;
                                sector_seen_mask[sector_number] <= 1'b1;
                                if (sector_number > max_sector_seen)
                                    max_sector_seen <= sector_number;
                                if (sector_number < min_sector_seen)
                                    min_sector_seen <= sector_number;
                            end

                            STAGE_CYL_BINARY, STAGE_CYL_VERIFY: begin
                                // Any valid sector = cylinder exists
                                if (sector_cylinder == seek_cylinder) begin
                                    sector_count <= sector_count + 1;
                                end
                            end

                            STAGE_INTERLEAVE: begin
                                if (order_idx < 6'd63) begin
                                    sector_order[order_idx] <= sector_number;
                                    order_idx <= order_idx + 1;
                                end
                            end

                            STAGE_SKEW: begin
                                if (!first_sector_captured) begin
                                    if (current_cylinder == 16'd0) begin
                                        track0_first_sector_time <= sector_time_counter;
                                    end else begin
                                        track1_first_sector_time <= sector_time_counter;
                                    end
                                    first_sector_captured <= 1'b1;
                                end
                            end
                        endcase
                    end

                    // Complete after required rotations
                    if (rotation_count >= 8'd2 || timeout_counter > ROTATION_TIMEOUT) begin
                        state <= STATE_PROCESS;
                    end

                    // Abort check
                    if (scan_abort) begin
                        scan_stage <= STAGE_IDLE;
                        state <= STATE_DONE;
                    end
                end

                //-------------------------------------------------------------
                STATE_PROCESS: begin
                    case (scan_stage)
                        STAGE_HEAD_SCAN: begin
                            if (sector_count > 0) begin
                                // Found sectors - this head is valid
                                head_valid_mask[head_probe_idx] <= 1'b1;
                            end

                            if (head_probe_idx < MAX_HEADS) begin
                                head_probe_idx <= head_probe_idx + 1;
                                state <= STATE_SELECT_HEAD;
                            end else begin
                                // Count valid heads
                                num_heads <= count_heads(head_valid_mask);
                                scan_stage <= STAGE_SPT_SCAN;
                                state <= STATE_SELECT_HEAD;
                            end
                        end

                        STAGE_SPT_SCAN: begin
                            // Sectors per track = max sector number (assuming 0-based or 1-based)
                            if (min_sector_seen == 8'd0) begin
                                sectors_per_track <= max_sector_seen + 1;  // 0-based
                            end else begin
                                sectors_per_track <= max_sector_seen;      // 1-based
                            end

                            // Start cylinder search
                            cyl_low <= 16'd0;
                            cyl_high <= MAX_CYLINDERS;
                            scan_stage <= STAGE_CYL_BINARY;
                            state <= STATE_NEXT;
                        end

                        STAGE_CYL_BINARY: begin
                            if (sector_count > 0) begin
                                // Cylinder valid - search higher
                                max_good_cylinder <= seek_cylinder;
                                cyl_low <= seek_cylinder;
                            end else begin
                                // Cylinder invalid - search lower
                                cyl_high <= seek_cylinder;
                            end
                            state <= STATE_NEXT;
                        end

                        STAGE_CYL_VERIFY: begin
                            num_cylinders <= max_good_cylinder + 1;
                            scan_stage <= STAGE_INTERLEAVE;
                            // Go back to cylinder 0 for interleave test
                            seek_cylinder <= 16'd0;
                            seek_start <= 1'b1;
                            state <= STATE_SEEK;
                        end

                        STAGE_INTERLEAVE: begin
                            // Calculate interleave from sector order
                            if (order_idx >= 6'd2) begin
                                // Interleave = difference between first two sectors
                                if (sector_order[1] > sector_order[0]) begin
                                    interleave <= sector_order[1] - sector_order[0];
                                end else begin
                                    interleave <= sector_order[0] - sector_order[1];
                                end
                            end else begin
                                interleave <= 8'd1;  // Default sequential
                            end

                            // Measure skew - seek to cylinder 1
                            seek_cylinder <= 16'd1;
                            seek_start <= 1'b1;
                            scan_stage <= STAGE_SKEW;
                            state <= STATE_SEEK;
                        end

                        STAGE_SKEW: begin
                            // Calculate skew from timing difference
                            if (track1_first_sector_time > track0_first_sector_time) begin
                                track_skew <= (track1_first_sector_time - track0_first_sector_time) >> 8;
                            end else begin
                                track_skew <= (track0_first_sector_time - track1_first_sector_time) >> 8;
                            end

                            geometry_valid <= 1'b1;
                            scan_stage <= STAGE_COMPLETE;
                            state <= STATE_DONE;
                        end

                        default: state <= STATE_DONE;
                    endcase
                end

                //-------------------------------------------------------------
                STATE_NEXT: begin
                    case (scan_stage)
                        STAGE_CYL_BINARY: begin
                            // Binary search: pick midpoint
                            if (cyl_high - cyl_low <= 16'd1) begin
                                // Converged - verify
                                scan_stage <= STAGE_CYL_VERIFY;
                                seek_cylinder <= max_good_cylinder;
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end else begin
                                cyl_mid <= (cyl_low + cyl_high) >> 1;
                                seek_cylinder <= (cyl_low + cyl_high) >> 1;
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end
                        end

                        default: begin
                            state <= STATE_IDLE;
                        end
                    endcase
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    scan_done <= 1'b1;
                    scan_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Count Valid Heads Function
    //-------------------------------------------------------------------------
    function [3:0] count_heads;
        input [15:0] mask;
        integer i;
        reg [3:0] count;
        begin
            count = 4'd0;
            for (i = 0; i < 16; i = i + 1) begin
                if (mask[i]) count = count + 1;
            end
            count_heads = count;
        end
    endfunction

endmodule

//-----------------------------------------------------------------------------
// Geometry Profile Encoder
// Packs discovered geometry into a profile register
//-----------------------------------------------------------------------------
module hdd_geometry_profile (
    input  wire [3:0]  num_heads,
    input  wire [15:0] num_cylinders,
    input  wire [7:0]  sectors_per_track,
    input  wire [2:0]  detected_rate,
    input  wire        is_differential,
    input  wire [7:0]  interleave,

    // Packed profile (64 bits)
    output wire [63:0] profile
);

    // Profile format:
    // [63:60] = Reserved
    // [59:56] = Encoding (0=MFM, 1=RLL, 2=ESDI)
    // [55:52] = Heads (0-15)
    // [51:36] = Cylinders (0-65535)
    // [35:28] = Sectors per track (0-255)
    // [27:20] = Interleave
    // [19:17] = Data rate code
    // [16]    = Differential PHY
    // [15:0]  = Capacity in MB (calculated)

    wire [15:0] capacity_mb;
    wire [31:0] capacity_sectors;
    wire [3:0]  encoding;

    // Calculate capacity: heads * cylinders * spt * 512 / (1024*1024)
    assign capacity_sectors = {12'd0, num_heads} * {16'd0, num_cylinders} * {24'd0, sectors_per_track};
    assign capacity_mb = capacity_sectors >> 11;  // Divide by 2048 (512/1M)

    // Determine encoding from rate
    assign encoding = (detected_rate == 3'd2) ? 4'd1 :  // 7.5M = RLL
                      (detected_rate >= 3'd3) ? 4'd2 :  // 10M+ = ESDI
                      4'd0;                              // else MFM

    assign profile = {
        4'd0,               // [63:60] Reserved
        encoding,           // [59:56] Encoding
        num_heads,          // [55:52] Heads
        num_cylinders,      // [51:36] Cylinders
        sectors_per_track,  // [35:28] SPT
        interleave,         // [27:20] Interleave
        detected_rate,      // [19:17] Rate
        is_differential,    // [16] Differential
        capacity_mb         // [15:0] Capacity MB
    };

endmodule
