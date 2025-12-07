# FluxRipper SoC - Vivado Block Design TCL Script
# Milestone 0: "Hello SoC" - MicroBlaze V + UART + Timer
#
# Usage: vivado -mode batch -source create_soc.tcl
#
# Target: AMD Spartan UltraScale+ SCU35 (xcsu35p-2sbvb625e)
# Updated: 2025-12-03

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------
set project_name "fluxripper_soc"
set project_dir  "../vivado"
set part         "xcsu35p-2sbvb625e"
set board        ""  ;# No board file for SCU35 eval yet

# Clock parameters
set input_clk_freq_mhz  50.0   ;# Board input clock
set axi_clk_freq_mhz   100.0   ;# AXI bus / MicroBlaze
set fdc_clk_freq_mhz   200.0   ;# FDC data path (Milestone 1+)

#------------------------------------------------------------------------------
# Create Project
#------------------------------------------------------------------------------
create_project $project_name $project_dir -part $part -force

set_property target_language Verilog [current_project]

#------------------------------------------------------------------------------
# Create Block Design
#------------------------------------------------------------------------------
create_bd_design "fluxripper_soc"

#------------------------------------------------------------------------------
# Add Clocking Wizard
#------------------------------------------------------------------------------
puts "Adding Clocking Wizard..."

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_0

set_property -dict [list \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ $input_clk_freq_mhz \
    CONFIG.CLKOUT_USED {true,true,false,false,false,false,false} \
    CONFIG.CLKOUT_PORT {clk_100m,clk_200m,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY "$axi_clk_freq_mhz,$fdc_clk_freq_mhz,100.000,100.000,100.000,100.000,100.000" \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
] [get_bd_cells clk_wizard_0]

#------------------------------------------------------------------------------
# Add Processor System Reset
#------------------------------------------------------------------------------
puts "Adding Processor System Reset..."

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

# Connect reset
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wizard_0/locked] [get_bd_pins proc_sys_reset_0/dcm_locked]

#------------------------------------------------------------------------------
# Add MicroBlaze V (RISC-V)
#------------------------------------------------------------------------------
puts "Adding MicroBlaze V..."

create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze_riscv:1.0 microblaze_riscv_0

# Configure MicroBlaze V: RV32IMC, caches, no MMU
set_property -dict [list \
    CONFIG.C_USE_ICACHE {1} \
    CONFIG.C_CACHE_BYTE_SIZE {8192} \
    CONFIG.C_ICACHE_LINE_LEN {4} \
    CONFIG.C_ICACHE_VICTIMS {0} \
    CONFIG.C_USE_DCACHE {1} \
    CONFIG.C_DCACHE_BYTE_SIZE {4096} \
    CONFIG.C_DCACHE_LINE_LEN {4} \
    CONFIG.C_DCACHE_VICTIMS {0} \
    CONFIG.C_USE_MMU {0} \
    CONFIG.C_USE_BRANCH_TARGET_CACHE {0} \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_NUMBER_OF_PC_BRK {4} \
] [get_bd_cells microblaze_riscv_0]

# Connect clock
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins microblaze_riscv_0/Clk]
connect_bd_net [get_bd_pins proc_sys_reset_0/mb_reset] [get_bd_pins microblaze_riscv_0/Reset]

#------------------------------------------------------------------------------
# Add Local Memory (BRAM) - Code + Data TCM
#------------------------------------------------------------------------------
puts "Adding Local Memory..."

# Code memory: 32KB (Milestone 0 minimal)
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 ilmb_bram_if_cntlr
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 ilmb_v10
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 ilmb_bram

set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_32bit_Address {false} \
    CONFIG.Use_Byte_Write_Enable {true} \
    CONFIG.Byte_Size {8} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Write_Depth_A {8192} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Width_B {32} \
    CONFIG.Read_Width_B {32} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
] [get_bd_cells ilmb_bram]

# Data memory: 16KB
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 dlmb_bram_if_cntlr
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 dlmb_v10
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 dlmb_bram

set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_32bit_Address {false} \
    CONFIG.Use_Byte_Write_Enable {true} \
    CONFIG.Byte_Size {8} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Write_Depth_A {4096} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Width_B {32} \
    CONFIG.Read_Width_B {32} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
] [get_bd_cells dlmb_bram]

