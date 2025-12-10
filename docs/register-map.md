# FluxRipper Register Map

*Updated: 2025-12-08 00:35*

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

The Tape Drive Register at 0x3F3 enables QIC-117 tape mode:

| Bit | Name | Description |
|-----|------|-------------|
| 7 | TAPE_EN | Tape mode enable (1=tape, 0=floppy) |
| 6:3 | Reserved | Reserved, should be 0 |
| 2:0 | TAPE_SEL | Tape drive select (1-3, 0=none) |

When TAPE_EN=1, the FDC signal semantics change for QIC-117 tape protocol:
- **STEP** pulses encode commands (1-48 pulses = command code)
- **TRK0** becomes status output (time-encoded status bits)
- **INDEX** signals segment boundaries
- **RDATA/WDATA** carry continuous MFM data stream

See the "QIC-117 Tape Support" section below for complete tape register documentation

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

---

## ISA Real-Time Clock Registers (Universal Card)

The FluxRipper Universal card exposes its onboard PCF8563 RTC as an **AT-compatible MC146818 CMOS RTC** for legacy systems without a built-in clock.

### RTC Port Addresses (ISA Bus)

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x70 | RTC_ADDR | W | CMOS address register (index 0x00-0x3F) |
| 0x71 | RTC_DATA | R/W | CMOS data register |

### Standard CMOS Registers (MC146818 Compatible)

| Index | Name | Access | Description |
|-------|------|--------|-------------|
| 0x00 | Seconds | R/W | Current seconds (BCD 00-59) |
| 0x01 | Seconds Alarm | R/W | Alarm seconds (BCD 00-59) |
| 0x02 | Minutes | R/W | Current minutes (BCD 00-59) |
| 0x03 | Minutes Alarm | R/W | Alarm minutes (BCD 00-59) |
| 0x04 | Hours | R/W | Current hours (BCD 00-23 or 01-12+AM/PM) |
| 0x05 | Hours Alarm | R/W | Alarm hours |
| 0x06 | Day of Week | R/W | Day of week (1-7, Sunday=1) |
| 0x07 | Day of Month | R/W | Day of month (BCD 01-31) |
| 0x08 | Month | R/W | Month (BCD 01-12) |
| 0x09 | Year | R/W | Year (BCD 00-99) |
| 0x0A | Status A | R/W | Update-in-progress flag, divider |
| 0x0B | Status B | R/W | Interrupt enables, data format |
| 0x0C | Status C | R | Interrupt flags (read clears) |
| 0x0D | Status D | R | Battery status (VRT bit) |
| 0x32 | Century | R/W | Century (BCD 19-20) |

### Status Register A (0x0A)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | UIP | Update In Progress (1 = update cycle active) |
| 6:4 | DV | Divider select (typically 010 for 32.768kHz) |
| 3:0 | RS | Rate select (periodic interrupt rate) |

**Note:** Wait for UIP=0 before reading time to avoid reading during update.

### Status Register B (0x0B)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | SET | 1 = Halt updates for setting time |
| 6 | PIE | Periodic Interrupt Enable |
| 5 | AIE | Alarm Interrupt Enable |
| 4 | UIE | Update-ended Interrupt Enable |
| 3 | SQWE | Square Wave Enable |
| 2 | DM | Data Mode (0=BCD, 1=Binary) |
| 1 | 24/12 | Hour format (1=24-hour, 0=12-hour) |
| 0 | DSE | Daylight Savings Enable |

### Status Register C (0x0C) - Read Only

| Bit | Name | Description |
|-----|------|-------------|
| 7 | IRQF | Interrupt Request Flag |
| 6 | PF | Periodic Interrupt Flag |
| 5 | AF | Alarm Flag |
| 4 | UF | Update-ended Flag |
| 3:0 | - | Reserved (0) |

**Note:** Reading this register clears all interrupt flags.

### Status Register D (0x0D) - Read Only

| Bit | Name | Description |
|-----|------|-------------|
| 7 | VRT | Valid RAM and Time (1 = battery OK) |
| 6:0 | - | Reserved (0) |

### Implementation Notes

**Hardware Translation:**
- PCF8563 (I2C) registers are translated to MC146818 format in FPGA logic
- BCD conversion handled automatically
- ~50 LUTs for address decode + BCD conversion

**Battery Backup:**
- CR2032 coin cell maintains time when system powered off
- VRT bit (Status D, bit 7) indicates battery health

**Use Cases:**
- **XT Clones:** Add RTC to IBM PC, early clones without built-in clock
- **DOS DATE/TIME:** Automatic clock set at boot via BIOS
- **Legacy Software:** Y2K-compliant century register (0x32)

**DIP Switch Configuration:**
- SW1-5: RTC Enable (ON = enabled at 0x70-0x71, OFF = disabled)
- Disable RTC on systems with built-in CMOS RTC to avoid conflicts

