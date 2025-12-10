# FluxRipper

**The Ultimate FPGA-Based Disk Controller for Vintage Computing!**

FluxRipper is a powerful, open-source FPGA System-on-Chip that brings modern recovery capabilities to vintage floppy and hard disk drives. Whether you're rescuing irreplaceable data from aging media or building the ultimate retro computing setup, FluxRipper has you covered!

## What Makes FluxRipper Special?

- **Universal Floppy Support** - Full Intel 82077AA FDC clone supporting MFM, FM, GCR (Apple/Commodore), and M2FM formats
- **Hard Disk Controller** - WD1003/WD1006/WD1007-compatible controller for ST-506 MFM, RLL(2,7), and ESDI drives
- **Statistical Flux Recovery** - Our "Bit Healer" technology uses multi-pass capture and histogram analysis to recover data from degraded media that other tools give up on!
- **SpinRite-Style Diagnostics** - Built-in interleave benchmark, surface scan, and signal quality analysis
- **Dual Interface** - USB 2.0 High-Speed (480 Mbps) for modern systems AND ISA bus for authentic vintage PC integration
- **Protocol Compatible** - Works with KryoFlux, Greaseweazle, and HxC software!

## Hardware Platform

**Target:** AMD Spartan UltraScale+ SCU35 Evaluation Kit (XCSU35P)

| Feature | Specification |
|---------|---------------|
| Floppy Drives | 4x Shugart interface (34-pin) |
| Hard Drives | 2x ST-506/ESDI (34+20 pin) |
| USB | 2.0 High-Speed via ULPI PHY |
| ISA Bus | 8-bit XT and 16-bit AT compatible |
| Debug | JTAG with RISC-V Debug Module |

## Project Statistics

| Component | Size |
|-----------|------|
| RTL Modules | 127 Verilog files (~49,800 lines) |
| Testbenches | 17 test modules (~9,200 lines) |
| BIOS Code | 28 files (~14,200 lines of x86 assembly) |
| SoC Firmware | 53 files (~22,800 lines of C) |

### Simulation Status: ✅ ALL LAYERS VALIDATED

| Layer | Component | Tests | Status |
|-------|-----------|-------|--------|
| 0 | JTAG TAP Controller | 9 | ✅ Pass |
| 1 | Debug Transport Module | 5 | ✅ Pass |
| 2 | Debug Module + Memory | 6 | ✅ Pass |
| 3 | System Bus Fabric | 7 | ✅ Pass |
| 4 | Clock/Reset Manager | 5 | ✅ Pass |
| 5 | Peripheral Subsystems | 8 | ✅ Pass |
| 6 | Full System Integration | 12 | ✅ Pass |

## Quick Start

### Simulation
```bash
cd sim
make all              # Run all core testbenches
make sim_dpll         # Digital PLL simulation
make sim_encoding     # MFM/FM/GCR encoding tests
make sim_hdd          # Hard disk controller tests
make lint             # Verilator lint check
```

### Synthesis (Vivado 2024.1+)
```bash
cd soc
vivado -mode batch -source scripts/synth_fluxripper.tcl
vivado -mode batch -source scripts/program_fpga.tcl
```

### BIOS Build (NASM)
```bash
cd bios/hdd
make                  # Build 8KB and 16KB HDD Option ROMs
cd ../fdd
make                  # Build FDD Option ROM
```

## Architecture Highlights

### Clock Domains
| Domain | Frequency | Purpose |
|--------|-----------|---------|
| `clk_sys` | 100 MHz | System bus, debug, USB |
| `clk_fdc` | 200 MHz | FDC data path, DPLL |
| `clk_hdd` | 300 MHz | HDD data separator |
| `clk_usb` | 60 MHz | ULPI PHY interface |

