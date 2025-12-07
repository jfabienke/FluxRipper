//-----------------------------------------------------------------------------
// Multi-Pass Flux Capture Controller for FluxStat Recovery
//
// Automates the capture of multiple flux passes for statistical analysis.
// Coordinates with existing flux capture infrastructure to:
//   - Capture N passes of the same track
//   - Store each pass in separate memory regions
//   - Track per-pass metadata (flux count, index timing, duration)
//   - Trigger histogram updates during capture
//
// Created: 2025-12-04 18:15
//-----------------------------------------------------------------------------

module multipass_capture #(
    parameter MAX_PASSES    = 64,           // Maximum passes supported
    parameter PASS_BITS     = 6,            // log2(MAX_PASSES)
    parameter ADDR_WIDTH    = 24,           // Memory address width
    parameter PASS_SIZE     = 24'h010000,   // Memory per pass (64KB default)
    parameter TIMESTAMP_BITS = 28           // Flux timestamp width
)(
    input  wire                    clk,
    input  wire                    reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire                    start,           // Start multi-pass capture
    input  wire                    abort,           // Abort current capture
    input  wire [PASS_BITS-1:0]    pass_count,      // Number of passes to capture (1-64)
    input  wire [ADDR_WIDTH-1:0]   base_addr,       // Base address in memory
    output reg                     busy,            // Capture in progress
    output reg                     done,            // All passes complete
    output reg                     error,           // Error occurred
    output reg  [PASS_BITS-1:0]    current_pass,    // Current pass number (0-based)

    //-------------------------------------------------------------------------
    // Flux Capture Interface (directly controls flux_capture.v)
    //-------------------------------------------------------------------------
    output reg                     capture_start,   // Start single capture
    output reg                     capture_stop,    // Stop capture
    input  wire                    capture_busy,    // Capture in progress
    input  wire                    capture_done,    // Capture complete
    input  wire                    capture_overflow,// FIFO overflow during capture

    //-------------------------------------------------------------------------
    // Memory Interface (address routing)
    //-------------------------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]   mem_base_addr,   // Base address for current pass
    output wire [ADDR_WIDTH-1:0]   mem_end_addr,    // End address for current pass

    //-------------------------------------------------------------------------
    // Index Pulse Interface
    //-------------------------------------------------------------------------
    input  wire                    index_pulse,     // Index pulse from drive
    output reg                     wait_for_index,  // Waiting for index alignment

    //-------------------------------------------------------------------------
    // Flux Stream Interface (for counting and histogram)
    //-------------------------------------------------------------------------
    input  wire                    flux_valid,      // Flux transition received
    input  wire [TIMESTAMP_BITS-1:0] flux_timestamp,// Timestamp of transition

    //-------------------------------------------------------------------------
    // Histogram Interface
    //-------------------------------------------------------------------------
    output reg                     hist_enable,     // Enable histogram collection
    output reg                     hist_clear,      // Clear histogram (between passes)
    output reg                     hist_snapshot,   // Snapshot current histogram

    //-------------------------------------------------------------------------
    // Per-Pass Metadata (directly readable)
    //-------------------------------------------------------------------------
    output reg  [31:0]             pass_flux_count  [0:MAX_PASSES-1], // Flux count per pass
    output reg  [31:0]             pass_index_time  [0:MAX_PASSES-1], // Index-to-index time
    output reg  [31:0]             pass_start_time  [0:MAX_PASSES-1], // Capture start timestamp
    output reg  [ADDR_WIDTH-1:0]   pass_data_size   [0:MAX_PASSES-1], // Bytes written per pass

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    output reg  [31:0]             total_flux_count,    // Sum across all passes
    output reg  [31:0]             min_flux_count,      // Minimum flux count (any pass)
    output reg  [31:0]             max_flux_count,      // Maximum flux count (any pass)
    output reg  [31:0]             total_capture_time,  // Total time for all passes
    output reg  [PASS_BITS-1:0]    passes_completed     // Number of passes finished
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE          = 4'd0,
        ST_INIT          = 4'd1,
        ST_WAIT_INDEX    = 4'd2,
        ST_CAPTURE_START = 4'd3,
        ST_CAPTURING     = 4'd4,
        ST_CAPTURE_DONE  = 4'd5,
        ST_NEXT_PASS     = 4'd6,
        ST_COMPLETE      = 4'd7,
        ST_ERROR         = 4'd8;

    reg [3:0] state;
    reg [3:0] next_state;

    //-------------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------------
    reg [PASS_BITS-1:0] target_passes;       // Number of passes to capture
    reg [31:0]          flux_counter;         // Flux count for current pass
    reg [31:0]          index_counter;        // Time since last index
    reg [31:0]          capture_start_time;   // Timestamp when capture started
    reg                 first_index_seen;     // Have we seen first index?
    reg                 second_index_seen;    // Have we seen second index (track complete)?
    reg [31:0]          global_timer;         // Global time counter

    // Edge detection for index
    reg index_pulse_d;
    wire index_edge = index_pulse & ~index_pulse_d;

    always @(posedge clk) begin
        index_pulse_d <= index_pulse;
    end

    //-------------------------------------------------------------------------
    // Memory Address Calculation
    //-------------------------------------------------------------------------
    assign mem_end_addr = mem_base_addr + PASS_SIZE - 1;

    //-------------------------------------------------------------------------
    // Global Timer
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            global_timer <= 32'd0;
        end else begin
            global_timer <= global_timer + 1;
        end
    end

    //-------------------------------------------------------------------------
    // State Machine - Sequential
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    //-------------------------------------------------------------------------
    // State Machine - Combinational
    //-------------------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start && pass_count > 0) begin
                    next_state = ST_INIT;
                end
            end

            ST_INIT: begin
                next_state = ST_WAIT_INDEX;
            end

            ST_WAIT_INDEX: begin
                if (abort) begin
                    next_state = ST_ERROR;
                end else if (index_edge) begin
                    next_state = ST_CAPTURE_START;
                end
            end

            ST_CAPTURE_START: begin
                next_state = ST_CAPTURING;
            end

            ST_CAPTURING: begin
                if (abort) begin
                    next_state = ST_ERROR;
                end else if (capture_overflow) begin
                    next_state = ST_ERROR;
                end else if (second_index_seen) begin
                    next_state = ST_CAPTURE_DONE;
                end
            end

            ST_CAPTURE_DONE: begin
                next_state = ST_NEXT_PASS;
            end

            ST_NEXT_PASS: begin
                if (current_pass >= target_passes - 1) begin
                    next_state = ST_COMPLETE;
                end else begin
                    next_state = ST_WAIT_INDEX;
                end
            end

            ST_COMPLETE: begin
                next_state = ST_IDLE;
            end

            ST_ERROR: begin
                next_state = ST_IDLE;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    //-------------------------------------------------------------------------
    // State Machine - Output Logic
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            busy             <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;
            current_pass     <= {PASS_BITS{1'b0}};
            target_passes    <= {PASS_BITS{1'b0}};
            capture_start    <= 1'b0;
            capture_stop     <= 1'b0;
            mem_base_addr    <= {ADDR_WIDTH{1'b0}};
            wait_for_index   <= 1'b0;
            hist_enable      <= 1'b0;
            hist_clear       <= 1'b0;
            hist_snapshot    <= 1'b0;
            flux_counter     <= 32'd0;
            index_counter    <= 32'd0;
            first_index_seen <= 1'b0;
            second_index_seen<= 1'b0;
            capture_start_time <= 32'd0;
            total_flux_count <= 32'd0;
            min_flux_count   <= 32'hFFFFFFFF;
            max_flux_count   <= 32'd0;
            total_capture_time <= 32'd0;
            passes_completed <= {PASS_BITS{1'b0}};

            for (i = 0; i < MAX_PASSES; i = i + 1) begin
                pass_flux_count[i] <= 32'd0;
                pass_index_time[i] <= 32'd0;
                pass_start_time[i] <= 32'd0;
                pass_data_size[i]  <= {ADDR_WIDTH{1'b0}};
            end

        end else begin
            // Default pulse signals
            capture_start  <= 1'b0;
            capture_stop   <= 1'b0;
            hist_clear     <= 1'b0;
            hist_snapshot  <= 1'b0;
            done           <= 1'b0;

            // Count flux transitions during capture
            if (state == ST_CAPTURING && flux_valid) begin
                flux_counter <= flux_counter + 1;
            end

            // Count time since index
            if (state == ST_CAPTURING || state == ST_WAIT_INDEX) begin
                index_counter <= index_counter + 1;
            end

            // Detect second index (end of track)
            if (state == ST_CAPTURING && index_edge && first_index_seen) begin
                second_index_seen <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;
                end

                ST_INIT: begin
                    busy             <= 1'b1;
                    done             <= 1'b0;
                    error            <= 1'b0;
                    current_pass     <= {PASS_BITS{1'b0}};
                    target_passes    <= pass_count;
                    mem_base_addr    <= base_addr;
                    total_flux_count <= 32'd0;
                    min_flux_count   <= 32'hFFFFFFFF;
                    max_flux_count   <= 32'd0;
                    total_capture_time <= 32'd0;
                    passes_completed <= {PASS_BITS{1'b0}};

                    // Clear all pass metadata
                    for (i = 0; i < MAX_PASSES; i = i + 1) begin
                        pass_flux_count[i] <= 32'd0;
                        pass_index_time[i] <= 32'd0;
                        pass_start_time[i] <= 32'd0;
                        pass_data_size[i]  <= {ADDR_WIDTH{1'b0}};
                    end
                end

                ST_WAIT_INDEX: begin
                    wait_for_index   <= 1'b1;
                    first_index_seen <= 1'b0;
                    second_index_seen<= 1'b0;
                    flux_counter     <= 32'd0;
                    index_counter    <= 32'd0;

                    // Clear histogram for new pass (optional - keep for comparison)
                    // hist_clear <= 1'b1;
                end

                ST_CAPTURE_START: begin
                    wait_for_index     <= 1'b0;
                    capture_start      <= 1'b1;
                    hist_enable        <= 1'b1;
                    first_index_seen   <= 1'b1;
                    capture_start_time <= global_timer;
                    index_counter      <= 32'd0;

                    // Record pass start time
                    pass_start_time[current_pass] <= global_timer;
                end

                ST_CAPTURING: begin
                    // Continue capture until second index
                end

                ST_CAPTURE_DONE: begin
                    capture_stop <= 1'b1;
                    hist_enable  <= 1'b0;
                    hist_snapshot <= 1'b1;

                    // Record pass metadata
                    pass_flux_count[current_pass] <= flux_counter;
                    pass_index_time[current_pass] <= index_counter;
                    // pass_data_size populated by external memory controller

                    // Update statistics
                    total_flux_count <= total_flux_count + flux_counter;
                    total_capture_time <= total_capture_time + index_counter;

                    if (flux_counter < min_flux_count) begin
                        min_flux_count <= flux_counter;
                    end
                    if (flux_counter > max_flux_count) begin
                        max_flux_count <= flux_counter;
                    end

                    passes_completed <= current_pass + 1;
                end

                ST_NEXT_PASS: begin
                    current_pass  <= current_pass + 1;
                    mem_base_addr <= mem_base_addr + PASS_SIZE;
                end

                ST_COMPLETE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end

                ST_ERROR: begin
                    busy         <= 1'b0;
                    error        <= 1'b1;
                    capture_stop <= 1'b1;
                    hist_enable  <= 1'b0;
                end
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Debug/Status
    //-------------------------------------------------------------------------
    `ifdef SIMULATION
    reg [8*20-1:0] state_name;
    always @(*) begin
        case (state)
            ST_IDLE:          state_name = "IDLE";
            ST_INIT:          state_name = "INIT";
            ST_WAIT_INDEX:    state_name = "WAIT_INDEX";
            ST_CAPTURE_START: state_name = "CAPTURE_START";
            ST_CAPTURING:     state_name = "CAPTURING";
            ST_CAPTURE_DONE:  state_name = "CAPTURE_DONE";
            ST_NEXT_PASS:     state_name = "NEXT_PASS";
            ST_COMPLETE:      state_name = "COMPLETE";
            ST_ERROR:         state_name = "ERROR";
            default:          state_name = "UNKNOWN";
        endcase
    end
    `endif

endmodule

//-----------------------------------------------------------------------------
// Multi-Pass Capture Register Interface
//
// AXI-Lite accessible registers for control and status
//-----------------------------------------------------------------------------
module multipass_capture_regs #(
    parameter MAX_PASSES = 64,
    parameter PASS_BITS  = 6,
    parameter ADDR_WIDTH = 24
)(
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Register Interface (directly from AXI-Lite decoder)
    //-------------------------------------------------------------------------
    input  wire [7:0]  reg_addr,
    input  wire        reg_write,
    input  wire        reg_read,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,
    output wire        reg_ready,

    //-------------------------------------------------------------------------
    // Multipass Capture Interface
    //-------------------------------------------------------------------------
    output reg         mp_start,
    output reg         mp_abort,
    output reg  [PASS_BITS-1:0] mp_pass_count,
    output reg  [ADDR_WIDTH-1:0] mp_base_addr,
    input  wire        mp_busy,
    input  wire        mp_done,
    input  wire        mp_error,
    input  wire [PASS_BITS-1:0] mp_current_pass,
    input  wire [PASS_BITS-1:0] mp_passes_completed,
    input  wire [31:0] mp_total_flux,
    input  wire [31:0] mp_min_flux,
    input  wire [31:0] mp_max_flux,
    input  wire [31:0] mp_total_time,

    // Per-pass metadata access
    input  wire [31:0] pass_flux_count [0:MAX_PASSES-1],
    input  wire [31:0] pass_index_time [0:MAX_PASSES-1]
);

    assign reg_ready = 1'b1;  // Single-cycle access

    // Register map:
    // 0x00: Control (W: [0]=start, [1]=abort, [7:2]=pass_count)
    // 0x04: Status (R: [0]=busy, [1]=done, [2]=error, [13:8]=current_pass, [21:16]=completed)
    // 0x08: Base Address (RW)
    // 0x0C: Total Flux Count (R)
    // 0x10: Min Flux Count (R)
    // 0x14: Max Flux Count (R)
    // 0x18: Total Capture Time (R)
    // 0x20-0x9F: Pass Flux Count [0-31] (R)
    // 0xA0-0x11F: Pass Index Time [0-31] (R)

    // Read multiplexer for pass arrays
    wire [4:0] pass_index = reg_addr[6:2];  // For 0x20+ addresses

    always @(posedge clk) begin
        if (reset) begin
            mp_start      <= 1'b0;
            mp_abort      <= 1'b0;
            mp_pass_count <= 6'd8;  // Default 8 passes
            mp_base_addr  <= {ADDR_WIDTH{1'b0}};
            reg_rdata     <= 32'd0;
        end else begin
            // Auto-clear pulses
            mp_start <= 1'b0;
            mp_abort <= 1'b0;

            if (reg_write) begin
                case (reg_addr)
                    8'h00: begin
                        mp_start      <= reg_wdata[0];
                        mp_abort      <= reg_wdata[1];
                        mp_pass_count <= reg_wdata[7:2];
                    end
                    8'h08: mp_base_addr <= reg_wdata[ADDR_WIDTH-1:0];
                endcase
            end

            if (reg_read) begin
                case (reg_addr)
                    8'h00: reg_rdata <= {24'd0, mp_pass_count, 2'b00};
                    8'h04: reg_rdata <= {10'd0, mp_passes_completed, mp_current_pass, 5'd0,
                                         mp_error, mp_done, mp_busy};
                    8'h08: reg_rdata <= {{(32-ADDR_WIDTH){1'b0}}, mp_base_addr};
                    8'h0C: reg_rdata <= mp_total_flux;
                    8'h10: reg_rdata <= mp_min_flux;
                    8'h14: reg_rdata <= mp_max_flux;
                    8'h18: reg_rdata <= mp_total_time;
                    default: begin
                        if (reg_addr >= 8'h20 && reg_addr < 8'hA0) begin
                            // Pass flux count array
                            reg_rdata <= pass_flux_count[pass_index];
                        end else if (reg_addr >= 8'hA0) begin
                            // Pass index time array
                            reg_rdata <= pass_index_time[pass_index];
                        end else begin
                            reg_rdata <= 32'd0;
                        end
                    end
                endcase
            end
        end
    end

endmodule
