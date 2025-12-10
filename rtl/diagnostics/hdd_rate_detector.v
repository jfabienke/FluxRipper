//-----------------------------------------------------------------------------
// HDD Rate Detector - Data Rate Auto-Detection
//
// Analyzes flux transitions to determine the drive's data rate:
//   - 5 Mbps (MFM ST-506)
//   - 7.5 Mbps (RLL ST-506)
//   - 10 Mbps (ESDI)
//   - 15 Mbps (High-speed ESDI)
//
// Method: Build histogram of pulse widths, find peaks, match to expected rates
//
// Created: 2025-12-03 22:00
//-----------------------------------------------------------------------------

module hdd_rate_detector (
    input  wire        clk,              // 300 MHz HDD clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        detect_start,     // Start detection
    output reg         detect_done,      // Detection complete
    output reg         detect_busy,      // Detection in progress

    //-------------------------------------------------------------------------
    // Data Input
    //-------------------------------------------------------------------------
    input  wire        flux_edge,        // Edge detected from DPLL/raw
    input  wire        flux_valid,       // Edge is valid
    input  wire        index_pulse,      // Index for rotation reference

    //-------------------------------------------------------------------------
    // Detection Results
    //-------------------------------------------------------------------------
    output reg  [2:0]  detected_rate,    // 0=unknown, 1=5M, 2=7.5M, 3=10M, 4=15M
    output reg  [7:0]  rate_confidence,  // 0-255 confidence score
    output reg  [15:0] avg_pulse_width,  // Average pulse width (clocks)
    output reg  [15:0] peak_pulse_width, // Most common pulse width
    output reg         rate_valid        // Detection succeeded
);

    //-------------------------------------------------------------------------
    // Expected Pulse Widths at 300 MHz clock
    //-------------------------------------------------------------------------
    // Bit cell = 1/data_rate, pulse width = bit_cell * clocks_per_second
    //
    // 5 Mbps:   bit cell = 200ns,  min pulse (2T) = 400ns  = 160 clocks
    //           max pulse (MFM) = 800ns = 320 clocks
    // 7.5 Mbps: bit cell = 133ns,  min pulse (2T) = 266ns  = 106 clocks
    //           RLL(2,7): 2T-7T gives 106-373 clocks
    // 10 Mbps:  bit cell = 100ns,  min pulse = 200ns = 80 clocks
    // 15 Mbps:  bit cell = 67ns,   min pulse = 133ns = 53 clocks

    localparam [15:0] PW_5M_MIN       = 16'd105;   // 5 Mbps minimum (with tolerance)
    localparam [15:0] PW_5M_MAX       = 16'd270;   // 5 Mbps maximum
    localparam [15:0] PW_5M_PEAK      = 16'd120;   // 5 Mbps typical peak (2T)

    localparam [15:0] PW_7_5M_MIN     = 16'd68;    // 7.5 Mbps minimum
    localparam [15:0] PW_7_5M_MAX     = 16'd300;   // 7.5 Mbps maximum (RLL 7T)
    localparam [15:0] PW_7_5M_PEAK    = 16'd80;   // 7.5 Mbps typical peak

    localparam [15:0] PW_10M_MIN      = 16'd49;    // 10 Mbps minimum
    localparam [15:0] PW_10M_MAX      = 16'd210;   // 10 Mbps maximum
    localparam [15:0] PW_10M_PEAK     = 16'd60;    // 10 Mbps typical peak

    localparam [15:0] PW_15M_MIN      = 16'd30;    // 15 Mbps minimum
    localparam [15:0] PW_15M_MAX      = 16'd143;   // 15 Mbps maximum
    localparam [15:0] PW_15M_PEAK     = 16'd40;    // 15 Mbps typical peak

    // Rate codes
    localparam [2:0] RATE_UNKNOWN = 3'd0;
    localparam [2:0] RATE_5M      = 3'd1;
    localparam [2:0] RATE_7_5M    = 3'd2;
    localparam [2:0] RATE_10M     = 3'd3;
    localparam [2:0] RATE_15M     = 3'd4;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE       = 3'd0,
        STATE_WAIT_INDEX = 3'd1,
        STATE_COLLECT    = 3'd2,
        STATE_HISTOGRAM  = 3'd3,
        STATE_ANALYZE    = 3'd4,
        STATE_DONE       = 3'd5;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Sample Collection
    //-------------------------------------------------------------------------
    localparam [23:0] COLLECT_WINDOW    = 24'd3_000_000;  // 10ms @ 300 MHz
    localparam [15:0] MAX_SAMPLES = 16'd16384;

    reg [23:0] collect_counter;
    reg [15:0] sample_count;
    reg [15:0] pulse_width_counter;

    // Accumulator for average calculation
    reg [31:0] pulse_width_sum;

    //-------------------------------------------------------------------------
    // Histogram Bins (simplified - 8 bins covering expected ranges)
    //-------------------------------------------------------------------------
    // Bin 0: 0-50 clocks (noise/invalid)
    // Bin 1: 50-80 clocks (15 Mbps range)
    // Bin 2: 80-120 clocks (10 Mbps range)
    // Bin 3: 120-160 clocks (7.5 Mbps range)
    // Bin 4: 160-200 clocks (5 Mbps range)
    // Bin 5: 200-280 clocks (extended MFM)
    // Bin 6: 280-400 clocks (RLL extended)
    // Bin 7: 400+ clocks (sync gaps)

    reg [15:0] histogram [0:7];
    reg [2:0]  current_bin;

    // Find which bin a pulse width belongs to
    function [2:0] get_bin;
        input [15:0] width;
        begin
            if (width < 16'd50)       get_bin = 3'd0;
            else if (width < 16'd80)  get_bin = 3'd1;
            else if (width < 16'd120) get_bin = 3'd2;
            else if (width < 16'd160) get_bin = 3'd3;
            else if (width < 16'd200) get_bin = 3'd4;
            else if (width < 16'd280) get_bin = 3'd5;
            else if (width < 16'd400) get_bin = 3'd6;
            else                      get_bin = 3'd7;
        end
    endfunction

    //-------------------------------------------------------------------------
    // Analysis Registers
    //-------------------------------------------------------------------------
    reg [2:0]  peak_bin;
    reg [15:0] peak_count;
    reg [2:0]  analyze_idx;

    // Score accumulators for each rate
    reg [15:0] score_5m;
    reg [15:0] score_7_5m;
    reg [15:0] score_10m;
    reg [15:0] score_15m;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            detect_done <= 1'b0;
            detect_busy <= 1'b0;
            detected_rate <= RATE_UNKNOWN;
            rate_confidence <= 8'd0;
            avg_pulse_width <= 16'd0;
            peak_pulse_width <= 16'd0;
            rate_valid <= 1'b0;
            collect_counter <= 24'd0;
            sample_count <= 16'd0;
            pulse_width_counter <= 16'd0;
            pulse_width_sum <= 32'd0;
            for (i = 0; i < 8; i = i + 1)
                histogram[i] <= 16'd0;
            peak_bin <= 3'd0;
            peak_count <= 16'd0;
            analyze_idx <= 3'd0;
        end else begin
            detect_done <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    detect_busy <= 1'b0;
                    if (detect_start) begin
                        detect_busy <= 1'b1;
                        collect_counter <= 24'd0;
                        sample_count <= 16'd0;
                        pulse_width_counter <= 16'd0;
                        pulse_width_sum <= 32'd0;
                        for (i = 0; i < 8; i = i + 1)
                            histogram[i] <= 16'd0;
                        peak_bin <= 3'd0;
                        peak_count <= 16'd0;
                        rate_valid <= 1'b0;
                        state <= STATE_WAIT_INDEX;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_INDEX: begin
                    // Wait for index pulse for synchronized measurement
                    collect_counter <= collect_counter + 1;
                    if (index_pulse) begin
                        collect_counter <= 24'd0;
                        state <= STATE_COLLECT;
                    end else if (collect_counter > COLLECT_WINDOW) begin
                        // No index - start anyway
                        collect_counter <= 24'd0;
                        state <= STATE_COLLECT;
                    end
                end

                //-------------------------------------------------------------
                STATE_COLLECT: begin
                    collect_counter <= collect_counter + 1;
                    pulse_width_counter <= pulse_width_counter + 1;

                    if (flux_valid && flux_edge) begin
                        // Record pulse width
                        if (sample_count < MAX_SAMPLES &&
                            pulse_width_counter > 16'd10) begin  // Ignore very short

                            // Add to histogram
                            current_bin <= get_bin(pulse_width_counter);

                            // Accumulate for average
                            pulse_width_sum <= pulse_width_sum + {16'd0, pulse_width_counter};
                            sample_count <= sample_count + 1;
                        end

                        pulse_width_counter <= 16'd0;
                    end

                    // Update histogram (delayed by 1 cycle for current_bin)
                    if (sample_count > 16'd0 && pulse_width_counter == 16'd1) begin
                        if (histogram[current_bin] < 16'hFFFF)
                            histogram[current_bin] <= histogram[current_bin] + 1;
                    end

                    if (collect_counter >= COLLECT_WINDOW ||
                        sample_count >= MAX_SAMPLES) begin
                        analyze_idx <= 3'd0;
                        state <= STATE_HISTOGRAM;
                    end
                end

                //-------------------------------------------------------------
                STATE_HISTOGRAM: begin
                    // Find peak bin
                    if (histogram[analyze_idx] > peak_count) begin
                        peak_count <= histogram[analyze_idx];
                        peak_bin <= analyze_idx;
                    end

                    if (analyze_idx == 3'd7) begin
                        state <= STATE_ANALYZE;
                    end else begin
                        analyze_idx <= analyze_idx + 1;
                    end
                end

                //-------------------------------------------------------------
                STATE_ANALYZE: begin
                    // Calculate average pulse width
                    if (sample_count > 0) begin
                        avg_pulse_width <= pulse_width_sum[31:16] / sample_count[15:0];
                    end

                    // Assign peak pulse width based on peak bin
                    case (peak_bin)
                        3'd1: peak_pulse_width <= 16'd65;   // 15 Mbps
                        3'd2: peak_pulse_width <= 16'd100;  // 10 Mbps
                        3'd3: peak_pulse_width <= 16'd140;  // 7.5 Mbps
                        3'd4: peak_pulse_width <= 16'd180;  // 5 Mbps
                        3'd5: peak_pulse_width <= 16'd240;  // Extended MFM
                        3'd6: peak_pulse_width <= 16'd340;  // RLL extended
                        default: peak_pulse_width <= 16'd0;
                    endcase

                    // Score each rate based on histogram distribution
                    // 5 Mbps: peaks in bins 4-5
                    score_5m <= histogram[4] + histogram[5];

                    // 7.5 Mbps (RLL): peaks in bins 3-6
                    score_7_5m <= histogram[3] + histogram[4] + histogram[5] + histogram[6];

                    // 10 Mbps: peaks in bins 2-4
                    score_10m <= histogram[2] + histogram[3] + histogram[4];

                    // 15 Mbps: peaks in bins 1-3
                    score_15m <= histogram[1] + histogram[2] + histogram[3];

                    // Determine best match
                    if (sample_count < 16'd100) begin
                        // Not enough samples
                        detected_rate <= RATE_UNKNOWN;
                        rate_confidence <= 8'd0;
                        rate_valid <= 1'b0;
                    end else if (peak_bin == 3'd1 && histogram[1] > histogram[2]) begin
                        // Clear 15 Mbps signature
                        detected_rate <= RATE_15M;
                        rate_confidence <= calc_confidence(score_15m, sample_count);
                        rate_valid <= 1'b1;
                    end else if (peak_bin == 3'd2 && histogram[2] > histogram[3]) begin
                        // Clear 10 Mbps signature
                        detected_rate <= RATE_10M;
                        rate_confidence <= calc_confidence(score_10m, sample_count);
                        rate_valid <= 1'b1;
                    end else if ((peak_bin == 3'd3 || peak_bin == 3'd4) &&
                                 histogram[6] > (sample_count >> 4)) begin
                        // Has extended pulses - likely RLL
                        detected_rate <= RATE_7_5M;
                        rate_confidence <= calc_confidence(score_7_5m, sample_count);
                        rate_valid <= 1'b1;
                    end else if (peak_bin == 3'd4 || peak_bin == 3'd5) begin
                        // Standard 5 Mbps MFM
                        detected_rate <= RATE_5M;
                        rate_confidence <= calc_confidence(score_5m, sample_count);
                        rate_valid <= 1'b1;
                    end else begin
                        detected_rate <= RATE_UNKNOWN;
                        rate_confidence <= 8'd0;
                        rate_valid <= 1'b0;
                    end

                    state <= STATE_DONE;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    detect_done <= 1'b1;
                    detect_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Confidence Calculation
    //-------------------------------------------------------------------------
    function [7:0] calc_confidence;
        input [15:0] score;
        input [15:0] total;
        reg [23:0] ratio;
        begin
            if (total == 0) begin
                calc_confidence = 8'd0;
            end else begin
                // ratio = (score * 256) / total
                ratio = ({8'd0, score} << 8) / {8'd0, total};
                if (ratio > 24'd255)
                    calc_confidence = 8'd255;
                else
                    calc_confidence = ratio[7:0];
            end
        end
    endfunction

endmodule

//-----------------------------------------------------------------------------
// Rate to NCO Frequency Word Converter
// Converts detected rate to appropriate NCO frequency word
//-----------------------------------------------------------------------------
module hdd_rate_to_nco (
    input  wire [2:0]  detected_rate,
    output reg  [31:0] nco_freq_word,
    output reg         rate_valid
);

    // Frequency words for 300 MHz base clock
    localparam [31:0] FW_5M   = 32'h0333_3333;  // 5 Mbps
    localparam [31:0] FW_7_5M = 32'h04CC_CCCD;  // 7.5 Mbps
    localparam [31:0] FW_10M  = 32'h0666_6666;  // 10 Mbps
    localparam [31:0] FW_15M  = 32'h0999_9999;  // 15 Mbps

    always @(*) begin
        case (detected_rate)
            3'd1: begin nco_freq_word = FW_5M;   rate_valid = 1'b1; end
            3'd2: begin nco_freq_word = FW_7_5M; rate_valid = 1'b1; end
            3'd3: begin nco_freq_word = FW_10M;  rate_valid = 1'b1; end
            3'd4: begin nco_freq_word = FW_15M;  rate_valid = 1'b1; end
            default: begin nco_freq_word = FW_5M; rate_valid = 1'b0; end
        endcase
    end

endmodule
