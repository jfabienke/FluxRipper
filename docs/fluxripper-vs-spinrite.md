# FluxRipper vs SpinRite: Technical Comparison

*Created: 2025-12-04 20:31:16*

---

## Executive Summary

SpinRite and FluxRipper serve different eras of storage technology. SpinRite is a **software tool** that works through existing drive controllers to recover data from modern SATA/NVMe/USB drives. FluxRipper is a **hardware platform** that directly interfaces with vintage ST-506/ESDI drives at the magnetic flux level, bypassing the need for a working controller entirely.

**SpinRite** = Software doctor for modern drives (works through the system)
**FluxRipper** = Hardware archaeologist for vintage drives (replaces the system)

---

## Product Overview

| Aspect | SpinRite 6.1 | FluxRipper |
|--------|--------------|------------|
| **Developer** | Gibson Research Corporation | FluxRipper Project |
| **Type** | Bootable DOS software | FPGA hardware platform |
| **Target Era** | Modern drives (SATA, NVMe, SSD) | Vintage drives (ST-506, ESDI, MFM/RLL) |
| **Interface Level** | Block-level (sector abstraction) | Flux-level (raw magnetic transitions) |
| **Boot Environment** | DOS (BIOS only, no UEFI yet) | Embedded FPGA SoC (standalone) |
| **Host Dependency** | Requires working PC to boot | Standalone hardware device |
| **Drive Interfaces** | IDE/SATA/USB via BIOS/AHCI | ST-506 34+20 pin, ESDI differential |
| **Price** | ~$89 USD | Open hardware (BOM cost) |

---

## Architecture Comparison

### SpinRite Access Path

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   SpinRite   │───►│  BIOS/AHCI   │───►│  WD/IDE/SATA │───►│    Drive     │
│    (DOS)     │    │   INT 13h    │    │  Controller  │    │  (sectors)   │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                           ▲
                           │
              Abstracted access through controller
              Limited by controller firmware capabilities
              Cannot access raw magnetic data
```

**Limitations:**
- Requires functional drive controller
- Cannot work with vintage interfaces (ST-506, ESDI)
- No access to raw flux transitions
- Dependent on BIOS support for the drive
- Cannot bypass controller-level errors

### FluxRipper Access Path

```
┌──────────────┐    ┌─────────────────────────────────────────────────────────┐
│  FluxRipper  │───►│     Direct ST-506/ESDI wiring to drive head signals     │
│    (FPGA)    │    │     Raw flux transitions sampled @ 400 MHz              │
│              │    │     MFM/RLL/ESDI decoding in hardware                   │
└──────────────┘    └─────────────────────────────────────────────────────────┘
                           ▲
                           │
              No abstraction - raw magnetic signal access
              Full control over read timing and retries
              Works even with dead original controller
