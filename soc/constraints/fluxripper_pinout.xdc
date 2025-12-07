#------------------------------------------------------------------------------
# FluxRipper Pin Assignments
# Target: AMD Spartan UltraScale+ SCU35 Evaluation Board
#
# IMPORTANT: These are placeholder assignments!
# Update with actual board pinout before synthesis.
#
# Created: 2025-12-07 23:55
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Clock Input
#------------------------------------------------------------------------------
# 25 MHz oscillator - update to match your board
# set_property PACKAGE_PIN <pin> [get_ports clk_25m]

# Placeholder - common oscillator locations
set_property PACKAGE_PIN E12 [get_ports clk_25m]

#------------------------------------------------------------------------------
# Reset
#------------------------------------------------------------------------------
# Active-low external reset button
# set_property PACKAGE_PIN <pin> [get_ports rst_n]

set_property PACKAGE_PIN F12 [get_ports rst_n]

#------------------------------------------------------------------------------
# JTAG Interface
#------------------------------------------------------------------------------
# User JTAG header (not the configuration JTAG)
# These pins should be on a GPIO header for Black Magic Probe connection

# Option 1: PMOD header (common on eval boards)
set_property PACKAGE_PIN A12 [get_ports tck]
set_property PACKAGE_PIN B12 [get_ports tms]
set_property PACKAGE_PIN A13 [get_ports tdi]
set_property PACKAGE_PIN B13 [get_ports tdo]
set_property PACKAGE_PIN A14 [get_ports trst_n]

#------------------------------------------------------------------------------
# Disk Interface
#------------------------------------------------------------------------------
# Connect to floppy drive interface or test header

set_property PACKAGE_PIN C12 [get_ports flux_in]
set_property PACKAGE_PIN D12 [get_ports index_in]
set_property PACKAGE_PIN C13 [get_ports motor_on]
set_property PACKAGE_PIN D13 [get_ports head_sel]
set_property PACKAGE_PIN C14 [get_ports dir]
set_property PACKAGE_PIN D14 [get_ports step]

#------------------------------------------------------------------------------
# USB Status LEDs
#------------------------------------------------------------------------------
# Connect to LEDs or test points

set_property PACKAGE_PIN E13 [get_ports usb_connected]
set_property PACKAGE_PIN F13 [get_ports usb_configured]

#------------------------------------------------------------------------------
# Debug Status LEDs
#------------------------------------------------------------------------------
# Connect to onboard LEDs

set_property PACKAGE_PIN E14 [get_ports pll_locked]
set_property PACKAGE_PIN F14 [get_ports sys_rst_n]

#------------------------------------------------------------------------------
# IMPORTANT: Pin Assignment Verification
#------------------------------------------------------------------------------
# Before synthesis, verify these pins against your specific board:
#
# 1. Check board schematic for available GPIO pins
# 2. Verify voltage bank compatibility (using LVCMOS33)
# 3. Ensure no conflicts with dedicated pins
# 4. Update clock pin to match board oscillator
#
# Common SCU35 evaluation board resources:
# - PMOD connectors: 8 pins each, typically LVCMOS33
# - User LEDs: 4-8 LEDs typically available
# - User buttons: 2-4 buttons typically available
# - FTDI USB-JTAG: May share pins with user JTAG
#
# For Black Magic Probe connection:
# - TCK, TMS, TDI, TDO on GPIO header
# - TRST optional (active-low reset)
# - GND connection required
#------------------------------------------------------------------------------