# Connect LMB buses
connect_bd_intf_net [get_bd_intf_pins microblaze_riscv_0/ILMB] [get_bd_intf_pins ilmb_v10/LMB_M]
connect_bd_intf_net [get_bd_intf_pins ilmb_v10/LMB_Sl_0] [get_bd_intf_pins ilmb_bram_if_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins ilmb_bram/BRAM_PORTA]

connect_bd_intf_net [get_bd_intf_pins microblaze_riscv_0/DLMB] [get_bd_intf_pins dlmb_v10/LMB_M]
connect_bd_intf_net [get_bd_intf_pins dlmb_v10/LMB_Sl_0] [get_bd_intf_pins dlmb_bram_if_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins dlmb_bram/BRAM_PORTA]

# Connect LMB clocks and resets
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins ilmb_v10/LMB_Clk]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins dlmb_v10/LMB_Clk]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk]

connect_bd_net [get_bd_pins proc_sys_reset_0/bus_struct_reset] [get_bd_pins ilmb_v10/SYS_Rst]
connect_bd_net [get_bd_pins proc_sys_reset_0/bus_struct_reset] [get_bd_pins dlmb_v10/SYS_Rst]
connect_bd_net [get_bd_pins proc_sys_reset_0/bus_struct_reset] [get_bd_pins ilmb_bram_if_cntlr/LMB_Rst]
connect_bd_net [get_bd_pins proc_sys_reset_0/bus_struct_reset] [get_bd_pins dlmb_bram_if_cntlr/LMB_Rst]

#------------------------------------------------------------------------------
# Add AXI Interconnect
#------------------------------------------------------------------------------
puts "Adding AXI Interconnect..."

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0

set_property -dict [list \
    CONFIG.NUM_MI {3} \
    CONFIG.NUM_SI {1} \
] [get_bd_cells axi_interconnect_0]

# Connect MicroBlaze M_AXI to interconnect
connect_bd_intf_net [get_bd_intf_pins microblaze_riscv_0/M_AXI_DP] [get_bd_intf_pins axi_interconnect_0/S00_AXI]

# Connect clocks
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_interconnect_0/M01_ACLK]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_interconnect_0/M02_ACLK]

connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M01_ARESETN]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M02_ARESETN]

#------------------------------------------------------------------------------
# Add UART Lite
#------------------------------------------------------------------------------
puts "Adding UART Lite..."

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0

set_property -dict [list \
    CONFIG.C_BAUDRATE {115200} \
    CONFIG.C_DATA_BITS {8} \
    CONFIG.C_USE_PARITY {0} \
    CONFIG.C_ODD_PARITY {0} \
] [get_bd_cells axi_uartlite_0]

# Connect to AXI interconnect M00
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins axi_uartlite_0/S_AXI]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_uartlite_0/s_axi_aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_uartlite_0/s_axi_aresetn]

#------------------------------------------------------------------------------
# Add AXI Timer
#------------------------------------------------------------------------------
puts "Adding AXI Timer..."

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer:2.0 axi_timer_0

set_property -dict [list \
    CONFIG.enable_timer2 {0} \
    CONFIG.mode_64bit {0} \
] [get_bd_cells axi_timer_0]

# Connect to AXI interconnect M01
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M01_AXI] [get_bd_intf_pins axi_timer_0/S_AXI]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_timer_0/s_axi_aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_timer_0/s_axi_aresetn]

#------------------------------------------------------------------------------
# Add AXI GPIO (LEDs/Debug)
#------------------------------------------------------------------------------
puts "Adding AXI GPIO..."

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0

set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {8} \
    CONFIG.C_ALL_OUTPUTS {1} \
] [get_bd_cells axi_gpio_0]

# Connect to AXI interconnect M02
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M02_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_net [get_bd_pins clk_wizard_0/clk_100m] [get_bd_pins axi_gpio_0/s_axi_aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn]

#------------------------------------------------------------------------------
# Add Interrupt Controller
#------------------------------------------------------------------------------
puts "Adding Interrupt Controller..."

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_0

set_property -dict [list \
    CONFIG.C_KIND_OF_INTR {0xFFFFFFFF} \
    CONFIG.C_IRQ_CONNECTION {1} \
] [get_bd_cells axi_intc_0]

# Connect UART and Timer interrupts
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {2}] [get_bd_cells xlconcat_0]