### Usage Example (DOS/BIOS)

```asm
; Read current hour from RTC
    mov  al, 04h        ; Index 04h = Hours
    out  70h, al        ; Write to address port
    in   al, 71h        ; Read from data port
    ; AL now contains hours in BCD format

; Set time (example: 12:30:00)
    mov  al, 0Bh        ; Status B register
    out  70h, al
    in   al, 71h
    or   al, 80h        ; Set SET bit (halt updates)
    out  71h, al

    mov  al, 04h        ; Hours
    out  70h, al
    mov  al, 12h        ; 12 hours (BCD)
    out  71h, al

    mov  al, 02h        ; Minutes
    out  70h, al
    mov  al, 30h        ; 30 minutes (BCD)
    out  71h, al

    mov  al, 00h        ; Seconds
    out  70h, al
    mov  al, 00h        ; 00 seconds (BCD)
    out  71h, al

    mov  al, 0Bh        ; Status B
    out  70h, al
    in   al, 71h
    and  al, 7Fh        ; Clear SET bit (resume updates)
    out  71h, al
```

---

## Universal Card Extended Registers

### MicroSD Status (SPI)

| Register | Address | Description |
|----------|---------|-------------|
| SD_STATUS | 0xA0 | Card detect, write protect, busy |
| SD_CTRL | 0xA4 | SPI enable, clock divider |

### Rotary Encoder

| Register | Address | Description |
|----------|---------|-------------|
| ENC_STATUS | 0xB0 | Position delta, button state |
| ENC_COUNT | 0xB4 | Absolute position counter |

### Power Monitor (INA3221)

| Register | Address | Description |
|----------|---------|-------------|
| PWR_DRV0 | 0x80 | Drive 0: +5V current [15:0], +12V current [31:16] |
| PWR_DRV1 | 0x84 | Drive 1: +5V current [15:0], +12V current [31:16] |
| PWR_DRV2 | 0x88 | Drive 2: +5V current [15:0], +12V current [31:16] |
| PWR_DRV3 | 0x8C | Drive 3: +5V current [15:0], +12V current [31:16] |
| PWR_RAILS | 0x90 | +5V voltage [15:0], +12V voltage [31:16] |
| PWR_24V | 0x94 | +24V voltage [15:0], +24V current [31:16] |
| PWR_ALERTS | 0x98 | Over-current/under-voltage flags |

---

## JTAG Debug Subsystem Registers

The FluxRipper debug subsystem provides JTAG-accessible registers for hardware bring-up and diagnostics.

### JTAG TAP Controller

| IR Value | Register | Width | Description |
|----------|----------|-------|-------------|
| 0x00 | EXTEST | N/A | External test (not implemented) |
| 0x01 | IDCODE | 32 | Device identification |
| 0x10 | DTMCS | 32 | Debug Transport Module Control/Status |
| 0x11 | DMI | 41 | Debug Module Interface access |
| 0x1F | BYPASS | 1 | Bypass register |

### IDCODE (IR=0x01)

**Value:** 0xFB010001

```
┌────────────────┬────────────────┬────────────────┬────┐
│   Version [4]  │   Part [16]    │   Manuf [11]   │ 1  │
│    0xF (15)    │   0xB010       │    0x000       │    │
└────────────────┴────────────────┴────────────────┴────┘
```

| Field | Bits | Value | Description |
|-------|------|-------|-------------|
| Version | 31:28 | 0xF | FluxRipper version 1 |
| Part Number | 27:12 | 0xB010 | FluxRipper JTAG debug |
| Manufacturer | 11:1 | 0x000 | Unassigned (non-commercial) |
| LSB | 0 | 1 | Required by IEEE 1149.1 |

### DTMCS - Debug Transport Module Control/Status (IR=0x10)

| Bits | Name | Access | Description |
|------|------|--------|-------------|
| 31:18 | Reserved | R | Always 0 |
| 17 | dmihardreset | W | Hard reset DMI |
| 16 | dmireset | W | Clear DMI error state |
| 15 | Reserved | R | Always 0 |
| 14:12 | idle | R | Idle cycles required (0x1 = 1 cycle) |
| 11:10 | dmistat | R | DMI status (0=ok, 2=failed, 3=busy) |
| 9:4 | abits | R | Address bits (0x07 = 7 bits) |
| 3:0 | version | R | DTM version (0x1 = v0.13) |

**Read value:** 0x00001071 (idle=1, abits=7, version=1)

### DMI - Debug Module Interface (IR=0x11)

41-bit shift register for Debug Module access:

```
┌───────────────┬───────────────────────────────────┬─────────┐
│  addr [40:34] │           data [33:2]             │ op [1:0]│
│    7 bits     │             32 bits               │  2 bits │
└───────────────┴───────────────────────────────────┴─────────┘
```

