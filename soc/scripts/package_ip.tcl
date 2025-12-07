#-----------------------------------------------------------------------------
# FluxRipper FDC - IP Packaging Script
#
# Creates a Vivado IP package from the FluxRipper RTL
#
# Usage: vivado -mode batch -source package_ip.tcl
#
# Updated: 2025-12-03 18:30
#-----------------------------------------------------------------------------

# Configuration
set ip_name "fluxripper_fdc"
set ip_version "1.0"
set ip_vendor "fluxripper"
set ip_library "user"

# Paths
set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set rtl_dir [file normalize "$project_dir/../rtl"]
set ip_dir "$project_dir/ip/${ip_name}_${ip_version}"

puts "============================================"
puts "FluxRipper FDC IP Packaging"
puts "============================================"
puts "RTL Directory: $rtl_dir"
puts "IP Directory:  $ip_dir"
puts ""

# Create IP project
create_project -force ip_package $ip_dir/project -part xcsu35p-2sbvb625e

# Add all RTL source files
puts "Adding RTL sources..."
set rtl_files [list \
    "$rtl_dir/top/fluxripper_dual_top.v" \
    "$rtl_dir/axi/axi_fdc_periph_dual.v" \
    "$rtl_dir/axi/axi_stream_flux_dual.v" \
    "$rtl_dir/fdc_core/fdc_core_instance.v" \
    "$rtl_dir/fdc_core/command_fsm.v" \
    "$rtl_dir/fdc_core/motor_controller.v" \
    "$rtl_dir/fdc_core/step_controller.v" \
    "$rtl_dir/data_separator/digital_pll.v" \
    "$rtl_dir/data_separator/nco.v" \
    "$rtl_dir/data_separator/loop_filter.v" \
    "$rtl_dir/data_separator/zone_calculator.v" \
    "$rtl_dir/am_detector/address_mark_detector.v" \
    "$rtl_dir/encoding/mfm_codec.v" \
    "$rtl_dir/encoding/fm_codec.v" \
    "$rtl_dir/encoding/gcr_apple.v" \
    "$rtl_dir/encoding/gcr_cbm.v" \
    "$rtl_dir/encoding/m2fm_codec.v" \
    "$rtl_dir/encoding/tandy_sync.v" \
    "$rtl_dir/encoding/encoding_mux.v" \
    "$rtl_dir/encoding/encoding_detector.v" \
    "$rtl_dir/crc/crc16_ccitt.v" \
    "$rtl_dir/drive_ctrl/index_handler_dual.v" \
    "$rtl_dir/diagnostics/drive_profile_detector.v" \
    "$rtl_dir/diagnostics/flux_analyzer.v" \
]

foreach f $rtl_files {
    if {[file exists $f]} {
        add_files -norecurse $f
        puts "  Added: [file tail $f]"
    } else {
        puts "  WARNING: File not found: $f"
    }
}

