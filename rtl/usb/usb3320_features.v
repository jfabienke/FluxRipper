// SPDX-License-Identifier: BSD-3-Clause
////////////////////////////////////////////////////////////////////////////////
// usb3320_features.v - USB3320 ULPI PHY Advanced Features Module
//
// Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
// Copyright (c) 2025 John Fabienke
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Created: 2025-12-06 17:49:02
// Updated: 2025-12-06 20:50:00
////////////////////////////////////////////////////////////////////////////////
// This module provides access to USB3320-specific features beyond basic ULPI:
// - VBUS monitoring and detection (4.4V, 2.0V, 0.8V thresholds)
// - OTG support (ID pin detection, VBUS drive control)
// - Low power mode (suspend/resume)
// - Charger detection (SDP/CDP/DCP classification)
// - Register read/write state machine for ULPI extended registers
//
// USB3320 ULPI Register Map (relevant subset):
//   0x00-0x03: Vendor ID / Product ID (read-only, 0x0424/0x0009)
//   0x04: Function Control - USB operation mode, suspend, reset
//   0x07: USB Interrupt Enable - Enable VBUS comparator interrupts
//   0x0A: OTG Control - ID pullup, D+/D- pulldown, VBUS drive/discharge
//   0x13: USB Interrupt Status - VBUS comparators (VbusValid, SessValid, etc)
//   0x14: USB Interrupt Latch - Latched interrupt events
//   0x3D: Scratch Register - General purpose test register
//
// OTG Control Register (0x0A) bit definitions:
//   [0] IdPullup - Enable ID pin pullup (default 1)
//   [1] DpPulldown - D+ 15k pulldown for host mode
//   [2] DmPulldown - D- 15k pulldown for host mode
//   [3] DischargeVbus - Enable VBUS discharge (100 ohm to GND)
//   [4] ChargeVbus - Enable VBUS charge for SRP (pull to 3.3V via 100k)
//   [5] DrvVbus - Drive VBUS internally (if supported)
//   [6] DrvVbusExternal - Drive VBUS via CPEN pin (charge pump enable)
//   [7] UseExternalVbusIndicator - Use external VBUS detect
//
// USB Interrupt Status Register (0x13) bit definitions:
//   [0] VbusValid - VBUS > 4.4V (valid host present)
//   [1] SessValid - VBUS > 2.0V (session valid)
//   [2] SessEnd - VBUS < 0.8V (session ended, almost 0V)
//   [3] IdGnd - ID pin grounded (A-device / host mode)
//   [7:4] Reserved
//
// Function Control Register (0x04) bit definitions:
//   [5:4] OpMode - 00=Normal, 01=Non-driving, 10=Disable bit stuff, 11=Reserved
//   [6] SuspendM - Put PHY in low power mode
//   [7] Reset - Software reset of PHY
//
////////////////////////////////////////////////////////////////////////////////

module usb3320_features (
    input         clk_60mhz,        // ULPI clock (60MHz from USB3320)
    input         rst_n,            // Active-low reset

    // ULPI register access interface
    // Connect to ulpi_wrapper or custom ULPI register access logic
    output reg [7:0]  reg_addr,     // ULPI register address (0x00-0x3F)
    output reg [7:0]  reg_wdata,    // Data to write to register
    output reg        reg_write,    // Pulse to initiate write
    output reg        reg_read,     // Pulse to initiate read
    input  [7:0]      reg_rdata,    // Data read from register
    input             reg_done,     // Read/write completed (pulse)

    // VBUS status outputs (from USB Interrupt Status register)
    output reg        vbus_valid,   // VBUS > 4.4V (host connected)
    output reg        sess_valid,   // VBUS > 2.0V (session active)
    output reg        sess_end,     // VBUS < 0.8V (session ended)
    output reg        cable_connected,    // Rising edge of vbus_valid
    output reg        cable_disconnect,   // Falling edge of vbus_valid

    // OTG status and control
    input             id_pin,       // ID pin state (0=host/A-device, 1=device/B-device)
    output reg        is_host_mode, // We are in host mode (ID grounded)
    output reg        drv_vbus,     // Driving VBUS (for host mode)

    // Low power control
    input             enter_suspend, // Request to enter suspend
    output reg        in_suspend,    // Currently in suspend mode

    // Charger detection
    output reg        charger_detected,  // Charger detection complete
    output reg [1:0]  charger_type,      // 0=SDP, 1=CDP, 2=DCP, 3=unknown

    // Configuration inputs
    input             enable_vbus_poll,  // Enable periodic VBUS polling
    input  [15:0]     poll_interval      // Polling interval in 60MHz clocks
                                         // Default: 60000 = 1ms
);

