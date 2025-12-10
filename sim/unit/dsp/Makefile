# FluxRipper DSP Subsystem Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/dsp
COMMON_DIR = ../../common

# Source files
SRC_FIR = $(RTL_DIR)/fir_flux_filter.v
SRC_PRML = $(RTL_DIR)/prml_decoder.v
SRC_EQ = $(RTL_DIR)/adaptive_equalizer.v
SRC_FFT = $(RTL_DIR)/fft_analyzer.v
SRC_CORR = $(RTL_DIR)/correlation_sync_detector.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_fir test_prml test_equalizer test_fft test_correlation

#-----------------------------------------------------------------------------
# FIR Filter Test
#-----------------------------------------------------------------------------
test_fir: tb_fir_flux_filter.vvp
	@echo "Running FIR Filter tests..."
	$(VVP) $<

tb_fir_flux_filter.vvp: tb_fir_flux_filter.v $(SRC_FIR)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_FIR) $<

#-----------------------------------------------------------------------------
# PRML Decoder Test
#-----------------------------------------------------------------------------
test_prml: tb_prml_decoder.vvp
	@echo "Running PRML Decoder tests..."
	$(VVP) $<

tb_prml_decoder.vvp: tb_prml_decoder.v $(SRC_PRML)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_PRML) $<

#-----------------------------------------------------------------------------
# Adaptive Equalizer Test
#-----------------------------------------------------------------------------
test_equalizer: tb_adaptive_equalizer.vvp
	@echo "Running Adaptive Equalizer tests..."
	$(VVP) $<

tb_adaptive_equalizer.vvp: tb_adaptive_equalizer.v $(SRC_EQ)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_EQ) $<

#-----------------------------------------------------------------------------
# FFT Analyzer Test
#-----------------------------------------------------------------------------
test_fft: tb_fft_analyzer.vvp
	@echo "Running FFT Analyzer tests..."
	$(VVP) $<

tb_fft_analyzer.vvp: tb_fft_analyzer.v $(SRC_FFT)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_FFT) $<

#-----------------------------------------------------------------------------
# Correlation Sync Detector Test
#-----------------------------------------------------------------------------
test_correlation: tb_correlation_sync.vvp
	@echo "Running Correlation Sync tests..."
	$(VVP) $<

tb_correlation_sync.vvp: tb_correlation_sync.v $(SRC_CORR)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_CORR) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