**Operation codes (op):**
| Value | Direction | Meaning |
|-------|-----------|---------|
| 00 | Write | NOP - no operation |
| 01 | Write | Read from addr |
| 10 | Write | Write data to addr |
| 11 | Write | Reserved |
| 00 | Read | Success |
| 01 | Read | Reserved |
| 10 | Read | Failed |
| 11 | Read | Busy |

### Debug Module Registers (via DMI)

#### System Bus Access Registers

| Addr | Name | Access | Description |
|------|------|--------|-------------|
| 0x38 | sbcs | R/W | System Bus Control/Status |
| 0x39 | sbaddress0 | R/W | System Bus Address [31:0] |
| 0x3C | sbdata0 | R/W | System Bus Data [31:0] |

#### sbcs - System Bus Control/Status (DMI 0x38)

| Bits | Name | Description |
|------|------|-------------|
| 31:29 | sbversion | System bus version (1) |
| 22 | sbbusyerror | Busy error (W1C) |
| 21 | sbbusy | Bus operation in progress |
| 20 | sbreadonaddr | Auto-read on address write |
| 19:17 | sbaccess | Access size (2=32-bit) |
| 16 | sbautoincrement | Auto-increment address |
| 15 | sbreadondata | Auto-read on data read |
| 14:12 | sberror | Error code (W1C) |
| 11:5 | sbasize | Address size (32) |
| 4:0 | sbaccess128-8 | Supported access sizes |

**Typical configuration for 32-bit access:**
- Write 0x00000404 to enable 32-bit access with read-on-addr

### Peripheral Registers (via System Bus)

#### System Control (Base: 0x4000_0000)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | SYSCTRL_ID | R | System ID: 0xFB010100 |

#### Disk Controller (Base: 0x4001_0000)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | DISK_ID | R | Disk controller ID |
| 0x04 | DISK_CTRL | R/W | Control: [2]=motor_on, [1]=head_sel, [0]=enabled |
| 0x08 | DISK_STATUS | R | Status: [1]=index, [0]=flux_in |
| 0x0C | DISK_DMA | R/W | DMA control |
| 0x10 | DISK_INDEX_CNT | R | Index pulse counter |

#### USB Controller (Base: 0x4002_0000)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | USB_ID | R | USB controller ID: 0x05B20001 |
| 0x04 | USB_STATUS | R | Status: [1]=configured, [0]=connected |
| 0x08 | USB_CTRL | R/W | Control: [1]=configured_en, [0]=connected_en |

#### Signal Tap (Base: 0x4003_0000)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | SIGTAP_ID | R | Signal Tap ID: 0x51670001 |
| 0x04 | SIGTAP_STATUS | R | Status: [3]=triggered, [2]=full, [1]=running, [0]=armed |
| 0x08 | SIGTAP_CTRL | R/W | Control: [0]=arm |
| 0x0C | SIGTAP_TRIG_VAL | R/W | Trigger value |
| 0x10 | SIGTAP_TRIG_MASK | R/W | Trigger mask |
| 0x14 | SIGTAP_WRITE_PTR | R | Write pointer |
| 0x40-0x7F | SIGTAP_BUFFER | R | Captured probe data (256 entries) |

### JTAG Access Examples

#### Read IDCODE via OpenOCD
```tcl
irscan fluxripper.tap 0x01
drscan fluxripper.tap 32 0
# Returns: fb010001
```

#### Read System Control ID via Debug Module
```tcl
# Select DMI register
irscan fluxripper.tap 0x11

# Configure sbcs for 32-bit read-on-addr
# addr=0x38, data=0x00000404, op=write(2)
drscan fluxripper.tap 41 0x1C000002024

# Write target address to sbaddress0
# addr=0x39, data=0x40000000, op=write(2)
drscan fluxripper.tap 41 0x1C800000002

# Read result from sbdata0
# addr=0x3C, data=0, op=read(1)
drscan fluxripper.tap 41 0x1E000000001

# Shift out result
drscan fluxripper.tap 41 0
# data field contains 0xFB010100
```

---

## User Configuration Registers (ISA)

The FluxRipper FPGA provides user-configurable registers for enabling/disabling controllers at runtime. These registers are accessible from the Option ROM BIOS via the F3 diagnostics menu.

### Register Base Address

| Controller | Base Address | Config Offset | Config Base |
|------------|--------------|---------------|-------------|
| FDC | 0x3F0 | +0xD0 | 0x4C0 |
| WD HDD (AT) | 0x1F0 | +0xD0 | 0x2C0 |
| WD HDD (XT) | 0x320 | +0xD0 | 0x3F0 |

**Note:** In XT mode, the WD controller uses base 0x320. The BIOS uses the `current_base` variable to access the correct address.

