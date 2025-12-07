# Layer 5 (Peripheral Subsystems) Simulation Makefile
# Created: 2025-12-07 22:05

IVERILOG = iverilog
VVP = vvp

RTL_DEBUG = ../../rtl/debug
RTL_BUS = ../../rtl/bus
RTL_DISK = ../../rtl/disk
RTL_USB = ../../rtl/usb
COMMON_DIR = ../common

SRC = $(RTL_DEBUG)/jtag_tap_controller.v \
      $(RTL_DEBUG)/jtag_dtm.v \
      $(RTL_DEBUG)/debug_module.v \
      $(RTL_DEBUG)/signal_tap.v \
      $(RTL_BUS)/system_bus.v \
      $(RTL_DISK)/disk_controller.v \
      $(RTL_USB)/usb_controller.v

.PHONY: all clean

all: run

run: tb_peripherals.vvp
	$(VVP) $<

tb_peripherals.vvp: tb_peripherals.v $(SRC)
	$(IVERILOG) -o $@ -I $(RTL_DEBUG) -I $(RTL_BUS) -I $(RTL_DISK) -I $(RTL_USB) -I $(COMMON_DIR) $(SRC) $<

clean:
	rm -f *.vvp *.vcd
