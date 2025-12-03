##-----------------------------------------------------------------------------
## FluxRipper Dual Shugart Interface Constraints
## Target: AMD Spartan UltraScale+ SCU35 Evaluation Kit (XCSU35P-2SBVB625E)
##
## Dual Shugart Interface Pin Mapping:
##   - Header 1 (J3): Interface A - Drives 0 & 1
##   - Header 2 (J4): Interface B - Drives 2 & 3
##
## Updated: 2025-12-03 21:05
##-----------------------------------------------------------------------------

##=============================================================================
## Clock Constraints
##=============================================================================

# Primary system clock - 200 MHz (from onboard oscillator)
create_clock -period 5.000 -name clk_200mhz [get_ports clk_200mhz]

# AXI clock - 100 MHz (generated from MMCM)
create_generated_clock -name aclk -source [get_ports clk_200mhz] \
    -divide_by 2 [get_pins u_mmcm/CLKOUT0]

##=============================================================================
## Clock Domain Crossings
##=============================================================================

# Asynchronous clock groups (FDC domain vs AXI domain if separate)
# set_clock_groups -asynchronous \
#     -group [get_clocks clk_200mhz] \
#     -group [get_clocks aclk]

##=============================================================================
## Interface A - RPi Header 1 (J3) - Drives 0 & 1
##=============================================================================

## SCU35 Header 1 Pin Mapping (RPi 40-pin compatible)
## GPIO pins directly accessible on J3

# Step pulse - Interface A
set_property PACKAGE_PIN A12 [get_ports if_a_step]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_step]

# Direction - Interface A
set_property PACKAGE_PIN B12 [get_ports if_a_dir]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_dir]

# Motor enable drive 0 - Interface A
set_property PACKAGE_PIN A13 [get_ports if_a_motor_0]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_motor_0]

# Motor enable drive 1 - Interface A
set_property PACKAGE_PIN B13 [get_ports if_a_motor_1]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_motor_1]

# Head select - Interface A
set_property PACKAGE_PIN C12 [get_ports if_a_head_sel]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_head_sel]

# Write gate - Interface A
set_property PACKAGE_PIN D12 [get_ports if_a_write_gate]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_write_gate]

# Write data - Interface A
set_property PACKAGE_PIN C13 [get_ports if_a_write_data]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_write_data]

# Drive select (active low, directly drives Shugart DS0/DS1) - Interface A
set_property PACKAGE_PIN D13 [get_ports if_a_drive_sel]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_drive_sel]

# Read data - Interface A (high-speed input)
set_property PACKAGE_PIN A14 [get_ports if_a_read_data]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_read_data]
set_property IBUF_LOW_PWR FALSE [get_ports if_a_read_data]

# Index pulse - Interface A
set_property PACKAGE_PIN B14 [get_ports if_a_index]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_index]

# Track 0 - Interface A
set_property PACKAGE_PIN C14 [get_ports if_a_track0]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_track0]

# Write protect - Interface A
set_property PACKAGE_PIN D14 [get_ports if_a_wp]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_wp]

# Ready - Interface A
set_property PACKAGE_PIN A15 [get_ports if_a_ready]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_ready]

# Disk change - Interface A
set_property PACKAGE_PIN B15 [get_ports if_a_dskchg]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_dskchg]

##-----------------------------------------------------------------------------
## Extended Drive Control - Interface A (8" / 5.25" HD / Hard-Sectored Support)
##-----------------------------------------------------------------------------

# HEAD_LOAD - For 8" drives with solenoid-actuated heads (50-pin Shugart pin 4)
set_property PACKAGE_PIN C15 [get_ports if_a_head_load]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_head_load]

# /TG43 - Track Greater Than 43 (5.25" HD write precompensation, pin 2)
set_property PACKAGE_PIN D15 [get_ports if_a_tg43]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_tg43]

# DENSITY - DD/HD mode indicator (low = DD, high = HD)
set_property PACKAGE_PIN A16 [get_ports if_a_density]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_density]