### Register Map (offset from config base)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | CONFIG_CTRL | R/W | Global control register |
| 0x01 | CONFIG_FDC | R/W | FDC configuration |
| 0x02 | CONFIG_WD | R/W | WD HDD configuration |
| 0x03 | CONFIG_DMA | R/W | DMA configuration |
| 0x04 | CONFIG_IRQ | R/W | IRQ configuration |
| 0x05 | CONFIG_STATUS | R | Status register |
| 0x06 | CONFIG_SCRATCH | R/W | Scratch register (BIOS use) |
| 0x07 | CONFIG_MAGIC | R | Magic number (0xFB) |
| 0x08 | CONFIG_INTLV_CTRL | R/W | Interleave control |
| 0x09 | CONFIG_INTLV_STAT | R | Detected interleave (read-only) |
| 0x0E | CONFIG_SAVE | W | Write 0x5A to save to flash |
| 0x0F | CONFIG_RESTORE | W | Write 0xA5 to restore defaults |

### CONFIG_CTRL (0x00) - Global Control

| Bit | Name | Default | Description |
|-----|------|---------|-------------|
| 0 | FDC_EN | 1 | FDC controller enabled |
| 1 | WD_EN | 1 | WD HDD controller enabled |
| 2-3 | Reserved | 0 | Reserved |
| 4 | LOCKED | 0 | Configuration write-protected |
| 5-7 | Reserved | 0 | Reserved |

**Unlock mechanism:** When LOCKED=1, writes are blocked. To unlock, write the value with bit 4 clear. This allows unlocking even when locked.

### CONFIG_FDC (0x01) - FDC Configuration

| Bit | Name | Default | Description |
|-----|------|---------|-------------|
| 0 | FDC_DMA_EN | 1 | FDC DMA enabled |
| 1 | FDC_SEC_EN | 0 | Secondary FDC (0x370) enabled |
| 2-7 | Reserved | 0 | Reserved |

### CONFIG_WD (0x02) - WD HDD Configuration

| Bit | Name | Default | Description |
|-----|------|---------|-------------|
| 0 | WD_DMA_EN | 1 | WD DMA enabled (XT mode only) |
| 1 | WD_SEC_EN | 0 | Secondary WD (0x170) enabled |
| 2-6 | Reserved | 0 | Reserved |
| 7 | BUF_BYPASS | 0 | Track buffer bypass (for benchmark) |

**Track Buffer Bypass (Bit 7):**
- When set to 1, disables track buffer caching for reads
- Every sector read goes directly to disk (no cache hits)
- Used by the Interleave Benchmark to simulate stock WD controller behavior
- Should be cleared (0) for normal operation

### CONFIG_DMA (0x03) - DMA Configuration

| Bits | Name | Default | Description |
|------|------|---------|-------------|
| 2:0 | FDC_DMA | 2 | FDC DMA channel (0-7) |
| 3 | Reserved | 0 | Reserved |
| 6:4 | WD_DMA | 3 | WD DMA channel (0-7, XT only) |
| 7 | Reserved | 0 | Reserved |

### CONFIG_IRQ (0x04) - IRQ Configuration

| Bits | Name | Default | Description |
|------|------|---------|-------------|
| 3:0 | FDC_IRQ | 6 | FDC IRQ line (0-15) |
| 7:4 | WD_IRQ | 14 | WD IRQ line (0-15) |

### CONFIG_STATUS (0x05) - Status Register (Read-Only)

| Bit | Name | Description |
|-----|------|-------------|
| 0 | 8BIT | 8-bit XT slot detected |
| 1 | 16BIT | 16-bit AT slot detected |
| 2 | PNP | PnP mode active |
| 3 | FLASH_BUSY | Flash operation in progress |
| 5:4 | WD_PERS | WD Personality (0=WD1002, 1=WD1003, 2=WD1006, 3=WD1007) |
| 6 | FDC_PRESENT | FDC hardware installed |
| 7 | WD_PRESENT | WD hardware installed |

### CONFIG_MAGIC (0x07) - Magic Number (Read-Only)

Always returns 0xFB. Used by BIOS to detect FluxRipper config registers presence.

### CONFIG_INTLV_CTRL (0x08) - Interleave Control

| Bits | Name | Default | Description |
|------|------|---------|-------------|
| 3:0 | INTLV | 0 | Target interleave (0=auto, 1-8=override) |
| 7:4 | Reserved | 0 | Reserved, reads as 0 |

**Interleave Values:**
- `0` = Auto-match (preserve existing interleave from disk)
- `1` = 1:1 interleave (no interleave, fastest)
- `2` = 2:1 interleave (typical for 286)
- `3` = 3:1 interleave (typical for XT)
- `4-6` = Higher interleave for slower systems
- `7-8` = Very slow systems

