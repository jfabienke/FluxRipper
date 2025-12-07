# Layer 2 (TAP + DTM + Debug Module) Simulation Makefile
# Created: 2025-12-07 21:40

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../rtl/debug
COMMON_DIR = ../common

SRC = $(RTL_DIR)/jtag_tap_controller.v \
      $(RTL_DIR)/jtag_dtm.v \
      $(RTL_DIR)/debug_module.v

.PHONY: all clean

all: run

run: tb_debug_module.vvp
	$(VVP) $<

tb_debug_module.vvp: tb_debug_module.v $(SRC)
	$(IVERILOG) -o $@ -I $(RTL_DIR) -I $(COMMON_DIR) $(SRC) $<

clean:
	rm -f *.vvp *.vcd
