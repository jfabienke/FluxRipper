## SPDX-License-Identifier: BSD-3-Clause
##-----------------------------------------------------------------------------
## ULPI USB3300/USB3320 PHY Interface Constraints
## Target: Xilinx Spartan UltraScale+
##
## Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
## Copyright (c) 2025 John Fabienke
##
## Description:
##   Constraints for USB3300/USB3320 ULPI (UTMI+ Low Pin Interface) PHY
##   - 60 MHz clock from PHY to FPGA
##   - 8-bit bidirectional data bus
##   - Source-synchronous interface (data valid relative to ulpi_clk edges)
##   - Async clock domain crossing with system clock
##
## Updated: 2025-12-06 20:50:00
##-----------------------------------------------------------------------------

##-----------------------------------------------------------------------------
## ULPI Clock Constraint
##-----------------------------------------------------------------------------

# ULPI 60 MHz clock from USB3300 PHY
# Period = 16.667 ns (60 MHz)
create_clock -period 16.667 -name ulpi_clk [get_ports ulpi_clk]

##-----------------------------------------------------------------------------
## Clock Domain Crossing
##-----------------------------------------------------------------------------

# Async clock groups between system clock and ULPI clock
# These two clocks are completely asynchronous - no phase relationship
set_clock_groups -asynchronous -group [get_clocks clk_200mhz] -group [get_clocks ulpi_clk]

##-----------------------------------------------------------------------------
## ULPI Input Delays
##-----------------------------------------------------------------------------

# ULPI data bus - when PHY is driving (DIR=1)
# USB3300 spec: Valid data window is typically 5ns setup, 1ns hold relative to ulpi_clk
# Using conservative values for max/min analysis
set_input_delay -clock ulpi_clk -max 5.000 [get_ports {ulpi_data[*]}]
set_input_delay -clock ulpi_clk -min 0.500 [get_ports {ulpi_data[*]}]

# ULPI DIR (Direction) - PHY indicates bus direction
# DIR changes are synchronized to ulpi_clk
set_input_delay -clock ulpi_clk -max 5.000 [get_ports ulpi_dir]
set_input_delay -clock ulpi_clk -min 0.500 [get_ports ulpi_dir]

# ULPI NXT (Next) - PHY indicates data acceptance/continuation
# NXT timing is critical for throttling data transfers
set_input_delay -clock ulpi_clk -max 5.000 [get_ports ulpi_nxt]
set_input_delay -clock ulpi_clk -min 0.500 [get_ports ulpi_nxt]

##-----------------------------------------------------------------------------
## ULPI Output Delays
##-----------------------------------------------------------------------------

# ULPI data bus - when FPGA is driving (DIR=0)
# FPGA must provide valid data before rising edge of ulpi_clk
# Setup requirement: ~5ns before clock, hold: ~0.5ns after clock
set_output_delay -clock ulpi_clk -max 5.000 [get_ports {ulpi_data[*]}]
set_output_delay -clock ulpi_clk -min 0.500 [get_ports {ulpi_data[*]}]

# ULPI STP (Stop) - FPGA terminates transfer
# Critical timing for packet boundaries
set_output_delay -clock ulpi_clk -max 5.000 [get_ports ulpi_stp]
set_output_delay -clock ulpi_clk -min 0.500 [get_ports ulpi_stp]

##-----------------------------------------------------------------------------
## False Paths
##-----------------------------------------------------------------------------

# ULPI reset is asynchronous
# RST_N is asserted/deasserted independently of clocks
set_false_path -from [get_ports ulpi_rst_n]
set_false_path -to [get_ports ulpi_rst_n]

# CDC synchronizers between system clock and ULPI clock domains
# These are explicitly handled by synchronizer chains (2+ FFs)
set_false_path -from [get_clocks clk_200mhz] -to [get_cells -hierarchical *ulpi*sync_reg[0]*]
set_false_path -from [get_clocks ulpi_clk] -to [get_cells -hierarchical *sys*sync_reg[0]*]

##-----------------------------------------------------------------------------
## I/O Standards
##-----------------------------------------------------------------------------

