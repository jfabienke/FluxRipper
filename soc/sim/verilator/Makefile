#-----------------------------------------------------------------------------
# FluxRipper SoC - Verilator Simulation Makefile
#
# Builds and runs Verilator simulation of the FluxRipper FDC
#
# Updated: 2025-12-03 19:30
#-----------------------------------------------------------------------------

# Directories
RTL_DIR     = ../../rtl
SIM_DIR     = .
BUILD_DIR   = obj_dir

# Top module
TOP_MODULE  = fluxripper_dual_top

# Verilator settings
VERILATOR   = verilator
VERILATOR_FLAGS = --cc --exe --build
VERILATOR_FLAGS += --trace          # Enable VCD trace
VERILATOR_FLAGS += --trace-depth 10 # Trace depth
VERILATOR_FLAGS += -Wall            # Enable warnings
VERILATOR_FLAGS += -Wno-fatal       # Don't stop on warnings
VERILATOR_FLAGS += --timing         # Enable timing
VERILATOR_FLAGS += -O3              # Optimization level
VERILATOR_FLAGS += --threads 4      # Multi-threaded simulation

# Include paths
VERILATOR_FLAGS += -I$(RTL_DIR)/top
VERILATOR_FLAGS += -I$(RTL_DIR)/axi
VERILATOR_FLAGS += -I$(RTL_DIR)/fdc_core
VERILATOR_FLAGS += -I$(RTL_DIR)/data_separator
VERILATOR_FLAGS += -I$(RTL_DIR)/am_detector
VERILATOR_FLAGS += -I$(RTL_DIR)/encoding
VERILATOR_FLAGS += -I$(RTL_DIR)/crc
VERILATOR_FLAGS += -I$(RTL_DIR)/drive_ctrl
VERILATOR_FLAGS += -I$(RTL_DIR)/diagnostics
VERILATOR_FLAGS += -I$(RTL_DIR)/write_path

# RTL source files
RTL_FILES = \
    $(RTL_DIR)/top/fluxripper_dual_top.v \
    $(RTL_DIR)/axi/axi_fdc_periph_dual.v \
    $(RTL_DIR)/axi/axi_stream_flux_dual.v \
    $(RTL_DIR)/fdc_core/fdc_core_instance.v \
    $(RTL_DIR)/fdc_core/command_fsm.v \
    $(RTL_DIR)/fdc_core/motor_controller.v \
    $(RTL_DIR)/fdc_core/step_controller.v \
    $(RTL_DIR)/data_separator/digital_pll.v \
    $(RTL_DIR)/data_separator/nco.v \
    $(RTL_DIR)/data_separator/loop_filter.v \
    $(RTL_DIR)/data_separator/zone_calculator.v \
    $(RTL_DIR)/am_detector/address_mark_detector.v \
    $(RTL_DIR)/encoding/mfm_codec.v \
    $(RTL_DIR)/encoding/fm_codec.v \
    $(RTL_DIR)/encoding/gcr_apple.v \
    $(RTL_DIR)/encoding/gcr_cbm.v \
    $(RTL_DIR)/encoding/m2fm_codec.v \
    $(RTL_DIR)/encoding/tandy_sync.v \
    $(RTL_DIR)/encoding/encoding_mux.v \
    $(RTL_DIR)/encoding/encoding_detector.v \
    $(RTL_DIR)/crc/crc16_ccitt.v \
    $(RTL_DIR)/drive_ctrl/index_handler_dual.v \
    $(RTL_DIR)/diagnostics/drive_profile_detector.v \
    $(RTL_DIR)/diagnostics/flux_analyzer.v

# Testbench
TB_FILE = tb_soc_top.cpp

# Simulation executable
SIM_EXE = $(BUILD_DIR)/V$(TOP_MODULE)

#-----------------------------------------------------------------------------
# Targets
#-----------------------------------------------------------------------------

.PHONY: all build run wave clean help

all: build

build: $(SIM_EXE)

$(SIM_EXE): $(RTL_FILES) $(TB_FILE)
	@echo "Building Verilator simulation..."
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module $(TOP_MODULE) \
		$(RTL_FILES) \
		$(TB_FILE)
	@echo "Build complete: $(SIM_EXE)"

run: $(SIM_EXE)
	@echo "Running simulation..."
	./$(SIM_EXE)
	@echo "Simulation complete"

wave: fluxripper_soc.vcd
	@echo "Opening waveform viewer..."
	@if command -v gtkwave > /dev/null; then \
		gtkwave fluxripper_soc.vcd &; \
	else \
		echo "GTKWave not found. VCD file: fluxripper_soc.vcd"; \
	fi

fluxripper_soc.vcd: run

lint:
	@echo "Running Verilator lint..."
	$(VERILATOR) --lint-only \
		-I$(RTL_DIR)/top \
		-I$(RTL_DIR)/axi \
		-I$(RTL_DIR)/fdc_core \
		-I$(RTL_DIR)/data_separator \
		-I$(RTL_DIR)/am_detector \
		-I$(RTL_DIR)/encoding \
		-I$(RTL_DIR)/crc \
		-I$(RTL_DIR)/drive_ctrl \
		-I$(RTL_DIR)/diagnostics \
		$(RTL_FILES)

clean:
	@echo "Cleaning..."
	rm -rf $(BUILD_DIR) *.vcd

help:
	@echo "FluxRipper SoC Verilator Simulation"
	@echo ""
	@echo "Targets:"
	@echo "  all   - Build simulation (default)"
	@echo "  build - Build simulation executable"
	@echo "  run   - Run simulation"
	@echo "  wave  - Open waveform in GTKWave"
	@echo "  lint  - Run Verilator lint checks"
	@echo "  clean - Remove build artifacts"
	@echo "  help  - Show this help"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Verilator (brew install verilator)"
	@echo "  - GTKWave for viewing waveforms (optional)"