### RTL Organization
```
rtl/
├── top/               # Top-level modules
├── fdc_core/          # Intel 82077AA FDC clone
├── hdd_controller/    # WD1003-series HDD controller
├── encoding/          # MFM, FM, GCR, M2FM, RLL codecs
├── drive_interface/   # ST-506, ESDI PHY layers
├── diagnostics/       # Drive discovery, instrumentation
├── recovery/          # Flux histogram, multi-pass capture
├── dsp/               # FIR filters, PRML decoder
├── usb/               # USB 2.0 High-Speed stack
├── host/              # ISA bus bridge, Plug-and-Play
├── debug/             # JTAG TAP, Debug Module
└── clocking/          # Clock generation (MMCM)
```

## Key Features in Detail

### Floppy Disk Controller
- Full 82077AA register-compatible implementation
- Automatic format detection (MFM, FM, GCR, M2FM)
- Support for 8", 5.25", and 3.5" drives
- 250/300/500/1000 kbps data rates
- Enhanced diagnostics via F3 boot menu

### Hard Disk Controller
- WD1002 (8-bit XT), WD1003 (16-bit AT), WD1006 (RLL), WD1007 (ESDI) personalities
- Automatic drive parameter discovery
- **Track buffer with write-back caching** - Makes interleave irrelevant!
- **Interleave detection and preservation** - Critical for forensic disk imaging
- INT 13h BIOS with LBA extensions (16KB build)

### Signal Recovery
- **Flux histogram analysis** - Visualize signal quality
- **Multi-pass capture** - Statistical bit recovery from weak signals
- **Adaptive equalization** - DSP-based signal enhancement
- **PRML decoder** - Maximum likelihood detection for marginal media

### Diagnostics (F3 Menu)
1. Surface Scan - Full drive verification
2. Seek Test - Head positioning accuracy
3. Flux Histogram - Signal quality visualization
4. Error Log - Recent error history
5. Health Monitor - Drive status overview
6. Signal Quality - Real-time flux analysis
7. Controller Config - Enable/disable controllers
8. Drive Interleave - View/set interleave factor
9. **Interleave Benchmark** - SpinRite-style performance testing!

### Hardware Auto-Detection (DRIVE_PROFILE)

FluxRipper automatically identifies connected drives without manual configuration. Just plug in any drive and read the 32-bit DRIVE_PROFILE register:

