//-----------------------------------------------------------------------------
// Numerically Controlled Oscillator (NCO) for FluxRipper DPLL
// Generates bit clock synchronized to flux transitions
//
// Supports:
//   - Standard rates: 250K, 300K, 500K, 1M bps
//   - RPM compensation: 300 RPM vs 360 RPM
//   - Macintosh variable-speed zones (5 zones, 393.6K - 590.1K bps)
//
// Updated: 2025-12-03 22:45
//-----------------------------------------------------------------------------

module nco (
    input  wire        clk,             // System clock (200 MHz)
    input  wire        reset,
    input  wire        enable,
    input  wire [31:0] freq_word,       // Frequency control word
    input  wire [15:0] phase_adj,       // Phase adjustment from loop filter
    input  wire        phase_adj_valid, // Apply phase adjustment
    output reg         bit_clk,         // Output bit clock
    output reg  [31:0] phase_accum,     // Current phase accumulator
    output reg         sample_point     // Data sampling point (mid-bit)
);

    // Phase accumulator
    reg [31:0] next_phase;
    reg        phase_overflow;
    reg        phase_half;

    // Frequency control word calculations for different data rates:
    // FW = (data_rate * 2^32) / system_clock
    //
    // @200 MHz system clock:
    //   250 kbps: FW = 5,368,709    (0x0051EB85)
    //   300 kbps: FW = 6,442,451    (0x00624DD3)
    //   500 kbps: FW = 10,737,418   (0x00A3D70A)
    //   1000 kbps: FW = 21,474,836  (0x0147AE14)

    always @(*) begin
        next_phase = phase_accum + freq_word;
        if (phase_adj_valid) begin
            next_phase = next_phase + {{16{phase_adj[15]}}, phase_adj};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            phase_accum <= 32'd0;
            bit_clk <= 1'b0;
            sample_point <= 1'b0;
            phase_overflow <= 1'b0;
            phase_half <= 1'b0;
        end else if (enable) begin
            phase_accum <= next_phase;

            // Detect phase accumulator overflow (bit boundary)
            phase_overflow <= (next_phase < phase_accum);

            // Detect 50% phase point (sample point)
            phase_half <= (next_phase[31] && !phase_accum[31]);

            // Generate bit clock (toggle on overflow)
            if (next_phase < phase_accum) begin
                bit_clk <= ~bit_clk;
            end

            // Generate sample point pulse at mid-bit
            sample_point <= (next_phase[31] && !phase_accum[31]);
        end else begin
            sample_point <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// NCO with configurable data rates
// Supports 250K, 300K, 500K, 1M bps
//-----------------------------------------------------------------------------
module nco_multirate (
    input  wire        clk,             // System clock (200 MHz)
    input  wire        reset,
    input  wire        enable,
    input  wire [1:0]  data_rate,       // 00=250K, 01=300K, 10=500K, 11=1M
    input  wire [15:0] phase_adj,
    input  wire        phase_adj_valid,
    output wire        bit_clk,
    output wire [31:0] phase_accum,
    output wire        sample_point
);

    // Pre-calculated frequency words for 200 MHz system clock
    reg [31:0] freq_word;

    always @(*) begin
        case (data_rate)
            2'b00: freq_word = 32'h0051EB85;  // 250 kbps
            2'b01: freq_word = 32'h00624DD3;  // 300 kbps
            2'b10: freq_word = 32'h00A3D70A;  // 500 kbps
            2'b11: freq_word = 32'h0147AE14;  // 1000 kbps
        endcase
    end

    nco nco_inst (
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
// NCO with RPM compensation and Macintosh zone support
// Adjusts for 300 RPM vs 360 RPM drive speeds
// Supports Mac/Lisa variable-speed GCR zones
//-----------------------------------------------------------------------------
module nco_rpm_compensated (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [1:0]  data_rate,       // Base data rate (when not in Mac mode)
    input  wire        rpm_360,         // 1 = 360 RPM drive, 0 = 300 RPM
    input  wire        mac_zone_enable, // Enable Macintosh variable-speed mode
    input  wire [2:0]  mac_zone,        // Macintosh zone (0-4)
    input  wire [15:0] phase_adj,
    input  wire        phase_adj_valid,
    output wire        bit_clk,
    output wire [31:0] phase_accum,
    output wire        sample_point
);

    // Frequency words for 200 MHz system clock
    // Standard 300 RPM values
    localparam FW_250K_300RPM = 32'h0051EB85;
    localparam FW_300K_300RPM = 32'h00624DD3;
    localparam FW_500K_300RPM = 32'h00A3D70A;
    localparam FW_1M_300RPM   = 32'h0147AE14;

    // Standard 360 RPM values (multiply by 1.2 = 360/300)
    localparam FW_250K_360RPM = 32'h00624DD3;  // 300 kbps effective
    localparam FW_300K_360RPM = 32'h00765D9F;  // 360 kbps effective
    localparam FW_500K_360RPM = 32'h00C49BA6;  // 600 kbps effective
    localparam FW_1M_360RPM   = 32'h01893748;  // 1.2 Mbps effective

    //-------------------------------------------------------------------------
    // Macintosh 400K/800K GCR Zone Frequency Words
    //-------------------------------------------------------------------------
    // Mac drives spin at constant 394-590 RPM equivalent data rate
    // Zones are divided by track number:
    //   Zone 0: Tracks 0-15   (innermost, slowest data rate)
    //   Zone 1: Tracks 16-31
    //   Zone 2: Tracks 32-47
    //   Zone 3: Tracks 48-63
    //   Zone 4: Tracks 64-79  (outermost, fastest data rate)
    //
    // FW = (data_rate_bps * 2^32) / 200_000_000
    //
    localparam FW_MAC_ZONE0 = 32'h00D1B717;  // 393.6 Kbps (2.54 µs bit cell)
    localparam FW_MAC_ZONE1 = 32'h00E4B0A9;  // 429.2 Kbps (2.33 µs bit cell)
    localparam FW_MAC_ZONE2 = 32'h00FB931A;  // 472.1 Kbps (2.12 µs bit cell)
    localparam FW_MAC_ZONE3 = 32'h011762F4;  // 524.6 Kbps (1.91 µs bit cell)
    localparam FW_MAC_ZONE4 = 32'h013A22C3;  // 590.1 Kbps (1.69 µs bit cell)

    reg [31:0] freq_word;

    always @(*) begin
        if (mac_zone_enable) begin
            // Macintosh variable-speed mode
            case (mac_zone)
                3'd0:    freq_word = FW_MAC_ZONE0;
                3'd1:    freq_word = FW_MAC_ZONE1;
                3'd2:    freq_word = FW_MAC_ZONE2;
                3'd3:    freq_word = FW_MAC_ZONE3;
                default: freq_word = FW_MAC_ZONE4;  // Zone 4 and above
            endcase
        end else if (rpm_360) begin
            // Standard 360 RPM mode
            case (data_rate)
                2'b00: freq_word = FW_250K_360RPM;
                2'b01: freq_word = FW_300K_360RPM;
                2'b10: freq_word = FW_500K_360RPM;
                2'b11: freq_word = FW_1M_360RPM;
            endcase
        end else begin
            // Standard 300 RPM mode
            case (data_rate)
                2'b00: freq_word = FW_250K_300RPM;
                2'b01: freq_word = FW_300K_300RPM;
                2'b10: freq_word = FW_500K_300RPM;
                2'b11: freq_word = FW_1M_300RPM;
            endcase
        end
    end

    nco nco_inst (
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
