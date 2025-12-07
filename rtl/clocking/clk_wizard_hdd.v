//-----------------------------------------------------------------------------
// HDD Clock Domain Generator for FluxRipper
// Generates 300 MHz clock for ST-506 MFM/RLL/ESDI support
//
// Dual-clock architecture:
//   - 200 MHz domain: Existing floppy logic (unchanged)
//   - 300 MHz domain: HDD NCO, RLL decoder, high-rate flux capture
//
// 300 MHz chosen for reliable timing closure on Spartan UltraScale+ (-2 grade)
// Resolution: 3.33ns (sufficient for 15 Mbps ESDI)
//
// Created: 2025-12-03 15:15
// Updated: 2025-12-04 13:30
//-----------------------------------------------------------------------------

module clk_wizard_hdd (
    input  wire        clk_in,          // Input clock (typically 200 MHz from MMCM)
    input  wire        reset,
    input  wire        hdd_mode_enable, // Enable 300 MHz domain

    output wire        clk_200mhz,      // Pass-through for floppy domain
    output wire        clk_300mhz,      // HDD domain clock
    output wire        clk_300mhz_en,   // Clock enable for power gating
    output wire        locked           // PLL/MMCM locked status
);

    // For AMD/Xilinx UltraScale+, use MMCM primitive
    // Target: Spartan UltraScale+ (XCSU35P)
    // This is a behavioral model - replace with vendor primitive for synthesis

    `ifdef XILINX_FPGA

    //-------------------------------------------------------------------------
    // AMD/Xilinx MMCM Implementation (UltraScale+)
    // Input: 200 MHz, Output: 300 MHz (VCO at 800-1600 MHz)
    //-------------------------------------------------------------------------
    wire clk_300_unbuf;
    wire clk_fb;
    wire mmcm_locked;

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(6.0),       // VCO = 200 * 6 = 1200 MHz
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(5.0),         // 200 MHz = 5ns period
        .CLKOUT0_DIVIDE_F(4.0),      // 1200 / 4 = 300 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.01),
        .STARTUP_WAIT("FALSE")
    ) mmcm_hdd (
        .CLKOUT0(clk_300_unbuf),
        .CLKFBOUT(clk_fb),
        .LOCKED(mmcm_locked),
        .CLKIN1(clk_in),
        .PWRDWN(~hdd_mode_enable),   // Power down when HDD mode disabled
        .RST(reset),
        .CLKFBIN(clk_fb)
    );

    // Global clock buffers
    BUFG bufg_300 (
        .I(clk_300_unbuf),
        .O(clk_300mhz)
    );

    assign locked = mmcm_locked;

    `else

    //-------------------------------------------------------------------------
    // Behavioral Model (for simulation)
    // Generate 300 MHz from 200 MHz using phase accumulator
    //-------------------------------------------------------------------------
    reg clk_300_gen;
    reg lock_delay;
    reg [1:0] phase_acc;  // 3:2 ratio accumulator

    initial begin
        clk_300_gen = 1'b0;
        lock_delay = 1'b0;
        phase_acc = 2'b0;
    end

    // Generate 300 MHz from 200 MHz (3:2 ratio)
    // Every 2 input cycles, generate 3 output cycles
    always @(posedge clk_in or negedge clk_in) begin
        if (!hdd_mode_enable || reset) begin
            clk_300_gen <= 1'b0;
            phase_acc <= 2'b0;
        end else begin
            // Approximate 300 MHz by toggling at 1.5x rate
            phase_acc <= phase_acc + 2'd3;
            if (phase_acc[1]) begin
                clk_300_gen <= ~clk_300_gen;
            end
        end
    end

    // Simulate lock delay
    reg [7:0] lock_counter;
    always @(posedge clk_in) begin
        if (reset || !hdd_mode_enable) begin
            lock_counter <= 8'd0;
            lock_delay <= 1'b0;
        end else if (lock_counter < 8'd100) begin
            lock_counter <= lock_counter + 1;
            lock_delay <= 1'b0;
        end else begin
            lock_delay <= 1'b1;
        end
    end

    assign clk_300mhz = clk_300_gen;
    assign locked = lock_delay;

    `endif

    // Pass-through 200 MHz
    assign clk_200mhz = clk_in;

    // Clock enable for power gating
    assign clk_300mhz_en = hdd_mode_enable && locked;

endmodule

//-----------------------------------------------------------------------------
// Async FIFO for CDC between 200 MHz and 300 MHz domains
// Used for transferring flux data and status between clock domains
//-----------------------------------------------------------------------------
module hdd_cdc_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH_LOG2 = 4        // 16-entry FIFO
) (
    // Write side (HDD domain - 300 MHz)
    input  wire                    wr_clk,
    input  wire                    wr_reset,
    input  wire                    wr_en,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    output wire                    wr_full,

    // Read side (Floppy/CPU domain - 200/100 MHz)
    input  wire                    rd_clk,
    input  wire                    rd_reset,
    input  wire                    rd_en,
    output wire [DATA_WIDTH-1:0]   rd_data,
    output wire                    rd_empty
);

    localparam DEPTH = 1 << DEPTH_LOG2;

    // FIFO memory
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write pointer (gray-coded for CDC)
    reg [DEPTH_LOG2:0] wr_ptr;
    reg [DEPTH_LOG2:0] wr_ptr_gray;
    reg [DEPTH_LOG2:0] wr_ptr_gray_sync1;
    reg [DEPTH_LOG2:0] wr_ptr_gray_sync2;

    // Read pointer (gray-coded for CDC)
    reg [DEPTH_LOG2:0] rd_ptr;
    reg [DEPTH_LOG2:0] rd_ptr_gray;
    reg [DEPTH_LOG2:0] rd_ptr_gray_sync1;
    reg [DEPTH_LOG2:0] rd_ptr_gray_sync2;

    // Binary to Gray conversion
    function [DEPTH_LOG2:0] bin2gray;
        input [DEPTH_LOG2:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    // Write logic (300 MHz domain)
    always @(posedge wr_clk) begin
        if (wr_reset) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
        end else if (wr_en && !wr_full) begin
            mem[wr_ptr[DEPTH_LOG2-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
            wr_ptr_gray <= bin2gray(wr_ptr + 1);
        end
    end

    // Synchronize read pointer to write domain
    always @(posedge wr_clk) begin
        if (wr_reset) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Read logic (200/100 MHz domain)
    always @(posedge rd_clk) begin
        if (rd_reset) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
        end else if (rd_en && !rd_empty) begin
            rd_ptr <= rd_ptr + 1;
            rd_ptr_gray <= bin2gray(rd_ptr + 1);
        end
    end

    // Synchronize write pointer to read domain
    always @(posedge rd_clk) begin
        if (rd_reset) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // Output data
    assign rd_data = mem[rd_ptr[DEPTH_LOG2-1:0]];

    // Full/empty flags
    assign wr_full = (wr_ptr_gray == {~rd_ptr_gray_sync2[DEPTH_LOG2:DEPTH_LOG2-1],
                                       rd_ptr_gray_sync2[DEPTH_LOG2-2:0]});
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

endmodule
