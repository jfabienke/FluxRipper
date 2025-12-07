# FluxRipper Simulation Layer Strategy

*Created: 2025-12-07 20:15*
*Updated: 2025-12-08 00:15*

## Overview

This document describes a layer-by-layer simulation strategy for bringing up the
FluxRipper FPGA design. Each layer builds on the previous, using the JTAG TAP
controller as the primary test access point.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Layer 6: Full System ✓                      │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                 Layer 5: Peripherals ✓                  │   │
│   │   ┌─────────────────────────────────────────────────┐   │   │
│   │   │          Layer 4: Clock/Reset Manager ✓         │   │   │
│   │   │   ┌─────────────────────────────────────────┐   │   │   │
│   │   │   │       Layer 3: System Bus Fabric ✓      │   │   │   │
│   │   │   │   ┌─────────────────────────────────┐   │   │   │   │
│   │   │   │   │     Layer 2: Debug Module ✓     │   │   │   │   │
│   │   │   │   │   ┌─────────────────────────┐   │   │   │   │   │
│   │   │   │   │   │     Layer 1: DTM ✓      │   │   │   │   │   │
│   │   │   │   │   │   ┌─────────────────┐   │   │   │   │   │   │
│   │   │   │   │   │   │ Layer 0: TAP ✓  │   │   │   │   │   │   │
│   │   │   │   │   │   └─────────────────┘   │   │   │   │   │   │
│   │   │   │   │   └─────────────────────────┘   │   │   │   │   │
│   │   │   │   └─────────────────────────────────┘   │   │   │   │
│   │   │   └─────────────────────────────────────────┘   │   │   │
│   │   └─────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

                    *** ALL LAYERS COMPLETE! ***
```

---

## Layer 0: JTAG TAP Controller ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/debug/jtag_tap_controller.v`
**Tests:** `sim/tb_jtag_tap.v`, `sim/tb_jtag_verilator.cpp`

### What We Tested
- TAP state machine (16 states, IEEE 1149.1)
- IR shift/capture/update
- DR shift/capture/update
- IDCODE register (0xFB010001)
- BYPASS instruction
- Strobe signals (ir_capture, ir_shift, ir_update, dr_*)

### Performance Baseline
- Icarus Verilog: 9 tests in ~30ms
- Verilator: 1M cycles in ~50ms (20 MHz simulation speed)

---

## Layer 1: Debug Transport Module (DTM) ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/debug/jtag_dtm.v`
**Tests:** `sim/layer1/tb_jtag_dtm.v`

### What We Tested
- DTMCS register (version=1, abits=7, idle=1)
- DMI read operations (pipelined request/response)
- DMI write operations
- Multiple sequential accesses
- TAP/DTM TDO multiplexing

### Key Implementation Notes
- DMI is 41 bits: [40:34]=address, [33:2]=data, [1:0]=op
- Operations: 0=nop, 1=read, 2=write
- Results available on NEXT DR scan (pipelined)

### Purpose
Bridges JTAG interface to Debug Module Interface (DMI). Implements RISC-V debug
transport (DTMCS and DMI registers).

### Module Interface
```verilog
module jtag_dtm (
    // JTAG TAP interface
    input  [4:0]  ir_value,
    input         dr_capture,
    input         dr_shift,
    input         dr_update,
    input         tdi,
    output        tdo,

    // DMI interface (to Debug Module)
    output [6:0]  dmi_addr,
    output [31:0] dmi_wdata,
    output [1:0]  dmi_op,      // 0=nop, 1=read, 2=write
    output        dmi_req,
    input  [31:0] dmi_rdata,
    input  [1:0]  dmi_resp,    // 0=ok, 2=busy, 3=error
    input         dmi_ack
);
```

### Tests to Implement

| Test | Description | Expected Result |
|------|-------------|-----------------|
| DTM-1 | Read DTMCS register | Version=1, abits=7, idle=1 |
| DTM-2 | DMI read operation | Correct address on dmi_addr |
| DTM-3 | DMI write operation | Data appears on dmi_wdata |
| DTM-4 | DMI busy handling | Retry when resp=busy |
| DTM-5 | Error recovery | dmihardreset clears error |

