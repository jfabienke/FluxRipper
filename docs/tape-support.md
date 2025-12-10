# FluxRipper QIC-117 Tape Support

## Overview

FluxRipper provides comprehensive support for QIC-117 floppy-interface tape drives, enabling preservation and recovery of data from quarter-inch cartridge (QIC) tape media. This document covers the supported tape standards, hardware interface, software protocol, and usage instructions.

## Supported Tape Standards

| Standard | Year | Tracks | Capacity | Data Rate | BPI | Media |
|----------|------|--------|----------|-----------|-----|-------|
| QIC-40 | 1987 | 20 | 40 MB | 250 Kbps | 10,000 | DC2000 |
| QIC-80 | 1989 | 28 | 80-120 MB | 500 Kbps | 12,500 | DC2080 |
| QIC-80 Wide | 1991 | 28 | 120-170 MB | 500 Kbps | 14,700 | DC2120 |
| QIC-3010 | 1992 | 40 | 340 MB | 500 Kbps | 22,125 | DC3010 |
| QIC-3020 | 1993 | 40 | 680 MB | 1 Mbps | 22,125 | DC3020 |
| Travan TR-1 | 1995 | 36 | 400 MB | 500 Kbps | - | TR-1 |
| Travan TR-2 | 1996 | 36 | 800 MB | 500 Kbps | - | TR-2 |
| Travan TR-3 | 1997 | 50 | 1.6 GB | 1 Mbps | - | TR-3 |

### Compatible Drive Manufacturers

- **Colorado Memory Systems (CMS)**: Jumbo, Trakker series
- **Conner/Archive/Seagate**: TapeStor series
- **Iomega**: Ditto, Ditto Max, Ditto Easy
- **Mountain**: FileSafe series
- **Wangtek**: Various OEM models
- **Exabyte**: Travan drives
- **AIWA/Sony**: OEM drives

---

## Hardware Architecture

### Signal Reinterpretation

QIC-117 drives connect to a standard floppy controller but reinterpret the signals:

| Signal | Floppy Use | QIC-117 Tape Use |
|--------|------------|------------------|
| STEP | Head step pulses | Command bits (pulse count = command code) |
| DIR | Head direction | Unused (tape handles direction internally) |
| TRK0 | Track 0 sensor | Status bit stream output (time-encoded) |
| INDEX | Index hole | Segment boundary marker |
| RDATA | Disk read data | Tape MFM data stream (continuous) |
| WDATA | Disk write data | Tape MFM write stream (continuous) |
| MOTOR | Motor enable | Tape motor enable |
| DS0-DS1 | Drive select | Tape drive select |

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FluxRipper QIC-117 Tape Subsystem                       │
│                                                                             │
│  ┌──────────────────┐                      ┌──────────────────────────────┐ │
│  │   FDC Registers  │                      │     QIC-117 Controller       │ │
│  │                  │                      │                              │ │
│  │  TDR[7]=1       ─┼──── tape_mode_en ───►│  ┌────────────────────────┐  │ │
│  │  (tape mode)     │                      │  │  STEP Pulse Counter    │  │ │
│  │                  │                      │  │  (count 1-48 pulses)   │  │ │
│  │  TDR[2:0]       ─┼──── tape_select ────►│  └───────────┬────────────┘  │ │
│  │  (drive select)  │                      │              │               │ │
│  └──────────────────┘                      │  ┌───────────▼────────────┐  │ │
│                                            │  │   Command Decoder      │  │ │
│  ┌──────────────────┐                      │  │   48 QIC-117 commands  │  │ │
│  │  Drive Interface │                      │  └───────────┬────────────┘  │ │
│  │                  │                      │              │               │ │
│  │  STEP pulses    ─┼──────────────────────┼──────────────┘               │ │
│  │                  │                      │                              │ │
│  │  TRK0 input    ◄─┼──────────────────────┼── Status Encoder            │ │
│  │                  │                      │   (time-encoded bits)       │ │
│  │  MFM data      ◄─┼──────────────────────┼── Data Streamer             │ │
│  │                  │                      │   (block/segment detect)    │ │
│  └──────────────────┘                      │                              │ │
│                                            │  ┌────────────────────────┐  │ │
│  ┌──────────────────┐                      │  │   Drive Detection      │  │ │
│  │  AXI Registers   │◄─────────────────────┼──│   (auto-identify)      │  │ │
│  │  0x30-0x48       │                      │  └────────────────────────┘  │ │
│  └──────────────────┘                      └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### RTL Module Hierarchy

