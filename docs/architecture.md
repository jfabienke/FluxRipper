# FluxRipper System Architecture

*Updated: 2025-12-07 12:16*

## Overview

FluxRipper is an FPGA-based System-on-Chip implementing an enhanced Intel 82077AA Floppy Disk Controller with diagnostic capabilities. The design targets the **AMD Spartan UltraScale+ SCU35 Evaluation Kit** with a MicroBlaze V (RISC-V) soft core. The HDL design is derived from the CAPSImg library's FDC emulator.

**Dual Interface Architecture**: FluxRipper supports two independent Shugart interfaces for 4 concurrent drives, enabling parallel flux capture and disk-to-disk copy operations.

## FluxRipper Universal Card Architecture

The Universal card design provides multiple host interfaces on a single PCB:

### Host Interfaces
| Interface | Edge/Connector | Protocol | Use Case |
|-----------|----------------|----------|----------|
| **ISA** | Edge connector | ISA bus (3F0-3F7, DMA, IRQ) | Retro PC restoration |
| **USB 2.0 HS** | USB-C receptacle | ULPI PHY (480 Mbps) | Cross-platform tool (primary) |

**Note:** USB 2.0 HS is the sole high-speed host interface.

### Universal Card Peripherals
| Component | Interface | Purpose |
|-----------|-----------|---------|
| **SPI OLED** | SSD1306 128×64 | Status display, menu UI |
| **Rotary Encoder** | EC11 quadrature | Menu navigation + select |
| **MicroSD Slot** | SPI mode | Standalone disk image storage |
| **RTC** | PCF8563 I2C | FAT timestamps + ISA RTC (0x70-0x71) |
| **Power Monitors** | INA3221 I2C (×3) | Per-drive voltage/current sensing |

### ISA Plug and Play Support
FluxRipper implements full ISA PnP for auto-configuration:

| Logical Device | Default I/O | Default IRQ | Default DMA |
|----------------|-------------|-------------|-------------|
| FDC A (Primary) | 0x3F0-0x3F7 | IRQ 6 | DMA 2 |
| FDC B (Secondary) | 0x370-0x377 | IRQ 6 | DMA 1 |
| FluxRipper Extensions | 0x3E8-0x3EF | - | - |
| Real-Time Clock | 0x70-0x71 | IRQ 8 | - |

### ISA Real-Time Clock
The onboard RTC is exposed as an AT-compatible MC146818 RTC for legacy systems:
- **Ports:** 0x70 (address), 0x71 (data)
- **Use case:** Add RTC to XT clones without a built-in clock
- **Features:** BCD time/date, century register (0x32), battery backup

## System Block Diagram (SCU35 SoC)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FluxRipper SoC (XCSU35P)                            │
│                                                                             │
│  ┌──────────────────┐                      ┌──────────────────────────────┐ │
│  │   MicroBlaze V   │◄───── AXI4-Lite ────►│     AXI FDC Peripheral       │ │
│  │    (RISC-V)      │                      │  ┌────────────────────────┐  │ │
│  │   ~3.5K LUTs     │                      │  │   FDC Register Map     │  │ │
│  └────────┬─────────┘                      │  │  DOR│DSR│MSR│DIR│CCR   │  │ │
│           │                                │  └───────────┬────────────┘  │ │
│           │ AXI4 (Memory)                  │              │               │ │
│           ▼                                │  ┌───────────▼────────────┐  │ │
│  ┌──────────────────┐                      │  │     Command FSM        │  │ │
│  │   AXI DMA        │◄─── AXI-Stream ─────►│  │  Type 1│2│3│4 cmds     │  │ │
│  │   Controller     │                      │  └───────────┬────────────┘  │ │
│  └────────┬─────────┘                      └──────────────┼───────────────┘ │
│           │                                               │                 │
│           ▼                                ┌──────────────▼───────────────┐ │
│  ┌──────────────────┐                      │       AXI-Stream Flux        │ │
│  │   HyperRAM       │  8MB Track Buffer    │  ┌────────────────────────┐  │ │
│  │   Controller     │  (40+ tracks)        │  │    Flux Capture        │  │ │
│  └──────────────────┘                      │  │   512-entry FIFO       │  │ │
│                                            │  │   28-bit timestamps    │  │ │
│                                            │  └───────────┬────────────┘  │ │
│                                            └──────────────┼───────────────┘ │
│                                                           │                 │
│                                                           ▼                 │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        FDC Data Path                                  │  │
│  │                                                                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │  │
│  │  │  Step    │  │   DPLL   │  │ Encoding │  │  Signal  │               │  │
│  │  │Controller│  │ (6 sub)  │  │ MFM/FM/  │  │ Quality  │               │  │
│  │  │          │  │          │  │   GCR    │  │ Monitor  │               │  │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘               │  │
│  │       │             │             │             │                     │  │
│  │  ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐  ┌────▼────────┐            │  │
│  │  │  Motor   │  │    AM    │  │   CRC    │  │Write Precomp│            │  │
│  │  │Controller│  │ Detector │  │  CCITT   │  │             │            │  │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬──────┘            │  │
│  │       │             │             │               │                   │  │
│  └───────┼─────────────┼─────────────┼───────────────┼───────────────────┘  │
│          │             │             │               │                      │
│          ▼             ▼             ▼               ▼                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    Drive Interface (via Level Shifters)              │   │
│  │   STEP │ DIR │ MOTOR │ HEAD_SEL │ WRITE_GATE │ WRITE_DATA │ RD       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                          ┌─────────────┴─────────────┐
                          │  Level Shifter Board      │
                          │  (74AHCT125 / 74LVC245)   │
                          │  3.3V LVCMOS ↔ 5V TTL     │
                          └─────────────┬─────────────┘
                                        │
                          ┌─────────────▼─────────────┐
                          │      Floppy Drive         │
                          │  34-pin Shugart Interface │
                          └───────────────────────────┘
