# FluxRipper Register Map

*Updated: 2025-12-03 23:20*

## Intel 82077AA Compatible Registers

### Status Register A (SRA) - Address 0x3F0 (Read Only)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | INT | Interrupt pending |
| 6 | DRQ | DMA request |
| 5 | STEP | Step signal |
| 4 | TRK0 | Track 0 signal |
| 3 | HDSEL | Head select |
| 2 | INDEX | Index pulse |
| 1 | WP | Write protect |
| 0 | DIR | Direction |

### Status Register B (SRB) - Address 0x3F1 (Read Only)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | - | Reserved |
| 6 | DRV2 | Drive 2 data |
| 5 | DS1 | Drive select 1 |
| 4 | DS0 | Drive select 0 |
| 3 | WRDATA | Write data toggle |
| 2 | RDDATA | Read data toggle |
| 1 | WE | Write enable |
| 0 | MOT0 | Motor 0 on |

### Digital Output Register (DOR) - Address 0x3F2 (Read/Write)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | MOTD | Motor D enable |
| 6 | MOTC | Motor C enable |
| 5 | MOTB | Motor B enable |
| 4 | MOTA | Motor A enable |
| 3 | DMA | DMA enable |
| 2 | RESET | Controller reset (active low) |
| 1:0 | DSEL | Drive select (0-3) |

### Main Status Register (MSR) - Address 0x3F4 (Read Only)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | RQM | Request for master |
| 6 | DIO | Data I/O direction (1=read, 0=write) |
| 5 | NDMA | Non-DMA execution mode |
| 4 | CB | Controller busy |
| 3 | D3B | Drive 3 busy |
| 2 | D2B | Drive 2 busy |
| 1 | D1B | Drive 1 busy |
| 0 | D0B | Drive 0 busy |

### Data Rate Select Register (DSR) - Address 0x3F4 (Write Only)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | SWRST | Software reset |
| 6 | PD | Power down |
| 5 | - | Reserved |
| 4:2 | PRECOMP | Precompensation select |
| 1:0 | DRATE | Data rate select |

**Data Rate Select:**
- 00 = 500 Kbps
- 01 = 300 Kbps
- 10 = 250 Kbps
- 11 = 1 Mbps

### Data Register (FIFO) - Address 0x3F5 (Read/Write)

16-byte FIFO for command/result/data transfer.

### Digital Input Register (DIR) - Address 0x3F7 (Read Only)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | DSKCHG | Disk change |
| 6:0 | - | Reserved |

### Configuration Control Register (CCR) - Address 0x3F7 (Write Only)

| Bit | Name | Description |
|-----|------|-------------|
| 7:5 | - | Reserved |
| 4 | MAC_ZONE | Macintosh variable-speed zone mode enable |
| 3:2 | - | Reserved |
| 1:0 | DRATE | Data rate select |

#### MAC_ZONE Bit (CCR Bit 4) - FluxRipper Extension

When `MAC_ZONE = 1`, the DPLL data rate is automatically selected based on the current track position for Macintosh 400K/800K GCR disk decoding:

| Zone | Tracks | Data Rate | Bit Cell |
|------|--------|-----------|----------|
| 0 | 0-15 | 393.6 Kbps | 2.54 µs |
| 1 | 16-31 | 429.2 Kbps | 2.33 µs |
| 2 | 32-47 | 472.1 Kbps | 2.12 µs |
| 3 | 48-63 | 524.6 Kbps | 1.91 µs |
| 4 | 64-79 | 590.1 Kbps | 1.69 µs |

When `MAC_ZONE = 0` (default), the standard `DRATE` bits control the data rate.

**Also compatible with:** Apple Lisa (same zone structure)

## Status Registers (Result Phase)

### ST0 - Status Register 0

| Bit | Name | Description |
|-----|------|-------------|
| 7:6 | IC | Interrupt code |
| 5 | SE | Seek end |
| 4 | EC | Equipment check |
| 3 | NR | Not ready |
| 2 | HD | Head address |
| 1:0 | DS | Drive select |