```
qic117_controller.v          # Top-level tape controller
├── qic117_step_counter.v    # STEP pulse counting with timeout
├── qic117_cmd_decoder.v     # Command code decoding (1-48)
├── qic117_status_encoder.v  # TRK0 status bit encoding
├── qic117_tape_fsm.v        # Position tracking state machine
├── qic117_data_streamer.v   # Block boundary detection
├── qic117_trk0_decoder.v    # TRK0 response capture
└── qic117_drive_detect.v    # Automatic drive detection
```

---

## QIC-117 Command Protocol

### Command Transmission

Commands are sent by issuing STEP pulses. The number of pulses (1-48) determines the command code:

1. Assert STEP low for minimum 1µs
2. Deassert STEP high for minimum 3ms (inter-pulse gap)
3. Repeat for command code value
4. After 100ms timeout with no pulses, command is executed

### Command Reference

#### Reset Commands (1-3)

| Code | Command | Description |
|------|---------|-------------|
| 1 | SOFT_RESET_1 | Soft reset, maintain tape position |
| 2 | SOFT_RESET_2 | Soft reset variant |
| 3 | SOFT_RESET_3 | Soft reset variant |

#### Status Commands (4-5)

| Code | Command | Description |
|------|---------|-------------|
| 4 | REPORT_STATUS | Report 8-bit status word via TRK0 |
| 5 | REPORT_NEXT_BIT | Report next status bit via TRK0 |

#### Motion Control (6-13)

| Code | Command | Description |
|------|---------|-------------|
| 6 | PAUSE | Stop tape motion, maintain position |
| 7 | MICRO_STEP_PAUSE | Micro-step pause for precise positioning |
| 8 | SEEK_LOAD_POINT | Seek to beginning of tape (BOT) |
| 9 | SEEK_END_OF_DATA | Seek to end of tape (EOT) |
| 10 | SKIP_REVERSE_SEGMENT | Skip one segment backward |
| 11 | SKIP_REVERSE_FILE | Skip to previous file mark |
| 12 | SKIP_FORWARD_SEGMENT | Skip one segment forward |
| 13 | SKIP_FORWARD_FILE | Skip to next file mark |

#### Streaming Commands (21-23, 30-31)

| Code | Command | Description |
|------|---------|-------------|
| 21 | LOGICAL_FORWARD | Enter logical forward streaming mode |
| 22 | LOGICAL_REVERSE | Enter logical reverse streaming mode |
| 23 | STOP_TAPE | Stop tape motion |
| 30 | PHYSICAL_FORWARD | Physical forward motion |
| 31 | PHYSICAL_REVERSE | Physical reverse motion |

#### Drive Control (36, 45-47)

| Code | Command | Description |
|------|---------|-------------|
| 36 | NEW_CARTRIDGE | Signal new cartridge inserted |
| 45 | SELECT_RATE | Select data rate |
| 46 | PHANTOM_SELECT | Enable drive (phantom select) |
| 47 | PHANTOM_DESELECT | Disable drive |

#### Diagnostic/Query Commands (38-44)

| Code | Command | Description |
|------|---------|-------------|
| 38 | REPORT_VENDOR | Report vendor ID via TRK0 |
| 39 | REPORT_MODEL | Report model ID via TRK0 |
| 40 | REPORT_ROM_VERSION | Report firmware version via TRK0 |
| 41 | REPORT_DRIVE_CONFIG | Report drive configuration via TRK0 |
| 42 | REPORT_TAPE_STATUS | Report tape-specific status |
| 43 | SKIP_EXTENDED_REV | Extended reverse skip |
| 44 | SKIP_EXTENDED_FWD | Extended forward skip |