```

## Dual-FDC Block Diagram (4 Drives)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FluxRipper Dual-FDC SoC (XCSU35P)                        │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │   MicroBlaze V   │◄───── AXI4-Lite ─────┐                                │
│  │    (RISC-V)      │                      │                                │
│  └────────┬─────────┘                      ▼                                │
│           │ AXI4              ┌────────────────────────┐                    │
│           │                   │  AXI FDC Peripheral    │                    │
│           │                   │  (Dual Interface Regs) │                    │
│           │                   │  0x00-0x2C: Standard   │                    │
│           │                   │  0x30-0x58: Dual Ext   │                    │
│           │                   └───────────┬────────────┘                    │
│           │                               │                                 │
│  ┌────────┴─────────┐         ┌───────────┴────────────┐                    │
│  │   AXI DMA (2ch)  │         │    Dual FDC Core       │                    │
│  │   Controller     │         │                        │                    │
│  └────────┬─────────┘         │  ┌──────┐  ┌──────┐    │                    │
│           │                   │  │FDC A │  │FDC B │    │                    │
│           │ AXI-Stream (2x)   │  │Drv0/1│  │Drv2/3│    │                    │
│           │◄──────────────────│  └──┬───┘  └──┬───┘    │                    │
│           │                   │     │         │        │                    │
│           ▼                   └─────┼─────────┼────────┘                    │
│  ┌──────────────────┐               │         │                             │
│  │   HyperRAM       │               │         │                             │
│  │   Controller     │               │         │                             │
│  │   (8MB buffer)   │               │         │                             │
│  └──────────────────┘               │         │                             │
└─────────────────────────────────────┼─────────┼─────────────────────────────┘
                                      │         │                             
                        ┌─────────────┴───┐ ┌───┴─────────────┐               
                        │  Level Shifter  │ │  Level Shifter  │               
                        │  (Header 1)     │ │  (Header 2)     │              
                        └────────┬────────┘ └────────┬────────┘               
                                 │                   │                        
                        ┌────────┴────────┐ ┌────────┴────────┐               
                        │ 34-pin Shugart  │ │ 34-pin Shugart  │               
                        │ Drives 0 & 1    │ │ Drives 2 & 3    │               
                        └─────────────────┘ └─────────────────┘               
```

### Dual Interface Features

- **Parallel Flux Capture**: Both interfaces capture flux simultaneously via dual AXI-Stream channels
- **Concurrent Seeks**: Each FDC core operates independently - seek drive 0 while reading drive 2
- **Disk-to-Disk Copy**: Hardware-accelerated copy with optional CRC verification
- **Independent RPM Detection**: Per-drive RPM measurement (300/360 RPM auto-detect)
- **4 Drive Motors**: Independent motor control for all 4 drives

## Legacy Block Diagram (Standalone FDC)

```
                        ┌─────────────────────────────────────────────────────┐
                        │                   FluxRipper FDC                    │
                        │                                                     │
   ┌────────┐           │  ┌──────────────────────────────────────────────┐   │
   │  CPU   │◄─────────►│  │              FDC Register Interface          │   │
   │ (Host) │  ISA Bus  │  │    DOR │ DSR │ MSR │ DIR │ CCR │ FIFO        │   │
   └────────┘           │  └───────────────────┬──────────────────────────┘   │
                                               │                           
                           ┌───────────────────▼──────────────────────────┐
                           │              Command FSM                     │
                           │   Type 1 │ Type 2 │ Type 3 │ Type 4          │
                           └────┬─────────┬────────────┬──────────────────┘
                                │         │            │                    
         ┌──────────────────────┼─────────┼────────────┼───────────────────┐
         │                      ▼         ▼            ▼                   │
         │  ┌──────────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
         │  │    Step      │ │  Read   │ │  Write  │ │   AM    │           │
         │  │  Controller  │ │  Path   │ │  Path   │ │Detector │           │
         │  │              │ │         │ │         │ │         │           │
         │  │ Double-Step  │ │  Data   │ │ Precomp │ │ A1/C2   │           │
         │  └──────┬───────┘ │Separator│ │         │ │ Sync    │           │
         │         │         └────┬────┘ └────┬────┘ └────┬────┘           │
         │         │              │           │           │                │
         │  ┌──────▼───────┐ ┌────▼────┐ ┌────▼────┐ ┌────▼────┐           │
         │  │   Motor      │ │  DPLL   │ │  MFM    │ │  CRC    │           │
         │  │  Controller  │ │         │ │Encoder  │ │ CCITT   │           │
         │  └──────┬───────┘ └────┬────┘ └────┬────┘ └─────────┘           │
         │         │              │           │                            │
         └─────────┼──────────────┼───────────┼────────────────────────────┘
                   │              │           │                               
                   ▼              ▼           ▼                               
            ┌──────────────────────────────────────┐                          
            │         Drive Interface              │
            │  STEP │ DIR │ MOTOR │ WG │ WD │ RD   │
            └──────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Floppy Drive   │
                    │   (Physical)    │
                    └─────────────────┘
```