////////////////////////////////////////////////////////////////////////////////
// Register Addresses (USB3320 ULPI Register Map)
////////////////////////////////////////////////////////////////////////////////
localparam ADDR_VENDOR_ID_LO    = 8'h00;  // Vendor ID low byte
localparam ADDR_VENDOR_ID_HI    = 8'h01;  // Vendor ID high byte (0x0424)
localparam ADDR_PRODUCT_ID_LO   = 8'h02;  // Product ID low byte
localparam ADDR_PRODUCT_ID_HI   = 8'h03;  // Product ID high byte (0x0009)
localparam ADDR_FUNC_CTRL       = 8'h04;  // Function Control
localparam ADDR_INT_ENABLE      = 8'h07;  // USB Interrupt Enable
localparam ADDR_OTG_CTRL        = 8'h0A;  // OTG Control
localparam ADDR_INT_STATUS      = 8'h13;  // USB Interrupt Status
localparam ADDR_INT_LATCH       = 8'h14;  // USB Interrupt Latch
localparam ADDR_SCRATCH         = 8'h3D;  // Scratch register

////////////////////////////////////////////////////////////////////////////////
// State Machine States
////////////////////////////////////////////////////////////////////////////////
localparam STATE_IDLE           = 4'd0;
localparam STATE_INIT_READ_VID  = 4'd1;   // Read Vendor ID (optional init)
localparam STATE_INIT_WAIT_VID  = 4'd2;
localparam STATE_POLL_WAIT      = 4'd3;   // Wait for poll interval
localparam STATE_READ_INT_STAT  = 4'd4;   // Read USB Interrupt Status
localparam STATE_WAIT_INT_STAT  = 4'd5;
localparam STATE_PROCESS_INT    = 4'd6;   // Process interrupt status
localparam STATE_WRITE_OTG      = 4'd7;   // Write OTG Control
localparam STATE_WAIT_OTG       = 4'd8;
localparam STATE_SUSPEND_WRITE  = 4'd9;   // Write Function Control for suspend
localparam STATE_SUSPEND_WAIT   = 4'd10;
localparam STATE_CHARGER_DETECT = 4'd11;  // Charger detection sequence
localparam STATE_CHARGER_WAIT   = 4'd12;

reg [3:0] state;
reg [3:0] next_state;

////////////////////////////////////////////////////////////////////////////////
// Polling Timer
////////////////////////////////////////////////////////////////////////////////
reg [15:0] poll_counter;
reg poll_trigger;

always @(posedge clk_60mhz or negedge rst_n) begin
    if (!rst_n) begin
        poll_counter <= 16'd0;
        poll_trigger <= 1'b0;
    end else begin
        poll_trigger <= 1'b0;

        if (enable_vbus_poll) begin
            if (poll_counter >= poll_interval) begin
                poll_counter <= 16'd0;
                poll_trigger <= 1'b1;
            end else begin
                poll_counter <= poll_counter + 16'd1;
            end
        end else begin
            poll_counter <= 16'd0;
        end
    end
end

////////////////////////////////////////////////////////////////////////////////
// Edge Detection for Cable Connect/Disconnect
////////////////////////////////////////////////////////////////////////////////
reg vbus_valid_prev;

always @(posedge clk_60mhz or negedge rst_n) begin
    if (!rst_n) begin
        vbus_valid_prev <= 1'b0;
        cable_connected <= 1'b0;
        cable_disconnect <= 1'b0;
    end else begin
        vbus_valid_prev <= vbus_valid;

        // Rising edge = cable connected
        cable_connected <= vbus_valid && !vbus_valid_prev;

        // Falling edge = cable disconnected
        cable_disconnect <= !vbus_valid && vbus_valid_prev;
    end
end

////////////////////////////////////////////////////////////////////////////////
// OTG Mode Detection
////////////////////////////////////////////////////////////////////////////////
// ID pin: 0 = Host (A-device), 1 = Device (B-device)
reg id_pin_prev;