---

## TRK0 Status Encoding

### Bit Timing

Status bits are encoded as pulse widths on the TRK0 signal:

| Bit Value | TRK0 Low Duration | Inter-bit Gap |
|-----------|-------------------|---------------|
| 0 | 500 µs (±30%) | 1000 µs |
| 1 | 1500 µs (±30%) | 1000 µs |

### Timing Diagram

```
TRK0 ─────┐     ┌─────────┐     ┌───────────────┐     ┌─────
          │     │         │     │               │     │
          └─────┘         └─────┘               └─────┘
          |─────|         |─────|               |─────────|
           500µs           1ms                    1500µs
          (bit=0)         (gap)                  (bit=1)
```

### Status Byte Format

Bits are transmitted MSB first:

| Bit | Name | Description |
|-----|------|-------------|
| 7 | READY | Drive ready for commands |
| 6 | ERROR | Error condition detected |
| 5 | CARTRIDGE | Cartridge present in drive |
| 4 | WRITE_PROT | Write protection enabled |
| 3 | NEW_CART | New cartridge detected (cleared by cmd 36) |
| 2 | AT_BOT | Tape at beginning of tape |
| 1 | AT_EOT | Tape at end of tape |
| 0 | Reserved | Always 0 |

---

## Tape Data Format

### Physical Structure

QIC tapes use serpentine recording across multiple tracks:

```
Track Layout (QIC-80, 28 tracks):
┌────────────────────────────────────────────────────────────┐
│ Track 0  ──────────────────────────────────────────────►   │
│ Track 1  ◄──────────────────────────────────────────────   │
│ Track 2  ──────────────────────────────────────────────►   │
│ ...                                                        │
│ Track 27 ◄──────────────────────────────────────────────   │
└────────────────────────────────────────────────────────────┘
      BOT (Beginning of Tape)              EOT (End of Tape)
```

### Block Format

Each block contains 512 bytes of user data with MFM encoding:

| Component | Size | Description |
|-----------|------|-------------|
| Preamble | 10 bytes | 0x00 pattern for PLL synchronization |
| Sync Mark | 2 bytes | 0xA1, 0xA1 with missing clock (MFM 0x4489) |
| Header | 1 byte | Block type identifier |
| Data | 512 bytes | User data |
| ECC | 3 bytes | Error correction code |
| **Total** | **528 bytes** | |

### Block Types

| Header Value | Type | Description |
|--------------|------|-------------|
| 0x00 | DATA | Normal data block |
| 0x0F | EOD | End of data marker |
| 0x1F | FILE_MARK | File mark (tape file separator) |
| 0xFF | BAD | Bad block marker |

### Segment Structure

- 32 blocks per segment = 16 KB per segment
- Segments separated by inter-record gaps
- INDEX pulse generated at segment boundaries

---

## Automatic Drive Detection

FluxRipper can automatically detect QIC-117 tape drive presence, vendor, model, and capabilities.

### Detection Sequence

1. **PHANTOM_SELECT** (46 pulses) - Enable drive
2. **REPORT_STATUS** (4 pulses) - Verify drive responds
3. **REPORT_VENDOR** (38 pulses) - Get vendor ID
4. **REPORT_MODEL** (39 pulses) - Get model ID
5. **REPORT_DRIVE_CFG** (41 pulses) - Get capabilities
6. **DECODE** - Identify drive type from responses

### Known Vendor IDs

| ID | Vendor | Common Models |
|----|--------|---------------|
| 0x01 | Colorado Memory Systems | Jumbo 120, Jumbo 250, Trakker |
| 0x02 | Conner/Archive/Seagate | TapeStor 420, 850, 3200 |
| 0x03 | Iomega | Ditto 2GB, Ditto Max, Ditto Easy |
| 0x04 | Mountain | FileSafe series |
| 0x05 | Wangtek | Various OEM models |
| 0x06 | Exabyte | Eagle series (Travan) |
| 0x07 | AIWA | OEM tape drives |
| 0x08 | Sony | OEM tape drives |

### Drive Type Identification

| Type | Standard | Tracks | Capacity | Data Rate |
|------|----------|--------|----------|-----------|
| 1 | QIC-40 | 20 | 40 MB | 250 Kbps |
| 2 | QIC-80 | 28 | 80-120 MB | 500 Kbps |
| 3 | QIC-80 Wide | 28 | 120-170 MB | 500 Kbps |
| 4 | QIC-3010 | 40 | 340 MB | 500 Kbps |
| 5 | QIC-3020 | 40 | 680 MB | 1 Mbps |
| 6 | Travan TR-1 | 36 | 400 MB | 500 Kbps |
| 7 | Travan TR-2 | 36 | 800 MB | 500 Kbps |
| 8 | Travan TR-3 | 50 | 1.6 GB | 1 Mbps |
| 9 | Iomega Ditto | 28 | 120 MB | 500 Kbps |
| 10 | Iomega Ditto Max | 40 | 400 MB | 1 Mbps |

---

## Register Interface

### TDR Register (I/O 0x3F3)

Controls tape mode enable and drive selection:

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 7 | TAPE_EN | R/W | Tape mode enable (1=tape, 0=floppy) |
| 6:3 | Reserved | R | Always 0 |
| 2:0 | TAPE_SEL | R/W | Tape drive select (1-3, 0=none) |

### Extended AXI Registers

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x30 | TAPE_STATUS | R | Tape status and FSM state |
| 0x34 | TAPE_POSITION | R | Segment and track position |
| 0x38 | TAPE_COMMAND | R/W | Direct command interface |
| 0x3C | TAPE_DETECT_CTRL | R/W | Detection control (start/abort) |
| 0x40 | TAPE_DETECT_STATUS | R | Detection status flags |
| 0x44 | TAPE_VENDOR_MODEL | R | Detected vendor and model IDs |
| 0x48 | TAPE_DRIVE_INFO | R | Drive type, tracks, data rates |

### TAPE_STATUS (0x30)

| Bits | Name | Description |
|------|------|-------------|
| 29:24 | LAST_CMD | Last decoded command code |
| 23 | ERROR | Error condition |
| 22 | READY | Drive ready |
| 21 | CMD_ACTIVE | Command in progress |
| 15:8 | STATUS_BYTE | Raw status byte from drive |

### TAPE_POSITION (0x34)

| Bits | Name | Description |
|------|------|-------------|
| 20:16 | TRACK | Current track number (0-49) |
| 15:0 | SEGMENT | Current segment number (0-4095) |

### TAPE_DETECT_STATUS (0x40)

| Bits | Name | Description |
|------|------|-------------|
| 3 | DETECTED | Drive detected and responding |
| 2 | ERROR | Detection sequence failed |
| 1 | COMPLETE | Detection sequence finished |
| 0 | IN_PROGRESS | Detection currently running |

### TAPE_VENDOR_MODEL (0x44)

| Bits | Name | Description |
|------|------|-------------|
| 31:24 | CONFIG | Drive configuration byte |
| 15:8 | MODEL_ID | Model identifier |
| 7:0 | VENDOR_ID | Vendor identifier |

### TAPE_DRIVE_INFO (0x48)

| Bits | Name | Description |
|------|------|-------------|
| 17:16 | RATES | Supported data rates (bitmap) |
| 11:8 | TYPE | Drive type enumeration |
| 4:0 | MAX_TRACKS | Maximum tracks supported |

---

## Usage Examples

### Basic Initialization (C)