## Module Hierarchy

### Dual-FDC SoC Architecture (Primary)
```
fluxripper_dual_top (top-level for dual Shugart)
├── microblaze_v                    # RISC-V soft processor (Vivado IP)
├── axi_interconnect                # AXI4-Lite crossbar (Vivado IP)
├── axi_dma (2-channel)             # AXI DMA controller (Vivado IP)
├── hyperram_controller             # HyperRAM interface (AMD IP)
├── axi_fdc_periph_dual             # Extended AXI4-Lite register wrapper
│   ├── Standard registers (0x00-0x2C)
│   ├── Dual control (0x30-0x58)
│   └── FDC B mirrors (0x60+)
├── axi_stream_flux_dual            # Dual AXI-Stream flux capture
│   ├── Stream A (256-entry FIFO)
│   ├── Stream B (256-entry FIFO)
│   └── Per-stream capture control
├── index_handler_dual              # 4-index RPM handler
│   ├── Per-drive revolution timing
│   └── RPM detection (300/360)
├── motor_controller                # Shared 4-drive motor control
├── fdc_core_instance (A)           # Interface A - Drives 0/1
│   ├── digital_pll
│   ├── am_detector
│   ├── step_controller
│   ├── command_fsm
│   ├── crc16_ccitt
│   └── encoding_mux
└── fdc_core_instance (B)           # Interface B - Drives 2/3
    ├── digital_pll
    ├── am_detector
    ├── step_controller
    ├── command_fsm
    ├── crc16_ccitt
    └── encoding_mux
```

### Single-Interface SoC Architecture
```
fluxripper_soc (top-level for SCU35)
├── microblaze_v                    # RISC-V soft processor (Vivado IP)
├── axi_interconnect                # AXI4-Lite crossbar (Vivado IP)
├── axi_dma                         # AXI DMA controller (Vivado IP)
├── hyperram_controller             # HyperRAM interface (AMD IP)
├── axi_fdc_periph                  # AXI4-Lite FDC register wrapper
│   ├── FDC register logic
│   ├── Flux capture control
│   └── Signal quality interface
├── axi_stream_flux                 # AXI-Stream flux capture
│   ├── 512-entry FIFO
│   ├── Timestamp generator (28-bit)
│   └── Edge detector (3-stage sync)
└── fluxripper_core                 # FDC core logic
    ├── fdc_registers
    │   └── fdc_fifo
    ├── command_fsm
    ├── fdc_status
    ├── digital_pll
    │   ├── edge_detector
    │   ├── phase_detector
    │   ├── loop_filter
    │   ├── nco
    │   ├── data_sampler
    │   └── lock_detector
    ├── am_detector
    │   └── sync_fsm
    ├── mfm_encoder
    ├── mfm_decoder
    ├── fm_codec
    ├── gcr_cbm
    ├── gcr_apple
    ├── encoding_mux
    ├── crc16_ccitt
    ├── step_controller
    │   └── track_width_analyzer
    ├── motor_controller
    ├── index_handler
    ├── write_precomp
    ├── flux_capture
    └── signal_quality_monitor
```

### Standalone FDC Architecture
```
fluxripper_top
├── fdc_registers
│   └── fdc_fifo
├── command_fsm
├── fdc_status
├── digital_pll
│   ├── edge_detector_filtered
│   ├── phase_detector_robust
│   ├── loop_filter_auto
│   ├── nco_rpm_compensated
│   ├── data_sampler
│   └── lock_detector
├── am_detector
│   └── sync_fsm
├── mfm_encoder_sync
├── mfm_decoder_sync
├── crc16_ccitt
├── crc16_ccitt_serial
├── step_controller
│   └── track_width_analyzer
├── motor_controller
├── write_precompensation
└── write_driver
```

## Data Flow

### Read Operation

1. CPU writes READ DATA command to Command Register
2. Command FSM initiates seek to target cylinder
3. Step Controller positions head
4. DPLL acquires lock on flux transitions
5. AM Detector finds sync marks (A1 A1 A1 FE)
6. ID field read and verified against target sector
7. Data field read through DPLL/MFM decoder
8. CRC calculated and verified
9. Data transferred to FIFO
10. Status bytes returned to CPU

### Write Operation

1. CPU writes WRITE DATA command
2. Step Controller positions head
3. Wait for ID field to locate sector
4. Gap write for write splice
5. Data written through MFM encoder with precompensation
6. CRC appended
7. Gap write to end of sector

