# FluxRipper Data Separator Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/data_separator
COMMON_DIR = ../../common

# Source files
SRC_NCO = $(RTL_DIR)/nco.v
SRC_PHASE_DET = $(RTL_DIR)/phase_detector.v
SRC_LOOP_FILTER = $(RTL_DIR)/loop_filter.v
SRC_EDGE_DET = $(RTL_DIR)/edge_detector.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_nco test_phase_detector

#-----------------------------------------------------------------------------
# NCO Test
#-----------------------------------------------------------------------------
test_nco: tb_nco.vvp
	@echo "Running NCO tests..."
	$(VVP) $<

tb_nco.vvp: tb_nco.v $(SRC_NCO)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_NCO) $<

#-----------------------------------------------------------------------------
# Phase Detector Test
#-----------------------------------------------------------------------------
test_phase_detector: tb_phase_detector.vvp
	@echo "Running Phase Detector tests..."
	$(VVP) $<

tb_phase_detector.vvp: tb_phase_detector.v $(SRC_PHASE_DET)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_PHASE_DET) $<

#-----------------------------------------------------------------------------
# Loop Filter Test
#-----------------------------------------------------------------------------
test_loop_filter: tb_loop_filter.vvp
	@echo "Running Loop Filter tests..."
	$(VVP) $<

tb_loop_filter.vvp: tb_loop_filter.v $(SRC_LOOP_FILTER)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_LOOP_FILTER) $<

#-----------------------------------------------------------------------------
# Edge Detector Test
#-----------------------------------------------------------------------------
test_edge_detector: tb_edge_detector.vvp
	@echo "Running Edge Detector tests..."
	$(VVP) $<

tb_edge_detector.vvp: tb_edge_detector.v $(SRC_EDGE_DET)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_EDGE_DET) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