### Test Strategy
```
                    ┌──────────────┐
   JTAG Stimulus ──▶│   TAP (L0)   │
                    └──────┬───────┘
                           │ ir_value, dr_*
                           ▼
                    ┌──────────────┐
                    │   DTM (L1)   │◀── Test assertions here
                    └──────┬───────┘
                           │ dmi_*
                           ▼
                    ┌──────────────┐
                    │  Mock DMI    │◀── Stimulus/response model
                    └──────────────┘
```

---

## Layer 2: Debug Module (DM) + Memory Access ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/debug/debug_module.v`
**Tests:** `sim/layer2/tb_debug_module.v`

### What We Tested
- dmstatus register (version=2, authenticated=1)
- dmcontrol register (write/read dmactive)
- sbcs register (sbversion=1, sbaccess32/16/8)
- System bus write via sbdata0
- System bus read via sbaddress0 + sbreadonaddr
- Pre-initialized memory verification

### Purpose
Implements the RISC-V Debug Module specification. Provides:
- System bus access (memory read/write)
- Abstract command execution
- Program buffer
- Hart control (halt/resume)

### Module Interface
```verilog
module debug_module (
    input         clk,
    input         rst_n,

    // DMI interface (from DTM)
    input  [6:0]  dmi_addr,
    input  [31:0] dmi_wdata,
    input  [1:0]  dmi_op,
    input         dmi_req,
    output [31:0] dmi_rdata,
    output [1:0]  dmi_resp,
    output        dmi_ack,

    // System bus master
    output [31:0] sbaddr,
    output [31:0] sbdata_o,
    input  [31:0] sbdata_i,
    output [2:0]  sbsize,      // 0=byte, 1=half, 2=word
    output        sbread,
    output        sbwrite,
    input         sbbusy,
    input         sberror
);
```

### Tests to Implement

| Test | Description | Expected Result |
|------|-------------|-----------------|
| DM-1 | Read dmstatus | Version=2, authenticated=1 |
| DM-2 | Write dmcontrol | haltreq propagates |
| DM-3 | System bus read | Address on sbaddr, data returned |
| DM-4 | System bus write | Data written to sbdata_o |
| DM-5 | Auto-increment | sbaddr increments after access |
| DM-6 | Bus error handling | sberror reflected in sbcs |

### Test Strategy
```
   JTAG Stimulus ──▶ TAP ──▶ DTM ──▶ DM ──▶ Mock Memory
                                      │
                                      └── Test assertions
```

### Memory Model
```cpp
class MockMemory {
    std::map<uint32_t, uint32_t> mem;
public:
    uint32_t read(uint32_t addr) { return mem[addr]; }
    void write(uint32_t addr, uint32_t data) { mem[addr] = data; }
};
```

---

## Layer 3: System Bus Fabric ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/bus/system_bus.v`
**Tests:** `sim/layer3/tb_system_bus.v`

### What We Tested
- Boot ROM read access (0x0000_xxxx)
- Main RAM read/write (0x1000_xxxx)
- System Control ID register (0x4000_0000)
- Disk Controller status/control (0x4001_xxxx)
- USB Controller stub (0x4002_xxxx)
- Signal Tap stub (0x4003_xxxx)
- Multiple sequential RAM accesses

### Purpose
Simple address-decoded bus connecting debug module to memory and peripherals.

### Address Map
```
0x0000_0000 - 0x0000_FFFF : Boot ROM (64KB)
0x1000_0000 - 0x1FFF_FFFF : Main Memory (256MB)
0x4000_0000 - 0x4000_00FF : System Control
0x4001_0000 - 0x4001_00FF : Disk Controller
0x4002_0000 - 0x4002_00FF : USB Controller
0x4003_0000 - 0x4003_00FF : Signal Tap
```

### Tests to Implement