**Behavior:**
- When set to 0 (Auto), the FPGA detects and preserves the existing disk interleave pattern on read/write operations
- When set to 1-8, the FPGA uses the specified interleave for FORMAT TRACK operations
- The interleave setting affects how sector IDs are arranged on a newly formatted track
- Auto-match is recommended for disk preservation/forensic applications

### CONFIG_INTLV_STAT (0x09) - Detected Interleave (Read-Only)

| Bits | Name | Description |
|------|------|-------------|
| 3:0 | DETECTED | Last detected interleave (1-8, or 0 if unknown) |
| 7:4 | Reserved | Reserved, reads as 0 |

**Notes:**
- This register reflects the interleave pattern detected from the last track read
- Value is updated by the FPGA's interleave detection logic during disk reads
- Returns 0 if no track has been read or detection failed
- Detection analyzes the physical order of sector IDs on the track

**Example Usage (Assembly):**
```asm
; Read detected interleave
    mov     dx, WD_BASE + 0xD0 + 0x09   ; CONFIG_INTLV_STAT
    in      al, dx
    and     al, 0x0F                     ; Mask to interleave value
    ; AL now contains detected interleave (1-8) or 0

; Set interleave override to 3:1
    mov     dx, WD_BASE + 0xD0 + 0x08   ; CONFIG_INTLV_CTRL
    mov     al, 3                        ; 3:1 interleave
    out     dx, al

; Return to auto-match mode
    mov     dx, WD_BASE + 0xD0 + 0x08   ; CONFIG_INTLV_CTRL
    xor     al, al                       ; 0 = auto-match
    out     dx, al
```

### CONFIG_SAVE (0x0E) - Save to Flash

Write 0x5A to save current configuration to flash storage. Check CONFIG_STATUS.FLASH_BUSY until clear.

### CONFIG_RESTORE (0x0F) - Restore Defaults

Write 0xA5 to restore factory defaults (both controllers enabled).

### Usage Example (Assembly)

```asm
; Check if FluxRipper config registers are present
    mov     dx, 0x3F0 + 0xD0 + 0x07   ; FDC base + config offset + MAGIC
    in      al, dx
    cmp     al, 0xFB                   ; Check magic
    jne     .no_fluxripper

; Read current configuration
    mov     dx, 0x3F0 + 0xD0 + 0x00   ; CONFIG_CTRL
    in      al, dx

; Disable WD controller
    and     al, ~0x02                  ; Clear WD_EN bit
    out     dx, al

; Save to flash
    mov     dx, 0x3F0 + 0xD0 + 0x0E   ; CONFIG_SAVE
    mov     al, 0x5A                   ; Save magic
    out     dx, al

; Wait for flash complete
.wait_flash:
    mov     dx, 0x3F0 + 0xD0 + 0x05   ; CONFIG_STATUS
    in      al, dx
    test    al, 0x08                   ; FLASH_BUSY
    jnz     .wait_flash
```

### Edge Cases and Limitations

#### Cannot Disable Host Controller

**Critical limitation:** You cannot disable the controller that hosts the config registers from its own BIOS.

| BIOS | Cannot Disable | Can Disable |
|------|----------------|-------------|
| FDD BIOS | FDC | WD HDD |
| HDD BIOS | WD HDD | FDC |

If you disable the host controller and save to flash, you lose access to re-enable it. The BIOS prevents this by blocking the toggle operation.

#### 8KB ROM Build Limitation

The F3 diagnostics menu (including config) is only available in 16KB ROM builds. Systems using 8KB ROMs cannot access the config menu.

```asm
%if BUILD_16KB && ENABLE_DIAG
    ; Config menu code here
%endif
```

**Workaround:** Use a USB configuration tool or JTAG to modify settings.

#### PnP Mode Override Warning

When PnP mode is active (CONFIG_STATUS.PNP=1), the OS PnP driver may override user settings. Settings saved via the F3 menu take effect only in legacy mode.

#### Configuration Lock

If CONFIG_CTRL.LOCKED=1:
- All register writes are blocked (except unlock)
- Save and restore operations are blocked
- Press [U] in F3 menu to unlock

#### Flash Timeout

Flash save operations should complete within ~1 second. If CONFIG_STATUS.FLASH_BUSY remains set after timeout, the save failed. The BIOS reports "Settings NOT saved" in this case.

#### XT Mode I/O Base

In 8-bit XT mode, the WD controller uses base 0x320 instead of 0x1F0. The HDD BIOS uses the `current_base` variable to access the correct config register address. The config menu displays "I/O Base: 0x0320" for verification.

#### Controller Presence Bits

CONFIG_STATUS bits 6-7 indicate whether FDC/WD hardware is actually installed. If a controller is not present (bit=0), the BIOS displays "(not installed)" and prevents toggle operations.

---

## QIC-117 Tape Support

FluxRipper includes QIC-117 floppy-interface tape drive support for capturing data from QIC-40, QIC-80, QIC-3010, and QIC-3020 tape drives.

