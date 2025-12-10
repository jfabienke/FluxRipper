# FluxRipper Image Format Support & Storage Architecture

**Date:** 2025-12-07 15:00
**Status:** Design Specification

---

## Storage Locations on the Board

FluxRipper has three storage tiers available for disk images:

| Tier | Media | Capacity | Speed | Use Case |
|------|-------|----------|-------|----------|
| **L1** | FPGA BRAM | 128 KB | 400 MB/s | Boot ROM, cache, real-time buffers |
| **L2** | HyperRAM | 8 MB | 333 MB/s | Active capture buffer, working memory |
| **L3** | MicroSD | 32 GB+ | 25-50 MB/s | Image archive, firmware, format databases |

### Storage Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FluxRipper Storage                                │
│                                                                         │
│  ┌───────────────┐    ┌───────────────┐    ┌───────────────────────┐   │
│  │   BRAM        │    │   HyperRAM    │    │      MicroSD          │   │
│  │   128 KB      │    │   8 MB        │    │      32 GB+           │   │
│  │               │    │               │    │                       │   │
│  │ • Boot ROM    │    │ • Track A buf │    │ /firmware/            │   │
│  │ • Option ROM  │    │ • Track B buf │    │ /formats/             │   │
│  │ • USB buffers │    │ • .text/.data │    │ /captures/            │   │
│  │ • Flux FIFO   │    │ • Format DB   │    │ /config/              │   │
│  └───────────────┘    └───────────────┘    └───────────────────────┘   │
│         ▲                    ▲                       ▲                  │
│         │                    │                       │                  │
│         └────────────────────┴───────────────────────┘                  │
│                              │                                          │
│                     ┌────────┴────────┐                                 │
│                     │   AXI Fabric    │                                 │
│                     └─────────────────┘                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Image Format Categories

### 1. Sector-Level Formats (Decoded Data)

These formats store decoded sector data — the logical file content.

| Format | Extension | Typical Size | Platform | Notes |
|--------|-----------|--------------|----------|-------|
| **Raw Sector** | `.img`, `.ima`, `.dsk` | 360K-2.88M | PC/DOS | Sector-by-sector dump |
| **CopyQM** | `.cqm` | Variable | PC | Compressed sector image |
| **Teledisk** | `.td0` | Variable | PC | Compressed, metadata |
| **D64** | `.d64` | 170-683 KB | C64 | 35/40 tracks, GCR decoded |
| **G64** | `.g64` | ~330 KB | C64 | GCR-encoded track data |
| **ADF** | `.adf` | 880K-1.76M | Amiga | OFS/FFS decoded sectors |
| **HFE** | `.hfe` | Variable | Universal | SD HxC format |
| **ST** | `.st`, `.msa` | 360K-1.4M | Atari ST | Raw/compressed |
| **DSK** | `.dsk` | 180K-800K | CPC/Spectrum | CPCEMU format |

### 2. Flux-Level Formats (Raw Magnetic Data)

These formats preserve raw magnetic transitions — essential for copy protection and archival.

| Format | Extension | Data Per Track | Features |
|--------|-----------|----------------|----------|
| **KryoFlux Stream** | `.raw` | ~50-150 KB | Index timing, OOB messages |
| **SuperCard Pro** | `.scp` | ~100-200 KB | Multi-revolution, checksums |
| **IPF** | `.ipf` | Variable | CAPS format, protection metadata |
| **Flux** | `.flux` | Variable | FluxRipper native |
| **CTRaw** | `.ctr` | Variable | CatWeasel format |

### 3. Hybrid/Container Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| **86F** | `.86f` | PCem format, sector + flux |
| **FDI** | `.fdi` | Formatted Disk Image, multi-platform |
| **WOZ** | `.woz` | Apple II preservation (flux-level) |

---

## Recommended Format Support Matrix

### Priority 1: Must Have (Native Support)

| Format | Read | Write | Reason |
|--------|:----:|:-----:|--------|
| **Raw Sector** (.img/.ima) | ✅ | ✅ | Universal compatibility |
| **KryoFlux Stream** (.raw) | ✅ | ✅ | DTC compatibility (already implemented) |
| **FluxRipper Native** (.flux) | ✅ | ✅ | Native format, full metadata |
| **SuperCard Pro** (.scp) | ✅ | ✅ | Popular flux format |
| **IPF** (.ipf) | ✅ | ❌ | CAPS/SPS archival standard |
| **ADF** (.adf) | ✅ | ✅ | Amiga preservation |
| **D64/G64** | ✅ | ✅ | C64 preservation |

### Priority 2: Should Have

