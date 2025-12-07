# Statistical Flux Recovery (FluxStat) - Design Document

*Created: 2025-12-04 16:00*

## Overview

This document describes how to implement DynaStat-like statistical bit recovery in FluxRipper, but with a key advantage: **we operate at the flux level, giving us access to raw magnetic domain data that SpinRite never sees**.

SpinRite's DynaStat works at the sector level—it re-reads decoded sectors and performs statistics on the *output* of the drive's controller. FluxRipper can perform statistics on the *raw flux transitions*, which gives us:

1. **More data points** - We see every flux transition, not just decoded bits
2. **Timing information** - We know *when* each transition occurred to ±5ns
3. **Pattern analysis** - We can analyze flux patterns across multiple reads
4. **Encoding-agnostic** - Works regardless of MFM, GCR, RLL, or unknown encoding

We call this capability **FluxStat**.

---

## Theoretical Foundation

### What DynaStat Does (Sector Level)

```
Multiple Sector Reads → Bit-by-bit comparison → Probability estimation → Best guess

Read 1: 10110010...  →  Bit 0: [1,1,1,1,0,1,1,1,1,1] = 90% confidence "1"
Read 2: 10110010...      Bit 1: [0,0,0,0,0,0,0,0,0,0] = 100% confidence "0"
Read 3: 10010010...      Bit 2: [1,1,0,1,1,1,0,1,1,1] = 70% confidence "1"
Read 4: 10110010...      ...
...                      Bit N: reconstruction
Read 2000: 10110010...
```

**Limitation**: Only sees decoded data. Drive firmware has already:
- Applied error correction (or failed)
- Discarded timing information
- Masked the actual flux behavior

### What FluxStat Does (Flux Level)

```
Multiple Flux Captures → Transition timing analysis → Bit cell reconstruction → Statistical decode

Capture 1: [0, 847, 1693, 2128, 2971, ...]  timestamps (5ns resolution)
Capture 2: [0, 851, 1687, 2131, 2965, ...]
Capture 3: [0, 844, 1699, 2125, 2978, ...]
...
Capture N: [0, 849, 1691, 2129, 2968, ...]

                 ↓ Statistical Analysis ↓

Bit Cell 0: Transition at 848±4ns → HIGH confidence "1"
Bit Cell 1: No transition (gap 846ns) → HIGH confidence "0"
Bit Cell 2: Transition at 2127±6ns, sometimes missing → MEDIUM confidence "1"
Bit Cell 3: Transition varies 2968-2985ns (wide spread) → LOW confidence, weak bit
```

**Advantages**:
- See the raw physics of the magnetic domain
- Detect *why* a bit is uncertain (timing jitter vs. missing transition vs. weak magnetization)
- Recover bits that would be unreadable through the controller

---

## Architecture

### System Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FluxStat Recovery Engine                            │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Multi-Pass Flux Capture                             │ │
│  │                                                                        │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │ │
│  │  │  Pass 1     │  │  Pass 2     │  │  Pass 3     │  │  Pass N     │    │ │
│  │  │  Flux Data  │  │  Flux Data  │  │  Flux Data  │  │  Flux Data  │    │ │
│  │  │  + Timing   │  │  + Timing   │  │  + Timing   │  │  + Timing   │    │ │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │ │
│  │         │                │                │                │           │ │
│  └─────────┼────────────────┼────────────────┼────────────────┼───────────┘ │
│            │                │                │                │             │
│            ▼                ▼                ▼                ▼             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Flux Alignment Engine                               │ │
│  │  • Index pulse alignment (track start)                                 │ │
│  │  • Flux transition correlation across passes                           │ │
│  │  • Time-base normalization (RPM compensation)                          │ │
│  └────────────────────────────────┬───────────────────────────────────────┘ │
│                                   │                                         │
│                                   ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Bit Cell Analyzer                                   │ │
│  │  • Divide track into bit cells based on data rate                      │ │
│  │  • For each cell: count transitions, measure timing spread             │ │
│  │  • Classify: STRONG_1, WEAK_1, STRONG_0, WEAK_0, AMBIGUOUS             │ │
│  └────────────────────────────────┬───────────────────────────────────────┘ │
│                                   │                                         │
│                                   ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Statistical Decoder                                 │ │
│  │  • Per-bit probability estimation                                      │ │
│  │  • Confidence scoring (0-100%)                                         │ │
│  │  • Weak bit flagging                                                   │ │
│  │  • CRC-guided correction                                               │ │
│  └────────────────────────────────┬───────────────────────────────────────┘ │
│                                   │                                         │
│                                   ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Output Generator                                    │ │
│  │  • Reconstructed sector data                                           │ │
│  │  • Per-bit confidence map                                              │ │
│  │  • Weak bit locations                                                  │ │
│  │  • Quality report                                                      │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
         Drive Head                    Index Pulse
              │                             │
              ▼                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          FPGA (200 MHz)                                     │