# /SECTOR - Hard-sector pulse input (50-pin Shugart pin 28)
# For NorthStar, Vector Graphics, S-100 hard-sectored drives
set_property PACKAGE_PIN B16 [get_ports if_a_sector]
set_property IOSTANDARD LVCMOS33 [get_ports if_a_sector]

##=============================================================================
## Interface B - RPi Header 2 (J4) - Drives 2 & 3
##=============================================================================

## SCU35 Header 2 Pin Mapping (RPi 40-pin compatible)
## GPIO pins directly accessible on J4

# Step pulse - Interface B
set_property PACKAGE_PIN E12 [get_ports if_b_step]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_step]

# Direction - Interface B
set_property PACKAGE_PIN F12 [get_ports if_b_dir]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_dir]

# Motor enable drive 0 - Interface B (physical drive 2)
set_property PACKAGE_PIN E13 [get_ports if_b_motor_0]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_motor_0]

# Motor enable drive 1 - Interface B (physical drive 3)
set_property PACKAGE_PIN F13 [get_ports if_b_motor_1]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_motor_1]

# Head select - Interface B
set_property PACKAGE_PIN G12 [get_ports if_b_head_sel]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_head_sel]

# Write gate - Interface B
set_property PACKAGE_PIN H12 [get_ports if_b_write_gate]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_write_gate]

# Write data - Interface B
set_property PACKAGE_PIN G13 [get_ports if_b_write_data]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_write_data]

# Drive select - Interface B
set_property PACKAGE_PIN H13 [get_ports if_b_drive_sel]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_drive_sel]

# Read data - Interface B (high-speed input)
set_property PACKAGE_PIN E14 [get_ports if_b_read_data]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_read_data]
set_property IBUF_LOW_PWR FALSE [get_ports if_b_read_data]

# Index pulse - Interface B
set_property PACKAGE_PIN F14 [get_ports if_b_index]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_index]

# Track 0 - Interface B
set_property PACKAGE_PIN G14 [get_ports if_b_track0]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_track0]

# Write protect - Interface B
set_property PACKAGE_PIN H14 [get_ports if_b_wp]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_wp]

# Ready - Interface B
set_property PACKAGE_PIN E15 [get_ports if_b_ready]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_ready]

# Disk change - Interface B
set_property PACKAGE_PIN F15 [get_ports if_b_dskchg]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_dskchg]

##-----------------------------------------------------------------------------
## Extended Drive Control - Interface B (8" / 5.25" HD / Hard-Sectored Support)
##-----------------------------------------------------------------------------

# HEAD_LOAD - For 8" drives with solenoid-actuated heads (50-pin Shugart pin 4)
set_property PACKAGE_PIN G15 [get_ports if_b_head_load]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_head_load]

# /TG43 - Track Greater Than 43 (5.25" HD write precompensation, pin 2)
set_property PACKAGE_PIN H15 [get_ports if_b_tg43]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_tg43]

# DENSITY - DD/HD mode indicator (low = DD, high = HD)
set_property PACKAGE_PIN E16 [get_ports if_b_density]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_density]

# /SECTOR - Hard-sector pulse input (50-pin Shugart pin 28)
# For NorthStar, Vector Graphics, S-100 hard-sectored drives
set_property PACKAGE_PIN F16 [get_ports if_b_sector]
set_property IOSTANDARD LVCMOS33 [get_ports if_b_sector]

##=============================================================================
## System Signals
##=============================================================================

# System clock input (200 MHz oscillator on board)
set_property PACKAGE_PIN R4 [get_ports clk_200mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_200mhz]

# Active-low reset button
set_property PACKAGE_PIN T4 [get_ports reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports reset_n]

##=============================================================================
## Status LEDs
##=============================================================================

# Activity LED - Interface A
set_property PACKAGE_PIN J15 [get_ports led_activity_a]
set_property IOSTANDARD LVCMOS33 [get_ports led_activity_a]
set_property DRIVE 8 [get_ports led_activity_a]

# Activity LED - Interface B
set_property PACKAGE_PIN K15 [get_ports led_activity_b]
set_property IOSTANDARD LVCMOS33 [get_ports led_activity_b]
set_property DRIVE 8 [get_ports led_activity_b]

