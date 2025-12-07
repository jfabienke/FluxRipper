//-----------------------------------------------------------------------------
// ST-506 Drive Interface for FluxRipper
// Implements 34-pin control + 20-pin data interface for MFM/RLL/ESDI drives
//
// Supports:
//   - 34-pin control cable (active-low signals)
//   - 20-pin data cable (single-ended or differential)
//   - 4-bit head selection (up to 16 heads)
//   - SEEK_COMPLETE based seek control
//   - Write fault detection
//
// Created: 2025-12-03 15:30
//-----------------------------------------------------------------------------

module st506_interface (
    input  wire        clk,              // System clock
    input  wire        reset_n,

    //-------------------------------------------------------------------------
    // FDC Core Interface (active-high, directly from command FSM)
    //-------------------------------------------------------------------------
    input  wire [3:0]  head_select,      // 4-bit head selection (0-15)
    input  wire        step_pulse,       // Step request (single cycle)
    input  wire        step_direction,   // 1 = in (toward center), 0 = out
    input  wire        write_gate,       // Write enable
    input  wire        write_data,       // Write data stream
    input  wire [1:0]  drive_select,     // Drive selection (0-3)

    //-------------------------------------------------------------------------
    // ST-506 34-Pin Control Cable Interface (active-low, directly to drive)
    //-------------------------------------------------------------------------
    // Output signals
    output wire [3:0]  st506_head_sel_n, // Pins 2,4,14,18: HEAD SELECT 8,4,1,2
    output wire        st506_step_n,     // Pin 24: STEP
    output wire        st506_dir_n,      // Pin 34: DIRECTION
    output wire        st506_write_gate_n,// Pin 6: WRITE GATE
    output wire [3:0]  st506_drv_sel_n,  // Pins 26,28,30,32: DRIVE SELECT 1-4

    // Input signals
    input  wire        st506_seek_complete_n, // Pin 8: SEEK COMPLETE
    input  wire        st506_track00_n,       // Pin 10: TRACK 00
    input  wire        st506_write_fault_n,   // Pin 12: WRITE FAULT
    input  wire        st506_index_n,         // Pin 20: INDEX
    input  wire        st506_ready_n,         // Pin 22: READY

    //-------------------------------------------------------------------------
    // ST-506 20-Pin Data Cable Interface
    //-------------------------------------------------------------------------
    // Single-ended mode (MFM/RLL)
    output wire        st506_write_data,      // Pin 13: +WRITE DATA
    input  wire        st506_read_data,       // Pin 17: +READ DATA

    // Differential mode (ESDI) - directly from +/- pins
    output wire        st506_write_data_p,    // Pin 13: +WRITE DATA
    output wire        st506_write_data_n,    // Pin 14: -WRITE DATA
    input  wire        st506_read_data_p,     // Pin 17: +READ DATA
    input  wire        st506_read_data_n,     // Pin 18: -READ DATA

    // PHY mode selection
    input  wire        differential_mode,     // 0 = single-ended, 1 = differential

    //-------------------------------------------------------------------------
    // Status Outputs (active-high for FDC core)
    //-------------------------------------------------------------------------
    output wire        seek_complete,         // Seek operation done
    output wire        at_track00,            // Head at track 0
    output wire        drive_ready,           // Drive ready
    output wire        drive_fault,           // Write fault or error
    output wire        index_pulse,           // Index pulse (once per revolution)
    output wire        read_data              // Recovered read data
);

    //-------------------------------------------------------------------------
    // Input Synchronization (metastability protection)
    //-------------------------------------------------------------------------
    reg [1:0] seek_complete_sync;
    reg [1:0] track00_sync;
    reg [1:0] write_fault_sync;
    reg [1:0] index_sync;
    reg [1:0] ready_sync;
    reg [1:0] read_data_se_sync;
    reg [1:0] read_data_diff_sync;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            seek_complete_sync <= 2'b11;  // Active-low, default inactive
            track00_sync <= 2'b11;
            write_fault_sync <= 2'b11;
            index_sync <= 2'b11;
            ready_sync <= 2'b11;
            read_data_se_sync <= 2'b00;
            read_data_diff_sync <= 2'b00;
        end else begin
            seek_complete_sync <= {seek_complete_sync[0], st506_seek_complete_n};
            track00_sync <= {track00_sync[0], st506_track00_n};
            write_fault_sync <= {write_fault_sync[0], st506_write_fault_n};
            index_sync <= {index_sync[0], st506_index_n};
            ready_sync <= {ready_sync[0], st506_ready_n};
            read_data_se_sync <= {read_data_se_sync[0], st506_read_data};
            // Differential: recover data from P-N
            read_data_diff_sync <= {read_data_diff_sync[0],
                                    st506_read_data_p & ~st506_read_data_n};
        end
    end

    //-------------------------------------------------------------------------
    // Output Signal Generation (active-low conversion)
    //-------------------------------------------------------------------------

    // Head selection - directly map 4-bit value to active-low outputs
    // ST-506 uses scattered pin arrangement: 8,4,1,2 on pins 2,4,14,18
    assign st506_head_sel_n = ~head_select;

    // Step pulse - already a single-cycle pulse, just invert
    assign st506_step_n = ~step_pulse;

    // Direction - 1=in (toward spindle), 0=out (toward edge)
    assign st506_dir_n = ~step_direction;

    // Write gate
    assign st506_write_gate_n = ~write_gate;

    // Drive select - decode 2-bit to 4 active-low lines
    reg [3:0] drv_sel_decoded;
    always @(*) begin
        case (drive_select)
            2'b00: drv_sel_decoded = 4'b1110;
            2'b01: drv_sel_decoded = 4'b1101;
            2'b10: drv_sel_decoded = 4'b1011;
            2'b11: drv_sel_decoded = 4'b0111;
        endcase
    end
    assign st506_drv_sel_n = drv_sel_decoded;

    //-------------------------------------------------------------------------
    // Write Data Output
    //-------------------------------------------------------------------------
    // Single-ended: direct output
    assign st506_write_data = write_data;

    // Differential: generate complementary pair
    assign st506_write_data_p = differential_mode ? write_data : write_data;
    assign st506_write_data_n = differential_mode ? ~write_data : 1'b0;

    //-------------------------------------------------------------------------
    // Status Signal Conversion (active-low to active-high)
    //-------------------------------------------------------------------------
    assign seek_complete = ~seek_complete_sync[1];
    assign at_track00 = ~track00_sync[1];
    assign drive_fault = ~write_fault_sync[1];  // Fault when asserted (low)
    assign index_pulse = ~index_sync[1];
    assign drive_ready = ~ready_sync[1];

    // Read data: select based on PHY mode
    assign read_data = differential_mode ? read_data_diff_sync[1]
                                          : read_data_se_sync[1];