| Format | Read | Write | Reason |
|--------|:----:|:-----:|--------|
| **HFE** (.hfe) | ✅ | ✅ | SD HxC compatibility |
| **WOZ** (.woz) | ✅ | ✅ | Apple II preservation |
| **DSK** (.dsk) | ✅ | ✅ | CPC/Spectrum |
| **ST/MSA** | ✅ | ✅ | Atari ST |
| **86F** | ✅ | ✅ | PCem emulator |

### Priority 3: Nice to Have

| Format | Read | Write | Reason |
|--------|:----:|:-----:|--------|
| **Teledisk** (.td0) | ✅ | ❌ | Legacy archives |
| **CopyQM** (.cqm) | ✅ | ❌ | Legacy DOS |
| **FDI** | ✅ | ✅ | Multi-platform |
| **CTRaw** | ✅ | ❌ | CatWeasel compatibility |

---

## Native FluxRipper Format (.flux)

### Design Goals

1. **Complete preservation** — All timing, metadata, signal quality
2. **Efficient storage** — Delta encoding, optional compression
3. **Random access** — Seek to any track quickly
4. **Extensible** — Version field, optional chunks

### File Structure

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FluxRipper .flux Format                          │
├─────────────────────────────────────────────────────────────────────────┤
│ HEADER (64 bytes)                                                       │
│   Magic: "FLUX" (4 bytes)                                               │
│   Version: 1.0 (2 bytes)                                                │
│   Flags: (2 bytes)                                                      │
│   Track count: (2 bytes)                                                │
│   Head count: (1 byte)                                                  │
│   Sample rate: (4 bytes, Hz)                                            │
│   Creation timestamp: (8 bytes, Unix epoch)                             │
│   Drive fingerprint hash: (16 bytes, MD5)                               │
│   Reserved: (25 bytes)                                                  │
├─────────────────────────────────────────────────────────────────────────┤
│ TRACK INDEX (8 bytes × track_count × head_count)                        │
│   Track N, Head H:                                                      │
│     Offset: (4 bytes, from file start)                                  │
│     Length: (4 bytes, compressed size)                                  │
├─────────────────────────────────────────────────────────────────────────┤
│ METADATA CHUNK (optional, variable)                                     │
│   Chunk ID: "META" (4 bytes)                                            │
│   Length: (4 bytes)                                                     │
│   JSON metadata: { "disk_label": "...", "notes": "..." }               │
├─────────────────────────────────────────────────────────────────────────┤
│ TRACK DATA (repeated for each track)                                    │
│   Track Header:                                                         │
│     Revolution count: (1 byte)                                          │
│     Quality score: (1 byte, 0-100)                                      │
│     Flags: (1 byte)                                                     │
│     Encoding detected: (1 byte)                                         │
│   Per-Revolution Data:                                                  │
│     Index-to-index time: (4 bytes, sample clocks)                       │
│     Transition count: (4 bytes)                                         │
│     Flux deltas: (variable, delta-encoded)                              │
├─────────────────────────────────────────────────────────────────────────┤
│ CHECKSUM (4 bytes, CRC32)                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Encoding Scheme

Flux timing deltas use variable-length encoding:

| Delta Range | Encoding | Bytes |
|-------------|----------|-------|
| 0-127 | 0xxxxxxx | 1 |
| 128-16383 | 10xxxxxx xxxxxxxx | 2 |
| 16384-2097151 | 110xxxxx xxxxxxxx xxxxxxxx | 3 |
| 2097152+ | 111xxxxx + 4-byte value | 5 |

---

## KryoFlux Compatibility

FluxRipper already implements the KryoFlux stream protocol (`kf_protocol.v`):

### Stream Format Codes
```
0x00-0x07: FLUX2 (accumulator)
0x08-0x0A: NOP1/NOP2/NOP3
0x0B:      OVL16 (overflow)
0x0C:      FLUX3 (16-bit)
0x0D:      OOB (out-of-band)
0x0E-0xFF: FLUX1 (single byte)
```

### OOB Messages
```
0x01: Stream Info
0x02: Index
0x03: Stream End
0x0D: EOF
```

### USB Command Codes (OpenDTC)
```
0x05: Reset
0x06: Device select
0x07: Motor control
0x08: Density
0x09: Side select
0x0A: Track seek
0x0B: Stream start/stop
0x80: Status query
0x81: Device info
```

---

## SuperCard Pro Format (.scp)

### File Structure

