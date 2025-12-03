# FluxRipper Drive Support Reference

*Updated: 2025-12-03 15:45*

This document details the physical floppy drive types supported by FluxRipper, including interface specifications, track densities, data rates, and compatibility notes.

---

## Table of Contents

1. [Quick Reference Tables](#quick-reference-tables)
2. [Architecture Overview](#architecture-overview)
3. [Supported Drive Families](#supported-drive-families)
4. [Track Density (TPI) Support](#track-density-tpi-support)
5. [Data Rate Support](#data-rate-support)
6. [Encoding Format Support](#encoding-format-support)
7. [Physical Interface Reference](#physical-interface-reference)
8. [Drive Compatibility Matrix](#drive-compatibility-matrix)
9. [Platform-Specific Notes](#platform-specific-notes)
10. [Adapter Requirements](#adapter-requirements)

---

## Quick Reference Tables

### All Supported Drive Types

| Form Factor | Format | Capacity | Tracks | TPI | Data Rate | RPM | Status |
|-------------|--------|----------|--------|-----|-----------|-----|--------|
| **3.5"** | DD | 720 KB | 80 | 135 | 250 Kbps | 300 | ✅ Native |
| **3.5"** | HD | 1.44 MB | 80 | 135 | 500 Kbps | 300 | ✅ Native |
| **3.5"** | ED | 2.88 MB | 80 | 135 | 1 Mbps | 300 | ✅ Native |
| **3.5" Slimline** | DD/HD | 720K-1.44M | 80 | 135 | 250-500K | 300 | ✅ Adapter |
| **5.25"** | SSDD 40T | 180 KB | 40 | 48 | 250 Kbps | 300 | ✅ Native |
| **5.25"** | DSDD 40T | 360 KB | 40 | 48 | 250 Kbps | 300 | ✅ Native |
| **5.25"** | SSQD 80T | 400 KB | 80 | 96 | 250 Kbps | 300 | ✅ Native |
| **5.25"** | DSQD 80T | 720 KB | 80 | 96 | 250 Kbps | 300 | ✅ Native |
| **5.25"** | DSHD 80T | 1.2 MB | 80 | 96 | 500 Kbps | 360 | ✅ Full (+TG43) |
| **8"** | SSSD | 250 KB | 77 | 100 | 250 Kbps | 360 | ✅ Full (+HEAD_LOAD) |
| **8"** | SSDD | 500 KB | 77 | 100 | 500 Kbps | 360 | ✅ Full (+HEAD_LOAD) |
| **8"** | DSDD | 1.2 MB | 77 | 100 | 500 Kbps | 360 | ✅ Full (+HEAD_LOAD) |
| **3" CF2** | SS | 180 KB | 40 | 96 | 250 Kbps | 300 | ✅ Adapter |
| **3" CF2** | DS | 720 KB | 80 | 96 | 250 Kbps | 300 | ✅ Adapter |

### Hard-Sectored Drives

| System | Form Factor | Tracks | Sectors/Track | Encoding | Status |
|--------|-------------|--------|---------------|----------|--------|
| NorthStar | 5.25" | 35 | 10 | FM | ✅ Full (+SECTOR) |
| Vector Graphics | 5.25"/8" | 35-77 | 16 | MFM | ✅ Full (+SECTOR) |
| Morrow | 5.25"/8" | 35-77 | 10-16 | FM/MFM | ✅ Full (+SECTOR) |
| Micropolis | 5.25"/8" | 35-77 | 16 | MFM | ✅ Full (+SECTOR) |
| Generic S-100 | 5.25"/8" | 35-77 | Variable | FM/MFM | ✅ Full (+SECTOR) |

### Specialty & Exotic Drives

| Drive Type | Form Factor | Tracks | Encoding | Interface | Status |
|------------|-------------|--------|----------|-----------|--------|
| Apple II 5.25" media† | 5.25" | 35 | GCR 6&2 | 34-pin Shugart | ✅ Native |
| Apple II DOS 3.2 media† | 5.25" | 35 | GCR 5&3 | 34-pin Shugart | ✅ Native |
| Macintosh 400K/800K | 3.5" | 80 | GCR | 34-pin Shugart | ✅ Native (+MAC_ZONE) |
| Apple Lisa | 3.5" | 80 | GCR | 34-pin Shugart | ✅ Native (+MAC_ZONE) |
| Commodore 5.25" media† | 5.25" | 35-40 | GCR-CBM | 34-pin Shugart | ✅ Native |
| Amiga DD | 3.5" | 80 | MFM | 34-pin | ✅ Native |
| Amiga HD | 3.5" | 80 | MFM | 34-pin | ✅ Native |
| Atari ST | 3.5" | 80 | MFM | 34-pin | ✅ Native |
| BBC Micro | 5.25" | 40/80 | FM/MFM | 34-pin | ✅ Native |
| TRS-80 | 5.25" | 35-40 | FM/MFM | 34-pin | ✅ Native |

> †**Note:** "Apple II media" and "Commodore media" refer to disks read using a **standard Shugart-interface drive** (e.g., a 5.25" PC drive). The original Disk II controller and 1541 drive use proprietary interfaces — FluxRipper reads the *media format*, not the original hardware.

### Tape Drives (Flux Capture)

| Drive Type | Interface | Data Path | Status |
|------------|-----------|-----------|--------|
| Colorado Jumbo | 34-pin | Streaming | ✅ Flux capture |
| Iomega Ditto | 34-pin | Streaming | ✅ Flux capture |
| QIC-40/80 | 34-pin | Streaming | ✅ Flux capture |

### Platform Compatibility Matrix

| Platform | Form Factor | Encoding | Data Rate | Tracks | Support |
|----------|-------------|----------|-----------|--------|---------|
| IBM PC/XT | 5.25" DD | MFM | 250K | 40 | ✅ Native |
| IBM PC/AT | 5.25" HD | MFM | 500K | 80 | ✅ (+TG43) |
| IBM PS/2 | 3.5" HD | MFM | 500K | 80 | ✅ Native |
| IBM PS/2 | 3.5" ED | MFM | 1M | 80 | ✅ Native |
| NeXT | 3.5" ED | MFM | 1M | 80 | ✅ Native |
| Apple II | 5.25" | GCR 6&2 | ~250K | 35 | ✅ Native |
| Apple II | 5.25" | GCR 5&3 | ~250K | 35 | ✅ Native |
| Macintosh 400K | 3.5" | GCR | Variable | 80 | ✅ Native (+MAC_ZONE) |
| Macintosh 800K | 3.5" | GCR | Variable | 80 | ✅ Native (+MAC_ZONE) |
| Apple Lisa | 3.5" | GCR | Variable | 80 | ✅ Native (+MAC_ZONE) |
| Commodore 64 | 5.25" | GCR-CBM | ~300K | 35 | ✅ Native |
| Amiga | 3.5" DD/HD | MFM | 250-500K | 80 | ✅ Native |
| Atari ST | 3.5" DD | MFM | 250K | 80 | ✅ Native |
| BBC Micro | 5.25" | FM/MFM | 125-250K | 40/80 | ✅ Native |
| TRS-80 | 5.25" | FM/MFM | 125-250K | 35-40 | ✅ Native |
| CP/M (8") | 8" | FM/MFM | 250-500K | 77 | ✅ (+HEAD_LOAD) |
| CP/M (5.25") | 5.25" | FM/MFM | 250K | 40/77 | ✅ Native |
| DEC 8" | 8" | FM/MFM | 250-500K | 77 | ✅ (+HEAD_LOAD) |
| DEC RX50 | 5.25" | MFM | 250K | 80 | ✅ Native |
| DEC RX01/02 | 8" | M2FM | 250K | 77 | ✅ Native (+HEAD_LOAD) |
| Intel MDS | 8" | M2FM | 250K | 77 | ✅ Native (+HEAD_LOAD) |
| Cromemco | 5.25"/8" | M2FM | 250K | 35-77 | ✅ Native |
| TRS-80 CoCo | 5.25" | Tandy FM | 250K | 35-40 | ✅ Native |
| Dragon 32/64 | 5.25" | Tandy FM | 250K | 35-40 | ✅ Native |
| Agat-7 | 5.25" | GCR (Agat) | ~250K | 35 | ✅ Native |
| Agat-9 | 5.25" | GCR (Agat) | ~250K | 80 | ✅ Native |
| NorthStar | 5.25" | FM | 250K | 35 | ✅ (+SECTOR) |
| Vector Graphics | 5.25"/8" | FM/MFM | 250-500K | 35-77 | ✅ (+SECTOR) |
| S-100 hard-sect | 5.25"/8" | FM/MFM | 250-500K | 35-77 | ✅ (+SECTOR) |
| NEC PC-88 | 5.25"/3.5" | MFM | 250-500K | 77/80 | ✅ Native |
| NEC PC-98 | 5.25"/3.5" | MFM | 250-500K | 77/80 | ✅ (+TG43) |
| Sharp X68000 | 5.25"/3.5" | MFM | 250-500K | 77/80 | ✅ Native |
| FM-Towns | 3.5" | MFM | 500K-1M | 80 | ✅ Native |
| MSX | 3.5" | MFM | 250-500K | 80 | ✅ Native |
| Amstrad CPC/PCW | 3" CF2 | MFM | 250K | 40/80 | ✅ Adapter |
| Spectrum +3 | 3" CF2 | MFM | 250K | 40/80 | ✅ Adapter |
| Wang WP | 8" | MFM | 500K | 77 | ✅ (+HEAD_LOAD) |
| Xerox 820 | 8" | MFM | 250-500K | 77 | ✅ (+HEAD_LOAD) |
| Kaypro | 5.25" | MFM | 250K | 40/80 | ✅ Native |
| Osborne | 5.25" | MFM | 250K | 40 | ✅ Native |

### Hardware Encoding Support

| Encoding | RTL Module | Description | Platforms |
|----------|------------|-------------|-----------|
| MFM | `mfm_encoder.v`, `mfm_decoder.v` | Modified FM | IBM PC, Amiga, Atari ST, MSX |
| FM | `fm_codec.v` | Single density | CP/M, BBC, TRS-80, early systems |
| M2FM | `m2fm_codec.v` | Modified MFM (inverted clocks) | DEC RX01/02, Intel MDS, Cromemco |
| GCR-CBM | `gcr_cbm.v` | Commodore 4-to-5 | C64, VIC-20, C128 |
| GCR-Apple 6&2 | `gcr_apple.v` | Apple 6-and-2 | Apple II DOS 3.3, ProDOS, Mac |
| GCR-Apple 5&3 | `gcr_apple.v` | Apple 5-and-3 | Apple II DOS 3.2 |
| Tandy FM | `tandy_sync.v` | FM with Tandy sync | TRS-80 CoCo, Dragon 32/64 |
| Agat | `agat_sync.v` | Apple-compatible + native | Soviet Agat-7/Agat-9 clones |

### Data Rate Support

| Rate | CCR Value | Bit Cell | Common Use |
|------|-----------|----------|------------|
| 250 Kbps | 00 | 4.0 µs | DD formats, Commodore |
| 300 Kbps | 01 | 3.33 µs | 5.25" HD at 360 RPM |
| 500 Kbps | 10 | 2.0 µs | HD formats |
| 1 Mbps | 11 | 1.0 µs | ED (2.88MB) formats |

### Extended Drive Control Signals

| Signal | Direction | Function | Drives Enabled |
|--------|-----------|----------|----------------|
| HEAD_LOAD | Output | Head load solenoid | 8" SA800/850, Wang, Xerox, DEC |
| /TG43 | Output | Track ≥ 43 indicator | 5.25" HD, quad-density, PC-98 |
| DENSITY | Output | DD/HD mode (0=DD, 1=HD) | HD/DD combo drives |
| /SECTOR | Input | Hard-sector pulse | NorthStar, Vector Graphics, S-100 |
| MAC_ZONE | Register | Variable-speed zone mode | Macintosh 400K/800K, Lisa |

### Support Level Legend

| Level | Meaning |
|-------|---------|
| ✅ Native | Hardware encoding, standard 34-pin Shugart |
| ✅ Full (+signal) | Full support with extended signal (HEAD_LOAD, TG43, SECTOR) |
| ✅ Native (+MAC_ZONE) | Native support with CCR bit 4 zone mode enabled |
| ✅ Adapter | Physical connector adapter required (26-pin or 50-pin) |
| ✅ Flux capture | Raw flux capture; decode in software |

---

## Architecture Overview

FluxRipper is fundamentally **format-agnostic** at the hardware level. The controller doesn't "know" what kind of drive is attached — it simply:

1. **Generates step pulses** at configurable rates
2. **Captures flux transitions** with nanosecond precision
3. **Detects RPM** via index pulse timing
4. **Decodes data** using selectable encoding schemes

This means **any drive with a Shugart-compatible interface** can be used, regardless of:
- Track density (TPI)
- Physical form factor
- Original platform
- Age or manufacturer

### Controller Limits

| Parameter | Limit | Notes |
|-----------|-------|-------|
| Maximum tracks | 84 (0-83) | Covers all standard formats |
| Data rates | 250K, 300K, 500K, 1M | Via CCR register |
| RPM detection | 150-400 RPM | Auto-detect 300/360 ±5% |
| Step rates | 2ms, 3ms, 6ms, 12ms | Via SPECIFY command |
| Heads | 2 | Head select signal implemented |
| Drives per interface | 2 | DS0/DS1 active-low select |
| Interfaces | 2 | Dual Shugart (4 drives total) |

### Extended Drive Control Signals

FluxRipper provides dedicated signals for 8", HD, and hard-sectored drives:

| Signal | Function | Drives Enabled |
|--------|----------|----------------|
| **HEAD_LOAD** | Head load solenoid control | 8" SA800/850, Wang, Xerox, DEC |
| **/TG43** | Track ≥ 43 indicator | 5.25" HD, quad-density |
| **DENSITY** | DD/HD mode indicator | HD/DD combo drives |
| **/SECTOR** | Hard-sector pulse input | NorthStar, Vector Graphics, S-100 |

See [register_map.md#extended-drive-control-signals](register_map.md#extended-drive-control-signals) for detailed semantics.

---

## Supported Drive Families

### 3.5" Drives (Micro Floppy)

| Format | Capacity | Tracks | TPI | Data Rate | RPM | Status |
|--------|----------|--------|-----|-----------|-----|--------|
| DD | 720 KB | 80 | 135 | 250 Kbps | 300 | ✅ Full support |
| HD | 1.44 MB | 80 | 135 | 500 Kbps | 300 | ✅ Full support |
| ED | 2.88 MB | 80 | 135 | 1 Mbps | 300 | ✅ Full support |

**Common drives:** Sony MPF920, Teac FD-235HF, Panasonic JU-257, NEC FD1231H, Alps DF354H

### 5.25" Drives (Mini Floppy)

| Format | Capacity | Tracks | TPI | Data Rate | RPM | Status |
|--------|----------|--------|-----|-----------|-----|--------|
| SSDD 40T | 180 KB | 40 | 48 | 250 Kbps | 300 | ✅ Full support |
| DSDD 40T | 360 KB | 40 | 48 | 250 Kbps | 300 | ✅ Full support |
| SSQD 80T | 400 KB | 80 | 96 | 250 Kbps | 300 | ✅ Full support |
| DSQD 80T | 720 KB | 80 | 96 | 250 Kbps | 300 | ✅ Full support |
| DSHD 80T | 1.2 MB | 80 | 96 | 500 Kbps | 360 | ✅ Full support |

**Common drives:** Teac FD-55GFR, Mitsubishi MF504C, Tandon TM100-2A, Shugart SA400

**HD/QD Drive Features:**
- **/TG43 signal**: Asserts when track ≥ 43 for proper write current control
- **DENSITY output**: Indicates HD mode (500K/1M) vs DD mode (250K/300K)
- **360 RPM support**: DPLL compensates for faster rotation

### 8" Drives (Standard Floppy)

| Format | Capacity | Tracks | TPI | Data Rate | RPM | Status |
|--------|----------|--------|-----|-----------|-----|--------|
| SSSD | 250 KB | 77 | 100 | 250 Kbps | 360 | ✅ Full support |
| SSDD | 500 KB | 77 | 100 | 500 Kbps | 360 | ✅ Full support |
| DSDD | 1.2 MB | 77 | 100 | 500 Kbps | 360 | ✅ Full support |

**Common drives:** Shugart SA800/SA850, Siemens FDD100-8, Tandon TM848, Qume DT-8, Wang, Xerox 820

**Full 8" Support Features:**
- **HEAD_LOAD signal**: Properly drives head load solenoid (50-pin Shugart pin 4)
- **50-pin adapter**: Maps to FluxRipper GPIO with HEAD_LOAD/READY
- **No head cooking**: HEAD_LOAD controlled by step_controller with proper settle timing

**Note:** 8" drives use a 50-pin Shugart connector. FluxRipper provides the HEAD_LOAD signal required for solenoid-actuated heads.

### Specialty & Exotic Drives

| Drive Type | Tracks | TPI | Interface | Status |
|------------|--------|-----|-----------|--------|
| Apple Disk II (5.25") | 35 | 48 | 34-pin Shugart | ✅ GCR supported |
| Apple 3.5" (800K) | 80 | 135 | 34-pin Shugart | ✅ GCR supported |
| Commodore 1541 | 35-40 | 48 | 34-pin Shugart | ✅ GCR-CBM supported |
| Amiga DD/HD | 80 | 135 | 34-pin Shugart | ✅ MFM compatible |
| Atari ST | 80 | 135 | 34-pin Shugart | ✅ MFM compatible |
| BBC Micro | 40/80 | 48/96 | 34-pin Shugart | ✅ FM/MFM supported |
| TRS-80 | 35-40 | 48 | 34-pin Shugart | ✅ FM/MFM supported |

### 3" CF2 Drives (Amstrad / Spectrum)

The "weird 3-inch" compact floppy drives used in Amstrad CPC, PCW, and Sinclair Spectrum +3:

| Format | Capacity | Tracks | TPI | Data Rate | Status |
|--------|----------|--------|-----|-----------|--------|
| CF2 SS | 180 KB | 40 | 96/100 | 250 Kbps | ✅ Adapter required |
| CF2 DS | 720 KB | 80 | 96/100 | 250 Kbps | ✅ Adapter required |

**Common drives:** Hitachi HFD305/HFD306, Panasonic/Matsushita JU-363

**Interface notes:**
- Uses 26-pin Shugart-variant connector
- Signals are standard: STEP, DIR, INDEX, RDATA, WGATE, WDATA, TRK0, WPT, DS
- Encoding: FM/MFM (exactly as supported)
- READY/DSKCHG semantics differ slightly between machines (firmware policy, not hardware blocker)

**Adapter:** Passive 26-pin to 34-pin cable adapter required.

### Laptop / Slimline 3.5" Drives

90s–2000s laptop floppy drives with compact connectors:

| Format | Capacity | Tracks | TPI | Data Rate | Status |
|--------|----------|--------|-----|-----------|--------|
| Slimline DD | 720 KB | 80 | 135 | 250 Kbps | ✅ Adapter required |
| Slimline HD | 1.44 MB | 80 | 135 | 500 Kbps | ✅ Adapter required |

**Common drives:** TEAC FD-05 series, Sony MPF-xx laptop variants, Alps slimline

**Interface notes:**
- Core signals are standard Shugart
- Connector: 26-pin JAE or flat-flex variants
- Electrically identical to standard 3.5" DD/HD drives

**Adapter:** Passive 26-pin slimline to 34-pin adapter board required.

### Hard-Sectored Drives (NorthStar / S-100)

Early 5.25" and 8" drives with physical sector holes punched in the media:

| Format | Tracks | TPI | Sectors/Track | Status |
|--------|--------|-----|---------------|--------|
| NorthStar 5.25" | 35 | 48 | 10 (hard) | ✅ Full support |
| Vector Graphics | 35-77 | 48-100 | Variable | ✅ Full support |
| Morrow | 35-77 | 48-100 | Variable | ✅ Full support |
| Micropolis | 35-77 | 48-100 | 16 (typical) | ✅ Full support |
| S-100 systems | 35-77 | 48-100 | Variable | ✅ Full support |

**How hard-sectored works:**
- 1 genuine index pulse per revolution
- N additional sector pulses on `/SECTOR` line (one per physical hole)
- Enables physical sector alignment without software encoding

**FluxRipper /SECTOR Support:**
- **/SECTOR input** (GPIO pin B16/F16) captures sector pulses directly
- **Flux word tagging**: Bit 29 (SECTOR) set in flux stream when sector hole detected
- **"Pulse since last word" semantics**: Each flux word spanning a sector hole gets SECTOR=1
- **Simultaneous capture**: INDEX + SECTOR + flux timestamps in unified stream
- **Software decode**: Format-specific sector parsing handled in post-processing

**Typical configurations:**
| System | Sectors/Track | Format |
|--------|---------------|--------|
| NorthStar DOS | 10 | FM, 256 bytes/sector |
| Vector Graphics | 16 | MFM, 512 bytes/sector |
| Morrow | 10-16 | FM/MFM |
| Generic CP/M | 10-16 | FM/MFM |

### QIC-40/QIC-80 Floppy-Interface Tape Drives

Some tape backup drives abused the floppy interface:

| Drive Type | Interface | Data Path | Status |
|------------|-----------|-----------|--------|
| Colorado Jumbo | 34-pin floppy | Streaming | ✅ Flux capture |
| Iomega Ditto | 34-pin floppy | Streaming | ✅ Flux capture |
| QIC-80 units | 34-pin floppy | Streaming | ✅ Flux capture |

**How they work:**
- Electrically 34-pin Shugart-like
- Use STEP/DIR for tape positioning
- Capture RDATA flux while tape runs
- No sector structure — pure streaming bitstream

**FluxRipper approach:**
- Can drive STEP/DIR as normal for tape positioning
- Capture /RDATA flux continuously with DENSITY output set appropriately
- DRV_ID tagging identifies source in dual-interface setups
- FDC sector commands not applicable — raw flux capture only
- Decoding fully software-defined (QIC-40/80 format parsing)

**What you get:**
- Timestamped flux stream from tape head
- Software can recover QIC-40/80 bitstream from flux data
- Useful for recovering old tape backups when drive mechanisms are marginal

*These are "bonus nerd" devices that happen to abuse a Shugart cable. FluxRipper can capture the raw signal; what you do with it is between you and your sanity.*

---

## Track Density (TPI) Support

### Understanding TPI

**TPI (Tracks Per Inch)** is a mechanical property of the drive, not something the controller manages. FluxRipper is **TPI-agnostic** — it simply counts step pulses.

| TPI | Track Spacing | Common Use |
|-----|---------------|------------|
| 48 | 0.0208" | 5.25" 40-track drives |
| 96 | 0.0104" | 5.25" 80-track, most 3.5" |
| 100 | 0.0100" | 8" drives, some specialty |
| 135 | 0.0074" | 3.5" HD/ED drives |

### Cross-TPI Compatibility

Reading disks written at different TPI than the drive:

| Drive TPI | Disk TPI | Compatibility | Notes |
|-----------|----------|---------------|-------|
| 96 | 48 | ✅ Use double-step | 40T disk in 80T drive |
| 48 | 96 | ⚠️ Marginal | Wide head may read adjacent tracks |
| 100 | 96 | ⚠️ Marginal | ~4% cumulative misalignment |
| 96 | 100 | ⚠️ Marginal | ~4% cumulative misalignment |

**Double-Step Mode:**

FluxRipper includes automatic double-step support for reading 48 TPI (40-track) disks in 96 TPI (80-track) drives:

```
Register: CCR or SPECIFY command
Function: Step motor twice per logical track
Detection: Track Width Analyzer module auto-detects 40T vs 80T
```

### TPI Misalignment Effects

When reading a disk at mismatched TPI:

```
Track alignment error accumulates:
  Track  0: 0.0% error (aligned)
  Track 10: 4.0% error (96 vs 100 TPI)
  Track 25: 10.0% error (half-track offset)
  Track 50: 20.0% error (full track offset)
  Track 77: 30.8% error (multiple tracks off)
```

**FluxRipper can still capture flux** even with misalignment — quality metrics will indicate degradation, and flux-level data may allow recovery through post-processing.

---

## Data Rate Support

### Configurable Data Rates

| Rate | CCR Value | Bit Cell | Common Use |
|------|-----------|----------|------------|
| 250 Kbps | 00 | 4.0 µs | DD formats, Commodore |
| 300 Kbps | 01 | 3.33 µs | 5.25" HD at 360 RPM |
| 500 Kbps | 10 | 2.0 µs | HD formats |
| 1 Mbps | 11 | 1.0 µs | ED (2.88MB) formats |

> **Note:** This mapping (00=250K, 01=300K, 10=500K, 11=1M) is the canonical encoding used throughout FluxRipper — in detection logic, CCR register, and DRIVE_PROFILE.

### RPM Compensation

The DPLL automatically compensates for drive speed:

| Drive RPM | 250K Effective | 500K Effective |
|-----------|----------------|----------------|
| 300 | 250 Kbps | 500 Kbps |
| 360 | 300 Kbps | 600 Kbps |

This allows reading 5.25" HD disks (500K @ 360 RPM = 300K effective) correctly.

### Data Rate Detection

FluxRipper can auto-detect data rate via flux timing analysis:

```
Flux timing histogram peaks:
  ~4.0 µs → 250 Kbps MFM
  ~3.3 µs → 300 Kbps MFM
  ~2.0 µs → 500 Kbps MFM
  ~1.0 µs → 1 Mbps MFM
```

---

## Encoding Format Support

### Hardware-Supported Encodings

| Encoding | Module | Description | Platforms |
|----------|--------|-------------|-----------|
| **MFM** | `mfm_encoder.v`, `mfm_decoder.v` | Modified Frequency Modulation | IBM PC, Amiga, Atari ST |
| **FM** | `fm_codec.v` | Frequency Modulation (single density) | CP/M, early systems |
| **GCR-CBM** | `gcr_cbm.v` | Commodore 4-to-5 bit GCR | C64, VIC-20, C128 |
| **GCR-Apple6** | `gcr_apple.v` | Apple 6-and-2 encoding | Apple II DOS 3.3, ProDOS |
| **GCR-Apple5** | `gcr_apple.v` | Apple 5-and-3 encoding | Apple II DOS 3.2 |

### Encoding Selection

Via the `encoding_mux.v` module:

```verilog
localparam ENC_MFM     = 3'b000;  // Standard MFM (IBM PC, Amiga, etc.)
localparam ENC_FM      = 3'b001;  // FM (single density, CP/M, BBC)
localparam ENC_GCR_CBM = 3'b010;  // Commodore GCR (C64, 1541)
localparam ENC_GCR_AP6 = 3'b011;  // Apple 6-bit GCR (DOS 3.3, ProDOS, Mac)
localparam ENC_GCR_AP5 = 3'b100;  // Apple 5-bit GCR (DOS 3.2)
localparam ENC_M2FM    = 3'b101;  // M2FM (DEC RX01/02, Intel MDS, Cromemco)
localparam ENC_TANDY   = 3'b110;  // Tandy FM (TRS-80 CoCo, Dragon 32/64)
```

### Flux-Level Capture (Format Agnostic)

Even for unsupported encodings, FluxRipper can capture raw flux transitions:

```
Capture Mode: Continuous flux capture
Output: 32-bit timestamped transitions
Resolution: ~5ns (200 MHz clock)
Post-processing: Decode in software
```

This enables support for:
- Unknown/proprietary formats
- Copy-protected disks
- Damaged media recovery
- Format reverse-engineering

---

## Physical Interface Reference

### 34-Pin Shugart Interface (Primary)

Standard interface for 3.5" and 5.25" drives.

| Pin | Signal | Direction | Description |
|-----|--------|-----------|-------------|
| 2 | /REDWC | Out | Density select (active low) |
| 4 | N/C | — | Not connected |
| 6 | N/C | — | Not connected |
| 8 | /INDEX | In | Index pulse (once per revolution) |
| 10 | /DS0 | Out | Drive select 0 (active low) |
| 12 | /DS1 | Out | Drive select 1 (active low) |
| 14 | /DS2 | Out | Drive select 2 (active low) |
| 16 | /MOTEA | Out | Motor enable A |
| 18 | /DIR | Out | Step direction (1=in, 0=out) |
| 20 | /STEP | Out | Step pulse |
| 22 | /WDATA | Out | Write data |
| 24 | /WGATE | Out | Write gate |
| 26 | /TRK00 | In | Track 0 sensor |
| 28 | /WPT | In | Write protect |
| 30 | /RDATA | In | Read data |
| 32 | /SIDE1 | Out | Head select (0=side 0, 1=side 1) |
| 34 | /DSKCHG | In | Disk change |
| Odd | GND | — | Ground (all odd pins) |

### 50-Pin Shugart Interface (8" Drives)

For 8" drives, signals are electrically compatible but use different pinout.

| Pin | Signal | Pin | Signal |
|-----|--------|-----|--------|
| 1 | GND | 2 | /HEAD LOAD |
| 3 | GND | 4 | /DS3 |
| 5 | GND | 6 | /DS2 |
| 7 | GND | 8 | /DS1 |
| 9 | GND | 10 | /DS0 |
| 11 | GND | 12 | /MOTOR ON |
| 13 | GND | 14 | /DIR |
| 15 | GND | 16 | /STEP |
| 17 | GND | 18 | /WRITE DATA |
| 19 | GND | 20 | /WRITE GATE |
| 21 | GND | 22 | /TRACK 0 |
| 23 | GND | 24 | /WRITE PROTECT |
| 25 | GND | 26 | /READ DATA |
| 27 | GND | 28 | /SECTOR (not used) |
| 29 | GND | 30 | /INDEX |
| 31 | GND | 32 | /FAULT (not used) |
| 33 | GND | 34 | /READY |
| 35-50 | GND/Reserved | | |

### Level Shifting

FluxRipper uses 3.3V LVCMOS I/O. External level shifters required:

| Direction | Chip | Function |
|-----------|------|----------|
| FPGA → Drive | 74AHCT125 | 3.3V to 5V buffer (quad) |
| Drive → FPGA | 74LVC245 | 5V to 3.3V buffer (octal) |

**Per interface:** 2× 74AHCT125 + 1× 74LVC245

---

## Drive Compatibility Matrix

### By Platform

| Platform | Form Factor | Encoding | Data Rate | Tracks | Support Level |
|----------|-------------|----------|-----------|--------|---------------|
| **IBM PC/XT** | 5.25" DD | MFM | 250K | 40 | ✅ Native |
| **IBM PC/AT** | 5.25" HD | MFM | 500K | 80 | ✅ Native (+TG43) |
| **IBM PS/2** | 3.5" HD | MFM | 500K | 80 | ✅ Native |
| **IBM PS/2** | 3.5" ED | MFM | 1M | 80 | ✅ Native |
| **Apple II** | 5.25" | GCR 6&2 | ~250K | 35 | ✅ Native |
| **Apple II** | 5.25" | GCR 5&3 | ~250K | 35 | ✅ Native |
| **Macintosh** | 3.5" | GCR | Variable | 80 | ✅ Native (+MAC_ZONE) |
| **Commodore 64** | 5.25" | GCR-CBM | ~300K | 35 | ✅ Native |
| **Amiga** | 3.5" DD | MFM | 250K | 80 | ✅ Native |
| **Amiga** | 3.5" HD | MFM | 500K | 80 | ✅ Native |
| **Atari ST** | 3.5" DD | MFM | 250K | 80 | ✅ Native |
| **BBC Micro** | 5.25" | FM/MFM | 125K/250K | 40/80 | ✅ Native |
| **TRS-80** | 5.25" | FM/MFM | 125K/250K | 35-40 | ✅ Native |
| **CP/M (8")** | 8" | FM/MFM | 250K/500K | 77 | ✅ Full (+HEAD_LOAD) |
| **CP/M (5.25")** | 5.25" | FM/MFM | 250K | 40/77 | ✅ Native |
| **DEC 8"** | 8" | FM/MFM | 250K/500K | 77 | ✅ Full (+HEAD_LOAD) |
| **DEC RX50** | 5.25" | MFM | 250K | 80 | ✅ Native |
| **NorthStar** | 5.25" | FM | 250K | 35 | ✅ Full (+SECTOR) |
| **Vector Graphics** | 5.25"/8" | FM/MFM | 250K/500K | 35-77 | ✅ Full (+SECTOR) |
| **S-100 hard-sect** | 5.25"/8" | FM/MFM | 250K/500K | 35-77 | ✅ Full (+SECTOR) |
| **NEC PC-88** | 5.25"/3.5" | MFM | 250K/500K | 77/80 | ✅ Native |
| **NEC PC-98** | 5.25"/3.5" | MFM | 250K/500K | 77/80 | ✅ Native (+TG43) |
| **Sharp X68000** | 5.25"/3.5" | MFM | 250K/500K | 77/80 | ✅ Native |
| **Fujitsu FM-Towns** | 3.5" | MFM | 500K/1M | 80 | ✅ Native |
| **MSX** | 3.5" | MFM | 250K/500K | 80 | ✅ Native |
| **Amstrad CPC/PCW** | 3" CF2 | MFM | 250K | 40/80 | ✅ Adapter |
| **Spectrum +3** | 3" CF2 | MFM | 250K | 40/80 | ✅ Adapter |
| **Wang WP** | 8" | MFM | 500K | 77 | ✅ Full (+HEAD_LOAD) |
| **Xerox 820** | 8" | MFM | 250K/500K | 77 | ✅ Full (+HEAD_LOAD) |

### Support Levels

| Level | Meaning |
|-------|---------|
| ✅ Native | Hardware encoding support, standard 34-pin Shugart |
| ✅ Full (+signal) | Full hardware support with extended signal (HEAD_LOAD, TG43, SECTOR) |
| ✅ Adapter | Physical connector adapter required (26-pin or 50-pin) |
| ⚠️ Software | Flux capture works; decode in post-processing |

**Extended signal annotations:**
- **(+HEAD_LOAD)** — 8" drives with solenoid heads, properly supported
- **(+TG43)** — 5.25" HD drives with write current control, properly supported
- **(+SECTOR)** — Hard-sectored drives, sector pulses captured in flux stream

---

## Platform-Specific Notes

### IBM PC Compatible

Standard operation. All PC floppy formats natively supported via 82077AA-compatible command set.

```
Formats: 160K, 180K, 320K, 360K, 720K, 1.2M, 1.44M, 2.88M
Commands: All Type 1-4 commands implemented
DMA: Via AXI-Stream to HyperRAM buffer
```

### Apple II

GCR encoding with variable-speed zones requires special handling:

```
Track zones (DOS 3.3):
  Tracks  0-15: 16 sectors, ~262 RPM equivalent
  Tracks 16-31: 15 sectors, ~276 RPM equivalent
  Tracks 32-34: 13 sectors, ~303 RPM equivalent

FluxRipper approach:
  1. Capture flux at constant sample rate
  2. Decode GCR in hardware (gcr_apple.v)
  3. Or capture raw flux for software processing
```

### Commodore 1541

GCR-CBM encoding with zone-based sector counts:

```
Track zones:
  Tracks  1-17: 21 sectors
  Tracks 18-24: 19 sectors
  Tracks 25-30: 18 sectors
  Tracks 31-35: 17 sectors

Hardware support: gcr_cbm.v provides encode/decode
```

### Amiga

Uses standard MFM but with different track format:

```
Sector format: 512 bytes + AmigaDOS header
Tracks: 80 (DD) or 80 (HD)
Special: Tracks contain 11 sectors (DD) or 22 sectors (HD)
Support: MFM decode works; sector parsing in software
```

### 8" Drives (CP/M, DEC, etc.)

Electrically compatible, requires connector adapter:

```
Differences from 34-pin:
  - 50-pin connector
  - Active /HEAD LOAD signal (directly drive head solenoid)
  - /READY signal active (some drives)
  - Typically 77 tracks at 100 TPI

FluxRipper notes:
  - HEAD LOAD can be directly driven from FPGA
  - READY signal directly readable
  - All timing parameters within spec
```

### Japanese PC Platforms (PC-88/98, X68000, FM-Towns)

These systems use standard 34-pin Shugart MFM drives with quirky geometries:

```
NEC PC-8801 / PC-9801:
  - 5.25" and 3.5" variants
  - 77 or 80 tracks, 8 or 9 sectors
  - Standard MFM encoding
  - Non-PC sector interleave

Sharp X68000:
  - 5.25" (1232KB) or 3.5" HD
  - 77 tracks × 8 sectors × 1024 bytes
  - Standard MFM, unusual geometry

Fujitsu FM-Towns:
  - 3.5" HD drives
  - Standard 1.44MB or custom layouts
  - MFM encoding

MSX turboR:
  - 3.5" DD/HD drives
  - Standard MFM

FluxRipper notes:
  - Drives are identical to PC drives (same connectors, signals)
  - Data rates within supported range (250K-500K)
  - Sector layout differs — handled in software
  - Flux capture mode captures everything for any format
```

### DEC 5.25" (RX50 and similar)

DEC's RX50 and similar 5.25" drives use MFM with odd sector sizes:

```
RX50:
  - 80 tracks, 10 sectors, 512 bytes
  - MFM encoding
  - Non-standard interleave

FluxRipper notes:
  - Drive is standard 34-pin Shugart
  - MFM decode works at hardware level
  - Sector layout parsing in software
```

### 3" CF2 (Amstrad / Spectrum / Word Processors)

Amstrad CPC, PCW, and Spectrum +3 use 3" compact floppies:

```
Amstrad CPC:
  - DATA format: 40 tracks, 9 sectors
  - SYSTEM format: 40 tracks, 9 sectors
  - MFM encoding

Amstrad PCW:
  - 80 tracks for HD versions
  - Various sector layouts

Spectrum +3:
  - 40 tracks, 9 sectors
  - +3DOS format

FluxRipper notes:
  - 26-pin to 34-pin passive adapter required
  - All signals map directly
  - MFM decoding native
  - Filesystem handled in software
```

### Word Processors & CP/M Derivatives

Many dedicated word processors and CP/M-derived systems use completely standard 5.25"/3.5" Shugart-interface MFM or FM drives. These include:

- Brother word processors
- Sanyo machines
- Kaypro, Osborne
- Various dedicated office machines

**FluxRipper support:** These are supported natively at the hardware level; only the filesystem and sector interleave differ. Those are handled in software, not the FDC.

---

## Adapter Requirements

### 8" Drive Adapter (50-pin to 34-pin)

Required signals to map:

| 50-pin | 34-pin | Notes |
|--------|--------|-------|
| /DS0 (10) | /DS0 (10) | Direct |
| /MOTOR ON (12) | /MOTEA (16) | Direct |
| /DIR (14) | /DIR (18) | Direct |
| /STEP (16) | /STEP (20) | Direct |
| /WRITE DATA (18) | /WDATA (22) | Direct |
| /WRITE GATE (20) | /WGATE (24) | Direct |
| /TRACK 0 (22) | /TRK00 (26) | Direct |
| /WRITE PROTECT (24) | /WPT (28) | Direct |
| /READ DATA (26) | /RDATA (30) | Direct |
| /INDEX (30) | /INDEX (8) | Direct |
| /HEAD LOAD (2) | GPIO | Optional: drive from FPGA |
| /READY (34) | GPIO | Optional: read to FPGA |

### Active Termination

8" drives typically require active termination on the last drive:

```
Termination: 150Ω to +5V on all active-low signals
Location: Last drive on cable only
FluxRipper: No changes needed (termination on drive side)
```

### 26-Pin Drive Adapters (3" CF2 / Laptop)

For 3" CF2 (Amstrad) and laptop/slimline drives with 26-pin connectors:

| 26-pin | 34-pin | Signal |
|--------|--------|--------|
| 2 | 8 | /INDEX |
| 4 | 10 | /DS0 |
| 6 | 12 | /DS1 |
| 8 | 16 | /MOTEA |
| 10 | 18 | /DIR |
| 12 | 20 | /STEP |
| 14 | 22 | /WDATA |
| 16 | 24 | /WGATE |
| 18 | 26 | /TRK00 |
| 20 | 28 | /WPT |
| 22 | 30 | /RDATA |
| 24 | 32 | /SIDE1 |
| 26 | 34 | /DSKCHG (if present) |
| Odd | Odd | GND |

**Notes:**
- Simple passive adapter (no active components)
- Some 26-pin variants omit DSKCHG — not critical for operation
- 3" CF2 drives may have different READY semantics — check specific drive documentation

---

## Appendix: Step Timing Reference

### Standard Step Rates

| Setting | Time | Use Case |
|---------|------|----------|
| 2 ms | Fast | Modern drives, short seeks |
| 3 ms | Standard | Most 3.5" HD drives |
| 6 ms | Slow | Older drives, reliability |
| 12 ms | Very slow | 8" drives, worn mechanisms |

### Head Settle Time

```
Default: 15 ms (from SPECIFY command)
Range: 0-255 ms (programmable)
Recommendation: 15-25 ms for archival work
```

### Motor Spinup

```
Detection: Via index pulse timing
Spinup count: 8 revolutions default
At 300 RPM: ~1.6 seconds
At 360 RPM: ~1.3 seconds
```

---

## Summary

FluxRipper supports virtually **any floppy drive with a Shugart-compatible interface**:

| Category | Support |
|----------|---------|
| 3.5" drives (DD/HD/ED) | ✅ Native |
| 5.25" drives (40T/80T DD) | ✅ Native |
| 5.25" HD drives (1.2 MB) | ✅ Full (+TG43, +DENSITY) |
| 3" CF2 drives (Amstrad) | ✅ 26-pin adapter |
| 8" drives | ✅ Full (+HEAD_LOAD) |
| Laptop/slimline drives | ✅ 26-pin adapter |
| MFM encoding | ✅ Hardware |
| FM encoding | ✅ Hardware |
| GCR (Apple/Commodore) | ✅ Hardware |
| Unknown formats | ✅ Flux capture |
| Hard-sectored media | ✅ Full (+SECTOR capture) |
| QIC floppy-tape | ✅ Flux capture |
| 48/96/100/135 TPI | ✅ TPI-agnostic |
| 300/360 RPM | ✅ Auto-detect |
| 250K-1M data rates | ✅ Configurable |

### Extended Drive Control Signals

| Signal | Function | Drives Enabled |
|--------|----------|----------------|
| HEAD_LOAD | Solenoid control | 8" SA800/850, Wang, Xerox, DEC |
| /TG43 | Track ≥43 indicator | 5.25" HD, quad-density, PC-98 |
| DENSITY | DD/HD mode | HD/DD combo drives |
| /SECTOR | Sector pulse input | NorthStar, Vector Graphics, S-100 |

### Platforms Explicitly Supported

| Region | Platforms |
|--------|-----------|
| **Western** | IBM PC, Apple II, Macintosh, Amiga, Atari ST, BBC Micro, TRS-80, CP/M, DEC |
| **Japanese** | NEC PC-88/98, Sharp X68000, Fujitsu FM-Towns, MSX |
| **European** | Amstrad CPC/PCW, Sinclair Spectrum +3, Commodore 64/128, Dragon 32/64 |
| **Soviet/Russian** | Agat-7, Agat-9 (Soviet Apple II clones) |
| **8" ecosystem** | CP/M, DEC RX01/02, Intel MDS, Wang, Xerox 820, IBM 3740, Cromemco |
| **Hard-sectored** | NorthStar, Vector Graphics, Morrow, Micropolis, S-100 |
| **M2FM systems** | DEC RX01/02, Intel MDS, Cromemco, Heathkit/Zenith |
| **Tandy/CoCo** | TRS-80 Color Computer, Dragon 32/64, RSDOS |
| **Edge cases** | QIC-40/80 tape, word processors, unknown formats |

The philosophy: **"If the head can see magnetism, FluxRipper can capture it."**

*Your weird drive is invited to the party too — and now we speak its native control signals.*
