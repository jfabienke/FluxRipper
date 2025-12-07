# Layer 4 (Clock/Reset Manager) Simulation Makefile
# Created: 2025-12-07 21:35

IVERILOG = iverilog
VVP = vvp

RTL_DEBUG = ../../rtl/debug
RTL_CLOCK = ../../rtl/clocking
COMMON_DIR = ../common

SRC = $(RTL_CLOCK)/clock_reset_mgr.v \
      $(RTL_DEBUG)/jtag_tap_controller.v \
      $(RTL_DEBUG)/jtag_dtm.v

.PHONY: all clean

all: run

run: tb_clock_reset.vvp
	$(VVP) $<

tb_clock_reset.vvp: tb_clock_reset.v $(SRC)
	$(IVERILOG) -o $@ -I $(RTL_DEBUG) -I $(RTL_CLOCK) -I $(COMMON_DIR) $(SRC) $<

clean:
	rm -f *.vvp *.vcd
