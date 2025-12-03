//-----------------------------------------------------------------------------
// Digital PLL Top Module for FluxRipper
// Complete data separator with all submodules
//
// Based on CAPSImg CapsFDCEmulator.cpp FdcShiftBit() algorithm
//
// Supports:
//   - Standard data rates: 250K, 300K, 500K, 1M bps
//   - RPM compensation: 300 RPM vs 360 RPM
//   - Macintosh variable-speed GCR zones (5 zones, 393.6K - 590.1K bps)
//
// Updated: 2025-12-03 23:00
//-----------------------------------------------------------------------------

module digital_pll (
    // Clock and reset
    input  wire        clk,             // System clock (200 MHz recommended)
    input  wire        reset,

    // Configuration
    input  wire        enable,
    input  wire [1:0]  data_rate,       // 00=250K, 01=300K, 10=500K, 11=1M
    input  wire        rpm_360,         // 1 = 360 RPM drive
    input  wire [15:0] lock_threshold,  // Lock detection threshold

    // Macintosh variable-speed zone support
    input  wire        mac_zone_enable, // Enable Mac zone-based data rate
    input  wire [2:0]  mac_zone,        // Current Mac zone (0-4)
    input  wire        rate_change,     // Pulse when zone changes (forces re-lock)

    // Flux input
    input  wire        flux_in,         // Raw flux signal from drive

    // Data output
    output wire        data_bit,        // Recovered data bit
    output wire        data_ready,      // Data bit is valid
    output wire        bit_clk,         // Recovered bit clock

    // Status outputs
    output wire        pll_locked,      // PLL is locked
    output wire [7:0]  lock_quality,    // Lock quality (0-255)
    output wire [1:0]  margin_zone,     // Phase margin indicator
    output wire [31:0] phase_accum,     // NCO phase (for diagnostics)
    output wire [15:0] phase_error,     // Current phase error
    output wire [1:0]  bandwidth        // Current loop bandwidth
);

    //-------------------------------------------------------------------------
    // Internal signals
    //-------------------------------------------------------------------------

    // Edge detector outputs
    wire        edge_detected;
    wire        edge_polarity;
    wire [31:0] edge_timestamp;
    wire [15:0] edge_interval;

    // Phase detector outputs
    wire [15:0] pd_phase_error;
    wire        pd_error_valid;
    wire [1:0]  pd_margin_zone;

    // Loop filter outputs
    wire [15:0] lf_phase_adj;
    wire        lf_phase_adj_valid;

    // NCO outputs
    wire        nco_bit_clk;
    wire [31:0] nco_phase;
    wire        nco_sample_point;

    // Data sampler outputs
    wire        sampler_data;
    wire        sampler_ready;
    wire        sampler_in_window;

    // Lock detector outputs
    wire        ld_locked;
    wire [7:0]  ld_quality;
    wire [15:0] ld_avg_error;

    // Loop filter bandwidth
    wire [1:0]  lf_bandwidth;

    //-------------------------------------------------------------------------
    // Submodule instantiations
    //-------------------------------------------------------------------------

    // Edge Detector with glitch filtering
    edge_detector_filtered u_edge_detector (
        .clk(clk),
        .reset(reset),
        .flux_in(flux_in),
        .enable(enable),
        .filter_depth(4'd3),            // 3 clock filter
        .edge_detected(edge_detected),
        .edge_polarity(edge_polarity),
        .edge_timestamp(edge_timestamp),
        .edge_interval(edge_interval)
    );

    // Phase Detector with missing pulse detection
    phase_detector_robust u_phase_detector (
        .clk(clk),
        .reset(reset),
        .edge_detected(edge_detected),
        .nco_phase(nco_phase),
        .bit_clk(nco_bit_clk),
        .phase_error(pd_phase_error),
        .error_valid(pd_error_valid),
        .margin_zone(pd_margin_zone),
        .missing_pulse(),               // Not used at top level
        .consecutive_missing()          // Not used at top level
    );

    // Loop Filter with automatic bandwidth adjustment
    // rate_change input forces acquisition mode during Mac zone transitions
    loop_filter_auto u_loop_filter (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .phase_error(pd_phase_error),
        .error_valid(pd_error_valid),
        .pll_locked(ld_locked),
        .margin_zone(pd_margin_zone),
        .rate_change(rate_change),       // Mac zone transition strobe
        .phase_adj(lf_phase_adj),
        .phase_adj_valid(lf_phase_adj_valid),
        .current_bandwidth(lf_bandwidth)
    );

    // NCO with RPM compensation and Mac zone support
    nco_rpm_compensated u_nco (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_rate(data_rate),
        .rpm_360(rpm_360),
        .mac_zone_enable(mac_zone_enable),  // Mac variable-speed mode
        .mac_zone(mac_zone),                // Current Mac zone (0-4)
        .phase_adj(lf_phase_adj),
        .phase_adj_valid(lf_phase_adj_valid),
        .bit_clk(nco_bit_clk),
        .phase_accum(nco_phase),
        .sample_point(nco_sample_point)
    );

    // Data Sampler
    data_sampler u_data_sampler (
        .clk(clk),
        .reset(reset),
        .sample_point(nco_sample_point),
        .flux_in(flux_in),
        .nco_phase(nco_phase),
        .bit_value(sampler_data),
        .bit_ready(sampler_ready),
        .in_window(sampler_in_window)
    );

    // Lock Detector
    lock_detector u_lock_detector (
        .clk(clk),
        .reset(reset),
        .phase_error(pd_phase_error),
        .error_valid(pd_error_valid),
        .margin_zone(pd_margin_zone),
        .lock_threshold(lock_threshold),
        .pll_locked(ld_locked),
        .lock_quality(ld_quality),
        .avg_phase_error(ld_avg_error)
    );

    //-------------------------------------------------------------------------
    // Output assignments
    //-------------------------------------------------------------------------

    assign data_bit     = sampler_data;
    assign data_ready   = sampler_ready;
    assign bit_clk      = nco_bit_clk;
    assign pll_locked   = ld_locked;
    assign lock_quality = ld_quality;
    assign margin_zone  = pd_margin_zone;
    assign phase_accum  = nco_phase;
    assign phase_error  = pd_phase_error;
    assign bandwidth    = lf_bandwidth;

endmodule

//-----------------------------------------------------------------------------
// Simplified Digital PLL for basic operation
// Reduced resource usage, no automatic bandwidth adjustment
//-----------------------------------------------------------------------------
module digital_pll_simple (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [1:0]  data_rate,
    input  wire        flux_in,
    output wire        data_bit,
    output wire        data_ready,
    output wire        bit_clk,
    output wire        pll_locked
);

    // Simplified implementation with fixed bandwidth
    wire        edge_detected;
    wire [15:0] phase_error;
    wire        error_valid;
    wire [15:0] phase_adj;
    wire        phase_adj_valid;
    wire [31:0] nco_phase;
    wire        sample_point;

    edge_detector u_edge (
        .clk(clk),
        .reset(reset),
        .flux_in(flux_in),
        .enable(enable),
        .edge_detected(edge_detected),
        .edge_polarity(),
        .edge_timestamp(),
        .edge_interval()
    );

    phase_detector u_pd (
        .clk(clk),
        .reset(reset),
        .edge_detected(edge_detected),
        .nco_phase(nco_phase),
        .phase_error(phase_error),
        .error_valid(error_valid),
        .margin_zone()
    );

    loop_filter u_lf (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .phase_error(phase_error),
        .error_valid(error_valid),
        .kp(8'h20),                     // Fixed medium bandwidth
        .ki(8'h04),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid)
    );

    nco_multirate u_nco (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_rate(data_rate),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid),
        .bit_clk(bit_clk),
        .phase_accum(nco_phase),
        .sample_point(sample_point)
    );

    data_sampler u_sampler (
        .clk(clk),
        .reset(reset),
        .sample_point(sample_point),
        .flux_in(flux_in),
        .nco_phase(nco_phase),
        .bit_value(data_bit),
        .bit_ready(data_ready),
        .in_window()
    );

    // Simple lock detection based on sample count
    reg [7:0] sample_cnt;
    assign pll_locked = (sample_cnt > 8'd32);

    always @(posedge clk) begin
        if (reset) begin
            sample_cnt <= 8'd0;
        end else if (data_ready) begin
            if (sample_cnt < 8'hFF) begin
                sample_cnt <= sample_cnt + 1'b1;
            end
        end
    end

endmodule
