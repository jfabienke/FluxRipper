# FluxRipper Instrumentation Architecture

*Created: 2025-12-04 14:45*
*Updated: 2025-12-04 14:45*

## Overview

The FluxRipper instrumentation subsystem provides comprehensive diagnostic capabilities for analyzing drive health, media condition, and system performance. This goes far beyond simple error reporting—it enables forensic-level analysis of vintage storage systems, predictive failure detection, and guided repair workflows.

## Architecture

### Instrumentation Layers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FluxRipper Instrumentation Architecture                  │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        CLI / User Interface                            │ │
│  │   diag errors │ diag pll │ diag fifo │ diag capture │ diag seek        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                    Instrumentation HAL (C Firmware)                    │ │
│  │   diag_read_errors() │ diag_read_pll() │ diag_read_fifo() │ etc.       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                 Memory-Mapped Register Interface                       │ │
│  │                    DIAG_BASE (0xA000) + offsets                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                        RTL Diagnostics Modules                         │ │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │ │
│  │  │    Error     │ │     PLL      │ │    FIFO      │ │    Seek      │   │ │
│  │  │   Counters   │ │ Diagnostics  │ │  Statistics  │ │  Histogram   │   │ │
│  │  │              │ │              │ │              │ │   (HDD)      │   │ │
│  │  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘   │ │
│  │         │                │                │                │           │ │
│  │  ┌──────▼────────────────▼────────────────▼────────────────▼───────┐   │ │
│  │  │                    Capture Timing Module                        │   │ │
│  │  │   Duration │ Time-to-first │ Index periods │ Flux intervals     │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                        Physical Data Path                              │ │
│  │   DPLL │ AM Detector │ Encoders │ Step Controller │ Flux Capture       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Instrumentation Modules

| Module | File | Lines | Purpose |
|--------|------|-------|---------|
| Error Counters | `error_counters.v` | ~200 | Lifetime error tracking, per-track stats |
| PLL Diagnostics | `pll_diagnostics.v` | ~260 | Phase/frequency analysis, lock statistics |
| FIFO Statistics | `fifo_statistics.v` | ~360 | Buffer health, throughput metrics |
| Capture Timing | `fifo_statistics.v` | (incl.) | Timing analysis, RPM calculation |
| Seek Histogram | `seek_histogram.v` | ~260 | HDD mechanical characterization |

---

## Subsystem Details

### 1. Lifetime Error Counters

Tracks cumulative error counts across all operations, providing insight into media degradation and drive health.

#### Error Types Tracked

| Error | Register | Description | Typical Cause |
|-------|----------|-------------|---------------|
| CRC Data | `DIAG_ERR_CRC_DATA` | CRC error in data field | Media degradation, alignment |
| CRC Address | `DIAG_ERR_CRC_ADDR` | CRC error in ID field | Weak address marks |
| Missing AM | `DIAG_ERR_MISSING_AM` | Missing address mark | Formatting issues, weak signal |
| Missing DAM | `DIAG_ERR_MISSING_DAM` | Missing data address mark | Corrupt sector header |
| Overrun | `DIAG_ERR_OVERRUN` | Data overrun | System too slow, DMA issue |
| Underrun | `DIAG_ERR_UNDERRUN` | Data underrun | Write buffer starvation |
| Seek | `DIAG_ERR_SEEK` | Seek error/timeout | Mechanical failure |
| Write Fault | `DIAG_ERR_WRITE_FAULT` | Write fault from drive | Head crash, media damage |
| PLL Unlock | `DIAG_ERR_PLL_UNLOCK` | PLL lost lock | Weak signal, speed variation |

#### Error Rate Calculation

The system calculates errors per 1000 operations:

```
Error Rate = (Total Errors × 1000) / Total Operations
```

Saturating at 255 to fit in 8 bits.

#### Per-Track Error Statistics

The `track_error_stats` submodule maintains per-track error counts:
- 8-bit saturating counter per track (max 255 errors)
- Automatic "worst track" identification
- Query interface for specific track error counts

### 2. PLL/DPLL Diagnostics

Exposes the Digital Phase-Locked Loop internal state for tuning and analysis.