## Clock Domains & CDC Strategy

### Clock Domain Summary

| Domain | Frequency | Usage | Modules |
|--------|-----------|-------|---------|
| `clk_sys` | 200 MHz | FDC data path, DPLL, flux capture | digital_pll, am_detector, encoders, flux_capture |
| `aclk` | 100 MHz | AXI bus, DMA, MicroBlaze | axi_fdc_periph, axi_interconnect, microblaze_v |
| `clk_cpu` | Variable | Legacy CPU interface (standalone) | fdc_registers (standalone mode only) |

### Clock Domain Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          FluxRipper Clock Domains                           │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     clk_sys (200 MHz) Domain                        │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │    │
│  │  │  DPLL    │ │    AM    │ │ Encoders │ │   CRC    │ │  Flux    │   │    │
│  │  │ (6 sub)  │ │ Detector │ │ MFM/FM/  │ │  CCITT   │ │ Capture  │   │    │
│  │  │          │ │          │ │   GCR    │ │          │ │          │   │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘   │    │
│  └───────────────────────────────────────────────────────────┼─────────┘    │
│                                                              │              │
│                              ┌────────────────────────────┐  │              │
│                              │   CDC: Async FIFO          │◄─┘              │
│                              │   (200 MHz → 100 MHz)      │                 │
│                              │   Depth: 512 entries       │                 │
│                              └─────────────┬──────────────┘                 │
│                                            │                                │
│  ┌─────────────────────────────────────────┼────────────────────────────┐   │
│  │                     aclk (100 MHz) Domain                            │   │
│  │  ┌───────────────┐  ┌────────┴──────┐  ┌──────────────────────────┐  │   │
│  │  │  MicroBlaze V │  │ AXI-Stream    │  │    AXI FDC Peripheral    │  │   │
│  │  │   (RISC-V)    │  │ Flux Output   │  │  (Register Interface)    │  │   │
│  │  └───────┬───────┘  └───────┬───────┘  └────────────┬─────────────┘  │   │
│  │          │                  │                       │                │   │
│  │          │    ┌─────────────┴───────────────────────┘                │   │
│  │          │    │                                                      │   │
│  │  ┌───────▼────▼───────┐  ┌──────────────┐  ┌──────────────┐          │   │
│  │  │  AXI Interconnect  │  │   AXI DMA    │  │   HyperRAM   │          │   │
│  │  │   (Crossbar)       │◄─┤  Controller  ├──┤  Controller  │          │   │
│  │  └────────────────────┘  └──────────────┘  └──────────────┘          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### CDC Crossing Points

| Crossing | From | To | Mechanism | Notes |
|----------|------|-----|-----------|-------|
| Flux data | clk_sys (200) | aclk (100) | Async FIFO | 512-entry, in axi_stream_flux |
| Control signals | aclk (100) | clk_sys (200) | 2-stage sync | capture_enable, soft_reset |
| Status signals | clk_sys (200) | aclk (100) | 2-stage sync | overflow, capturing |
| Counters | clk_sys (200) | aclk (100) | Gray-code sync | capture_count, index_count |

### AXI-Stream Flux Clock Clarification

The `axi_stream_flux` module operates with a **split clock architecture**:

1. **Front-end (clk_sys @ 200 MHz)**:
   - Flux edge detection (3-stage synchronizer)
   - Timestamp generation (28-bit counter with /56 divider)
   - FIFO write logic

2. **Back-end (aclk @ 100 MHz)**:
   - AXI-Stream master interface (m_axis_*)
   - FIFO read logic
   - DMA handshaking

The internal 512-entry FIFO serves as the CDC boundary, using standard async FIFO techniques (Gray-code pointers, dual-clock synchronizers).

### Standalone Mode (Legacy CPU Interface)

In standalone mode (`fluxripper_top`), the FDC operates with:
- `clk_sys` (200 MHz): All data path logic
- `clk_cpu` (variable, typically 8-25 MHz): CPU register interface

CDC between domains uses:
- 2-stage synchronizers for control signals
- Handshake protocol for FIFO access
- Status registers are sampled atomically on clk_cpu edge

## AXI Infrastructure

### AXI4-Lite FDC Peripheral (`axi_fdc_periph.v`)

Memory-mapped peripheral exposing FDC registers and extended diagnostics to the MicroBlaze V soft core.

**Features:**
- Full AXI4-Lite slave interface (32-bit data, 6-bit address)
- 82077AA-compatible register access
- Extended flux capture control registers
- Real-time signal quality monitoring
- Hardware version identification

**Interface Signals:**
```
AXI4-Lite Slave     FDC Core            Flux Capture
─────────────────   ──────────────      ─────────────────
s_axi_awaddr   ───► data_rate      ───► flux_capture_enable
s_axi_awvalid       motor_on            flux_soft_reset
s_axi_wdata         drive_sel           flux_capture_mode
s_axi_rdata    ◄─── busy           ◄─── flux_capture_count
                    rqm                 flux_index_count
                    dio                 flux_overflow
```

### AXI-Stream Flux Capture (`axi_stream_flux.v`)

