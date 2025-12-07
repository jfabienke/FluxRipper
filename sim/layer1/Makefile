# Layer 1 (TAP + DTM) Simulation Makefile
# Created: 2025-12-07 20:50

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../rtl/debug
COMMON_DIR = ../common

SRC = $(RTL_DIR)/jtag_tap_controller.v $(RTL_DIR)/jtag_dtm.v

.PHONY: all clean

all: run

run: tb_jtag_dtm.vvp
	$(VVP) $<

tb_jtag_dtm.vvp: tb_jtag_dtm.v $(SRC)
	$(IVERILOG) -o $@ -I $(RTL_DIR) -I $(COMMON_DIR) $(SRC) $<

clean:
	rm -f *.vvp *.vcd