#### Phase Error Metrics

| Metric | Description | Use Case |
|--------|-------------|----------|
| Instantaneous | Raw phase detector output | Real-time jitter analysis |
| Average (EMA) | Exponentially weighted moving average (α=1/16) | Trend analysis |
| Peak | Maximum absolute phase error seen | Worst-case jitter |

#### Frequency Offset

Calculated in parts per million (PPM) from nominal:

```
PPM = ((actual_freq_word - nominal_freq_word) / nominal_freq_word) × 1,000,000
```

Typical values:
- Good drive: ±50 PPM
- Marginal: ±200 PPM
- Failing: >500 PPM

#### Lock Statistics

| Metric | Description |
|--------|-------------|
| Lock Time | Clocks to achieve lock from last unlock |
| Total Lock Time | Cumulative time in locked state |
| Unlock Count | Number of lock loss events |
| Quality Min/Avg/Max | Lock quality score (0-255) |

#### Phase Error Histogram

8-bin histogram for jitter distribution analysis:

```
Bin 0: Very Early   (<-3σ)     ████
Bin 1: Early        (-3σ to -2σ)  ██████████
Bin 2: Slightly Early (-2σ to -σ)   ████████████████
Bin 3: On Time (-)  (-σ to 0)    ██████████████████████████
Bin 4: On Time (+)  (0 to +σ)    ████████████████████████████
Bin 5: Slightly Late (+σ to +2σ)    ██████████████
Bin 6: Late         (+2σ to +3σ)  ████████
Bin 7: Very Late    (>+3σ)      ███
```

Ideal distribution: Bell curve centered on bins 3-4.

### 3. FIFO Statistics

Monitors the flux capture FIFO for throughput and health.

#### Fill Level Tracking

| Metric | Description |
|--------|-------------|
| Peak Level | Maximum fill level (high water mark) |
| Min Level | Minimum fill level during capture |
| Utilization % | Average fill percentage |

#### Event Counters

| Counter | Description | Impact |
|---------|-------------|--------|
| Overflow Count | Write attempts when full | **Data loss** |
| Underrun Count | Read attempts when empty | Processing stall |
| Backpressure Cnt | TREADY deassertions | DMA slowdown |
| Total Writes | Total flux words written | Throughput metric |
| Total Reads | Total flux words read | Throughput metric |

#### Time Tracking (Clocks)

| Metric | Description |
|--------|-------------|
| Time at Peak | Clocks spent at peak fill level |
| Time Empty | Clocks spent with FIFO empty |
| Time Full | Clocks spent with FIFO full |

#### Sticky Flags

- **Overflow Flag**: Set on first overflow, cleared manually
- **Underrun Flag**: Set on first underrun, cleared manually

### 4. Capture Timing

Provides detailed timing analysis during flux capture.

#### Duration Metrics

| Metric | Description |
|--------|-------------|
| Total Duration | Capture time in clocks |
| Time to First Flux | Clocks from start to first flux transition |
| Time to First Index | Clocks from start to first index pulse |

#### Index Period Analysis

| Metric | Description | Use Case |
|--------|-------------|----------|
| Last | Most recent index-to-index period | Current RPM |
| Min | Minimum period seen | Speed variation range |
| Max | Maximum period seen | Speed variation range |
| Average (EMA) | Smoothed average (α=1/8) | Stable RPM estimate |

**RPM Calculation:**

```
RPM = 60,000,000 / (Index_Period_µs)

At 200 MHz clock:
- 300 RPM: ~40,000,000 clocks (200ms)
- 360 RPM: ~33,333,333 clocks (166.7ms)
```

#### Flux Interval Analysis

| Metric | Description |
|--------|-------------|
| Min Interval | Minimum flux-to-flux interval |
| Max Interval | Maximum flux-to-flux interval |
| Flux Count | Total flux transitions captured |

### 5. Seek Histogram (HDD Only)

Characterizes hard drive mechanical behavior by tracking seek operations.

#### Distance Buckets