High-speed streaming interface for flux transition data to DMA controller.

**Features:**
- AXI-Stream master interface (32-bit data)
- 512-entry internal FIFO for burst buffering
- 28-bit timestamps with ~280ns resolution (200MHz/56)
- Index pulse marking for track boundaries
- Overflow detection and reporting

**Data Format (32-bit per transition):**
```
┌────┬────┬────┬────────┬───────────────────────────────┐
│ 31 │ 30 │ 29 │ 28:27  │             26:0              │
├────┼────┼────┼────────┼───────────────────────────────┤
│ IX │ OV │ SC │ DRV_ID │          Timestamp            │
└────┴────┴────┴────────┴───────────────────────────────┘
IX     = Index pulse marker (1 = index pulse detected since last word)
OV     = Overflow warning (FIFO was full)
SC     = Sector pulse marker (1 = hard-sector pulse detected since last word)
DRV_ID = Drive ID (0-3 in dual mode, identifies source drive)
Timestamp = 27-bit timestamp (~5ns resolution at 200MHz, ~670ms range)
```

**Hard-Sector Support (Bit 29):**

The SECTOR flag (bit 29) supports hard-sectored disks such as NorthStar, Vector Graphics, and S-100 systems. These drives have physical holes in the disk media that generate sector pulses via the /SECTOR signal (50-pin Shugart pin 28).

- **Semantics**: "pulse detected since last word" — if a sector hole passed the sensor between the previous flux word and this one, bit 29 = 1
- **Soft-sectored disks**: Always 0 (tie /SECTOR input low or leave unconnected)
- **Hard-sectored disks**: Software counts sector marks to identify sector boundaries

**Capture Modes:**
| Mode | Value | Description |
|------|-------|-------------|
| Continuous | 00 | Capture until manually stopped |
| One Track | 01 | Stop after 2 index pulses (full track) |
| One Revolution | 10 | Stop after 1 index pulse |

**Interface Signals:**
```
Flux Input          AXI-Stream Master   Control/Status
──────────────      ─────────────────   ─────────────────
flux_raw       ───► m_axis_tdata   ───► capture_enable
index_pulse         m_axis_tvalid       capture_mode
                    m_axis_tready  ◄─── capture_count
                    m_axis_tlast        overflow
                    m_axis_tkeep        fifo_level
```

## Memory Map (82077AA Compatible)

| Address | Register | R/W | Description |
|---------|----------|-----|-------------|
| 0x3F0 | SRA | R | Status Register A |
| 0x3F1 | SRB | R | Status Register B |
| 0x3F2 | DOR | R/W | Digital Output Register |
| 0x3F3 | TDR | R/W | Tape Drive Register |
| 0x3F4 | MSR | R | Main Status Register |
| 0x3F4 | DSR | W | Data Rate Select |
| 0x3F5 | DATA | R/W | Data Register (FIFO) |
| 0x3F7 | DIR | R | Digital Input Register |
| 0x3F7 | CCR | W | Configuration Control |

## Dual-Interface Extended Registers

The dual-interface design adds extended registers at offsets 0x30-0x58:

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x30 | DUAL_CTRL | R/W | Dual interface enable, mode, sync |
| 0x34 | FDC_A_STATUS | R | FDC A extended status |
| 0x38 | FDC_B_STATUS | R | FDC B extended status |
| 0x3C | TRACK_A | R | Current track position (drives 0/1) |
| 0x40 | TRACK_B | R | Current track position (drives 2/3) |
| 0x44 | FLUX_CTRL_A | R/W | Interface A flux capture control |
| 0x48 | FLUX_CTRL_B | R/W | Interface B flux capture control |
| 0x4C | FLUX_STATUS_A | R | Interface A flux status |
| 0x50 | FLUX_STATUS_B | R | Interface B flux status |
| 0x54 | COPY_CTRL | R/W | Disk-to-disk copy control |
| 0x58 | COPY_STATUS | R | Copy operation status |

### DUAL_CTRL Register (0x30)

```
Bits 31:8  Reserved
Bit  7     ENABLE      1=Dual mode enabled
Bit  6     SYNC_INDEX  1=Sync index pulses between interfaces
Bits 5:4   Reserved
Bits 3:2   IF_B_DRV    Active drive on interface B (0-1 → physical 2-3)
Bits 1:0   IF_A_DRV    Active drive on interface A (0-1 → physical 0-1)
```

### AXI-Stream Dual Output

The dual design provides two independent AXI-Stream master ports:
- `m_axis_a_*` - Flux data from Interface A (drives 0/1)
- `m_axis_b_*` - Flux data from Interface B (drives 2/3)

Each stream uses the 32-bit format with DRV_ID identifying the source drive.

## Supported Commands

### Type 1 (Seek)
- RECALIBRATE (0x07)
- SEEK (0x0F)

### Type 2 (Read/Write Sector)
- READ DATA (0x06, 0x46, 0xC6, 0xE6)
- WRITE DATA (0x05, 0x45, 0xC5)
- READ DELETED DATA (0x0C)
- WRITE DELETED DATA (0x09)

