#============================================================================
# FluxRipper SoC - Firmware Makefile
#
# Builds bare-metal firmware for MicroBlaze V (RISC-V)
#
# Updated: 2025-12-03 18:00
#============================================================================

# Project
PROJECT     = fluxripper_fw
VERSION     = 0.1.0

# Toolchain (Vitis/Xilinx or generic RISC-V)
# Use CROSS_COMPILE to override, e.g., make CROSS_COMPILE=riscv64-unknown-elf-
CROSS_COMPILE ?= riscv32-unknown-elf-

CC          = $(CROSS_COMPILE)gcc
AS          = $(CROSS_COMPILE)as
LD          = $(CROSS_COMPILE)ld
OBJCOPY     = $(CROSS_COMPILE)objcopy
OBJDUMP     = $(CROSS_COMPILE)objdump
SIZE        = $(CROSS_COMPILE)size

# Directories
SRC_DIR     = src
INC_DIR     = include
BUILD_DIR   = build
FATFS_DIR   = fatfs
ADFLIB_DIR  = adflib

# Architecture flags for MicroBlaze V (RV32IMC)
ARCH        = rv32imc
ABI         = ilp32

# Compiler flags
CFLAGS      = -march=$(ARCH) -mabi=$(ABI)
CFLAGS     += -Os -g
CFLAGS     += -Wall -Wextra -Werror
CFLAGS     += -ffunction-sections -fdata-sections
CFLAGS     += -ffreestanding -nostdlib
CFLAGS     += -I$(INC_DIR)

# Assembler flags
ASFLAGS     = -march=$(ARCH) -mabi=$(ABI)

# Linker flags
LDFLAGS     = -T link.ld
LDFLAGS    += -nostdlib -nostartfiles
LDFLAGS    += -Wl,--gc-sections
LDFLAGS    += -Wl,-Map=$(BUILD_DIR)/$(PROJECT).map

# Libraries
LIBS        = -lgcc

# Source files
C_SRCS      = $(wildcard $(SRC_DIR)/*.c)
S_SRCS      = $(wildcard $(SRC_DIR)/*.S)

# Object files
C_OBJS      = $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SRCS))
S_OBJS      = $(patsubst $(SRC_DIR)/%.S,$(BUILD_DIR)/%.o,$(S_SRCS))
OBJS        = $(S_OBJS) $(C_OBJS)

# Output files
ELF         = $(BUILD_DIR)/$(PROJECT).elf
BIN         = $(BUILD_DIR)/$(PROJECT).bin
HEX         = $(BUILD_DIR)/$(PROJECT).hex
LST         = $(BUILD_DIR)/$(PROJECT).lst
MEM         = $(BUILD_DIR)/$(PROJECT).mem

#============================================================================
# Targets
#============================================================================

.PHONY: all clean flash size lst mem help

all: $(BUILD_DIR) $(ELF) $(BIN) $(HEX) $(MEM) size

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Link
$(ELF): $(OBJS)
	@echo "LD      $@"
	@$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) $(LIBS)

# Compile C
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@echo "CC      $<"
	@$(CC) $(CFLAGS) -c -o $@ $<

# Assemble
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.S
	@echo "AS      $<"
	@$(CC) $(ASFLAGS) -c -o $@ $<

# Binary
$(BIN): $(ELF)
	@echo "OBJCOPY $@"
	@$(OBJCOPY) -O binary $< $@

# Intel HEX
$(HEX): $(ELF)
	@echo "OBJCOPY $@"
	@$(OBJCOPY) -O ihex $< $@

# Memory initialization file for Vivado BRAM
$(MEM): $(BIN)
	@echo "MEM     $@"
	@xxd -c 4 -e $< | awk '{print $$2}' > $@

# Disassembly listing
lst: $(ELF)
	@echo "OBJDUMP $(LST)"
	@$(OBJDUMP) -d -S $< > $(LST)

# Size report
size: $(ELF)
	@echo ""
	@echo "=== Memory Usage ==="
	@$(SIZE) $<
	@echo ""

# Clean
clean:
	@echo "CLEAN   $(BUILD_DIR)"
	@rm -rf $(BUILD_DIR)

# Help
help:
	@echo "FluxRipper SoC Firmware Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build firmware (default)"
	@echo "  clean   - Remove build directory"
	@echo "  size    - Show memory usage"
	@echo "  lst     - Generate disassembly listing"
	@echo "  mem     - Generate BRAM initialization file"
	@echo "  help    - Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  CROSS_COMPILE - Toolchain prefix (default: riscv32-unknown-elf-)"
	@echo ""
	@echo "Example:"
	@echo "  make CROSS_COMPILE=riscv64-unknown-elf-"

#============================================================================
# Dependencies
#============================================================================

$(BUILD_DIR)/main.o: $(INC_DIR)/platform.h $(INC_DIR)/uart.h $(INC_DIR)/timer.h $(INC_DIR)/cli.h
$(BUILD_DIR)/uart.o: $(INC_DIR)/platform.h $(INC_DIR)/uart.h
$(BUILD_DIR)/timer.o: $(INC_DIR)/platform.h $(INC_DIR)/timer.h
$(BUILD_DIR)/cli.o: $(INC_DIR)/platform.h $(INC_DIR)/uart.h $(INC_DIR)/timer.h $(INC_DIR)/cli.h