connect_bd_net [get_bd_pins axi_uartlite_0/interrupt] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_timer_0/interrupt] [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins axi_intc_0/intr]

# Connect INTC to MicroBlaze
connect_bd_net [get_bd_pins axi_intc_0/irq] [get_bd_pins microblaze_riscv_0/INTERRUPT]

#------------------------------------------------------------------------------
# Create External Ports
#------------------------------------------------------------------------------
puts "Creating external ports..."

# Clock input
create_bd_port -dir I -type clk clk_in
set_property CONFIG.FREQ_HZ [expr int($input_clk_freq_mhz * 1000000)] [get_bd_ports clk_in]
connect_bd_net [get_bd_ports clk_in] [get_bd_pins clk_wizard_0/clk_in1]

# Reset input (active low)
create_bd_port -dir I -type rst reset_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports reset_n]
connect_bd_net [get_bd_ports reset_n] [get_bd_pins clk_wizard_0/resetn]
connect_bd_net [get_bd_ports reset_n] [get_bd_pins proc_sys_reset_0/ext_reset_in]

# UART
create_bd_port -dir I uart_rxd
create_bd_port -dir O uart_txd
connect_bd_net [get_bd_ports uart_rxd] [get_bd_pins axi_uartlite_0/rx]
connect_bd_net [get_bd_ports uart_txd] [get_bd_pins axi_uartlite_0/tx]

# GPIO LEDs
create_bd_port -dir O -from 7 -to 0 gpio_leds
connect_bd_net [get_bd_ports gpio_leds] [get_bd_pins axi_gpio_0/gpio_io_o]

# 200MHz clock output (for FDC in Milestone 1+)
create_bd_port -dir O clk_200m
connect_bd_net [get_bd_ports clk_200m] [get_bd_pins clk_wizard_0/clk_200m]

#------------------------------------------------------------------------------
# Assign Addresses
#------------------------------------------------------------------------------
puts "Assigning addresses..."

assign_bd_address

# Customize addresses to match our memory map
set_property offset 0x00000000 [get_bd_addr_segs {microblaze_riscv_0/Data/SEG_ilmb_bram_if_cntlr_Mem}]
set_property offset 0x00000000 [get_bd_addr_segs {microblaze_riscv_0/Instruction/SEG_ilmb_bram_if_cntlr_Mem}]
set_property offset 0x00010000 [get_bd_addr_segs {microblaze_riscv_0/Data/SEG_dlmb_bram_if_cntlr_Mem}]

set_property offset 0x80002000 [get_bd_addr_segs {microblaze_riscv_0/Data/SEG_axi_uartlite_0_Reg}]
set_property offset 0x80001000 [get_bd_addr_segs {microblaze_riscv_0/Data/SEG_axi_timer_0_Reg}]
set_property offset 0x80006000 [get_bd_addr_segs {microblaze_riscv_0/Data/SEG_axi_gpio_0_Reg}]

#------------------------------------------------------------------------------
# Validate and Save
#------------------------------------------------------------------------------
puts "Validating design..."
validate_bd_design

puts "Saving block design..."
save_bd_design

#------------------------------------------------------------------------------
# Generate Output Products
#------------------------------------------------------------------------------
puts "Generating output products..."
generate_target all [get_files $project_dir/$project_name.srcs/sources_1/bd/fluxripper_soc/fluxripper_soc.bd]

#------------------------------------------------------------------------------
# Create HDL Wrapper
#------------------------------------------------------------------------------
puts "Creating HDL wrapper..."
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/fluxripper_soc/fluxripper_soc.bd] -top
add_files -norecurse $project_dir/$project_name.gen/sources_1/bd/fluxripper_soc/hdl/fluxripper_soc_wrapper.v

puts "=========================================="
puts "FluxRipper SoC Milestone 0 Complete!"
puts "=========================================="
puts ""
puts "Memory Map:"
puts "  0x00000000 - Code BRAM (32KB)"
puts "  0x00010000 - Data BRAM (16KB)"
puts "  0x80001000 - AXI Timer"
puts "  0x80002000 - AXI UART Lite"
puts "  0x80006000 - AXI GPIO"
puts ""
puts "Next steps:"
puts "  1. Add constraints file for SCU35 pinout"
puts "  2. Create firmware project"
puts "  3. Build and test"
puts ""