| Bucket | Range | Typical HDD | Description |
|--------|-------|-------------|-------------|
| 0 | 0-1 cyl | ~3ms | Track-to-track |
| 1 | 2-10 cyl | ~5ms | Short seek |
| 2 | 11-25 cyl | ~8ms | Short-medium |
| 3 | 26-50 cyl | ~12ms | Medium |
| 4 | 51-100 cyl | ~18ms | Medium-long |
| 5 | 101-200 cyl | ~25ms | Long |
| 6 | 201-500 cyl | ~35ms | Very long |
| 7 | 501+ cyl | ~45ms | Full stroke |

#### Per-Bucket Metrics

- **Count**: Number of seeks in this bucket
- **Average Time (µs)**: Mean seek time for this distance

#### Summary Statistics

| Metric | Description |
|--------|-------------|
| Total Seeks | Total seek operations |
| Total Errors | Failed seek operations |
| Avg Time | Overall average seek time |
| Min Time | Fastest seek observed |
| Max Time | Slowest seek observed |

#### Error Categorization

| Category | Distance | Typical Cause |
|----------|----------|---------------|
| Short | <25 cyl | Head positioning fine adjustment |
| Medium | 25-100 cyl | Servo calibration |
| Long | >100 cyl | Voice coil/servo failure |

---

## Register Map

All instrumentation registers are memory-mapped at `DIAG_BASE` (PERIPH_BASE + 0xA000).

### Error Counters (0x00-0x2C)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | DIAG_ERR_CRC_DATA | R | CRC data field errors |
| 0x04 | DIAG_ERR_CRC_ADDR | R | CRC address field errors |
| 0x08 | DIAG_ERR_MISSING_AM | R | Missing address mark |
| 0x0C | DIAG_ERR_MISSING_DAM | R | Missing data address mark |
| 0x10 | DIAG_ERR_OVERRUN | R | Data overrun count |
| 0x14 | DIAG_ERR_UNDERRUN | R | Data underrun count |
| 0x18 | DIAG_ERR_SEEK | R | Seek error count |
| 0x1C | DIAG_ERR_WRITE_FAULT | R | Write fault count |
| 0x20 | DIAG_ERR_PLL_UNLOCK | R | PLL unlock events |
| 0x24 | DIAG_ERR_TOTAL | R | Total error count |
| 0x28 | DIAG_ERR_RATE | R | Errors per 1000 ops [7:0] |
| 0x2C | DIAG_ERR_CTRL | W | Control (bit 0 = clear all) |

### PLL Diagnostics (0x30-0x64)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x30 | DIAG_PLL_PHASE_ERR | R | Instantaneous phase error |
| 0x34 | DIAG_PLL_FREQ_WORD | R | NCO frequency word |
| 0x38 | DIAG_PLL_PHASE_AVG | R | Averaged phase error |
| 0x3C | DIAG_PLL_PHASE_PEAK | R | Peak phase error |
| 0x40 | DIAG_PLL_FREQ_PPM | R | Frequency offset (signed PPM) |
| 0x44 | DIAG_PLL_LOCK_TIME | R | Time to achieve lock |
| 0x48 | DIAG_PLL_TOTAL_LOCK | R | Total time locked |
| 0x4C | DIAG_PLL_UNLOCK_CNT | R | Unlock event count |
| 0x50 | DIAG_PLL_QUALITY | R | Quality [23:16]=avg [15:8]=max [7:0]=min |
| 0x54 | DIAG_PLL_HIST_01 | R | Histogram bins 0,1 [31:16]=bin1 [15:0]=bin0 |
| 0x58 | DIAG_PLL_HIST_23 | R | Histogram bins 2,3 |
| 0x5C | DIAG_PLL_HIST_45 | R | Histogram bins 4,5 |
| 0x60 | DIAG_PLL_HIST_67 | R | Histogram bins 6,7 |
| 0x64 | DIAG_PLL_CTRL | W | Control (bit 0 = snapshot, bit 1 = clear) |

### FIFO Statistics (0x70-0x98)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x70 | DIAG_FIFO_PEAK | R | Peak/min level [31:16]=min [15:0]=peak |
| 0x74 | DIAG_FIFO_OVERFLOW | R | Overflow count |
| 0x78 | DIAG_FIFO_UNDERRUN | R | Underrun count |
| 0x7C | DIAG_FIFO_BACKPRESS | R | Backpressure count |
| 0x80 | DIAG_FIFO_WRITES | R | Total writes |
| 0x84 | DIAG_FIFO_READS | R | Total reads |
| 0x88 | DIAG_FIFO_TIME_PEAK | R | Time at peak (clocks) |
| 0x8C | DIAG_FIFO_TIME_EMPTY | R | Time empty (clocks) |
| 0x90 | DIAG_FIFO_TIME_FULL | R | Time full (clocks) |
| 0x94 | DIAG_FIFO_UTIL | R | Utilization [9]=underrun [8]=overflow [7:0]=% |
| 0x98 | DIAG_FIFO_CTRL | W | Control (bit 0 = clear) |

### Capture Timing (0xA0-0xC8)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0xA0 | DIAG_CAP_DURATION | R | Total capture duration (clocks) |
| 0xA4 | DIAG_CAP_FIRST_FLUX | R | Time to first flux |
| 0xA8 | DIAG_CAP_FIRST_IDX | R | Time to first index |
| 0xAC | DIAG_CAP_IDX_PERIOD | R | Last index period |
| 0xB0 | DIAG_CAP_IDX_MIN | R | Minimum index period |
| 0xB4 | DIAG_CAP_IDX_MAX | R | Maximum index period |
| 0xB8 | DIAG_CAP_IDX_AVG | R | Average index period (EMA) |
| 0xBC | DIAG_CAP_FLUX_MIN | R | Minimum flux interval |
| 0xC0 | DIAG_CAP_FLUX_MAX | R | Maximum flux interval |
| 0xC4 | DIAG_CAP_FLUX_CNT | R | Total flux count [15:0] |
| 0xC8 | DIAG_CAP_CTRL | W | Control (bit 0 = clear) |

### Seek Histogram (0xD0-0x11C) - HDD Only

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0xD0-0xEC | DIAG_SEEK_HIST[0-7] | R | Seek count per bucket |
| 0xF0-0x10C | DIAG_SEEK_TIME[0-7] | R | Avg time per bucket (µs) |
| 0x110 | DIAG_SEEK_TOTAL | R | Total seek count |
| 0x114 | DIAG_SEEK_ERRORS | R | Total seek errors |
| 0x118 | DIAG_SEEK_AVG_TIME | R | Overall average [31:16]=min [15:0]=avg |
| 0x11C | DIAG_SEEK_CTRL | W | Control (bit 0 = clear) |

---

## CLI Reference

### Command Syntax

```
diag <subcommand> [options]
```

### Available Subcommands

| Command | Description |
|---------|-------------|
| `diag errors` | Display lifetime error counters |
| `diag pll` | Display PLL/DPLL diagnostics with histogram |
| `diag fifo` | Display FIFO statistics and health |
| `diag capture` | Display capture timing analysis |
| `diag seek` | Display seek histogram (HDD only) |
| `diag clear [cat]` | Clear statistics (all or by category) |
| `diag all` | Display complete diagnostics summary |

### Example Output

#### Error Counters
```
FluxRipper> diag errors

Lifetime Error Counters
-----------------------------------------
  CRC Data:       47
  CRC Address:    3
  Missing AM:     12
  Missing DAM:    0
  Overrun:        0
  Underrun:       0
  Seek:           0
  Write Fault:    0
  PLL Unlock:     8
-----------------------------------------
  Total:          70
  Error Rate:     2 per 1000 ops
-----------------------------------------
```

#### PLL Diagnostics
```
FluxRipper> diag pll

PLL/DPLL Diagnostics
-----------------------------------------
Phase Error:
  Instantaneous:  -127
  Average (EMA):  45
  Peak:           892

Frequency:
  NCO Word:       0x00A3D70A
  Offset:         +23 PPM

Lock Statistics:
  Lock Time:      4521 clocks
  Total Locked:   892341567 clocks
  Unlock Events:  8

Quality (0-255):
  Min/Avg/Max:    178 / 223 / 247

Phase Error Histogram:
  [Very Early]    12   145   892  3421  3567   923   187    34 [Very Late]

                            ##### #####
                      ##### ##### #####
                ##### ##### ##### ##### #####
          ##### ##### ##### ##### ##### ##### #####
    ##### ##### ##### ##### ##### ##### ##### #####
  -3sig -2sig -1sig  <0   >0  +1sig +2sig +3sig
-----------------------------------------
```

