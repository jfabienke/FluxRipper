# FluxRipper Option ROM Memory Maps

## Side-by-Side Comparison: 16KB FDD vs HDD BIOS

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    16KB OPTION ROM MEMORY MAP COMPARISON                         │
├──────────────┬─────────────────────────────┬─────────────────────────────────────┤
│    OFFSET    │      FDD BIOS (16KB)        │         HDD BIOS (16KB)             │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0000-0x0002│ ROM Header (55 AA 20)       │ ROM Header (55 AA 20)               │
│              │ Signature + 32 blocks       │ Signature + 32 blocks               │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0003-0x0005│ JMP rom_init                │ JMP rom_init                        │
│              │ Entry point                 │ Entry point                         │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0006-0x0019│ Reserved (alignment)        │ Reserved (alignment)                │
│              │ 20 bytes padding            │ 20 bytes padding                    │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x001A-0x003A│ PnP Header (32 bytes)       │ PnP Header (32 bytes)               │
│              │ Device ID: FLX0200          │ Device ID: FLX0100                  │
│              │ Type: Mass Storage/Floppy   │ Type: Mass Storage/HDD              │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x003B-0x0060│ PnP Strings + BEV           │ PnP Strings + BEV                   │
│              │ "FluxRipper FDD BIOS"       │ "FluxRipper HDD BIOS"               │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│              │                             │                                     │
│   CODE       │ ═══════════════════════════ │ ═══════════════════════════════════ │
│   SECTION    │                             │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0061-0x0200│ rom_init (~400 bytes)       │ rom_init (~100 bytes)               │
│              │ FluxRipper detection        │ FluxRipper detection                │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0200-0x0300│ util.asm (~256 bytes)       │ util.asm (~1200 bytes)              │
│              │ print, delay, status        │ print, delay, detect                │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0300-0x0400│ discovery.asm (~256 bytes)  │ discovery.asm (in HDD ~0x2800)      │
│              │ FPGA profile reading        │ WD personality detection            │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0400-0x0600│ detect.asm (~512 bytes)     │ INT 13h handler (~3000 bytes)       │
│              │ Drive type mapping          │ Main dispatcher (0x0498)            │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0600-0x0800│ init.asm (~512 bytes)       │ func_basic.asm (~4000 bytes)        │
│              │ FDC init, INT 13h hook      │ Basic INT 13h (00h-08h)             │
│              │ Drive mapping, BDA update   │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0800-0x0A00│ fdc_io.asm (~512 bytes)     │ func_extended.asm (~3000 bytes)     │
│              │ FDC command interface       │ Extended INT 13h (09h-15h)          │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0A00-0x0C00│ int13h.asm (~512 bytes)     │ func_lba.asm (~3000 bytes)          │
│              │ INT 13h dispatcher          │ LBA extensions (41h-48h)            │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0C00-0x0E00│ read_write.asm (~512 bytes) │ discovery.asm (~4000 bytes)         │
│              │ Sector I/O, DMA setup       │ FPGA drive discovery                │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0E00-0x0F00│ format.asm (~256 bytes)     │ video.asm (~1500 bytes)             │
│              │ Track formatting            │ Diagnostics display                 │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0F00-0x0F80│ strings.asm (~128 bytes)    │ monitor.asm (~600 bytes)            │
│              │ Message strings             │ Real-time monitor                   │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x0F80-0x1500│ diag.asm (~1408 bytes)      │ (continued code)                    │
│              │ F3 diagnostics menu         │                                     │
│              │ Drive swap, instrumentation │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│              │                             │                                     │
│   DATA       │ ═══════════════════════════ │ ═══════════════════════════════════ │
│   SECTION    │                             │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x1500      │ old_int13h (4 bytes)        │ old_int13h (4 bytes)                │
│              │ old_int19 (4 bytes)         │ old_int19 (4 bytes)                 │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x1508      │ drive_profiles[4] (16 bytes)│ drive0_params (8 bytes)             │
│              │ FPGA auto-detected          │ drive1_params (8 bytes)             │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x1518      │ drive_types[4] (4 bytes)    │ fdpt_drive0 (16 bytes)              │
│              │ BIOS type codes             │ Fixed Disk Parameter Table          │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x151C      │ drive_params[4] (16 bytes)  │ fdpt_drive1 (16 bytes)              │
│              │ Geometry (C/H/S)            │ Fixed Disk Parameter Table          │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x152C      │ num_drives (1 byte)         │ num_drives (1 byte)                 │
│              │ current_fdc (2 bytes)       │ current_base (2 bytes)              │
│              │ motor_status (1 byte)       │ personality (1 byte)                │
│              │ secondary_fdc_present (1)   │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x1530      │ drive_map[4] (4 bytes)      │ (N/A - no drive remapping)          │
│              │ phys_to_logical[4] (4 bytes)│                                     │
│              │ mapped_drive_count (1 byte) │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│              │                             │                                     │
│   PADDING    │ ═══════════════════════════ │ ═══════════════════════════════════ │
│              │                             │                                     │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ ~0x1540-     │ 0xFF padding                │ 0xFF padding                        │
│ 0x3FFE       │ ~10,942 bytes (67%)         │ ~3,379 bytes (21%)                  │
├──────────────┼─────────────────────────────┼─────────────────────────────────────┤
│ 0x3FFF       │ Checksum byte               │ Checksum byte                       │
│              │ (makes sum = 0)             │ (makes sum = 0)                     │
└──────────────┴─────────────────────────────┴─────────────────────────────────────┘
```

---

## Size Comparison Summary

| Section | FDD BIOS | HDD BIOS | Notes |
|---------|----------|----------|-------|
| ROM Header | 3 bytes | 3 bytes | Identical structure |
| Entry JMP | 3 bytes | 3 bytes | Same pattern |
| PnP Header | 32 bytes | 32 bytes | Different Device IDs |
| PnP Strings | ~40 bytes | ~40 bytes | Different names |
| **Code Total** | ~5,376 bytes | ~12,500 bytes | HDD has more INT 13h functions |
| **Data Total** | ~64 bytes | ~60 bytes | Similar state storage |
| **Padding** | ~10,942 bytes | ~3,379 bytes | FDD has more room |
| Checksum | 1 byte | 1 byte | Standard ISA ROM |
| **TOTAL** | 16,384 bytes | 16,384 bytes | |

---

## Key Architectural Differences

### Controller Interface

| Aspect | FDD BIOS | HDD BIOS |
|--------|----------|----------|
| Controller Type | 82077AA FDC | WD1003/WD1006/WD1007 |
| I/O Base (Primary) | 0x3F0 | 0x1F0 (AT) / 0x320 (XT) |
| I/O Base (Secondary) | 0x370 | 0x170 (AT only) |
| Max Drives | 4 (quad-floppy) | 2 |
| DMA | Channel 2 | Channel 3 (XT) / PIO (AT) |
| IRQ | IRQ 6 | IRQ 14 (AT) / IRQ 5 (XT) |

#### HDD DMA Notes

| System | Transfer Mode | Notes |
|--------|---------------|-------|
| PC/XT (8088) | DMA Channel 3 | Required for stock XT BIOS compatibility |
| PC/AT (286+) | PIO (REP INSW) | Standard AT IDE behavior, faster than DMA |

**XT DMA Considerations:**
- Stock XT BIOS expects DMA channel 3 for hard disk transfers
- Without DMA support, FluxRipper requires the Option ROM to function on XT
- With DMA support, FluxRipper works even if Option ROM fails to load
- DMA also required for XT diagnostic software and non-DOS operating systems

### INT 13h Functions Supported

| Function | FDD BIOS | HDD BIOS | Description |
|----------|----------|----------|-------------|
| 00h | ✓ | ✓ | Reset disk system |
| 01h | ✓ | ✓ | Get status of last operation |
| 02h | ✓ | ✓ | Read sectors |
| 03h | ✓ | ✓ | Write sectors |
| 04h | ✓ | ✓ | Verify sectors |
| 05h | ✓ | ✓ | Format track |
| 08h | ✓ | ✓ | Get drive parameters |
| 09h-0Fh | - | ✓ | Extended functions |
| 15h | ✓ | ✓ | Get disk type |
| 16h | ✓ | - | Disk change status |
| 41h-48h | - | ✓ | LBA extensions |

### FPGA-Specific Features

| Feature | FDD BIOS | HDD BIOS |
|---------|----------|----------|
| Auto-Detection | Drive profiles | WD personality |
| Instrumentation | Signal quality, flux timing | Command timing |
| Discovery Registers | 0x68, 0x74 per FDC | Custom |
| Encoding Support | MFM, FM, GCR, M2FM | MFM, RLL |

---

## PnP Device IDs

| BIOS | Device ID | Meaning |
|------|-----------|---------|
| FDD | FLX0200 | FluxRipper FDD Controller |
| HDD | FLX0100 | FluxRipper HDD Controller |

---

## ROM Header Structure (Both ROMs)

```
Offset  Size  Content         Description
------  ----  --------------  ----------------------------------
0x0000  1     0x55            ROM signature byte 1
0x0001  1     0xAA            ROM signature byte 2
0x0002  1     0x20 (32)       ROM size in 512-byte blocks
0x0003  2-3   JMP rom_init    Entry point jump instruction
```

---

## PnP Header Structure (Both ROMs)

Located at offset 0x001A (aligned to 16-byte boundary):

```
Offset  Size  Field                   FDD Value        HDD Value
------  ----  ----------------------  ---------------  ---------------
0x001A  4     Signature               '$PnP'           '$PnP'
0x001E  1     Revision                0x01             0x01
0x001F  1     Header Length / 16      0x02             0x02
0x0020  2     Next Header Offset      0x0000           0x0000
0x0022  1     Reserved                0x00             0x00
0x0023  1     Checksum                (calculated)     (calculated)
0x0024  4     Device ID               0x464C5802       0x464C5801
0x0028  2     Manufacturer String     (offset)         (offset)
0x002A  2     Product Name            (offset)         (offset)
0x002C  1     Device Type             0x01 (Storage)   0x03 (Storage)
0x002D  1     Device Sub-Type         0x02 (Floppy)    0x00 (HDD)
0x002E  1     Device Interface        0x00             0x00
0x002F  2     Device Indicators       0x0000           0x0000
0x0031  2     Boot Connection Vector  0x0000           0x0000
0x0033  2     Bootstrap Entry Vector  (offset)         (offset)
0x0035  2     Reserved                0x0000           0x0000
0x0037  2     Static Resource Info    0x0000           0x0000
```

---

## Data Section Details

### FDD BIOS Data Variables

| Offset | Size | Name | Description |
|--------|------|------|-------------|
| ~0x1500 | 4 | old_int13h | Saved INT 13h vector (offset:segment) |
| ~0x1504 | 4 | old_int19 | Saved INT 19h vector (PnP boot) |
| ~0x1508 | 16 | drive_profiles[4] | FPGA auto-detected profiles (4 bytes each) |
| ~0x1518 | 4 | drive_types[4] | BIOS type codes (1 byte each) |
| ~0x151C | 16 | drive_params[4] | Geometry: cylinders(2), heads(1), spt(1) |
| ~0x152C | 1 | num_drives | Number of detected drives (0-4) |
| ~0x152D | 2 | current_fdc | Active FDC I/O base (0x3F0 or 0x370) |
| ~0x152F | 1 | motor_status | Motor on/off bits for each drive |
| ~0x1530 | 1 | secondary_fdc_present | Secondary FDC detected flag |
| ~0x1531 | 4 | drive_map[4] | Logical to physical drive mapping |
| ~0x1535 | 4 | phys_to_logical[4] | Physical to logical drive mapping |
| ~0x1539 | 1 | mapped_drive_count | Number of mapped DOS drives |

### HDD BIOS Data Variables

| Offset | Size | Name | Description |
|--------|------|------|-------------|
| ~0x3190 | 4 | old_int13h | Saved INT 13h vector (offset:segment) |
| ~0x3194 | 4 | old_int19 | Saved INT 19h vector (PnP boot) |
| ~0x3198 | 8 | drive0_params | Drive 0 geometry structure |
| ~0x31A0 | 8 | drive1_params | Drive 1 geometry structure |
| ~0x31A8 | 16 | fdpt_drive0 | Fixed Disk Parameter Table (INT 41h) |
| ~0x31B8 | 16 | fdpt_drive1 | Fixed Disk Parameter Table (INT 46h) |
| ~0x31C8 | 1 | num_drives | Number of detected drives (0-2) |
| ~0x31C9 | 2 | current_base | Active WD I/O base (0x1F0 or 0x170) |
| ~0x31CB | 1 | personality | Detected WD personality code |

---

## Unused Space Available

| BIOS | Unused Bytes | Percentage | Notes |
|------|--------------|------------|-------|
| FDD | ~10,942 | 67% | Significant room for expansion |
| HDD | ~3,379 | 21% | Tighter fit due to LBA extensions |

---

## 8KB vs 16KB Build Differences

### FDD BIOS

| Feature | 8KB Build | 16KB Build |
|---------|-----------|------------|
| PnP Header | No | Yes |
| F3 Diagnostics | No | Yes |
| Instrumentation Display | No | Yes |
| Drive Swap Menu | No | Yes |
| Extended Formats | No | Yes (8", GCR, M2FM) |

### HDD BIOS

| Feature | 8KB Build | 16KB Build |
|---------|-----------|------------|
| PnP Header | No | Yes |
| LBA Extensions (41h-48h) | No | Yes |
| Extended INT 13h (09h-15h) | No | Yes |
| Diagnostics Menu | No | Yes |
| Setup Utility | No | Yes |
| Real-time Monitor | No | Yes |

---

## Checksum Calculation

Both ROMs use the standard ISA Option ROM checksum:

1. Sum all bytes from 0x0000 to 0x3FFE
2. Calculate: `checksum = (256 - (sum & 0xFF)) & 0xFF`
3. Store result at 0x3FFF

The `romsum.py` tool handles this automatically during build.

---

## Source File Organization

### FDD BIOS (`bios/fdd/src/`)

```
entry.asm           Main entry, ROM header, data section
├── config.inc      Build configuration
├── fdc_regs.inc    FDC register definitions
├── profile.inc     Drive profile definitions
├── int13h.inc      INT 13h constants
├── util.asm        Utility functions
├── discovery.asm   FPGA profile reading
├── detect.asm      Drive type mapping
├── init.asm        FDC initialization
├── fdc_io.asm      FDC command interface
├── int13h.asm      INT 13h dispatcher
├── read_write.asm  Sector I/O operations
├── format.asm      Track formatting
├── strings.asm     Message strings
└── diag.asm        Diagnostics (16KB only)
```

### HDD BIOS (`bios/hdd/src/`)

```
entry.asm           Main entry, ROM header, data section
├── config.inc      Build configuration
├── wd_regs.inc     WD controller definitions
├── bda.inc         BIOS Data Area addresses
├── util.asm        Utility functions
├── discovery.asm   FPGA personality detection
├── init.asm        Controller initialization
├── int13h.asm      INT 13h dispatcher
├── func_basic.asm  Basic INT 13h (00h-08h)
├── func_extended.asm Extended INT 13h (09h-15h)
├── func_lba.asm    LBA extensions (41h-48h)
├── strings.asm     Message strings
├── video.asm       Display functions
├── keyboard.asm    Input handling
├── monitor.asm     Real-time monitor
├── diag.asm        Diagnostics menu
└── setup.asm       Setup utility
```

---

*Document generated: 2025-12-08*
*FluxRipper Project - SPDX-License-Identifier: BSD-3-Clause*
