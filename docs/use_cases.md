# FluxRipper Use Cases

*Updated: 2025-12-03 19:25*

> "You haven't just built a floppy controller; you've built a general-purpose magnetic storage observatory."

This document catalogs the diverse applications enabled by FluxRipper's dual Shugart interface, 4-drive support, flux-level capture, signal quality metrics, and 82077AA-compatible architecture.

---

## Table of Contents

1. [Retrocomputing & Preservation](#1-retrocomputing--preservation)
2. [Copy Protection, Forensics & Analysis](#2-copy-protection-forensics--analysis)
3. [Drive Characterization & Hardware R&D](#3-drive-characterization--hardware-rd)
4. [Software / OS / Driver Development](#4-software--os--driver-development)
5. [Disk-to-Disk & Live Tools](#5-disk-to-disk--live-tools)
6. [Teaching & Research](#6-teaching--research)
7. [Emulation & Hybrid Systems](#7-emulation--hybrid-systems)
8. [Operational / Service Use Cases](#8-operational--service-use-cases)
9. [Pure Nerd Fun](#9-pure-nerd-fun)

---

## 1. Retrocomputing & Preservation

### 1.1 High-Volume Archival Rig

**Capability Stack:**
- 4 drives across dual interfaces
- Parallel flux capture via dual AXI-Stream
- On-board MicroBlaze V SoC + 8MB HyperRAM buffer
- Per-revolution signal quality metrics

**Workflow:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Production Archival Station                   │
│                                                                  │
│   Drive 0 ──► Primary read (continuous capture)                 │
│   Drive 1 ──► Verification pass / re-read marginal tracks       │
│   Drive 2 ──► Alternate drive for "stubborn" disks              │
│   Drive 3 ──► Queue next disk while others work                 │
│                                                                  │
│   Decision Engine:                                               │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ IF quality[track] < THRESHOLD:                          │   │
│   │     retry_count++                                       │   │
│   │     IF retry_count > 3:                                 │   │
│   │         try_alternate_drive(track)                      │   │
│   │     ELSE:                                               │   │
│   │         re_read(track)                                  │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Applications:**
- Museum and archive digitization projects
- Personal collection imaging (thousands of disks)
- Preservation organizations needing throughput + quality assurance

**Key Metrics Used:**
- `QUALITY` register per track/revolution
- `capture_count` for flux density analysis
- `rpm_valid` / `rpm_300` / `rpm_360` for drive health

---

### 1.2 Exotic-Format Rescue Station

**Supported Encoding Schemes:**

| Format | Encoding | Data Rate | Platform |
|--------|----------|-----------|----------|
| IBM PC HD | MFM | 500 Kbps | DOS/Windows |
| IBM PC DD | MFM | 250 Kbps | DOS/Windows |
| Apple II DOS 3.3 | GCR-6bit | Variable | Apple II |
| Apple II DOS 3.2 | GCR-5bit | Variable | Apple II |
| Commodore 1541 | GCR-CBM | Variable | C64/VIC-20 |
| Amiga | MFM (custom) | Variable | Amiga |
| FM (legacy) | FM | 125/250 Kbps | CP/M, early systems |

**Philosophy:**

> "Send it anything with a spindle and a 34-pin-ish connector; if the head can see magnetism, we can at least capture it."

**Workflow:**
1. Connect unknown disk to any drive
2. Enable flux capture in continuous mode
3. Capture raw transitions regardless of encoding
4. Post-process with format-specific decoders
5. If standard decode fails, analyze flux histogram for encoding clues

**Implementation:**
```c
// Pseudo-code for format detection
flux_capture_enable(DRIVE_0, MODE_CONTINUOUS);
wait_for_index();
capture_revolution();

histogram = analyze_flux_timing(flux_data);
if (histogram.peak_near(4us))
    decode_as_mfm_250k();
else if (histogram.peak_near(2us))
    decode_as_mfm_500k();
else if (histogram.has_gcr_signature())
    try_gcr_variants();
else
    save_raw_flux("unknown_format.flux");
```

---

### 1.3 Automated "Try Multiple Drives" Rescue Mode

**Problem:** Marginal disks may read better on certain drives due to:
- Head alignment differences
- Azimuth variations
- Age-related characteristics
- Manufacturing tolerances

**Solution: Multi-Drive Comparison Pipeline**

```
┌─────────────────────────────────────────────────────────────────┐
│                  Multi-Drive Rescue Workflow                     │
│                                                                  │
│  1. Load disk into Drive 0                                      │
│  2. FOR each track:                                             │
│       read_result[0] = capture_track(DRIVE_0)                   │
│       IF quality[0] < THRESHOLD:                                │
│           mark_suspect(track)                                   │
│                                                                  │
│  3. FOR each suspect track:                                     │
│       FOR drive IN [1, 2, 3]:                                   │
│           move_disk_to(drive)  // manual or robotic             │
│           read_result[drive] = capture_track(drive)             │
│       best = select_best_quality(read_result)                   │
│       use_data_from(best.drive)                                 │
│                                                                  │
│  4. Generate report:                                            │
│       - Per-track quality comparison                            │
│       - Drive performance ranking for this disk type            │
│       - Recommended "best drive" for similar media              │
└─────────────────────────────────────────────────────────────────┘
```

**Output: Drive Personality Database**

| Drive | Best For | Weakness | Notes |
|-------|----------|----------|-------|
| Sony MPF920 | High-density MFM | GCR timing | Excellent alignment |
| Teac FD-235HF | Double-density | Worn heads | Good for old 360K disks |
| Panasonic JU-257 | All-rounder | None notable | Reliable baseline |
| NEC FD1231H | Commodore GCR | MFM marginal | Unusual head width |

---

## 2. Copy Protection, Forensics & Analysis

### 2.1 Copy Protection Dissection Platform

**Capability:** Capture, analyze, reconstruct, and compare protected disks.

**Common Protection Techniques Detectable:**

| Technique | Detection Method | FluxRipper Feature Used |
|-----------|------------------|-------------------------|
| Weak bits | Flux variance across reads | Multi-revolution capture |
| Timing anomalies | Non-standard bit spacing | Flux timestamp analysis |
| Long tracks | >standard bytes/track | `capture_count` monitoring |
| Density variations | Zone-based encoding | Per-sector quality metrics |
| Index alignment | Sector placement vs index | `flux_index` correlation |
| Deliberate CRC errors | Expected failures | CRC mismatch logging |

**Workflow: Protection Analysis**

```
┌─────────────────────────────────────────────────────────────────┐
│                Copy Protection Analysis Lab                      │
│                                                                  │
│  Phase 1: Capture Original                                      │
│  ─────────────────────────                                      │
│  • Flux capture entire disk (all tracks, multiple revolutions)  │
│  • Store raw flux + decoded data + quality metrics              │
│                                                                  │
│  Phase 2: Statistical Analysis                                  │
│  ─────────────────────────────                                  │
│  • Identify tracks with:                                        │
│    - High variance between revolutions (weak bits)              │
│    - Unusual flux timing distribution (timing protection)       │
│    - Extra data beyond sector boundaries (long tracks)          │
│                                                                  │
│  Phase 3: Reconstruction Test                                   │
│  ───────────────────────────                                    │
│  • Write reconstructed image to blank disk (Drive B)            │
│  • Compare flux characteristics:                                │
│    - Does protection loader accept the copy?                    │
│    - Which track(s) fail verification?                          │
│                                                                  │
│  Phase 4: Documentation                                         │
│  ─────────────────────────                                      │
│  • Classify protection scheme                                   │
│  • Document bypass/emulation requirements                       │
│  • Generate visualization of protection features                │
└─────────────────────────────────────────────────────────────────┘
```

**Visualization Output Example:**

```
Track 6 Analysis - Detected: WEAK BIT PROTECTION
═══════════════════════════════════════════════════════════════

Revolution 1: ████████████░░████████████████████████████████████
Revolution 2: ████████████░░████████████████████████████████████
Revolution 3: ██████████████████████████████████████████████████
Revolution 4: ████████████░░████████████████████████████████████
                           ▲
                    Weak bit region (bytes 0x1A0-0x1A8)
                    Variance: 73% across 10 revolutions

Flux Timing Histogram:
  2.0µs: ████████████████████████ (MFM '1')
  3.0µs: ████████████████ (MFM '01')
  4.0µs: ████████████████████ (MFM '001')
  Anomaly at 5.2µs: ██ (protection timing marker)
```

---

### 2.2 Digital Forensics: "Was This Disk Altered?"

**Forensic Indicators:**

| Indicator | What It Reveals | Detection Method |
|-----------|-----------------|------------------|
| PLL lock instability | Different write equipment | `pll_locked` transitions per track |
| RPM micro-variations | Drive motor fingerprint | `revolution_time` analysis |
| Write splice patterns | Sector-level modifications | Flux gap analysis at sector boundaries |
| Magnetic coercivity | Media age/type mismatch | Amplitude envelope (advanced) |
| Alignment shifts | Different drive wrote data | Track-to-track flux offset |

**Forensic Workflow:**

```
┌─────────────────────────────────────────────────────────────────┐
│              Disk Authenticity Analysis                          │
│                                                                  │
│  Step 1: Baseline Capture                                       │
│  • Capture entire disk, 5+ revolutions per track                │
│  • Record quality metrics, PLL behavior, RPM per revolution     │
│                                                                  │
│  Step 2: Consistency Analysis                                   │
│  • Compare inter-track characteristics:                         │
│    - Do all tracks show similar PLL lock behavior?              │
│    - Is RPM consistent across disk?                             │
│    - Are write splice patterns uniform?                         │
│                                                                  │
│  Step 3: Anomaly Detection                                      │
│  • Flag tracks with:                                            │
│    - Significantly different quality profile                    │
│    - Unusual flux timing distribution                           │
│    - Different effective data rate                              │
│                                                                  │
│  Step 4: Report                                                 │
│  • "Disk appears original" OR                                   │
│  • "Tracks X, Y, Z show evidence of later modification"         │
│  • Confidence level based on statistical significance           │
└─────────────────────────────────────────────────────────────────┘
```

**Example Report:**

```
FORENSIC ANALYSIS REPORT
═══════════════════════════════════════════════════════════════
Disk: Evidence Item #2024-0847
Date: 2025-12-03

FINDING: PARTIAL MODIFICATION DETECTED

Bulk Disk Characteristics:
  Mean RPM: 299.7 (σ=0.3)
  Mean Quality: 87.3% (σ=2.1%)
  PLL Lock Time: 12.4µs (σ=1.8µs)

Anomalous Tracks:
  Track 15: Quality=72.1% (4.2σ below mean)
            RPM=300.4 (2.3σ above mean)
            PLL Lock Time: 28.7µs (9.1σ above mean)

  Track 16: Similar anomalies detected

CONCLUSION: Tracks 15-16 were likely written by a different
drive than the remainder of the disk. Pattern consistent with
sector-level data modification.

Confidence: 94.7%
```

---

## 3. Drive Characterization & Hardware R&D

### 3.1 Automated Drive Characterization Bench

**Test Suite Components:**

| Test | Measurement | Pass Criteria |
|------|-------------|---------------|
| RPM Stability | Revolution time σ over 100 revs | < 0.5% variation |
| Warm-up Drift | RPM change first 60 seconds | < 1% total drift |
| Head Load Time | Index to first valid flux | < 50ms |
| Step Accuracy | Track 0 sensor reliability | 100% detection |
| Read Quality | Mean QUALITY across test disk | > 85% |
| Multi-rate | Performance at 250K/300K/500K | All rates functional |

**Characterization Report Format:**

```
╔══════════════════════════════════════════════════════════════════╗
║              DRIVE CHARACTERIZATION REPORT                        ║
║══════════════════════════════════════════════════════════════════║
║  Drive: Sony MPF920-Z                                            ║
║  Serial: 4A7B2C1D                                                ║
║  Test Date: 2025-12-03 19:30                                     ║
╠══════════════════════════════════════════════════════════════════╣
║  PERFORMANCE METRICS                                              ║
║  ─────────────────────────────────────────────────────────────── ║
║  RPM (cold):        299.2 ± 0.8                                  ║
║  RPM (warm):        300.1 ± 0.3                                  ║
║  Warm-up time:      47 seconds                                   ║
║  Head load:         32ms                                         ║
║  Step rate:         3.0ms (measured), 3.0ms (configured)         ║
║                                                                   ║
║  QUALITY SCORES (by encoding)                                     ║
║  ─────────────────────────────────────────────────────────────── ║
║  MFM 250K:          ████████████████████░░░░  89%                ║
║  MFM 500K:          ███████████████████░░░░░  86%                ║
║  FM:                ██████████████████░░░░░░  82%                ║
║  GCR-CBM:           ████████████░░░░░░░░░░░░  61%  ⚠ WEAK        ║
║                                                                   ║
║  RECOMMENDATION                                                   ║
║  ─────────────────────────────────────────────────────────────── ║
║  ✓ Suitable for: MFM archival work                               ║
║  ⚠ Limited for:  GCR formats (consider alternate drive)         ║
║  ✗ Not recommended for: High-precision timing analysis           ║
╚══════════════════════════════════════════════════════════════════╝
```

---

### 3.2 Media Aging Studies

**Long-Term Study Protocol:**

```
┌─────────────────────────────────────────────────────────────────┐
│              MEDIA AGING STUDY PROTOCOL                          │
│                                                                  │
│  Sample Set: 100 disks (mixed brands/ages)                      │
│  Duration: 24 months                                            │
│  Measurement Interval: Monthly                                  │
│                                                                  │
│  Per-Measurement:                                               │
│  ├── Full disk capture (all tracks)                             │
│  ├── Quality metrics per track                                  │
│  ├── Flux distribution histogram                                │
│  ├── Error rate (soft/hard errors)                              │
│  └── Environmental conditions logged                            │
│                                                                  │
│  Storage Conditions (varied by group):                          │
│  ├── Group A: Climate controlled (20°C, 40% RH)                │
│  ├── Group B: Ambient office (variable)                         │
│  ├── Group C: Elevated temp (30°C)                              │
│  └── Group D: High humidity (70% RH)                            │
│                                                                  │
│  Analysis:                                                       │
│  ├── Quality degradation curves per group                       │
│  ├── Brand/media type correlation                               │
│  ├── Failure mode classification                                │
│  └── Predictive model for remaining lifespan                    │
└─────────────────────────────────────────────────────────────────┘
```

**Example Degradation Curve:**

```
Quality Score vs Time (Track 40, various storage conditions)

100% ─┬─────────────────────────────────────────────────
      │ ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●  Group A (controlled)
 90% ─┤         ○○○○○○○○○○○○○○○○○○○○○
      │               ○○○○○○○○○○○○○     Group B (ambient)
 80% ─┤                     ○○○○○○
      │                          △△△△△△
 70% ─┤                    △△△△△         Group C (warm)
      │              △△△△△
 60% ─┤        △△△△△
      │  □□□□□         □□□□□□□□□□□□□    Group D (humid)
 50% ─┤       □□□□□
      │
 40% ─┴─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────
           0     3     6     9    12    15    18    21  months
```

---

### 3.3 Write-Strategy Experimentation

**Research Questions:**

1. Does write precompensation improve readability on aged media?
2. What's the optimal erase current for overwriting old data?
3. How does write speed affect magnetic transition quality?

**Experiment Framework:**

```
┌─────────────────────────────────────────────────────────────────┐
│           WRITE STRATEGY EXPERIMENT                              │
│                                                                  │
│  Test Matrix:                                                    │
│  ──────────────────────────────────────────────────────         │
│  Variable 1: Precompensation delay                              │
│              [0ns, 100ns, 200ns, 300ns]                         │
│                                                                  │
│  Variable 2: Write current (if adjustable)                      │
│              [Low, Medium, High]                                │
│                                                                  │
│  Variable 3: Media type                                         │
│              [New HD, New DD, Aged HD, Aged DD]                 │
│                                                                  │
│  Procedure (per combination):                                   │
│  1. Write test pattern to track N                               │
│  2. Immediate read → Quality_A                                  │
│  3. Wait 1 hour → Quality_B                                     │
│  4. 10x re-read → Error_rate                                    │
│  5. Record all metrics                                          │
│                                                                  │
│  Output:                                                         │
│  • Optimal precomp for each media type                          │
│  • Read margin analysis (jitter tolerance)                      │
│  • Recommendations for archival writes                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Software / OS / Driver Development

### 4.1 Golden FDC for OS Driver Testing

**Test Scenarios:**

| Scenario | Injection Method | Expected Driver Behavior |
|----------|------------------|--------------------------|
| CRC error | Set `data_error` flag | Retry, then report error |
| Missing sector | Timeout AM detection | Seek retry, then fail |
| Write protect | Assert `wp` input | Abort write, report error |
| Drive not ready | Deassert `ready` | Wait with timeout |
| Index timeout | Inhibit index pulse | Motor timeout handling |
| Slow response | Delay RQM assertion | DMA timeout handling |

**Driver Test Framework:**

```c
// Example test case: CRC error recovery
void test_crc_error_recovery() {
    // Configure FluxRipper to inject CRC error on sector 5
    axi_write(INJECT_ERROR_REG, SECTOR(5) | ERROR_CRC);

    // Attempt to read track
    int result = driver_read_track(0, buffer);

    // Verify driver behavior
    ASSERT(driver_retry_count >= 3);
    ASSERT(result == -EIO);
    ASSERT(driver_last_error == FDC_ERR_CRC);

    // Check that driver didn't corrupt other sectors
    for (int i = 0; i < 18; i++) {
        if (i != 5) {
            ASSERT(sector_valid[i] == true);
        }
    }
}
```

**Supported Driver Test Targets:**
- Linux floppy.ko
- FreeBSD fd driver
- MS-DOS FDC drivers
- Custom embedded FDC stacks

---

### 4.2 Continuous Integration for Retro Stacks

**Hardware-in-the-Loop CI Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    CI/CD Pipeline                                │
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   GitLab    │───►│   CI Runner │───►│  Test Host  │         │
│  │   Server    │    │             │    │  (Linux)    │         │
│  └─────────────┘    └─────────────┘    └──────┬──────┘         │
│                                               │                 │
│                                        ┌──────▼──────┐         │
│                                        │ FluxRipper  │         │
│                                        │   SCU35     │         │
│                                        └──────┬──────┘         │
│                                               │                 │
│                              ┌────────────────┼────────────────┐│
│                              │                │                ││
│                       ┌──────▼──────┐  ┌──────▼──────┐        ││
│                       │   Drive 0   │  │   Drive 1   │        ││
│                       │ (Test Disk) │  │ (Reference) │        ││
│                       └─────────────┘  └─────────────┘        ││
└─────────────────────────────────────────────────────────────────┘

Pipeline Stages:
1. Build new gateware/firmware
2. Flash to FluxRipper
3. Boot test OS from real floppy
4. Run FDC driver tests
5. Capture flux + bus traces
6. Compare against golden baseline
7. Pass/fail + artifact storage
```

**Example `.gitlab-ci.yml`:**

```yaml
stages:
  - build
  - flash
  - test
  - analyze

fdc_regression:
  stage: test
  script:
    - fluxripper-cli flash bitstream.bit
    - fluxripper-cli boot-disk dos622.img
    - fluxripper-cli run-test fdc_torture_suite
    - fluxripper-cli capture-flux test_capture.flux
  artifacts:
    paths:
      - test_capture.flux
      - test_results.json
    when: always
```

---

## 5. Disk-to-Disk & Live Tools

### 5.1 Intelligent Disk-to-Disk Copier

**Smart Copy Algorithm:**

```
┌─────────────────────────────────────────────────────────────────┐
│              INTELLIGENT DISK COPY                               │
│                                                                  │
│  Source: Drive 0 (Interface A)                                  │
│  Destination: Drive 2 (Interface B)                             │
│                                                                  │
│  FOR each track (0 to max_track):                               │
│      attempts = 0                                               │
│      success = false                                            │
│                                                                  │
│      WHILE NOT success AND attempts < MAX_ATTEMPTS:             │
│          source_data = read_track(DRIVE_0, track)               │
│          quality = get_quality(DRIVE_0)                         │
│                                                                  │
│          IF quality >= GOOD_THRESHOLD:                          │
│              write_track(DRIVE_2, track, source_data)           │
│              verify_data = read_track(DRIVE_2, track)           │
│              IF verify_data == source_data:                     │
│                  success = true                                 │
│                  log_track(track, "OK", quality)                │
│          ELSE IF quality >= MARGINAL_THRESHOLD:                 │
│              // Try flux-level reconstruction                   │
│              flux_data = capture_flux(DRIVE_0, track, 5_revs)   │
│              reconstructed = best_of_revolutions(flux_data)     │
│              write_track(DRIVE_2, track, reconstructed)         │
│              success = verify_track(DRIVE_2, track)             │
│              log_track(track, "RECONSTRUCTED", quality)         │
│          ELSE:                                                  │
│              attempts++                                         │
│              IF attempts == MAX_ATTEMPTS:                       │
│                  log_track(track, "FAILED", quality)            │
│                  prompt_user("Track {track} unreadable")        │
│                                                                  │
│  GENERATE health_report(source_disk, dest_disk)                 │
└─────────────────────────────────────────────────────────────────┘
```

**Copy Report:**

```
╔══════════════════════════════════════════════════════════════════╗
║                    DISK COPY REPORT                               ║
╠══════════════════════════════════════════════════════════════════╣
║  Source:      Drive 0 - Original DOS disk                        ║
║  Destination: Drive 2 - New Verbatim HD                          ║
║  Date:        2025-12-03 19:45                                   ║
╠══════════════════════════════════════════════════════════════════╣
║  TRACK STATUS                                                     ║
║  ──────────────────────────────────────────────────────────────  ║
║  Tracks 0-39:   ████████████████████████████████████████  100%   ║
║                 All tracks copied successfully                   ║
║                                                                   ║
║  Track Quality Distribution:                                      ║
║    Excellent (>95%):  32 tracks                                  ║
║    Good (85-95%):      6 tracks                                  ║
║    Marginal (70-85%):  2 tracks (reconstructed from multi-rev)   ║
║    Failed (<70%):      0 tracks                                  ║
║                                                                   ║
║  Problem Tracks:                                                  ║
║    Track 17: Quality 78%, required 3 read attempts               ║
║    Track 31: Quality 72%, used 5-revolution reconstruction       ║
║                                                                   ║
║  VERIFICATION: PASSED                                             ║
║  All destination tracks verified against source                  ║
╚══════════════════════════════════════════════════════════════════╝
```

---

### 5.2 "On-the-Fly Analyzer" Mode

**Network-Accessible Lab Instrument:**

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│    ┌──────────────────────────────────────────────────────┐     │
│    │              FluxRipper Web Interface                 │     │
│    │              http://fluxripper.local                  │     │
│    └──────────────────────────────────────────────────────┘     │
│                                                                  │
│    ┌─────────────────┐  ┌─────────────────┐                     │
│    │ Drive 0         │  │ Drive 2         │                     │
│    │ ══════════════  │  │ ══════════════  │                     │
│    │ RPM: 299.8      │  │ RPM: 300.2      │                     │
│    │ Quality: 87%    │  │ Quality: 91%    │                     │
│    │ Track: 15       │  │ Track: 22       │                     │
│    │ Status: READING │  │ Status: IDLE    │                     │
│    └─────────────────┘  └─────────────────┘                     │
│                                                                  │
│    ┌──────────────────────────────────────────────────────┐     │
│    │  Live Flux Visualization - Track 15                   │     │
│    │  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁     │     │
│    │  |    |    |    |    |    |    |    |    |    |       │     │
│    │  0   10   20   30   40   50   60   70   80   90  ms   │     │
│    └──────────────────────────────────────────────────────┘     │
│                                                                  │
│    API Endpoints:                                                │
│    • GET  /api/drives              - List all drives            │
│    • GET  /api/drives/0/status     - Drive 0 status             │
│    • POST /api/drives/0/capture    - Start flux capture         │
│    • GET  /api/flux/stream         - WebSocket flux stream      │
│    • GET  /api/flux/histogram      - Timing histogram           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Python API Example:**

```python
import fluxripper

# Connect to FluxRipper
fr = fluxripper.connect("192.168.1.100")

# Check all drives
for drive in fr.drives:
    print(f"Drive {drive.id}: RPM={drive.rpm:.1f}, Quality={drive.quality}%")

# Capture flux from drive 0
with fr.drives[0].capture(mode='one_revolution') as capture:
    for transition in capture.flux_stream():
        print(f"t={transition.timestamp}, index={transition.is_index}")

# Get timing histogram
hist = fr.drives[0].flux_histogram(revolutions=5)
hist.plot()  # matplotlib visualization
```

---

## 6. Teaching & Research

### 6.1 Teaching Magnetic Storage

**Lab Exercise Portfolio:**

| Exercise | Learning Objectives | FluxRipper Features Used |
|----------|---------------------|--------------------------|
| Lab 1: Flux Fundamentals | Understand magnetic transitions | Live flux visualization |
| Lab 2: PLL Design | Implement/observe data separation | DPLL lock metrics, phase error |
| Lab 3: Encoding Schemes | Compare FM/MFM/GCR | Multi-encoding support |
| Lab 4: Error Detection | Implement CRC, analyze failures | CRC module, error injection |
| Lab 5: Drive Mechanics | Measure RPM, step timing | Index handler, step controller |
| Lab 6: Copy Protection | Analyze real protected disks | Multi-revolution capture |

**Lab 3 Example: Encoding Comparison**

```
┌─────────────────────────────────────────────────────────────────┐
│  LAB 3: ENCODING SCHEME COMPARISON                               │
│                                                                  │
│  Objective: Understand why MFM replaced FM                      │
│                                                                  │
│  Procedure:                                                      │
│  1. Capture same data written in FM and MFM                     │
│  2. Measure flux density (transitions per inch)                 │
│  3. Calculate effective data rate                               │
│  4. Analyze DC content and self-clocking properties             │
│                                                                  │
│  Captured Data: 0xA5 (10100101)                                 │
│                                                                  │
│  FM Encoding:   (clock bits shown as 'c')                       │
│  ──────────────────────────────────────────────                 │
│  c1c0c1c0c0c1c0c1                                               │
│  ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑                                               │
│  │ │ │ │ │ │ │ └── 1 (data + clock)                            │
│  │ │ │ │ │ │ └──── 0 (clock only)                              │
│  ...                                                             │
│  Efficiency: 50% (half the bits are clocks)                     │
│                                                                  │
│  MFM Encoding:  (no separate clock bits)                        │
│  ──────────────────────────────────────────────                 │
│  0100100101001001                                               │
│  Rule: Write '1' only if:                                       │
│        - Data bit is '1', OR                                    │
│        - Previous AND current data bits are '0'                 │
│  Efficiency: 100% (all bits are data or minimal clocks)         │
│                                                                  │
│  Questions:                                                      │
│  1. Why does MFM achieve 2x data density?                       │
│  2. What's the maximum run length of zeros in MFM?              │
│  3. How does this affect PLL design requirements?               │
└─────────────────────────────────────────────────────────────────┘
```

---

### 6.2 Datasets for ML / Signal-Processing Experiments

**Dataset Schema:**

```json
{
  "capture_id": "cap_20251203_194500_0001",
  "metadata": {
    "drive": "Sony MPF920",
    "media": "Verbatim DD",
    "age_years": 15,
    "track": 35,
    "side": 0,
    "encoding": "MFM",
    "data_rate_kbps": 250
  },
  "quality_metrics": {
    "overall_quality": 82,
    "pll_lock_time_us": 15.2,
    "flux_variance": 0.034,
    "error_rate": 0.0012
  },
  "flux_data": {
    "format": "delta_timestamps_ns",
    "revolution_count": 10,
    "transitions_per_rev": [12847, 12851, 12849, ...],
    "data_url": "s3://fluxripper-dataset/raw/cap_20251203_194500_0001.flux"
  },
  "labels": {
    "read_success": true,
    "required_retries": 2,
    "human_verified": true,
    "protection_type": "none"
  }
}
```

**ML Research Applications:**

| Application | Input Features | Output | Model Type |
|-------------|----------------|--------|------------|
| Readability Prediction | Flux timing, quality metrics | P(successful read) | Classification |
| Optimal Retry Strategy | Quality per revolution | Best revolution to use | Reinforcement Learning |
| Format Detection | Flux histogram | Encoding type | Multi-class Classification |
| Anomaly Detection | Flux patterns | Copy protection / damage | Autoencoder |
| Drive Fingerprinting | Write patterns | Drive identification | Siamese Network |

**Benchmark Suite:**

```
┌─────────────────────────────────────────────────────────────────┐
│  FLUXRIPPER ML BENCHMARK SUITE                                   │
│                                                                  │
│  Dataset Statistics:                                             │
│  • 50,000 track captures                                        │
│  • 500 unique disks                                             │
│  • 20 different drives                                          │
│  • 5 encoding schemes                                           │
│  • Labels: readability, format, protection, quality tier        │
│                                                                  │
│  Baseline Results (test set):                                    │
│  ────────────────────────────────────────────────────────────── │
│  Task                    │ Classical │ CNN    │ Transformer     │
│  ────────────────────────┼───────────┼────────┼────────────────│
│  Readability Prediction  │ 78.3%     │ 89.1%  │ 91.4%          │
│  Format Detection        │ 94.2%     │ 98.7%  │ 99.1%          │
│  Quality Estimation      │ MAE 4.2   │ MAE 2.1│ MAE 1.8        │
│  Protection Detection    │ 71.5%     │ 85.3%  │ 88.9%          │
│                                                                  │
│  Download: https://fluxripper-dataset.example.com               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Emulation & Hybrid Systems

### 7.1 "Live-Bridge" Between Real Drives and Emulators

**Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    LIVE FLOPPY BRIDGE                            │
│                                                                  │
│  ┌───────────────┐         ┌───────────────┐                    │
│  │   Emulator    │◄───────►│  FluxRipper   │                    │
│  │  (MAME/VICE/  │  TCP/IP │    Bridge     │                    │
│  │   MiSTer)     │         │    Daemon     │                    │
│  └───────────────┘         └───────┬───────┘                    │
│                                    │                             │
│                            ┌───────▼───────┐                    │
│                            │  Real Drive   │                    │
│                            │  + Real Disk  │                    │
│                            └───────────────┘                    │
│                                                                  │
│  Modes of Operation:                                            │
│  ──────────────────────────────────────────────────────         │
│  1. PASSTHROUGH: Emulator reads/writes go to real drive         │
│     • Authentic timing and behavior                             │
│     • Good for testing real software on real media              │
│                                                                  │
│  2. CAPTURE+REPLAY: Record flux, replay deterministically       │
│     • Create reproducible test cases                            │
│     • Analyze edge cases in slow motion                         │
│                                                                  │
│  3. INJECT: Modify flux/timing in real-time                     │
│     • "What if the index pulse was 5ms late?"                   │
│     • Test emulator edge case handling                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Protocol:**

```c
// FluxRipper Bridge Protocol (TCP)
struct bridge_command {
    uint8_t  cmd;           // CMD_READ, CMD_WRITE, CMD_SEEK, etc.
    uint8_t  drive;         // 0-3
    uint16_t track;         // Cylinder number
    uint8_t  head;          // 0-1
    uint8_t  flags;         // FLUX_MODE, INJECT_ERRORS, etc.
};

struct bridge_response {
    uint8_t  status;        // OK, ERROR, TIMEOUT
    uint32_t flux_count;    // Number of transitions
    uint8_t  data[];        // Sector data or raw flux
};

// Example: VICE C64 emulator with real 1541 drive
void vice_read_sector(int track, int sector) {
    bridge_command cmd = {
        .cmd = CMD_READ_SECTOR,
        .drive = 0,
        .track = track,
        .flags = FLAG_REAL_TIMING
    };
    send_to_fluxripper(&cmd);

    bridge_response resp;
    recv_from_fluxripper(&resp);

    // Emulator now has real sector data with authentic timing
    memcpy(emulated_buffer, resp.data, 256);
}
```

---

### 7.2 Hybrid FDC + ISA Backplane Project

**Integration Concept:**

```
┌─────────────────────────────────────────────────────────────────┐
│                HYBRID RETRO SYSTEM                               │
│                                                                  │
│    ┌───────────────────────────────────────────────────────┐    │
│    │              Retro PC (ISA Bus)                        │    │
│    │  ┌─────────┐  ┌─────────┐  ┌─────────┐               │    │
│    │  │  8088   │  │   RAM   │  │   VGA   │               │    │
│    │  │   CPU   │  │  640KB  │  │  Card   │               │    │
│    │  └────┬────┘  └────┬────┘  └────┬────┘               │    │
│    │       └────────────┴────────────┴───────┐            │    │
│    │                     ISA BUS             │            │    │
│    │       ┌─────────────────────────────────┴───────┐    │    │
│    │       │                                         │    │    │
│    └───────┼─────────────────────────────────────────┼────┘    │
│            │                                         │          │
│            ▼                                         │          │
│    ┌───────────────────┐                            │          │
│    │  FluxRipper ISA   │◄───────────────────────────┘          │
│    │   Interface Card  │                                        │
│    │  (directly on bus)│                                        │
│    └─────────┬─────────┘                                        │
│              │                                                   │
│    ┌─────────▼─────────┐                                        │
│    │    FluxRipper     │                                        │
│    │      SCU35        │                                        │
│    │  ┌─────┐ ┌─────┐  │   ┌──────────────────┐                │
│    │  │FDC A│ │FDC B│  │───│  Modern PC       │                │
│    │  └──┬──┘ └──┬──┘  │   │  (monitoring)    │                │
│    └─────┼───────┼─────┘   └──────────────────┘                │
│          │       │                                              │
│    ┌─────▼──┐ ┌──▼─────┐                                       │
│    │Drive 0 │ │Drive 2 │                                       │
│    └────────┘ └────────┘                                       │
│                                                                  │
│  The retro PC thinks it's talking to a normal FDC.             │
│  FluxRipper silently captures everything at flux + bus level.  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Use Cases:**
- Reverse-engineer obscure DOS drivers
- Debug boot loaders that fail on emulators
- Capture "real" FDC timing for emulator improvement
- Analyze copy protection that checks for real hardware

---

## 8. Operational / Service Use Cases

### 8.1 Field "Triage Kit" for Archives / Collectors

**Appliance Configuration:**

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│    ╔═══════════════════════════════════════════════════════╗    │
│    ║           FLUXRIPPER FIELD STATION                     ║    │
│    ╠═══════════════════════════════════════════════════════╣    │
│    ║                                                        ║    │
│    ║   [DRIVE 0]  [DRIVE 1]  [DRIVE 2]  [DRIVE 3]          ║    │
│    ║      ░░░        ░░░        ░░░        ░░░             ║    │
│    ║     [====]     [====]     [====]     [====]           ║    │
│    ║                                                        ║    │
│    ║   ┌────────────────────────────────────────────┐      ║    │
│    ║   │  Mode: QUICK HEALTH CHECK                  │      ║    │
│    ║   │  ════════════════════════════════════════  │      ║    │
│    ║   │  Drive 0: Disk inserted                    │      ║    │
│    ║   │  Status: Scanning... Track 15/80           │      ║    │
│    ║   │  Quality: ████████████░░░░░ 78%            │      ║    │
│    ║   │                                            │      ║    │
│    ║   │  [QUICK CHECK] [DEEP IMAGE] [COPY A→B]    │      ║    │
│    ║   └────────────────────────────────────────────┘      ║    │
│    ║                                                        ║    │
│    ║   Status LEDs:  ● ● ○ ○   Power: ████████            ║    │
│    ║                 A B C D                                ║    │
│    ╚═══════════════════════════════════════════════════════╝    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pre-Built Workflows:**

| Workflow | Time | Output |
|----------|------|--------|
| Quick Health Check | ~30 sec | Pass/Marginal/Fail per disk |
| Standard Image | ~2 min | IMG file + quality report |
| Deep Archival | ~10 min | Multi-rev flux capture + decoded data |
| Copy A→B | ~3 min | Verified duplicate + health report |
| Batch Triage | ~20 sec/disk | Sorted pile: Good / Needs Work / Likely Dead |

**Triage Report (Quick Mode):**

```
╔══════════════════════════════════════════════════════════════════╗
║  DISK TRIAGE REPORT - Quick Mode                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  Collection: Smith Family Archive                                 ║
║  Date: 2025-12-03                                                ║
║  Disks Scanned: 47                                               ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  SUMMARY                                                          ║
║  ════════════════════════════════════════════════════════════    ║
║  ████████████████████████████████░░░░░░░░░░  32 GOOD (68%)       ║
║  ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  11 MARGINAL (23%)   ║
║  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   4 CRITICAL (9%)    ║
║                                                                   ║
║  PRIORITY ACTION LIST                                             ║
║  ════════════════════════════════════════════════════════════    ║
║  1. Disk #23 "Tax Records 1987" - CRITICAL                       ║
║     Track 0 unreadable, FAT likely damaged                       ║
║     Recommendation: Immediate deep imaging, try alternate drive  ║
║                                                                   ║
║  2. Disk #41 "Photos Backup" - CRITICAL                          ║
║     Multiple bad tracks, RPM unstable                            ║
║     Recommendation: Clean drive heads, retry with Drive 2        ║
║                                                                   ║
║  3. Disk #12 "Games Disk 3" - MARGINAL                           ║
║     Tracks 35-40 degraded (likely outer edge damage)             ║
║     Recommendation: Image now, quality may degrade further       ║
║                                                                   ║
║  DRIVES USED                                                      ║
║  ════════════════════════════════════════════════════════════    ║
║  Drive 0 (Sony MPF920): 47 disks, performing normally            ║
║  Drive 1: Not used                                               ║
║                                                                   ║
╚══════════════════════════════════════════════════════════════════╝
```

---

### 8.2 Batch Validation of Written Media

**QC Station for Disk Production:**

```
┌─────────────────────────────────────────────────────────────────┐
│                PRODUCTION QC WORKFLOW                            │
│                                                                  │
│  Input: Stack of freshly written disks                          │
│  Output: Pass/fail status + quality log                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   BATCH QC MODE                          │    │
│  │                                                          │    │
│  │  Current Batch: "RetroOS v2.1 Release Disks"            │    │
│  │  Pass Threshold: Quality > 90%                          │    │
│  │                                                          │    │
│  │  Progress: ████████████████████░░░░░░░░░░  52/100       │    │
│  │                                                          │    │
│  │  Results:                                                │    │
│  │    PASS: 49                                              │    │
│  │    FAIL:  3 (Disk #17, #31, #44)                        │    │
│  │                                                          │    │
│  │  Current Disk #52:                                       │    │
│  │    Track: 45/80                                          │    │
│  │    Quality: 94%                                          │    │
│  │    Status: ✓ Looking good                               │    │
│  │                                                          │    │
│  │  [PAUSE]  [ABORT]  [VIEW FAILURES]                      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Integration Options:                                            │
│  • Barcode scanner for disk ID tracking                         │
│  • Label printer for pass/fail stickers                         │
│  • Database export for batch records                            │
│  • Email alert on failure rate > threshold                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**QC Log Entry:**

```json
{
  "batch_id": "BATCH-2025-1203-001",
  "product": "RetroOS v2.1",
  "disk_serial": "ROS21-00052",
  "timestamp": "2025-12-03T19:50:23Z",
  "result": "PASS",
  "quality_score": 94.2,
  "tracks_tested": 80,
  "tracks_passed": 80,
  "min_track_quality": 89.1,
  "write_drive": "Drive 0",
  "verify_drive": "Drive 1",
  "operator": "Station-A"
}
```

---

## 9. Pure Nerd Fun

### 9.1 "Flux Zoo" Explorer

**Interactive Visualization:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUX ZOO EXPLORER                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Disk: "Mystery Disk from Grandpa's Attic"               │    │
│  │  Track: 17  Side: 0  Encoding: Unknown                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              FLUX TIMELINE (revolution 1)                │    │
│  │                                                          │    │
│  │  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▁▂▃▄▅   │    │
│  │  ↑                 ↑                    ↑                │    │
│  │  Sector 1          Sector 2             Weird gap!       │    │
│  │                                                          │    │
│  │  [Zoom +] [Zoom -] [Next Rev] [Overlay Revs]            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              TIMING HISTOGRAM                            │    │
│  │                                                          │    │
│  │   2µs ████████████████████████████ (4,521)              │    │
│  │   3µs ██████████████████████ (3,892)                    │    │
│  │   4µs ████████████████████████████████ (5,102)          │    │
│  │   5µs ██ (347) ← suspicious!                            │    │
│  │   6µs █ (89) ← very suspicious!                         │    │
│  │                                                          │    │
│  │  Analysis: Likely MFM with timing-based copy protection │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              JITTER HEATMAP                              │    │
│  │                                                          │    │
│  │  Rev 1: ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │    │
│  │  Rev 2: ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │    │
│  │  Rev 3: ░░░░░░░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │    │
│  │  Rev 4: ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │    │
│  │  Rev 5: ░░░░░░░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │    │
│  │               ↑                                         │    │
│  │          Weak bit region (changes between revolutions)  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.2 Generative Art from Flux Data

**"What Does Lotus 1-2-3 Sound Like?"**

```python
# flux_to_audio.py - Convert flux timing to audio

import numpy as np
from scipy.io import wavfile

def flux_to_audio(flux_timestamps, sample_rate=44100):
    """
    Convert flux transitions to audio.
    Each transition becomes a click/blip.
    Timing variations create rhythm and texture.
    """
    # Normalize timestamps to audio samples
    duration_sec = (flux_timestamps[-1] - flux_timestamps[0]) / 1e9
    total_samples = int(duration_sec * sample_rate)

    audio = np.zeros(total_samples)

    for ts in flux_timestamps:
        sample_pos = int((ts / 1e9) * sample_rate)
        if 0 <= sample_pos < total_samples:
            # Create a short blip
            blip = np.sin(np.linspace(0, 4*np.pi, 50)) * 0.3
            audio[sample_pos:sample_pos+len(blip)] += blip

    return audio

# Load flux data from FluxRipper
flux_data = load_flux_file("lotus123_track0.flux")
audio = flux_to_audio(flux_data.timestamps)

# Save as WAV
wavfile.write("lotus123_sonified.wav", 44100, audio.astype(np.float32))

# Result: A rhythmic clicking pattern that represents the data structure
# Dense areas (like the FAT) sound "busy"
# Gaps between sectors are audible silence
# Copy protection sounds "glitchy"
```

**Visual Art Example:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUX MANDALA                                  │
│                                                                  │
│  Each ring = one track                                          │
│  Color = flux density                                           │
│  Brightness = quality                                           │
│                                                                  │
│                        ╭───────────╮                            │
│                    ╭───┤           ├───╮                        │
│                ╭───┤   │ ░░░░░░░░░ │   ├───╮                    │
│            ╭───┤   │   │ ░▒▒▒▒▒▒░ │   │   ├───╮                │
│        ╭───┤   │   │   │ ░▒▓▓▓▒░ │   │   │   ├───╮            │
│    ╭───┤   │   │   │   │ ░▒▓█▓▒░ │   │   │   │   ├───╮        │
│    │   │   │   │   │   │ ░▒▓▓▓▒░ │   │   │   │   │   │        │
│    ╰───┤   │   │   │   │ ░▒▒▒▒▒░ │   │   │   │   ├───╯        │
│        ╰───┤   │   │   │ ░░░░░░░ │   │   │   ├───╯            │
│            ╰───┤   │   │         │   │   ├───╯                │
│                ╰───┤   │         │   ├───╯                    │
│                    ╰───┤         ├───╯                        │
│                        ╰─────────╯                            │
│                                                                  │
│  Track 0 (center): Boot sector - high density, good quality    │
│  Outer tracks: Progressively degraded on this old disk         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.3 Drive Personality Cards

**Collectible Trading Card Format:**

```
╔══════════════════════════════════════════════════════════════════╗
║  ┌────────────────────────────────────────────────────────────┐  ║
║  │                    ★ DRIVE CARD ★                          │  ║
║  │                                                            │  ║
║  │            ┌─────────────────────────┐                    │  ║
║  │            │      ┌───────────┐      │                    │  ║
║  │            │      │  ═══════  │      │                    │  ║
║  │            │      │   [====]  │      │                    │  ║
║  │            │      │           │      │                    │  ║
║  │            │      └───────────┘      │                    │  ║
║  │            │    SONY MPF920-Z        │                    │  ║
║  │            └─────────────────────────┘                    │  ║
║  │                                                            │  ║
║  │  STATS                              SPECIAL ABILITIES      │  ║
║  │  ═════                              ═════════════════      │  ║
║  │  RPM Stability:  ████████░░  8/10   "The Resurrector"     │  ║
║  │  MFM Quality:    █████████░  9/10   +2 to reads on       │  ║
║  │  GCR Quality:    ██████░░░░  6/10   damaged media        │  ║
║  │  Head Alignment: ████████░░  8/10                         │  ║
║  │  Reliability:    ███████░░░  7/10   WEAKNESS              │  ║
║  │                                      ═════════             │  ║
║  │  RARITY: ★★★☆☆ (Uncommon)           Struggles with       │  ║
║  │                                      Commodore GCR        │  ║
║  │  HIGH SCORE                                               │  ║
║  │  ══════════                                               │  ║
║  │  "Nastiest disk successfully read"                        │  ║
║  │  Water-damaged Lotus 1-2-3 (1987)                        │  ║
║  │  Quality achieved: 34% → Fully recovered!                │  ║
║  │                                                            │  ║
║  └────────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════════╝
```

**Card Rarity System:**

| Rarity | Criteria | Example |
|--------|----------|---------|
| Common | Standard PC drives | Generic Mitsumi |
| Uncommon | Good quality, specific strengths | Sony MPF920 |
| Rare | Exceptional performers | NEC FD1231H |
| Legendary | Vintage + excellent condition | Tandon TM-100 (working!) |
| Mythic | Historically significant + functional | Original IBM PC drive |

---

## Summary

FluxRipper isn't just a floppy disk controller—it's a **general-purpose magnetic storage observatory**. Whether you're:

- **Preserving history** (archivists, museums, collectors)
- **Analyzing protection** (researchers, security analysts)
- **Building tools** (developers, makers)
- **Teaching concepts** (educators, students)
- **Having fun** (retrocomputing enthusiasts)

...this platform provides the hardware foundation for virtually any floppy-related project imaginable.

The combination of:
- **4 concurrent drives** across dual interfaces
- **Flux-level capture** with precise timestamps
- **Signal quality metrics** per revolution
- **82077AA compatibility** for legacy software
- **Modern SoC architecture** with AXI buses
- **Open hardware design** for customization

...creates possibilities that go far beyond what any commercial floppy controller ever offered.

**Build something wonderful.**
