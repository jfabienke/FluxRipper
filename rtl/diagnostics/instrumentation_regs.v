//-----------------------------------------------------------------------------
// instrumentation_regs.v
// FluxRipper Instrumentation and Performance Counter Registers
//
// Created: 2025-12-05 17:35
//
// Hardware performance counters and instrumentation probes for:
//   - USB transfer statistics
//   - DMA statistics
//   - FIFO monitoring
//   - Timing measurements
//   - Signal quality metrics
//   - Error tracking
//
// Register Map (base + offset):
//   0x000-0x03F: System info and control
//   0x040-0x07F: USB statistics
//   0x080-0x0BF: DMA statistics
//   0x0C0-0x0FF: FIFO statistics
//   0x100-0x13F: Timing measurements
//   0x140-0x17F: Signal quality
//   0x180-0x1BF: PLL/clock stats
//   0x1C0-0x1FF: Error counters
//   0x200-0x2FF: Histogram data
//   0x300-0x3FF: Trace buffer control
//-----------------------------------------------------------------------------

module instrumentation_regs #(
    parameter BASE_ADDR        = 32'h8000_0000,
    parameter HISTOGRAM_BINS   = 64,
    parameter TRACE_DEPTH      = 256
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // Register Bus Interface
    //=========================================================================

    input  wire [31:0] reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_we,
    input  wire        reg_re,
    output reg  [31:0] reg_rdata,
    output reg         reg_ready,

    //=========================================================================
    // USB Instrumentation Inputs
    //=========================================================================

    input  wire        usb_rx_valid,
    input  wire        usb_rx_ready,
    input  wire [31:0] usb_rx_data,
    input  wire        usb_tx_valid,
    input  wire        usb_tx_ready,
    input  wire        usb_error,

    //=========================================================================
    // DMA Instrumentation Inputs
    //=========================================================================

    input  wire        dma_active,
    input  wire        dma_done,
    input  wire        dma_error,
    input  wire [15:0] dma_length,

    //=========================================================================
    // FIFO Instrumentation Inputs
    //=========================================================================

    input  wire [9:0]  rx_fifo_level,
    input  wire [9:0]  tx_fifo_level,
    input  wire [12:0] flux_fifo_level,
    input  wire [9:0]  sector_fifo_level,
    input  wire        rx_fifo_overflow,
    input  wire        tx_fifo_underrun,
    input  wire        flux_fifo_overflow,

    //=========================================================================
    // Signal Quality Inputs
    //=========================================================================

    input  wire [15:0] signal_amplitude,
    input  wire        signal_valid,
    input  wire [26:0] flux_timestamp,
    input  wire        flux_valid,
    input  wire        flux_index,
    input  wire        flux_weak,

    //=========================================================================
    // PLL/Clock Inputs
    //=========================================================================

    input  wire        pll_locked,
    input  wire [31:0] index_period,
    input  wire        index_pulse,

    //=========================================================================
    // Error Inputs
    //=========================================================================

    input  wire        fdd_error,
    input  wire        hdd_error,
    input  wire        crc_error,
    input  wire        timeout_error,

    //=========================================================================
    // Timing Measurement Inputs
    //=========================================================================

    input  wire        cmd_start,
    input  wire        cmd_done,

    //=========================================================================
    // Control Outputs
    //=========================================================================

    output reg         counters_reset,
    output reg         histogram_reset,
    output reg  [31:0] trace_mask,
    output reg         trace_enable,
    output reg         trigger_arm,
    output wire        trigger_fired
);

    //=========================================================================
    // Local Parameters - Register Offsets
    //=========================================================================

    localparam REG_VERSION          = 12'h000;
    localparam REG_CONTROL          = 12'h004;
    localparam REG_STATUS           = 12'h008;
    localparam REG_UPTIME_SEC       = 12'h00C;
    localparam REG_UPTIME_MS        = 12'h010;

    localparam REG_USB_RX_BYTES_LO  = 12'h040;
    localparam REG_USB_RX_BYTES_HI  = 12'h044;
    localparam REG_USB_TX_BYTES_LO  = 12'h048;
    localparam REG_USB_TX_BYTES_HI  = 12'h04C;
    localparam REG_USB_RX_PACKETS   = 12'h050;
    localparam REG_USB_TX_PACKETS   = 12'h054;
    localparam REG_USB_ERRORS       = 12'h058;

    localparam REG_DMA_BYTES_LO     = 12'h080;
    localparam REG_DMA_BYTES_HI     = 12'h084;
    localparam REG_DMA_TRANSFERS    = 12'h088;
    localparam REG_DMA_ERRORS       = 12'h08C;

    localparam REG_FIFO_RX_HWM      = 12'h0C0;
    localparam REG_FIFO_TX_HWM      = 12'h0C4;
    localparam REG_FIFO_FLUX_HWM    = 12'h0C8;
    localparam REG_FIFO_SECTOR_HWM  = 12'h0CC;
    localparam REG_FIFO_OVERFLOWS   = 12'h0D0;

    localparam REG_LATENCY_MIN      = 12'h100;
    localparam REG_LATENCY_MAX      = 12'h104;
    localparam REG_LATENCY_AVG      = 12'h108;
    localparam REG_LATENCY_LAST     = 12'h10C;

    localparam REG_SIG_AMP_MIN      = 12'h140;
    localparam REG_SIG_AMP_MAX      = 12'h144;
    localparam REG_SIG_AMP_AVG      = 12'h148;
    localparam REG_FLUX_COUNT       = 12'h14C;
    localparam REG_INDEX_COUNT      = 12'h150;
    localparam REG_WEAK_COUNT       = 12'h154;

    localparam REG_PLL_STATUS       = 12'h180;
    localparam REG_PLL_LOCK_COUNT   = 12'h184;
    localparam REG_INDEX_PERIOD     = 12'h188;
    localparam REG_INDEX_MIN        = 12'h18C;
    localparam REG_INDEX_MAX        = 12'h190;
    localparam REG_RPM_MEASURED     = 12'h194;

    localparam REG_ERR_FDD          = 12'h1C0;
    localparam REG_ERR_HDD          = 12'h1C4;
    localparam REG_ERR_CRC          = 12'h1C8;
    localparam REG_ERR_TIMEOUT      = 12'h1CC;
    localparam REG_ERR_TOTAL        = 12'h1D0;

    localparam REG_HIST_CTRL        = 12'h200;
    localparam REG_HIST_BIN_BASE    = 12'h204;

    localparam REG_TRACE_CTRL       = 12'h300;
    localparam REG_TRACE_MASK       = 12'h304;
    localparam REG_TRACE_STATUS     = 12'h308;
    localparam REG_TRACE_HEAD       = 12'h30C;
    localparam REG_TRACE_DATA       = 12'h310;

    //=========================================================================
    // Performance Counters
    //=========================================================================

    // USB statistics
    reg [63:0] usb_rx_bytes;
    reg [63:0] usb_tx_bytes;
    reg [31:0] usb_rx_packets;
    reg [31:0] usb_tx_packets;
    reg [31:0] usb_error_count;

    // DMA statistics
    reg [63:0] dma_bytes_total;
    reg [31:0] dma_transfer_count;
    reg [31:0] dma_error_count;

    // FIFO high-water marks
    reg [9:0]  fifo_rx_hwm;
    reg [9:0]  fifo_tx_hwm;
    reg [12:0] fifo_flux_hwm;
    reg [9:0]  fifo_sector_hwm;
    reg [31:0] fifo_overflow_count;

    // Latency measurement
    reg [31:0] latency_min;
    reg [31:0] latency_max;
    reg [63:0] latency_sum;
    reg [31:0] latency_count;
    reg [31:0] latency_last;
    reg [31:0] latency_timer;
    reg        cmd_active;

    // Signal statistics
    reg [15:0] sig_amp_min;
    reg [15:0] sig_amp_max;
    reg [31:0] sig_amp_sum;
    reg [31:0] sig_amp_count;
    reg [31:0] flux_transition_count;
    reg [31:0] flux_index_count;
    reg [31:0] flux_weak_count;

    // PLL/clock statistics
    reg [31:0] pll_lock_count;
    reg        pll_locked_prev;
    reg [31:0] index_period_reg;
    reg [31:0] index_period_min;
    reg [31:0] index_period_max;
    reg [15:0] rpm_measured;

    // Error counters
    reg [31:0] err_fdd_count;
    reg [31:0] err_hdd_count;
    reg [31:0] err_crc_count;
    reg [31:0] err_timeout_count;

    // System
    reg [31:0] uptime_seconds;
    reg [19:0] uptime_ms_counter;   // Counts up to 1M (1 second @ 1MHz tick)
    reg [9:0]  uptime_ms;

    //=========================================================================
    // Flux Timing Histogram
    //=========================================================================

    reg [31:0] flux_histogram [0:HISTOGRAM_BINS-1];
    reg [31:0] hist_bin_min;
    reg [31:0] hist_bin_width;
    reg [7:0]  hist_read_idx;

    //=========================================================================
    // Trace Buffer
    //=========================================================================

    reg [63:0] trace_buffer [0:TRACE_DEPTH-1];
    reg [$clog2(TRACE_DEPTH)-1:0] trace_head_ptr;
    reg [$clog2(TRACE_DEPTH)-1:0] trace_read_ptr;
    reg [31:0] trace_count;
    reg        trigger_active;
    reg        trigger_detected;

    assign trigger_fired = trigger_detected;

    //=========================================================================
    // Uptime Counter
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uptime_seconds <= 32'h0;
            uptime_ms_counter <= 20'h0;
            uptime_ms <= 10'h0;
        end else begin
            // Assuming 100MHz clock, count every 100,000 cycles = 1ms
            if (uptime_ms_counter >= 20'd99999) begin
                uptime_ms_counter <= 20'h0;
                if (uptime_ms >= 10'd999) begin
                    uptime_ms <= 10'h0;
                    uptime_seconds <= uptime_seconds + 1'b1;
                end else begin
                    uptime_ms <= uptime_ms + 1'b1;
                end
            end else begin
                uptime_ms_counter <= uptime_ms_counter + 1'b1;
            end
        end
    end

    //=========================================================================
    // USB Statistics
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            usb_rx_bytes <= 64'h0;
            usb_tx_bytes <= 64'h0;
            usb_rx_packets <= 32'h0;
            usb_tx_packets <= 32'h0;
            usb_error_count <= 32'h0;
        end else begin
            if (usb_rx_valid && usb_rx_ready) begin
                usb_rx_bytes <= usb_rx_bytes + 4;  // 32-bit words
                usb_rx_packets <= usb_rx_packets + 1'b1;
            end
            if (usb_tx_valid && usb_tx_ready) begin
                usb_tx_bytes <= usb_tx_bytes + 4;
                usb_tx_packets <= usb_tx_packets + 1'b1;
            end
            if (usb_error) begin
                usb_error_count <= usb_error_count + 1'b1;
            end
        end
    end

    //=========================================================================
    // DMA Statistics
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            dma_bytes_total <= 64'h0;
            dma_transfer_count <= 32'h0;
            dma_error_count <= 32'h0;
        end else begin
            if (dma_done) begin
                dma_bytes_total <= dma_bytes_total + {16'h0, dma_length};
                dma_transfer_count <= dma_transfer_count + 1'b1;
            end
            if (dma_error) begin
                dma_error_count <= dma_error_count + 1'b1;
            end
        end
    end

    //=========================================================================
    // FIFO High-Water Marks
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            fifo_rx_hwm <= 10'h0;
            fifo_tx_hwm <= 10'h0;
            fifo_flux_hwm <= 13'h0;
            fifo_sector_hwm <= 10'h0;
            fifo_overflow_count <= 32'h0;
        end else begin
            if (rx_fifo_level > fifo_rx_hwm) fifo_rx_hwm <= rx_fifo_level;
            if (tx_fifo_level > fifo_tx_hwm) fifo_tx_hwm <= tx_fifo_level;
            if (flux_fifo_level > fifo_flux_hwm) fifo_flux_hwm <= flux_fifo_level;
            if (sector_fifo_level > fifo_sector_hwm) fifo_sector_hwm <= sector_fifo_level;

            if (rx_fifo_overflow || tx_fifo_underrun || flux_fifo_overflow) begin
                fifo_overflow_count <= fifo_overflow_count + 1'b1;
            end
        end
    end

    //=========================================================================
    // Latency Measurement
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            latency_min <= 32'hFFFFFFFF;
            latency_max <= 32'h0;
            latency_sum <= 64'h0;
            latency_count <= 32'h0;
            latency_last <= 32'h0;
            latency_timer <= 32'h0;
            cmd_active <= 1'b0;
        end else begin
            if (cmd_start && !cmd_active) begin
                cmd_active <= 1'b1;
                latency_timer <= 32'h0;
            end else if (cmd_active) begin
                latency_timer <= latency_timer + 1'b1;

                if (cmd_done) begin
                    cmd_active <= 1'b0;
                    latency_last <= latency_timer;
                    latency_sum <= latency_sum + latency_timer;
                    latency_count <= latency_count + 1'b1;

                    if (latency_timer < latency_min) begin
                        latency_min <= latency_timer;
                    end
                    if (latency_timer > latency_max) begin
                        latency_max <= latency_timer;
                    end
                end
            end
        end
    end

    //=========================================================================
    // Signal Statistics
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            sig_amp_min <= 16'hFFFF;
            sig_amp_max <= 16'h0;
            sig_amp_sum <= 32'h0;
            sig_amp_count <= 32'h0;
            flux_transition_count <= 32'h0;
            flux_index_count <= 32'h0;
            flux_weak_count <= 32'h0;
        end else begin
            if (signal_valid) begin
                if (signal_amplitude < sig_amp_min) sig_amp_min <= signal_amplitude;
                if (signal_amplitude > sig_amp_max) sig_amp_max <= signal_amplitude;
                sig_amp_sum <= sig_amp_sum + signal_amplitude;
                sig_amp_count <= sig_amp_count + 1'b1;
            end

            if (flux_valid) begin
                flux_transition_count <= flux_transition_count + 1'b1;
                if (flux_index) flux_index_count <= flux_index_count + 1'b1;
                if (flux_weak) flux_weak_count <= flux_weak_count + 1'b1;
            end
        end
    end

    //=========================================================================
    // PLL/Clock Statistics
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            pll_lock_count <= 32'h0;
            pll_locked_prev <= 1'b0;
            index_period_reg <= 32'h0;
            index_period_min <= 32'hFFFFFFFF;
            index_period_max <= 32'h0;
            rpm_measured <= 16'h0;
        end else begin
            pll_locked_prev <= pll_locked;

            if (pll_locked && !pll_locked_prev) begin
                pll_lock_count <= pll_lock_count + 1'b1;
            end

            if (index_pulse) begin
                index_period_reg <= index_period;
                if (index_period < index_period_min && index_period > 0) begin
                    index_period_min <= index_period;
                end
                if (index_period > index_period_max) begin
                    index_period_max <= index_period;
                end

                // Calculate RPM: 60 * 10^9 / period_ns
                // Simplified: RPM = 60000000000 / period
                // At 300 RPM, period = 200,000,000 ns
                if (index_period > 0) begin
                    // Approximate: RPM ≈ 60M / (period / 1000) = 60B / period
                    rpm_measured <= 16'd60000 / (index_period[31:10] + 1);
                end
            end
        end
    end

    //=========================================================================
    // Error Counters
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || counters_reset) begin
            err_fdd_count <= 32'h0;
            err_hdd_count <= 32'h0;
            err_crc_count <= 32'h0;
            err_timeout_count <= 32'h0;
        end else begin
            if (fdd_error) err_fdd_count <= err_fdd_count + 1'b1;
            if (hdd_error) err_hdd_count <= err_hdd_count + 1'b1;
            if (crc_error) err_crc_count <= err_crc_count + 1'b1;
            if (timeout_error) err_timeout_count <= err_timeout_count + 1'b1;
        end
    end

    //=========================================================================
    // Flux Histogram
    //=========================================================================

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || histogram_reset) begin
            for (i = 0; i < HISTOGRAM_BINS; i = i + 1) begin
                flux_histogram[i] <= 32'h0;
            end
            hist_bin_min <= 32'd1000;       // 1us minimum
            hist_bin_width <= 32'd125;       // 125ns bins
        end else if (flux_valid) begin
            // Convert timestamp to ns (assuming 5ns resolution)
            reg [31:0] timing_ns;
            reg [7:0] bin_idx;

            timing_ns = {5'h0, flux_timestamp} * 5;

            if (timing_ns >= hist_bin_min) begin
                bin_idx = (timing_ns - hist_bin_min) / hist_bin_width;
                if (bin_idx < HISTOGRAM_BINS) begin
                    flux_histogram[bin_idx] <= flux_histogram[bin_idx] + 1'b1;
                end
            end
        end
    end

    //=========================================================================
    // Trace Buffer
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trace_head_ptr <= 0;
            trace_count <= 32'h0;
            trigger_active <= 1'b0;
            trigger_detected <= 1'b0;
        end else begin
            if (!trace_enable) begin
                trace_head_ptr <= 0;
                trace_count <= 32'h0;
                trigger_detected <= 1'b0;
            end else if (trace_enable) begin
                // Record trace events based on mask
                // Simplified: just record USB and flux events
                if ((trace_mask[0] && usb_rx_valid) ||
                    (trace_mask[1] && usb_tx_valid) ||
                    (trace_mask[8] && flux_valid)) begin

                    trace_buffer[trace_head_ptr] <= {uptime_seconds, uptime_ms, 22'h0};
                    trace_head_ptr <= trace_head_ptr + 1'b1;
                    if (trace_count < TRACE_DEPTH) begin
                        trace_count <= trace_count + 1'b1;
                    end
                end

                // Check trigger
                if (trigger_arm && !trigger_detected) begin
                    trigger_active <= 1'b1;
                    // Trigger on any error
                    if (usb_error || fdd_error || hdd_error) begin
                        trigger_detected <= 1'b1;
                    end
                end
            end
        end
    end

    //=========================================================================
    // Register Read/Write
    //=========================================================================

    wire [11:0] reg_offset = reg_addr[11:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rdata <= 32'h0;
            reg_ready <= 1'b0;
            counters_reset <= 1'b0;
            histogram_reset <= 1'b0;
            trace_mask <= 32'h0;
            trace_enable <= 1'b0;
            trigger_arm <= 1'b0;
            hist_read_idx <= 8'h0;
            trace_read_ptr <= 0;
        end else begin
            reg_ready <= 1'b0;
            counters_reset <= 1'b0;
            histogram_reset <= 1'b0;

            if (reg_re || reg_we) begin
                reg_ready <= 1'b1;

                // Handle writes
                if (reg_we) begin
                    case (reg_offset)
                        REG_CONTROL: begin
                            counters_reset <= reg_wdata[0];
                            histogram_reset <= reg_wdata[1];
                        end
                        REG_TRACE_CTRL: begin
                            trace_enable <= reg_wdata[0];
                            trigger_arm <= reg_wdata[1];
                        end
                        REG_TRACE_MASK: begin
                            trace_mask <= reg_wdata;
                        end
                        REG_HIST_CTRL: begin
                            hist_read_idx <= reg_wdata[7:0];
                        end
                    endcase
                end

                // Handle reads
                if (reg_re) begin
                    case (reg_offset)
                        REG_VERSION:        reg_rdata <= 32'h00010000;  // v1.0.0
                        REG_CONTROL:        reg_rdata <= 32'h0;
                        REG_STATUS:         reg_rdata <= {30'h0, trigger_detected, trace_enable};
                        REG_UPTIME_SEC:     reg_rdata <= uptime_seconds;
                        REG_UPTIME_MS:      reg_rdata <= {22'h0, uptime_ms};

                        REG_USB_RX_BYTES_LO: reg_rdata <= usb_rx_bytes[31:0];
                        REG_USB_RX_BYTES_HI: reg_rdata <= usb_rx_bytes[63:32];
                        REG_USB_TX_BYTES_LO: reg_rdata <= usb_tx_bytes[31:0];
                        REG_USB_TX_BYTES_HI: reg_rdata <= usb_tx_bytes[63:32];
                        REG_USB_RX_PACKETS:  reg_rdata <= usb_rx_packets;
                        REG_USB_TX_PACKETS:  reg_rdata <= usb_tx_packets;
                        REG_USB_ERRORS:      reg_rdata <= usb_error_count;

                        REG_DMA_BYTES_LO:    reg_rdata <= dma_bytes_total[31:0];
                        REG_DMA_BYTES_HI:    reg_rdata <= dma_bytes_total[63:32];
                        REG_DMA_TRANSFERS:   reg_rdata <= dma_transfer_count;
                        REG_DMA_ERRORS:      reg_rdata <= dma_error_count;

                        REG_FIFO_RX_HWM:     reg_rdata <= {22'h0, fifo_rx_hwm};
                        REG_FIFO_TX_HWM:     reg_rdata <= {22'h0, fifo_tx_hwm};
                        REG_FIFO_FLUX_HWM:   reg_rdata <= {19'h0, fifo_flux_hwm};
                        REG_FIFO_SECTOR_HWM: reg_rdata <= {22'h0, fifo_sector_hwm};
                        REG_FIFO_OVERFLOWS:  reg_rdata <= fifo_overflow_count;

                        REG_LATENCY_MIN:     reg_rdata <= latency_min;
                        REG_LATENCY_MAX:     reg_rdata <= latency_max;
                        REG_LATENCY_AVG:     reg_rdata <= (latency_count > 0) ?
                                                          latency_sum[31:0] / latency_count : 32'h0;
                        REG_LATENCY_LAST:    reg_rdata <= latency_last;

                        REG_SIG_AMP_MIN:     reg_rdata <= {16'h0, sig_amp_min};
                        REG_SIG_AMP_MAX:     reg_rdata <= {16'h0, sig_amp_max};
                        REG_SIG_AMP_AVG:     reg_rdata <= (sig_amp_count > 0) ?
                                                          sig_amp_sum / sig_amp_count : 32'h0;
                        REG_FLUX_COUNT:      reg_rdata <= flux_transition_count;
                        REG_INDEX_COUNT:     reg_rdata <= flux_index_count;
                        REG_WEAK_COUNT:      reg_rdata <= flux_weak_count;

                        REG_PLL_STATUS:      reg_rdata <= {30'h0, pll_locked_prev, pll_locked};
                        REG_PLL_LOCK_COUNT:  reg_rdata <= pll_lock_count;
                        REG_INDEX_PERIOD:    reg_rdata <= index_period_reg;
                        REG_INDEX_MIN:       reg_rdata <= index_period_min;
                        REG_INDEX_MAX:       reg_rdata <= index_period_max;
                        REG_RPM_MEASURED:    reg_rdata <= {16'h0, rpm_measured};

                        REG_ERR_FDD:         reg_rdata <= err_fdd_count;
                        REG_ERR_HDD:         reg_rdata <= err_hdd_count;
                        REG_ERR_CRC:         reg_rdata <= err_crc_count;
                        REG_ERR_TIMEOUT:     reg_rdata <= err_timeout_count;
                        REG_ERR_TOTAL:       reg_rdata <= err_fdd_count + err_hdd_count +
                                                          err_crc_count + err_timeout_count;

                        REG_HIST_CTRL:       reg_rdata <= {24'h0, hist_read_idx};
                        REG_HIST_BIN_BASE:   reg_rdata <= flux_histogram[hist_read_idx];

                        REG_TRACE_CTRL:      reg_rdata <= {30'h0, trigger_arm, trace_enable};
                        REG_TRACE_MASK:      reg_rdata <= trace_mask;
                        REG_TRACE_STATUS:    reg_rdata <= {30'h0, trigger_detected, trigger_active};
                        REG_TRACE_HEAD:      reg_rdata <= trace_count;
                        REG_TRACE_DATA:      begin
                            reg_rdata <= trace_buffer[trace_read_ptr][31:0];
                            trace_read_ptr <= trace_read_ptr + 1'b1;
                        end

                        default:             reg_rdata <= 32'hDEADBEEF;
                    endcase
                end
            end
        end
    end

endmodule