### Type 3 (Track Operations)
- READ ID (0x0A, 0x4A)
- READ TRACK (0x02)
- FORMAT TRACK (0x0D, 0x4D)

### Type 4 (Control)
- SENSE INTERRUPT (0x08)
- SENSE DRIVE (0x04)
- SPECIFY (0x03)
- CONFIGURE (0x13)
- VERSION (0x10)

## Key Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Data Rates | 250K, 300K, 500K, 1M | Configurable via CCR |
| Drive Speeds | 300 RPM, 360 RPM | Auto-detected |
| Track Support | 40, 80 | Double-step for 40T in 80T drive |
| Sector Sizes | 128, 256, 512, 1024, 2048, 4096 | Via N parameter |
| FIFO Depth | 16 bytes | Standard 82077AA |
| Step Rates | 2ms, 3ms, 6ms, 12ms | Via SPECIFY |

## 82077AA Compatibility

FluxRipper implements the Intel 82077AA-1 floppy disk controller interface with extensions for diagnostic capture. See [register_map.md](register_map.md#82077aa-compatibility-notes) for detailed compatibility notes including:

- Implemented vs. unimplemented commands
- MSR/RQM/DIO polling semantics
- TDR (Tape Drive Register) stub behavior
- CONFIGURE command defaults
- Drive select limitations (2 drives supported)

**Key differences from 82077AA:**
- SCAN commands (0x11, 0x19, 0x1D) return Invalid Command
- PERPENDICULAR MODE (0x12) not implemented
- Extended registers at 0x18-0x2C for flux capture and diagnostics
- VERSION command returns 0x90 (82077AA compatible)

## JTAG Debug Subsystem Architecture

The FluxRipper includes a complete RISC-V Debug Module 0.13-compliant JTAG debug subsystem for hardware bring-up and diagnostics.

### Debug Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FluxRipper Debug Subsystem                          │
│                                                                             │
│  ┌──────────────────┐                      ┌──────────────────────────────┐ │
│  │  JTAG Connector  │                      │       System Bus Fabric      │ │
│  │  (TCK,TMS,TDI,   │                      │                              │ │
│  │   TDO,TRST)      │                      │  ROM    RAM    Peripherals   │ │
│  └────────┬─────────┘                      └──────────────┬───────────────┘ │
│           │                                               ▲                 │
│           ▼                                               │                 │
│  ┌──────────────────┐    IR/DR     ┌──────────────────┐   │                 │
│  │  TAP Controller  │──────────────│  Debug Transport │   │                 │
│  │  (IEEE 1149.1)   │              │  Module (DTM)    │   │                 │
│  │                  │              │                  │   │                 │
│  │  IDCODE: 0xFB010001             │  DTMCS, DMI      │   │                 │
│  │  IR: 5-bit       │              │  Registers       │   │                 │
│  └──────────────────┘              └────────┬─────────┘   │                 │
│                                             │             │                 │
│                                    ┌────────▼─────────┐   │                 │
│                                    │  Debug Module    │───┘                 │
│                                    │  (RISC-V DM 0.13)│                     │
│                                    │                  │                     │
│                                    │  sbcs, sbaddr,   │                     │
│                                    │  sbdata          │                     │
│                                    └──────────────────┘                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Debug Module Hierarchy

```
fluxripper_top
├── jtag_tap_controller          # IEEE 1149.1 TAP
│   ├── 16-state FSM             # Test-Logic-Reset → Run-Test-Idle → ...
│   ├── IDCODE (0xFB010001)      # FluxRipper v1 identifier
│   ├── BYPASS                   # Single-bit bypass register
│   └── 5-bit IR                 # Instruction register
├── jtag_dtm                     # Debug Transport Module
│   ├── DTMCS (IR=0x10)          # Control/Status register
│   ├── DMI Access (IR=0x11)     # Debug Module Interface
│   └── 41-bit shift register    # addr[7]+data[32]+op[2]
├── debug_module                 # RISC-V Debug Module 0.13
│   ├── DMI register interface   # 128 registers
│   ├── System bus master        # Memory access
│   └── Abstract commands        # (placeholder)
├── system_bus                   # Address decoder + arbiter
│   ├── Slave 0: ROM             # 0x0000_0000 - 0x0FFF_FFFF
│   ├── Slave 1: RAM             # 0x1000_0000 - 0x1FFF_FFFF
│   ├── Slave 2: SYSCTRL         # 0x4000_0000
│   ├── Slave 3: Disk Controller # 0x4001_0000
│   ├── Slave 4: USB Controller  # 0x4002_0000
│   └── Slave 5: Signal Tap      # 0x4003_0000
└── clock_reset_mgr              # Clock generation + reset sync
    ├── MMCME4_BASE (synthesis)  # 25→100/48/50 MHz
    ├── Behavioral (simulation)  # Toggle-based clocks
    ├── Reset synchronizers      # Per-domain
    └── Watchdog timer           # System health
```

### DMI Protocol

The Debug Module Interface (DMI) uses a 41-bit shift register:

```
┌───────────────┬───────────────────────────────────┬──────────┐
│  addr [40:34] │           data [33:2]             │ op [1:0] │
│    7 bits     │             32 bits               │  2 bits  │
└───────────────┴───────────────────────────────────┴──────────┘

op values:
  00 = NOP
  01 = Read
  10 = Write
  11 = Reserved

Response status (in op field on read-back):
  00 = Success
  01 = Reserved
  10 = Failed
  11 = Busy
```

### Memory Map (via Debug Module)

| Address Range | Size | Description |
|---------------|------|-------------|
| 0x0000_0000 - 0x0FFF_FFFF | 256 MB | Boot ROM (64 KB implemented) |
| 0x1000_0000 - 0x1FFF_FFFF | 256 MB | Main RAM (64 KB implemented) |
| 0x4000_0000 - 0x4000_00FF | 256 B | System Control |
| 0x4001_0000 - 0x4001_00FF | 256 B | Disk Controller |
| 0x4002_0000 - 0x4002_00FF | 256 B | USB Controller |
| 0x4003_0000 - 0x4003_00FF | 256 B | Signal Tap |

### Simulation Validation Status

All debug subsystem layers have been validated in simulation:

| Layer | Module | Tests | Status |
|-------|--------|-------|--------|
| 0 | TAP Controller | 9 | ✅ Pass |
| 1 | DTM | 5 | ✅ Pass |
| 2 | Debug Module | 6 | ✅ Pass |
| 3 | System Bus | 7 | ✅ Pass |
| 4 | Clock/Reset | 5 | ✅ Pass |
| 5 | Peripherals | 8 | ✅ Pass |
| 6 | Full System | 12 | ✅ Pass |

See [SIMULATION_LAYERS.md](SIMULATION_LAYERS.md) for detailed test descriptions.

---

## QIC-117 Tape Controller Architecture

FluxRipper includes support for QIC-117 floppy-interface tape drives, enabling flux capture from QIC-40, QIC-80, QIC-3010, and QIC-3020 tape cartridges.

### QIC-117 Protocol Overview

QIC (Quarter-Inch Cartridge) tape drives "abuse" the standard floppy interface by reinterpreting signals:

| Signal | Floppy Use | QIC-117 Tape Use |
|--------|------------|------------------|
| STEP | Head step pulses | Command bits (count = command) |
| DIR | Head direction | Unused |
| TRK0 | Track 0 sensor | Status bit stream (time-encoded) |
| INDEX | Index hole | Segment boundary marker |
| RDATA | Disk read data | Tape MFM data stream |
| WDATA | Disk write data | Tape MFM write stream |

### QIC-117 Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FluxRipper QIC-117 Tape Subsystem                       │
│                                                                             │
│  ┌──────────────────┐                      ┌──────────────────────────────┐ │
│  │   Existing FDC   │                      │     QIC-117 Controller       │ │
│  │   Command FSM    │                      │                              │ │
│  │                  │    tape_mode_en      │  ┌────────────────────────┐  │ │
│  │  STEP generator ─┼──────────────────────┼─►│  STEP Pulse Counter    │  │ │
│  │                  │                      │  │  (count 1-48 pulses)   │  │ │
│  │  TRK0 input    ◄─┼──────────────────────┼──│                        │  │ │
│  │                  │                      │  └───────────┬────────────┘  │ │
│  │  INDEX input   ◄─┼──────────────────────┼──────────────┤               │ │
│  └──────────────────┘                      │  ┌───────────▼────────────┐  │ │
│                                            │  │   Command Decoder      │  │ │
│                                            │  │   48 QIC-117 commands  │  │ │
│  ┌──────────────────┐                      │  └───────────┬────────────┘  │ │
│  │   TDR Register   │──── tape_select ────►│              │               │ │
│  │   (0x3F3)        │                      │  ┌───────────▼────────────┐  │ │
│  │   [2:0] = drive  │                      │  │   Tape State Machine   │  │ │
│  │   [7] = enable   │                      │  │   - Position tracking  │  │ │
│  └──────────────────┘                      │  │   - Segment counter    │  │ │
│                                            │  │   - Direction state    │  │ │
│                                            │  └───────────┬────────────┘  │ │
│  ┌──────────────────┐                      │              │               │ │
│  │  Status Encoder  │◄─────────────────────┼──────────────┘               │ │
│  │  TRK0 bit-bang   │                      │                              │ │
│  │  INDEX pulses    │                      │  ┌────────────────────────┐  │ │
│  └──────────────────┘                      │  │   Data Streamer        │  │ │
│                                            │  │   - Block boundary     │  │ │
│  ┌──────────────────┐                      │  │   - Segment tracking   │  │ │
│  │  Existing DPLL   │◄─────────────────────┼──│   - Continuous MFM     │  │ │
│  │  MFM decoder     │                      │  └────────────────────────┘  │ │
│  └──────────────────┘                      └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### QIC-117 Module Hierarchy

```
fdc_core_instance
├── ... (existing FDC modules)
└── qic117_controller              # Main QIC-117 controller
    ├── qic117_step_counter        # STEP pulse counting with timeout
    │   ├── 3-stage synchronizer   # Async STEP input sync
    │   ├── Debounce filter        # 10µs debounce
    │   └── 100ms timeout counter  # Command boundary detection
    ├── qic117_cmd_decoder         # Command code decoding
    │   ├── Command type classify  # Reset/Seek/Skip/Motion/Status/Config
    │   └── Individual cmd flags   # 48 command outputs
    ├── qic117_status_encoder      # TRK0 status bit encoding
    │   ├── 500µs/1500µs timing    # Bit 0/1 encoding
    │   └── 1ms inter-bit gap      # Gap timing
    ├── qic117_tape_fsm            # Position tracking FSM
    │   ├── Segment counter        # 0-4095 segments
    │   ├── Track counter          # 0-27 tracks (QIC-80)
    │   ├── Motion state           # Seek/Skip/Stream states
    │   └── Serpentine logic       # Bi-directional track handling
    └── qic117_data_streamer       # Block boundary detector
        ├── Sync pattern detect    # 0x4489 MFM sync
        ├── Block assembly         # 512-byte data blocks
        ├── Segment tracking       # 32 blocks per segment
        └── File mark detection    # 0x1F header byte
```

### QIC-117 Data Flow

**Command Flow:**
1. Host sends N STEP pulses (1-48)
2. `qic117_step_counter` counts and debounces pulses
3. After 100ms timeout, pulse count becomes command code
4. `qic117_cmd_decoder` decodes to specific command flags
5. `qic117_tape_fsm` executes command (seek, skip, stream)
6. Status reported via `qic117_status_encoder` on TRK0

**Data Capture Flow:**
1. Tape drive moves in stream mode
2. MFM data arrives on RDATA
3. Existing DPLL recovers clock/data
4. `qic117_data_streamer` detects block boundaries
5. Data bytes output with position tracking
6. INDEX asserted at segment boundaries (32 blocks)

### QIC Tape Data Format

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           QIC Block Structure                                │
│                                                                             │
│  ┌──────────┬───────────┬────────┬───────────────────────┬──────────┐       │
│  │ Preamble │ Sync Mark │ Header │        Data           │   ECC    │       │
│  │ 10 bytes │  2 bytes  │ 1 byte │      512 bytes        │ 3 bytes  │       │
│  │  (0x00)  │(0xA1,0xA1)│ (type) │                       │          │       │
│  └──────────┴───────────┴────────┴───────────────────────┴──────────┘       │
│                                                                             │
│  Segment = 32 blocks = 16 KB                                                │
│  Track contains multiple segments                                           │
│  Serpentine: Track 0→, Track 1←, Track 2→, ...                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### TRK0 Status Bit Timing

```
         ┌─────────────────────────────────────────────────────────────────┐
  TRK0   │                                                                 │
  (idle) ─┘                                                                 │
         │     ┌─────────────────┐        ┌───────┐        ┌───────┐       │
  Bit=1  │     │    1500 µs      │        │ 1 ms  │        │       │       │
         │     │                 │        │  gap  │        │       │       │
         └─────┘                 └────────┘       └────────┘       └───... │
         │     ┌───────┐        ┌───────┐        ┌───────┐                 │
  Bit=0  │     │500 µs │        │ 1 ms  │        │       │                 │
         │     │       │        │  gap  │        │       │                 │
         └─────┘       └────────┘       └────────┘       └───────────...   │
         │                                                                 │
         └─────────────────────────────────────────────────────────────────┘
```

### Supported QIC Standards

| Standard | Tracks | Capacity | Data Rate | BPI | Max Segments |
|----------|--------|----------|-----------|-----|--------------|
| QIC-40 | 20 | 40 MB | 250-500 Kbps | 10,000 | ~2,500 |
| QIC-80 | 28 | 80-170 MB | 500 Kbps | 12,500 | ~5,000 |
| QIC-3010 | 40-50 | 340 MB | 500 Kbps | 22,125 | ~10,000 |
| QIC-3020 | 40-50 | 680 MB | 1 Mbps | 22,125 | ~20,000 |

### Resource Utilization (QIC-117 Subsystem)

| Module | LUTs | FFs | BRAM |
|--------|------|-----|------|
| qic117_controller | ~100 | ~50 | 0 |
| qic117_cmd_decoder | ~200 | ~100 | 0 |
| qic117_step_counter | ~150 | ~100 | 0 |
| qic117_status_encoder | ~150 | ~100 | 0 |
| qic117_tape_fsm | ~300 | ~200 | 0 |
| qic117_data_streamer | ~200 | ~150 | 0 |
| **Total** | **~1,100** | **~700** | **0** |

This represents approximately 3% of XCSU35P resources.

---

## CAPSImg Source Mapping

| FluxRipper Module | CAPSImg Source |
|-------------------|----------------|
| command_fsm.v | CapsFDCEmulator.cpp:505 |
| digital_pll.v | CapsFDCEmulator.cpp:2134 |
| am_detector.v | CapsFDCEmulator.cpp:2160 |
| mfm_encoder.v | DiskEncoding.cpp:291 |
| mfm_decoder.v | DiskEncoding.cpp:341 |
| crc16_ccitt.v | CRC.cpp:37 |
| step_controller.v | CapsFDCEmulator.cpp:409 |
