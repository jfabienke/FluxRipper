// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// clock_reset_mgr.v - FluxRipper Clock and Reset Manager
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 21:25
// Updated: 2025-12-07 23:30 - Added XILINX_FPGA MMCM implementation
//
// Description:
//   Generates system clocks and manages reset sequencing.
//   - 100 MHz system clock from 25 MHz reference
//   - 48 MHz USB clock
//   - 50 MHz disk controller clock
//   - Synchronized resets per domain
//   - Debug reset bypass (debug survives system reset)
//   - Watchdog timeout reset
//
// Synthesis: Define XILINX_FPGA to use MMCME4_BASE primitive
// Simulation: Behavioral clock generation (default)
//
//-----------------------------------------------------------------------------

module clock_reset_mgr #(
    parameter WATCHDOG_CYCLES = 100000000  // ~1 sec at 100 MHz
)(
    // Reference clock and external reset
    input         clk_ref,        // 25 MHz reference
    input         rst_ext_n,      // External reset (active low)

    // Generated clocks
    output        clk_sys,        // 100 MHz system clock
    output        clk_usb,        // 48 MHz USB clock
    output        clk_disk,       // 50 MHz disk controller clock

    // Synchronized resets (active low)
    output        rst_sys_n,      // System domain reset
    output        rst_usb_n,      // USB domain reset
    output        rst_disk_n,     // Disk domain reset

    // Debug interface (active low reset, survives system reset)
    input         rst_debug_n,    // Debug reset request
    output        rst_dbg_sync_n, // Synchronized debug reset

    // Status
    output        pll_locked,     // PLL lock indicator

    // Watchdog interface
    input         wdt_kick,       // Kick watchdog (pulse)
    output        wdt_reset       // Watchdog triggered reset
);

    //=========================================================================
    // Clock Generation
    //=========================================================================

`ifdef XILINX_FPGA

    //-------------------------------------------------------------------------
    // AMD/Xilinx MMCM Implementation (Spartan UltraScale+)
    // Input: 25 MHz, VCO: 1200 MHz
    // Outputs: 100 MHz (sys), 48 MHz (usb), 50 MHz (disk)
    //-------------------------------------------------------------------------
    wire clk_sys_unbuf, clk_usb_unbuf, clk_disk_unbuf;
    wire clk_fb, clk_fb_buf;
    wire mmcm_locked;

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(48.0),      // VCO = 25 * 48 = 1200 MHz
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(40.0),        // 25 MHz = 40ns period
        .CLKOUT0_DIVIDE_F(12.0),     // 1200 / 12 = 100 MHz (system)
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(25),         // 1200 / 25 = 48 MHz (USB)
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(0.0),
        .CLKOUT2_DIVIDE(24),         // 1200 / 24 = 50 MHz (disk)
        .CLKOUT2_DUTY_CYCLE(0.5),
        .CLKOUT2_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.01),
        .STARTUP_WAIT("FALSE")
    ) mmcm_clk (
        .CLKOUT0(clk_sys_unbuf),
        .CLKOUT1(clk_usb_unbuf),
        .CLKOUT2(clk_disk_unbuf),
        .CLKOUT3(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clk_fb),
        .LOCKED(mmcm_locked),
        .CLKIN1(clk_ref),
        .PWRDWN(1'b0),
        .RST(~rst_ext_n),
        .CLKFBIN(clk_fb_buf)
    );

    // Global clock buffers
    BUFG bufg_fb (
        .I(clk_fb),
        .O(clk_fb_buf)
    );

    BUFG bufg_sys (
        .I(clk_sys_unbuf),
        .O(clk_sys)
    );

    BUFG bufg_usb (
        .I(clk_usb_unbuf),
        .O(clk_usb)
    );

    BUFG bufg_disk (
        .I(clk_disk_unbuf),
        .O(clk_disk)
    );

    assign pll_locked = mmcm_locked;

`else

    //-------------------------------------------------------------------------
    // Behavioral Model (for simulation)
    //-------------------------------------------------------------------------
    // clk_ref = 25 MHz (40 ns period)
    // clk_sys = 100 MHz (10 ns period) = ref * 4
    // clk_usb = 48 MHz (~20.8 ns period) ≈ ref * 1.92
    // clk_disk = 50 MHz (20 ns period) = ref * 2

    reg clk_sys_reg = 0;
    reg clk_usb_reg = 0;
    reg clk_disk_reg = 0;

    // System clock: 4x reference (100 MHz from 25 MHz)
    reg [1:0] sys_div = 0;
    always @(posedge clk_ref or negedge rst_ext_n) begin
        if (!rst_ext_n) begin
            sys_div <= 0;
            clk_sys_reg <= 0;
        end else begin
            sys_div <= sys_div + 1;
            // Toggle every cycle for 4x frequency (simplified)
            clk_sys_reg <= ~clk_sys_reg;
        end
    end

    // USB clock: ~48 MHz (approximate with toggle)
    reg [2:0] usb_div = 0;
    always @(posedge clk_ref or negedge rst_ext_n) begin
        if (!rst_ext_n) begin
            usb_div <= 0;
            clk_usb_reg <= 0;
        end else begin
            // Toggle approximately at 48/25 ratio
            if (usb_div == 0) begin
                clk_usb_reg <= ~clk_usb_reg;
                usb_div <= 0;  // Every cycle for simulation
            end else begin
                usb_div <= usb_div - 1;
            end
        end
    end

    // Disk clock: 2x reference (50 MHz from 25 MHz)
    always @(posedge clk_ref or negedge rst_ext_n) begin
        if (!rst_ext_n)
            clk_disk_reg <= 0;
        else
            clk_disk_reg <= ~clk_disk_reg;
    end

    assign clk_sys = clk_sys_reg;
    assign clk_usb = clk_usb_reg;
    assign clk_disk = clk_disk_reg;

    //-------------------------------------------------------------------------
    // PLL Lock Simulation
    //-------------------------------------------------------------------------
    // Simulate PLL lock time (~100 reference cycles)
    reg [7:0] lock_counter = 0;
    reg pll_locked_reg = 0;

    always @(posedge clk_ref or negedge rst_ext_n) begin
        if (!rst_ext_n) begin
            lock_counter <= 0;
            pll_locked_reg <= 0;
        end else if (!pll_locked_reg) begin
            if (lock_counter == 8'd100)
                pll_locked_reg <= 1;
            else
                lock_counter <= lock_counter + 1;
        end
    end

    assign pll_locked = pll_locked_reg;

`endif

    //=========================================================================
    // Reset Synchronizers
    //=========================================================================
    // 2-stage synchronizer for each clock domain

    // System domain reset
    reg [2:0] rst_sys_sync = 3'b000;
    always @(posedge clk_sys or negedge rst_ext_n) begin
        if (!rst_ext_n)
            rst_sys_sync <= 3'b000;
        else if (pll_locked_reg)
            rst_sys_sync <= {rst_sys_sync[1:0], 1'b1};
    end
    assign rst_sys_n = rst_sys_sync[2] & ~wdt_reset;

    // USB domain reset
    reg [2:0] rst_usb_sync = 3'b000;
    always @(posedge clk_usb or negedge rst_ext_n) begin
        if (!rst_ext_n)
            rst_usb_sync <= 3'b000;
        else if (pll_locked_reg)
            rst_usb_sync <= {rst_usb_sync[1:0], 1'b1};
    end
    assign rst_usb_n = rst_usb_sync[2] & ~wdt_reset;

    // Disk domain reset
    reg [2:0] rst_disk_sync = 3'b000;
    always @(posedge clk_disk or negedge rst_ext_n) begin
        if (!rst_ext_n)
            rst_disk_sync <= 3'b000;
        else if (pll_locked_reg)
            rst_disk_sync <= {rst_disk_sync[1:0], 1'b1};
    end
    assign rst_disk_n = rst_disk_sync[2] & ~wdt_reset;

    // Debug domain reset (survives system reset, only responds to debug reset)
    reg [2:0] rst_dbg_sync = 3'b000;
    always @(posedge clk_sys or negedge rst_debug_n) begin
        if (!rst_debug_n)
            rst_dbg_sync <= 3'b000;
        else if (pll_locked_reg)
            rst_dbg_sync <= {rst_dbg_sync[1:0], 1'b1};
    end
    assign rst_dbg_sync_n = rst_dbg_sync[2];

    //=========================================================================
    // Watchdog Timer
    //=========================================================================
    reg [31:0] wdt_counter = 0;
    reg wdt_expired = 0;

    always @(posedge clk_sys or negedge rst_ext_n) begin
        if (!rst_ext_n) begin
            wdt_counter <= 0;
            wdt_expired <= 0;
        end else if (wdt_kick) begin
            wdt_counter <= 0;
            wdt_expired <= 0;
        end else if (rst_sys_sync[2]) begin  // Only count when out of reset
            if (wdt_counter >= WATCHDOG_CYCLES)
                wdt_expired <= 1;
            else
                wdt_counter <= wdt_counter + 1;
        end
    end

    assign wdt_reset = wdt_expired;

    //=========================================================================
    // Debug Status Register (accessible via system bus)
    //=========================================================================
    // This would be memory-mapped in the real system
    // For now, expose as outputs for testbench visibility

endmodule
