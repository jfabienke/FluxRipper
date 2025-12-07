# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FluxRipper is an FPGA-based System-on-Chip implementing:
- **Intel 82077AA FDC clone** - Full floppy disk controller with diagnostics
- **WD1003-compatible HDD controller** - ST-506/ESDI hard disk support
- **Statistical flux recovery** - "Bit Healer" for degraded media

Target platform: AMD Spartan UltraScale+ SCU35 Evaluation Kit (XCSU35P)

Key features:
- Dual Shugart interface (4 FDD drives) + ST-506/ESDI HDD support
- USB 2.0 High-Speed via ULPI PHY (480 Mbps) - primary host interface
- ISA bus interface for vintage PC integration
- Multi-format: MFM, FM, GCR, M2FM, RLL(2,7), ESDI
- KryoFlux/Greaseweazle/HxC protocol compatibility
- JTAG debug subsystem (RISC-V DM 0.13 compliant)

## Build and Simulation Commands

### Simulation (Icarus Verilog)
```bash
cd sim
make all              # Run all core testbenches
make sim_dpll         # Digital PLL only
make sim_encoding     # Encoding modules (MFM/FM/GCR/RLL)
make sim_usb          # USB 2.0 stack
make sim_hdd          # HDD controller
make lint             # Verilator lint check

# Layer-by-layer system validation
cd sim/layer1 && make  # JTAG DTM
cd sim/layer2 && make  # Debug Module
cd sim/layer3 && make  # System Bus
cd sim/layer4 && make  # Clock/Reset
cd sim/layer5 && make  # Peripherals
cd sim/layer6 && make  # Full system (12 tests)
```

### Synthesis (Vivado)
```bash
cd soc
vivado -mode batch -source scripts/synth_fluxripper.tcl  # Build bitstream
vivado -mode batch -source scripts/program_fpga.tcl      # Program FPGA
```
- Requires Vivado 2024.1+ (for SCU35 support)
- Target: xcsu35p-2sbvb625e
- Define `XILINX_FPGA` to enable MMCM primitives

### Firmware Build
```bash
cd soc/firmware
make                  # Build firmware ELF
make clean
```

## Architecture

### Clock Domains
| Domain | Frequency | Usage |
|--------|-----------|-------|
| `clk_sys` | 100 MHz | System bus, debug, USB |
| `clk_fdc` | 200 MHz | FDC data path, DPLL |
| `clk_hdd` | 300 MHz | HDD data separator |
| `clk_usb` | 60 MHz | ULPI PHY interface |

### RTL Module Hierarchy
```
rtl/
├── top/               # fluxripper_top.v (main), fluxripper_hdd_top.v
├── fdc_core/          # 82077AA FDC: command_fsm.v, fdc_registers.v
├── hdd_controller/    # WD1003: wd_command_fsm.v, wd_registers.v
├── encoding/          # FDD: MFM/FM/GCR, HDD: RLL(2,7)/ESDI
├── drive_interface/   # st506_interface.v, esdi_phy.v, esdi_cmd.v
├── diagnostics/       # hdd_discovery_fsm.v, instrumentation_regs.v
├── detection/         # interface_detector.v (FDD vs HDD auto-detect)
├── recovery/          # flux_histogram.v, multipass_capture.v
├── dsp/               # fir_flux_filter.v, prml_decoder.v
├── usb/               # USB 2.0 HS: usb_top_v2.v, ulpi_wrapper_v2.v
├── host/              # ISA: isa_bus_bridge.v, isa_pnp_controller.v
├── debug/             # JTAG: jtag_tap_controller.v, debug_module.v
├── clocking/          # clock_reset_mgr.v (MMCM)
├── bus/               # system_bus.v (address decode)
└── axi/               # axi_fdc_periph.v, axi_wd_periph.v
```

### Key Design Patterns
- **Dual-FDC + HDD architecture**: Independent controllers share bus fabric
- **USB personalities**: 4 runtime-selectable USB device modes (GW, HxC, KF, Native)
- **JTAG debug**: Full system bus access via Debug Module Interface (DMI)
- **Layered simulation**: 6-layer validation from TAP to full system

### Memory Map (via JTAG/System Bus)
| Address | Peripheral |
|---------|------------|
| 0x0000_0000 | Boot ROM (64KB) |
| 0x1000_0000 | Main RAM (64KB) |
| 0x4000_0000 | System Control |
| 0x4001_0000 | Disk Controller |
| 0x4002_0000 | USB Controller |
| 0x4003_0000 | Signal Tap |

## Important Documentation

- `docs/README.md` - Project overview, status, resource budget
- `docs/architecture.md` - Block diagrams, JTAG debug subsystem
- `docs/USB_HS_DESIGN.md` - USB 2.0 implementation details
- `docs/SIMULATION_LAYERS.md` - Layered test methodology
- `docs/BRINGUP_GUIDE.md` - Hardware bring-up procedures
- `docs/register_map.md` - FDC/HDD register interfaces
- `soc/firmware/` - C firmware for MicroBlaze V