```
Offset  Size  Description
0x00    3     Signature "SCP"
0x03    1     Version/Revision
0x04    1     Disk type
0x05    1     Number of revolutions
0x06    1     Start track
0x07    1     End track
0x08    1     Flags
0x09    1     Bit cell encoding
0x0A    1     Number of heads
0x0B    1     Resolution (25ns units)
0x0C    4     Checksum
0x10    4×N   Track data offsets

Track Header (at offset):
0x00    3     "TRK"
0x03    1     Track number
0x04    4×R   Revolution data lengths
0x??    N     Flux data (16-bit big-endian)
```

### Implementation Notes

- 16-bit flux values in 25ns units
- Multiple revolutions per track
- Checksum validation
- Supports up to 168 tracks (84 cylinders × 2 heads)

---

## IPF Format (CAPS/SPS)

### Overview

IPF (Interchangeable Preservation Format) is the gold standard for preservation:

- Developed by Software Preservation Society (SPS)
- Stores decoded track data + timing + protection metadata
- Handles weak bits, long tracks, density variations
- Used by major preservation projects (TOSEC, No-Intro)

### FluxRipper Integration

- **Read**: Full IPF support via CAPSImg library (already in repo)
- **Write**: Not supported (proprietary encoder)
- **Playback**: Convert IPF → flux for writing to media

### CAPSImg Library Usage

```c
#include "CapsLib.h"

// Initialize
CAPSInit();

// Load IPF
int container = CAPSAddImage();
CAPSLockImage(container, "disk.ipf");

// Read track
CapsTrackInfoT2 track_info;
CAPSLockTrack(&track_info, container, cylinder, head,
              DI_LOCK_TYPE | DI_LOCK_DENVAR);

// Access flux/timing data
uint8_t* track_data = track_info.trackdata;
uint32_t track_len = track_info.tracklen;
```

---

## Storage Allocation

### MicroSD Directory Structure

```
/
├── firmware/
│   ├── fluxripper.bit          # FPGA bitstream
│   └── firmware.bin            # RISC-V firmware
│
├── formats/
│   ├── amiga.fdb               # Amiga format signatures
│   ├── pc.fdb                  # PC format signatures
│   ├── c64.fdb                 # C64/GCR signatures
│   ├── apple.fdb               # Apple II signatures
│   └── protection.fdb          # Copy protection database
│
├── images/
│   ├── floppy/
│   │   ├── dos/                # PC DOS images
│   │   ├── amiga/              # Amiga ADFs
│   │   ├── c64/                # D64/G64 files
│   │   └── flux/               # Raw flux captures
│   │
│   └── hdd/
│       ├── st506/              # ST-506 MFM images
│       └── esdi/               # ESDI images
│
├── captures/
│   └── YYYY-MM-DD/
│       ├── session_001.flux    # Capture session
│       ├── session_001.log     # Session log
│       └── session_001.json    # Metadata
│
├── config/
│   ├── settings.cfg            # User preferences
│   ├── profiles/               # Drive profiles
│   └── precomp/                # Write precompensation
│
└── logs/
    ├── system.log
    └── errors.log
```

### HyperRAM Buffer Allocation

| Region | Address | Size | Purpose |
|--------|---------|------|---------|
| .text | 0x4000_0000 | 2 MB | Firmware code |
| .data/.bss | 0x4020_0000 | 1 MB | Heap, globals |
| Format DB | 0x4030_0000 | 512 KB | Loaded from SD |
| Precomp | 0x4038_0000 | 256 KB | Write precomp tables |
| Scratch | 0x403C_0000 | 256 KB | Temporary work |
| **Track Buffer A** | 0x4040_0000 | 2 MB | Active capture |
| **Track Buffer B** | 0x4060_0000 | 2 MB | Double-buffer |

### Image Size Estimates

| Media Type | Sector Format | Flux Format | Notes |
|------------|---------------|-------------|-------|
| 360K DD FDD | 360 KB | ~3 MB | 40 tracks × 2 sides |
| 720K DD FDD | 720 KB | ~6 MB | 80 tracks × 2 sides |
| 1.44M HD FDD | 1.44 MB | ~12 MB | 80 tracks × 2 sides |
| 20MB ST-506 | 20 MB | ~200 MB | MFM HDD |
| 40MB RLL | 40 MB | ~300 MB | RLL HDD |

---

## USB Mass Storage Mode

When connected via USB, FluxRipper can expose the MicroSD as a mass storage device:

### LUN Mapping

| LUN | Device | Mode |
|-----|--------|------|
| 0 | MicroSD | Read/Write filesystem |
| 1 | Virtual FDD | Mounted image file |
| 2 | Virtual HDD | Mounted image file |

### Image Mounting