# USB3300/USB3320 operates at 3.3V LVCMOS
set_property IOSTANDARD LVCMOS33 [get_ports ulpi_clk]
set_property IOSTANDARD LVCMOS33 [get_ports {ulpi_data[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports ulpi_dir]
set_property IOSTANDARD LVCMOS33 [get_ports ulpi_nxt]
set_property IOSTANDARD LVCMOS33 [get_ports ulpi_stp]
set_property IOSTANDARD LVCMOS33 [get_ports ulpi_rst_n]

##-----------------------------------------------------------------------------
## IOB Packing
##-----------------------------------------------------------------------------

# Pack ULPI I/Os into IOB registers for best timing
# This minimizes routing delay and improves setup/hold margins
# Input path: PAD -> IBUF -> IOB FF -> fabric
# Output path: fabric -> IOB FF -> OBUF -> PAD
set_property IOB TRUE [get_cells -hierarchical *ulpi_data_in_reg*]
set_property IOB TRUE [get_cells -hierarchical *ulpi_data_out_reg*]
set_property IOB TRUE [get_cells -hierarchical *ulpi_dir_reg*]
set_property IOB TRUE [get_cells -hierarchical *ulpi_nxt_reg*]
set_property IOB TRUE [get_cells -hierarchical *ulpi_stp_reg*]

##-----------------------------------------------------------------------------
## Pin Assignments (Device-specific - update for actual board)
##-----------------------------------------------------------------------------

# NOTE: Pin assignments below are placeholders.
# Update PACKAGE_PIN constraints based on actual board layout.
#
# IMPORTANT: All ULPI signals should be placed in the same I/O bank to ensure:
#   1. Common VCCO voltage (3.3V)
#   2. Minimal skew on data bus
#   3. Clean routing with matched trace lengths
#
# Recommended: Use adjacent pins for ulpi_data[7:0] to minimize skew

# ULPI Clock input (from PHY)
# set_property PACKAGE_PIN xxx [get_ports ulpi_clk]

# ULPI Data bus [7:0] - bidirectional
# Place these on adjacent pins in same bank for minimal skew
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[0]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[1]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[2]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[3]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[4]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[5]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[6]}]
# set_property PACKAGE_PIN xxx [get_ports {ulpi_data[7]}]

# ULPI Control signals
# set_property PACKAGE_PIN xxx [get_ports ulpi_dir]
# set_property PACKAGE_PIN xxx [get_ports ulpi_nxt]
# set_property PACKAGE_PIN xxx [get_ports ulpi_stp]
# set_property PACKAGE_PIN xxx [get_ports ulpi_rst_n]

##-----------------------------------------------------------------------------
## Drive Strength and Slew Rate
##-----------------------------------------------------------------------------

# Output drive strength for ULPI outputs
# Use moderate drive (8mA) to reduce EMI while meeting timing
set_property DRIVE 8 [get_ports {ulpi_data[*]}]
set_property DRIVE 8 [get_ports ulpi_stp]
set_property DRIVE 8 [get_ports ulpi_rst_n]

# Slew rate control
# FAST slew for data and STP to meet 60 MHz timing
# SLOW slew for reset to reduce EMI
set_property SLEW FAST [get_ports {ulpi_data[*]}]
set_property SLEW FAST [get_ports ulpi_stp]
set_property SLEW SLOW [get_ports ulpi_rst_n]

##-----------------------------------------------------------------------------
## Input Termination
##-----------------------------------------------------------------------------

# No pullups/pulldowns needed on ULPI interface
# PHY handles all bus drive states appropriately
# Uncomment if needed for specific board requirements:
# set_property PULLUP true [get_ports ulpi_rst_n]

##-----------------------------------------------------------------------------
## Max Delay Constraints
##-----------------------------------------------------------------------------

# Ensure clock-to-out on ULPI outputs meets PHY requirements
# USB3300 requires valid data within one clock cycle
set_max_delay -from [get_clocks ulpi_clk] -to [get_ports {ulpi_data[*]}] 16.667
set_max_delay -from [get_clocks ulpi_clk] -to [get_ports ulpi_stp] 16.667

##-----------------------------------------------------------------------------
## Data Bus Skew
##-----------------------------------------------------------------------------

# Minimize skew across ULPI data bus bits
# All bits should arrive within 1ns of each other for reliable operation
set_bus_skew -from [get_ports {ulpi_data[*]}] 1.000
set_bus_skew -to [get_ports {ulpi_data[*]}] 1.000

##-----------------------------------------------------------------------------
## Debug and Verification
##-----------------------------------------------------------------------------

# Uncomment to mark ULPI signals for debug with ILA
# set_property MARK_DEBUG true [get_nets u_ulpi_ctrl/ulpi_data_in*]
# set_property MARK_DEBUG true [get_nets u_ulpi_ctrl/ulpi_dir*]
# set_property MARK_DEBUG true [get_nets u_ulpi_ctrl/ulpi_nxt*]
# set_property MARK_DEBUG true [get_nets u_ulpi_ctrl/ulpi_stp*]

##-----------------------------------------------------------------------------
## End of File
##-----------------------------------------------------------------------------
