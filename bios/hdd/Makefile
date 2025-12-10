#==============================================================================
# FluxRipper HDD BIOS Makefile
#==============================================================================
# Builds 8KB (XT-compatible) and 16KB (AT + diagnostics) Option ROMs
#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2025 FluxRipper Project
#==============================================================================

NASM := nasm
PYTHON := python3

# Output directory
ROM_DIR := rom

# Source files (in link order)
ENTRY_SRC := src/entry.asm

# Include paths
INCLUDES := -I include/ -I src/

# NASM flags
NASM_FLAGS := -f bin $(INCLUDES) -w+all

# Build targets
.PHONY: all rom8k rom16k clean info

all: rom8k rom16k

#------------------------------------------------------------------------------
# 8KB Minimal Build (XT-compatible)
#------------------------------------------------------------------------------
rom8k: $(ROM_DIR)/hdd_8k.bin
	@echo "Built 8KB ROM: $(ROM_DIR)/hdd_8k.bin"
	@$(PYTHON) tools/rominfo.py $(ROM_DIR)/hdd_8k.bin

$(ROM_DIR)/hdd_8k.bin: $(ENTRY_SRC) $(wildcard src/*.asm) $(wildcard include/*.inc)
	@mkdir -p $(ROM_DIR)
	$(NASM) $(NASM_FLAGS) -DBUILD_8KB=1 -DBUILD_16KB=0 \
		-o $@ $(ENTRY_SRC)
	@$(PYTHON) tools/romsum.py $@

#------------------------------------------------------------------------------
# 16KB Full Build (AT + Diagnostics)
#------------------------------------------------------------------------------
rom16k: $(ROM_DIR)/hdd_16k.bin
	@echo "Built 16KB ROM: $(ROM_DIR)/hdd_16k.bin"
	@$(PYTHON) tools/rominfo.py $(ROM_DIR)/hdd_16k.bin

$(ROM_DIR)/hdd_16k.bin: $(ENTRY_SRC) $(wildcard src/*.asm) $(wildcard include/*.inc)
	@mkdir -p $(ROM_DIR)
	$(NASM) $(NASM_FLAGS) -DBUILD_8KB=0 -DBUILD_16KB=1 \
		-o $@ $(ENTRY_SRC)
	@$(PYTHON) tools/romsum.py $@

#------------------------------------------------------------------------------
# Utilities
#------------------------------------------------------------------------------
clean:
	rm -rf $(ROM_DIR)/*.bin $(ROM_DIR)/*.lst

info:
	@echo "FluxRipper HDD BIOS Build System"
	@echo "================================"
	@echo "Targets:"
	@echo "  rom8k   - Build 8KB XT-compatible ROM"
	@echo "  rom16k  - Build 16KB AT ROM with diagnostics"
	@echo "  all     - Build both ROMs"
	@echo "  clean   - Remove build artifacts"
	@echo ""
	@echo "Requirements:"
	@echo "  - NASM 2.15+"
	@echo "  - Python 3.8+"

# Generate listing files for debugging
%.lst: %.asm
	$(NASM) $(NASM_FLAGS) -l $@ $<
