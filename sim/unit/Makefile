# FluxRipper Unit Test Makefile
# Created: 2025-12-07
#
# Runs all unit tests across subsystems
#
# Usage:
#   make        - Run all unit tests
#   make clean  - Remove build artifacts

SUBDIRS = clocking debug dsp usb axi bus data_separator drive_ctrl

.PHONY: all clean $(SUBDIRS)

all: $(SUBDIRS)
	@echo "========================================"
	@echo " All Unit Tests Complete"
	@echo "========================================"

$(SUBDIRS):
	@echo "========================================"
	@echo " Running $@ tests"
	@echo "========================================"
	$(MAKE) -C $@

clean:
	@for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir clean; \
	done