│                                                                             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────┐   │
│  │  Edge Detector   │───►│  Timestamp Gen   │───►│  Flux Stream FIFO    │   │
│  │  (3-stage sync)  │    │  (28-bit, 5ns)   │    │  (512 entries)       │   │
│  └──────────────────┘    └──────────────────┘    └──────────┬───────────┘   │
│                                                             │               │
└─────────────────────────────────────────────────────────────┼───────────────┘
                                                              │
                                                              ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                         HyperRAM (8 MB)                                      │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Pass Storage (up to 32 passes per track)                              │  │
│  │                                                                        │  │
│  │  Track 0:  [Pass 0: 50KB] [Pass 1: 50KB] ... [Pass N: 50KB]            │  │
│  │  Track 1:  [Pass 0: 50KB] [Pass 1: 50KB] ... [Pass N: 50KB]            │  │
│  │  ...                                                                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
                                                               │
                                                               ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MicroBlaze V (FluxStat Algorithm)                         │
│                                                                              │
│  1. Load N passes from HyperRAM                                              │
│  2. Align by index pulse                                                     │
│  3. Correlate flux transitions                                               │
│  4. Build bit cell probability matrix                                        │
│  5. Decode with confidence scoring                                           │
│  6. Output reconstructed data + quality map                                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Algorithm Details

### Phase 1: Multi-Pass Capture

Capture the same track N times (default N=8, up to 64 for difficult media):

```c
typedef struct {
    uint32_t pass_count;
    uint32_t flux_counts[MAX_PASSES];     // Transitions per pass
    uint32_t *flux_times[MAX_PASSES];     // Timestamp arrays
    uint32_t index_offset[MAX_PASSES];    // Index pulse position
    uint32_t total_time[MAX_PASSES];      // Total track time
} multipass_capture_t;
```

**Capture Strategy**:
- Wait for index pulse to align track start
- Capture exactly 1 revolution (index-to-index)
- Small variations in head position between passes help sample different parts of the magnetic domain

### Phase 2: Flux Alignment

Align multiple passes temporally:

```c
// Normalize all passes to same time base
// Account for RPM variation between passes
void flux_align(multipass_capture_t *capture) {
    // Use index-to-index time as reference
    uint32_t ref_period = capture->total_time[0];

    for (int pass = 1; pass < capture->pass_count; pass++) {
        // Scale factor for this pass
        float scale = (float)ref_period / capture->total_time[pass];

        // Rescale all timestamps
        for (int i = 0; i < capture->flux_counts[pass]; i++) {
            capture->flux_times[pass][i] *= scale;
        }
    }
}
```

### Phase 3: Bit Cell Analysis

For each bit cell position, analyze flux transitions across all passes:

```c
typedef struct {
    uint8_t  transition_count;     // How many passes had a transition here
    uint8_t  total_passes;         // Total passes analyzed
    uint16_t timing_mean;          // Mean transition time within cell
    uint16_t timing_stddev;        // Standard deviation of timing
    uint8_t  classification;       // STRONG_1, WEAK_1, STRONG_0, WEAK_0, AMBIGUOUS
    uint8_t  confidence;           // 0-100%
} bit_cell_stats_t;

// Classifications
#define CLASS_STRONG_1    0x01    // >90% of passes have transition, low jitter
#define CLASS_WEAK_1      0x02    // 50-90% have transition, or high jitter
#define CLASS_STRONG_0    0x03    // <10% have transition
#define CLASS_WEAK_0      0x04    // 10-50% have transition (suspicious)
#define CLASS_AMBIGUOUS   0x05    // ~50/50, cannot determine
```

**Classification Algorithm**:

```c
void classify_bit_cell(bit_cell_stats_t *cell) {
    float ratio = (float)cell->transition_count / cell->total_passes;

    if (ratio > 0.90) {
        if (cell->timing_stddev < JITTER_THRESHOLD_LOW) {
            cell->classification = CLASS_STRONG_1;
            cell->confidence = 95 + (5 * (1.0 - cell->timing_stddev / JITTER_THRESHOLD_LOW));
        } else {
            cell->classification = CLASS_WEAK_1;
            cell->confidence = 70 + (20 * ratio);
        }
    } else if (ratio < 0.10) {
        cell->classification = CLASS_STRONG_0;
        cell->confidence = 95 + (5 * (1.0 - ratio / 0.10));
    } else if (ratio < 0.50) {
        cell->classification = CLASS_WEAK_0;
        cell->confidence = 50 + (40 * (0.50 - ratio) / 0.40);
    } else if (ratio > 0.50) {
        cell->classification = CLASS_WEAK_1;
        cell->confidence = 50 + (40 * (ratio - 0.50) / 0.40);
    } else {
        cell->classification = CLASS_AMBIGUOUS;
        cell->confidence = 50;  // True 50/50
    }
}
```

### Phase 4: Statistical Decoding

Apply encoding rules with probability weighting:

```c
typedef struct {
    uint8_t  data_bit;           // Most likely bit value
    uint8_t  confidence;         // Confidence in this value
    uint8_t  weak_flag;          // 1 if this is a weak bit
    uint8_t  corrected;          // 1 if CRC correction was applied
} decoded_bit_t;

// MFM decoding with statistics
void decode_mfm_statistical(bit_cell_stats_t *cells, int cell_count,
                            decoded_bit_t *output, int *bit_count) {
    int out_idx = 0;

    for (int i = 0; i < cell_count; i += 2) {
        // MFM: pairs of cells (clock, data)
        bit_cell_stats_t *clock_cell = &cells[i];
        bit_cell_stats_t *data_cell = &cells[i + 1];

        // Data bit determination
        if (data_cell->classification == CLASS_STRONG_1 ||
            data_cell->classification == CLASS_WEAK_1) {
            output[out_idx].data_bit = 1;
        } else {
            output[out_idx].data_bit = 0;
        }

        // Confidence combining
        output[out_idx].confidence = data_cell->confidence;
        output[out_idx].weak_flag = (data_cell->classification == CLASS_WEAK_1 ||
                                     data_cell->classification == CLASS_WEAK_0 ||
                                     data_cell->classification == CLASS_AMBIGUOUS);
        output[out_idx].corrected = 0;
        out_idx++;
    }
    *bit_count = out_idx;
}
```

### Phase 5: CRC-Guided Correction

Use CRC to guide correction of uncertain bits:

```c
typedef struct {
    int bit_index;
    uint8_t original_value;
    uint8_t confidence;
} uncertain_bit_t;

// Try flipping uncertain bits to satisfy CRC
int crc_guided_correction(decoded_bit_t *bits, int bit_count,
                          uint8_t *sector_data, int sector_size) {
    // Find uncertain bits (below threshold)
    uncertain_bit_t uncertain[MAX_UNCERTAIN];
    int uncertain_count = 0;

    for (int i = 0; i < bit_count && uncertain_count < MAX_UNCERTAIN; i++) {
        if (bits[i].confidence < CONFIDENCE_THRESHOLD) {
            uncertain[uncertain_count].bit_index = i;
            uncertain[uncertain_count].original_value = bits[i].data_bit;
            uncertain[uncertain_count].confidence = bits[i].confidence;
            uncertain_count++;
        }
    }

    // Sort by confidence (try least confident first)
    sort_by_confidence(uncertain, uncertain_count);

    // Try combinations (limited to avoid exponential blowup)
    if (uncertain_count <= 8) {
        // Exhaustive search for small count
        for (uint32_t combo = 0; combo < (1 << uncertain_count); combo++) {
            // Apply combination
            for (int i = 0; i < uncertain_count; i++) {
                int idx = uncertain[i].bit_index;
                bits[idx].data_bit = uncertain[i].original_value ^ ((combo >> i) & 1);
            }

            // Rebuild sector and check CRC
            rebuild_sector(bits, bit_count, sector_data);
            if (verify_crc(sector_data, sector_size)) {
                // Mark corrected bits
                for (int i = 0; i < uncertain_count; i++) {
                    if ((combo >> i) & 1) {
                        bits[uncertain[i].bit_index].corrected = 1;
                    }
                }
                return 1;  // Success
            }
        }

        // Restore original values
        for (int i = 0; i < uncertain_count; i++) {
            bits[uncertain[i].bit_index].data_bit = uncertain[i].original_value;
        }
    }

    return 0;  // Could not correct
}
```

