# FluxRipper Memory & Storage Architecture

**Target Device:** AMD Spartan UltraScale+ XCSU35P-2SBVB625E
**Created:** 2025-12-07 10:17
**Updated:** 2025-12-07 10:17

---

## Overview

FluxRipper employs a three-tier memory hierarchy optimized for real-time flux capture, firmware execution, and long-term archival storage:

| Tier | Technology | Capacity | Latency | Persistence | Primary Role |
|------|------------|----------|---------|-------------|--------------|
| L1 | FPGA BRAM | 128 KB | 1 cycle | Volatile | Boot ROM, cache, stack |
| L2 | HyperRAM | 8 MB | 10-20 cycles | Volatile | Working memory, buffers |
| L3 | MicroSD | 32 GB+ | 1-10 ms | Non-volatile | Firmware, archives |

---

## Memory Hierarchy Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RISC-V SOFTCORE                                 │
│                                                                         │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│   │  I-Cache    │    │  D-Cache    │    │   Stack     │                 │
│   │   8 KB      │    │   8 KB      │    │   16 KB     │                 │
│   └──────┬──────┘    └──────┬──────┘    └─────────────┘                 │
│          │                  │                                           │
│          └────────┬─────────┘                                           │
│                   │                                                     │
│                   ▼                                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    AXI Interconnect                             │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│          │                  │                    │                      │
└──────────┼──────────────────┼────────────────────┼──────────────────────┘
           │                  │                    │
           ▼                  ▼                    ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐
    │  BRAM       │    │  HyperRAM   │    │  Peripherals    │
    │  64 KB ROM  │    │  8 MB       │    │  (inc. SD Ctrl) │
    │  64 KB RAM  │    │  166 MHz    │    │                 │
    └─────────────┘    └─────────────┘    └─────────────────┘
                             │
                             │ DMA
                             ▼
                       ┌───────────┐
                       │ Flux ADC  │
                       │ Flux DAC  │
                       └───────────┘
```

---

## Tier 1: FPGA Block RAM (BRAM)

### Specifications

| Parameter | Value |
|-----------|-------|
| Total Available | 106 × 18Kb = 1.93 Mb (238 KB) |
| Allocated to Memory | 128 KB |
| Access Latency | 1 clock cycle |
| Bandwidth | 32-bit @ 100 MHz = 400 MB/s |
| Port Configuration | True dual-port |

### BRAM Allocation

| Block | Size | Address Range | Purpose |
|-------|------|---------------|---------|
| Boot ROM | 16 KB | 0x0000_0000 - 0x0000_3FFF | Reset vector, bootstrap loader |
| Interrupt Vectors | 4 KB | 0x0000_4000 - 0x0000_4FFF | Exception handlers |
| I-Cache | 8 KB | N/A (internal) | 2-way set associative, 32B lines |
| D-Cache | 8 KB | N/A (internal) | 2-way set associative, write-back |
| Stack | 16 KB | 0x0001_0000 - 0x0001_3FFF | RISC-V call stack |
| Critical Data | 8 KB | 0x0001_4000 - 0x0001_5FFF | DMA descriptors, IRQ state |
| Peripheral FIFOs | 4 KB | 0x0001_6000 - 0x0001_6FFF | USB, UART buffers |
| **Total** | **64 KB** | | Used for memory |

### BRAM Reserved for Logic

| Block | BRAM Count | Purpose |
|-------|------------|---------|
| USB Endpoint Buffers | 4 × 18Kb | EP0-EP3 packet memory |
| Flux FIFO | 2 × 18Kb | Capture/playback staging |
| Debug Module | 1 × 18Kb | Program buffer, abstract data |
| **Total Reserved** | ~7 × 18Kb | ~16 KB equivalent |

---

## Tier 2: HyperRAM

### Specifications

| Parameter | Value |
|-----------|-------|
| Capacity | 8 MB (64 Mbit) |
| Interface | HyperBus (12 signals) |
| Clock | 166 MHz DDR |
| Bandwidth | 333 MB/s peak |
| Access Latency | 6 clocks initial (~36 ns) + 2 clocks/word |
| Refresh | Self-refresh (transparent) |

### HyperRAM Memory Map

| Region | Address Range | Size | Purpose |
|--------|---------------|------|---------|
| RISC-V .text | 0x4000_0000 - 0x401F_FFFF | 2 MB | Firmware code (cached XIP) |
| RISC-V .data/.bss | 0x4020_0000 - 0x402F_FFFF | 1 MB | Heap, global variables |
| Format Database | 0x4030_0000 - 0x4037_FFFF | 512 KB | Protection schemes, decoders |
| Precomp Tables | 0x4038_0000 - 0x403B_FFFF | 256 KB | Write precompensation data |
| Scratch | 0x403C_0000 - 0x403F_FFFF | 256 KB | Temporary processing |
| Track Buffer A | 0x4040_0000 - 0x405F_FFFF | 2 MB | Active capture (DMA target) |
| Track Buffer B | 0x4060_0000 - 0x407F_FFFF | 2 MB | Double-buffer / verification |

### HyperRAM Usage by Function

#### Real-Time Flux Capture
- **Track Buffer A/B**: DMA controller writes flux samples directly
- Double-buffering allows processing while capturing next track
- 2 MB per buffer supports ~10 seconds of raw flux at 50 MHz sample rate

#### RISC-V Execution
- Firmware executes from HyperRAM via instruction cache
- Heap allocations (malloc) from .data/.bss region
- Stack remains in BRAM for interrupt latency

#### Format Detection
- Format database loaded from MicroSD at boot
- Contains known protection scheme signatures
- Binary search structures for fast lookup

#### Multi-Revolution Analysis
- Store 10-20 revolutions of same track
- Compare timing variations for weak bit detection
- Uses Track Buffer B during single-track analysis mode

### HyperRAM Controller Features

| Feature | Description |
|---------|-------------|
| Burst Length | Variable (1-1024 words) |
| Address Mapping | Linear, no bank interleaving |
| Refresh | Handled by HyperRAM device (self-refresh) |
| DMA Channels | 2 (Flux capture, Flux playback) |
| Arbitration | Round-robin with priority boost for DMA |

---

## Tier 3: MicroSD Storage

### Specifications

| Parameter | Value |
|-----------|-------|
| Capacity | 32 GB (typical), up to 2 TB |
| Interface | SD 3.0 (4-bit, 50 MHz) |
| Bandwidth | 25-50 MB/s |
| Filesystem | FAT32 (≤32GB) or exFAT (>32GB) |
| Access Latency | 1-10 ms typical |

### Directory Structure

```
/
├── firmware/
│   ├── fluxripper_v1.0.bit      # FPGA bitstream
│   ├── fluxripper_v1.1.bit      # Backup/update bitstream
│   └── firmware.bin             # RISC-V firmware image
│
├── formats/
│   ├── amiga.fdb                # Amiga format database
│   ├── pc.fdb                   # PC format database
│   ├── c64.fdb                  # C64/GCR format database
│   ├── apple2.fdb               # Apple II format database
│   └── protection.fdb           # Copy protection signatures
│
├── precomp/
│   ├── default.pct              # Default precomp tables
│   └── drive_xxxxx.pct          # Per-drive calibration
│
├── captures/
│   ├── 2025-12-07/
│   │   ├── disk_001.ipf         # Captured disk images
│   │   ├── disk_001.raw         # Raw flux data (optional)
│   │   └── session.log          # Capture session log
│   └── .../
│
├── config/
│   ├── settings.cfg             # User preferences
│   ├── profiles/
│   │   ├── amiga_dd.cfg         # Amiga DD profile
│   │   └── pc_hd.cfg            # PC HD profile
│   └── calibration.dat          # System calibration
│
└── logs/
    ├── system.log               # System event log
    ├── errors.log               # Error history
    └── debug/                   # Debug dumps
```

### MicroSD Usage Patterns

| Pattern | Description | Frequency |
|---------|-------------|-----------|
| Boot Load | Read bitstream, firmware, format DB | Once at power-on |
| Config Read | Load user profiles, calibration | Once at power-on |
| Capture Write | Save completed disk images | Per-disk (1-4 MB) |
| Log Append | Write session logs, errors | Continuous (buffered) |
| Format Update | Refresh protection database | Occasional |

### Filesystem Driver

| Feature | Support |
|---------|---------|
| FAT32 | Full read/write |
| exFAT | Full read/write |
| Long Filenames | Yes (LFN) |
| Subdirectories | Yes |
| File Size Limit | 4 GB (FAT32), 16 EB (exFAT) |
| Allocation | First-fit, pre-allocation for captures |

---

## Data Flow Diagrams

### Disk Capture Flow

```
                                    ┌─────────────┐
                                    │  MicroSD    │
                                    │  (archive)  │
                                    └──────▲──────┘
                                           │
                                           │ 4. Save .IPF
                                           │
┌──────────┐    ┌──────────┐    ┌──────────┴──────────┐
│  Disk    │    │  Flux    │    │      HyperRAM       │
│  Head    │───►│  ADC     │───►│   Track Buffer A    │
└──────────┘    └──────────┘    └──────────┬──────────┘
                  1. Sample                │
                                           │ 2. DMA
                                           ▼
                                    ┌─────────────┐
                                    │   RISC-V    │
                                    │  (decode)   │
                                    └──────┬──────┘
                                           │
                                           │ 3. Process
                                           ▼
                                    ┌─────────────┐
                                    │  HyperRAM   │
                                    │   .data     │
                                    └─────────────┘
```

### Disk Write Flow

```
┌──────────┐    ┌──────────┐    ┌─────────────────────┐
│ MicroSD  │    │  RISC-V  │    │      HyperRAM       │
│  .IPF    │───►│ (encode) │───►│   Track Buffer A    │
└──────────┘    └──────────┘    └──────────┬──────────┘
  1. Load                                  │
                                           │ 2. Stage
                                           ▼
                                    ┌─────────────┐
                                    │  Flux DAC   │
                                    │  (DMA read) │
                                    └──────┬──────┘
                                           │
                                           │ 3. Output
                                           ▼
                                    ┌─────────────┐
                                    │  Disk Head  │
                                    └─────────────┘
```

### Boot Sequence

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. FPGA Configuration                                                   │
│    MicroSD ──► FPGA Config Logic ──► Bitstream Load                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. RISC-V Bootstrap                                                     │
│    BRAM Boot ROM ──► Initialize HyperRAM ──► Load firmware from SD      │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. Runtime Initialization                                               │
│    HyperRAM ◄── Format DB, Precomp Tables, Config                       │
│    (loaded from MicroSD, cached in HyperRAM)                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. Ready State                                                          │
│    USB enumeration complete, awaiting commands                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Cache Architecture

### Instruction Cache (I-Cache)

| Parameter | Value |
|-----------|-------|
| Size | 8 KB |
| Associativity | 2-way set associative |
| Line Size | 32 bytes |
| Sets | 128 |
| Replacement | LRU |
| Write Policy | N/A (read-only) |

### Data Cache (D-Cache)

| Parameter | Value |
|-----------|-------|
| Size | 8 KB |
| Associativity | 2-way set associative |
| Line Size | 32 bytes |
| Sets | 128 |
| Replacement | LRU |
| Write Policy | Write-back, write-allocate |

### Cache Coherency

| Scenario | Handling |
|----------|----------|
| DMA to HyperRAM | Software invalidate I-Cache before execution |
| DMA from HyperRAM | Software flush D-Cache before DMA |
| Peripheral MMIO | Uncached region (0x8000_0000+) |

---

## DMA Controller

### Channel Configuration

| Channel | Source | Destination | Width | Priority |
|---------|--------|-------------|-------|----------|
| 0 | Flux ADC FIFO | HyperRAM Track Buffer | 32-bit | High |
| 1 | HyperRAM Track Buffer | Flux DAC FIFO | 32-bit | High |
| 2 | MicroSD Controller | HyperRAM | 32-bit | Medium |
| 3 | HyperRAM | MicroSD Controller | 32-bit | Medium |

### DMA Descriptor Format

```
┌────────────────────────────────────────────────────────────────┐
│ 31:0   │ Source Address                                        │
├────────────────────────────────────────────────────────────────┤
│ 31:0   │ Destination Address                                   │
├────────────────────────────────────────────────────────────────┤
│ 31:16  │ Reserved  │ 15:0  │ Transfer Count (words)            │
├────────────────────────────────────────────────────────────────┤
│ 31:8   │ Next Descriptor Pointer  │ 7:0 │ Control Flags        │
└────────────────────────────────────────────────────────────────┘

Control Flags:
  [0]   - Enable
  [1]   - Interrupt on complete
  [2]   - Chain to next descriptor
  [3]   - Increment source address
  [4]   - Increment destination address
  [7:5] - Reserved
```

---

## Power Management

### Memory Power States

| State | BRAM | HyperRAM | MicroSD | Notes |
|-------|------|----------|---------|-------|
| Active | On | On | On | Full operation |
| Idle | On | Self-refresh | Clock-gated | Low-power wait |
| Standby | On | Self-refresh | Power-down | Minimal power |
| Off | Lost | Lost | Retained | Power removed |

### Considerations

- HyperRAM enters self-refresh automatically when not accessed
- MicroSD can be power-gated between file operations
- BRAM contents lost on power-down; boot from MicroSD required

---

## Performance Characteristics

### Bandwidth Summary

| Path | Bandwidth | Limiting Factor |
|------|-----------|-----------------|
| BRAM ↔ RISC-V | 400 MB/s | 32-bit @ 100 MHz |
| HyperRAM ↔ RISC-V | 200 MB/s | Cache miss penalty |
| HyperRAM ↔ DMA | 333 MB/s | HyperRAM interface |
| MicroSD ↔ DMA | 25-50 MB/s | SD interface |
| Flux ADC → HyperRAM | 50 MB/s | Sample rate |

### Latency Summary

| Access | Cycles | Time @ 100 MHz |
|--------|--------|----------------|
| BRAM read | 1 | 10 ns |
| HyperRAM (cache hit) | 1 | 10 ns |
| HyperRAM (cache miss) | 12-20 | 120-200 ns |
| MicroSD (first byte) | ~100K-1M | 1-10 ms |

---

## RISC-V Address Map Summary

| Region | Start | End | Size | Type |
|--------|-------|-----|------|------|
| Boot ROM | 0x0000_0000 | 0x0000_3FFF | 16 KB | BRAM (RO) |
| Vectors | 0x0000_4000 | 0x0000_4FFF | 4 KB | BRAM (RO) |
| BRAM RAM | 0x0001_0000 | 0x0001_FFFF | 64 KB | BRAM (RW) |
| HyperRAM | 0x4000_0000 | 0x407F_FFFF | 8 MB | HyperRAM (RW) |
| Peripherals | 0x8000_0000 | 0x8000_FFFF | 64 KB | MMIO (RW) |

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-07 10:17 | 1.0 | Initial document |
