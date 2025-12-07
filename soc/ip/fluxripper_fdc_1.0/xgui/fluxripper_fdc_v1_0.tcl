#-----------------------------------------------------------------------------
# FluxRipper FDC - Vivado IP GUI Customization
#
# Defines the IP customization GUI for the Vivado IP Integrator
#
# Updated: 2025-12-03 18:30
#-----------------------------------------------------------------------------

# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"

  #------ Page: General ------
  set General [ipgui::add_page $IPINST -name "General"]

  ipgui::add_static_text $IPINST -name "Description" -parent ${General} -text {
    FluxRipper FDC - Intel 82077AA Compatible Floppy Disk Controller

    This IP provides a register-compatible implementation of the Intel 82077AA
    floppy disk controller with integrated flux capture and auto-detection.

    Features:
    - Dual Shugart interface (4 drives total)
    - AXI4-Lite register interface
    - AXI4-Stream flux capture output
    - Auto-detection of RPM, data rate, encoding
    - Support for MFM, FM, GCR, M2FM encodings
    - Macintosh variable-speed GCR support

    Clock Requirements:
    - clk_200mhz: 200 MHz FDC core clock
    - s_axi_aclk: 100 MHz AXI clock (typical)

    Memory Map:
    - 0x00-0x2C: 82077AA compatible registers
    - 0x30-0x7C: FluxRipper extensions
  }
}

proc update_PARAM_VALUE.Component_Name { PARAM_VALUE.Component_Name } {
	# Procedure called to update Component_Name
}

proc validate_PARAM_VALUE.Component_Name { PARAM_VALUE.Component_Name } {
	# Procedure called to validate Component_Name
	return true
}

proc update_MODELPARAM_VALUE.Component_Name { MODELPARAM_VALUE.Component_Name PARAM_VALUE.Component_Name } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.Component_Name}] ${MODELPARAM_VALUE.Component_Name}
}
