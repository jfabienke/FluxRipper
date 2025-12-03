#------------------------------------------------------------------------------
# FluxRipper Simulation Makefile
# For use with Icarus Verilog (iverilog) or Verilator
#
# Updated: 2025-12-03 15:50
#------------------------------------------------------------------------------

# Simulation tool (iverilog or verilator)
SIM ?= iverilog

# Directories
RTL_DIR   = ../rtl
TB_DIR    = ../tb
SIM_DIR   = .
WAVE_DIR  = waves

# RTL source files
RTL_SOURCES = \
	$(RTL_DIR)/top/fluxripper_top.v \
	$(RTL_DIR)/fdc_core/command_fsm.v \
	$(RTL_DIR)/fdc_core/fdc_registers.v \
	$(RTL_DIR)/data_separator/digital_pll.v \
	$(RTL_DIR)/data_separator/edge_detector.v \
	$(RTL_DIR)/data_separator/phase_detector.v \
	$(RTL_DIR)/data_separator/loop_filter.v \
	$(RTL_DIR)/data_separator/nco.v \
	$(RTL_DIR)/data_separator/data_sampler.v \
	$(RTL_DIR)/am_detector/am_detector.v \
	$(RTL_DIR)/encoding/mfm_encoder.v \
	$(RTL_DIR)/encoding/mfm_decoder.v \
	$(RTL_DIR)/encoding/fm_codec.v \
	$(RTL_DIR)/encoding/gcr_cbm.v \
	$(RTL_DIR)/encoding/gcr_apple.v \
	$(RTL_DIR)/encoding/encoding_mux.v \
	$(RTL_DIR)/crc/crc16_ccitt.v \
	$(RTL_DIR)/drive_ctrl/step_controller.v \
	$(RTL_DIR)/drive_ctrl/index_handler.v \
	$(RTL_DIR)/drive_ctrl/motor_controller.v \
	$(RTL_DIR)/write_path/write_precomp.v \
	$(RTL_DIR)/diagnostics/flux_capture.v \
	$(RTL_DIR)/axi/axi_stream_flux.v \
	$(RTL_DIR)/axi/axi_fdc_periph.v

# AXI infrastructure sources (for SoC builds)
AXI_SOURCES = \
	$(RTL_DIR)/axi/axi_stream_flux.v \
	$(RTL_DIR)/axi/axi_fdc_periph.v

# Testbench files
TB_DPLL       = $(TB_DIR)/tb_digital_pll.v
TB_ENCODING   = $(TB_DIR)/tb_encoding.v
TB_CRC        = $(TB_DIR)/tb_crc16.v
TB_TOP        = $(TB_DIR)/tb_fluxripper_top.v
TB_AXI_STREAM = $(RTL_DIR)/axi/axi_stream_flux.v
TB_AXI_FDC    = $(RTL_DIR)/axi/axi_fdc_periph.v

# Test vector files
TEST_VECTORS = $(SIM_DIR)/capsimg_test_vectors.v

# Simulation outputs
VVP_DPLL       = $(SIM_DIR)/tb_digital_pll.vvp
VVP_ENCODING   = $(SIM_DIR)/tb_encoding.vvp
VVP_CRC        = $(SIM_DIR)/tb_crc16.vvp
VVP_TOP        = $(SIM_DIR)/tb_fluxripper_top.vvp
VVP_AXI_STREAM = $(SIM_DIR)/tb_axi_stream_flux.vvp
VVP_AXI_FDC    = $(SIM_DIR)/tb_axi_fdc_periph.vvp

# Icarus Verilog flags
IVERILOG_FLAGS = -Wall -g2012

#------------------------------------------------------------------------------
# Default target
#------------------------------------------------------------------------------
.PHONY: all clean help

all: sim_dpll sim_encoding sim_crc sim_top

help:
	@echo "FluxRipper Simulation Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all             - Run all simulations"
	@echo "  sim_dpll        - Run Digital PLL testbench"
	@echo "  sim_encoding    - Run encoding module testbench"
	@echo "  sim_crc         - Run CRC testbench"
	@echo "  sim_top         - Run top-level integration testbench"
	@echo "  sim_axi_stream  - Run AXI-Stream flux testbench"
	@echo "  sim_axi_fdc     - Run AXI4-Lite FDC peripheral testbench"
	@echo "  sim_axi         - Run all AXI testbenches"
	@echo "  compile_all     - Compile all testbenches without running"
	@echo "  waves           - Open waveform viewer (gtkwave)"
	@echo "  clean           - Remove generated files"
	@echo ""
	@echo "Variables:"
	@echo "  SIM=iverilog   - Use Icarus Verilog (default)"
	@echo "  SIM=verilator  - Use Verilator"

#------------------------------------------------------------------------------
# Digital PLL Testbench
#------------------------------------------------------------------------------
.PHONY: sim_dpll compile_dpll

compile_dpll: $(VVP_DPLL)

