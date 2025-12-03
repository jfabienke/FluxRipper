//-----------------------------------------------------------------------------
// AXI-Stream Flux Capture Interface
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Bridges the flux capture hardware to MicroBlaze V via AXI-Stream DMA.
// Converts flux timestamps into 32-bit AXI-Stream transactions.
//
// Data Format (32-bit per flux transition):
//   Bit 31:    Index flag (1 = this is an index pulse)
//   Bit 30:    Overflow warning
//   Bit 29:28: Reserved
//   Bit 27:0:  Timestamp (280ns resolution at 200MHz / 56)
//
// Target: AMD Spartan UltraScale+ (SCU35)
// Updated: 2025-12-03 15:30
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi_stream_flux #(
    parameter FIFO_DEPTH     = 512,     // Internal FIFO depth (power of 2)
    parameter FIFO_ADDR_BITS = 9,       // log2(FIFO_DEPTH)
    parameter CLK_DIV        = 56       // Clock divisor for timestamp (200MHz/56 = ~3.5MHz)
)(
    //-------------------------------------------------------------------------
    // Clock/Reset (AXI domain)
    //-------------------------------------------------------------------------
    input  wire        aclk,
    input  wire        aresetn,

    //-------------------------------------------------------------------------
    // Flux Engine Interface (from existing flux_capture.v)
    //-------------------------------------------------------------------------
    input  wire        flux_raw,         // Raw flux pulse from drive
    input  wire        index_pulse,      // Track boundary marker

    //-------------------------------------------------------------------------
    // AXI-Stream Master Interface (to DMA)
    //-------------------------------------------------------------------------
    output wire [31:0] m_axis_tdata,     // Flux data + flags
    output wire        m_axis_tvalid,    // Data valid
    input  wire        m_axis_tready,    // DMA ready
    output wire        m_axis_tlast,     // End of track (index)
    output wire [3:0]  m_axis_tkeep,     // Byte enables (all 1s)

    //-------------------------------------------------------------------------
    // Control Interface (directly accessible or via AXI4-Lite)
    //-------------------------------------------------------------------------
    input  wire        capture_enable,   // Start/stop capture
    input  wire        soft_reset,       // Soft reset (clears FIFO)
    input  wire [1:0]  capture_mode,     // 00=continuous, 01=one track, 10=one rev

    //-------------------------------------------------------------------------
    // Status Interface
    //-------------------------------------------------------------------------
    output reg  [31:0] capture_count,    // Flux transitions captured
    output reg  [15:0] index_count,      // Index pulses seen
    output wire        overflow,         // FIFO overflow flag
    output wire        capturing,        // Capture in progress
    output wire        fifo_empty,       // FIFO empty status
    output wire [FIFO_ADDR_BITS:0] fifo_level  // Current FIFO fill level
);

    //-------------------------------------------------------------------------
    // Capture modes (matching flux_capture.v)
    //-------------------------------------------------------------------------
    localparam MODE_CONTINUOUS = 2'b00;
    localparam MODE_ONE_TRACK  = 2'b01;
    localparam MODE_ONE_REV    = 2'b10;

    //-------------------------------------------------------------------------
    // Internal signals
    //-------------------------------------------------------------------------
    reg  [27:0] timestamp;           // 28-bit timestamp counter
    reg  [5:0]  clk_div_cnt;         // Clock divider counter
    reg         timestamp_tick;      // Timestamp increment flag

    // Flux edge detection (synchronization chain)
    reg  [2:0]  flux_sync;
    wire        flux_edge;

    // Index pulse synchronization
    reg  [2:0]  index_sync;
    wire        index_edge;

    // FIFO signals
    reg  [31:0] fifo_mem [0:FIFO_DEPTH-1];
    reg  [FIFO_ADDR_BITS-1:0] wr_ptr;
    reg  [FIFO_ADDR_BITS-1:0] rd_ptr;
    reg  [FIFO_ADDR_BITS:0]   fifo_count;
    wire        fifo_full;
    reg         fifo_wr_en;
    reg  [31:0] fifo_wr_data;
    reg  [31:0] fifo_rd_data;

    // State machine
    reg  [2:0]  state;
    localparam S_IDLE       = 3'd0;
    localparam S_ARMED      = 3'd1;
    localparam S_CAPTURING  = 3'd2;
    localparam S_INDEX_WAIT = 3'd3;
    localparam S_DONE       = 3'd4;

    // Capture state
    reg         capture_active;
    reg         overflow_flag;
    reg         index_seen;
    reg         second_index;
    reg         last_was_index;

    //-------------------------------------------------------------------------
    // Flux Edge Detection (metastability protection)
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn)
            flux_sync <= 3'b000;
        else
            flux_sync <= {flux_sync[1:0], flux_raw};
    end

    assign flux_edge = (flux_sync[2:1] == 2'b01);

    //-------------------------------------------------------------------------
    // Index Pulse Edge Detection
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn)
            index_sync <= 3'b000;
        else
            index_sync <= {index_sync[1:0], index_pulse};
    end

    assign index_edge = (index_sync[2:1] == 2'b01);

    //-------------------------------------------------------------------------
    // Timestamp Generator with Clock Division
    // Divides 200MHz clock to ~3.5MHz for reasonable timestamp resolution
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            timestamp      <= 28'd0;
            clk_div_cnt    <= 6'd0;
            timestamp_tick <= 1'b0;
        end
        else if (capture_active) begin
            if (clk_div_cnt >= CLK_DIV - 1) begin
                clk_div_cnt    <= 6'd0;
                timestamp_tick <= 1'b1;
                // Allow overflow (wraps at 28 bits = 268M ticks)
                timestamp      <= timestamp + 1'b1;
            end
            else begin
                clk_div_cnt    <= clk_div_cnt + 1'b1;
                timestamp_tick <= 1'b0;
            end
        end
        else begin
            timestamp_tick <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // FIFO Write Pointer and Memory
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            wr_ptr     <= {FIFO_ADDR_BITS{1'b0}};
            fifo_wr_en <= 1'b0;
        end
        else begin
            fifo_wr_en <= 1'b0;

            if (fifo_wr_en && !fifo_full) begin
                fifo_mem[wr_ptr] <= fifo_wr_data;
                wr_ptr           <= wr_ptr + 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // FIFO Read Pointer
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            rd_ptr       <= {FIFO_ADDR_BITS{1'b0}};
            fifo_rd_data <= 32'd0;
        end
        else begin
            // Read data for output
            fifo_rd_data <= fifo_mem[rd_ptr];

            // Advance read pointer when data consumed
            if (m_axis_tvalid && m_axis_tready && !fifo_empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // FIFO Count Management
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            fifo_count <= {(FIFO_ADDR_BITS+1){1'b0}};
        end
        else begin
            case ({fifo_wr_en && !fifo_full, m_axis_tvalid && m_axis_tready && !fifo_empty})
                2'b10: fifo_count <= fifo_count + 1'b1;  // Write only
                2'b01: fifo_count <= fifo_count - 1'b1;  // Read only
                default: fifo_count <= fifo_count;       // Both or neither
            endcase
        end
    end

    assign fifo_full  = (fifo_count == FIFO_DEPTH);
    assign fifo_empty = (fifo_count == 0);
    assign fifo_level = fifo_count;

    //-------------------------------------------------------------------------
    // Capture State Machine
    //-------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            state          <= S_IDLE;
            capture_active <= 1'b0;
            overflow_flag  <= 1'b0;
            index_seen     <= 1'b0;
            second_index   <= 1'b0;
            capture_count  <= 32'd0;
            index_count    <= 16'd0;
            last_was_index <= 1'b0;
        end
        else begin
            // Default: no write
            fifo_wr_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (capture_enable) begin
                        // Clear counters on new capture
                        capture_count  <= 32'd0;
                        index_count    <= 16'd0;
                        overflow_flag  <= 1'b0;
                        index_seen     <= 1'b0;
                        second_index   <= 1'b0;
                        last_was_index <= 1'b0;

                        if (capture_mode == MODE_CONTINUOUS) begin
                            // Start immediately
                            state          <= S_CAPTURING;
                            capture_active <= 1'b1;
                        end
                        else begin
                            // Wait for index pulse
                            state          <= S_ARMED;
                            capture_active <= 1'b0;
                        end
                    end
                end

                S_ARMED: begin
                    if (!capture_enable) begin
                        state <= S_IDLE;
                    end
                    else if (index_edge) begin
                        // Start capture on index
                        state          <= S_CAPTURING;
                        capture_active <= 1'b1;
                        index_seen     <= 1'b1;
                        index_count    <= index_count + 1'b1;

                        // Write index marker to FIFO
                        fifo_wr_en     <= 1'b1;
                        fifo_wr_data   <= {1'b1, overflow_flag, 2'b00, 28'd0};
                        last_was_index <= 1'b1;
                    end
                end

                S_CAPTURING: begin
                    if (!capture_enable) begin
                        state          <= S_DONE;
                        capture_active <= 1'b0;
                    end
                    else if (fifo_full) begin
                        // Overflow condition
                        overflow_flag <= 1'b1;
                        // Continue capturing, just mark overflow in next packet
                    end
                    else if (index_edge) begin
                        // Index pulse detected
                        index_count <= index_count + 1'b1;

                        if (index_seen) begin
                            second_index <= 1'b1;

                            // Check end conditions
                            if (capture_mode == MODE_ONE_REV) begin
                                // Single revolution complete
                                state          <= S_DONE;
                                capture_active <= 1'b0;
                            end
                            else if (capture_mode == MODE_ONE_TRACK && second_index) begin
                                // Full track (2 revolutions) complete
                                state          <= S_DONE;
                                capture_active <= 1'b0;
                            end
                        end
                        else begin
                            index_seen <= 1'b1;
                        end

                        // Write index marker to FIFO
                        if (!fifo_full) begin
                            fifo_wr_en     <= 1'b1;
                            fifo_wr_data   <= {1'b1, overflow_flag, 2'b00, timestamp};
                            last_was_index <= 1'b1;
                        end
                    end
                    else if (flux_edge) begin
                        // Flux transition detected
                        capture_count <= capture_count + 1'b1;

                        if (!fifo_full) begin
                            fifo_wr_en     <= 1'b1;
                            fifo_wr_data   <= {1'b0, overflow_flag, 2'b00, timestamp};
                            last_was_index <= 1'b0;
                            overflow_flag  <= 1'b0;  // Clear after first marked packet
                        end
                    end
                end

                S_DONE: begin
                    capture_active <= 1'b0;

                    // Wait for FIFO to drain, then return to idle
                    if (fifo_empty && !capture_enable) begin
                        state <= S_IDLE;
                    end
                    else if (capture_enable) begin
                        // Re-arm if capture enabled again
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // AXI-Stream Output Signals
    //-------------------------------------------------------------------------
    assign m_axis_tdata  = fifo_rd_data;
    assign m_axis_tvalid = !fifo_empty;
    assign m_axis_tlast  = fifo_rd_data[31];  // Index flag marks end of packet
    assign m_axis_tkeep  = 4'b1111;           // All bytes valid

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    assign overflow  = overflow_flag;
    assign capturing = capture_active;

endmodule


//-----------------------------------------------------------------------------
// Testbench for AXI-Stream Flux
//-----------------------------------------------------------------------------
`ifdef SIMULATION

module tb_axi_stream_flux;

    // Clock and reset
    reg         aclk;
    reg         aresetn;

    // Flux inputs
    reg         flux_raw;
    reg         index_pulse;

    // AXI-Stream
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;
    wire [3:0]  m_axis_tkeep;

    // Control
    reg         capture_enable;
    reg         soft_reset;
    reg  [1:0]  capture_mode;

    // Status
    wire [31:0] capture_count;
    wire [15:0] index_count;
    wire        overflow;
    wire        capturing;
    wire        fifo_empty;
    wire [9:0]  fifo_level;

    // DUT
    axi_stream_flux #(
        .FIFO_DEPTH(512),
        .FIFO_ADDR_BITS(9),
        .CLK_DIV(4)  // Faster for simulation
    ) u_dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .flux_raw(flux_raw),
        .index_pulse(index_pulse),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tkeep(m_axis_tkeep),
        .capture_enable(capture_enable),
        .soft_reset(soft_reset),
        .capture_mode(capture_mode),
        .capture_count(capture_count),
        .index_count(index_count),
        .overflow(overflow),
        .capturing(capturing),
        .fifo_empty(fifo_empty),
        .fifo_level(fifo_level)
    );

    // Clock generation (200 MHz)
    initial begin
        aclk = 0;
        forever #2.5 aclk = ~aclk;
    end

    // Test stimulus
    initial begin
        $display("===========================================");
        $display("AXI-Stream Flux Testbench");
        $display("===========================================");

        // Initialize
        aresetn        = 0;
        flux_raw       = 0;
        index_pulse    = 0;
        m_axis_tready  = 1;
        capture_enable = 0;
        soft_reset     = 0;
        capture_mode   = 2'b01;  // One track mode

        // Reset
        #100;
        aresetn = 1;
        #100;

        // Start capture
        $display("\nStarting capture (one track mode)...");
        capture_enable = 1;
        #50;

        // Generate index pulse to start
        index_pulse = 1;
        #20;
        index_pulse = 0;
        #100;

        // Generate some flux pulses
        repeat(10) begin
            #200;
            flux_raw = 1;
            #10;
            flux_raw = 0;
        end

        // Generate second index
        #500;
        index_pulse = 1;
        #20;
        index_pulse = 0;

        // More flux pulses
        repeat(5) begin
            #200;
            flux_raw = 1;
            #10;
            flux_raw = 0;
        end

        // Third index (should end capture)
        #500;
        index_pulse = 1;
        #20;
        index_pulse = 0;

        // Wait for completion
        #1000;

        // Check results
        $display("\nCapture complete:");
        $display("  Flux count: %d", capture_count);
        $display("  Index count: %d", index_count);
        $display("  FIFO level: %d", fifo_level);
        $display("  Overflow: %b", overflow);

        #500;
        $finish;
    end

    // Monitor AXI-Stream transactions
    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            if (m_axis_tdata[31])
                $display("[%0t] INDEX marker: timestamp=%d", $time, m_axis_tdata[27:0]);
            else
                $display("[%0t] FLUX: timestamp=%d", $time, m_axis_tdata[27:0]);
        end
    end

    // Timeout
    initial begin
        #100000;
        $display("Simulation timeout");
        $finish;
    end

endmodule

`endif
