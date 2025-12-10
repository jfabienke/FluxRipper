# FluxRipper Drive Control Unit Tests
# Created: 2025-12-07

IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../../../rtl/drive_ctrl
COMMON_DIR = ../../common

# Source files
SRC_STEP = $(RTL_DIR)/step_controller.v
SRC_MOTOR = $(RTL_DIR)/motor_controller.v
SRC_INDEX = $(RTL_DIR)/index_handler.v

# Include paths
INCLUDES = -I $(RTL_DIR) -I $(COMMON_DIR)

.PHONY: all clean

all: test_step_controller test_motor_controller

#-----------------------------------------------------------------------------
# Step Controller Test
#-----------------------------------------------------------------------------
test_step_controller: tb_step_controller.vvp
	@echo "Running Step Controller tests..."
	$(VVP) $<

tb_step_controller.vvp: tb_step_controller.v $(SRC_STEP)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_STEP) $<

#-----------------------------------------------------------------------------
# Motor Controller Test
#-----------------------------------------------------------------------------
test_motor_controller: tb_motor_controller.vvp
	@echo "Running Motor Controller tests..."
	$(VVP) $<

tb_motor_controller.vvp: tb_motor_controller.v $(SRC_MOTOR)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_MOTOR) $<

#-----------------------------------------------------------------------------
# Index Handler Test
#-----------------------------------------------------------------------------
test_index_handler: tb_index_handler.vvp
	@echo "Running Index Handler tests..."
	$(VVP) $<

tb_index_handler.vvp: tb_index_handler.v $(SRC_INDEX)
	$(IVERILOG) -o $@ $(INCLUDES) $(SRC_INDEX) $<

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd
