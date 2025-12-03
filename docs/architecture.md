# FluxRipper System Architecture

*Updated: 2025-12-03 21:10*

## Overview

FluxRipper is an FPGA-based System-on-Chip implementing an enhanced Intel 82077AA Floppy Disk Controller with diagnostic capabilities. The design targets the **AMD Spartan UltraScale+ SCU35 Evaluation Kit** with a MicroBlaze V (RISC-V) soft core. The HDL design is derived from the CAPSImg library's FDC emulator.

**Dual Interface Architecture**: FluxRipper supports two independent Shugart interfaces for 4 concurrent drives, enabling parallel flux capture and disk-to-disk copy operations.

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
│  ┌────────────────────────────────────────────────────────┼───────────────┐ │
│  │                        FDC Data Path                   │               │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┼─┐              │ │
│  │  │  Step    │  │   DPLL   │  │ Encoding │  │  Signal  │ │              │ │
│  │  │Controller│  │ (6 sub)  │  │ MFM/FM/  │  │ Quality  │ │              │ │
│  │  │          │  │          │  │   GCR    │  │ Monitor  │ │              │ │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────┘ │              │ │
│  │       │             │             │                     │              │ │
│  │  ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐  ┌───────────▼─┐             │ │
│  │  │  Motor   │  │    AM    │  │   CRC    │  │Write Precomp│             │ │
│  │  │Controller│  │ Detector │  │  CCITT   │  │             │             │ │
│  │  └────┬─────┘  └────┬─────┘  └──────────┘  └──────┬──────┘             │ │
│  │       │             │                             │                    │ │
│  └───────┼─────────────┼─────────────────────────────┼────────────────────┘ │
│          │             │                             │                      │
│          ▼             ▼                             ▼                      │
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
│  │   MicroBlaze V   │◄───── AXI4-Lite ─────┬──────────────────────────────┐ │
│  │    (RISC-V)      │                      │                              │ │
│  └────────┬─────────┘                      ▼                              │ │
│           │ AXI4              ┌────────────────────────┐                  │ │
│           │                   │  AXI FDC Peripheral    │                  │ │
│           │                   │  (Dual Interface Regs) │                  │ │
│           │                   │  0x00-0x2C: Standard   │                  │ │
│           │                   │  0x30-0x58: Dual Ext   │                  │ │
│           │                   └───────────┬────────────┘                  │ │
│           │                               │                               │ │
│  ┌────────┴─────────┐         ┌───────────┴────────────┐                  │ │
│  │   AXI DMA (2ch)  │         │    Dual FDC Core       │                  │ │
│  │   Controller     │         │                        │                  │ │
│  └────────┬─────────┘         │  ┌──────┐  ┌──────┐    │                  │ │
│           │                   │  │FDC A │  │FDC B │    │                  │ │
│           │ AXI-Stream (2x)   │  │Drv0/1│  │Drv2/3│    │                  │ │
│           │◄──────────────────│  └──┬───┘  └──┬───┘    │                  │ │
│           │                   │     │         │        │                  │ │
│           ▼                   └─────┼─────────┼────────┘                  │ │
│  ┌──────────────────┐               │         │                           │ │
│  │   HyperRAM       │               │         │                           │ │
│  │   Controller     │               │         │                           │ │
│  │   (8MB buffer)   │               │         │                           │ │
│  └──────────────────┘               │         │                           │ │
└─────────────────────────────────────┼─────────┼───────────────────────────┘ │
                                      │         │                             │
                        ┌─────────────┴───┐ ┌───┴─────────────┐               │
                        │  Level Shifter  │ │  Level Shifter  │               │
                        │  (Header 1)     │ │  (Header 2)     │               │
                        └────────┬────────┘ └────────┬────────┘               │
                                 │                   │                        │
                        ┌────────┴────────┐ ┌────────┴────────┐               │
                        │ 34-pin Shugart  │ │ 34-pin Shugart  │               │
                        │ Drives 0 & 1    │ │ Drives 2 & 3    │               │
                        └─────────────────┘ └─────────────────┘               │
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
                        │                      │                              │
                        │  ┌───────────────────▼──────────────────────────┐   │
                        │  │              Command FSM                     │   │
                        │  │   Type 1 │ Type 2 │ Type 3 │ Type 4          │   │
                        │  └────┬─────────┬────────────┬──────────────────┘   │
                        │       │         │            │                      │
         ┌──────────────┼───────┼─────────┼────────────┼───────────────────┐  │
         │              │       ▼         ▼            ▼                   │  │
         │  ┌───────────┴──┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │  │
         │  │    Step      │ │  Read   │ │  Write  │ │   AM    │           │  │
         │  │  Controller  │ │  Path   │ │  Path   │ │Detector │           │  │
         │  │              │ │         │ │         │ │         │           │  │
         │  │ Double-Step  │ │  Data   │ │ Precomp │ │ A1/C2   │           │  │
         │  └──────┬───────┘ │Separator│ │         │ │ Sync    │           │  │
         │         │         └────┬────┘ └────┬────┘ └────┬────┘           │  │
         │         │              │           │           │                │  │
         │  ┌──────▼───────┐ ┌────▼────┐ ┌────▼────┐ ┌────▼────┐           │  │
         │  │   Motor      │ │  DPLL   │ │  MFM    │ │  CRC    │           │  │
         │  │  Controller  │ │         │ │Encoder  │ │ CCITT   │           │  │
         │  └──────┬───────┘ └────┬────┘ └────┬────┘ └─────────┘           │  │
         │         │              │           │                            │  │
         └─────────┼──────────────┼───────────┼────────────────────────────┘  │
                   │              │           │                               │
                   ▼              ▼           ▼                               │
            ┌──────────────────────────────────────┐                          │
            │         Drive Interface              │◄─────────────────────────┘
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
┌────┬────┬────┬──────┬───────────────────────────────┐
│ 31 │ 30 │ 29 │28:27 │             26:0              │
├────┼────┼────┼──────┼───────────────────────────────┤
│ IX │ OV │ SC │DRV_ID│          Timestamp            │
└────┴────┴────┴──────┴───────────────────────────────┘
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