### Supported Tape Standards

| Standard | Tracks | Capacity | Data Rate | BPI |
|----------|--------|----------|-----------|-----|
| QIC-40 | 20 | 40 MB | 250-500 Kbps | 10,000 |
| QIC-80 | 28 | 80-170 MB | 500 Kbps | 12,500 |
| QIC-3010 | 40-50 | 340 MB | 500 Kbps | 22,125 |
| QIC-3020 | 40-50 | 680 MB | 1 Mbps | 22,125 |

### TDR Register (0x3F3) - Tape Mode Control

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 7 | TAPE_EN | R/W | Tape mode enable (1=tape mode, 0=floppy mode) |
| 6:3 | Reserved | R | Reserved, reads as 0 |
| 2:0 | TAPE_SEL | R/W | Tape drive select (1-3, 0=none selected) |

**Mode switching:**
- Setting TAPE_EN=1 activates QIC-117 tape protocol
- All FDC signal semantics change (see table below)
- Setting TAPE_EN=0 returns to standard floppy mode
- State is reset when switching modes

### Signal Reinterpretation (Tape Mode)

When TDR[7]=1 (tape mode enabled), FDC signals have different meanings:

| Signal | Floppy Mode | Tape Mode (QIC-117) |
|--------|-------------|---------------------|
| STEP | Head step pulse | Command bit (count = command code) |
| DIR | Head direction | Unused (direction internal to drive) |
| TRK0 | Track 0 sensor | Status bit stream output (time-encoded) |
| INDEX | Index hole | Segment boundary marker |
| RDATA | Disk read data | Tape MFM data stream (continuous) |
| WDATA | Disk write data | Tape MFM write stream (continuous) |

### QIC-117 Command Protocol

Commands are sent by issuing STEP pulses. The number of pulses (1-48) determines the command:

| Pulses | Command | Description |
|--------|---------|-------------|
| 1 | RESET_1 | Soft reset |
| 2 | RESET_2 | Hard reset |
| 4 | REPORT_STATUS | Report 8-bit status word via TRK0 |
| 5 | REPORT_NEXT_BIT | Report next status bit via TRK0 |
| 6 | PAUSE | Stop tape motion |
| 7 | MICRO_STEP_PAUSE | Micro-step pause |
| 8 | SEEK_LOAD_POINT | Seek to BOT (beginning of tape) |
| 9 | SEEK_EOT | Seek to EOT (end of tape) |
| 10 | SKIP_REV_SEG | Skip 1 segment reverse |
| 11 | SKIP_REV_FILE | Skip to previous file mark |
| 12 | SKIP_FWD_SEG | Skip 1 segment forward |
| 13 | SKIP_FWD_FILE | Skip to next file mark |
| 21 | LOGICAL_FWD | Enter logical forward streaming mode |
| 22 | LOGICAL_REV | Enter logical reverse streaming mode |
| 23 | STOP_TAPE | Stop tape motion |
| 30 | PHYSICAL_FWD | Physical forward motion |
| 31 | PHYSICAL_REV | Physical reverse motion |
| 36 | NEW_CARTRIDGE | Signal new cartridge inserted |
| 45 | SELECT_RATE | Select data rate |
| 46 | PHANTOM_SELECT | Enable drive (phantom select) |
| 47 | PHANTOM_DESELECT | Disable drive |

**Command timing:**
- Minimum inter-pulse gap: ~2.5ms (set by FDC SPECIFY register)
- Command timeout: 100ms after last STEP pulse
- After timeout, pulse count is latched as command code

### TRK0 Status Encoding

Status bits are encoded as pulse widths on the TRK0 signal:

| Bit Value | TRK0 Low Time | Gap Time |
|-----------|---------------|----------|
| 0 | 500 µs | 1000 µs |
| 1 | 1500 µs | 1000 µs |

**Status byte format (MSB first):**

| Bit | Name | Description |
|-----|------|-------------|
| 7 | READY | Drive ready |
| 6 | ERROR | Error condition |
| 5 | CARTRIDGE | Cartridge present |
| 4 | WRITE_PROT | Write protected |
| 3 | NEW_CART | New cartridge detected |
| 2 | AT_BOT | At beginning of tape |
| 1 | AT_EOT | At end of tape |
| 0 | Reserved | Reserved (always 0) |

### Extended Tape Registers (AXI)

Additional tape status registers are available via AXI peripheral access.

#### TAPE_STATUS (Offset 0x30) - Read Only