---

## Implementation Plan

### Phase 1: RTL Modifications

#### 1.1 Multi-Pass Capture Controller

New module: `rtl/recovery/multipass_capture.v`

```verilog
module multipass_capture #(
    parameter MAX_PASSES = 64,
    parameter PASS_SIZE  = 65536    // Max flux words per pass
)(
    input  wire        clk,
    input  wire        reset,

    // Control
    input  wire        start_capture,
    input  wire [5:0]  pass_count,       // Number of passes to capture
    input  wire        abort,
    output reg         capture_done,
    output reg         capture_active,
    output reg  [5:0]  current_pass,

    // Flux input
    input  wire        flux_edge,
    input  wire [27:0] flux_timestamp,
    input  wire        index_pulse,

    // Memory interface (to HyperRAM)
    output reg         mem_write,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_data,
    input  wire        mem_ready,

    // Pass metadata
    output reg  [31:0] pass_flux_count [0:MAX_PASSES-1],
    output reg  [31:0] pass_index_time [0:MAX_PASSES-1],
    output reg  [31:0] pass_total_time [0:MAX_PASSES-1]
);
```

#### 1.2 Flux Histogram Builder

New module: `rtl/recovery/flux_histogram.v`

Hardware-accelerated histogram of flux transition times:

```verilog
module flux_histogram #(
    parameter BIN_COUNT = 256,
    parameter BIN_WIDTH = 16
)(
    input  wire        clk,
    input  wire        reset,

    // Flux input
    input  wire        flux_valid,
    input  wire [15:0] flux_interval,    // Time since last flux

    // Control
    input  wire        clear,
    input  wire        enable,

    // Histogram output
    output wire [BIN_WIDTH-1:0] histogram [0:BIN_COUNT-1],
    output reg  [31:0] total_count,
    output reg  [15:0] peak_bin,
    output reg  [15:0] mean_interval
);
```

### Phase 2: Firmware Implementation

#### 2.1 FluxStat HAL

New files:
- `soc/firmware/include/fluxstat_hal.h`
- `soc/firmware/src/fluxstat_hal.c`

```c
// fluxstat_hal.h

#ifndef FLUXSTAT_HAL_H
#define FLUXSTAT_HAL_H

#include <stdint.h>

// Recovery configuration
typedef struct {
    uint8_t  pass_count;         // Number of capture passes (4-64)
    uint8_t  confidence_threshold; // Minimum confidence for "good" bit (0-100)
    uint8_t  max_correction_bits;  // Max bits to try correcting per sector
    uint8_t  encoding;           // MFM, FM, GCR, etc.
    uint32_t data_rate;          // Expected data rate
    uint8_t  use_crc_correction; // Enable CRC-guided correction
} fluxstat_config_t;

// Per-bit analysis result
typedef struct {
    uint8_t  value;              // Most likely bit value
    uint8_t  confidence;         // 0-100%
    uint8_t  weak;               // Weak bit flag
    uint8_t  corrected;          // Was CRC-corrected
} fluxstat_bit_t;

// Sector recovery result
typedef struct {
    uint8_t  data[4096];         // Recovered sector data
    uint16_t size;               // Sector size
    uint8_t  crc_ok;             // CRC verified
    uint8_t  confidence_min;     // Minimum bit confidence
    uint8_t  confidence_avg;     // Average bit confidence
    uint8_t  weak_bit_count;     // Number of weak bits
    uint8_t  corrected_count;    // Bits corrected by CRC guidance
    uint16_t weak_bit_map[32];   // Bit positions of weak bits (first 512)
} fluxstat_sector_t;

// Track recovery result
typedef struct {
    uint8_t  sector_count;
    fluxstat_sector_t sectors[32];
    uint8_t  sectors_recovered;
    uint8_t  sectors_partial;
    uint8_t  sectors_failed;
} fluxstat_track_t;

// API Functions
int fluxstat_init(void);
int fluxstat_configure(const fluxstat_config_t *config);
int fluxstat_capture_multipass(uint8_t track, uint8_t head);
int fluxstat_analyze_track(fluxstat_track_t *result);
int fluxstat_recover_sector(uint8_t sector, fluxstat_sector_t *result);
int fluxstat_get_bit_analysis(uint32_t bit_offset, uint32_t count,
                              fluxstat_bit_t *bits);

#endif
```

