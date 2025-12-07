//-----------------------------------------------------------------------------
// HDD Numerically Controlled Oscillator (NCO) for FluxRipper
// Generates bit clock for ST-506 MFM/RLL/ESDI hard drives
//
// Supports:
//   - MFM:  5 Mbps (ST-412, ST-506)
//   - RLL:  7.5 Mbps (RLL 2,7)
//   - ESDI: 10 Mbps, 15 Mbps
//
// Clock domain: 300 MHz (HDD domain)
// Timestamp resolution: 3.33ns
//
// Created: 2025-12-03 15:20
// Updated: 2025-12-04 13:35
//-----------------------------------------------------------------------------

module nco_hdd (
    input  wire        clk,             // System clock (300 MHz HDD domain)
    input  wire        reset,
    input  wire        enable,
    input  wire [31:0] freq_word,       // Frequency control word
    input  wire [15:0] phase_adj,       // Phase adjustment from loop filter
    input  wire        phase_adj_valid, // Apply phase adjustment
    output reg         bit_clk,         // Output bit clock
    output reg  [31:0] phase_accum,     // Current phase accumulator
    output reg         sample_point     // Data sampling point (mid-bit)
);

    //-------------------------------------------------------------------------
    // Frequency Control Word Calculations
    //-------------------------------------------------------------------------
    // FW = (data_rate * 2^32) / system_clock
    //
    // @300 MHz system clock:
    //   5 Mbps MFM:    FW = 71,582,788   (0x0444_4444)
    //   7.5 Mbps RLL:  FW = 107,374,182  (0x0666_6666)
    //   10 Mbps ESDI:  FW = 143,165,576  (0x0888_8888)
    //   15 Mbps ESDI:  FW = 214,748,364  (0x0CCC_CCCC)
    //
    // Verification:
    //   5M:   0x04444444 * 300M / 2^32 = 5.00 Mbps ✓
    //   7.5M: 0x06666666 * 300M / 2^32 = 7.50 Mbps ✓
    //   10M:  0x08888888 * 300M / 2^32 = 10.00 Mbps ✓
    //   15M:  0x0CCCCCCC * 300M / 2^32 = 15.00 Mbps ✓

    // Phase accumulator
    reg [31:0] next_phase;

    always @(*) begin
        next_phase = phase_accum + freq_word;
        if (phase_adj_valid) begin
            // Sign-extend phase adjustment
            next_phase = next_phase + {{16{phase_adj[15]}}, phase_adj};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            phase_accum <= 32'd0;
            bit_clk <= 1'b0;
            sample_point <= 1'b0;
        end else if (enable) begin
            phase_accum <= next_phase;

            // Generate bit clock (toggle on overflow)
            if (next_phase < phase_accum) begin
                bit_clk <= ~bit_clk;
            end

            // Generate sample point pulse at mid-bit (50% phase)
            sample_point <= (next_phase[31] && !phase_accum[31]);
        end else begin
            sample_point <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// HDD NCO with configurable data rates
// Supports MFM (5M), RLL (7.5M), ESDI (10M, 15M)
//-----------------------------------------------------------------------------
module nco_hdd_multirate (
    input  wire        clk,             // System clock (300 MHz)
    input  wire        reset,
    input  wire        enable,
    input  wire [2:0]  data_rate,       // HDD data rate selector
    input  wire [15:0] phase_adj,
    input  wire        phase_adj_valid,
    output wire        bit_clk,
    output wire [31:0] phase_accum,
    output wire        sample_point
);

    //-------------------------------------------------------------------------
    // Data Rate Encoding
    //-------------------------------------------------------------------------
    // 000 = 5 Mbps    (MFM standard, ST-506/ST-412)
    // 001 = 7.5 Mbps  (RLL 2,7)
    // 010 = 10 Mbps   (ESDI low)
    // 011 = 15 Mbps   (ESDI high)
    // 100 = 6 Mbps    (MFM high-capacity)
    // 101 = 8 Mbps    (RLL variant)
    // 110 = 12 Mbps   (ESDI mid)
    // 111 = Reserved

    // Pre-calculated frequency words for 300 MHz system clock
    // FW = (data_rate * 2^32) / 300M
    localparam FW_5M   = 32'h0444_4444;  // 5 Mbps
    localparam FW_6M   = 32'h051E_B851;  // 6 Mbps
    localparam FW_7_5M = 32'h0666_6666;  // 7.5 Mbps
    localparam FW_8M   = 32'h06D3_A06D;  // 8 Mbps
    localparam FW_10M  = 32'h0888_8888;  // 10 Mbps
    localparam FW_12M  = 32'h0A3D_70A3;  // 12 Mbps
    localparam FW_15M  = 32'h0CCC_CCCC;  // 15 Mbps

    reg [31:0] freq_word;

    always @(*) begin
        case (data_rate)
            3'b000: freq_word = FW_5M;
            3'b001: freq_word = FW_7_5M;
            3'b010: freq_word = FW_10M;
            3'b011: freq_word = FW_15M;
            3'b100: freq_word = FW_6M;
            3'b101: freq_word = FW_8M;
            3'b110: freq_word = FW_12M;
            default: freq_word = FW_5M;  // Default to MFM
        endcase
    end

    nco_hdd nco_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .freq_word(freq_word),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid),
        .bit_clk(bit_clk),
        .phase_accum(phase_accum),
        .sample_point(sample_point)
    );