#### FIFO Statistics
```
FluxRipper> diag fifo

FIFO Statistics
-----------------------------------------
Fill Level:
  Peak:           478
  Minimum:        12
  Utilization:    34%

Event Counts:
  Overflows:      0
  Underruns:      0
  Backpressure:   1247

Throughput:
  Total Writes:   8923456
  Total Reads:    8923456

Timing (clocks):
  Time at Peak:   12345
  Time Empty:     892341
  Time Full:      0
-----------------------------------------
Health: OK
```

#### Capture Timing
```
FluxRipper> diag capture

Capture Timing Statistics
-----------------------------------------
Duration:           40000000 clocks (200 ms)

First Events:
  Time to 1st flux: 1234 clocks (6 us)
  Time to 1st idx:  234567 clocks (1172 us)

Index Period:
  Last:             40012345 clocks (200061 us)
  Min:              39987654 clocks (199938 us)
  Max:              40023456 clocks (200117 us)
  Avg (EMA):        40000123 clocks (200000 us)
  Calculated RPM:   299

Flux Intervals:
  Min:              156 clocks
  Max:              412 clocks
  Count:            123456 transitions
-----------------------------------------
```

#### Seek Histogram (HDD)
```
FluxRipper> diag seek

Seek Distance Histogram (HDD)
-----------------------------------------
Distance Bucket     Count    Avg Time
-----------------------------------------
  0-1 cyl           1234      3200 us
  2-10 cyl          5678      5100 us
  11-25 cyl         2345      8200 us
  26-50 cyl         1123     12100 us
  51-100 cyl         567     18400 us
  101-200 cyl        234     25300 us
  201-500 cyl         89     34800 us
  501+ cyl            12     45200 us
-----------------------------------------
  Total Seeks:      11282
  Total Errors:     3
  Average Time:     7823 us
  Min Time:         3100 us
  Max Time:         48200 us

Errors by Distance:
  Short (<25 cyl):  1
  Medium (25-100):  1
  Long (>100 cyl):  1
-----------------------------------------

Distribution:
  0: ##############################
  1: ################################################
  2: ####################
  3: #########
  4: ####
  5: ##
  6: #
  7:
```

---

## Use Cases

### 1. Drive Health Assessment

**Goal**: Determine overall health of a floppy or hard drive.

**Procedure**:
1. Clear all statistics: `diag clear`
2. Read multiple tracks (e.g., full disk scan)
3. Review diagnostics: `diag all`

**Interpretation**:

| Metric | Good | Marginal | Failing |
|--------|------|----------|---------|
| Error Rate | <1 per 1000 | 1-10 per 1000 | >10 per 1000 |
| PLL Unlock Events | 0 | 1-5 | >5 |
| PLL Quality Avg | >200 | 150-200 | <150 |
| Frequency Offset | <±50 PPM | ±50-200 PPM | >±200 PPM |
| FIFO Overflows | 0 | 0 | Any |
| RPM Variance | <0.1% | 0.1-0.5% | >0.5% |

**Healthy Drive Output**:
```
Error Rate:     0 per 1000 ops
PLL Unlock:     0
Quality Avg:    234
Freq Offset:    +12 PPM
Overflows:      0
RPM:            300 (variance: 0.02%)

Assessment: GOOD - Drive is healthy
```

**Failing Drive Output**:
```
Error Rate:     47 per 1000 ops
PLL Unlock:     23
Quality Avg:    142
Freq Offset:    +387 PPM
Overflows:      0
RPM:            298 (variance: 1.2%)

Assessment: FAILING - Replace drive or clean heads
```

### 2. Media Quality Analysis

**Goal**: Identify weak tracks and bad sectors on disk media.