# Error LED (shared)
set_property PACKAGE_PIN L15 [get_ports led_error]
set_property IOSTANDARD LVCMOS33 [get_ports led_error]
set_property DRIVE 8 [get_ports led_error]

# PLL Lock LED - Interface A
set_property PACKAGE_PIN M15 [get_ports led_pll_lock_a]
set_property IOSTANDARD LVCMOS33 [get_ports led_pll_lock_a]
set_property DRIVE 8 [get_ports led_pll_lock_a]

# PLL Lock LED - Interface B
set_property PACKAGE_PIN N15 [get_ports led_pll_lock_b]
set_property IOSTANDARD LVCMOS33 [get_ports led_pll_lock_b]
set_property DRIVE 8 [get_ports led_pll_lock_b]

##=============================================================================
## Timing Constraints - Interface A
##=============================================================================

# Read data - tight timing for DPLL (flux transitions)
set_input_delay -clock clk_200mhz -max 2.000 [get_ports if_a_read_data]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports if_a_read_data]

# Index pulse - moderate timing
set_input_delay -clock clk_200mhz -max 5.000 [get_ports if_a_index]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports if_a_index]

# Status signals - relaxed timing
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_a_track0]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_a_wp]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_a_ready]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_a_dskchg]

# Step pulse - critical for head positioning
set_output_delay -clock clk_200mhz -max 3.000 [get_ports if_a_step]
set_output_delay -clock clk_200mhz -min 0.500 [get_ports if_a_step]

# Direction - must be stable before step
set_output_delay -clock clk_200mhz -max 3.000 [get_ports if_a_dir]

# Motor control - relaxed timing
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_a_motor_0]
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_a_motor_1]

# Head select
set_output_delay -clock clk_200mhz -max 5.000 [get_ports if_a_head_sel]

# Write signals - critical timing
set_output_delay -clock clk_200mhz -max 2.000 [get_ports if_a_write_gate]
set_output_delay -clock clk_200mhz -max 2.000 [get_ports if_a_write_data]

# Drive select - moderate timing
set_output_delay -clock clk_200mhz -max 5.000 [get_ports if_a_drive_sel]

# Extended signals - Interface A
# HEAD_LOAD - moderate timing (head settle time is ms-scale)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_a_head_load]

# /TG43 - relaxed timing (changes only on track transitions)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_a_tg43]

# DENSITY - relaxed timing (changes only on mode switch)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_a_density]

# /SECTOR - moderate timing for hard-sector pulse capture
set_input_delay -clock clk_200mhz -max 5.000 [get_ports if_a_sector]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports if_a_sector]

##=============================================================================
## Timing Constraints - Interface B
##=============================================================================

# Read data - tight timing for DPLL (flux transitions)
set_input_delay -clock clk_200mhz -max 2.000 [get_ports if_b_read_data]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports if_b_read_data]

# Index pulse - moderate timing
set_input_delay -clock clk_200mhz -max 5.000 [get_ports if_b_index]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports if_b_index]

# Status signals - relaxed timing
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_b_track0]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_b_wp]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_b_ready]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports if_b_dskchg]

# Step pulse - critical for head positioning
set_output_delay -clock clk_200mhz -max 3.000 [get_ports if_b_step]
set_output_delay -clock clk_200mhz -min 0.500 [get_ports if_b_step]

# Direction - must be stable before step
set_output_delay -clock clk_200mhz -max 3.000 [get_ports if_b_dir]

# Motor control - relaxed timing
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_b_motor_0]
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_b_motor_1]

# Head select
set_output_delay -clock clk_200mhz -max 5.000 [get_ports if_b_head_sel]

# Write signals - critical timing
set_output_delay -clock clk_200mhz -max 2.000 [get_ports if_b_write_gate]
set_output_delay -clock clk_200mhz -max 2.000 [get_ports if_b_write_data]

# Drive select - moderate timing
set_output_delay -clock clk_200mhz -max 5.000 [get_ports if_b_drive_sel]

# Extended signals - Interface B
# HEAD_LOAD - moderate timing (head settle time is ms-scale)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_b_head_load]

