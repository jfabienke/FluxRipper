# FluxRipper Drive Detection & Fingerprinting System

*Document Version: 1.1*
*Updated: 2025-12-03 15:45*

## Overview

FluxRipper implements a multi-layered drive detection system that automatically identifies floppy drive characteristics without requiring user configuration. The system uses passive observation of electrical signals combined with active probing to build a comprehensive drive profile.

This document describes the detection methods, fingerprinting algorithms, and heuristic decision trees used to classify drives.

---

## Table of Contents

1. [Detection Architecture](#1-detection-architecture)
2. [Signal-Based Detection (Layer 1)](#2-signal-based-detection-layer-1)
3. [Behavioral Analysis (Layer 2)](#3-behavioral-analysis-layer-2)
4. [Form Factor Inference (Layer 3)](#4-form-factor-inference-layer-3)
5. [Drive Profile Register](#5-drive-profile-register)
6. [Detection Confidence Levels](#6-detection-confidence-levels)
7. [Limitations](#7-limitations)
8. [Software Integration](#8-software-integration)

---

## 1. Detection Architecture

### 1.1 Layered Detection Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 3: Form Factor Inference               │
│         (Combines all signals to determine drive type)          │
│                                                                 │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │              LAYER 2: Behavioral Analysis               │  │
│    │   (Data rate probing, encoding detection, track width)  │  │
│    │                                                         │  │
│    │    ┌─────────────────────────────────────────────────┐  │  │
│    │    │         LAYER 1: Signal Detection              │  │  │
│    │    │  (RPM, READY, TRK00, WPT, INDEX, HEAD_LOAD)    │  │  │
│    │    └─────────────────────────────────────────────────┘  │  │
│    └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    DRIVE_PROFILE Register
                    (32-bit packed result)
```

### 1.2 Module Hierarchy

| Module | Location | Purpose |
|--------|----------|---------|
| `index_handler_dual` | `rtl/drive_ctrl/` | RPM detection from index timing |
| `track_width_analyzer` | `rtl/drive_ctrl/` | 40/80-track detection |
| `flux_analyzer` | `rtl/diagnostics/` | Data rate detection |
| `encoding_detector` | `rtl/encoding/` | Encoding auto-selection |
| `drive_profile_detector` | `rtl/diagnostics/` | Profile aggregation |
| `density_probe_ctrl` | `rtl/diagnostics/` | Active density testing |

---

## 2. Signal-Based Detection (Layer 1)

Layer 1 detects drive characteristics through direct observation of Shugart interface signals. These are high-confidence measurements requiring no interpretation.

### 2.1 RPM Detection

**Method:** Measure time between INDEX pulses

**Implementation:** `index_handler_dual.v`

```
At 200 MHz system clock:
  300 RPM → 200ms/revolution → 40,000,000 clocks
  360 RPM → 166.67ms/revolution → 33,333,333 clocks

Tolerance: ±5% (accounts for motor speed variation)
```

**Thresholds:**
```verilog
rpm_300_min = clk_freq / 5 * 95 / 100;   // 190ms
rpm_300_max = clk_freq / 5 * 105 / 100;  // 210ms
rpm_360_min = clk_freq * 10 / 60 * 95 / 100;   // 158ms
rpm_360_max = clk_freq * 10 / 60 * 105 / 100;  // 175ms
```

**Output Signals:**
- `rpm_valid[3:0]` - RPM measurement valid (per drive)
- `rpm_300[3:0]` - Detected 300 RPM
- `rpm_360[3:0]` - Detected 360 RPM

**Accuracy:** ~99%

### 2.2 Drive Status Signals

| Signal | Detection | Accuracy |
|--------|-----------|----------|
| `/READY` | Direct input | 100% |
| `/TRK00` | Direct input | 100% |
| `/WPT` (Write Protect) | Direct input | 100% |
| `/INDEX` presence | Pulse count > 0 in 500ms | 99% |

### 2.3 HEAD_LOAD Detection

**Purpose:** Distinguish 8" drives from 5.25" HD drives (both are 360 RPM)

**Method:** Monitor HEAD_LOAD output signal activity during read operations

```
8" drives (Shugart SA800/850):
  - Require HEAD_LOAD assertion before head contacts media
  - Head load solenoid needs ~35ms to engage
  - Reads fail without HEAD_LOAD

5.25" HD drives:
  - HEAD_LOAD signal has no effect
  - Head is always in contact when disk inserted
```

**Detection Logic:**
```verilog
// If HEAD_LOAD is being driven AND drive is 360 RPM
if (head_load_active && rpm_360)
    inferred_form_factor = FF_8;  // 8" drive
else if (rpm_360)
    inferred_form_factor = FF_5_25;  // 5.25" HD
```

### 2.4 Hard-Sector Detection

**Purpose:** Identify hard-sectored media (NorthStar, Vector Graphics, etc.)

**Method:** Count `/SECTOR` pulses per revolution

**Implementation:** Sector pulse flag in flux capture stream (bit 29)

| Sector Count | System |
|--------------|--------|
| 0 | Soft-sectored (most drives) |
| 10 | NorthStar |
| 16 | Vector Graphics, some S-100 |
| 32 | Rare variants |

---

## 3. Behavioral Analysis (Layer 2)

Layer 2 performs active analysis of disk data to determine media and drive characteristics.

### 3.1 Track Density Detection (40T vs 80T)

**Purpose:** Detect 40-track disks in 80-track drives to enable double-stepping

**Method:** Compare logical cylinder (from sector ID field) with physical track position

**Implementation:** `track_width_analyzer.v` within `fdc_core_instance.v`

**Algorithm:**
```
For each sector ID field read:
  1. Extract cylinder number from ID (logical cylinder)
  2. Compare with step_controller's physical_track
  3. If cylinder == physical_track/2 consistently → 40-track disk

Detection requires 8 consistent samples for confidence.
```

**Example - 40-track disk in 80-track drive:**
```
Physical Track 0  → ID Cylinder 0  (match, inconclusive)
Physical Track 2  → ID Cylinder 1  (mismatch! cyl should be 2)
Physical Track 4  → ID Cylinder 2  (mismatch!)
Physical Track 6  → ID Cylinder 3  (mismatch!)
...
After 8 mismatches → double_step_recommended = 1
```

**Output Signals:**
- `track_density_detected` - Analysis complete
- `detected_40_track` - 1 if 40-track disk detected

**Accuracy:** ~95%

### 3.2 Data Rate Detection

**Purpose:** Determine media density (DD/HD/ED) by measuring flux transition timing

**Method:** Statistical analysis of flux interval distribution

**Implementation:** `flux_analyzer.v`

**Bit Cell Timing (at 200 MHz clock):**
```
Data Rate    Bit Cell     Clock Counts    Typical Interval Range
─────────────────────────────────────────────────────────────────
250 Kbps     4.0 µs       800 clocks      600-1000 (T1-T3)
300 Kbps     3.33 µs      667 clocks      500-833
500 Kbps     2.0 µs       400 clocks      300-500
1 Mbps       1.0 µs       200 clocks      150-250
```

**Detection Thresholds:**
```verilog
localparam THRESH_1M_500K   = 16'd300;   // 1.5µs boundary
localparam THRESH_500K_300K = 16'd530;   // 2.65µs boundary
localparam THRESH_300K_250K = 16'd730;   // 3.65µs boundary

if (avg_interval < THRESH_1M_500K)
    detected_rate = 2'b11;  // 1 Mbps
else if (avg_interval < THRESH_500K_300K)
    detected_rate = 2'b10;  // 500 Kbps
else if (avg_interval < THRESH_300K_250K)
    detected_rate = 2'b01;  // 300 Kbps
else
    detected_rate = 2'b00;  // 250 Kbps
```

**Lock Criteria:** Rate stable for 256 consecutive samples

### 3.3 Encoding Detection

**Purpose:** Auto-select between MFM, FM, GCR, M2FM, etc.

**Method:** Pattern matching on sync/address mark sequences

**Implementation:** `encoding_detector.v`

**Sync Patterns:**
```
Encoding    Sync Pattern              Distinctiveness
────────────────────────────────────────────────────────
MFM         A1 A1 A1 (clock violation)    Medium
FM          C7 (clock pattern)            Low
GCR-Apple   D5 AA 96/AD                   Very High
GCR-CBM     FF FF FF... (10 bytes)        High
M2FM        F7 7A                         High
Tandy FM    FE/FB/F8 (specific AMs)       Medium
```

**Priority Order:** (most distinctive patterns have highest priority)
1. GCR-Apple (D5 AA xx) - Very distinctive 3-byte prologue
2. GCR-CBM (10-byte 0xFF sync) - Long distinctive run
3. M2FM (F77A) - Unique to DEC/Intel
4. Tandy FM - Specific address mark sequence
5. MFM (A1 A1 A1) - Most common, lowest priority
6. FM - Fallback

**Lock Criteria:** 3 consecutive matches of same encoding

### 3.4 Active Density Probing

**Purpose:** Definitively determine drive density capability by attempting reads

**Method:** Sequentially test data rates and check for successful PLL lock + sync detection

**Implementation:** `density_probe_ctrl.v`

**Probe Sequence:**
```
1. Try 500 Kbps (most common HD rate)
   ├── Success → Try 1 Mbps (ED test)
   │   ├── Success → Drive is ED capable
   │   └── Fail → Drive is HD capable
   └── Fail → Try 250 Kbps
       ├── Success → Try 300 Kbps
       │   └── (Record both results)
       └── Fail → Try 300 Kbps alone
```

**Success Criteria:**
- PLL locks within 780µs
- Sync pattern detected within 3ms

**Non-Destructive:** All probing uses read operations only

---

## 4. Form Factor Inference (Layer 3)

Layer 3 combines all detection results to infer the drive's physical form factor.

### 4.1 Decision Tree

```
                        ┌──────────────┐
                        │  RPM Valid?  │
                        └──────┬───────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                 ▼
        ┌──────────┐                      ┌──────────┐
        │ 360 RPM  │                      │ 300 RPM  │
        └────┬─────┘                      └────┬─────┘
             │                                  │
    ┌────────┴────────┐            ┌───────────┼───────────┐
    ▼                 ▼            ▼           ▼           ▼
┌─────────┐    ┌──────────┐   ┌────────┐ ┌─────────┐ ┌──────────┐
│HEAD_LOAD│    │No HEAD   │   │500K/1M │ │Apple/CBM│ │DD Only   │
│ Active  │    │  LOAD    │   │ Works  │ │  GCR    │ │(250/300K)│
└────┬────┘    └────┬─────┘   └───┬────┘ └────┬────┘ └────┬─────┘
     │              │             │           │           │
     ▼              ▼             ▼           ▼           ▼
  ┌─────┐      ┌────────┐    ┌───────┐   ┌────────┐   ┌───────┐
  │ 8"  │      │5.25" HD│    │3.5" HD│   │5.25" DD│   │3.5" DD│
  │95%  │      │  90%   │    │  85%  │   │  80%   │   │  70%  │
  └─────┘      └────────┘    └───────┘   └────────┘   └───────┘
```

### 4.2 Inference Rules

**Implementation:** `drive_profile_detector.v`

```verilog
// Form factor inference logic
always @(*) begin
    inferred_form_factor = FF_UNKNOWN;
    ff_confidence = 8'd0;

    if (rpm_valid) begin
        if (rpm_360) begin
            // 360 RPM: Could be 8" or 5.25" HD
            if (head_load_active) begin
                inferred_form_factor = FF_8;      // 8" drive
                ff_confidence = 8'd95;
            end else begin
                inferred_form_factor = FF_5_25;   // 5.25" HD
                ff_confidence = 8'd90;
            end
        end else if (rpm_300) begin
            // 300 RPM: 3.5" or 5.25" DD
            if (can_500k || can_1m) begin
                inferred_form_factor = FF_3_5;    // 3.5" HD/ED
                ff_confidence = 8'd85;
            end else if (encoding == GCR_APPLE || encoding == GCR_CBM) begin
                inferred_form_factor = FF_5_25;   // Apple II or C64
                ff_confidence = 8'd80;
            end else begin
                inferred_form_factor = FF_3_5;    // Default: 3.5" DD
                ff_confidence = 8'd70;
            end
        end
    end
end
```

### 4.3 Density Capability Inference

```verilog
// Density capability inference
always @(*) begin
    if (can_1m)
        inferred_density = DENS_ED;    // 2.88 MB ED
    else if (can_500k)
        inferred_density = DENS_HD;    // HD capable
    else if (can_250k || can_300k)
        inferred_density = DENS_DD;    // DD only
    else
        inferred_density = DENS_UNK;   // Unknown
end
```

### 4.4 Track Count Inference

```verilog
// Track count inference
always @(*) begin
    if (track_density_valid) begin
        if (detected_40_track)
            inferred_track_density = TRACKS_40;
        else if (inferred_form_factor == FF_8)
            inferred_track_density = TRACKS_77;  // 8" standard
        else
            inferred_track_density = TRACKS_80;
    end else if (inferred_form_factor == FF_8) begin
        inferred_track_density = TRACKS_77;      // Default for 8"
    end else begin
        inferred_track_density = TRACKS_UNK;
    end
end
```

---

## 5. Drive Profile Register

### 5.1 Register Addresses

| Address | Name | Access |
|---------|------|--------|
| 0x68 | DRIVE_PROFILE_A | Read-Only |
| 0x74 | DRIVE_PROFILE_B | Read-Only |

### 5.2 Bit Field Layout

```
 31      24 23      16 15 14 13 12 11 10  9  8   6 5   4 3   2 1   0
┌─────────┬──────────┬──┬──┬─────┬──┬──┬──┬──────┬─────┬─────┬─────┐
│ Quality │ RPM/10   │PV│PL│Rsvd │HL│VZ│HS│ Enc  │TrkD │Dens │ FF  │
└─────────┴──────────┴──┴──┴─────┴──┴──┴──┴──────┴─────┴─────┴─────┘
```

### 5.3 Field Definitions

| Bits | Name | Values |
|------|------|--------|
| [1:0] | Form Factor (FF) | 00=Unknown, 01=3.5", 10=5.25", 11=8" |
| [3:2] | Density Cap (Dens) | 00=DD, 01=HD, 10=ED, 11=Unknown |
| [5:4] | Track Density (TrkD) | 00=40T, 01=80T, 10=77T, 11=Unknown |
| [8:6] | Encoding (Enc) | 000=MFM, 001=FM, 010=GCR-CBM, 011=GCR-Apple, 100=GCR-Apple5, 101=M2FM, 110=Tandy, 111=Agat |
| [9] | Hard-Sectored (HS) | 1 = Hard-sectored media detected |
| [10] | Variable-Speed (VZ) | 1 = Mac GCR zones detected |
| [11] | HEAD_LOAD (HL) | 1 = 8" drive (HEAD_LOAD required) |
| [13:12] | Reserved | - |
| [14] | Profile Locked (PL) | 1 = High-confidence detection complete |
| [15] | Profile Valid (PV) | 1 = Detection complete, profile data valid |
| [23:16] | RPM/10 | 30=300 RPM, 36=360 RPM |
| [31:24] | Quality Score | 0-255 composite quality metric |

> **Software Tip:** Check bit 15 (PV) first — if 0, the profile is not yet valid. Check bit 14 (PL) for high-confidence results suitable for auto-configuration.

### 5.4 Example Profile Values

```
3.5" HD MFM disk (locked):
  Profile = 0xC81EC005
  Quality=200, RPM=300, PV=1, PL=1, Enc=MFM, TrkD=80, Dens=HD, FF=3.5"

8" FM disk (locked):
  Profile = 0xB424C84F
  Quality=180, RPM=360, PV=1, PL=1, HL=1, Enc=FM, TrkD=77, Dens=DD, FF=8"

Apple II GCR disk (valid, not yet locked):
  Profile = 0xB91E80CA
  Quality=185, RPM=300, PV=1, PL=0, Enc=GCR-Apple, TrkD=40, Dens=DD, FF=5.25"

No disk / detection pending:
  Profile = 0x00000000
  PV=0, PL=0 — profile not valid, wait for detection
```

---

## 6. Detection Confidence Levels

### 6.1 Confidence Matrix

| Detection | Confidence | Notes |
|-----------|------------|-------|
| RPM (300/360) | 99% | Hardware timing measurement |
| Drive Ready | 100% | Direct signal |
| Write Protect | 100% | Direct signal |
| Track 0 | 100% | Direct signal |
| 8" vs 5.25" HD | 95% | HEAD_LOAD distinguishes |
| 3.5" HD | 85% | Density test confirms |
| 5.25" DD (Apple/CBM) | 80% | Encoding confirms |
| 3.5" DD vs 5.25" DD | 70% | Ambiguous without encoding |
| 40T vs 80T | 95% | ID field comparison |
| Encoding | 95% | Multiple sync matches |
| Hard-sectored | 100% | SECTOR pulses present |

### 6.2 Ambiguous Cases

The following cases require manual user confirmation:

1. **300 RPM + DD + MFM**: Could be 3.5" DD or 5.25" DD
   - Default: 3.5" (more common modern drive)
   - Override: User selects 5.25" if using older equipment

2. **360 RPM + No HEAD_LOAD response**: Could be 5.25" HD or 8" with stuck solenoid
   - Default: 5.25" HD
   - Override: User confirms 8" if head not loading

3. **Platform-specific formats**: Same geometry, different systems
   - IBM PC vs Atari ST (both MFM, 512-byte sectors)
   - Detected: MFM encoding
   - Platform: User specifies or software detects from filesystem

---

## 7. Limitations

### 7.1 Cannot Detect

| Information | Reason |
|-------------|--------|
| Vendor (Sony, TEAC, etc.) | No identification protocol in Shugart interface |
| Model number | No query mechanism |
| Serial number | Not accessible |
| Firmware version | Not queryable |
| Physical head width | Must infer from track density |
| Exact step timing | Varies by model, not exposed |

### 7.2 Requires Active Probing

| Detection | Why |
|-----------|-----|
| Density capability | Must attempt read at each rate |
| Track density | Must read sector ID fields |
| Encoding | Must see sync patterns |

### 7.3 Edge Cases

| Case | Handling |
|------|----------|
| No disk inserted | profile_valid = 0 |
| Motor not spinning | rpm_valid = 0, wait for spinup |
| Unformatted disk | encoding_valid = 0, density_cap = unknown |
| Damaged media | quality_score reflects PLL stability |

---

## 8. Software Integration

### 8.1 Reading Drive Profile

```c
// C code example for MicroBlaze
#include "fluxripper.h"

#define DRIVE_PROFILE_A  0x68
#define DRIVE_PROFILE_B  0x74

typedef struct {
    uint8_t form_factor;    // 0=unk, 1=3.5", 2=5.25", 3=8"
    uint8_t density_cap;    // 0=DD, 1=HD, 2=ED, 3=unk
    uint8_t track_density;  // 0=40T, 1=80T, 2=77T, 3=unk
    uint8_t encoding;       // 0=MFM, 1=FM, 2=CBM, 3=Apple...
    bool    hard_sectored;
    bool    variable_speed;
    bool    needs_head_load;
    uint8_t rpm_div10;      // 30=300, 36=360
    uint8_t quality;        // 0-255
} drive_profile_t;

drive_profile_t parse_profile(uint32_t raw) {
    drive_profile_t p;
    p.form_factor    = (raw >> 0) & 0x3;
    p.density_cap    = (raw >> 2) & 0x3;
    p.track_density  = (raw >> 4) & 0x3;
    p.encoding       = (raw >> 6) & 0x7;
    p.hard_sectored  = (raw >> 9) & 0x1;
    p.variable_speed = (raw >> 10) & 0x1;
    p.needs_head_load= (raw >> 11) & 0x1;
    p.rpm_div10      = (raw >> 16) & 0xFF;
    p.quality        = (raw >> 24) & 0xFF;
    return p;
}

const char* form_factor_str(uint8_t ff) {
    switch (ff) {
        case 1: return "3.5\"";
        case 2: return "5.25\"";
        case 3: return "8\"";
        default: return "Unknown";
    }
}

void print_drive_info(int interface) {
    uint32_t addr = (interface == 0) ? DRIVE_PROFILE_A : DRIVE_PROFILE_B;
    uint32_t raw = FDC_READ(addr);
    drive_profile_t p = parse_profile(raw);

    printf("Drive %c Profile:\n", 'A' + interface);
    printf("  Form Factor: %s\n", form_factor_str(p.form_factor));
    printf("  Density:     %s\n",
           p.density_cap == 0 ? "DD" :
           p.density_cap == 1 ? "HD" :
           p.density_cap == 2 ? "ED" : "Unknown");
    printf("  Tracks:      %d\n",
           p.track_density == 0 ? 40 :
           p.track_density == 1 ? 80 :
           p.track_density == 2 ? 77 : 0);
    printf("  RPM:         %d\n", p.rpm_div10 * 10);
    printf("  Quality:     %d%%\n", p.quality * 100 / 255);
}
```

### 8.2 Waiting for Detection

```c
// Bit positions for profile status
#define PROFILE_VALID_BIT   (1 << 15)
#define PROFILE_LOCKED_BIT  (1 << 14)

// Wait for profile detection to complete
bool wait_for_profile(int interface, int timeout_ms) {
    uint32_t addr = (interface == 0) ? DRIVE_PROFILE_A : DRIVE_PROFILE_B;

    for (int i = 0; i < timeout_ms; i++) {
        uint32_t raw = FDC_READ(addr);

        // Check PROFILE_VALID bit (bit 15) - explicit valid flag
        if (raw & PROFILE_VALID_BIT) {
            return true;
        }
        delay_ms(1);
    }
    return false;
}

// Wait for high-confidence locked profile
bool wait_for_locked_profile(int interface, int timeout_ms) {
    uint32_t addr = (interface == 0) ? DRIVE_PROFILE_A : DRIVE_PROFILE_B;

    for (int i = 0; i < timeout_ms; i++) {
        uint32_t raw = FDC_READ(addr);

        // Check both VALID and LOCKED bits for high-confidence result
        if ((raw & (PROFILE_VALID_BIT | PROFILE_LOCKED_BIT)) ==
            (PROFILE_VALID_BIT | PROFILE_LOCKED_BIT)) {
            return true;
        }
        delay_ms(1);
    }
    return false;
}
```

### 8.3 Manual Override

```c
// User can override detected values via CCR register
#define CCR_AUTO_DOUBLE_STEP  (1 << 5)
#define CCR_AUTO_DATA_RATE    (1 << 6)
#define CCR_AUTO_ENCODING     (1 << 7)

void disable_auto_detection() {
    uint8_t ccr = FDC_READ(ADDR_CCR);
    ccr &= ~(CCR_AUTO_DOUBLE_STEP | CCR_AUTO_DATA_RATE | CCR_AUTO_ENCODING);
    FDC_WRITE(ADDR_CCR, ccr);
}

void force_drive_config(uint8_t data_rate, bool double_step) {
    disable_auto_detection();

    // Set manual data rate
    FDC_WRITE(ADDR_DSR, data_rate);

    // Set manual double-step
    uint8_t dor = FDC_READ(ADDR_DOR);
    if (double_step)
        dor |= 0x40;  // Enable double-step
    else
        dor &= ~0x40;
    FDC_WRITE(ADDR_DOR, dor);
}
```

---

## Appendix A: Drive Fingerprint Database

Future enhancement: Build a database of drive behavioral fingerprints for vendor identification.

**Fingerprint Parameters:**
- Step settling time
- Motor spinup time to stable RPM
- RPM variance under load
- HEAD_LOAD response time (8" drives)
- Seek acoustic signature (if audio capture available)

**Example Fingerprint:**
```
Vendor: Sony
Model: MPF920
Fingerprint:
  spinup_time: 450ms
  rpm_variance: 0.3%
  step_settle: 3ms
  seek_10_tracks: 45ms
```

---

## Appendix B: Platform Detection Matrix

| Platform | RPM | Encoding | Sectors | Sector Size | Detection |
|----------|-----|----------|---------|-------------|-----------|
| IBM PC DD | 300 | MFM | 9 | 512 | High |
| IBM PC HD | 300 | MFM | 18 | 512 | High |
| Amiga | 300 | MFM | 11 | 512 | High (no gaps) |
| Atari ST | 300 | MFM | 9-10 | 512 | Medium |
| Apple II | 300 | GCR | 13-16 | 256 | Very High |
| Macintosh | 300 | GCR | Variable | 512 | Very High (zones) |
| Commodore | 300 | GCR | 17-21 | 256 | Very High |
| CP/M 8" | 360 | FM/MFM | 26 | 128 | High |
| NEC PC-98 | 360 | MFM | 8 | 1024 | Medium |
| DEC RX02 | 360 | M2FM | 26 | 256 | Very High |

---

## Appendix C: DRIVE_PROFILE to Platform Mapping

Use this table to map detected DRIVE_PROFILE values to likely platforms:

| DRIVE_PROFILE Pattern | Likely Platform(s) | Notes |
|-----------------------|--------------------|-------|
| FF=3.5", Dens=HD, Enc=MFM, RPM=300 | IBM PC HD, Amiga HD, Atari ST HD | Sector geometry distinguishes |
| FF=3.5", Dens=DD, Enc=MFM, RPM=300 | IBM PC DD, Amiga DD, Atari ST | Common DD format |
| FF=3.5", Dens=ED, Enc=MFM, RPM=300 | IBM PS/2 ED, NeXT | Rare ED drives |
| FF=3.5", Enc=GCR-Apple, VZ=1 | Macintosh 400K/800K, Lisa | Variable zones enabled |
| FF=5.25", Dens=HD, Enc=MFM, RPM=360 | IBM PC/AT 1.2MB, NEC PC-98 | TG43 active |
| FF=5.25", Dens=DD, Enc=MFM, TrkD=40 | IBM PC/XT, early CP/M | 48 TPI drives |
| FF=5.25", Dens=DD, Enc=MFM, TrkD=80 | DEC RX50, QD formats | 96 TPI drives |
| FF=5.25", Enc=GCR-Apple | Apple II DOS 3.3/ProDOS | 35/40 tracks |
| FF=5.25", Enc=GCR-Apple5 | Apple II DOS 3.2 | 13-sector format |
| FF=5.25", Enc=GCR-CBM | Commodore 64/128 | Zone-based sectors |
| FF=5.25", Enc=Agat | Soviet Agat-7/9 | Apple-derived |
| FF=5.25", Enc=Tandy | TRS-80 CoCo, Dragon 32/64 | Tandy FM sync |
| FF=8", Dens=DD, Enc=FM, HL=1 | CP/M SSSD, DEC RX01 | Single density |
| FF=8", Dens=DD, Enc=MFM, HL=1 | CP/M DSDD, Wang, Xerox | Double density |
| FF=8", Enc=M2FM, HL=1 | DEC RX02, Intel MDS | Modified MFM |
| HS=1, any | NorthStar, Vector Graphics | Hard-sectored media |

### Platform Auto-Selection Algorithm

```c
// Suggest default platform based on DRIVE_PROFILE
const char* suggest_platform(uint32_t profile) {
    uint8_t ff   = (profile >> 0) & 0x3;
    uint8_t dens = (profile >> 2) & 0x3;
    uint8_t trkd = (profile >> 4) & 0x3;
    uint8_t enc  = (profile >> 6) & 0x7;
    bool    hs   = (profile >> 9) & 0x1;
    bool    vz   = (profile >> 10) & 0x1;
    bool    hl   = (profile >> 11) & 0x1;
    uint8_t rpm  = (profile >> 16) & 0xFF;

    // Hard-sectored takes priority
    if (hs) return "S-100 Hard-Sectored";

    // 8" drives
    if (ff == 3) {  // FF_8
        if (enc == 5) return "DEC RX02 / Intel MDS (M2FM)";
        if (enc == 1) return "CP/M SSSD (FM)";
        return "CP/M 8\" (MFM)";
    }

    // 5.25" drives
    if (ff == 2) {  // FF_5_25
        if (enc == 3 || enc == 4) return "Apple II";
        if (enc == 7) return "Soviet Agat";
        if (enc == 2) return "Commodore 64/1541";
        if (enc == 6) return "TRS-80 CoCo / Dragon";
        if (rpm == 36) return "IBM PC/AT 1.2MB";
        if (trkd == 0) return "IBM PC/XT 360KB";
        return "5.25\" MFM (generic)";
    }

    // 3.5" drives
    if (ff == 1) {  // FF_3_5
        if (vz) return "Macintosh 400K/800K";
        if (dens == 2) return "IBM PS/2 2.88MB ED";
        if (dens == 1) return "IBM PC HD 1.44MB";
        return "IBM PC DD 720KB";
    }

    return "Unknown";
}
```

---

## Appendix D: Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-04 | Initial documentation |
| 1.1 | 2025-12-03 | Added PROFILE_VALID (bit 15), PROFILE_LOCKED (bit 14); added Agat encoding (111); added track density to 3.5"/5.25" DD inference; added platform mapping appendix |