```c
#include "fluxripper.h"

void tape_init(void) {
    // Enable tape mode, select drive 1
    outb(TDR_PORT, 0x81);  // TAPE_EN=1, TAPE_SEL=1

    // Start auto-detection
    AXI_WRITE(TAPE_DETECT_CTRL, 0x01);

    // Wait for detection to complete
    while (AXI_READ(TAPE_DETECT_STATUS) & 0x01);

    // Check if drive detected
    uint32_t status = AXI_READ(TAPE_DETECT_STATUS);
    if (status & 0x08) {  // DETECTED bit
        uint32_t info = AXI_READ(TAPE_DRIVE_INFO);
        printf("Drive type: %d\n", (info >> 8) & 0x0F);
        printf("Max tracks: %d\n", info & 0x1F);
    } else {
        printf("No tape drive detected\n");
    }
}
```

### Send QIC-117 Command

```c
// Send command via direct register
void tape_command(uint8_t cmd) {
    AXI_WRITE(TAPE_COMMAND, cmd);

    // Wait for command to complete
    while (AXI_READ(TAPE_STATUS) & (1 << 21));  // CMD_ACTIVE
}

// Rewind tape to BOT
void tape_rewind(void) {
    tape_command(46);  // PHANTOM_SELECT
    tape_command(8);   // SEEK_LOAD_POINT

    // Wait for seek to complete
    uint32_t status;
    do {
        status = AXI_READ(TAPE_STATUS);
    } while (!(status & 0x04));  // Wait for AT_BOT
}
```

### Read Tape Position

```c
void tape_get_position(uint16_t *segment, uint8_t *track) {
    uint32_t pos = AXI_READ(TAPE_POSITION);
    *segment = pos & 0xFFFF;
    *track = (pos >> 16) & 0x1F;
}
```

### Capture Tape Data Stream

```c
void tape_capture_track(void) {
    // Enable flux capture
    AXI_WRITE(FLUX_CTRL, 0x01);

    // Start streaming forward
    tape_command(46);  // PHANTOM_SELECT
    tape_command(21);  // LOGICAL_FORWARD

    // Capture until segment complete or error
    while (!(AXI_READ(TAPE_STATUS) & 0x800000)) {  // Not ERROR
        // Read flux data from stream...
    }

    // Stop tape
    tape_command(6);  // PAUSE

    // Disable flux capture
    AXI_WRITE(FLUX_CTRL, 0x00);
}
```

---

## Troubleshooting

### Drive Not Detected

1. **Check connections**: Ensure floppy cable is properly connected
2. **Power**: Verify drive has both 5V and 12V power
3. **Drive select**: Try different TAPE_SEL values (1, 2, 3)
4. **Termination**: QIC drives typically have internal termination
5. **Cable orientation**: Pin 1 alignment is critical

### Status Errors

| Error | Possible Cause | Solution |
|-------|----------------|----------|
| No TRK0 response | Drive not selected | Send PHANTOM_SELECT first |
| Timeout | No cartridge | Insert tape cartridge |
| Invalid command | Wrong pulse count | Check command code |
| Write protected | Hardware switch | Check media write protect |

### Data Capture Issues

| Issue | Possible Cause | Solution |
|-------|----------------|----------|
| No sync detection | Wrong data rate | Match rate to drive type |
| Frequent errors | Dirty heads | Clean drive heads |
| Missing segments | Worn media | Try multiple passes |
| Garbled data | Tape stretched | Use different tape |

### Common Data Rates

| Drive Type | Set DSR to |
|------------|------------|
| QIC-40 | 250 Kbps (0x02) |
| QIC-80 | 500 Kbps (0x00) |
| QIC-3010 | 500 Kbps (0x00) |
| QIC-3020 | 1 Mbps (0x03) |

---

## Limitations

- **Write support**: Currently read-only; write path not implemented
- **ECC validation**: ECC bytes are captured but not decoded in hardware
- **Real-time streaming**: Full-speed streaming requires adequate host bandwidth
- **Travan NS**: Network-specific Travan formats not supported
- **DAT/DLT**: Only QIC-117 floppy-interface drives; not SCSI tape

---

## References

- QIC-117 Revision G Specification
- QIC-80 Format Specification
- QIC-3010/3020 Format Specification
- Colorado Memory Systems Technical Reference
- Archive Corporation Technical Manual

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-10 | Initial release with auto-detection support |