```

**Advantages:**
- Direct magnetic flux access
- Works with dead/missing controllers
- Supports obsolete interfaces natively
- Full timing and retry control
- Archival-quality flux imaging

---

## Technical Capabilities

### Interface Support

| Interface | SpinRite | FluxRipper |
|-----------|:--------:|:----------:|
| SATA | Yes | No |
| IDE/PATA | Yes | No |
| NVMe | Via BIOS | No |
| USB | Via BIOS | No |
| ST-506 MFM | No | **Yes** |
| ST-506 RLL | No | **Yes** |
| ESDI | No | **Yes** |
| Floppy (FDD) | No | **Yes** |

### Recovery Techniques

| Technique | SpinRite | FluxRipper | Notes |
|-----------|:--------:|:----------:|-------|
| Multiple read retries | Yes (2000x) | **Yes (unlimited)** | FluxRipper stores all passes |
| Statistical bit voting | Yes | **Yes** | Histogram-based in FluxRipper |
| Head positioning optimization | No | **Yes** | Sub-track offset sweeps |
| Clock recovery tuning | No | **Yes** | DPLL bandwidth adjustment |
| ECC recalculation | Via controller | **Yes** | Reed-Solomon in FPGA |
| Viterbi PRML decoding | No | **Yes** | Soft-decision recovery |
| FFT jitter analysis | No | **Yes** | Wow/flutter compensation |
| Adaptive equalization | No | **Yes** | LMS + DFE algorithms |
| Correlation sync detection | No | **Yes** | Pattern matching in hardware |

### Diagnostic Capabilities

| Capability | SpinRite | FluxRipper |
|------------|:--------:|:----------:|
| SMART monitoring | Yes | **Yes** (emulated) |
| Sector read verification | Yes | **Yes** |
| Flux-level capture | No | **Yes** |
| Drive fingerprinting | Basic | **Full mechanical profile** |
| RPM jitter measurement | No | **Yes** |
| Seek timing analysis | No | **Yes** |
| Zone bit recording detection | No | **Yes** |
| Head switching timing | No | **Yes** |
| Write precompensation analysis | No | **Yes** |

### Advanced Features

| Feature | SpinRite | FluxRipper |
|---------|:--------:|:----------:|
| Raw flux imaging | No | **Yes** |
| Controller emulation | No | **Yes** (WD1003/1006/1007) |
| Hidden metadata storage | No | **Yes** (steganographic tagging) |
| Dual-drive support | No | **Yes** (drive-to-drive copy) |
| Interface auto-detection | N/A | **Yes** (MFM/RLL/ESDI) |
| Differential PHY | N/A | **Yes** (ESDI) |
| SSD TRIM/refresh | Yes | No |

---

## Recovery Depth Comparison

### What SpinRite Can Access

```
┌────────────────────────────────────────────────────────────────┐
│                        DRIVE INTERNALS                         │
├────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Magnetic Media                       │   │
│  │  ┌─────────────────────────────────────────────────────┐│   │
│  │  │                  Flux Transitions                   ││   │
│  │  │  ┌─────────────────────────────────────────────────┐││   │
│  │  │  │              MFM/RLL Bit Stream                 │││   │
│  │  │  │  ┌─────────────────────────────────────────────┐│││   │
│  │  │  │  │           Sector Data + ECC                 ││││   │
│  │  │  │  │  ┌─────────────────────────────────────────┐││││   │
│  │  │  │  │  │     ◄── SpinRite Access Level ──►       │││││   │
│  │  │  │  │  │         (Sector/Block I/O)              │││││   │
│  │  │  │  │  └─────────────────────────────────────────┘││││   │
│  │  │  │  └─────────────────────────────────────────────┘│││   │
│  │  │  └─────────────────────────────────────────────────┘││   │
│  │  └─────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

### What FluxRipper Can Access

