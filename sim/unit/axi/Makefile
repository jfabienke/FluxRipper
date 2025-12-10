# FluxRipper AXI Subsystem Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/axi
COMMON_DIR = ../../common

# Source files
SRC_STREAM = $(RTL_DIR)/axi_stream_flux.v
SRC_FDC = $(RTL_DIR)/axi_fdc_periph.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_axi_stream test_axi_fdc

#-----------------------------------------------------------------------------
# AXI-Stream Flux Test
#-----------------------------------------------------------------------------
test_axi_stream: tb_axi_stream_flux.vvp
	@echo "Running AXI-Stream Flux tests..."
	$(VVP) $<

tb_axi_stream_flux.vvp: tb_axi_stream_flux.v $(SRC_STREAM)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_STREAM) $<

#-----------------------------------------------------------------------------
# AXI FDC Peripheral Test
#-----------------------------------------------------------------------------
test_axi_fdc: tb_axi_fdc_periph.vvp
	@echo "Running AXI FDC Peripheral tests..."
	$(VVP) $<

tb_axi_fdc_periph.vvp: tb_axi_fdc_periph.v $(SRC_FDC)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_FDC) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