**Procedure**:
1. Clear statistics: `diag clear`
2. Read all tracks on disk
3. Check per-track error stats
4. Identify worst tracks

**Weak Track Indicators**:
- High CRC error count on specific track
- PLL unlock events concentrated on certain tracks
- Phase error histogram shifts during track

**Example Analysis**:
```
Track Error Summary:
  Track 12:   45 errors (WEAK)
  Track 37:   23 errors (MARGINAL)
  Track 79:    8 errors (MARGINAL)
  All others:  0 errors

Recommendation: Re-image track 12 multiple times and combine
```

### 3. PLL Tuning for Difficult Media

**Goal**: Optimize DPLL settings for marginal disks.

**Procedure**:
1. Capture track with default settings
2. Examine `diag pll` histogram
3. Adjust loop bandwidth if needed
4. Re-capture and compare

**Histogram Interpretation**:

| Shape | Meaning | Action |
|-------|---------|--------|
| Narrow bell | Good lock | No change needed |
| Wide bell | Noisy signal | Increase bandwidth |
| Bimodal | Speed variation | Enable RPM compensation |
| Skewed | Frequency offset | Increase acquisition range |
| Flat | Very poor signal | May need head cleaning |

### 4. Speed Variation Detection

**Goal**: Detect drives with motor speed problems.

**Procedure**:
1. Clear capture timing: `diag clear capture`
2. Capture several revolutions
3. Analyze index period variance

**Calculation**:
```
Speed Variance (%) = ((Max_Period - Min_Period) / Avg_Period) × 100
```

**Thresholds**:
| Variance | Assessment | Action |
|----------|------------|--------|
| <0.1% | Excellent | None |
| 0.1-0.3% | Good | None |
| 0.3-0.5% | Marginal | Monitor |
| 0.5-1.0% | Poor | Lubricate motor |
| >1.0% | Failing | Replace drive |

### 5. Data Transfer Health (FIFO Analysis)

**Goal**: Detect system bottlenecks affecting capture.

**Procedure**:
1. Clear FIFO stats: `diag clear fifo`
2. Perform long capture session
3. Analyze FIFO utilization

**Warning Signs**:

| Metric | Threshold | Meaning |
|--------|-----------|---------|
| Utilization >80% | Warning | System is struggling |
| Any overflow | Critical | Data loss occurred |
| Backpressure >10% | Warning | DMA slowdowns |
| Time Full >0 | Critical | System too slow |

**Root Causes**:
- High CPU load during capture
- Insufficient DMA bandwidth
- HyperRAM contention
- USB backpressure

### 6. HDD Mechanical Analysis

**Goal**: Characterize hard drive head positioning system.

**Procedure**:
1. Clear seek stats: `diag clear seek`
2. Perform random seeks across disk surface
3. Analyze seek histogram

**Healthy HDD Pattern**:
- Track-to-track (0-1 cyl): 3-5ms
- Short seeks increase proportionally
- No seek errors
- Consistent timing within buckets

**Failing HDD Signs**:
| Symptom | Possible Cause |
|---------|----------------|
| Track-to-track >10ms | Head positioning system wear |
| High long-seek errors | Voice coil weakness |
| Inconsistent bucket times | Servo calibration drift |
| Many errors on all distances | Head crash imminent |

### 7. Comparative Drive Testing

**Goal**: Compare two drives for quality difference.

**Procedure**:
1. Test Drive A:
   - `diag clear`
   - Read standard test disk
   - Save output: `diag all`
2. Test Drive B:
   - Same procedure
3. Compare metrics

**Key Comparison Points**:
- Error rates on same media
- PLL quality and stability
- Speed variance
- Seek timing (HDD)

### 8. Pre-Imaging Assessment

**Goal**: Determine optimal imaging strategy before preservation.

**Procedure**:
1. Quick scan of track 0, 40, 79 (or equivalent)
2. Check diagnostics
3. Choose imaging approach

**Decision Matrix**:

| Assessment | Strategy |
|------------|----------|
| Healthy | Single pass, standard settings |
| Marginal | 3-pass average, increased retries |
| Weak tracks | 5+ passes on weak, combine |
| Failing drive | Multiple drives, flux-level capture |

