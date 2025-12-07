# FluxRipper FPGA Documentation

*Updated: 2025-12-07 12:16*

## Overview

FluxRipper is an FPGA-based System-on-Chip that implements an enhanced Intel 82077AA Floppy Disk Controller clone with comprehensive diagnostic capabilities. The HDL design is derived from the CAPSImg library's FDC emulator.

**Key Features:**
- Dual Shugart interface support (4 drives total)
- Parallel flux capture for high-throughput imaging
- Disk-to-disk copy capability
- Full 82077AA command compatibility
- Multi-format support: MFM, FM, GCR (CBM/Apple), M2FM, Tandy

## FluxRipper Universal Card

The FluxRipper Universal is a multi-host PCB design that functions as:

| Mode | Power Source | Host Interface | Use Case |
|------|--------------|----------------|----------|
| **ISA Card** | ISA bus +5V/+12V | ISA (3F0-3F7, DMA, IRQ) | Retro PC restoration |
| **USB Device** | USB-C (host) | USB 2.0 HS (480 Mbps) | Cross-platform tool (primary) |
| **Standalone** | USB-C PD (charger) | USB serial console | Portable disk utility |

**Note:** PCIe removed—XCSU35P has 0 GTH transceivers. USB 2.0 HS via ULPI PHY is the primary high-speed interface.

### Universal Card Features

- **MicroSD Card Slot** - Standalone disk image storage (.IMG, .ADF, .D64, etc.)
- **Real-Time Clock** - PCF8563 with CR2032 backup for accurate FAT timestamps
  - ISA-accessible as AT-compatible RTC (ports 0x70-0x71) for XT clones
- **Rotary Encoder** - EC11 with push button for menu-driven standalone operation
- **SPI OLED Display** - 128×64 SSD1306 for status and navigation
- **ISA Plug and Play** - Auto-configuration for Windows 95+ and PnP BIOS
- **8" Drive Support** - Native 50-pin Shugart with HEAD_LOAD and +24V rail
- **Per-Drive Power Monitoring** - INA3221 for voltage/current on all drives

## Project Status

**HDL Implementation: ~98% Complete**
**Simulation: ✅ ALL LAYERS VALIDATED** (Layers 0-6)
**Hardware: 🔜 Ready for FPGA Bring-Up**

### Simulation Validation Summary

| Layer | Component | Tests | Status |
|-------|-----------|-------|--------|
| 0 | JTAG TAP Controller | 9 | ✅ Pass |
| 1 | Debug Transport Module | 5 | ✅ Pass |
| 2 | Debug Module + Memory | 6 | ✅ Pass |
| 3 | System Bus Fabric | 7 | ✅ Pass |
| 4 | Clock/Reset Manager | 5 | ✅ Pass |
| 5 | Peripheral Subsystems | 8 | ✅ Pass |
| 6 | Full System Integration | 12 | ✅ Pass |

All testbenches run with Icarus Verilog. See [SIMULATION_LAYERS.md](SIMULATION_LAYERS.md) for details.

### Implemented Modules

#### Core FDC
- ✅ Top-level integration (`fluxripper_top.v`)
- ✅ Command FSM with Type 1-4 commands (`command_fsm.v`)
- ✅ Register interface - 82077AA compatible (`fdc_registers.v`)

#### Data Path
- ✅ Digital PLL with adaptive bandwidth (`digital_pll.v` + submodules)
- ✅ MFM encoder/decoder with sync mark support
- ✅ FM encoder/decoder (`fm_codec.v`)
- ✅ GCR encoder/decoder - CBM & Apple formats
- ✅ Encoding multiplexer for format selection
- ✅ AM detector for A1/C2 sync marks
- ✅ CRC-16 CCITT (table + serial versions)

#### Drive Control
- ✅ Step controller with double-step support
- ✅ Motor controller with auto-off
- ✅ Index pulse handler with RPM detection
- ✅ Write precompensation

#### Diagnostics
- ✅ Flux capture diagnostic module
- ✅ Signal quality monitor

#### AXI Infrastructure (for SCU35 SoC)
- ✅ AXI-Stream flux capture interface (`axi_stream_flux.v`)
- ✅ AXI4-Lite FDC peripheral wrapper (`axi_fdc_periph.v`)