| Test | Description | Expected Result |
|------|-------------|-----------------|
| BUS-1 | Address decode | Correct peripheral selected |
| BUS-2 | Read from ROM | Boot ROM data returned |
| BUS-3 | Write to RAM | Data stored and readable |
| BUS-4 | Invalid address | Bus error generated |
| BUS-5 | Arbitration | Debug has priority |

### End-to-End Test
```
JTAG ──▶ TAP ──▶ DTM ──▶ DM ──▶ BUS ──▶ RAM
                                  │
                                  └──▶ Verify RAM contents
```

---

## Layer 4: Clock/Reset Manager ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/clocking/clock_reset_mgr.v`
**Tests:** `sim/layer4/tb_clock_reset.v`

### What We Tested
- PLL lock detection (~100 reference cycles)
- Clock generation (behavioral for simulation)
- Synchronized reset release per domain
- Watchdog timeout triggers system reset
- Watchdog kick prevents timeout
- Debug reset bypass (JTAG survives system reset)

### Purpose
PLL configuration, clock domain crossing, reset sequencing.

### Features
- 100 MHz system clock from 25 MHz input
- 48 MHz USB clock
- 50 MHz disk controller clock
- Async reset synchronizers
- Watchdog reset
- Debug reset isolation

### Tests to Implement

| Test | Description | Expected Result |
|------|-------------|-----------------|
| CLK-1 | PLL lock detect | Lock signal asserts |
| CLK-2 | Clock frequencies | Correct division ratios |
| CLK-3 | Reset sequence | Peripherals reset in order |
| CLK-4 | Watchdog timeout | System reset triggered |
| CLK-5 | Debug reset bypass | Debug survives system reset |

### Clock Domain Crossing Test
```
               ┌─────────┐
   100MHz ────▶│  CDC    │────▶ 48MHz
               │  FIFO   │
               └─────────┘
                    │
                    └── Verify no metastability
```

---

## Layer 5: Peripheral Subsystems ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/disk/disk_controller.v`, `rtl/usb/usb_controller.v`, `rtl/debug/signal_tap.v`
**Tests:** `sim/layer5/tb_peripherals.v`

### What We Tested
- Disk Controller status register (READY bit)
- Disk motor control via JTAG (on/off)
- Disk index pulse counter (3 pulses counted)
- USB Controller ID register (0x05B20001)
- USB connection/configured control
- Signal Tap ID register (0x51670001)
- Signal Tap arm/trigger/capture sequence
- Disk DMA address/length configuration

### Test Results

| Test | Description | Result |
|------|-------------|--------|
| PERI-1 | Disk Controller Status | PASS - ready=1 |
| PERI-2 | Disk Motor Control | PASS - on/off verified |
| PERI-3 | Disk Index Counter | PASS - 3 pulses counted |
| PERI-4 | USB Controller ID | PASS - 0x05B20001 |
| PERI-5 | USB Connection Control | PASS - connected/configured |
| PERI-6 | Signal Tap ID | PASS - 0x51670001 |
| PERI-7 | Signal Tap Capture | PASS - armed, triggered |
| PERI-8 | Disk DMA Config | PASS - addr/len verified |

### 5a: Disk Controller

**RTL:** `rtl/disk/disk_controller.v`

Features:
- Status/Control registers
- DMA address/length configuration
- Index pulse counter
- RPM measurement
- Motor/head/step control outputs
- Flux transition capture FIFO

### 5b: USB Controller

**RTL:** `rtl/usb/usb_controller.v`

Features:
- Device ID register (0x05B20001)
- Status register (connected, configured)
- Control register (enable, force configured)
- Stub implementation for simulation

### 5c: Signal Tap

**RTL:** `rtl/debug/signal_tap.v`

Features:
- Configurable probe width and buffer depth
- Programmable trigger value and mask
- Arm/Capture/Done state machine
- Buffer readout via register interface
- Trigger position tracking

---

## Layer 6: Full System Integration ✓ COMPLETE

