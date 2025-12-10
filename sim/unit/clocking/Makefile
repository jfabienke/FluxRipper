# FluxRipper Clocking Subsystem Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/clocking
COMMON_DIR = ../../common

# Source files
SRC_CLOCK_RESET = $(RTL_DIR)/clock_reset_mgr.v
SRC_CLK_WIZARD = $(RTL_DIR)/clk_wizard_hdd.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_clock_reset_mgr test_clk_wizard_hdd

#-----------------------------------------------------------------------------
# Clock/Reset Manager Test
#-----------------------------------------------------------------------------
test_clock_reset_mgr: tb_clock_reset_mgr.vvp
	@echo "Running clock_reset_mgr tests..."
	$(VVP) $<

tb_clock_reset_mgr.vvp: tb_clock_reset_mgr.v $(SRC_CLOCK_RESET)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_CLOCK_RESET) $<

#-----------------------------------------------------------------------------
# HDD Clock Wizard Test
#-----------------------------------------------------------------------------
test_clk_wizard_hdd: tb_clk_wizard_hdd.vvp
	@echo "Running clk_wizard_hdd tests..."
	$(VVP) $<

tb_clk_wizard_hdd.vvp: tb_clk_wizard_hdd.v $(SRC_CLK_WIZARD)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_CLK_WIZARD) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
