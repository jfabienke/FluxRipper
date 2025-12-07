#------------------------------------------------------------------------------
# FluxRipper RTL Synthesis Script
# Target: AMD Spartan UltraScale+ (xcsu35p-2sbvb625e)
#
# Usage: vivado -mode batch -source synth_fluxripper.tcl
#
# Created: 2025-12-07 23:40
#------------------------------------------------------------------------------

set script_dir [file dirname [info script]]
set project_name "fluxripper_rtl"
set project_dir "$script_dir/../vivado_proj"
set rtl_dir "$script_dir/../../rtl"
set constraints_dir "$script_dir/../constraints"
set part "xcsu35p-2sbvb625e"

puts "=============================================="
puts "  FluxRipper RTL Synthesis"
puts "  Target: $part"
puts "=============================================="

#------------------------------------------------------------------------------
# Create Project
#------------------------------------------------------------------------------
puts "Creating project..."
create_project $project_name $project_dir -part $part -force

set_property target_language Verilog [current_project]

# Enable Verilog 2001 and define XILINX_FPGA for synthesis
set_property verilog_define {XILINX_FPGA=1} [current_fileset]

#------------------------------------------------------------------------------
# Add RTL Sources
#------------------------------------------------------------------------------
puts "Adding RTL sources..."

# Top level
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/top/*.v]

# Debug subsystem
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/debug/*.v]

# Bus fabric
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/bus/*.v]

# Clocking
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/clocking/clock_reset_mgr.v]

# Peripherals
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/disk/*.v]
add_files -fileset sources_1 [glob -nocomplain $rtl_dir/usb/*.v]

# Set top module
set_property top fluxripper_top [current_fileset]

# List all added files
puts "RTL files added:"
foreach f [get_files -filter {FILE_TYPE == "Verilog" || FILE_TYPE == "SystemVerilog"}] {
    puts "  [file tail $f]"
}

#------------------------------------------------------------------------------
# Add Constraints
#------------------------------------------------------------------------------
puts "Adding constraints..."

# Add timing constraints
if {[file exists $constraints_dir/fluxripper_timing.xdc]} {
    add_files -fileset constrs_1 $constraints_dir/fluxripper_timing.xdc
    puts "  Added: fluxripper_timing.xdc"
} else {
    puts "  WARNING: fluxripper_timing.xdc not found!"
}

# Add pin constraints
if {[file exists $constraints_dir/fluxripper_pinout.xdc]} {
    add_files -fileset constrs_1 $constraints_dir/fluxripper_pinout.xdc
    puts "  Added: fluxripper_pinout.xdc"
} else {
    puts "  WARNING: fluxripper_pinout.xdc not found!"
}

#------------------------------------------------------------------------------
# Synthesis Settings
#------------------------------------------------------------------------------
puts "Configuring synthesis..."

# Use rebuilt hierarchy for better optimization
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]

# Keep equivalent registers for debug signals
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]

# FSM encoding for reliability
set_property STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION one_hot [get_runs synth_1]

#------------------------------------------------------------------------------
# Implementation Settings
#------------------------------------------------------------------------------
puts "Configuring implementation..."

# Optimize for performance
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

#------------------------------------------------------------------------------
# Run Synthesis
#------------------------------------------------------------------------------
puts ""
puts "Running synthesis..."
puts "=============================================="

launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    open_run synth_1
    report_timing_summary -file $project_dir/synth_timing.rpt
    exit 1
}

puts "Synthesis complete!"

# Open synthesis run and report
open_run synth_1
report_utilization -file $project_dir/synth_utilization.rpt
report_timing_summary -file $project_dir/synth_timing.rpt
puts "Reports saved to $project_dir/"

#------------------------------------------------------------------------------
# Run Implementation
#------------------------------------------------------------------------------
puts ""
puts "Running implementation..."
puts "=============================================="

launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    open_run impl_1
    report_timing_summary -file $project_dir/impl_timing.rpt
    exit 1
}

puts "Implementation complete!"

#------------------------------------------------------------------------------
# Generate Bitstream
#------------------------------------------------------------------------------
puts ""
puts "Generating bitstream..."
puts "=============================================="

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

#------------------------------------------------------------------------------
# Final Reports
#------------------------------------------------------------------------------
puts ""
puts "Generating final reports..."

open_run impl_1

report_timing_summary -file $project_dir/timing_summary.rpt
report_utilization -file $project_dir/utilization.rpt
report_power -file $project_dir/power.rpt
report_drc -file $project_dir/drc.rpt

# Check for timing violations
set timing_slack [get_property SLACK [get_timing_paths -max_paths 1]]
if {$timing_slack < 0} {
    puts ""
    puts "WARNING: Timing violations detected! Slack = ${timing_slack}ns"
    puts "Review timing_summary.rpt for details."
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
puts ""
puts "=============================================="
puts "  FluxRipper Synthesis Complete!"
puts "=============================================="
puts ""
puts "Bitstream: $project_dir/fluxripper_rtl.runs/impl_1/fluxripper_top.bit"
puts ""
puts "Reports:"
puts "  - $project_dir/timing_summary.rpt"
puts "  - $project_dir/utilization.rpt"
puts "  - $project_dir/power.rpt"
puts "  - $project_dir/drc.rpt"
puts ""
puts "Next step: Program FPGA with program_fpga.tcl"
puts ""
