# FluxRipper FPGA Documentation

*Updated: 2025-12-03 23:45*

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
| **PCIe Card** | PCIe slot +3.3V/+12V | PCIe BAR0, MSI-X | Modern PC integration |
| **USB Device** | USB-C (host) | USB CDC/Bulk | Cross-platform tool |
| **Standalone** | USB-C PD (charger) | USB serial console | Portable disk utility |

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

**HDL Implementation: ~95% Complete** (without hardware testing)

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
- **30 RTL modules** (~10,500 lines of Verilog)
- **4 Core Testbenches** + **4 AXI/Dual Testbenches** (2,600+ lines)
- **1 Test vector file** with CAPSImg patterns

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
│   ├── fluxripper_top.v         # Single-interface top
│   ├── fluxripper_dual_top.v    # Dual-interface top (4 drives)
│   └── fluxripper_universal_top.v # Universal card top (ISA/PCIe/USB)
├── fdc_core/          # Command FSM, registers
│   ├── command_fsm.v            # FDC command state machine
│   ├── fdc_registers.v          # 82077AA register interface
│   └── fdc_core_instance.v      # FDC instance wrapper (for dual)
├── data_separator/    # Digital PLL (6 submodules)
│   └── zone_calculator.v        # Mac GCR variable-speed zones
├── am_detector/       # Address mark detection
├── encoding/          # MFM, FM, GCR, M2FM, Tandy codecs
│   ├── mfm_codec.v              # MFM encode/decode
│   ├── fm_codec.v               # FM encode/decode
│   ├── gcr_apple.v              # Apple GCR 5&3 / 6&2
│   ├── gcr_cbm.v                # Commodore GCR
│   ├── m2fm_codec.v             # DEC/Intel M2FM
│   └── tandy_sync.v             # Tandy/CoCo FM sync
├── crc/               # CRC-16 CCITT
├── drive_ctrl/        # Step, motor, index
│   ├── step_controller.v        # Head positioning
│   ├── motor_controller.v       # Motor control (4-drive)
│   └── index_handler_dual.v     # 4-index handler with RPM
├── write_path/        # Write precompensation
├── diagnostics/       # Flux capture, quality, drive profile
│   ├── flux_capture.v           # Flux transition capture
│   ├── flux_analyzer.v          # Data rate detection
│   └── drive_profile_detector.v # Auto-detect drive characteristics
├── host_interface/    # Universal card host adapters
│   ├── host_interface.v         # Unified register abstraction
│   ├── host_isa_adapter.v       # ISA bus protocol + DMA
│   ├── host_usb_adapter.v       # USB via FT232H
│   ├── isa_dma_controller.v     # ISA DMA channels
│   ├── isa_pnp_controller.v     # ISA Plug and Play
│   └── isa_cdc.v                # ISA clock domain crossing
├── peripherals/       # Universal card peripherals
│   ├── spi_oled_driver.v        # SSD1306 OLED
│   ├── oled_framebuffer.v       # 128x64 pixel buffer
│   └── power_manager.v          # USB-C PD status
└── axi/               # AXI infrastructure for SoC
    ├── axi_stream_flux.v        # Single AXI-Stream master
    ├── axi_stream_flux_dual.v   # Dual AXI-Stream (parallel capture)
    ├── axi_fdc_periph.v         # Single AXI4-Lite slave
    └── axi_fdc_periph_dual.v    # Dual AXI4-Lite (4-drive registers)
```

### Simulation
```
tb/
├── tb_digital_pll.v       # DPLL lock & tracking tests
├── tb_encoding.v          # MFM/FM/GCR encode/decode
├── tb_crc16.v             # CRC verification
└── tb_fluxripper_top.v    # System integration test

sim/
├── capsimg_test_vectors.v # Test patterns from CAPSImg
└── Makefile               # Icarus Verilog/Verilator
```

### AXI Testbenches (embedded in RTL)
```
rtl/axi/
├── axi_stream_flux.v      # Contains tb_axi_stream_flux (ifdef SIMULATION)
└── axi_fdc_periph.v       # Contains tb_axi_fdc_periph (ifdef SIMULATION)
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

### Total (Dual-FDC SCU35)
| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | ~10,350 | 36,000 | ~28.7% |
| FFs | ~5,800 | 36,000 | ~16.1% |
| BRAM (18Kb eq.) | ~54 | 106 | ~51% |
| DSP | 6 | 48 | ~12.5% |

*Headroom: 71% LUTs, 84% FFs, 49% BRAM, 87.5% DSP remaining for future enhancements.*

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
```

### Synthesis (Vivado)
1. Open Vivado 2024.1 or later (for SCU35 support)
2. Create new project for Spartan UltraScale+ (xcsu35p-2sbvb625e)
3. Add all RTL files from `rtl/` subdirectories including `rtl/axi/`
4. Add constraints from `constraints/scu35_pinout.xdc`
5. Configure MicroBlaze V soft core via Block Design
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
