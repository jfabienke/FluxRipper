# Floppy Controller Comparison Matrix

*FluxRipper vs KryoFlux vs GreaseWeazle vs SuperCard Pro*

*Updated: 2025-12-03 17:15*

---

## Executive Summary

| Feature | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|---------|------------|----------|--------------|---------------|
| **Price** | ~$150 (BOM)† | ~$100-150 | ~$35-50 | ~$100 |
| **Open Source** | Yes (RTL+SW) | No (closed) | Yes (FW+SW) | Partial (SW open) |
| **Interface** | AXI/PCIe | USB | USB | USB/Serial |
| **FPGA-based** | Yes | Yes (ARM+FPGA) | No (MCU) | No (MCU) |
| **Real-time decode** | Yes | No | No | No |
| **FDC replacement** | ✅ 82077AA / AXI | ❌ Host USB only | ❌ Host USB only | ❌ Host USB only |
| **Auto-detect (HW)** | ✅ DRIVE_PROFILE | ❌ Manual config | ❌ Manual/diskdef | ❌ Manual config |
| **8" native support** | Yes (HEAD_LOAD) | Via FDADAP | Via FDADAP | Via adapter |
| **Hard-sector native** | Yes (/SECTOR) | No | Yes (v1.18+) | No |
| **Write support** | Yes | Yes | Yes | Yes |

> †**Price note:** FluxRipper ~$150 is BOM cost for DIY build. Small production runs typically add 50-100% for assembly/margin.

---

## Table of Contents

1. [Hardware Specifications](#1-hardware-specifications)
2. [Drive Support Comparison](#2-drive-support-comparison)
3. [Encoding Format Support](#3-encoding-format-support)
4. [Platform/System Support](#4-platformsystem-support)
5. [Software & File Formats](#5-software--file-formats)
6. [Copy Protection Handling](#6-copy-protection-handling)
7. [Unique Features](#7-unique-features)
8. [Use Case Recommendations](#8-use-case-recommendations)

---

## 1. Hardware Specifications

| Specification | FluxRipper | KryoFlux | GreaseWeazle V4 | SuperCard Pro |
|---------------|------------|----------|-----------------|---------------|
| **Processor** | AMD SCU35 FPGA | ARM + FPGA | STM32F730 MCU | PIC24 MCU |
| **Clock/Resolution** | 200 MHz / 5ns | ~24 MHz / ~41ns | ~72 MHz / ~14ns | 40 MIPS / 25ns |
| **RAM** | HyperRAM 8MB | Internal | Internal | 512KB SRAM |
| **Host Interface** | AXI-Lite / PCIe | USB 2.0 | USB 2.0 | USB / Serial |
| **Floppy Interface** | Dual 34-pin + GPIO | Single 34-pin | Single 34-pin | Single 34-pin |
| **Drives per interface** | 2 (4 total) | 2 | 2-3 | 2 |
| **Power** | External 5V/12V | USB + external | USB + external | USB + external |
| **Buffered outputs** | Yes (74AHCT) | Yes | Yes (V4) | Yes |
| **Write protect jumper** | Yes | No | Yes | No |
| **Hardware auto-detect** | DRIVE_PROFILE reg | No | No | No |

### Extended Signal Support

| Signal | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|--------|------------|----------|--------------|---------------|
| HEAD_LOAD (8") | Native GPIO | Via FDADAP | Via FDADAP | Via adapter |
| /TG43 (5.25" HD) | Native GPIO | Via FDADAP | SW toggle‡ | No |
| DENSITY | Native GPIO | Manual | Via diskdef | No |
| /SECTOR (hard) | Native GPIO | No | Pin 34 option | No |
| READY | Native input | Yes | Yes | Yes |
| DISK_CHANGE | Native input | Yes | Yes | Yes |

> **Signal terminology:**
> - **Native GPIO** = Dedicated hardware signal, directly controlled by FPGA logic
> - **Via FDADAP** = Requires external adapter board (e.g., dbit.com FDADAP) to generate signal
> - **SW toggle‡** = Software-generated via `--gen-tg43` flag; toggles pin but not hardware-integrated
> - **Via diskdef** = Configured through software disk definition files, not hardware-aware

---

## 2. Drive Support Comparison

### Form Factor Support

| Drive Type | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|------------|------------|----------|--------------|---------------|
| **3.5" DD/HD** | Native | Native | Native | Native |
| **3.5" ED (2.88MB)** | Native (1 Mbps)† | Native | Native | Native |
| **5.25" DD (40T)** | Native | Native | Native | Native |
| **5.25" QD (80T)** | Native | Native | Native | Native |
| **5.25" HD (1.2MB)** | Native (+TG43) | Via adapter | `--gen-tg43` | Via adapter |
| **8" SS/DS** | Native (+HEAD_LOAD) | Via FDADAP | Via FDADAP | Via adapter |
| **3" CF2 (Amstrad)** | 26-pin adapter | 26-pin adapter | Native 26-pin | Via adapter |
| **Slimline laptop** | 26-pin adapter | Via adapter | Via adapter | Via adapter |

> †**ED note:** All controllers electrically support 2.88MB ED drives (1 Mbps data rate). FluxRipper uses 1 Mbps detection in DRIVE_PROFILE for automatic density capability identification — the others require manual configuration.

### RPM Support

| RPM | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|-----|------------|----------|--------------|---------------|
| 300 RPM | Auto-detect | Auto-detect | Auto-detect | Auto-detect |
| 360 RPM | Auto-detect | Auto-detect | Auto-detect | Auto-detect |
| Variable (Mac GCR) | Native (zone NCO) | Software decode | Software decode | Software decode |

### Track Density

| Track Config | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|--------------|------------|----------|--------------|---------------|
| 40-track (48 TPI) | Native + auto-detect | Native | Native | Native |
| 80-track (96 TPI) | Native + auto-detect | Native | Native | Native |
| 77-track (8" / 100 TPI) | Native | Native | Native | Native |
| Double-step auto | Yes (CCR[5]) | Manual | `--double-step` | Manual |

### Hard-Sectored Media

| System | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|--------|------------|----------|--------------|---------------|
| NorthStar (10 sector) | Native (/SECTOR) | No | Yes (v1.18+) | No |
| Vector Graphics (16 sector) | Native (/SECTOR) | No | Yes (v1.18+) | No |
| Micropolis | Native (/SECTOR) | No | Yes (v1.18+) | No |
| Generic S-100 | Native (/SECTOR) | No | Yes (v1.18+) | No |

---

## 3. Encoding Format Support

### Hardware vs Software Decode

**What "Hardware" means for FluxRipper:**
- Sector-level decode happens in FPGA at wire speed (200 MHz)
- Decoded data available to SoC in real-time via AXI registers
- Enables drop-in FDC replacement for retro systems
- No host CPU involvement during read/write operations

**What "Software" means for other controllers:**
- Raw flux transitions streamed to host over USB
- Host software decodes asynchronously after capture
- Suitable for archival/imaging but not real-time FDC operation

### Encoding Decode Matrix

| Encoding | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| **MFM** | Hardware | Flux + SW | Flux + SW | Flux + SW |
| **FM** | Hardware | Flux + SW | Flux + SW | Flux + SW |
| **M2FM** | Hardware | Flux + SW | Flux + SW† | Flux + SW† |
| **GCR-Apple (6&2)** | Hardware | Flux + SW | Flux + SW | Flux + SW |
| **GCR-Apple (5&3)** | Hardware | Flux + SW | Flux + SW | Flux + SW |
| **GCR-CBM** | Hardware | Flux + SW | Flux + SW | Flux + SW |
| **Tandy FM** | Hardware | Flux + SW | Flux capture‡ | Flux capture‡ |
| **Agat** | Hardware | Flux capture‡ | Flux capture‡ | Flux capture‡ |

> **Legend:**
> - **Hardware** = Real-time FPGA decode, sector data available immediately
> - **Flux + SW** = Flux capture with built-in software decoder
> - **Flux capture‡** = Raw flux capture works; decode requires external/community tools

### Software Codec Support (via flux analysis)

| Encoding | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| Amiga MFM (11 SPT) | Yes | Yes | Yes | Yes |
| BBC DFS/ADFS | Yes | Yes | Yes | Yes |
| Brother WP | Flux capture | Yes | Yes | Yes |
| Victor 9000 (10 zone) | Flux capture | Software | Software | Software |
| Roland/E-mu samplers | Flux capture | Yes | Yes | Flux capture |

---

## 4. Platform/System Support

### Western Platforms

| Platform | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| **IBM PC (all)** | Native | Native | Native | Native |
| **Apple II** | Native (GCR) | Native | Native | Native |
| **Macintosh 400K/800K** | Native (+MAC_ZONE) | Via CLV decode | Software | Software |
| **Commodore 64/128** | Native (GCR-CBM) | Native | Native | Native |
| **Amiga** | Native (MFM) | Native | Native | Native |
| **Atari ST** | Native (MFM) | Native | Native | Native |
| **Atari 8-bit** | Native (FM/MFM) | Native | Native | Native |
| **BBC Micro** | Native (FM/MFM) | Native | Native | Native |
| **TRS-80** | Native (FM/MFM) | Native | Native | Native |
| **TRS-80 CoCo** | Native (Tandy FM) | Flux + SW | Flux capture‡ | Flux capture‡ |
| **Amstrad CPC/PCW** | Adapter (MFM) | Adapter | Adapter | Adapter |
| **Spectrum +3** | Adapter (MFM) | Adapter | Adapter | Adapter |
| **Sam Coupé** | Native (MFM) | Native | Native | Native |
| **MSX** | Native (MFM) | Native | Native | Native |
| **CP/M (generic)** | Native | Native | Native | Native |

### Japanese Platforms

| Platform | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| **NEC PC-8801** | Native (MFM) | Native | Native | Native |
| **NEC PC-9801** | Native (+TG43) | Native | Native | Native |
| **Sharp X68000** | Native (MFM) | Native | Native | Native |
| **Fujitsu FM-Towns** | Native (MFM/1M) | Native | Native | Native |
| **MSX2/2+** | Native (MFM) | Native | Native | Native |

### 8" / Minicomputer Platforms

| Platform | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| **CP/M 8"** | Native (+HEAD_LOAD) | Via FDADAP | Via FDADAP | Via adapter |
| **DEC RX01** | Native (FM) | Native | Native | Native |
| **DEC RX02** | Native (M2FM) | Native | Software | Software |
| **Intel MDS** | Native (M2FM) | Native | Software | Software |
| **Cromemco** | Native (M2FM) | Native | Software | Software |
| **Wang** | Native (+HEAD_LOAD) | Via FDADAP | Via FDADAP | Via adapter |
| **Xerox 820** | Native (+HEAD_LOAD) | Via FDADAP | Via FDADAP | Via adapter |

### Soviet/Eastern Bloc

| Platform | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| **Agat-7/9** | Native (Agat) | Flux capture‡ | Flux capture‡ | Flux capture‡ |
| **Robotron** | Native (MFM)§ | Native | Native | Native |

> §**Robotron note:** Robotron systems use standard MFM encoding — the "weirdness" is geometry/filesystem, not magnetic encoding. All controllers can image the media; FluxRipper's "any geometry" approach handles it natively.

### Hard-Sectored Systems

| Platform | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|----------|------------|----------|--------------|---------------|
| **NorthStar Horizon** | Native (/SECTOR) | Flux capture‡ | Yes (v1.18+) | Flux capture‡ |
| **Vector Graphics** | Native (/SECTOR) | Flux capture‡ | Yes (v1.18+) | Flux capture‡ |
| **Morrow Designs** | Native (/SECTOR) | Flux capture‡ | Yes (v1.18+) | Flux capture‡ |
| **Heath H-89** | Native (/SECTOR) | Flux capture‡ | Yes (v1.18+) | Flux capture‡ |

> ‡**Flux capture note:** Controllers without native hard-sector support can still capture the raw flux; sector hole timing must be reconstructed in software from flux patterns or external timing reference.

---

## 5. Software & File Formats

### Image Format Support

| Format | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|--------|------------|----------|--------------|---------------|
| **Raw sector (IMG/IMA)** | R/W | R/W | R/W | R/W |
| **KryoFlux stream** | Import | Native | R/W | Import |
| **SCP (SuperCard Pro)** | Import | Import | R/W | Native |
| **HFE** | R/W | No | R/W | No |
| **ADF (Amiga)** | R/W | R/W | R/W | R/W |
| **D64 (C64)** | R/W | R/W | R/W | R/W |
| **G64 (C64 GCR)** | R/W | R/W | R/W | R/W |
| **DSK/EDSK** | R/W | R/W | R/W | R/W |
| **IPF** | Read | R/W | Read | Read |
| **IMD** | R/W | R/W | R/W | No |
| **TD0 (Teledisk)** | Read | Read | Read | No |
| **A2R (Applesauce)** | Read | No | Read | No |
| **FDI/HDM (PC-98)** | R/W | R/W | R/W | No |
| **ST (Atari)** | R/W | R/W | R/W | R/W |
| **MSA** | R/W | R/W | R/W | R/W |
| **FluxRipper native** | Native | No | No | No |

> **FluxRipper native format:** Stores raw flux + DRIVE_PROFILE metadata + per-revolution quality metrics + optional decoded sector data. Richer than stream-only formats; designed for archival with automatic drive fingerprinting. Can export losslessly to KryoFlux/SCP streams and major sector formats (ADF, D64, IMG, etc.).

### Software Tools

| Feature | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|---------|------------|----------|--------------|---------------|
| **GUI** | Web UI (planned) | DTC GUI (Win) | FluxMyFluffyFloppy | SCP GUI |
| **CLI** | Yes | DTC | `gw` command | Yes |
| **Cross-platform** | Linux/embedded | Win/Mac/Linux | Win/Mac/Linux | Windows |
| **Open source tools** | Yes | No | Yes | Partial |
| **Driver required** | No (embedded) | Yes (Windows) | No | No |
| **API/SDK** | Yes (C/Verilog) | Limited | Python | Limited |

---

## 6. Copy Protection Handling

### Timing Resolution

| Controller | Resolution | Notes |
|------------|------------|-------|
| **FluxRipper** | 5 ns | Highest resolution; fine-grained timing side-channel analysis |
| **SuperCard Pro** | 25 ns | Second-best; good for most protection schemes |
| **GreaseWeazle** | ~14 ns | Good resolution at low cost |
| **KryoFlux** | ~41 ns | Adequate for most schemes; proven track record |

### Capability Matrix

| Capability | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|------------|------------|----------|--------------|---------------|
| **Weak bit read** | Yes (flux capture) | Yes | Yes | Yes |
| **Weak bit write** | Via flux stream | Via IPF | Via SCP/HFE | Yes |
| **Long tracks** | Yes | Yes | Yes | Yes |
| **Short tracks** | Yes | Yes | Yes | Yes |
| **Variable density** | Yes | Yes | Yes | Yes |
| **Sector timing** | Hardware + flux | Flux analysis | Flux analysis | Flux analysis |
| **IPF write-back** | No (roadmap) | Yes | No | Read only |
| **Disk-to-disk copy** | No | No | No | Yes |

> **IPF roadmap:** Long-term goal is IPF-to-native conversion + write-back via FluxRipper's flux engine. KryoFlux remains the gold standard for IPF workflows today.

### Copy Protection Systems Supported

| Protection | FluxRipper | KryoFlux | GreaseWeazle | SuperCard Pro |
|------------|------------|----------|--------------|---------------|
| RapidLok (C64) | Flux capture | Yes | Yes | Yes |
| V-MAX! (C64) | Flux capture | Yes | Yes | Yes |
| Vorpal (C64) | Flux capture | Yes | Yes | Yes |
| Rob Northen (Amiga) | Flux capture | Via IPF | Flux capture | Yes |
| Copylock (Amiga) | Flux capture | Via IPF | Flux capture | Yes |
| Dungeon Master (ST) | Flux capture | Via IPF | Flux capture | Yes |
| Sierra (PC) | Flux capture | Yes | Flux capture | Flux capture |
| Vault (PC) | Flux capture | Yes | Flux capture | Flux capture |

---

## 7. Unique Features

### FluxRipper Exclusive

**The Two Killer Features:**

| Feature | Why It Matters |
|---------|----------------|
| **82077AA-Compatible FDC** | Drop-in replacement for legacy systems. Real-time sector read/write via AXI registers — not a USB peripheral that needs host software. Build a retro PC clone, NeXT restoration, or industrial controller with actual floppy I/O. |
| **DRIVE_PROFILE Auto-Detection** | Single 32-bit register reports: form factor (3.5"/5.25"/8"), density (DD/HD/ED), track density (40/80/77), encoding (MFM/FM/GCR/M2FM/etc.), RPM, quality score. No manual config — plug in any drive, read the profile. |

**Additional Exclusive Features:**

| Feature | Description |
|---------|-------------|
| **Real-time hardware decode** | FPGA decodes MFM/FM/GCR/M2FM/Tandy/Agat at wire speed (200 MHz) |
| **Dual interface** | Two independent 34-pin buses (4 drives total) |
| **Native 8" signals** | HEAD_LOAD, /TG43, /SECTOR, DENSITY on dedicated GPIO |
| **Zone NCO (Mac GCR)** | Hardware variable-speed decode — no software post-processing |
| **Hard-sector native** | /SECTOR input with automatic flux stream tagging (bit 29) |
| **AXI interface** | Direct SoC/PCIe integration, embedded Linux, no USB overhead |
| **Resto-mod ready** | Designed to host experimental neo-floppy formats with heavy ECC |

### KryoFlux Exclusive

| Feature | Description |
|---------|-------------|
| **IPF write support** | Write copy-protected disks from IPF |
| **Software Preservation Society** | Direct connection to preservation community |
| **Comprehensive format database** | Largest tested format library |
| **Multi-format simultaneous output** | One pass → multiple image formats |

### GreaseWeazle Exclusive

| Feature | Description |
|---------|-------------|
| **Fully open source** | Hardware designs, firmware, software |
| **Low cost** | ~$35-50 for complete solution |
| **Easy Windows setup** | No custom drivers needed |
| **Flippy disk support** | Read both sides in single pass (modded drive) |
| **Extensive diskdef library** | Community-contributed format definitions |
| **Active development** | Frequent updates (v1.20 Sept 2024) |

### SuperCard Pro Exclusive

| Feature | Description |
|---------|-------------|
| **Disk-to-disk copy** | Direct duplication without PC |
| **Standalone operation** | Can run from serial/SD card |
| **25ns resolution** | Highest timing resolution |
| **512KB buffer** | Large internal capture buffer |
| **Drive emulator (planned)** | Future firmware will emulate drive |

---

## 8. Use Case Recommendations

### Best For Each Use Case

| Use Case | Recommended | Why |
|----------|-------------|-----|
| **Budget preservation** | GreaseWeazle | Low cost, open source, good format support |
| **Professional archival** | KryoFlux | IPF support, proven track record, SPS backing |
| **8" drives native** | FluxRipper | Native HEAD_LOAD, no adapter needed |
| **Hard-sectored media** | FluxRipper or GreaseWeazle | Native /SECTOR support |
| **Macintosh GCR** | FluxRipper | Hardware zone decode at full speed |
| **Real-time FDC replacement** | FluxRipper | 82077AA-compatible, AXI interface |
| **Soviet/Agat disks** | FluxRipper | Only controller with Agat encoding |
| **Quick disk copying** | SuperCard Pro | Direct disk-to-disk without PC |
| **Embedded systems** | FluxRipper | FPGA-based, AXI interface, no host OS |
| **Copy-protected Amiga/ST** | KryoFlux | IPF write-back support |
| **TRS-80 CoCo** | FluxRipper | Hardware Tandy FM decode |
| **Learning/experimentation** | GreaseWeazle | Open source, extensive documentation |
| **Japanese retro (PC-98)** | FluxRipper or GreaseWeazle | Native 77-track + TG43 |
| **DEC M2FM systems** | FluxRipper | Hardware M2FM decode |

### Decision Matrix

```
START
  │
  ├─ Building hardware that needs an actual FDC?
  │   └─ YES → FluxRipper (only option with 82077AA/AXI interface)
  │
  ├─ Need 8" with native HEAD_LOAD?
  │   └─ YES → FluxRipper
  │
  ├─ Need copy-protected IPF write-back?
  │   └─ YES → KryoFlux
  │
  ├─ Budget under $50?
  │   └─ YES → GreaseWeazle
  │
  ├─ Need disk-to-disk standalone copy?
  │   └─ YES → SuperCard Pro
  │
  ├─ Need Macintosh GCR at full speed?
  │   └─ YES → FluxRipper
  │
  ├─ Need hard-sectored (NorthStar etc)?
  │   └─ YES → FluxRipper or GreaseWeazle
  │
  ├─ Want hardware auto-detection (no manual config)?
  │   └─ YES → FluxRipper (DRIVE_PROFILE)
  │
  ├─ General preservation work?
  │   └─ Any will work; GreaseWeazle for cost, KryoFlux for ecosystem
  │
  └─ Default recommendation: GreaseWeazle (best value)
```

---

## Summary Comparison

| Category | Winner | Notes |
|----------|--------|-------|
| **Best value** | GreaseWeazle | ~$40, fully open source |
| **Best FDC replacement** | FluxRipper | Only option — 82077AA-compatible, AXI interface |
| **Best auto-detection** | FluxRipper | Hardware DRIVE_PROFILE vs manual config |
| **Best 8" support** | FluxRipper | Native HEAD_LOAD, no adapter |
| **Best copy protection** | KryoFlux | IPF ecosystem, proven workflows |
| **Best Mac GCR** | FluxRipper | Hardware zone decode at full speed |
| **Best hard-sector** | FluxRipper | Native /SECTOR + flux tagging |
| **Best embedded** | FluxRipper | FPGA + AXI, no host OS required |
| **Best standalone** | SuperCard Pro | Disk-to-disk without PC |
| **Best timing resolution** | FluxRipper | 5ns vs 25ns (SCP) vs 41ns (KF) |
| **Best documentation** | KryoFlux | Extensive manual, SPS resources |
| **Best community** | GreaseWeazle | Active GitHub, Discord |
| **Best open source** | GreaseWeazle | Full stack open |
| **Most platforms** | Tie | All support major platforms |

---

## Sources

- [KryoFlux Supported Formats](https://kryoflux.com/?page=kf_formats)
- [KryoFlux Manual](https://www.kryoflux.com/download/kryoflux_manual.pdf)
- [KryoFlux Features](https://kryoflux.com/?page=kf_features)
- [GreaseWeazle Wiki](https://github.com/keirf/greaseweazle/wiki)
- [GreaseWeazle Supported Image Types](https://github.com/keirf/greaseweazle/wiki/Supported-Image-Types)
- [GreaseWeazle Models](https://github.com/keirf/greaseweazle/wiki/Greaseweazle-Models)
- [GreaseWeazle Release Notes](https://github.com/keirf/greaseweazle/blob/master/RELEASE_NOTES)
- [SuperCard Pro Manual](https://www.cbmstuff.com/downloads/scp/scp_manual.pdf)
- [SuperCard Pro SCP Format Specs](https://www.cbmstuff.com/downloads/scp/scp_image_specs.txt)
- [FluxEngine Documentation](https://cowlark.com/fluxengine/index.html)
- [Comparison Discussion - AtariAge](https://forums.atariage.com/topic/307756-greaseweazle-new-diy-open-source-alternative-to-kryoflux-and-scp/)
- [KryoFlux 8" Drive Support Forum](https://forum.kryoflux.com/viewtopic.php?t=56)
- [Hard Sector Support - GreaseWeazle Issue #339](https://github.com/keirf/greaseweazle/issues/339)

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-03 | Initial comparison matrix |
| 1.1 | 2025-12-03 | Added FDC replacement & DRIVE_PROFILE to executive summary; clarified hardware vs software decode terminology; softened "No" to "Flux capture" where applicable; added timing resolution table; added signal terminology footnotes; enhanced unique features section |