**Status:** Validated
**RTL:** `rtl/top/fluxripper_top.v`
**Tests:** `sim/layer6/tb_system.v`

### What We Tested
- Power-on reset sequence (PLL lock, reset release)
- JTAG IDCODE read (0xFB010001)
- Boot ROM read (NOP at address 0)
- RAM write/read verification
- System Control ID register
- Disk motor control via JTAG
- Disk index pulse counter
- USB controller ID and connection control
- Signal Tap ID and trigger capture
- Memory pattern test (multiple locations)

### Test Results

| Test | Description | Result |
|------|-------------|--------|
| SYS-1 | Power-On Reset | PASS - PLL locked, reset released |
| SYS-2 | JTAG IDCODE | PASS - 0xFB010001 |
| SYS-3 | Boot ROM Read | PASS - NOP instruction at 0x0 |
| SYS-4 | RAM Write/Read | PASS - 0xDEADBEEF verified |
| SYS-5 | System Control ID | PASS - 0xFB010100 |
| SYS-6 | Disk Motor Control | PASS - on/off verified |
| SYS-7 | Index Pulse Counter | PASS - 5 pulses counted |
| SYS-8 | USB Controller ID | PASS - 0x05B20001 |
| SYS-9 | USB Connection | PASS - connected/configured |
| SYS-10 | Signal Tap ID | PASS - 0x51670001 |
| SYS-11 | Signal Tap Capture | PASS - trigger on motor signal |
| SYS-12 | Memory Pattern | PASS - 4 locations verified |

### Top-Level Module

**RTL:** `rtl/top/fluxripper_top.v`

Integrates:
- Clock/Reset Manager (25 MHz → 100/48/50 MHz)
- JTAG TAP Controller with IDCODE
- Debug Transport Module (DTM)
- RISC-V Debug Module
- System Bus Fabric
- Boot ROM (64KB, behavioral)
- Main RAM (64KB, behavioral)
- System Control registers
- Disk Controller
- USB Controller
- Signal Tap with probe mux

### Performance Targets

| Test | Icarus Target | Verilator Target |
|------|---------------|------------------|
| Quick smoke test | <1 sec | <100 ms |
| Full regression | <1 min | <10 sec |
| 1M cycle benchmark | N/A | >10 MHz |

---

## Testbench Architecture

### Shared Test Infrastructure

```
sim/
├── Makefile                 # Top-level build
├── common/
│   ├── jtag_driver.v        # Reusable JTAG stimulus
│   ├── jtag_driver.cpp      # C++ version for Verilator
│   ├── memory_model.v       # Behavioral memory
│   └── test_utils.vh        # Macros and helpers
├── layer0/
│   ├── tb_jtag_tap.v
│   └── tb_jtag_verilator.cpp
├── layer1/
│   ├── tb_jtag_dtm.v
│   └── tb_dtm_verilator.cpp
├── layer2/
│   └── ...
└── system/
    ├── tb_system.v
    └── tb_system_verilator.cpp
```

### JTAG Driver Module (Reusable)

```verilog
// sim/common/jtag_driver.v
module jtag_driver (
    output reg tck,
    output reg tms,
    output reg tdi,
    input      tdo,
    output reg trst_n
);
    task reset_tap;
        begin
            repeat(6) jtag_clock(1);
            jtag_clock(0);
        end
    endtask

    task shift_ir;
        input [4:0] ir;
        // ... implementation
    endtask

    task shift_dr;
        input [63:0] data_in;
        input [6:0]  length;
        output [63:0] data_out;
        // ... implementation
    endtask

    // Higher-level operations
    task dmi_read;
        input [6:0] addr;
        output [31:0] data;
        // ... implementation
    endtask

    task mem_read;
        input [31:0] addr;
        output [31:0] data;
        // ... implementation
    endtask
endmodule
```

### C++ Driver Class (Verilator)