#### Dual Shugart Interface (NEW)
- ✅ FDC core instance wrapper (`fdc_core_instance.v`)
- ✅ Dual-FDC top level (`fluxripper_dual_top.v`)
- ✅ Dual index handler for 4 drives (`index_handler_dual.v`)
- ✅ Dual AXI4-Lite peripheral (`axi_fdc_periph_dual.v`)
- ✅ Dual AXI-Stream flux capture (`axi_stream_flux_dual.v`)
- ✅ Dual interface pin constraints (`scu35_dual_pinout.xdc`)

### Statistics
- **131 RTL modules** (~56,000 lines of Verilog)
- **19 Testbenches** (~10,400 lines)
- **SoC Firmware** (~15,000 lines of C)
- **Test vectors** from CAPSImg

### Remaining (Requires Hardware)
- Pin assignments for SCU35 evaluation board
- Level shifter interface (5V TTL ↔ 3.3V LVCMOS)
- Hardware validation and timing closure
- Integration testing with physical drives

## Target Platform

**AMD Spartan UltraScale+ SCU35 Evaluation Kit** ($229 USD)
- FPGA: XCSU35P-2SBVB625E (36K Logic Cells)
- Block RAM: 1.93 Mb (53 × 36Kb blocks, configurable as 106 × 18Kb)
- DSP Slices: 48
- External RAM: 8 MB HyperRAM (40+ track buffer)
- Connectivity: 2× Raspberry Pi 40-pin headers (for floppy interface)
- Soft Core: MicroBlaze V (AMD's RISC-V soft processor)

## Documentation Index

### Architecture
- [architecture.md](architecture.md) - System architecture, clock domains, CDC strategy
- [register_map.md](register_map.md) - 82077AA register interface, AXI4-Lite map
  - [82077AA Compatibility](register_map.md#82077aa-compatibility-notes) - Implemented commands, edge cases
  - [Signal Quality Algorithm](register_map.md#signal-quality-algorithm) - Metric derivation, thresholds

### Hardware Reference
- [drive_support.md](drive_support.md) - Comprehensive drive compatibility guide
  - [Supported Drive Families](drive_support.md#supported-drive-families) - 3.5", 5.25", 8" drives
  - [Track Density (TPI)](drive_support.md#track-density-tpi-support) - 48, 96, 100, 135 TPI handling
  - [Data Rates & Encoding](drive_support.md#data-rate-support) - MFM, FM, GCR configurations
  - [Physical Interface](drive_support.md#physical-interface-reference) - 34-pin and 50-pin Shugart pinouts
  - [Platform-Specific Notes](drive_support.md#platform-specific-notes) - Apple II, Commodore, Amiga, 8" drives

### Applications
- [use_cases.md](use_cases.md) - Comprehensive guide to FluxRipper applications
  - [Retrocomputing & Preservation](use_cases.md#1-retrocomputing--preservation) - Archival rigs, exotic formats
  - [Copy Protection & Forensics](use_cases.md#2-copy-protection-forensics--analysis) - Protection analysis, disk authenticity
  - [Hardware R&D](use_cases.md#3-drive-characterization--hardware-rd) - Drive characterization, media studies
  - [Software Development](use_cases.md#4-software--os--driver-development) - Driver testing, CI/CD integration
  - [Live Tools](use_cases.md#5-disk-to-disk--live-tools) - Smart copiers, network analyzers
  - [Teaching & Research](use_cases.md#6-teaching--research) - Lab exercises, ML datasets
  - [Emulation & Hybrid](use_cases.md#7-emulation--hybrid-systems) - Live bridges, ISA integration

### RTL Module Structure
```
rtl/
├── top/               # Top-level integration
│   ├── fluxripper_top.v         # Main top with JTAG debug
│   ├── fluxripper_dual_top.v    # Dual-interface (4 drives)
│   └── fluxripper_hdd_top.v     # HDD controller top
├── fdc_core/          # FDC command FSM, registers
├── hdd_controller/    # WD1003-compatible HDD controller
│   ├── wd_command_fsm.v         # WD command state machine
│   ├── wd_registers.v           # WD register interface
│   └── wd_track_buffer.v        # Track buffer management
├── data_separator/    # Digital PLL (8 submodules)
├── encoding/          # FDD: MFM, FM, GCR, M2FM, Tandy, Agat
│   └── ...            # HDD: RLL(2,7), ESDI encoder/decoder
├── drive_interface/   # ST-506/ESDI physical interface
│   ├── st506_interface.v        # ST-506 MFM/RLL interface
│   ├── esdi_phy.v               # ESDI physical layer
│   ├── esdi_cmd.v               # ESDI command channel
│   └── hdd_seek_controller.v    # HDD head positioning
├── diagnostics/       # Flux capture, HDD discovery
│   ├── hdd_discovery_fsm.v      # Auto-detect HDD parameters
│   ├── hdd_geometry_scanner.v   # CHS geometry detection
│   ├── hdd_health_monitor.v     # SMART-like monitoring
│   └── instrumentation_regs.v   # Performance counters
├── detection/         # Phase 0 interface detection
│   ├── interface_detector.v     # FDD vs HDD auto-detect
│   ├── data_path_sniffer.v      # Signal analysis
│   └── signal_quality_scorer.v  # Quality metrics
├── recovery/          # FluxStat statistical recovery
│   ├── flux_histogram.v         # Weak bit histogram
│   └── multipass_capture.v      # Multi-pass averaging
├── dsp/               # Signal processing
│   ├── fir_flux_filter.v        # FIR filter for flux
│   ├── prml_decoder.v           # PRML for HDD
│   └── adaptive_equalizer.v     # Adaptive EQ
├── usb/               # USB 2.0 HS (ULPI PHY)
│   ├── usb_top_v2.v             # USB top-level
│   ├── usb_device_core_v2.v     # Packet handling
│   ├── usb_hs_negotiator.v      # HS chirp FSM
│   ├── ulpi_wrapper_v2.v        # ULPI ↔ UTMI
│   ├── usb_descriptor_rom.v     # 4-personality descriptors
│   ├── kf_protocol.v            # KryoFlux compatibility
│   ├── gw_protocol.v            # Greaseweazle compatibility
│   └── msc_protocol.v           # Mass Storage Class
├── host/              # ISA bus interface
│   ├── isa_bus_bridge.v         # ISA protocol bridge
│   ├── isa_pnp_controller.v     # ISA Plug and Play
│   └── isa_option_rom.v         # ISA Option ROM
├── debug/             # JTAG debug subsystem
│   ├── jtag_tap_controller.v    # IEEE 1149.1 TAP
│   ├── jtag_dtm.v               # Debug Transport Module
│   ├── debug_module.v           # RISC-V DM 0.13
│   └── signal_tap.v             # Logic analyzer
├── clocking/          # Clock generation
│   ├── clock_reset_mgr.v        # MMCM + reset sync
│   └── clk_wizard_hdd.v         # HDD clock domains
├── bus/               # System bus fabric
│   └── system_bus.v             # Address decode + arbiter
├── periph/            # I2C, SPI peripherals
│   └── i2c_master.v             # INA3221, RTC access
└── axi/               # AXI infrastructure
    ├── axi_fdc_periph.v         # FDC AXI4-Lite
    └── axi_wd_periph.v          # WD HDD AXI4-Lite
```

### Simulation
```
tb/                        # Component testbenches
├── tb_digital_pll.v       # DPLL lock & tracking
├── tb_encoding.v          # MFM/FM/GCR encode/decode
├── tb_rll_2_7.v           # RLL(2,7) HDD encoding
├── tb_esdi.v              # ESDI interface
├── tb_wd_controller.v     # WD1003 HDD controller
├── tb_hdd_discovery.v     # HDD auto-discovery
├── tb_usb_top_v2.v        # USB 2.0 stack
├── tb_interface_detector.v # FDD/HDD auto-detect
└── tb_fluxstat.v          # Statistical recovery

sim/                       # Layered system tests
├── layer1/                # JTAG DTM tests
├── layer2/                # Debug Module tests
├── layer3/                # System Bus tests
├── layer4/                # Clock/Reset tests
├── layer5/                # Peripheral tests
├── layer6/                # Full system integration
└── Makefile               # Main simulation driver
```

## Resource Budget

### Single FDC Core Modules
| Block | LUTs | FFs | BRAM (18Kb) | DSP |
|-------|------|-----|-------------|-----|
| DPLL Core | 313 | 192 | 0 | 0 |
| AM Detector + Shifter | 180 | 96 | 0 | 0 |
| CRC-CCITT | 85 | 32 | 0.5 | 0 |
| 16-byte FIFO | 120 | 144 | 0 | 0 |
| MFM Encode/Decode | 80 | 0 | 9.0 | 0 |
| FM/GCR Tables | 200 | 0 | 8.5 | 0 |
| Command FSM | 510 | 280 | 0 | 0 |
| Register Interface | 150 | 96 | 0 | 0 |
| Step Controller | 220 | 104 | 0 | 0 |
| Motor Controller | 180 | 120 | 0 | 0 |
| Write Precompensation | 170 | 48 | 0 | 0 |
| Index Handler | 120 | 80 | 0 | 0 |
| Flux Capture | 200 | 48 | 8.5 | 0 |
| Signal Quality Monitor | 150 | 80 | 0 | 1 |
| **Subtotal (1x FDC)** | **~2,700** | **~1,400** | **~27** | **1** |

### Dual Interface Infrastructure
| Block | LUTs | FFs | BRAM (18Kb) | DSP |
|-------|------|-----|-------------|-----|
| FDC Core Instance (x2) | 5,400 | 2,800 | 54 | 2 |
| Index Handler Dual | 180 | 160 | 0 | 0 |
| AXI-Stream Flux Dual | 500 | 400 | 2.0 | 0 |
| AXI4-Lite FDC Dual | 550 | 420 | 0 | 0 |
| **Subtotal (Dual FDC)** | **~6,630** | **~3,780** | **~56** | **2** |

### AXI Infrastructure (SCU35 SoC)
| Block | LUTs | FFs | BRAM (18Kb) | DSP |
|-------|------|-----|-------------|-----|
| MicroBlaze V (est.) | 3,500 | 2,000 | 16 | 3 |
| AXI Interconnect (est.) | 800 | 400 | 0 | 0 |
| AXI DMA Controller (2ch) | 900 | 450 | 4 | 0 |
| HyperRAM Controller (est.) | 400 | 200 | 0 | 0 |
| **Subtotal (SoC)** | **~5,600** | **~3,050** | **~20** | **3** |

### HDD Support Modules (ST-506/ESDI)
| Block | LUTs | FFs | BRAM (18Kb) | DSP |
|-------|------|-----|-------------|-----|
| Clock Wizard HDD (300 MHz) | 50 | 30 | 0 | 0 |
| NCO HDD | 150 | 80 | 0 | 0 |
| RLL(2,7) Encoder | 180 | 60 | 2 | 0 |
| RLL(2,7) Decoder | 200 | 80 | 2 | 0 |
| ESDI Encoder | 220 | 90 | 2 | 0 |
| ESDI Decoder | 280 | 120 | 2 | 0 |
| ST-506 Interface | 180 | 100 | 0 | 0 |
| HDD Seek Controller | 200 | 120 | 0 | 0 |
| ESDI PHY | 250 | 100 | 0 | 0 |
| HDD Discovery FSM | 350 | 200 | 0 | 0 |
| HDD Rate Detector | 200 | 100 | 1 | 0 |
| HDD Geometry Scanner | 300 | 150 | 0 | 0 |
| HDD Health Monitor | 220 | 100 | 0 | 0 |
| HDD PHY Probe | 180 | 80 | 0 | 0 |
| **Subtotal (HDD)** | **~2,960** | **~1,410** | **~9** | **0** |

### Phase 0 Interface Detection
| Block | LUTs | FFs | BRAM (18Kb) | DSP |
|-------|------|-----|-------------|-----|
| Interface Detector FSM | 280 | 150 | 0 | 0 |
| Data Path Sniffer | 250 | 120 | 0 | 0 |
| Correlation Calculator | 160 | 80 | 0 | 0 |
| Signal Quality Scorer | 200 | 100 | 0 | 0 |
| Index Frequency Counter | 120 | 60 | 0 | 0 |
| **Subtotal (Detection)** | **~1,010** | **~510** | **0** | **0** |

### FluxStat Recovery Modules
| Block | LUTs | FFs | BRAM (18Kb) | DSP |
|-------|------|-----|-------------|-----|
| Flux Histogram (256 bins) | 200 | 120 | 2 | 0 |
| Multipass Capture FSM | 280 | 180 | 1 | 0 |
| **Subtotal (FluxStat)** | **~480** | **~300** | **~3** | **0** |

### Total (Full System - Dual-FDC + HDD + FluxStat)
| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | ~14,800 | 36,000 | ~41.1% |
| FFs | ~8,020 | 36,000 | ~22.3% |
| BRAM (18Kb eq.) | ~68 | 106 | ~64.2% |
| DSP | 6 | 48 | ~12.5% |

*Headroom: 59% LUTs, 78% FFs, 36% BRAM, 87.5% DSP remaining for future enhancements.*

### Resource Summary by Feature
| Configuration | LUTs | FFs | BRAM | Notes |
|--------------|------|-----|------|-------|
| Floppy-only (Dual FDC) | ~10,350 | ~5,800 | ~54 | Base configuration |
| + HDD Support | +2,960 | +1,410 | +9 | ST-506/ESDI |
| + Interface Detection | +1,010 | +510 | +0 | Phase 0 auto-detect |
| + FluxStat | +480 | +300 | +3 | Statistical recovery |
| **Full System** | **~14,800** | **~8,020** | **~68** | All features enabled |

*All estimates based on AMD Spartan UltraScale+ (XCSU35P-2SBVB625E) with 36K Logic Cells.*

## Quick Start

### Simulation (without hardware)
```bash
cd sim
make all           # Run all core testbenches
make sim_dpll      # Digital PLL only
make sim_encoding  # Encoding modules
make sim_crc       # CRC verification
make sim_top       # Top-level integration
make sim_axi       # AXI infrastructure tests
make lint          # Verilator lint check

# Layer-by-layer simulation
cd sim/layer6 && make   # Full system test (12 tests)
```

### Synthesis (Vivado CLI)

The project includes TCL scripts for fully automated synthesis:

```bash
# 1. Update pin constraints for your board
vim soc/constraints/fluxripper_pinout.xdc

# 2. Run synthesis (creates bitstream)
cd soc
vivado -mode batch -source scripts/synth_fluxripper.tcl

# 3. Program FPGA
vivado -mode batch -source scripts/program_fpga.tcl

# 4. Verify JTAG connectivity
openocd -f debug/openocd_fluxripper.cfg -c "init; fluxripper_test; shutdown"
```

See [BRINGUP_GUIDE.md](BRINGUP_GUIDE.md) for detailed hardware bring-up procedures.

### Synthesis (Vivado GUI)
1. Open Vivado 2024.1 or later (for SCU35 support)
2. Create new project for Spartan UltraScale+ (xcsu35p-2sbvb625e)
3. Add all RTL files from `rtl/` subdirectories including `rtl/axi/`
4. Add constraints from `soc/constraints/`
5. Define `XILINX_FPGA` to enable MMCM primitives
6. Run synthesis and implementation

## Supported Disk Formats

| Format | Encoding | Data Rate | Status |
|--------|----------|-----------|--------|
| IBM PC 1.44MB | MFM | 500 Kbps | ✅ |
| IBM PC 720KB | MFM | 250 Kbps | ✅ |
| IBM PC 1.2MB | MFM | 500 Kbps | ✅ |
| IBM PC 360KB | MFM | 250 Kbps | ✅ |
| FM (legacy) | FM | 125/250 Kbps | ✅ |
| Commodore 1541 | GCR-CBM | Variable | ✅ |
| Apple II DOS 3.3 | GCR-6bit | Variable | ✅ |
| Apple II DOS 3.2 | GCR-5bit | Variable | ✅ |

*Note: Format support implemented per CAPSImg behavioral model, pending hardware validation. SCAN commands (0x11, 0x19, 0x1D) and tape-oriented operations are not implemented.*

## License

See LICENSE file in repository root.
