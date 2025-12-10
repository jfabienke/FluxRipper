# FluxRipper Bus Subsystem Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/bus
COMMON_DIR = ../../common

# Source files
SRC_BUS = $(RTL_DIR)/system_bus.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_system_bus

#-----------------------------------------------------------------------------
# System Bus Test
#-----------------------------------------------------------------------------
test_system_bus: tb_system_bus.vvp
	@echo "Running System Bus tests..."
	$(VVP) $<

tb_system_bus.vvp: tb_system_bus.v $(SRC_BUS)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_BUS) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