| Detection | Method | Confidence |
|-----------|--------|------------|
| Form Factor (3.5"/5.25"/8") | RPM + HEAD_LOAD analysis | 95% |
| Density (DD/HD/ED) | Active data rate probing | 99% |
| Track Count (40/77/80) | Sector ID field comparison | 95% |
| Encoding (MFM/FM/GCR/M2FM) | Sync pattern matching | 95% |
| Hard-Sectored Media | /SECTOR pulse counting | 100% |
| RPM (300/360) | Index pulse timing | 99% |

```
DRIVE_PROFILE Register Layout (32-bit):
┌─────────┬──────────┬──┬──┬──┬──┬──────┬─────┬─────┬─────┐
│ Quality │ RPM/10   │PV│PL│HL│VZ│ Enc  │TrkD │Dens │ FF  │
│  [31:24]│ [23:16]  │15│14│11│10│[8:6] │[5:4]│[3:2]│[1:0]│
└─────────┴──────────┴──┴──┴──┴──┴──────┴─────┴─────┴─────┘
```

No more fumbling with diskdef files or manual configuration!

### Comprehensive Instrumentation

FluxRipper provides forensic-level diagnostic data that goes far beyond simple error reporting:

**Lifetime Error Counters** - Track CRC errors, missing address marks, overruns, seek errors, and PLL unlock events across all operations

**PLL/DPLL Diagnostics** - Real-time phase error analysis with 8-bin histogram, frequency offset in PPM, lock statistics, and quality scoring

**FIFO Statistics** - Buffer health monitoring with overflow detection, throughput metrics, and backpressure tracking

**Capture Timing** - Index period min/max/average for RPM variance detection, flux interval analysis

**Seek Histogram (HDD)** - Mechanical characterization with 8 distance buckets and per-bucket timing averages

| Metric | Good | Marginal | Failing |
|--------|------|----------|---------|
| Error Rate | <1 per 1000 | 1-10 per 1000 | >10 per 1000 |
| PLL Quality | >200 | 150-200 | <150 |
| Freq Offset | <±50 PPM | ±50-200 PPM | >±200 PPM |
| RPM Variance | <0.1% | 0.1-0.5% | >0.5% |

See [docs/instrumentation.md](docs/instrumentation.md) and [docs/drive_detection.md](docs/drive_detection.md) for complete details.

## Documentation

| Document | Description |
|----------|-------------|
| [docs/README.md](docs/README.md) | Project status and roadmap |
| [docs/architecture.md](docs/architecture.md) | System block diagrams |
| [docs/register_map.md](docs/register_map.md) | FDC/HDD register reference |
| [docs/drive_detection.md](docs/drive_detection.md) | DRIVE_PROFILE auto-detection system |
| [docs/instrumentation.md](docs/instrumentation.md) | Diagnostic subsystem architecture |
| [docs/controller_comparison.md](docs/controller_comparison.md) | FluxRipper vs KryoFlux vs GreaseWeazle |
| [docs/USB_HS_DESIGN.md](docs/USB_HS_DESIGN.md) | USB 2.0 implementation |
| [docs/SIMULATION_LAYERS.md](docs/SIMULATION_LAYERS.md) | Test methodology |
| [docs/BRINGUP_GUIDE.md](docs/BRINGUP_GUIDE.md) | Hardware bring-up |

## USB Device Modes

FluxRipper presents as different USB devices depending on configuration:

| Mode | Description | Compatible Software |
|------|-------------|---------------------|
| Native | FluxRipper native protocol | FluxRipper tools |
| Greaseweazle | GW protocol emulation | gw, Disk-Utilities |
| KryoFlux | KF protocol emulation | DTC, HxC |
| HxC | HxC protocol emulation | HxC software |

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

## How FluxRipper Compares

| Feature | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|---------|------------|----------|--------------|---------------|
| **Price** | $249 | ~$100-150 | ~$35-50 | ~$100 |
| **Open Source** | Yes (RTL+SW) | No | Yes (FW+SW) | Partial |
| **Real-time decode** | Yes (FPGA) | No | No | No |
| **FDC replacement** | ✅ 82077AA | ❌ | ❌ | ❌ |
| **HDD controller** | ✅ WD1003 | ❌ | ❌ | ❌ |
| **Auto-detect drives** | ✅ Hardware | ❌ Manual | ❌ Manual | ❌ Manual |
| **8" native support** | ✅ HEAD_LOAD+24V | Via adapter | Via adapter | Via adapter |
| **Standalone mode** | ✅ MicroSD+OLED | ❌ | ❌ | Partial |
| **Timing resolution** | 5 ns | ~41 ns | ~14 ns | 25 ns |
| **ISA bus interface** | ✅ | ❌ | ❌ | ❌ |

**FluxRipper wins at:** FDC/HDD replacement, hardware auto-detection, 8" drive support, timing resolution, standalone operation, ISA integration

**Best alternatives:** GreaseWeazle (budget), KryoFlux (IPF/copy protection ecosystem)

See [docs/controller_comparison.md](docs/controller_comparison.md) for the complete comparison matrix.

## Contributing

FluxRipper is open source! Contributions are welcome:
- Bug reports and feature requests via GitHub Issues
- Pull requests for code improvements
- Documentation improvements
- Testing on different drive types

## License

SPDX-License-Identifier: BSD-3-Clause

Copyright (c) 2025 FluxRipper Project

---

**Happy disk recovering!** Whether you're preserving computing history or just need to read that old floppy from 1987, FluxRipper is here to help!