| Bits | Name | Description |
|------|------|-------------|
| 31:24 | Reserved | Always 0 |
| 23:16 | TAPE_STATE | FSM state (debug) |
| 15:8 | STATUS_WORD | Current status byte |
| 7 | READY | Drive ready |
| 6 | ERROR | Error condition |
| 5 | MOVING | Tape currently moving |
| 4 | STREAMING | In streaming mode |
| 3 | AT_BOT | At beginning of tape |
| 2 | AT_EOT | At end of tape |
| 1 | CMD_ACTIVE | Command in progress |
| 0 | TAPE_MODE | Tape mode active (mirrors TDR[7]) |

#### TAPE_POSITION (Offset 0x34) - Read Only

| Bits | Name | Description |
|------|------|-------------|
| 31:21 | Reserved | Always 0 |
| 20:16 | TRACK | Current track number (0-27 for QIC-80) |
| 15:0 | SEGMENT | Current segment number (0-4095) |

#### TAPE_COMMAND (Offset 0x38) - Read/Write

| Bits | Name | Description |
|------|------|-------------|
| 31:6 | Reserved | Ignored on write, 0 on read |
| 5:0 | COMMAND | Last command code (R) / Direct command (W) |

**Direct command interface:**
- Write 1-48 to issue command without STEP pulses
- Useful for firmware-controlled tape operations
- Read returns last decoded command

#### TAPE_BLOCK_STATUS (Offset 0x3C) - Read Only

| Bits | Name | Description |
|------|------|-------------|
| 31 | FILE_MARK | File mark detected |
| 30 | BLOCK_SYNC | Block sync detected |
| 29 | SEG_COMPLETE | Segment (32 blocks) complete |
| 28:16 | Reserved | Always 0 |
| 15:11 | BLOCK_NUM | Block number in segment (0-31) |
| 10:9 | Reserved | Always 0 |
| 8:0 | BYTE_NUM | Byte position in block (0-511) |

### QIC Tape Data Format

Unlike floppy disks with sector structure, QIC tapes use continuous streaming:

| Component | Size | Description |
|-----------|------|-------------|
| Preamble | 10 bytes | 0x00 pattern for PLL sync |
| Sync Mark | 2 bytes | 0xA1, 0xA1 with missing clock (MFM 0x4489) |
| Header | 1 byte | Block type identifier |
| Data | 512 bytes | User data |
| ECC | 3 bytes | Error correction |

**Block types (header byte):**

| Value | Type | Description |
|-------|------|-------------|
| 0x00 | DATA | Normal data block |
| 0x0F | EOD | End of data marker |
| 0x1F | FILE_MARK | File mark (tape file separator) |
| 0xFF | BAD | Bad block marker |

**Segment structure:**
- 32 blocks per segment = 16 KB per segment
- Segments separated by inter-record gaps
- Track contains multiple segments

### Tape Mode Usage Example (C)

```c
#include "fdc_regs.h"

// Enable tape mode
void tape_mode_enable(uint8_t drive_select) {
    uint8_t tdr = 0x80 | (drive_select & 0x07);  // TAPE_EN=1, TAPE_SEL=drive
    outb(TDR_PORT, tdr);  // 0x3F3
}

// Send QIC-117 command via STEP pulses
void tape_send_command(uint8_t cmd) {
    for (int i = 0; i < cmd; i++) {
        // Generate STEP pulse via DOR motor bits toggle
        // or use direct command register
        delay_us(2500);  // Inter-pulse gap
    }
    delay_ms(100);  // Command timeout
}

// Initialize tape drive
void tape_init(void) {
    tape_mode_enable(1);           // Select tape drive 1
    tape_send_command(1);          // RESET
    tape_send_command(46);         // PHANTOM_SELECT
    tape_send_command(36);         // NEW_CARTRIDGE
    tape_send_command(8);          // SEEK_LOAD_POINT (rewind)
}

// Read status via direct register
uint8_t tape_get_status(void) {
    return AXI_READ(TAPE_STATUS) & 0xFF;
}

// Get current position
void tape_get_position(uint16_t *segment, uint8_t *track) {
    uint32_t pos = AXI_READ(TAPE_POSITION);
    *segment = pos & 0xFFFF;
    *track = (pos >> 16) & 0x1F;
}
```

### Automatic Drive Detection

FluxRipper can automatically detect QIC-117 tape drive presence, vendor, model, and capabilities. This eliminates the need for manual drive configuration.

#### TAPE_DETECT_CTRL (Offset 0x3C) - Read/Write

| Bits | Name | Description |
|------|------|-------------|
| 31:2 | Reserved | Ignored on write, 0 on read |
| 1 | ABORT | Write 1 to abort detection in progress |
| 0 | START | Write 1 to start auto-detection sequence |

**Operation:**
- Write 0x01 to start detection
- Write 0x02 to abort detection
- Read returns current detection status (same as TAPE_DETECT_STATUS)

**Detection Sequence:**
1. Send PHANTOM_SELECT (46 pulses)
2. Send REPORT_STATUS (4 pulses) - verify drive responds
3. Send REPORT_VENDOR (38 pulses) - get vendor ID
4. Send REPORT_MODEL (39 pulses) - get model ID
5. Send REPORT_DRIVE_CFG (41 pulses) - get capabilities
6. Decode results to identify drive type