---

## Repair Guidance

### Common Issues and Resolutions

#### Issue: High CRC Error Rate

**Symptoms**:
- `diag errors` shows elevated CRC counts
- Errors distributed across tracks

**Causes & Fixes**:

| Cause | Fix |
|-------|-----|
| Dirty heads | Clean with IPA and lint-free cloth |
| Head alignment | Adjust azimuth alignment |
| Worn media | Accept losses, multi-pass imaging |
| Wrong density | Check media type, adjust settings |

#### Issue: PLL Won't Lock

**Symptoms**:
- High unlock count
- Low quality scores
- Wide/flat histogram

**Causes & Fixes**:

| Cause | Fix |
|-------|-----|
| No disk signal | Check drive cable, motor running |
| Wrong data rate | Auto-detect or manual set |
| Severely degraded media | Try multiple drives |
| Drive alignment | Radial alignment adjustment |

#### Issue: FIFO Overflows

**Symptoms**:
- Overflow count > 0
- Utilization peaked at 100%
- Incomplete captures

**Causes & Fixes**:

| Cause | Fix |
|-------|-----|
| CPU overload | Close background tasks |
| USB bandwidth | Use shorter cable, different port |
| DMA not active | Check DMA configuration |
| Very high flux rate | Reduce capture rate |

#### Issue: RPM Variation

**Symptoms**:
- Large index period min/max spread
- Audible speed variation
- Intermittent PLL unlock

**Causes & Fixes**:

| Cause | Fix |
|-------|-----|
| Motor wear | Lubricate spindle bearing |
| Belt slip | Replace drive belt |
| Power supply sag | Check 12V rail under load |
| Bad capacitors | Recap motor driver |

#### Issue: HDD Seek Errors

**Symptoms**:
- Non-zero seek error count
- Long seek times
- Clicking sounds

**Causes & Fixes**:

| Cause | Fix |
|-------|-----|
| Sticky heads | Gentle tap on enclosure (last resort) |
| Servo track damage | Park heads, run low-level format |
| Voice coil failure | Replace actuator (advanced) |
| Power supply | Ensure adequate 12V for motor |

---

## Best Practices

### Regular Monitoring

1. **Clear stats before each session**: `diag clear`
2. **Check after significant operations**: `diag all`
3. **Log results for trending**: Save output to file

### Threshold Alerts

Set up monitoring for:
- Error rate > 5 per 1000
- PLL unlock count increases
- Any FIFO overflow
- RPM variance > 0.5%

### Preventive Maintenance

Based on instrumentation data:

| Metric Trend | Action |
|--------------|--------|
| Gradual error increase | Schedule head cleaning |
| RPM drift | Plan motor service |
| Seek time increase | HDD bearing wear, backup urgently |
| Quality degradation | Drive replacement soon |

### Documentation

For each drive/disk:
1. Baseline diagnostics when known good
2. Pre-imaging assessment
3. Post-imaging verification
4. Note any anomalies

---

## Implementation Files

### RTL Modules

| File | Location | Lines |
|------|----------|-------|
| error_counters.v | rtl/diagnostics/ | 203 |
| pll_diagnostics.v | rtl/diagnostics/ | 257 |
| fifo_statistics.v | rtl/diagnostics/ | 361 |
| seek_histogram.v | rtl/diagnostics/ | 263 |

### Firmware

| File | Location | Lines |
|------|----------|-------|
| instrumentation_hal.h | soc/firmware/include/ | 295 |
| instrumentation_hal.c | soc/firmware/src/ | 302 |
| instrumentation_cli.h | soc/firmware/include/ | 31 |
| instrumentation_cli.c | soc/firmware/src/ | 433 |

### Total Implementation

- **RTL**: ~1,084 lines Verilog
- **Firmware**: ~1,061 lines C
- **Total**: ~2,145 lines

---

## Related Documentation

- [Architecture Overview](architecture.md) - System block diagrams
- [Register Map](register_map.md) - Complete register reference
- [Power Monitoring](power_monitoring.md) - Power subsystem instrumentation
- [Drive Support](drive_support.md) - Supported drive types
