//-----------------------------------------------------------------------------
// Write Precompensation Module for FluxRipper
// Adjusts write timing to compensate for magnetic peak shift
//
// Updated: 2025-12-02 16:50
//-----------------------------------------------------------------------------

module write_precompensation (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Configuration
    input  wire [1:0]  data_rate,       // Current data rate
    input  wire [7:0]  precomp_track,   // Track threshold for precomp
    input  wire [7:0]  current_track,   // Current head position
    input  wire [3:0]  precomp_value,   // Precompensation amount (ns)

    // Data input
    input  wire        data_in,         // Write data bit
    input  wire        data_valid,      // Data is valid

    // MFM encoded output
    output reg         write_pulse,     // Precompensated write pulse
    output reg  [1:0]  precomp_status   // 00=none, 01=early, 10=late, 11=error
);

    //-------------------------------------------------------------------------
    // Precompensation timing
    //-------------------------------------------------------------------------
    // Standard precompensation delays:
    // @500 kbps: ~140ns early/late
    // @300 kbps: ~233ns early/late
    // @250 kbps: ~280ns early/late
    // @1 Mbps:   ~70ns early/late

    // Delay in clock cycles (assuming 200 MHz clock = 5ns per cycle)
    reg [5:0] precomp_cycles;

    always @(*) begin
        case (data_rate)
            2'b00: precomp_cycles = 6'd28;   // 500K: 140ns
            2'b01: precomp_cycles = 6'd47;   // 300K: 235ns
            2'b10: precomp_cycles = 6'd56;   // 250K: 280ns
            2'b11: precomp_cycles = 6'd14;   // 1M: 70ns
        endcase
    end

    //-------------------------------------------------------------------------
    // Pattern detection for precompensation decision
    //-------------------------------------------------------------------------
    // Precompensation rules (for MFM):
    // - Shift EARLY if: 1-1-0 pattern (adjacent 1s, current is 0)
    // - Shift LATE if:  0-1-1 pattern (current 1 follows another 1)
    // - No shift for:   0-1-0, 1-0-0, 0-0-1, etc.

    reg [3:0] bit_history;  // Last 4 data bits
    reg       precomp_enable;

    // Determine if precompensation should be applied
    always @(posedge clk) begin
        if (reset) begin
            precomp_enable <= 1'b0;
        end else begin
            // Only precompensate on inner tracks (higher density)
            precomp_enable <= (current_track >= precomp_track);
        end
    end

    //-------------------------------------------------------------------------
    // Precompensation decision
    //-------------------------------------------------------------------------
    wire shift_early;
    wire shift_late;

    // Pattern: bit_history[3]=oldest, bit_history[0]=newest (before current)
    // Current bit is data_in

    // Shift early for pattern: X-1-1-0 (two preceding 1s, current 0)
    assign shift_early = precomp_enable &&
                         bit_history[0] && bit_history[1] && !data_in;

    // Shift late for pattern: X-0-1-1 (preceding 0-1, current 1)
    assign shift_late = precomp_enable &&
                        !bit_history[1] && bit_history[0] && data_in;

    //-------------------------------------------------------------------------
    // Output timing adjustment
    //-------------------------------------------------------------------------
    reg [5:0] delay_counter;
    reg [5:0] target_delay;
    reg       output_pending;
    reg       pending_data;

    // Base delay for bit cell center
    reg [5:0] base_delay;

    always @(*) begin
        case (data_rate)
            2'b00: base_delay = 6'd50;   // 500K: 1us cell / 2 = 500ns = 100 cycles
            2'b01: base_delay = 6'd50;   // 300K: adjusted by NCO
            2'b10: base_delay = 6'd50;   // 250K: adjusted by NCO
            2'b11: base_delay = 6'd25;   // 1M: 500ns cell / 2 = 250ns = 50 cycles
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            bit_history <= 4'b0000;
            write_pulse <= 1'b0;
            precomp_status <= 2'b00;
            delay_counter <= 6'd0;
            target_delay <= 6'd0;
            output_pending <= 1'b0;
            pending_data <= 1'b0;
        end else if (enable) begin
            // Default outputs
            write_pulse <= 1'b0;

            // Handle pending output
            if (output_pending) begin
                if (delay_counter > 6'd0) begin
                    delay_counter <= delay_counter - 1'b1;
                end else begin
                    write_pulse <= pending_data;
                    output_pending <= 1'b0;
                end
            end

            // New data bit
            if (data_valid) begin
                // Update history
                bit_history <= {bit_history[2:0], data_in};

                // Calculate output delay
                if (shift_early) begin
                    target_delay <= base_delay - precomp_cycles;
                    precomp_status <= 2'b01;  // Early
                end else if (shift_late) begin
                    target_delay <= base_delay + precomp_cycles;
                    precomp_status <= 2'b10;  // Late
                end else begin
                    target_delay <= base_delay;
                    precomp_status <= 2'b00;  // None
                end

                // Start output timing
                delay_counter <= target_delay;
                output_pending <= 1'b1;
                pending_data <= data_in;
            end
        end else begin
            write_pulse <= 1'b0;
            precomp_status <= 2'b00;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Write Driver
// Generates write gate and write data signals
//-----------------------------------------------------------------------------
module write_driver (
    input  wire        clk,
    input  wire        reset,

    // Control
    input  wire        write_enable,    // Write gate command
    input  wire        write_data,      // Data to write
    input  wire        data_valid,

    // Configuration
    input  wire [1:0]  data_rate,
    input  wire        mfm_mode,        // 1=MFM, 0=FM

    // Drive outputs
    output reg         write_gate,      // Write gate signal
    output reg         write_data_out,  // Write data output
    output reg         write_clock,     // Write clock (for MFM)

    // Status
    output reg         write_active,
    output reg  [15:0] bytes_written
);

    // Write pulse generation
    reg [7:0] pulse_counter;
    reg [7:0] pulse_width;

    // Calculate pulse width based on data rate
    always @(*) begin
        case (data_rate)
            2'b00: pulse_width = 8'd50;   // 500K
            2'b01: pulse_width = 8'd83;   // 300K
            2'b10: pulse_width = 8'd100;  // 250K
            2'b11: pulse_width = 8'd25;   // 1M
        endcase
    end

    // State machine
    localparam S_IDLE = 2'd0;
    localparam S_WRITE = 2'd1;
    localparam S_GAP = 2'd2;

    reg [1:0] state;
    reg [7:0] gap_counter;

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            write_gate <= 1'b0;
            write_data_out <= 1'b0;
            write_clock <= 1'b0;
            write_active <= 1'b0;
            bytes_written <= 16'd0;
            pulse_counter <= 8'd0;
            gap_counter <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    write_gate <= 1'b0;
                    write_active <= 1'b0;

                    if (write_enable) begin
                        write_gate <= 1'b1;
                        write_active <= 1'b1;
                        bytes_written <= 16'd0;
                        gap_counter <= 8'd12;  // Write splice gap
                        state <= S_GAP;
                    end
                end

                S_GAP: begin
                    // Initial gap before data
                    if (gap_counter > 8'd0) begin
                        gap_counter <= gap_counter - 1'b1;
                        write_data_out <= 1'b0;
                    end else begin
                        state <= S_WRITE;
                    end
                end

                S_WRITE: begin
                    if (!write_enable) begin
                        state <= S_IDLE;
                    end else if (data_valid) begin
                        // Generate write pulse
                        write_data_out <= write_data;
                        pulse_counter <= pulse_width;

                        // Count bytes (every 8 bits for FM, 16 for MFM)
                        // Simplified: count every valid data
                    end else if (pulse_counter > 8'd0) begin
                        pulse_counter <= pulse_counter - 1'b1;
                        if (pulse_counter == 8'd1) begin
                            write_data_out <= 1'b0;  // End pulse
                        end
                    end
                end
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Erase Head Controller
// Controls tunnel erase for write operations
//-----------------------------------------------------------------------------
module erase_controller (
    input  wire        clk,
    input  wire        reset,

    // Control
    input  wire        write_gate,      // Write is active
    input  wire [31:0] clk_freq,

    // Erase outputs
    output reg         erase_enable,    // Enable erase current
    output reg         upper_erase,     // Upper erase head active
    output reg         lower_erase      // Lower erase head active
);

    // Erase timing: typically erase leads write by ~200us
    localparam ERASE_LEAD = 32'd200;  // 200us in microseconds

    reg [31:0] lead_counter;
    reg [31:0] lead_cycles;

    // Calculate lead time in clock cycles
    always @(posedge clk) begin
        lead_cycles <= (clk_freq / 1000000) * ERASE_LEAD;
    end

    always @(posedge clk) begin
        if (reset) begin
            erase_enable <= 1'b0;
            upper_erase <= 1'b0;
            lower_erase <= 1'b0;
            lead_counter <= 32'd0;
        end else begin
            if (write_gate) begin
                // Start erase before write data
                if (lead_counter < lead_cycles) begin
                    lead_counter <= lead_counter + 1'b1;
                    erase_enable <= 1'b1;
                    upper_erase <= 1'b1;
                    lower_erase <= 1'b1;
                end
            end else begin
                // Trail erase after write ends
                if (lead_counter > 32'd0) begin
                    lead_counter <= lead_counter - 1'b1;
                end else begin
                    erase_enable <= 1'b0;
                    upper_erase <= 1'b0;
                    lower_erase <= 1'b0;
                end
            end
        end
    end

endmodule
