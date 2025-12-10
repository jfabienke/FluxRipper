# FluxRipper Integration Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../rtl
COMMON_DIR = ../common

# DSP chain sources
SRC_DSP = $(RTL_DIR)/dsp/fir_flux_filter.v \
          $(RTL_DIR)/dsp/adaptive_equalizer.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(RTL_DIR)/dsp -I $(COMMON_DIR)

.PHONY: all clean

all: test_dsp_chain

#-----------------------------------------------------------------------------
# DSP Chain Integration Test
#-----------------------------------------------------------------------------
test_dsp_chain: tb_dsp_chain.vvp
	@echo "Running DSP Chain Integration tests..."
	$(VVP) $<

tb_dsp_chain.vvp: tb_dsp_chain.v $(SRC_DSP)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_DSP) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