**Interrupt Codes (IC):**
- 00 = Normal termination
- 01 = Abnormal termination
- 10 = Invalid command
- 11 = Abnormal termination (polling)

### ST1 - Status Register 1

| Bit | Name | Description |
|-----|------|-------------|
| 7 | EN | End of cylinder |
| 6 | - | Reserved (0) |
| 5 | DE | Data error (CRC) |
| 4 | OR | Overrun |
| 3 | - | Reserved (0) |
| 2 | ND | No data |
| 1 | NW | Not writable |
| 0 | MA | Missing address mark |

### ST2 - Status Register 2

| Bit | Name | Description |
|-----|------|-------------|
| 7 | - | Reserved (0) |
| 6 | CM | Control mark (deleted data) |
| 5 | DD | Data error in data field |
| 4 | WC | Wrong cylinder |
| 3 | SH | Scan equal hit |
| 2 | SN | Scan not satisfied |
| 1 | BC | Bad cylinder |
| 0 | MD | Missing data address mark |

### ST3 - Status Register 3

| Bit | Name | Description |
|-----|------|-------------|
| 7 | FT | Fault |
| 6 | WP | Write protect |
| 5 | RY | Ready |
| 4 | T0 | Track 0 |
| 3 | TS | Two side |
| 2 | HD | Head address |
| 1:0 | DS | Drive select |

## Command Summary

### Read Commands

| Command | Code | Parameters | Results |
|---------|------|------------|---------|
| READ DATA | 0x06 | HDS,C,H,R,N,EOT,GPL,DTL | ST0,ST1,ST2,C,H,R,N |
| READ DELETED | 0x0C | HDS,C,H,R,N,EOT,GPL,DTL | ST0,ST1,ST2,C,H,R,N |
| READ ID | 0x0A | HDS | ST0,ST1,ST2,C,H,R,N |
| READ TRACK | 0x02 | HDS,C,H,R,N,EOT,GPL,DTL | ST0,ST1,ST2,C,H,R,N |

### Write Commands

| Command | Code | Parameters | Results |
|---------|------|------------|---------|
| WRITE DATA | 0x05 | HDS,C,H,R,N,EOT,GPL,DTL | ST0,ST1,ST2,C,H,R,N |
| WRITE DELETED | 0x09 | HDS,C,H,R,N,EOT,GPL,DTL | ST0,ST1,ST2,C,H,R,N |
| FORMAT TRACK | 0x0D | HDS,N,SC,GPL,D | ST0,ST1,ST2,C,H,R,N |

### Control Commands

| Command | Code | Parameters | Results |
|---------|------|------------|---------|
| RECALIBRATE | 0x07 | DS | (none) |
| SEEK | 0x0F | HDS,NCN | (none) |
| SENSE INT | 0x08 | (none) | ST0,PCN |
| SENSE DRIVE | 0x04 | HDS | ST3 |
| SPECIFY | 0x03 | SRT/HUT,HLT/ND | (none) |
| CONFIGURE | 0x13 | 0,CONF,PRETRK | (none) |
| VERSION | 0x10 | (none) | 0x90 |

### Parameter Definitions

- **HDS**: Head select and drive select
- **C**: Cylinder number
- **H**: Head number
- **R**: Record (sector) number
- **N**: Sector size (0=128, 1=256, 2=512, 3=1024)
- **EOT**: End of track (last sector number)
- **GPL**: Gap length
- **DTL**: Data length (if N=0)
- **SC**: Sectors per cylinder
- **D**: Fill byte for format
- **NCN**: New cylinder number
- **SRT**: Step rate time
- **HUT**: Head unload time
- **HLT**: Head load time
- **ND**: Non-DMA mode
- **CONF**: Configuration byte
- **PRETRK**: Precompensation start track

---

## AXI4-Lite FDC Peripheral Register Map

The `axi_fdc_periph` module provides memory-mapped access to FDC registers for the MicroBlaze V soft core. All registers are 32-bit aligned.

### Register Summary

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | SRA_SRB | R | Status Registers A and B (packed) |
| 0x04 | DOR | R/W | Digital Output Register |
| 0x08 | TDR | R/W | Tape Drive Register |
| 0x0C | MSR_DSR | R/W | Main Status (R) / Data Rate Select (W) |
| 0x10 | DATA | R/W | FIFO Data Register |
| 0x14 | DIR_CCR | R/W | Digital Input (R) / Config Control (W) |
| 0x18 | FLUX_CTRL | R/W | Flux Capture Control |
| 0x1C | FLUX_STATUS | R | Flux Capture Status |
| 0x20 | CAPTURE_CNT | R | Flux Transition Count |
| 0x24 | INDEX_CNT | R | Index Pulse Count |
| 0x28 | QUALITY | R | Signal Quality Metrics |
| 0x2C | VERSION | R | Hardware Version |

### SRA_SRB (0x00) - Read Only

Packed status registers A and B.

| Bits | Name | Description |
|------|------|-------------|
| 31:16 | Reserved | Always 0 |
| 15:8 | SRB | Status Register B |
| 7:0 | SRA | Status Register A |

### DOR (0x04) - Read/Write

Digital Output Register (82077AA compatible).

| Bits | Name | Description |
|------|------|-------------|
| 31:8 | Reserved | Ignored on write, 0 on read |
| 7:4 | MOTOR | Motor enable bits (D:A) |
| 3 | DMA | DMA enable |
| 2 | RESET | Controller reset (active low) |
| 1:0 | DSEL | Drive select |

### TDR (0x08) - Read/Write

Tape Drive Register.

| Bits | Name | Description |
|------|------|-------------|
| 31:8 | Reserved | Ignored on write, 0 on read |
| 7:0 | TDR | Tape drive register value |

### MSR_DSR (0x0C) - Read/Write

Read returns Main Status Register, write sets Data Rate Select Register.

**Read (MSR):**
| Bits | Name | Description |
|------|------|-------------|
| 31:8 | Reserved | Always 0 |
| 7 | RQM | Request for Master |
| 6 | DIO | Data I/O direction |
| 5 | NDMA | Non-DMA mode |
| 4 | CB | Controller busy |
| 3:0 | DxB | Drive busy bits |

**Write (DSR):**
| Bits | Name | Description |
|------|------|-------------|
| 7 | SWRST | Software reset |
| 6:5 | PD | Power down |
| 4:2 | PRECOMP | Write precompensation |
| 1:0 | DRATE | Data rate select |

### DATA (0x10) - Read/Write

FIFO Data Register. Read pops from FIFO, write pushes to FIFO.

| Bits | Name | Description |
|------|------|-------------|
| 31:8 | Reserved | Ignored/0 |
| 7:0 | DATA | FIFO data byte |

### DIR_CCR (0x14) - Read/Write

Read returns Digital Input Register, write sets Configuration Control Register.

**Read (DIR):**
| Bits | Name | Description |
|------|------|-------------|
| 7 | DSKCHG | Disk change detect |
| 6:0 | Reserved | Always 0 |

**Write (CCR):**
| Bits | Name | Description |
|------|------|-------------|
| 7:2 | Reserved | Ignored |
| 1:0 | DRATE | Data rate select |

### FLUX_CTRL (0x18) - Read/Write

Flux capture control register (FluxRipper extended).

| Bits | Name | Description |
|------|------|-------------|
| 31:4 | Reserved | Ignored/0 |
| 3:2 | MODE | Capture mode (00=continuous, 01=one track, 10=one rev) |
| 1 | SOFT_RST | Soft reset (self-clearing, clears FIFO) |
| 0 | ENABLE | Capture enable |

### FLUX_STATUS (0x1C) - Read Only

Flux capture status register.

| Bits | Name | Description |
|------|------|-------------|
| 31 | CRITICAL | Signal critically degraded |
| 30 | DEGRADED | Signal degraded warning |
| 29 | OVERFLOW | FIFO overflow occurred |
| 28 | CAPTURING | Capture in progress |
| 27:26 | Reserved | Always 0 |
| 25:16 | FIFO_LEVEL | Current FIFO fill level (0-512) |
| 15:0 | INDEX_CNT | Index pulses seen (lower 16 bits) |

### CAPTURE_CNT (0x20) - Read Only

Flux transition count.

| Bits | Name | Description |
|------|------|-------------|
| 31:0 | COUNT | Total flux transitions captured |

### INDEX_CNT (0x24) - Read Only

Index pulse count.

| Bits | Name | Description |
|------|------|-------------|
| 31:16 | Reserved | Always 0 |
| 15:0 | COUNT | Index pulses seen |

### QUALITY (0x28) - Read Only

Signal quality metrics.

| Bits | Name | Description |
|------|------|-------------|
| 31:24 | Reserved | Always 0 |
| 23:16 | CONSISTENCY | Signal consistency (0-255) |
| 15:8 | STABILITY | Signal stability (0-255) |
| 7:0 | QUALITY | Overall quality (0-255, higher is better) |

### VERSION (0x2C) - Read Only

Hardware version identifier.

| Bits | Name | Description |
|------|------|-------------|
| 31:24 | ID | FluxRipper ID (0xFD) |
| 23:16 | MAJOR | Major version |
| 15:8 | MINOR | Minor version |
| 7:0 | PATCH | Patch version |

**Example:** Version 1.0.0 returns `0xFD010000`

---

## AXI-Stream Flux Data Format

The `axi_stream_flux` (single) and `axi_stream_flux_dual` (dual-interface) modules output 32-bit words via AXI-Stream.

### Data Word Format

```
┌────────┬────────┬────────┬────────┬───────────────────────────────┐
│ Bit 31 │ Bit 30 │ Bit 29 │ 28:27  │           Bits 26:0           │
├────────┼────────┼────────┼────────┼───────────────────────────────┤
│ INDEX  │  OVFL  │ SECTOR │ DRV_ID │          Timestamp            │
└────────┴────────┴────────┴────────┴───────────────────────────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| INDEX | 31 | Index pulse marker (1 = index pulse detected since last word) |
| OVFL | 30 | Overflow warning (FIFO was full when this transition occurred) |
| SECTOR | 29 | Hard-sector pulse marker (1 = sector hole detected since last word) |
| DRV_ID | 28:27 | Drive ID (0-3, identifies source drive) |
| Timestamp | 26:0 | 27-bit timestamp, ~5ns resolution at 200MHz, ~670ms range |

### DRV_ID Mapping

The DRV_ID field provides global drive identification across both interfaces:

| DRV_ID | Interface | Drive Select | Physical Drive |
|--------|-----------|--------------|----------------|
| 0 (00) | A | DS0 | Drive 0 |
| 1 (01) | A | DS1 | Drive 1 |
| 2 (10) | B | DS0 | Drive 2 |
| 3 (11) | B | DS1 | Drive 3 |

In single-interface mode, only DRV_ID 0 and 1 are used.

### INDEX, SECTOR, and Flux Word Semantics

The INDEX and SECTOR flags use **"pulse detected since last word"** semantics. The flags indicate that a pulse occurred between the previous flux word and this one.

**Word Types:**

| INDEX | SECTOR | Word Type | Description |
|-------|--------|-----------|-------------|
| 0 | 0 | Normal flux | Pure flux transition, no landmarks |
| 1 | 0 | Index marker | Index hole passed since last word |
| 0 | 1 | Sector marker | Hard-sector hole passed since last word |
| 1 | 1 | (rare) | Both index and sector in same interval |

**Note on INDEX words:** When INDEX=1, the word still contains a valid timestamp representing the flux transition (or synthesized timestamp at index time if no flux occurred). Software should use INDEX words as track boundary markers.

**Soft-sectored disks:** SECTOR is always 0. The /SECTOR input should be tied low or left unconnected.

**Hard-sectored disks (NorthStar, Vector Graphics, S-100):** SECTOR=1 marks that a sector hole passed. Software counts SECTOR markers to identify sector boundaries. Typical configurations:
- 10 sectors/track: 10 SECTOR pulses per revolution
- 16 sectors/track: 16 SECTOR pulses per revolution

### AXI-Stream Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| m_axis_tdata | 32 | Master→Slave | Flux data word |
| m_axis_tvalid | 1 | Master→Slave | Data valid |
| m_axis_tready | 1 | Slave→Master | DMA ready to accept |
| m_axis_tlast | 1 | Master→Slave | End of packet (index pulse) |
| m_axis_tkeep | 4 | Master→Slave | Byte enables (always 0xF) |

### Timing Characteristics

| Parameter | Value | Description |
|-----------|-------|-------------|
| Flux Capture Clock | 200 MHz | clk_sys domain (front-end) |
| AXI-Stream Clock | 100 MHz | aclk domain (back-end) |
| Timestamp Resolution | 5 ns | Direct from 200 MHz clock (no divider) |
| Timestamp Range | ~670 ms | Before 27-bit counter wraps (2^27 × 5ns) |
| FIFO Depth | 256 entries | Async FIFO for CDC (200→100 MHz) per interface |
| Max Burst | 256 words | Before FIFO must be drained |

**Note:** The timestamp resolution of 5ns provides excellent precision for all supported data rates (250 Kbps to 1 Mbps). The 670ms range comfortably exceeds a full revolution at any supported RPM (200ms at 300 RPM, 167ms at 360 RPM).

### Throughput Analysis

**Worst-case flux rate**: HD 1.44MB MFM at 500 Kbps
- Minimum bit cell: 2 µs
- Maximum flux transitions: ~500,000/second
- Data rate to DMA: 500K × 4 bytes = **2 MB/s**

**FIFO margin calculation**:
- FIFO depth: 512 entries × 4 bytes = 2048 bytes
- Fill time at max rate: 2048 / 2MB/s = **~1 ms**
- DMA must respond within 1 ms to avoid overflow

**DMA bandwidth requirement**:
- Minimum sustained: **2 MB/s** (HD MFM)
- Recommended: **4 MB/s** (2× margin for AXI backpressure)
- HyperRAM capability: ~100 MB/s (ample headroom)

**Capture mode considerations**:
| Mode | Duration | Data Volume | Notes |
|------|----------|-------------|-------|
| One Revolution | 200 ms | ~400 KB | Safe with any reasonable DMA latency |
| One Track | 400 ms | ~800 KB | Comfortable margin |
| Continuous | Unlimited | ~2 MB/s | Requires sustained DMA bandwidth |

### TLAST Semantics

The `m_axis_tlast` signal behavior:

| Mode | TLAST Behavior |
|------|----------------|
| One Revolution | Asserted on final index pulse; forms single AXI packet |
| One Track | Asserted on second index pulse; forms single AXI packet |
| Continuous | Asserted on every index pulse; each revolution is a packet |

**DMA configuration implications**:
- **Packet mode**: Use scatter-gather DMA with packet boundaries on TLAST
- **Linear mode**: Ignore TLAST, treat as continuous stream

### Timestamp Wrap Handling

The 27-bit timestamp wraps after ~670ms (2^27 × 5ns).

**For one-track/one-revolution modes**: No wrap concern (max 400ms at 300 RPM).

**For continuous mode**: Firmware must handle wrap by computing differences modulo 2^27:
```c
uint32_t delta = (new_ts - old_ts) & 0x07FFFFFF;  // 27-bit mask
```

Since typical track capture is ~200ms and the wrap point is ~670ms, wraps are rare during normal single-track operations.

### Usage Example (C firmware)

```c
#include "fdc_regs.h"

// Start flux capture (one track mode)
void start_flux_capture(void) {
    // Configure DMA for scatter-gather to HyperRAM
    axi_dma_configure(HYPERRAM_BASE, TRACK_BUFFER_SIZE);

    // Enable capture in one-track mode
    FDC_FLUX_CTRL = (CAPTURE_MODE_ONE_TRACK << 2) | CAPTURE_ENABLE;

    // Wait for capture complete
    while (FDC_FLUX_STATUS & FLUX_CAPTURING) {
        // Poll or use interrupt
    }

    // Read results
    uint32_t flux_count = FDC_CAPTURE_CNT;
    uint32_t quality = FDC_QUALITY & 0xFF;
}
```

---

## 82077AA Compatibility Notes

### Implementation Status

FluxRipper implements the Intel 82077AA-1 register interface with the following considerations:

#### Fully Implemented

| Feature | Notes |
|---------|-------|
| All Type 1 commands | RECALIBRATE, SEEK |
| All Type 2 commands | READ DATA, WRITE DATA, READ/WRITE DELETED |
| Type 3 commands | READ ID, READ TRACK, FORMAT TRACK |
| Type 4 commands | SENSE INTERRUPT, SENSE DRIVE, SPECIFY, CONFIGURE, VERSION |
| Multi-track (MT) bit | Automatic head switching |
| Multi-sector transfers | EOT-based sector counting |
| Implied seeks | Automatic seek before read/write |

#### Unimplemented Commands (Return Invalid Command)

| Command | Code(s) | Reason |
|---------|---------|--------|
| SCAN EQUAL | 0x11 | Host-side comparison; no practical FPGA benefit |
| SCAN LOW OR EQUAL | 0x19 | Host-side comparison; no practical FPGA benefit |
| SCAN HIGH OR EQUAL | 0x1D | Host-side comparison; no practical FPGA benefit |
| PERPENDICULAR MODE | 0x12 | 2.88MB ED drive support not targeted |
| RELATIVE SEEK | 0x8F | Rarely used; SEEK (0x0F) with absolute addressing preferred |

**SCAN commands** (0x11, 0x19, 0x1D): These commands read sector data and compare it byte-by-byte against host-supplied data, setting ST2.SH (Scan Hit) or ST2.SN (Scan Not Satisfied). Modern drivers perform this comparison in software after READ DATA. Implementing in hardware provides no benefit for preservation/diagnostic use cases.

#### TDR (Tape Drive Register) Semantics

The Tape Drive Register at 0x3F3 is **implemented as a stub**:
- Reads return the last written value
- Writes are stored but have no functional effect
- Original 82077AA used TDR for tape drive boot selection (tape support was vestigial by the -1 revision)

#### MSR/RQM/DIO Semantics

The Main Status Register follows 82077AA conventions:

| Bit | Polled By | Meaning for Driver |
|-----|-----------|-------------------|
| RQM (bit 7) | All operations | 1 = Controller ready for data transfer |
| DIO (bit 6) | Read/write decision | 1 = Controller → Host (read result/data); 0 = Host → Controller (write command/data) |
| CB (bit 4) | Command completion | 1 = Command in progress |

**Critical polling sequence** (matches PC BIOS and DOS drivers):
```c
// Wait for RQM before each byte transfer
while (!(MSR & 0x80)) ;  // Wait for RQM=1
if (MSR & 0x40) {
    data = DATA_REG;     // DIO=1: Read from controller
} else {
    DATA_REG = cmd_byte; // DIO=0: Write to controller
}
```

**Result phase behavior:**
- After command execution, RQM=1 and DIO=1 indicate result bytes ready
- ST0-ST3, C, H, R, N returned per command specification
- SENSE INTERRUPT must be issued after seek/recalibrate completion
- Failure to read all result bytes leaves controller in undefined state

#### CONFIGURE Command Differences

| Parameter | 82077AA Default | FluxRipper Default | Notes |
|-----------|-----------------|-------------------|-------|
| EIS (bit 6) | 0 (disabled) | 0 | Implied seek on read/write |
| EFIFO (bit 5) | 0 (enabled) | 0 | FIFO enabled |
| POLL (bit 4) | 0 (enabled) | 0 | Polling mode for completion |
| FIFOTHR (bits 3:0) | 1 | 1 | FIFO threshold (1 = 2 bytes) |
| PRETRK | 0 | 0 | Precompensation start track |

FluxRipper respects the CONFIGURE command but defaults match the 82077AA-1 power-on state.

#### Drive Select Behavior

- Only drives 0 and 1 are physically supported (2 floppy connectors)
- Selecting drives 2 or 3 returns ST0.EC (Equipment Check) on operations
- DOR motor bits 6-7 (drives C-D) are ignored

---

## Signal Quality Algorithm

### Overview

The `signal_quality_monitor` module provides real-time assessment of flux signal integrity. Metrics are computed per-revolution (on each index pulse) and exposed via the QUALITY register (0x28).

### Metric Definitions

#### QUALITY (bits 7:0)
**Overall signal quality score**: 0 (unusable) to 255 (excellent)

Calculated as: `QUALITY = (STABILITY / 2) + (CONSISTENCY / 2)`

#### STABILITY (bits 15:8)
**PLL lock stability**: Reflects how well the digital PLL maintains lock on the data stream.

**Derivation:**
- Accumulates `lock_quality` from DPLL on each valid flux transition
- `lock_quality` is an 8-bit metric from the PLL indicating instantaneous lock strength
- At each index pulse: `STABILITY = accumulated_lock_sum[15:8]`

**Interpretation:**
| Range | Meaning |
|-------|---------|
| 200-255 | Excellent lock, clean transitions |
| 150-199 | Good lock, minor jitter |
| 100-149 | Marginal lock, possible dropouts |
| 0-99 | Poor lock, unreliable data |

#### CONSISTENCY (bits 23:16)
**Flux interval consistency**: Measures variation in time between flux transitions.

**Derivation:**
- For each pair of consecutive flux transitions, computes `|interval_n - interval_(n-1)|`
- Accumulates absolute differences in `variance_sum`
- At each index pulse: `CONSISTENCY = 255 - variance_sum[23:16]`

Lower variance = higher consistency = better signal.

**Interpretation:**
| Range | Meaning |
|-------|---------|
| 200-255 | Very consistent (formatted, clean media) |
| 150-199 | Normal variation (typical used disk) |
| 100-149 | High variation (copy protection, wear) |
| 0-99 | Erratic (damaged media, misaligned head) |

### Warning Thresholds

| Status | Condition | FLUX_STATUS Bit |
|--------|-----------|-----------------|
| Normal | QUALITY ≥ 100 | Neither set |
| DEGRADED | 50 ≤ QUALITY < 100 | Bit 30 |
| CRITICAL | QUALITY < 50 | Bit 31 |

### Temporal Behavior

**Measurement window**: One revolution (~200ms at 300 RPM, ~167ms at 360 RPM)

**Update timing**: Metrics are computed and latched on each index pulse. Between index pulses, the QUALITY register holds the previous revolution's values.

**Sticky vs. instantaneous:**
- DEGRADED and CRITICAL are **instantaneous** (reflect current revolution)
- They clear automatically if the next revolution shows improvement
- Firmware can implement sticky behavior by OR-ing flags across multiple revolutions:

```c
static uint8_t sticky_status = 0;

void update_signal_status(void) {
    uint32_t status = FDC_FLUX_STATUS;
    sticky_status |= (status >> 30) & 0x03;  // Accumulate warnings
}

void clear_signal_status(void) {
    sticky_status = 0;
}
```

### Sample Count Requirements

Metrics require sufficient samples for statistical validity:
- Minimum: ~1000 flux transitions per revolution (typical for formatted disk)
- At HD 500Kbps: ~100,000 transitions/revolution (excellent statistics)
- Empty/DC-erased track: May show CRITICAL due to no transitions

### Hardware Implementation

From `rtl/diagnostics/flux_capture.v:signal_quality_monitor`:
```verilog
// Calculate overall quality on index pulse
if (index_pulse && measurement_count > 8'd0) begin
    stability <= lock_sum[15:8];

    if (variance_sum > 32'h00FF_FFFF)
        consistency <= 8'd0;
    else
        consistency <= 8'd255 - variance_sum[23:16];

    overall_quality <= (stability >> 1) + (consistency >> 1);

    degraded <= (overall_quality < 8'd100);
    critical <= (overall_quality < 8'd50);
end
```

---

## Extended Drive Control Signals

FluxRipper provides additional control signals for 8" drives, 5.25" HD drives, and hard-sectored media. These signals are directly exposed on GPIO pins (see `constraints/scu35_dual_pinout.xdc`).

### HEAD_LOAD (Output)

**Purpose:** Controls the head load solenoid on 8" drives with delayed-engagement heads (SA800/850-class, Wang, Xerox, DEC).

**Pin assignment:**
- `if_head_load_a` - Interface A (drives 0/1)
- `if_head_load_b` - Interface B (drives 2/3)

**Semantics:**
- **Assertion:** HEAD_LOAD asserts when any drive on the interface is selected AND a seek/read/write operation requires head engagement
- **Per-interface OR:** HEAD_LOAD is OR'd across drives on each interface, matching 50-pin Shugart bus semantics where HEAD_LOAD is per-bus (pin 4) and drives gate it internally with their DS
- **Timing:** HEAD_LOAD asserts during seek and remains asserted through head settle time; controlled by `step_controller.v`
- **Motor relationship:** HEAD_LOAD typically asserts when motor is on and drive is selected; some 8" drives tie HEAD_LOAD to MOTOR internally

**For 3.5"/5.25" drives:** HEAD_LOAD output is ignored (these drives load heads automatically when motor spins up). Leave unconnected or tie to GND.

### /TG43 (Output)

**Purpose:** Signals "Track Greater Than 43" for 5.25" HD drives that adjust write current on outer cylinders.

**Pin assignment:**
- `if_tg43_a` - Interface A
- `if_tg43_b` - Interface B

**Semantics:**
- **Assertion:** Asserts (active low on typical drives) when current track position ≥ 43
- **Derivation:** `if_tg43_x = (current_track >= 8'd43)`
- **Usage:** 5.25" 1.2MB HD and quad-density drives reduce write current on outer tracks to maintain signal integrity

**For 3.5" drives and DD-only 5.25" drives:** /TG43 is typically ignored. Leave unconnected or tie to VCC.

### DENSITY (Output)

**Purpose:** Indicates DD vs HD mode to drives with density-sensing capabilities.

**Pin assignment:**
- `if_density_a` - Interface A
- `if_density_b` - Interface B

**Semantics:**
- **Logic:**
  - `0` = Double Density (DD): data_rate ≤ 300 Kbps (250K or 300K)
  - `1` = High Density (HD): data_rate ≥ 500 Kbps (500K or 1M)
- **Derivation:** `if_density_x = (data_rate >= 2'b10)`
- **Threshold:** The 500 Kbps boundary matches PC-era combo drive expectations

**Note:** There is no separate ED (Extra Density) indicator. 2.88MB ED drives operating at 1 Mbps see DENSITY=1 (HD). ED drives internally detect the higher data rate via flux density.

**Data Rate to DENSITY Mapping:**

| data_rate[1:0] | Rate | DENSITY Output |
|----------------|------|----------------|
| 00 | 500 Kbps | 1 (HD) |
| 01 | 300 Kbps | 0 (DD) |
| 10 | 250 Kbps | 0 (DD) |
| 11 | 1 Mbps | 1 (HD) |

### /SECTOR (Input)

**Purpose:** Captures hard-sector pulses from drives with physically-sectored media (NorthStar, Vector Graphics, Micropolis, S-100).

**Pin assignment:**
- `if_sector_a` - Interface A
- `if_sector_b` - Interface B

**Semantics:**
- **Input:** Active-low pulse from drive's sector sensor (50-pin Shugart pin 28)
- **Edge detection:** Rising edge (pulse end) is detected and synchronized
- **Flux tagging:** Sets bit 29 (SECTOR) in the next flux word using "pulse detected since last word" semantics
- **Typical configurations:**
  - 10 sectors/track: 10 SECTOR pulses per revolution
  - 16 sectors/track: 16 SECTOR pulses per revolution

**For soft-sectored disks:** /SECTOR remains inactive (no pulses). Tie to VCC or leave floating with internal pull-up.

### GPIO Pin Summary

| Signal | Direction | Interface A Pin | Interface B Pin |
|--------|-----------|-----------------|-----------------|
| HEAD_LOAD | Output | C15 | G15 |
| /TG43 | Output | D15 | H15 |
| DENSITY | Output | A16 | E16 |
| /SECTOR | Input | B16 | F16 |