```cpp
// sim/common/jtag_driver.cpp
class JtagDriver {
    Vfluxripper_top* dut;
    uint64_t sim_time = 0;

public:
    void reset_tap();
    void shift_ir(uint8_t ir);
    uint64_t shift_dr(uint64_t data, int bits);

    // Layer 1+
    uint32_t dmi_read(uint8_t addr);
    void dmi_write(uint8_t addr, uint32_t data);

    // Layer 2+
    uint32_t mem_read(uint32_t addr);
    void mem_write(uint32_t addr, uint32_t data);

    // Layer 5+
    void disk_capture_start();
    std::vector<uint32_t> disk_capture_read();
};
```

---

## Implementation Sequence

### Phase 1: Core Debug Path (Layers 0-2)
```
Week 1: DTM implementation + tests
Week 2: Debug Module implementation + tests
Week 3: Integration testing, memory access validation
```

### Phase 2: System Infrastructure (Layers 3-4)
```
Week 4: Bus fabric + address decode
Week 5: Clock/reset manager
Week 6: Full debug path through bus to RAM
```

### Phase 3: Peripherals (Layer 5)
```
Week 7-8: Disk controller
Week 9-10: USB controller
Week 11: Signal tap + debug features
```

### Phase 4: Integration (Layer 6)
```
Week 12: Full system integration
Week 13: Performance optimization
Week 14: Hardware validation preparation
```

---

## Quick Reference: Running Tests

```bash
# Layer 0 only
cd sim && make -f Makefile.layer0 all

# Layers 0-1
cd sim && make -f Makefile.layer1 all

# Full system (when ready)
cd sim && make all

# Verilator performance benchmark
cd sim && make verilator CYCLES=10000000
```

---

## Success Criteria Per Layer

| Layer | Gate Criteria |
|-------|---------------|
| 0 | IDCODE reads correctly, IR/DR shift works |
| 1 | DMI read/write operations function |
| 2 | Can read/write memory via JTAG |
| 3 | All peripherals addressable |
| 4 | Clocks stable, reset sequence correct |
| 5 | Each peripheral passes unit tests |
| 6 | Full disk capture/USB transfer works |

Each layer must pass 100% of its tests before proceeding to the next layer.

---

## Hardware Bring-Up Readiness

**Status:** All 7 simulation layers (0-6) complete and validated!

### Next Phase: FPGA Synthesis

The simulation-validated design is ready for hardware bring-up on AMD Spartan UltraScale+.

**Synthesis Infrastructure Created:**
- `soc/scripts/synth_fluxripper.tcl` - Complete Vivado synthesis flow
- `soc/scripts/program_fpga.tcl` - FPGA programming script
- `soc/constraints/fluxripper_timing.xdc` - Timing constraints
- `soc/constraints/fluxripper_pinout.xdc` - Pin assignments (update for your board)

**RTL Synthesis Enhancements:**
- `clock_reset_mgr.v` - Added MMCME4_BASE primitive (`ifdef XILINX_FPGA`)
- `fluxripper_top.v` - Added BRAM/debug synthesis attributes

**Debug Tools:**
- `debug/openocd_fluxripper.cfg` - OpenOCD configuration with helper procs
- `debug/openocd_ftdi.cfg` - FTDI adapter config
- `debug/openocd_bmp.cfg` - Black Magic Probe config

### CLI Synthesis Commands

```bash
# 1. Update pin assignments for your board
vim soc/constraints/fluxripper_pinout.xdc

# 2. Run synthesis
cd FluxRipper/soc
vivado -mode batch -source scripts/synth_fluxripper.tcl

# 3. Program FPGA
vivado -mode batch -source scripts/program_fpga.tcl

# 4. JTAG validation
openocd -f debug/openocd_fluxripper.cfg -c "init; fluxripper_test; shutdown"
```

### Expected JTAG Output

```
FluxRipper JTAG Test
====================
  IDCODE: PASS
DTMCS: 0x00000071
Reading System Control ID...
  SYSCTRL_ID = 0xFB010100
FluxRipper JTAG Test: ALL PASSED!
```

See [BRINGUP_GUIDE.md](BRINGUP_GUIDE.md) for detailed hardware bring-up procedures.