#### 2.2 FluxStat CLI

New files:
- `soc/firmware/include/fluxstat_cli.h`
- `soc/firmware/src/fluxstat_cli.c`

```
FluxRipper CLI Commands:

  fluxstat config [passes=N] [threshold=N] [correction=on|off]
    Configure FluxStat recovery parameters

  fluxstat capture <track> [head=N] [passes=N]
    Capture track with multiple passes

  fluxstat analyze
    Analyze captured flux data

  fluxstat recover [sector=N]
    Recover sector(s) with statistical analysis

  fluxstat map
    Display bit confidence map

  fluxstat export <filename>
    Export recovered data with quality annotations
```

### Phase 3: Analysis Algorithms

#### 3.1 Flux Correlator

```c
// Find corresponding transitions across passes
typedef struct {
    uint32_t time_sum;           // Sum of transition times
    uint32_t time_sum_sq;        // Sum of squares (for stddev)
    uint16_t hit_count;          // Passes with transition here
    uint16_t total_passes;
} flux_correlation_t;

void correlate_flux_passes(multipass_capture_t *capture,
                           flux_correlation_t *correlation,
                           int *correlation_count) {
    // Window for matching transitions (±tolerance)
    const uint32_t TOLERANCE = 100;  // 500ns at 5ns resolution

    // Use pass 0 as reference
    uint32_t *ref = capture->flux_times[0];
    int ref_count = capture->flux_counts[0];

    *correlation_count = ref_count;

    for (int i = 0; i < ref_count; i++) {
        correlation[i].time_sum = ref[i];
        correlation[i].time_sum_sq = ref[i] * ref[i];
        correlation[i].hit_count = 1;
        correlation[i].total_passes = capture->pass_count;
    }

    // Match other passes
    for (int pass = 1; pass < capture->pass_count; pass++) {
        uint32_t *flux = capture->flux_times[pass];
        int count = capture->flux_counts[pass];

        int ref_idx = 0;
        for (int j = 0; j < count && ref_idx < ref_count; j++) {
            // Find matching reference transition
            while (ref_idx < ref_count &&
                   ref[ref_idx] + TOLERANCE < flux[j]) {
                ref_idx++;
            }

            if (ref_idx < ref_count &&
                abs((int32_t)ref[ref_idx] - (int32_t)flux[j]) <= TOLERANCE) {
                // Match found
                correlation[ref_idx].time_sum += flux[j];
                correlation[ref_idx].time_sum_sq += flux[j] * flux[j];
                correlation[ref_idx].hit_count++;
            }
        }
    }

    // Calculate statistics
    for (int i = 0; i < ref_count; i++) {
        // Mean and stddev calculation would go here
    }
}
```

#### 3.2 Confidence Calculator

```c
uint8_t calculate_confidence(flux_correlation_t *corr) {
    float hit_ratio = (float)corr->hit_count / corr->total_passes;

    // Calculate timing variance
    float mean = (float)corr->time_sum / corr->hit_count;
    float variance = ((float)corr->time_sum_sq / corr->hit_count) - (mean * mean);
    float stddev = sqrtf(variance);

    // Confidence based on hit ratio and timing consistency
    float ratio_score = hit_ratio * 50.0f;  // 0-50 from hit ratio
    float timing_score = 50.0f * expf(-stddev / 50.0f);  // 0-50 from timing

    float confidence = ratio_score + timing_score;

    if (confidence > 100.0f) confidence = 100.0f;
    if (confidence < 0.0f) confidence = 0.0f;

    return (uint8_t)confidence;
}
```

---

## Memory Requirements

| Component | Size | Notes |
|-----------|------|-------|
| Single pass (1 track) | ~50 KB | ~12,500 flux transitions × 4 bytes |
| Multi-pass (8 passes) | ~400 KB | Per track |
| Multi-pass (32 passes) | ~1.6 MB | Per track |
| Correlation array | ~50 KB | Per track |
| Bit cell stats | ~100 KB | Per track |
| **Total per track** | **~2 MB** | With 32 passes |

HyperRAM capacity: 8 MB → Can process 4 tracks simultaneously or 1 track with 64+ passes.