# /TG43 - relaxed timing (changes only on track transitions)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_b_tg43]

# DENSITY - relaxed timing (changes only on mode switch)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports if_b_density]

# /SECTOR - moderate timing for hard-sector pulse capture
set_input_delay -clock clk_200mhz -max 5.000 [get_ports if_b_sector]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports if_b_sector]

##=============================================================================
## False Paths
##=============================================================================

# Reset is asynchronous
set_false_path -from [get_ports reset_n]

# Cross-domain synchronizers (3-stage sync chains)
set_false_path -to [get_cells -hierarchical *_sync_reg[0]]

# LED outputs (display only, not timing critical)
set_false_path -to [get_ports led_*]

##=============================================================================
## Multicycle Paths
##=============================================================================

# Motor controller paths (slow state machine, runs at ~1ms rate)
# set_multicycle_path 4 -setup -from [get_cells u_motor_ctrl/*] -to [get_cells u_motor_ctrl/*]
# set_multicycle_path 3 -hold -from [get_cells u_motor_ctrl/*] -to [get_cells u_motor_ctrl/*]

##=============================================================================
## Physical Constraints - Dual DPLL Placement
##=============================================================================

# Place FDC Core A and FDC Core B in separate regions to minimize crosstalk
# and help with timing closure for dual DPLLs

# FDC Core A - Left side of device
# create_pblock pblock_fdc_a
# add_cells_to_pblock [get_pblocks pblock_fdc_a] [get_cells u_fdc_a/*]
# resize_pblock [get_pblocks pblock_fdc_a] -add {SLICE_X0Y0:SLICE_X49Y149}

# FDC Core B - Right side of device
# create_pblock pblock_fdc_b
# add_cells_to_pblock [get_pblocks pblock_fdc_b] [get_cells u_fdc_b/*]
# resize_pblock [get_pblocks pblock_fdc_b] -add {SLICE_X50Y0:SLICE_X99Y149}

##=============================================================================
## Configuration
##=============================================================================

# Configuration mode (SPI x4 for fast configuration)
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# Configuration voltage
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# Enable bitstream compression
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

##=============================================================================
## Power Optimization
##=============================================================================

# Pull unused I/Os low to reduce power
set_property BITSTREAM.CONFIG.UNUSEDIOB PULLDOWN [current_design]

##=============================================================================
## Debug (ILA Insertion Points)
##=============================================================================

# Mark key signals for debug with ILA
# Uncomment as needed during hardware bring-up

# DPLL phase accumulator - Interface A
# set_property MARK_DEBUG true [get_nets u_fdc_a/u_dpll/phase_accum*]

# DPLL phase accumulator - Interface B
# set_property MARK_DEBUG true [get_nets u_fdc_b/u_dpll/phase_accum*]

# Flux capture timestamp - Interface A
# set_property MARK_DEBUG true [get_nets u_fdc_a/flux_timestamp*]

# Flux capture timestamp - Interface B
# set_property MARK_DEBUG true [get_nets u_fdc_b/flux_timestamp*]

# AXI-Stream data paths
# set_property MARK_DEBUG true [get_nets u_axis_flux/m_axis_a_tdata*]
# set_property MARK_DEBUG true [get_nets u_axis_flux/m_axis_b_tdata*]

##=============================================================================
## Level Shifter Interface Notes
##=============================================================================
##
## External level shifters required between FPGA (3.3V LVCMOS) and
## Shugart interface (5V TTL):
##
## Outputs (FPGA -> Drive): Use 74AHCT125 (quad 3.3V->5V buffer)
##   - 2x per interface for 8 output signals
##   - OE active low, directly from FPGA or active high for always-on
##
## Inputs (Drive -> FPGA): Use 74LVC245 (octal 5V->3.3V buffer)
##   - 1x per interface for 5-6 input signals
##   - Direction pin tied for unidirectional operation
##
## BOM per interface:
##   - 2x 74AHCT125 (outputs)
##   - 1x 74LVC245 (inputs)
##   - Decoupling capacitors (0.1uF per chip)
##   - 34-pin IDC header for Shugart cable
##
##=============================================================================
