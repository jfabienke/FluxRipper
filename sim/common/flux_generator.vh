//-----------------------------------------------------------------------------
// FluxRipper Flux Generator - Reusable Test Infrastructure
// Created: 2025-12-07
//
// Provides synthetic flux signal generation for testbenches:
//   - MFM/FM flux pattern generation
//   - Index pulse generation
//   - Configurable data rate
//   - Noise injection
//   - Known-pattern sequences for decoder validation
//
// Usage:
//   `include "flux_generator.vh"
//   // Call tasks: flux_init(), flux_mfm_byte(), flux_index_pulse(), etc.
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Flux Generation Parameters
//-----------------------------------------------------------------------------
localparam FLUX_RATE_DD   = 250000;   // 250 kbps (DD floppy)
localparam FLUX_RATE_HD   = 500000;   // 500 kbps (HD floppy)
localparam FLUX_RATE_ED   = 1000000;  // 1 Mbps (ED floppy)
localparam FLUX_RATE_MFM  = 5000000;  // 5 Mbps (MFM HDD)
localparam FLUX_RATE_RLL  = 7500000;  // 7.5 Mbps (RLL HDD)
localparam FLUX_RATE_ESDI = 10000000; // 10 Mbps (ESDI HDD)

// Timing parameters (in simulation time units, assuming 1ns timescale)
reg [31:0] flux_bit_period;     // Time per bit cell
reg [31:0] flux_half_period;    // Half bit cell
reg [31:0] flux_quarter_period; // Quarter bit cell

// State
reg flux_prev_data_bit;         // Previous data bit for MFM encoding
reg flux_signal;                // Current flux output
reg index_signal;               // Index pulse output

// Noise parameters
reg flux_noise_enable;
reg [7:0] flux_noise_percent;   // 0-100% jitter

//-----------------------------------------------------------------------------
// Initialize Flux Generator
//-----------------------------------------------------------------------------
task flux_init;
    input [31:0] bit_rate;
    begin
        // Calculate timing (assuming 1ns timescale)
        flux_bit_period = 1_000_000_000 / bit_rate;  // ns per bit
        flux_half_period = flux_bit_period / 2;
        flux_quarter_period = flux_bit_period / 4;

        flux_prev_data_bit = 1'b0;
        flux_signal = 1'b0;
        index_signal = 1'b0;
        flux_noise_enable = 1'b0;
        flux_noise_percent = 8'd0;

        $display("  [FLUX] Generator initialized: %0d bps, bit_period=%0d ns",
                 bit_rate, flux_bit_period);
    end
endtask

//-----------------------------------------------------------------------------
// Enable/Disable Noise
//-----------------------------------------------------------------------------
task flux_set_noise;
    input enable;
    input [7:0] percent;
    begin
        flux_noise_enable = enable;
        flux_noise_percent = percent;
        $display("  [FLUX] Noise %s: %0d%%", enable ? "enabled" : "disabled", percent);
    end
endtask

//-----------------------------------------------------------------------------
// Add Jitter to Timing
//-----------------------------------------------------------------------------
function [31:0] flux_add_jitter;
    input [31:0] base_time;
    reg [31:0] jitter_range;
    reg [31:0] jitter;
    begin
        if (flux_noise_enable && flux_noise_percent > 0) begin
            jitter_range = (base_time * flux_noise_percent) / 100;
            jitter = ($random % jitter_range) - (jitter_range / 2);
            flux_add_jitter = base_time + jitter;
        end else begin
            flux_add_jitter = base_time;
        end
    end
endfunction

//-----------------------------------------------------------------------------
// Generate Flux Transition
//-----------------------------------------------------------------------------
task flux_transition;
    begin
        flux_signal = ~flux_signal;
    end
endtask

//-----------------------------------------------------------------------------
// Generate MFM Encoded Bit
// MFM encoding rules:
//   Data 1: Always transition in middle of bit cell
//   Data 0: Transition at start if previous was also 0
//-----------------------------------------------------------------------------
task flux_mfm_bit;
    input data_bit;
    begin
        if (data_bit) begin
            // Data 1: transition at center only
            #(flux_add_jitter(flux_half_period));
            flux_transition();
            #(flux_add_jitter(flux_half_period));
        end else begin
            // Data 0: transition at start if previous was 0
            if (!flux_prev_data_bit) begin
                flux_transition();
            end
            #(flux_add_jitter(flux_bit_period));
        end
        flux_prev_data_bit = data_bit;
    end