```
# Mount an image for emulation
fluxripper mount /images/floppy/dos/dos622.img --lun 1

# Host sees:
#   - LUN 0: SD card filesystem
#   - LUN 1: DOS 6.22 boot disk (read-only)
```

---

## Real-Time Capture Workflow

### Capture to HyperRAM → Save to SD

```
1. Start capture
   └─► Flux data → Track Buffer A (HyperRAM)

2. Index pulse detected
   └─► Swap buffers (A ↔ B)
   └─► DMA: Buffer B → MicroSD (background)

3. Continue capture to new buffer
   └─► Repeat until complete

4. Finalize
   └─► Write file header
   └─► Calculate checksum
   └─► Close file
```

### Memory Requirements

- **Single track capture**: ~150 KB (flux data + overhead)
- **Full disk buffer**: ~12 MB (1.44M HD, 2 revolutions/track)
- **Available HyperRAM**: 4 MB for track buffers (A+B)
- **Strategy**: Stream to SD during capture, use double-buffering

---

## Format Conversion Pipeline

### Inbound (Read Physical → Image File)

```
Physical Disk
     │
     ▼
┌─────────────┐
│ Flux Capture│ → .flux (native)
│ @ 200-400MHz│
└─────────────┘
     │
     ▼
┌─────────────┐
│ Format      │ → Detect encoding (MFM/FM/GCR)
│ Detection   │ → Identify protection
└─────────────┘
     │
     ├─► .flux (archival, full fidelity)
     ├─► .scp  (SuperCard Pro compatible)
     ├─► .raw  (KryoFlux compatible)
     ├─► .img  (sector dump, if clean read)
     └─► .ipf  (via external tools only)
```

### Outbound (Image File → Physical Disk)

```
Image File (.flux, .scp, .img, .adf, .d64, etc.)
     │
     ▼
┌─────────────┐
│ Format      │ → Parse container
│ Reader      │ → Extract track data
└─────────────┘
     │
     ▼
┌─────────────┐
│ Flux        │ → Convert to flux timing
│ Generator   │ → Apply write precomp
└─────────────┘
     │
     ▼
Physical Disk
```

---

## API for Image Handling

### C API

```c
// Open image file
flux_image_t* flux_image_open(const char* path, uint32_t flags);

// Get format info
int flux_image_get_format(flux_image_t* img, flux_format_info_t* info);

// Read track (decoded sectors)
int flux_image_read_track(flux_image_t* img,
                          uint8_t cyl, uint8_t head,
                          uint8_t* buffer, size_t* len);

// Read track (raw flux)
int flux_image_read_flux(flux_image_t* img,
                         uint8_t cyl, uint8_t head,
                         flux_track_t* flux);

// Write track
int flux_image_write_track(flux_image_t* img,
                           uint8_t cyl, uint8_t head,
                           const flux_track_t* flux);

// Close
void flux_image_close(flux_image_t* img);

// Supported formats
typedef enum {
    FLUX_FMT_NATIVE,    // .flux
    FLUX_FMT_SCP,       // .scp
    FLUX_FMT_KRYOFLUX,  // .raw
    FLUX_FMT_IPF,       // .ipf (read only)
    FLUX_FMT_IMG,       // .img/.ima
    FLUX_FMT_ADF,       // .adf
    FLUX_FMT_D64,       // .d64
    FLUX_FMT_G64,       // .g64
    FLUX_FMT_HFE,       // .hfe
    FLUX_FMT_WOZ,       // .woz
    FLUX_FMT_DSK,       // .dsk
    FLUX_FMT_AUTO       // Auto-detect
} flux_format_t;
```

---

## Summary

### What to Support

| Priority | Formats | Reason |
|----------|---------|--------|
| **P0** | .flux, .img, .raw, .scp | Core functionality |
| **P1** | .ipf, .adf, .d64/.g64 | Major platforms |
| **P2** | .hfe, .woz, .dsk | Extended compatibility |
| **P3** | .td0, .cqm, .fdi | Legacy support |

### Where to Store

| Storage | Use For |
|---------|---------|
| **HyperRAM** | Active capture buffers, working memory |
| **MicroSD** | Permanent image storage, archives |
| **USB MSC** | Host access to SD card + virtual drives |

### Key Design Decisions

1. **Native format (.flux)** optimized for FluxRipper's capabilities
2. **KryoFlux compatibility** already implemented in RTL
3. **IPF via CAPSImg** library (already in repo)
4. **Streaming capture** to SD via double-buffering in HyperRAM
5. **USB MSC** exposes both SD filesystem and virtual mounted images

---

## Revision History

| Date | Changes |
|------|---------|
| 2025-12-07 | Initial image format and storage specification |