#### TAPE_DETECT_STATUS (Offset 0x40) - Read Only

| Bits | Name | Description |
|------|------|-------------|
| 31:4 | Reserved | Always 0 |
| 3 | DETECTED | Drive detected and responding |
| 2 | ERROR | Detection sequence failed |
| 1 | COMPLETE | Detection sequence finished |
| 0 | IN_PROGRESS | Detection currently running |

**Status interpretation:**
- IN_PROGRESS=1: Detection running, wait for COMPLETE or ERROR
- COMPLETE=1, DETECTED=1: Drive found and identified
- COMPLETE=1, DETECTED=0: No drive present (timeout)
- ERROR=1: Detection aborted or communication failure

#### TAPE_VENDOR_MODEL (Offset 0x44) - Read Only

| Bits | Name | Description |
|------|------|-------------|
| 31:24 | CONFIG | Drive configuration byte |
| 23:16 | Reserved | Always 0 |
| 15:8 | MODEL_ID | Model identifier |
| 7:0 | VENDOR_ID | Vendor identifier |

**Known Vendor IDs:**

| ID | Vendor |
|----|--------|
| 0x01 | Colorado Memory Systems (CMS) |
| 0x02 | Conner/Archive/Seagate |
| 0x03 | Iomega |
| 0x04 | Mountain |
| 0x05 | Wangtek |
| 0x06 | Exabyte |
| 0x07 | AIWA |
| 0x08 | Sony |

**Model ID interpretation** is vendor-specific. See vendor documentation for details.

#### TAPE_DRIVE_INFO (Offset 0x48) - Read Only

| Bits | Name | Description |
|------|------|-------------|
| 31:18 | Reserved | Always 0 |
| 17:16 | RATES | Supported data rates bitmap |
| 15:12 | Reserved | Always 0 |
| 11:8 | TYPE | Drive type enumeration |
| 7:5 | Reserved | Always 0 |
| 4:0 | MAX_TRACKS | Maximum tracks supported |

**Data Rate Bitmap (RATES):**

| Value | Meaning |
|-------|---------|
| 0b01 | 250 Kbps (QIC-40) |
| 0b10 | 500 Kbps (QIC-80, QIC-3010) |
| 0b11 | 1 Mbps (QIC-3020) |

**Drive Type Enumeration (TYPE):**

| Value | Type | Tracks | Capacity |
|-------|------|--------|----------|
| 0 | Unknown | - | - |
| 1 | QIC-40 | 20 | 40 MB |
| 2 | QIC-80 | 28 | 80-170 MB |
| 3 | QIC-80 Wide | 28 | 120 MB |
| 4 | QIC-3010 | 40 | 340 MB |
| 5 | QIC-3020 | 40 | 680 MB |
| 6 | Travan TR-1 | 36 | 400 MB |
| 7 | Travan TR-2 | 36 | 800 MB |
| 8 | Travan TR-3 | 50 | 1.6 GB |
| 9 | Iomega Ditto | 28 | 120 MB |
| 10 | Iomega Ditto Max | 40 | 400 MB |

#### Detection Usage Example (C)

```c
#include "fdc_regs.h"

// Start drive detection
void tape_detect_drive(void) {
    // Must be in tape mode first
    tape_mode_enable(1);

    // Start detection
    AXI_WRITE(TAPE_DETECT_CTRL, 0x01);

    // Wait for completion
    uint32_t status;
    do {
        status = AXI_READ(TAPE_DETECT_STATUS);
    } while (status & 0x01);  // Wait while IN_PROGRESS

    if (status & 0x08) {  // DETECTED
        // Read detection results
        uint32_t vendor_model = AXI_READ(TAPE_VENDOR_MODEL);
        uint32_t drive_info = AXI_READ(TAPE_DRIVE_INFO);

        uint8_t vendor = vendor_model & 0xFF;
        uint8_t model = (vendor_model >> 8) & 0xFF;
        uint8_t drive_type = (drive_info >> 8) & 0x0F;
        uint8_t max_tracks = drive_info & 0x1F;

        printf("Vendor: 0x%02X, Model: 0x%02X\n", vendor, model);
        printf("Type: %d, Max tracks: %d\n", drive_type, max_tracks);
    } else {
        printf("No tape drive detected\n");
    }
}
```

### Limitations

- **Write support**: Currently read-only capture; write path not implemented
- **ECC**: ECC bytes are captured but not validated in hardware
- **Serpentine**: Multi-track serpentine recording supported via track FSM
- **Data rate**: Auto-detection identifies capabilities but does not change rate
- **Detection time**: Detection sequence takes ~2-3 seconds to complete