endtask

//-----------------------------------------------------------------------------
// Generate MFM Encoded Byte
//-----------------------------------------------------------------------------
task flux_mfm_byte;
    input [7:0] data;
    integer i;
    begin
        for (i = 7; i >= 0; i = i - 1) begin
            flux_mfm_bit(data[i]);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate MFM Encoded Data Array
//-----------------------------------------------------------------------------
task flux_mfm_data;
    input [7:0] data [0:511];
    input integer length;
    integer i;
    begin
        for (i = 0; i < length; i = i + 1) begin
            flux_mfm_byte(data[i]);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate FM Encoded Bit
// FM encoding: Always transition at start, transition at center for 1
//-----------------------------------------------------------------------------
task flux_fm_bit;
    input data_bit;
    begin
        // Clock bit at start
        flux_transition();
        #(flux_add_jitter(flux_half_period));

        // Data bit at center (if 1)
        if (data_bit) begin
            flux_transition();
        end
        #(flux_add_jitter(flux_half_period));
    end
endtask

//-----------------------------------------------------------------------------
// Generate FM Encoded Byte
//-----------------------------------------------------------------------------
task flux_fm_byte;
    input [7:0] data;
    integer i;
    begin
        for (i = 7; i >= 0; i = i - 1) begin
            flux_fm_bit(data[i]);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Index Pulse
//-----------------------------------------------------------------------------
task flux_index_pulse;
    input [31:0] pulse_width_ns;
    begin
        index_signal = 1'b1;
        #(pulse_width_ns);
        index_signal = 1'b0;
    end
endtask

