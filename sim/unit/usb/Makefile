# FluxRipper USB Subsystem Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/usb
COMMON_DIR = ../../common

# Source files
SRC_ULPI = $(RTL_DIR)/ulpi_wrapper_v2.v $(RTL_DIR)/ulpi_phy.v
SRC_HS_NEG = $(RTL_DIR)/usb_hs_negotiator.v
SRC_CORE = $(RTL_DIR)/usb_device_core_v2.v
SRC_CTRL_EP = $(RTL_DIR)/usb_control_ep.v
SRC_BULK_EP = $(RTL_DIR)/usb_bulk_ep.v
SRC_CDC_EP = $(RTL_DIR)/usb_cdc_ep.v
SRC_DESC = $(RTL_DIR)/usb_descriptor_rom.v
SRC_GW = $(RTL_DIR)/gw_protocol.v
SRC_HFE = $(RTL_DIR)/hfe_protocol.v
SRC_KF = $(RTL_DIR)/kf_protocol.v
SRC_NATIVE = $(RTL_DIR)/native_protocol.v
SRC_MSC = $(RTL_DIR)/msc_scsi_engine.v $(RTL_DIR)/msc_sector_buffer.v $(RTL_DIR)/drive_lun_mapper.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_ulpi test_hs_negotiator test_control_ep test_bulk_ep test_device_core test_cdc_ep test_gw_protocol test_kf_protocol

#-----------------------------------------------------------------------------
# ULPI Wrapper Test
#-----------------------------------------------------------------------------
test_ulpi: tb_ulpi_wrapper_v2.vvp
	@echo "Running ULPI Wrapper tests..."
	$(VVP) $<

tb_ulpi_wrapper_v2.vvp: tb_ulpi_wrapper_v2.v $(SRC_ULPI)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_ULPI) $<

#-----------------------------------------------------------------------------
# HS Negotiator Test
#-----------------------------------------------------------------------------
test_hs_negotiator: tb_usb_hs_negotiator.vvp
	@echo "Running HS Negotiator tests..."
	$(VVP) $<

tb_usb_hs_negotiator.vvp: tb_usb_hs_negotiator.v $(SRC_HS_NEG)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_HS_NEG) $<

#-----------------------------------------------------------------------------
# Control Endpoint Test
#-----------------------------------------------------------------------------
test_control_ep: tb_usb_control_ep.vvp
	@echo "Running Control Endpoint tests..."
	$(VVP) $<

tb_usb_control_ep.vvp: tb_usb_control_ep.v $(SRC_CTRL_EP)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_CTRL_EP) $<

#-----------------------------------------------------------------------------
# Bulk Endpoint Test
#-----------------------------------------------------------------------------
test_bulk_ep: tb_usb_bulk_ep.vvp
	@echo "Running Bulk Endpoint tests..."
	$(VVP) $<

tb_usb_bulk_ep.vvp: tb_usb_bulk_ep.v $(SRC_BULK_EP)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_BULK_EP) $<

#-----------------------------------------------------------------------------
# Descriptor ROM Test
#-----------------------------------------------------------------------------
test_descriptor_rom: tb_usb_descriptor_rom.vvp
	@echo "Running Descriptor ROM tests..."
	$(VVP) $<

tb_usb_descriptor_rom.vvp: tb_usb_descriptor_rom.v $(SRC_DESC)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_DESC) $<

#-----------------------------------------------------------------------------
# Device Core Test
#-----------------------------------------------------------------------------
test_device_core: tb_usb_device_core_v2.vvp
	@echo "Running Device Core tests..."
	$(VVP) $<

tb_usb_device_core_v2.vvp: tb_usb_device_core_v2.v $(SRC_CORE)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_CORE) $<

#-----------------------------------------------------------------------------
# CDC Endpoint Test
#-----------------------------------------------------------------------------
test_cdc_ep: tb_usb_cdc_ep.vvp
	@echo "Running CDC Endpoint tests..."
	$(VVP) $<

tb_usb_cdc_ep.vvp: tb_usb_cdc_ep.v $(SRC_CDC_EP)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_CDC_EP) $<

#-----------------------------------------------------------------------------
# Greaseweazle Protocol Test
#-----------------------------------------------------------------------------
test_gw_protocol: tb_gw_protocol.vvp
	@echo "Running Greaseweazle Protocol tests..."
	$(VVP) $<

tb_gw_protocol.vvp: tb_gw_protocol.v $(SRC_GW)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_GW) $<

#-----------------------------------------------------------------------------
# KryoFlux Protocol Test
#-----------------------------------------------------------------------------
test_kf_protocol: tb_kf_protocol.vvp
	@echo "Running KryoFlux Protocol tests..."
	$(VVP) $<

tb_kf_protocol.vvp: tb_kf_protocol.v $(SRC_KF)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_KF) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
