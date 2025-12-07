# FluxRipper Simulation Makefile
# Created: 2025-12-07 19:50
#
# Usage:
#   make icarus    - Run Icarus Verilog simulation (comprehensive, 9 tests)
#   make verilator - Run Verilator simulation (fast, 4 tests + 1M cycle perf)
#   make all       - Run both
#   make clean     - Remove build artifacts

IVERILOG = iverilog
VVP = vvp
VERILATOR = verilator

RTL_DIR = ../rtl/debug
SRC = $(RTL_DIR)/jtag_tap_controller.v

.PHONY: all icarus verilator clean

all: icarus verilator

#-----------------------------------------------------------------------------
# Icarus Verilog (comprehensive tests with VCD output)
#-----------------------------------------------------------------------------
icarus: tb_jtag_tap.vvp
	@echo "=========================================="
	@echo " Running Icarus Verilog Simulation"
	@echo "=========================================="
	$(VVP) tb_jtag_tap.vvp

tb_jtag_tap.vvp: tb_jtag_tap.v $(SRC)
	$(IVERILOG) -o $@ -I $(RTL_DIR) $(SRC) tb_jtag_tap.v

#-----------------------------------------------------------------------------
# Verilator (fast C++ simulation)
#-----------------------------------------------------------------------------
verilator: obj_dir/Vjtag_tap_controller
	@echo "=========================================="
	@echo " Running Verilator Simulation"
	@echo "=========================================="
	./obj_dir/Vjtag_tap_controller

obj_dir/Vjtag_tap_controller: tb_jtag_verilator.cpp $(SRC)
	$(VERILATOR) --cc $(SRC) --exe tb_jtag_verilator.cpp \
		--Mdir obj_dir -CFLAGS "-std=c++17" -Wno-CASEINCOMPLETE
	$(MAKE) -C obj_dir -f Vjtag_tap_controller.mk Vjtag_tap_controller

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -rf obj_dir
	rm -f tb_jtag_tap.vvp tb_jtag_tap.vcd
