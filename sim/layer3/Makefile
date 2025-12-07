# Layer 3 (Full Debug Path + System Bus) Simulation Makefile
# Created: 2025-12-07 21:30

IVERILOG = iverilog
VVP = vvp

RTL_DEBUG = ../../rtl/debug
RTL_BUS = ../../rtl/bus
COMMON_DIR = ../common

SRC = $(RTL_DEBUG)/jtag_tap_controller.v \
      $(RTL_DEBUG)/jtag_dtm.v \
      $(RTL_DEBUG)/debug_module.v \
      $(RTL_BUS)/system_bus.v

.PHONY: all clean

all: run

run: tb_system_bus.vvp
	$(VVP) $<

tb_system_bus.vvp: tb_system_bus.v $(SRC)
	$(IVERILOG) -o $@ -I $(RTL_DEBUG) -I $(RTL_BUS) -I $(COMMON_DIR) $(SRC) $<

clean:
	rm -f *.vvp *.vcd