# Set top module
set_property top fluxripper_dual_top [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

puts ""
puts "Creating IP package..."

# Create IP from project
ipx::package_project -root_dir $ip_dir -vendor $ip_vendor -library $ip_library \
    -taxonomy /UserIP -import_files -set_current false

# Open the packaged IP
ipx::open_ipxact_file $ip_dir/component.xml

# Set IP properties
set_property vendor $ip_vendor [ipx::current_core]
set_property library $ip_library [ipx::current_core]
set_property name $ip_name [ipx::current_core]
set_property version $ip_version [ipx::current_core]
set_property display_name "FluxRipper FDC" [ipx::current_core]
set_property description "Intel 82077AA Compatible FDC with Flux Capture" [ipx::current_core]
set_property vendor_display_name "FluxRipper Project" [ipx::current_core]
set_property company_url "https://github.com/fluxripper" [ipx::current_core]
set_property supported_families {spartan7 Production artix7 Production kintex7 Production \
    virtex7 Production zynq Production zynquplus Production kintexuplus Production \
    virtexuplus Production artixuplus Production} [ipx::current_core]

puts "Configuring interfaces..."

#-----------------------------------------------------------------------------
# AXI4-Lite Slave Interface
#-----------------------------------------------------------------------------
ipx::add_bus_interface S_AXI [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property interface_mode slave [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]

# Map AXI ports
ipx::add_port_map AWADDR [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_awaddr [ipx::get_port_maps AWADDR -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map AWVALID [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_awvalid [ipx::get_port_maps AWVALID -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map AWREADY [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_awready [ipx::get_port_maps AWREADY -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map WDATA [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_wdata [ipx::get_port_maps WDATA -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map WSTRB [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_wstrb [ipx::get_port_maps WSTRB -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map WVALID [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_wvalid [ipx::get_port_maps WVALID -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map WREADY [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_wready [ipx::get_port_maps WREADY -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map BRESP [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_bresp [ipx::get_port_maps BRESP -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map BVALID [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_bvalid [ipx::get_port_maps BVALID -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map BREADY [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_bready [ipx::get_port_maps BREADY -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map ARADDR [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_araddr [ipx::get_port_maps ARADDR -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map ARVALID [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_arvalid [ipx::get_port_maps ARVALID -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map ARREADY [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_arready [ipx::get_port_maps ARREADY -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map RDATA [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_rdata [ipx::get_port_maps RDATA -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map RRESP [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_rresp [ipx::get_port_maps RRESP -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map RVALID [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_rvalid [ipx::get_port_maps RVALID -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]
ipx::add_port_map RREADY [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
set_property physical_name s_axi_rready [ipx::get_port_maps RREADY -of_objects [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# AXI4-Stream Master Interface A
#-----------------------------------------------------------------------------
ipx::add_bus_interface M_AXIS_A [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property interface_mode master [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]

ipx::add_port_map TDATA [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property physical_name m_axis_a_tdata [ipx::get_port_maps TDATA -of_objects [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]]
ipx::add_port_map TVALID [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property physical_name m_axis_a_tvalid [ipx::get_port_maps TVALID -of_objects [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]]
ipx::add_port_map TREADY [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property physical_name m_axis_a_tready [ipx::get_port_maps TREADY -of_objects [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]]
ipx::add_port_map TLAST [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property physical_name m_axis_a_tlast [ipx::get_port_maps TLAST -of_objects [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]]
ipx::add_port_map TKEEP [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]
set_property physical_name m_axis_a_tkeep [ipx::get_port_maps TKEEP -of_objects [ipx::get_bus_interfaces M_AXIS_A -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# AXI4-Stream Master Interface B
#-----------------------------------------------------------------------------
ipx::add_bus_interface M_AXIS_B [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property interface_mode master [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]

ipx::add_port_map TDATA [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property physical_name m_axis_b_tdata [ipx::get_port_maps TDATA -of_objects [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]]
ipx::add_port_map TVALID [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property physical_name m_axis_b_tvalid [ipx::get_port_maps TVALID -of_objects [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]]
ipx::add_port_map TREADY [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property physical_name m_axis_b_tready [ipx::get_port_maps TREADY -of_objects [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]]
ipx::add_port_map TLAST [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property physical_name m_axis_b_tlast [ipx::get_port_maps TLAST -of_objects [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]]
ipx::add_port_map TKEEP [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]
set_property physical_name m_axis_b_tkeep [ipx::get_port_maps TKEEP -of_objects [ipx::get_bus_interfaces M_AXIS_B -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# Clock Interfaces
#-----------------------------------------------------------------------------
# FDC clock (200 MHz)
ipx::add_bus_interface clk_200mhz [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:signal:clock:1.0 [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]
set_property interface_mode slave [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]
ipx::add_port_map CLK [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]
set_property physical_name clk_200mhz [ipx::get_port_maps CLK -of_objects [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]
set_property value 200000000 [ipx::get_bus_parameters FREQ_HZ -of_objects [ipx::get_bus_interfaces clk_200mhz -of_objects [ipx::current_core]]]

# AXI clock (100 MHz)
ipx::add_bus_interface s_axi_aclk [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:signal:clock:1.0 [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property interface_mode slave [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
ipx::add_port_map CLK [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property physical_name s_axi_aclk [ipx::get_port_maps CLK -of_objects [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property value 100000000 [ipx::get_bus_parameters FREQ_HZ -of_objects [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]]
ipx::add_bus_parameter ASSOCIATED_BUSIF [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property value {S_AXI:M_AXIS_A:M_AXIS_B} [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]]
ipx::add_bus_parameter ASSOCIATED_RESET [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property value s_axi_aresetn [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# Reset Interface
#-----------------------------------------------------------------------------
ipx::add_bus_interface reset_n [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:signal:reset:1.0 [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]
set_property interface_mode slave [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]
ipx::add_port_map RST [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]
set_property physical_name reset_n [ipx::get_port_maps RST -of_objects [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]]
ipx::add_bus_parameter POLARITY [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]
set_property value ACTIVE_LOW [ipx::get_bus_parameters POLARITY -of_objects [ipx::get_bus_interfaces reset_n -of_objects [ipx::current_core]]]

ipx::add_bus_interface s_axi_aresetn [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:signal:reset:1.0 [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]
set_property interface_mode slave [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]
ipx::add_port_map RST [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]
set_property physical_name s_axi_aresetn [ipx::get_port_maps RST -of_objects [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]]
ipx::add_bus_parameter POLARITY [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]
set_property value ACTIVE_LOW [ipx::get_bus_parameters POLARITY -of_objects [ipx::get_bus_interfaces s_axi_aresetn -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# Interrupt Interfaces
#-----------------------------------------------------------------------------
ipx::add_bus_interface irq_fdc_a [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:signal:interrupt_rtl:1.0 [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:signal:interrupt:1.0 [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]
set_property interface_mode master [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]
ipx::add_port_map INTERRUPT [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]
set_property physical_name irq_fdc_a [ipx::get_port_maps INTERRUPT -of_objects [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]]
ipx::add_bus_parameter SENSITIVITY [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]
set_property value LEVEL_HIGH [ipx::get_bus_parameters SENSITIVITY -of_objects [ipx::get_bus_interfaces irq_fdc_a -of_objects [ipx::current_core]]]

ipx::add_bus_interface irq_fdc_b [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:signal:interrupt_rtl:1.0 [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:signal:interrupt:1.0 [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]
set_property interface_mode master [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]
ipx::add_port_map INTERRUPT [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]
set_property physical_name irq_fdc_b [ipx::get_port_maps INTERRUPT -of_objects [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]]
ipx::add_bus_parameter SENSITIVITY [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]
set_property value LEVEL_HIGH [ipx::get_bus_parameters SENSITIVITY -of_objects [ipx::get_bus_interfaces irq_fdc_b -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# Memory Map
#-----------------------------------------------------------------------------
ipx::add_memory_map S_AXI [ipx::current_core]
set_property slave_memory_map_ref S_AXI [ipx::get_bus_interfaces S_AXI -of_objects [ipx::current_core]]
ipx::add_address_block Reg [ipx::get_memory_maps S_AXI -of_objects [ipx::current_core]]
set_property range 256 [ipx::get_address_blocks Reg -of_objects [ipx::get_memory_maps S_AXI -of_objects [ipx::current_core]]]
set_property width 32 [ipx::get_address_blocks Reg -of_objects [ipx::get_memory_maps S_AXI -of_objects [ipx::current_core]]]
set_property usage register [ipx::get_address_blocks Reg -of_objects [ipx::get_memory_maps S_AXI -of_objects [ipx::current_core]]]

#-----------------------------------------------------------------------------
# Finalize
#-----------------------------------------------------------------------------
puts ""
puts "Validating IP..."
ipx::check_integrity [ipx::current_core]

puts "Saving IP..."
ipx::save_core [ipx::current_core]

puts ""
puts "============================================"
puts "IP Packaging Complete!"
puts "============================================"
puts "IP Location: $ip_dir"
puts ""
puts "To use in Vivado:"
puts "  1. Open Vivado"
puts "  2. Settings -> IP -> Repository"
puts "  3. Add: $ip_dir/.."
puts "  4. IP will appear as 'FluxRipper FDC'"
puts ""

close_project