endmodule

//-----------------------------------------------------------------------------
// HDD NCO with zone support for ESDI zone-recorded drives
// Some ESDI drives use variable data rates by cylinder zone
//-----------------------------------------------------------------------------
module nco_hdd_zoned (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [2:0]  base_rate,       // Base data rate
    input  wire        zone_enable,     // Enable zone-based rate adjustment
    input  wire [3:0]  zone,            // Zone number (0-15)
    input  wire [15:0] phase_adj,
    input  wire        phase_adj_valid,
    output wire        bit_clk,
    output wire [31:0] phase_accum,
    output wire        sample_point
);

    //-------------------------------------------------------------------------
    // Zone-Based Rate Adjustment
    //-------------------------------------------------------------------------
    // Some ESDI drives use Zone Bit Recording (ZBR) where outer zones
    // have higher data rates than inner zones.
    //
    // Example (CDC Wren series):
    //   Zone 0 (inner):  10 Mbps
    //   Zone 1:          11 Mbps
    //   Zone 2:          12 Mbps
    //   Zone 3 (outer):  13 Mbps
    //
    // The zone_offset adjusts the frequency word proportionally.

    // Zone frequency offsets (percentage increase per zone)
    // Each zone adds ~5% to base rate
    localparam [31:0] ZONE_OFFSET = 32'h0019_999A;  // ~5% of base rate

    // Base frequency words for 300 MHz
    localparam FW_5M   = 32'h0444_4444;
    localparam FW_7_5M = 32'h0666_6666;
    localparam FW_10M  = 32'h0888_8888;
    localparam FW_15M  = 32'h0CCC_CCCC;

    reg [31:0] base_freq;
    reg [31:0] freq_word;
    reg [35:0] zone_adjusted;  // Extra bits for multiplication

    always @(*) begin
        // Select base frequency
        case (base_rate)
            3'b000: base_freq = FW_5M;
            3'b001: base_freq = FW_7_5M;
            3'b010: base_freq = FW_10M;
            3'b011: base_freq = FW_15M;
            default: base_freq = FW_10M;
        endcase

        // Apply zone adjustment if enabled
        if (zone_enable) begin
            zone_adjusted = {4'b0, base_freq} + ({4'b0, ZONE_OFFSET} * {28'b0, zone});
            freq_word = zone_adjusted[31:0];
        end else begin
            freq_word = base_freq;
        end
    end

    nco_hdd nco_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .freq_word(freq_word),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid),
        .bit_clk(bit_clk),
        .phase_accum(phase_accum),
        .sample_point(sample_point)
    );

endmodule

//-----------------------------------------------------------------------------
// HDD Data Rate Definitions (for external use)
//-----------------------------------------------------------------------------
// These can be used by firmware to configure the NCO

// Data rate encodings for nco_hdd_multirate
`define HDD_RATE_5M_MFM     3'b000
`define HDD_RATE_7_5M_RLL   3'b001
`define HDD_RATE_10M_ESDI   3'b010
`define HDD_RATE_15M_ESDI   3'b011
`define HDD_RATE_6M_MFM     3'b100
`define HDD_RATE_8M_RLL     3'b101
`define HDD_RATE_12M_ESDI   3'b110