//-----------------------------------------------------------------------------
// Generate MFM Sync Pattern (A1 with missing clock)
// Standard MFM sync: 3x A1 bytes with missing clock bit
//-----------------------------------------------------------------------------
task flux_mfm_sync;
    integer i;
    begin
        // Generate 3 sync bytes (A1 with missing clock = 4489h)
        for (i = 0; i < 3; i = i + 1) begin
            // 0x4489 in MFM = 0100 0100 1000 1001
            // This is A1 with the 5th clock bit missing
            flux_mfm_byte(8'hA1);
            // Note: Actual missing clock requires special handling
            // For simulation, we just output the standard A1 pattern
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate GAP Bytes (4E pattern for MFM)
//-----------------------------------------------------------------------------
task flux_mfm_gap;
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1) begin
            flux_mfm_byte(8'h4E);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Zero-Filled Gap
//-----------------------------------------------------------------------------
task flux_mfm_zero_gap;
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1) begin
            flux_mfm_byte(8'h00);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Complete MFM Sector
// Standard IBM format sector structure
//-----------------------------------------------------------------------------
task flux_mfm_sector;
    input [7:0] cylinder;
    input [7:0] head;
    input [7:0] sector;
    input [7:0] size_code;  // 0=128, 1=256, 2=512, 3=1024 bytes
    input [7:0] data [0:511];
    input integer data_length;
    reg [7:0] crc_data [0:5];
    integer i;
    begin
        // Gap 2 (22 bytes of 4E)
        flux_mfm_gap(22);

        // Sync (12 bytes of 00)
        flux_mfm_zero_gap(12);

        // ID Address Mark
        flux_mfm_sync();
        flux_mfm_byte(8'hFE);  // ID AM

        // ID Field: C, H, R, N
        flux_mfm_byte(cylinder);
        flux_mfm_byte(head);
        flux_mfm_byte(sector);
        flux_mfm_byte(size_code);

        // ID CRC (placeholder - 2 bytes)
        flux_mfm_byte(8'h00);
        flux_mfm_byte(8'h00);

        // Gap 3 (22 bytes of 4E)
        flux_mfm_gap(22);

        // Sync (12 bytes of 00)
        flux_mfm_zero_gap(12);

        // Data Address Mark
        flux_mfm_sync();
        flux_mfm_byte(8'hFB);  // Data AM

        // Data Field
        for (i = 0; i < data_length; i = i + 1) begin
            flux_mfm_byte(data[i]);
        end

        // Data CRC (placeholder - 2 bytes)
        flux_mfm_byte(8'h00);
        flux_mfm_byte(8'h00);

        // Gap 4 (until next sector or index)
        flux_mfm_gap(54);
    end
endtask

//-----------------------------------------------------------------------------
// Generate Complete MFM Track
//-----------------------------------------------------------------------------
task flux_mfm_track;
    input [7:0] cylinder;
    input [7:0] head;
    input integer sectors_per_track;
    input [7:0] sector_data [0:511];  // Data for all sectors (same pattern)
    integer i;
    begin
        // Gap 4a (80 bytes of 4E)
        flux_mfm_gap(80);

        // Sync (12 bytes of 00)
        flux_mfm_zero_gap(12);

        // Index Address Mark
        flux_mfm_sync();
        flux_mfm_byte(8'hFC);  // Index AM

        // Gap 1 (50 bytes of 4E)
        flux_mfm_gap(50);

        // Sectors
        for (i = 1; i <= sectors_per_track; i = i + 1) begin
            flux_mfm_sector(cylinder, head, i, 8'h02, sector_data, 512);
        end

        // Gap 4b (fill to index)
        flux_mfm_gap(200);
    end
endtask

//-----------------------------------------------------------------------------
// Generate Raw Flux Intervals (for testing data separator)
// Input: Array of interval times in nanoseconds
//-----------------------------------------------------------------------------
task flux_raw_intervals;
    input [31:0] intervals [0:1023];
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1) begin
            flux_transition();
            #(flux_add_jitter(intervals[i]));
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Test Pattern: Alternating 1s and 0s
// Useful for PLL lock testing
//-----------------------------------------------------------------------------
task flux_test_pattern_alt;
    input integer bit_count;
    integer i;
    begin
        for (i = 0; i < bit_count; i = i + 1) begin
            flux_mfm_bit(i[0]);  // Alternating 0,1,0,1...
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Test Pattern: All 1s
// Maximum flux density
//-----------------------------------------------------------------------------
task flux_test_pattern_ones;
    input integer bit_count;
    integer i;
    begin
        for (i = 0; i < bit_count; i = i + 1) begin
            flux_mfm_bit(1'b1);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Test Pattern: All 0s
// Minimum flux density (clock bits only in FM, sparse in MFM)
//-----------------------------------------------------------------------------
task flux_test_pattern_zeros;
    input integer bit_count;
    integer i;
    begin
        flux_prev_data_bit = 1'b1;  // Start with 1 to get first clock
        for (i = 0; i < bit_count; i = i + 1) begin
            flux_mfm_bit(1'b0);
        end
    end
endtask

//-----------------------------------------------------------------------------
// Generate Test Pattern: Pseudo-Random
//-----------------------------------------------------------------------------
task flux_test_pattern_prbs;
    input integer bit_count;
    input [31:0] seed;
    reg [31:0] lfsr;
    integer i;
    begin
        lfsr = seed;
        for (i = 0; i < bit_count; i = i + 1) begin
            flux_mfm_bit(lfsr[0]);
            // LFSR feedback polynomial: x^32 + x^22 + x^2 + x^1 + 1
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        end
    end
endtask

//-----------------------------------------------------------------------------
// Simulate Revolution (continuous flux with periodic index)
//-----------------------------------------------------------------------------
task flux_revolution;
    input [31:0] revolution_time_ns;  // e.g., 200_000_000 for 200ms (300 RPM)
    input [31:0] index_width_ns;      // Index pulse width
    begin
        fork
            // Index pulse at start of revolution
            flux_index_pulse(index_width_ns);
        join_none

        // Generate flux for one revolution
        // (Caller should be generating flux data)
        #(revolution_time_ns);
    end
endtask

//-----------------------------------------------------------------------------
// Wait for Flux Transitions
// Useful for monitoring DUT output
//-----------------------------------------------------------------------------
task flux_wait_transitions;
    input integer count;
    input [31:0] timeout_ns;
    output integer actual_count;
    output timeout;
    reg [31:0] start_time;
    begin
        actual_count = 0;
        timeout = 0;
        start_time = $time;

        while (actual_count < count && !timeout) begin
            @(flux_signal);
            actual_count = actual_count + 1;
            if (($time - start_time) > timeout_ns) begin
                timeout = 1;
            end
        end
    end
endtask
