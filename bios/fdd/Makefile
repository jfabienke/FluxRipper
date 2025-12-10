#==============================================================================
# FluxRipper FDD BIOS - Makefile
#==============================================================================
# Build system for the FDD BIOS Option ROM.
#
# Targets:
#   all     - Build both 8KB and 16KB ROMs
#   rom8k   - Build 8KB minimal ROM (XT-compatible)
#   rom16k  - Build 16KB full ROM (with diagnostics)
#   clean   - Remove built files
#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2025 FluxRipper Project
#==============================================================================

# Tools
NASM = nasm
PYTHON = python3

# Directories
SRC_DIR = src
INC_DIR = include
OUT_DIR = build
TOOLS_DIR = tools

# Output files
ROM_8K = $(OUT_DIR)/fluxripper_fdd_8k.rom
ROM_16K = $(OUT_DIR)/fluxripper_fdd_16k.rom

# Source files
ENTRY = $(SRC_DIR)/entry.asm
INCLUDES = $(wildcard $(INC_DIR)/*.inc)
SOURCES = $(wildcard $(SRC_DIR)/*.asm)

# NASM flags
NASM_FLAGS = -f bin -I$(INC_DIR)/ -I$(SRC_DIR)/

# Default target
.PHONY: all
all: rom16k rom8k

# Create output directory
$(OUT_DIR):
	mkdir -p $(OUT_DIR)

# Build 16KB ROM (full features)
.PHONY: rom16k
rom16k: $(OUT_DIR) $(ROM_16K)
	@echo "Built 16KB FDD BIOS ROM: $(ROM_16K)"
	@ls -l $(ROM_16K)
	@echo "ROM checksum: $$($(PYTHON) $(TOOLS_DIR)/romsum.py --check $(ROM_16K))"

$(ROM_16K): $(ENTRY) $(SOURCES) $(INCLUDES)
	$(NASM) $(NASM_FLAGS) -DBUILD_8KB=0 -DBUILD_16KB=1 -o $@ $(ENTRY)
	$(PYTHON) $(TOOLS_DIR)/romsum.py $@

# Build 8KB ROM (minimal)
.PHONY: rom8k
rom8k: $(OUT_DIR) $(ROM_8K)
	@echo "Built 8KB FDD BIOS ROM: $(ROM_8K)"
	@ls -l $(ROM_8K)
	@echo "ROM checksum: $$($(PYTHON) $(TOOLS_DIR)/romsum.py --check $(ROM_8K))"

$(ROM_8K): $(ENTRY) $(SOURCES) $(INCLUDES)
	$(NASM) $(NASM_FLAGS) -DBUILD_8KB=1 -DBUILD_16KB=0 -o $@ $(ENTRY)
	$(PYTHON) $(TOOLS_DIR)/romsum.py $@

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(OUT_DIR)

# Show ROM information
.PHONY: info
info: $(ROM_16K)
	$(PYTHON) $(TOOLS_DIR)/romsum.py --info $(ROM_16K)

# Verify ROM checksums
.PHONY: verify
verify: $(ROM_8K) $(ROM_16K)
	@echo "Verifying 8KB ROM..."
	@$(PYTHON) $(TOOLS_DIR)/romsum.py --check $(ROM_8K)
	@echo "Verifying 16KB ROM..."
	@$(PYTHON) $(TOOLS_DIR)/romsum.py --check $(ROM_16K)

# Dependencies
$(SOURCES): $(INCLUDES)

.PHONY: help
help:
	@echo "FluxRipper FDD BIOS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build both ROM sizes (default)"
	@echo "  rom8k   - Build 8KB minimal ROM"
	@echo "  rom16k  - Build 16KB full ROM"
	@echo "  clean   - Remove build artifacts"
	@echo "  info    - Show ROM information"
	@echo "  verify  - Verify ROM checksums"
	@echo "  help    - Show this help"
	@echo ""
	@echo "Output:"
	@echo "  $(ROM_8K)"
	@echo "  $(ROM_16K)"