---

## Performance Estimates

| Operation | Time | Notes |
|-----------|------|-------|
| Single pass capture | 200 ms | 1 revolution at 300 RPM |
| 8-pass capture | 1.6 sec | Sequential revolutions |
| 32-pass capture | 6.4 sec | For difficult media |
| Alignment (8 passes) | ~50 ms | MicroBlaze V @ 100 MHz |
| Bit cell analysis | ~100 ms | Per track |
| Statistical decode | ~200 ms | Per track |
| CRC correction search | ~500 ms | Worst case (8 uncertain bits) |
| **Total (8-pass)** | **~2.5 sec** | Per track |
| **Total (32-pass)** | **~8 sec** | Per track |

---

## Comparison: FluxStat vs DynaStat

| Aspect | FluxStat (FluxRipper) | DynaStat (SpinRite) |
|--------|----------------------|---------------------|
| **Data level** | Flux transitions | Decoded sectors |
| **Timing info** | 5ns resolution | None |
| **Max retries** | 64 passes | 2000 re-reads |
| **Analysis** | Per-flux-cell statistics | Per-bit voting |
| **Weak bit detection** | Timing jitter analysis | Bit flip rate |
| **CRC correction** | Same | Same |
| **Head repositioning** | Natural variation | Deliberate seeks |
| **Encoding support** | Any (flux-level) | Controller-dependent |
| **Output** | Data + confidence map | Data only |
| **Copy protection** | Preserved | Lost |

---

## Use Cases

### 1. Marginal Floppy Recovery

```
> fluxstat capture 12 passes=16
Capturing track 12 with 16 passes...
Pass 1/16... 12,345 transitions
Pass 2/16... 12,351 transitions
...
Pass 16/16... 12,348 transitions

> fluxstat analyze
Track 12 Analysis:
  Total flux positions: 12,347 (averaged)
  Strong bits: 98,456 (92.3%)
  Weak bits: 7,891 (7.4%)
  Ambiguous: 312 (0.3%)

> fluxstat recover
Recovering sectors...
  Sector 0: OK (confidence 98%)
  Sector 1: OK (confidence 95%)
  Sector 2: RECOVERED (3 bits CRC-corrected, confidence 87%)
  Sector 3: OK (confidence 96%)
  ...
  Sector 8: PARTIAL (12 uncertain bits, confidence 62%)

8/9 sectors fully recovered, 1 partial
```

### 2. Copy-Protected Disk Preservation

```
> fluxstat capture 0 passes=32
> fluxstat analyze
Track 0 Analysis:
  Detected: Intentional weak bits at positions 4521-4536
  Pattern: Copy protection signature (Prolok-style)

> fluxstat export track0_preserved.flux
Exported with weak bit annotations.
Weak bits preserved at original positions.
```

### 3. Unknown Format Recovery

```
> fluxstat capture 0 passes=8
> fluxstat analyze
Track 0 Analysis:
  Encoding: Unknown (not MFM/GCR/FM)
  Bit cell period: 3.2µs (312.5 Kbps)
  Flux density: 12,500 transitions/track

> fluxstat export track0_raw.flux
Exported raw flux with statistics.
Analyze offline to determine encoding.
```

---

## Implementation Priority

| Priority | Component | Effort | Value |
|----------|-----------|--------|-------|
| 1 | Multi-pass capture controller | Medium | High |
| 2 | Flux alignment algorithm | Low | High |
| 3 | Bit cell analyzer | Medium | High |
| 4 | Statistical MFM decoder | Medium | High |
| 5 | CRC-guided correction | Low | Medium |
| 6 | CLI interface | Low | Medium |
| 7 | GCR/FM statistical decoders | Medium | Medium |
| 8 | Hardware histogram accelerator | High | Low |

**Estimated Total Effort**: 2-3 weeks for full implementation

---

## References

- [SpinRite DynaStat Overview](https://www.grc.com/srrecovery.htm)
- [DynaStat Analysis (John Willis)](https://www.johnwillis.com/2018/12/spinrite-puzzle-pieces-dynastat.html)
- [SpinRite Wikipedia](https://en.wikipedia.org/wiki/SpinRite)
- FluxRipper Digital PLL: `rtl/data_separator/digital_pll.v`
- FluxRipper Flux Capture: `rtl/axi/axi_stream_flux.v`