endmodule

//-----------------------------------------------------------------------------
// ST-506 4-bit Head Selector with Latching
// Holds head selection stable during seek operations
//-----------------------------------------------------------------------------
module st506_head_selector (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  head_in,          // Requested head
    input  wire        head_load,        // Load new head selection
    input  wire        seek_active,      // Seek in progress (freeze head)
    output reg  [3:0]  head_out          // Latched head selection
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head_out <= 4'd0;
        end else if (head_load && !seek_active) begin
            head_out <= head_in;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// ST-506 Step Pulse Generator
// Generates properly timed step pulses for HDD seek operations
//-----------------------------------------------------------------------------
module st506_step_generator (
    input  wire        clk,              // System clock
    input  wire        reset_n,
    input  wire        step_request,     // Request a step
    input  wire        step_direction,   // 1 = in, 0 = out
    input  wire [15:0] step_pulse_width, // Pulse width in clock cycles
    input  wire [15:0] step_period,      // Minimum time between steps

    output reg         step_pulse,       // Step pulse output
    output reg         step_dir,         // Direction output (latched)
    output reg         step_busy,        // Step in progress
    output reg         step_done         // Step complete (single cycle)
);

    //-------------------------------------------------------------------------
    // Step Timing Parameters (typical ST-506)
    //-------------------------------------------------------------------------
    // Step pulse width: 8-10 µs (2400-3000 cycles @ 300 MHz)
    // Step period: 3-15 ms (settling time varies by drive)
    //
    // For seek optimization, many drives support "buffered step":
    // - Can accept next step before SEEK_COMPLETE
    // - Controller tracks actual position

    localparam [2:0]
        STATE_IDLE    = 3'd0,
        STATE_SETUP   = 3'd1,   // Direction setup time
        STATE_PULSE   = 3'd2,   // Step pulse active
        STATE_HOLD    = 3'd3,   // Post-pulse hold
        STATE_WAIT    = 3'd4;   // Inter-step delay

    reg [2:0] state;
    reg [15:0] counter;

    // Setup and hold times (in clock cycles @ 300 MHz)
    localparam [15:0] DIR_SETUP_TIME      = 16.d300;   // 1 µs
    localparam [15:0] STEP_HOLD_TIME      = 16.d300;   // 1 µs

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            counter <= 16'd0;
            step_pulse <= 1'b0;
            step_dir <= 1'b0;
            step_busy <= 1'b0;
            step_done <= 1'b0;
        end else begin
            step_done <= 1'b0;  // Default: clear done pulse

            case (state)
                STATE_IDLE: begin
                    step_pulse <= 1'b0;
                    step_busy <= 1'b0;
                    if (step_request) begin
                        step_dir <= step_direction;
                        step_busy <= 1'b1;
                        counter <= DIR_SETUP_TIME;
                        state <= STATE_SETUP;
                    end
                end

                STATE_SETUP: begin
                    // Wait for direction setup time
                    if (counter == 0) begin
                        step_pulse <= 1'b1;
                        counter <= step_pulse_width;
                        state <= STATE_PULSE;
                    end else begin
                        counter <= counter - 1;
                    end
                end

                STATE_PULSE: begin
                    // Hold step pulse active
                    if (counter == 0) begin
                        step_pulse <= 1'b0;
                        counter <= STEP_HOLD_TIME;
                        state <= STATE_HOLD;
                    end else begin
                        counter <= counter - 1;
                    end
                end

                STATE_HOLD: begin
                    // Post-pulse hold time
                    if (counter == 0) begin
                        counter <= step_period;
                        state <= STATE_WAIT;
                    end else begin
                        counter <= counter - 1;
                    end
                end

                STATE_WAIT: begin
                    // Inter-step delay (minimum step period)
                    if (counter == 0) begin
                        step_done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        counter <= counter - 1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// ST-506 Signal Definitions
//-----------------------------------------------------------------------------
// 34-Pin Control Cable (active-low unless noted)
//
// Pin  Signal           Dir    Description
// ---  ------           ---    -----------
// 2    /HEAD SELECT 8   Out    Head select bit 3
// 4    /HEAD SELECT 4   Out    Head select bit 2
// 6    /WRITE GATE      Out    Enable write current
// 8    /SEEK COMPLETE   In     Seek operation finished
// 10   /TRACK 00        In     Head at outermost track
// 12   /WRITE FAULT     In     Write error detected
// 14   /HEAD SELECT 1   Out    Head select bit 0
// 16   (Reserved)       -      -
// 18   /HEAD SELECT 2   Out    Head select bit 1
// 20   /INDEX           In     Once per revolution
// 22   /READY           In     Drive spun up and ready
// 24   /STEP            Out    Step pulse
// 26   /DRIVE SELECT 1  Out    Select drive 0
// 28   /DRIVE SELECT 2  Out    Select drive 1
// 30   /DRIVE SELECT 3  Out    Select drive 2
// 32   /DRIVE SELECT 4  Out    Select drive 3
// 34   /DIRECTION       Out    Step direction (1=in, 0=out)
// Odd  GND              -      Ground
//
// 20-Pin Data Cable
//
// Pin  Signal           Dir    Description
// ---  ------           ---    -----------
// 1    /DRIVE SELECTED  In     Drive acknowledges selection
// 2-10 GND              -      Ground (interleaved)
// 11   GND              -      Ground
// 12   GND              -      Ground
// 13   +MFM WRITE DATA  Out    Write data (single-ended or diff +)
// 14   -MFM WRITE DATA  Out    Write data complement (differential)
// 15   GND              -      Ground
// 16   GND              -      Ground
// 17   +MFM READ DATA   In     Read data (single-ended or diff +)
// 18   -MFM READ DATA   In     Read data complement (differential)
// 19   GND              -      Ground
// 20   GND              -      Ground