```
┌────────────────────────────────────────────────────────────────┐
│                        DRIVE INTERNALS                         │
├────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ◄──────────── FluxRipper Access Level ─────────────►    │   │
│  │                    Magnetic Media                       │   │
│  │  ┌─────────────────────────────────────────────────────┐│   │
│  │  │ ◄──────── Raw Flux Capture @ 400 MHz ───────────►   ││   │
│  │  │                  Flux Transitions                   ││   │
│  │  │  ┌─────────────────────────────────────────────────┐││   │
│  │  │  │ ◄──────── FPGA MFM/RLL/ESDI Decode ──────────►  │││   │
│  │  │  │              MFM/RLL Bit Stream                 │││   │
│  │  │  │  ┌─────────────────────────────────────────────┐│││   │
│  │  │  │  │ ◄──────── Hardware ECC Recovery ──────────► ││││   │
│  │  │  │  │           Sector Data + ECC                 ││││   │
│  │  │  │  │  ┌─────────────────────────────────────────┐││││   │
│  │  │  │  │  │ ◄──────── WD Controller Emulation ────► │││││   │
│  │  │  │  │  │         (Sector/Block I/O)              │││││   │
│  │  │  │  │  └─────────────────────────────────────────┘││││   │
│  │  │  │  └─────────────────────────────────────────────┘│││   │
│  │  │  └─────────────────────────────────────────────────┘││   │
│  │  └─────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

---

## Use Case Comparison

### SpinRite Excels At

1. **Modern Drive Maintenance**
   - SSD performance refresh (TRIM-like effects)
   - SATA/NVMe sector verification
   - Pre-failure SMART monitoring

2. **Intermittent Read Failures**
   - Marginal sectors on spinning drives
   - Heat-related temporary failures
   - Retry-recoverable errors

3. **Convenience**
   - No hardware required beyond boot media
   - Works with any BIOS-accessible drive
   - Simple user interface

### FluxRipper Excels At

1. **Vintage Drive Recovery**
   - ST-506 MFM drives (1980s-1990s)
   - RLL drives (higher density ST-506)
   - ESDI drives (10-15 Mbps)
   - Drives with dead/unavailable controllers

2. **Archival Preservation**
   - Raw flux imaging (like Kryoflux for HDDs)
   - Bit-perfect sector extraction
   - Copy protection analysis
   - Format/encoding research

3. **Advanced Recovery Scenarios**
   - Drives with damaged servo tracks
   - Marginal head alignment issues
   - Degraded magnetic coating
   - Unknown/proprietary formats

4. **Hardware Replacement**
   - Emulates WD1003/1006/1007 controllers
   - Allows vintage PCs to use preserved images
   - Drive-to-drive cloning without host PC

---

## FluxRipper-Exclusive Capabilities

### 1. Flux-Level Imaging

Captures actual magnetic transitions, not just decoded sectors:

```
Traditional Recovery:     Sector → ECC Check → Pass/Fail
FluxRipper Recovery:      Flux → Histogram → Statistical Decode → Sector
```

This enables recovery of sectors that would be permanently lost with sector-level tools.

### 2. Multi-Pass Statistical Recovery

```
Pass 1: ████████░░░░░░░░ (50% bits confident)
Pass 2: ██████████░░░░░░ (62% bits confident)
Pass 3: ████████████░░░░ (75% bits confident)
...
Pass N: ████████████████ (99.9% bits confident)
```

Each pass adds to a histogram, and bit values are determined statistically.

### 3. DSP Recovery Pipeline

| Stage | Function |
|-------|----------|
| FIR Filter | Noise reduction, matched filtering |
| Adaptive Equalizer | Cable/head compensation (LMS + DFE) |
| Correlation Sync | Pattern matching for sector headers |
| PRML Decoder | Viterbi soft-decision for marginal bits |
| Reed-Solomon | Hardware ECC recalculation |
| FFT Analyzer | RPM jitter and wow/flutter analysis |

### 4. Hidden Metadata ("Drive Tagging")

FluxRipper can store provenance data directly on the drive:

```
meta id 0 Seagate ST-225 8734291
meta datecode 0 8723 A.01
meta note 0 "From Dad's 286 PC - important files"
```

This metadata:
- Survives reformatting (stored in "fake bad sectors")
- Includes drive fingerprint (geometry, RPM, jitter)
- Tracks diagnostic history
- Appears in WD IDENTIFY responses

### 5. Controller Emulation

FluxRipper can act as a WD1003/1006/1007 controller:

- Vintage PCs see a "normal" hard drive
- ISA bus interface (0x1F0-0x1F7)
- ISA Plug-and-Play support
- USB 2.0 HS interface for modern systems
- Serves flux images as virtual drives

---

## When to Use Each Tool

| Scenario | Recommended Tool |
|----------|------------------|
| Modern SATA drive with bad sectors | SpinRite |
| SSD performance degradation | SpinRite |
| ST-225 from a 1987 IBM AT | **FluxRipper** |
| ESDI drive with dead controller | **FluxRipper** |
| Creating archival image of vintage drive | **FluxRipper** |
| NVMe drive pre-failure maintenance | SpinRite |
| Unknown format reverse engineering | **FluxRipper** |
| Drive-to-drive vintage cloning | **FluxRipper** |
| USB external drive recovery | SpinRite |
| Miniscribe RLL drive from 1989 | **FluxRipper** |

---

## Technical Specifications

### SpinRite 6.1

| Spec | Value |
|------|-------|
| Size | ~250 KB |
| Boot | DOS (BIOS only) |
| Interfaces | IDE, SATA, USB, NVMe (via BIOS) |
| Max retries | 2000 per sector |
| UEFI support | No (planned for v7.0) |
| Operating mode | Software (through controller) |

### FluxRipper

| Spec | Value |
|------|-------|
| Platform | AMD Spartan UltraScale+ (XCSU35P) |
| Sample rate | 400 MHz |
| Interfaces | ST-506 (MFM/RLL), ESDI, FDD |
| Encoding | MFM, RLL(2,7), FM, GCR |
| Data rates | 250 Kbps - 15 Mbps |
| Dual-drive | Yes (2x ST-506 or 2x FDD) |
| Controller emulation | WD1003, WD1006, WD1007 |
| Host interfaces | AXI, ISA, ISA PnP, USB 2.0 HS |
| RTL size | ~35,700 lines (Verilog) |
| Firmware size | ~13,400 lines (C) |

---

## Conclusion

SpinRite and FluxRipper are **complementary tools** serving different segments of storage technology:

- **SpinRite** handles the drives you're still using today
- **FluxRipper** rescues the drives from computing history

For vintage computing enthusiasts, data archaeologists, and digital preservationists, FluxRipper provides capabilities that simply don't exist in any software tool - because it operates at a level below what software can reach.

---

## References

- [SpinRite Official Site (GRC)](https://www.grc.com/sr/spinrite.htm)
- [SpinRite Wikipedia](https://en.wikipedia.org/wiki/SpinRite)
- [SpinRite 6.1 Release Information](https://zorva.info/2024/02/02/spinrite-6-1-ready-to-launch/)
- FluxRipper Project Documentation (`docs/architecture.md`)
- FluxRipper Implementation Plan (`mellow-snuggling-octopus.md`)
