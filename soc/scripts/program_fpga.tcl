#------------------------------------------------------------------------------
# FluxRipper FPGA Programming Script
# Target: AMD Spartan UltraScale+ (xcsu35p-2sbvb625e)
#
# Usage: vivado -mode batch -source program_fpga.tcl
#        vivado -mode batch -source program_fpga.tcl -tclargs <bitstream_path>
#
# Created: 2025-12-07 23:45
#------------------------------------------------------------------------------

set script_dir [file dirname [info script]]
set project_dir "$script_dir/../vivado_proj"

# Get bitstream path from argument or use default
if {$argc > 0} {
    set bitstream [lindex $argv 0]
} else {
    set bitstream "$project_dir/fluxripper_rtl.runs/impl_1/fluxripper_top.bit"
}

puts "=============================================="
puts "  FluxRipper FPGA Programming"
puts "=============================================="
puts ""
puts "Bitstream: $bitstream"
puts ""

#------------------------------------------------------------------------------
# Verify Bitstream Exists
#------------------------------------------------------------------------------
if {![file exists $bitstream]} {
    puts "ERROR: Bitstream not found: $bitstream"
    puts ""
    puts "Run synthesis first:"
    puts "  vivado -mode batch -source synth_fluxripper.tcl"
    exit 1
}

#------------------------------------------------------------------------------
# Connect to Hardware
#------------------------------------------------------------------------------
puts "Connecting to hardware server..."

open_hw_manager

# Try to connect to local hardware server
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    puts "Starting local hardware server..."
    connect_hw_server -url localhost:3121 -allow_non_jtag
}

puts "Hardware server connected."

#------------------------------------------------------------------------------
# Open Target
#------------------------------------------------------------------------------
puts "Opening hardware target..."

# Get available targets
set targets [get_hw_targets]

if {[llength $targets] == 0} {
    puts "ERROR: No hardware targets found!"
    puts ""
    puts "Check that:"
    puts "  1. FPGA board is connected via USB"
    puts "  2. JTAG drivers are installed"
    puts "  3. Board is powered on"
    close_hw_manager
    exit 1
}

puts "Found targets: $targets"

# Open first target
open_hw_target [lindex $targets 0]

#------------------------------------------------------------------------------
# Get Device
#------------------------------------------------------------------------------
set devices [get_hw_devices]

if {[llength $devices] == 0} {
    puts "ERROR: No devices found on target!"
    close_hw_target
    close_hw_manager
    exit 1
}

puts "Found devices: $devices"

# Find our Spartan UltraScale+ device
set target_device ""
foreach dev $devices {
    set part [get_property PART $dev]
    if {[string match "*su*" $part] || [string match "*xcsu*" $part]} {
        set target_device $dev
        break
    }
}

if {$target_device == ""} {
    # Use first device if no specific match
    set target_device [lindex $devices 0]
}

puts "Using device: $target_device"

# Set current device
current_hw_device $target_device

#------------------------------------------------------------------------------
# Program Device
#------------------------------------------------------------------------------
puts ""
puts "Programming FPGA..."

# Set programming file
set_property PROGRAM.FILE $bitstream $target_device

# Program the device
if {[catch {program_hw_devices $target_device} err]} {
    puts "ERROR: Programming failed: $err"
    close_hw_target
    close_hw_manager
    exit 1
}

puts "Programming complete!"

#------------------------------------------------------------------------------
# Verify
#------------------------------------------------------------------------------
puts ""
puts "Verifying..."

# Refresh device status
refresh_hw_device $target_device

# Check DONE pin
set done_status [get_property REGISTER.CONFIG_STATUS $target_device]
puts "Config status: $done_status"

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------
close_hw_target
close_hw_manager

puts ""
puts "=============================================="
puts "  FluxRipper FPGA Programming Complete!"
puts "=============================================="
puts ""
puts "Next step: Test JTAG with OpenOCD:"
puts "  openocd -f debug/openocd_fluxripper.cfg -c \"init; scan_chain; shutdown\""
puts ""
