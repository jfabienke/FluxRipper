//-----------------------------------------------------------------------------
// Macintosh Zone Calculator for FluxRipper
// Calculates the data rate zone based on current track position
//
// Macintosh 400K/800K disks use Constant Angular Velocity (CAV) with
// variable data rates across 5 track zones to maximize capacity.
//
// Zone boundaries:
//   Zone 0: Tracks 0-15   (innermost, slowest: 393.6 Kbps)
//   Zone 1: Tracks 16-31  (429.2 Kbps)
//   Zone 2: Tracks 32-47  (472.1 Kbps)
//   Zone 3: Tracks 48-63  (524.6 Kbps)
//   Zone 4: Tracks 64-79  (outermost, fastest: 590.1 Kbps)
//
// Also compatible with:
//   - Apple Lisa (same zone structure)
//   - Victor 9000 / Sirius 1 (10 zones - requires parameter change)
//
// Updated: 2025-12-03 22:50
//-----------------------------------------------------------------------------

module zone_calculator #(
    parameter ZONE_MODE = 0  // 0 = Mac/Lisa (5 zones), 1 = Victor 9000 (10 zones)
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  current_track,    // Current head position (0-79 typical)
    input  wire        mac_mode_enable,  // Enable zone-based data rate
    output reg  [2:0]  zone,             // Current zone (0-4 for Mac, 0-9 for Victor)
    output reg         zone_changed      // Pulse on zone transition (for DPLL rate change)
);

    reg [2:0] prev_zone;
    reg [2:0] calc_zone;

    //-------------------------------------------------------------------------
    // Zone Calculation (combinational)
    //-------------------------------------------------------------------------
    always @(*) begin
        if (ZONE_MODE == 0) begin
            // Macintosh / Lisa: 5 zones, 16 tracks each
            // Zone = track / 16 (integer division via comparison)
            if (current_track >= 8'd64)
                calc_zone = 3'd4;
            else if (current_track >= 8'd48)
                calc_zone = 3'd3;
            else if (current_track >= 8'd32)
                calc_zone = 3'd2;
            else if (current_track >= 8'd16)
                calc_zone = 3'd1;
            else
                calc_zone = 3'd0;
        end else begin
            // Victor 9000 / Sirius 1: 10 zones, 8 tracks each
            // Zone = track / 8
            calc_zone = current_track[6:3];  // Bits [6:3] = track / 8
        end
    end

    //-------------------------------------------------------------------------
    // Zone State Machine (registered)
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            zone <= 3'd0;
            prev_zone <= 3'd0;
            zone_changed <= 1'b0;
        end else if (mac_mode_enable) begin
            zone <= calc_zone;
            prev_zone <= zone;

            // Generate single-cycle pulse when zone changes
            zone_changed <= (calc_zone != prev_zone);
        end else begin
            // Not in Mac mode - reset zone tracking
            zone <= 3'd0;
            prev_zone <= 3'd0;
            zone_changed <= 1'b0;
        end
    end

endmodule
