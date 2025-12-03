//-----------------------------------------------------------------------------
// Density Probe Controller
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Actively tests drive density capability by attempting reads at different
// data rates and measuring PLL lock success.
//
// Probe Strategy:
//   1. Start at configured data rate (or 500K default)
//   2. Attempt to read sector data
//   3. If PLL locks and sync detected -> data rate works
//   4. Record success/failure, move to next rate
//   5. Report highest successful rate as density capability
//
// Non-destructive: Only reads, never writes.
//
// Target: AMD Spartan UltraScale+ SCU35
// Created: 2025-12-04 11:52
//-----------------------------------------------------------------------------

module density_probe_ctrl (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    //-------------------------------------------------------------------------
    // Probe Request Interface (from drive_profile_detector)
    //-------------------------------------------------------------------------
    input  wire        probe_start,         // Start probing requested rate
    input  wire [1:0]  probe_rate,          // Rate to test (00=250K, 01=300K, 10=500K, 11=1M)
    output reg         probe_complete,      // Probe finished
    output reg         probe_success,       // Probe succeeded (PLL locked, sync found)

    //-------------------------------------------------------------------------
    // FDC Interface
    //-------------------------------------------------------------------------
    output reg  [1:0]  override_data_rate,  // Override data rate during probe
    output reg         override_enable,      // Enable data rate override
    output reg         enable_read,          // Request read operation

    //-------------------------------------------------------------------------
    // Status Inputs
    //-------------------------------------------------------------------------
    input  wire        pll_locked,          // DPLL locked to data
    input  wire        sync_detected,       // Address mark detected
    input  wire        index_pulse,         // Index pulse (revolution marker)

    //-------------------------------------------------------------------------
    // Timing Configuration
    //-------------------------------------------------------------------------
    input  wire [31:0] clk_freq             // System clock frequency
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam S_IDLE       = 3'd0;
    localparam S_SET_RATE   = 3'd1;
    localparam S_WAIT_LOCK  = 3'd2;
    localparam S_WAIT_SYNC  = 3'd3;
    localparam S_SUCCESS    = 3'd4;
    localparam S_FAIL       = 3'd5;
    localparam S_DONE       = 3'd6;

    reg [2:0]  state;
    reg [23:0] timeout_counter;
    reg [1:0]  current_rate;

    // Timeout: ~50ms at 200MHz = 10,000,000 clocks
    // Use shorter timeout for quick detection: ~5ms = 1,000,000 clocks
    wire [23:0] lock_timeout = clk_freq[31:8];    // ~780us at 200MHz
    wire [23:0] sync_timeout = clk_freq[31:6];    // ~3ms at 200MHz

    //-------------------------------------------------------------------------
    // Probe State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            timeout_counter <= 24'd0;
            current_rate <= 2'b00;
            probe_complete <= 1'b0;
            probe_success <= 1'b0;
            override_data_rate <= 2'b10;  // 500K default
            override_enable <= 1'b0;
            enable_read <= 1'b0;
        end else if (enable) begin
            // Clear one-shot signals
            probe_complete <= 1'b0;

            case (state)
                S_IDLE: begin
                    override_enable <= 1'b0;
                    enable_read <= 1'b0;

                    if (probe_start) begin
                        current_rate <= probe_rate;
                        state <= S_SET_RATE;
                        timeout_counter <= 24'd0;
                    end
                end

                S_SET_RATE: begin
                    // Apply the data rate override
                    override_data_rate <= current_rate;
                    override_enable <= 1'b1;
                    enable_read <= 1'b1;
                    timeout_counter <= 24'd0;
                    state <= S_WAIT_LOCK;
                end

                S_WAIT_LOCK: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (pll_locked) begin
                        // PLL locked, wait for sync
                        timeout_counter <= 24'd0;
                        state <= S_WAIT_SYNC;
                    end else if (timeout_counter >= lock_timeout) begin
                        // Failed to lock
                        state <= S_FAIL;
                    end
                end

                S_WAIT_SYNC: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (sync_detected) begin
                        // Found sync - success!
                        state <= S_SUCCESS;
                    end else if (!pll_locked) begin
                        // Lost lock
                        state <= S_FAIL;
                    end else if (timeout_counter >= sync_timeout) begin
                        // Timeout waiting for sync
                        state <= S_FAIL;
                    end
                end

                S_SUCCESS: begin
                    probe_success <= 1'b1;
                    probe_complete <= 1'b1;
                    state <= S_DONE;
                end

                S_FAIL: begin
                    probe_success <= 1'b0;
                    probe_complete <= 1'b1;
                    state <= S_DONE;
                end

                S_DONE: begin
                    override_enable <= 1'b0;
                    enable_read <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end else begin
            // Disabled
            state <= S_IDLE;
            override_enable <= 1'b0;
            enable_read <= 1'b0;
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Density Capability Analyzer
// Performs full density sweep and reports maximum supported rate
//-----------------------------------------------------------------------------
module density_capability_analyzer (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Start/control
    input  wire        start_analysis,      // Begin density analysis
    input  wire        abort,               // Cancel analysis
    output reg         analysis_complete,   // Analysis finished
    output reg         analysis_busy,       // Analysis in progress

    // Results
    output reg  [1:0]  max_data_rate,       // Highest successful rate
    output reg         can_250k,            // 250K works
    output reg         can_300k,            // 300K works
    output reg         can_500k,            // 500K works
    output reg         can_1m,              // 1M works
    output reg  [1:0]  density_capability,  // 00=DD, 01=HD, 10=ED, 11=unk

    // Probe interface
    output reg         probe_start,
    output reg  [1:0]  probe_rate,
    input  wire        probe_complete,
    input  wire        probe_success
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam S_IDLE       = 3'd0;
    localparam S_TEST_500K  = 3'd1;
    localparam S_TEST_1M    = 3'd2;
    localparam S_TEST_250K  = 3'd3;
    localparam S_TEST_300K  = 3'd4;
    localparam S_ANALYZE    = 3'd5;
    localparam S_DONE       = 3'd6;

    reg [2:0] state;

    // Density constants
    localparam DENS_DD  = 2'b00;
    localparam DENS_HD  = 2'b01;
    localparam DENS_ED  = 2'b10;
    localparam DENS_UNK = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            analysis_complete <= 1'b0;
            analysis_busy <= 1'b0;
            max_data_rate <= 2'b00;
            can_250k <= 1'b0;
            can_300k <= 1'b0;
            can_500k <= 1'b0;
            can_1m <= 1'b0;
            density_capability <= DENS_UNK;
            probe_start <= 1'b0;
            probe_rate <= 2'b00;
        end else if (enable) begin
            // Clear one-shot signals
            probe_start <= 1'b0;
            analysis_complete <= 1'b0;

            case (state)
                S_IDLE: begin
                    analysis_busy <= 1'b0;

                    if (start_analysis) begin
                        analysis_busy <= 1'b1;
                        can_250k <= 1'b0;
                        can_300k <= 1'b0;
                        can_500k <= 1'b0;
                        can_1m <= 1'b0;
                        // Start with 500K (most common HD rate)
                        probe_start <= 1'b1;
                        probe_rate <= 2'b10;  // 500K
                        state <= S_TEST_500K;
                    end
                end

                S_TEST_500K: begin
                    if (abort) begin
                        state <= S_ANALYZE;
                    end else if (probe_complete) begin
                        can_500k <= probe_success;
                        if (probe_success) begin
                            // Try 1M next
                            probe_start <= 1'b1;
                            probe_rate <= 2'b11;  // 1M
                            state <= S_TEST_1M;
                        end else begin
                            // Try 250K
                            probe_start <= 1'b1;
                            probe_rate <= 2'b00;  // 250K
                            state <= S_TEST_250K;
                        end
                    end
                end

                S_TEST_1M: begin
                    if (abort) begin
                        state <= S_ANALYZE;
                    end else if (probe_complete) begin
                        can_1m <= probe_success;
                        // Done with HD+ testing
                        state <= S_ANALYZE;
                    end
                end

                S_TEST_250K: begin
                    if (abort) begin
                        state <= S_ANALYZE;
                    end else if (probe_complete) begin
                        can_250k <= probe_success;
                        // Try 300K
                        probe_start <= 1'b1;
                        probe_rate <= 2'b01;  // 300K
                        state <= S_TEST_300K;
                    end
                end

                S_TEST_300K: begin
                    if (abort) begin
                        state <= S_ANALYZE;
                    end else if (probe_complete) begin
                        can_300k <= probe_success;
                        state <= S_ANALYZE;
                    end
                end

                S_ANALYZE: begin
                    // Determine density capability
                    if (can_1m) begin
                        density_capability <= DENS_ED;
                        max_data_rate <= 2'b11;
                    end else if (can_500k) begin
                        density_capability <= DENS_HD;
                        max_data_rate <= 2'b10;
                    end else if (can_300k) begin
                        density_capability <= DENS_DD;
                        max_data_rate <= 2'b01;
                    end else if (can_250k) begin
                        density_capability <= DENS_DD;
                        max_data_rate <= 2'b00;
                    end else begin
                        density_capability <= DENS_UNK;
                        max_data_rate <= 2'b00;
                    end

                    state <= S_DONE;
                end

                S_DONE: begin
                    analysis_complete <= 1'b1;
                    analysis_busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end else begin
            state <= S_IDLE;
            analysis_busy <= 1'b0;
            probe_start <= 1'b0;
        end
    end

endmodule
