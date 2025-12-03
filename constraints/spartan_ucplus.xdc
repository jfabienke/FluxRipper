##-----------------------------------------------------------------------------
## FluxRipper Constraints File
## Target: Xilinx Spartan UltraScale+ (UC+)
##
## Updated: 2025-12-02 17:00
##-----------------------------------------------------------------------------

##-----------------------------------------------------------------------------
## Clock Constraints
##-----------------------------------------------------------------------------

# Primary system clock - 200 MHz
create_clock -period 5.000 -name clk_200mhz [get_ports clk_200mhz]

# Derived clocks (if using MMCM/PLL)
# create_generated_clock -name clk_100mhz -source [get_ports clk_200mhz] -divide_by 2 [get_pins mmcm/CLKOUT0]

##-----------------------------------------------------------------------------
## Clock Groups
##-----------------------------------------------------------------------------

# Asynchronous clock domains
# set_clock_groups -asynchronous -group [get_clocks clk_200mhz] -group [get_clocks clk_cpu]

##-----------------------------------------------------------------------------
## Input Delays (Flux input from drive)
##-----------------------------------------------------------------------------

# Flux read data - tight timing for DPLL
set_input_delay -clock clk_200mhz -max 2.000 [get_ports drv*_read_data]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports drv*_read_data]

# Index pulse
set_input_delay -clock clk_200mhz -max 5.000 [get_ports drv*_index]
set_input_delay -clock clk_200mhz -min 0.500 [get_ports drv*_index]

# Drive status signals (less critical)
set_input_delay -clock clk_200mhz -max 10.000 [get_ports drv*_track0]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports drv*_wp]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports drv*_ready]
set_input_delay -clock clk_200mhz -max 10.000 [get_ports drv*_dskchg]

# CPU bus
set_input_delay -clock clk_200mhz -max 5.000 [get_ports addr*]
set_input_delay -clock clk_200mhz -max 5.000 [get_ports cs_n]
set_input_delay -clock clk_200mhz -max 5.000 [get_ports rd_n]
set_input_delay -clock clk_200mhz -max 5.000 [get_ports wr_n]
set_input_delay -clock clk_200mhz -max 5.000 [get_ports data*]

##-----------------------------------------------------------------------------
## Output Delays
##-----------------------------------------------------------------------------

# Step pulse - critical for head positioning
set_output_delay -clock clk_200mhz -max 3.000 [get_ports drv*_step]
set_output_delay -clock clk_200mhz -min 0.500 [get_ports drv*_step]

# Direction - setup before step
set_output_delay -clock clk_200mhz -max 3.000 [get_ports drv*_dir]

# Motor control (relaxed timing)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports drv*_motor]

# Head select
set_output_delay -clock clk_200mhz -max 5.000 [get_ports drv*_head_sel]

# Write signals - critical timing
set_output_delay -clock clk_200mhz -max 2.000 [get_ports drv*_write_gate]
set_output_delay -clock clk_200mhz -max 2.000 [get_ports drv*_write_data]

# CPU outputs
set_output_delay -clock clk_200mhz -max 5.000 [get_ports data*]
set_output_delay -clock clk_200mhz -max 5.000 [get_ports irq]
set_output_delay -clock clk_200mhz -max 5.000 [get_ports drq]

# Diagnostic outputs (relaxed)
set_output_delay -clock clk_200mhz -max 10.000 [get_ports led*]
set_output_delay -clock clk_200mhz -max 10.000 [get_ports pll_locked]
set_output_delay -clock clk_200mhz -max 10.000 [get_ports lock_quality*]
set_output_delay -clock clk_200mhz -max 10.000 [get_ports current_track*]
set_output_delay -clock clk_200mhz -max 10.000 [get_ports sync_acquired]

##-----------------------------------------------------------------------------
## False Paths
##-----------------------------------------------------------------------------

# Reset is asynchronous
set_false_path -from [get_ports reset_n]

# Cross-domain synchronizers (if any)
# set_false_path -to [get_cells -hierarchical *sync_reg*]

##-----------------------------------------------------------------------------
## Multicycle Paths
##-----------------------------------------------------------------------------

# Motor controller paths (slow)
# set_multicycle_path 4 -setup -from [get_cells u_motor_ctrl/*] -to [get_cells u_motor_ctrl/*]
# set_multicycle_path 3 -hold -from [get_cells u_motor_ctrl/*] -to [get_cells u_motor_ctrl/*]

##-----------------------------------------------------------------------------
## I/O Standards
##-----------------------------------------------------------------------------

# System clock
set_property IOSTANDARD LVCMOS33 [get_ports clk_200mhz]

# Reset
set_property IOSTANDARD LVCMOS33 [get_ports reset_n]

# CPU bus
set_property IOSTANDARD LVCMOS33 [get_ports {addr[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports rd_n]
set_property IOSTANDARD LVCMOS33 [get_ports wr_n]
set_property IOSTANDARD LVCMOS33 [get_ports irq]
set_property IOSTANDARD LVCMOS33 [get_ports drq]

# Drive interfaces
set_property IOSTANDARD LVCMOS33 [get_ports drv0_*]
set_property IOSTANDARD LVCMOS33 [get_ports drv1_*]

# Diagnostic outputs
set_property IOSTANDARD LVCMOS33 [get_ports led_*]
set_property IOSTANDARD LVCMOS33 [get_ports pll_locked]
set_property IOSTANDARD LVCMOS33 [get_ports {lock_quality[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {current_track[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports sync_acquired]

##-----------------------------------------------------------------------------
## Bidirectional Data Bus
##-----------------------------------------------------------------------------

# Pullup on data bus (optional)
# set_property PULLUP true [get_ports {data[*]}]

##-----------------------------------------------------------------------------
## Pin Assignments (Device-specific - update for actual device)
##-----------------------------------------------------------------------------

# NOTE: Pin assignments below are placeholders.
# Update for actual Spartan UC+ device and board layout.

# Clock and reset
# set_property PACKAGE_PIN xxx [get_ports clk_200mhz]
# set_property PACKAGE_PIN xxx [get_ports reset_n]

# CPU bus
# set_property PACKAGE_PIN xxx [get_ports {addr[0]}]
# set_property PACKAGE_PIN xxx [get_ports {addr[1]}]
# set_property PACKAGE_PIN xxx [get_ports {addr[2]}]
# ... etc

##-----------------------------------------------------------------------------
## Configuration
##-----------------------------------------------------------------------------

# Configuration mode
# set_property CONFIG_MODE SPIx4 [current_design]
# set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# Configuration voltage
# set_property CONFIG_VOLTAGE 3.3 [current_design]
# set_property CFGBVS VCCO [current_design]

##-----------------------------------------------------------------------------
## Power Optimization
##-----------------------------------------------------------------------------

# Enable low power mode for unused I/Os
# set_property BITSTREAM.CONFIG.UNUSEDIOB PULLDOWN [current_design]

##-----------------------------------------------------------------------------
## Debug
##-----------------------------------------------------------------------------

# Mark nets for debug (ILA insertion)
# set_property MARK_DEBUG true [get_nets u_dpll/phase_accum*]
# set_property MARK_DEBUG true [get_nets u_am_detector/shift_reg*]
