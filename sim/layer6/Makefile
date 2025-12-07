# Layer 6 (Full System Integration) Simulation Makefile
# Created: 2025-12-07 22:55

IVERILOG = iverilog
VVP = vvp

RTL_TOP = ../../rtl/top
RTL_DEBUG = ../../rtl/debug
RTL_BUS = ../../rtl/bus
RTL_DISK = ../../rtl/disk
RTL_USB = ../../rtl/usb
RTL_CLOCK = ../../rtl/clocking
COMMON_DIR = ../common

SRC = $(RTL_TOP)/fluxripper_top.v \
      $(RTL_DEBUG)/jtag_tap_controller.v \
      $(RTL_DEBUG)/jtag_dtm.v \
      $(RTL_DEBUG)/debug_module.v \
      $(RTL_DEBUG)/signal_tap.v \
      $(RTL_BUS)/system_bus.v \
      $(RTL_DISK)/disk_controller.v \
      $(RTL_USB)/usb_controller.v \
      $(RTL_CLOCK)/clock_reset_mgr.v

INCLUDES = -I $(RTL_TOP) -I $(RTL_DEBUG) -I $(RTL_BUS) -I $(RTL_DISK) \
           -I $(RTL_USB) -I $(RTL_CLOCK) -I $(COMMON_DIR)

.PHONY: all clean

all: run

run: tb_system.vvp
	$(VVP) $<

tb_system.vvp: tb_system.v $(SRC)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC) $<

clean:
	rm -f *.vvp *.vcd