always @(posedge clk_60mhz or negedge rst_n) begin
    if (!rst_n) begin
        is_host_mode <= 1'b0;
        id_pin_prev <= 1'b1;
    end else begin
        id_pin_prev <= id_pin;

        // ID grounded = host mode
        is_host_mode <= (id_pin == 1'b0);
    end
end

////////////////////////////////////////////////////////////////////////////////
// OTG Control Register Value
////////////////////////////////////////////////////////////////////////////////
// Default: IdPullup enabled, others disabled
reg [7:0] otg_ctrl_value;

always @(*) begin
    otg_ctrl_value = 8'h01;  // Start with IdPullup enabled

    if (is_host_mode) begin
        // Host mode: Enable D+/D- pulldowns, drive VBUS
        otg_ctrl_value[1] = 1'b1;  // DpPulldown
        otg_ctrl_value[2] = 1'b1;  // DmPulldown
        otg_ctrl_value[6] = drv_vbus;  // DrvVbusExternal
    end else begin
        // Device mode: Disable pulldowns, don't drive VBUS
        otg_ctrl_value[1] = 1'b0;
        otg_ctrl_value[2] = 1'b0;
        otg_ctrl_value[6] = 1'b0;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Suspend Control
////////////////////////////////////////////////////////////////////////////////
reg suspend_requested;

always @(posedge clk_60mhz or negedge rst_n) begin
    if (!rst_n) begin
        suspend_requested <= 1'b0;
    end else begin
        if (enter_suspend && !in_suspend) begin
            suspend_requested <= 1'b1;
        end else if (state == STATE_SUSPEND_WRITE) begin
            suspend_requested <= 1'b0;
        end
    end
end

////////////////////////////////////////////////////////////////////////////////
// Charger Detection State Machine
////////////////////////////////////////////////////////////////////////////////
// Simple charger detection: monitor D+/D- levels
// SDP (Standard Downstream Port): D+/D- both low or floating
// CDP (Charging Downstream Port): D+/D- shorted together
// DCP (Dedicated Charging Port): D+ and D- have voltage divider
// This is a simplified version - full detection requires D+/D- control

reg charger_detect_start;
reg [7:0] charger_detect_count;

always @(posedge clk_60mhz or negedge rst_n) begin
    if (!rst_n) begin
        charger_detect_start <= 1'b0;
        charger_detect_count <= 8'd0;
        charger_detected <= 1'b0;
        charger_type <= 2'b11;  // Unknown
    end else begin
        // Start charger detection when VBUS detected but no USB enumeration
        if (vbus_valid && !sess_valid && !charger_detected) begin
            charger_detect_start <= 1'b1;
        end

        // Simple timeout-based detection (placeholder logic)
        if (charger_detect_start) begin
            if (charger_detect_count < 8'd255) begin
                charger_detect_count <= charger_detect_count + 8'd1;
            end else begin
                charger_detected <= 1'b1;
                charger_detect_start <= 1'b0;

                // Simplified classification based on VBUS behavior
                // In real implementation, would read D+/D- comparators
                if (sess_valid) begin
                    charger_type <= 2'b01;  // CDP (can enumerate)
                end else if (vbus_valid) begin
                    charger_type <= 2'b10;  // DCP (VBUS only, no data)
                end else begin
                    charger_type <= 2'b00;  // SDP (standard USB)
                end
            end
        end

        // Reset detection when cable unplugged
        if (!vbus_valid) begin
            charger_detected <= 1'b0;
            charger_detect_start <= 1'b0;
            charger_detect_count <= 8'd0;
            charger_type <= 2'b11;
        end
    end
end

////////////////////////////////////////////////////////////////////////////////
// Main State Machine
////////////////////////////////////////////////////////////////////////////////
reg otg_update_needed;

always @(posedge clk_60mhz or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        reg_addr <= 8'h00;
        reg_wdata <= 8'h00;
        reg_write <= 1'b0;
        reg_read <= 1'b0;
        vbus_valid <= 1'b0;
        sess_valid <= 1'b0;
        sess_end <= 1'b1;
        drv_vbus <= 1'b0;
        in_suspend <= 1'b0;
        otg_update_needed <= 1'b0;
    end else begin
        // Default: clear pulses
        reg_write <= 1'b0;
        reg_read <= 1'b0;

        // Track OTG mode changes
        if (is_host_mode && !drv_vbus) begin
            drv_vbus <= 1'b1;
            otg_update_needed <= 1'b1;
        end else if (!is_host_mode && drv_vbus) begin
            drv_vbus <= 1'b0;
            otg_update_needed <= 1'b1;
        end

        case (state)
            ////////////////////////////////////////////////////////////////////////////////
            STATE_IDLE: begin
                // Priority order:
                // 1. Suspend request (highest priority)
                // 2. OTG control update needed
                // 3. Periodic VBUS poll

                if (suspend_requested) begin
                    state <= STATE_SUSPEND_WRITE;
                end else if (otg_update_needed) begin
                    state <= STATE_WRITE_OTG;
                end else if (poll_trigger) begin
                    state <= STATE_READ_INT_STAT;
                end
            end

            ////////////////////////////////////////////////////////////////////////////////
            // VBUS Polling: Read USB Interrupt Status register
            ////////////////////////////////////////////////////////////////////////////////
            STATE_READ_INT_STAT: begin
                reg_addr <= ADDR_INT_STATUS;
                reg_read <= 1'b1;
                state <= STATE_WAIT_INT_STAT;
            end

            STATE_WAIT_INT_STAT: begin
                if (reg_done) begin
                    // Parse USB Interrupt Status register
                    vbus_valid <= reg_rdata[0];  // Bit 0: VbusValid (>4.4V)
                    sess_valid <= reg_rdata[1];  // Bit 1: SessValid (>2.0V)
                    sess_end   <= reg_rdata[2];  // Bit 2: SessEnd   (<0.8V)
                    // reg_rdata[3] = IdGnd (ID pin grounded)

                    state <= STATE_IDLE;
                end
            end

            ////////////////////////////////////////////////////////////////////////////////
            // OTG Control: Write OTG Control register
            ////////////////////////////////////////////////////////////////////////////////
            STATE_WRITE_OTG: begin
                reg_addr <= ADDR_OTG_CTRL;
                reg_wdata <= otg_ctrl_value;
                reg_write <= 1'b1;
                state <= STATE_WAIT_OTG;
                otg_update_needed <= 1'b0;
            end

            STATE_WAIT_OTG: begin
                if (reg_done) begin
                    state <= STATE_IDLE;
                end
            end

            ////////////////////////////////////////////////////////////////////////////////
            // Suspend: Write Function Control register with SuspendM bit
            ////////////////////////////////////////////////////////////////////////////////
            STATE_SUSPEND_WRITE: begin
                reg_addr <= ADDR_FUNC_CTRL;
                // Bit [6] = SuspendM, Bits [5:4] = OpMode (00 = Normal)
                // Set SuspendM to enter low power mode
                reg_wdata <= 8'h40;  // 0b01000000 = SuspendM set
                reg_write <= 1'b1;
                state <= STATE_SUSPEND_WAIT;
            end

            STATE_SUSPEND_WAIT: begin
                if (reg_done) begin
                    in_suspend <= 1'b1;
                    state <= STATE_IDLE;
                end
            end

            ////////////////////////////////////////////////////////////////////////////////
            // Default: Return to idle
            ////////////////////////////////////////////////////////////////////////////////
            default: begin
                state <= STATE_IDLE;
            end
        endcase

        // Exit suspend when enter_suspend deasserts
        if (!enter_suspend && in_suspend) begin
            in_suspend <= 1'b0;
            // Could write Function Control to clear SuspendM here
        end
    end
end

////////////////////////////////////////////////////////////////////////////////
// Debug/Status Outputs (could be removed in production)
////////////////////////////////////////////////////////////////////////////////
// synthesis translate_off
reg [7:0] vendor_id_lo;
reg [7:0] vendor_id_hi;

always @(posedge clk_60mhz) begin
    if (state == STATE_INIT_WAIT_VID && reg_done) begin
        if (reg_addr == ADDR_VENDOR_ID_LO) vendor_id_lo <= reg_rdata;
        if (reg_addr == ADDR_VENDOR_ID_HI) vendor_id_hi <= reg_rdata;
    end
end
// synthesis translate_on

endmodule