$(VVP_DPLL): $(TB_DPLL) $(RTL_DIR)/data_separator/*.v
	@echo "Compiling Digital PLL testbench..."
	iverilog $(IVERILOG_FLAGS) -o $@ \
		$(RTL_DIR)/data_separator/digital_pll.v \
		$(RTL_DIR)/data_separator/edge_detector.v \
		$(RTL_DIR)/data_separator/phase_detector.v \
		$(RTL_DIR)/data_separator/loop_filter.v \
		$(RTL_DIR)/data_separator/nco.v \
		$(RTL_DIR)/data_separator/data_sampler.v \
		$(TB_DPLL)

sim_dpll: $(VVP_DPLL)
	@echo "Running Digital PLL simulation..."
	vvp $<

#------------------------------------------------------------------------------
# Encoding Testbench
#------------------------------------------------------------------------------
.PHONY: sim_encoding compile_encoding

compile_encoding: $(VVP_ENCODING)

$(VVP_ENCODING): $(TB_ENCODING) $(RTL_DIR)/encoding/*.v
	@echo "Compiling encoding testbench..."
	iverilog $(IVERILOG_FLAGS) -o $@ \
		$(RTL_DIR)/encoding/mfm_encoder.v \
		$(RTL_DIR)/encoding/mfm_decoder.v \
		$(RTL_DIR)/encoding/fm_codec.v \
		$(RTL_DIR)/encoding/gcr_cbm.v \
		$(RTL_DIR)/encoding/gcr_apple.v \
		$(TB_ENCODING)

sim_encoding: $(VVP_ENCODING)
	@echo "Running encoding simulation..."
	vvp $<

#------------------------------------------------------------------------------
# CRC Testbench
#------------------------------------------------------------------------------
.PHONY: sim_crc compile_crc

compile_crc: $(VVP_CRC)

$(VVP_CRC): $(TB_CRC) $(RTL_DIR)/crc/*.v
	@echo "Compiling CRC testbench..."
	iverilog $(IVERILOG_FLAGS) -o $@ \
		$(RTL_DIR)/crc/crc16_ccitt.v \
		$(TB_CRC)

sim_crc: $(VVP_CRC)
	@echo "Running CRC simulation..."
	vvp $<

#------------------------------------------------------------------------------
# Top-Level Testbench
#------------------------------------------------------------------------------
.PHONY: sim_top compile_top

compile_top: $(VVP_TOP)

$(VVP_TOP): $(TB_TOP) $(RTL_SOURCES)
	@echo "Compiling top-level testbench..."
	iverilog $(IVERILOG_FLAGS) -o $@ \
		$(RTL_SOURCES) \
		$(TEST_VECTORS) \
		$(TB_TOP)

sim_top: $(VVP_TOP)
	@echo "Running top-level simulation..."
	vvp $<

#------------------------------------------------------------------------------
# Compile all
#------------------------------------------------------------------------------
.PHONY: compile_all

compile_all: compile_dpll compile_encoding compile_crc compile_top
	@echo "All testbenches compiled successfully."

#------------------------------------------------------------------------------
# Waveform viewing
#------------------------------------------------------------------------------
.PHONY: waves

waves:
	@mkdir -p $(WAVE_DIR)
	@echo "Open .vcd files with gtkwave or another waveform viewer"

#------------------------------------------------------------------------------
# AXI-Stream Flux Testbench
#------------------------------------------------------------------------------
.PHONY: sim_axi_stream compile_axi_stream

compile_axi_stream: $(VVP_AXI_STREAM)

$(VVP_AXI_STREAM): $(RTL_DIR)/axi/axi_stream_flux.v
	@echo "Compiling AXI-Stream flux testbench..."
	iverilog $(IVERILOG_FLAGS) -DSIMULATION -o $@ \
		$(RTL_DIR)/axi/axi_stream_flux.v

sim_axi_stream: $(VVP_AXI_STREAM)
	@echo "Running AXI-Stream flux simulation..."
	vvp $<

#------------------------------------------------------------------------------
# AXI4-Lite FDC Peripheral Testbench
#------------------------------------------------------------------------------
.PHONY: sim_axi_fdc compile_axi_fdc

compile_axi_fdc: $(VVP_AXI_FDC)

$(VVP_AXI_FDC): $(RTL_DIR)/axi/axi_fdc_periph.v
	@echo "Compiling AXI4-Lite FDC peripheral testbench..."
	iverilog $(IVERILOG_FLAGS) -DSIMULATION -o $@ \
		$(RTL_DIR)/axi/axi_fdc_periph.v

sim_axi_fdc: $(VVP_AXI_FDC)
	@echo "Running AXI4-Lite FDC peripheral simulation..."
	vvp $<

#------------------------------------------------------------------------------
# All AXI Testbenches
#------------------------------------------------------------------------------
.PHONY: sim_axi compile_axi

compile_axi: compile_axi_stream compile_axi_fdc

sim_axi: sim_axi_stream sim_axi_fdc
	@echo "All AXI testbenches completed."

#------------------------------------------------------------------------------
# Lint check (with Verilator)
#------------------------------------------------------------------------------
.PHONY: lint

lint:
	@echo "Running lint check with Verilator..."
	verilator --lint-only -Wall \
		-I$(RTL_DIR)/top \
		-I$(RTL_DIR)/fdc_core \
		-I$(RTL_DIR)/data_separator \
		-I$(RTL_DIR)/am_detector \
		-I$(RTL_DIR)/encoding \
		-I$(RTL_DIR)/crc \
		-I$(RTL_DIR)/drive_ctrl \
		-I$(RTL_DIR)/write_path \
		-I$(RTL_DIR)/diagnostics \
		-I$(RTL_DIR)/axi \
		$(RTL_DIR)/top/fluxripper_top.v

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------
clean:
	@echo "Cleaning simulation outputs..."
	rm -f $(SIM_DIR)/*.vvp
	rm -f $(SIM_DIR)/*.vcd
	rm -rf $(WAVE_DIR)
	rm -rf obj_dir

#------------------------------------------------------------------------------
# Synthesis check (with Yosys)
#------------------------------------------------------------------------------
.PHONY: synth_check

synth_check:
	@echo "Running synthesis check with Yosys..."
	yosys -p "read_verilog $(RTL_SOURCES); synth; stat"
