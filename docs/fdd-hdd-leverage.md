# FDD → HDD Code Leverage Analysis

*FluxRipper Universal Storage Architecture*

*Created: 2025-12-04 09:12:00*

---

## Executive Summary

The FluxRipper floppy (FDD) codebase provides **~40% effort savings** when extending to HDD support. This document details the reuse analysis across all modules.

| Metric | Value |
|--------|-------|
| FDD code leveraged | ~1,800 lines |
| HDD-specific new code | ~4,665 lines |
| Effort saved | ~40% |
| Highest reuse modules | NCO, MFM decoder, CRC (100%) |

---

## High Leverage Modules (Direct Reuse)

These modules required minimal or no changes - only parameter adjustments.

| FDD Module | HDD Equivalent | Reuse % | Changes Required |
|------------|----------------|---------|------------------|
| `nco.v` (74 lines) | `nco_hdd.v` (76 lines) | **95%** | Clock domain 200→400 MHz, frequency words scaled |
| `nco_multirate.v` (37 lines) | `nco_hdd_multirate.v` (62 lines) | **90%** | Rate selector 2-bit→3-bit, added 7 rate options |
| `nco_rpm_compensated.v` (99 lines) | `nco_hdd_zoned.v` (74 lines) | **80%** | Mac GCR zone concept → ESDI ZBR support |
| `flux_analyzer.v` (250 lines) | `hdd_rate_detector.v` (385 lines) | **70%** | Same histogram algorithm, thresholds scaled for 5-15 MHz |
| `index_handler.v` (181 lines) | Used directly | **100%** | Only timing constants differ (RPM range) |
| `mfm_decoder.v` | Used directly | **100%** | MFM encoding identical for FDD and HDD |
| `mfm_encoder.v` | Used directly | **100%** | MFM encoding identical for FDD and HDD |
| `crc16_ccitt.v` | Used directly | **100%** | CRC calculation identical |
| `edge_detector.v` | Used directly | **100%** | No changes needed |
| `phase_detector.v` | Used directly | **100%** | No changes needed |
| `loop_filter.v` | Used directly | **100%** | No changes needed |
| `data_sampler.v` | Used directly | **100%** | No changes needed |
| `step_controller.v` (260 lines) | `hdd_seek_controller.v` (400 lines) | **50%** | Added SEEK_COMPLETE, faster step timing (5-20µs vs 2-12ms) |

---

## Medium Leverage (Architectural Pattern Reuse)

These modules provided structural templates that were adapted for HDD.

| FDD Pattern | HDD Application | Description |
|-------------|-----------------|-------------|
| `digital_pll.v` structure | HDD DPLL | Same submodule composition: edge_detector → phase_detector → loop_filter → NCO → data_sampler |
| `data_rate_detector.v` wrapper | Rate detector wrapper | Same pattern: flux edge detection, analyzer instantiation, auto/manual mux |
| `encoding_mux.v` | HDD encoding mux | Same mux pattern extended for MFM/RLL/ESDI selection |
| `drive_profile_detector.v` | `hdd_discovery_fsm.v` | Same discovery pipeline concept: probe → detect → classify → configure |
| Register interface pattern | HDD registers | Same AXI-Lite register structure, status/control separation |

---

## Low Leverage (Concept Transfer Only)

These areas required fundamentally new implementations due to hardware differences.

| FDD Concept | HDD Reality | Why Low Leverage |
|-------------|-------------|------------------|
| 34-pin Shugart pinout | ST-506 34-pin | Similar but NOT identical. HDD has SEEK_COMPLETE, HEAD_SELECT[3:0], different active-low mapping |
| No data cable | 20-pin data cable | Completely different physical layer. HDD needs SE/differential support |
| 1-bit head select | 4-bit head select | 2 heads max → up to 16 heads |
| Motor control | N/A | HDD motors always on (spindle locked to power) |
| Single-ended only | SE + Differential | ESDI requires differential receivers (RS-422 style) |

---

## Code Reuse Statistics

### FDD Code Leveraged

```
Category                    Lines    Description
─────────────────────────────────────────────────────────────
Directly reusable           ~800     NCO, MFM codec, CRC, Index handler,
                                     edge/phase detectors, loop filter
Parameterized reuse         ~400     Rate detection, PLL structure
Pattern reuse               ~600     FSM templates, register patterns
─────────────────────────────────────────────────────────────
Total FDD leverage         ~1,800    (~40% of HDD RTL effort saved)
```

### HDD-Specific New Code

```
Category                    Lines    Description
─────────────────────────────────────────────────────────────
ST-506/ESDI interface       ~600     New physical layer adaptation
RLL codec                   ~700     RLL(2,7) encoder/decoder
Seek controller             ~400     Modified FSM with SEEK_COMPLETE
Discovery pipeline          ~800     HDD-specific probing/geometry
Phase 0 detection          ~2,165    SE/DIFF discrimination (new concept)
─────────────────────────────────────────────────────────────
Total HDD-specific         ~4,665
```

---

## Key Insight: Universal NCO Architecture

The NCO (Numerically Controlled Oscillator) is the most valuable reuse. The phase accumulator architecture is **identical** - only frequency words change.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    NCO ARCHITECTURE (UNIVERSAL)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   FDD @ 200 MHz                      HDD @ 400 MHz                  │
│   ─────────────                      ─────────────                  │
│   250K bps: 0x0051EB85               5.0 Mbps: 0x03333333           │
│   300K bps: 0x00624DD3               7.5 Mbps: 0x04CCCCCD           │
│   500K bps: 0x00A3D70A               10  Mbps: 0x06666666           │
│   1M   bps: 0x0147AE14               15  Mbps: 0x09999999           │
│                                                                     │
│                     ┌──────────────────────┐                        │
│                     │  phase_accum += FW   │                        │
│   freq_word ───────►│  overflow → bit_clk  │───────► bit_clock      │
│                     │  50% → sample_point  │───────► sample_strobe  │
│                     └──────────────────────┘                        │
│                              ▲                                      │
│                              │                                      │
│                     IDENTICAL LOGIC FOR                             │
│                     BOTH FDD AND HDD                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Formula:** `freq_word = (target_freq * 2^32) / clock_freq`

---

## Rate Detection Algorithm Scaling

The `flux_analyzer.v` histogram-based rate detection algorithm scaled directly to HDD rates.

### FDD Thresholds (200 MHz clock)

```verilog
// Pulse width thresholds for 250K-1M bps
localparam THRESH_1M_500K   = 16'd150;   // 1M: ~100 clks, 500K: ~200 clks
localparam THRESH_500K_300K = 16'd265;   // 500K: ~200 clks, 300K: ~333 clks
localparam THRESH_300K_250K = 16'd365;   // 300K: ~333 clks, 250K: ~400 clks
```

### HDD Thresholds (400 MHz clock)

```verilog
// Pulse width thresholds for 5-15 Mbps
localparam PW_5M_PEAK   = 16'd160;   // 5 Mbps: ~160 clocks
localparam PW_7_5M_PEAK = 16'd106;   // 7.5 Mbps: ~106 clocks
localparam PW_10M_PEAK  = 16'd80;    // 10 Mbps: ~80 clocks
localparam PW_15M_PEAK  = 16'd53;    // 15 Mbps: ~53 clocks
```

Both use:
- EMA (Exponential Moving Average) for smoothing
- Histogram binning for classification
- Peak detection for rate identification

---

## Detailed Module Mapping

```
FDD Module                          HDD Usage
════════════════════════════════════════════════════════════════════════

rtl/data_separator/
├── nco.v                       →   nco_hdd.v (cloned, freq words changed)
├── nco_multirate.v             →   nco_hdd_multirate.v (cloned, extended)
├── nco_rpm_compensated.v       →   nco_hdd_zoned.v (concept transfer)
├── digital_pll.v               →   Pattern reused for HDD DPLL
├── edge_detector.v             →   Used directly (100% reuse)
├── phase_detector.v            →   Used directly (100% reuse)
├── loop_filter.v               →   Used directly (100% reuse)
├── data_sampler.v              →   Used directly (100% reuse)
└── zone_calculator.v           →   Concept for ESDI zone rates

rtl/drive_ctrl/
├── index_handler.v             →   Used directly (timing constants only)
├── step_controller.v           →   hdd_seek_controller.v (FSM adapted)
└── motor_controller.v          →   Not needed (HDD motors always on)

rtl/encoding/
├── mfm_encoder.v               →   Used directly for HDD MFM (100%)
├── mfm_decoder.v               →   Used directly for HDD MFM (100%)
└── encoding_mux.v              →   Extended for RLL/ESDI selection

rtl/diagnostics/
├── flux_analyzer.v             →   hdd_rate_detector.v (algorithm scaled)
├── flux_capture.v              →   Extended for 400 MHz HDD capture
└── drive_profile_detector.v    →   hdd_discovery_fsm.v (pattern reused)

rtl/crc/
└── crc16_ccitt.v               →   Used directly (100% reuse)
```

---

## What's Genuinely New (No FDD Analog)

Phase 0 Interface Detection required completely new modules:

| New Module | Lines | Purpose | Why No FDD Analog |
|------------|-------|---------|-------------------|
| `interface_detector.v` | ~400 | Evidence-based scoring FSM | Floppy has no auto-detect need |
| `data_path_sniffer.v` | ~350 | SE/DIFF mode switching | Floppy is always single-ended |
| `correlation_calc.v` | ~280 | A/B wire correlation | Floppy has single data wire |
| `signal_quality_scorer.v` | ~300 | Edge quality analysis | Partial overlap with flux_analyzer |
| `index_freq_counter.v` | ~230 | Floppy vs HDD discrimination | New requirement for universal support |

**Total Phase 0:** ~2,165 lines of genuinely new code

---

## Physical Layer Differences

### Data Path Comparison

| Feature | Floppy | ST-506 MFM/RLL | ESDI |
|---------|--------|----------------|------|
| Data cable | None (34-pin only) | 20-pin, single-ended | 20-pin, differential pairs |
| INDEX frequency | 5-6 Hz (300-360 RPM) | 50-60 Hz (3000-3600 RPM) | 50-60 Hz |
| Data rate | 250K-1M bps | 5-7.5 Mbps | 10-15+ Mbps |
| A/B correlation | N/A | Low (one wire active) | High (complementary) |
| Termination | N/A | Optional | 100Ω required |

### Clock Domain Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                    DUAL-CLOCK DOMAIN DESIGN                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────────────────┐       ┌────────────────────────────┐   │
│  │  FLOPPY DOMAIN         │       │  HDD DOMAIN                │   │
│  │  200 MHz               │       │  400 MHz                   │   │
│  │                        │       │                            │   │
│  │  • Existing FDC core   │       │  • HDD NCO / DPLL          │   │
│  │  • Floppy DPLL / NCO   │       │  • RLL(2,7) decoder        │   │
│  │  • MFM/FM/GCR codecs   │       │  • ESDI decoder            │   │
│  │  • Step/motor control  │       │  • High-rate flux capture  │   │
│  │  • Index handler       │       │  • HDD seek controller     │   │
│  │                        │       │                            │   │
│  └───────────┬────────────┘       └─────────────┬──────────────┘   │
│              │                                  │                  │
│              │       ┌──────────────────┐       │                  │
│              └──────►│   Async FIFOs    │◄──────┘                  │
│                      │   (CDC Bridge)   │                          │
│                      └────────┬─────────┘                          │
│                               │                                    │
│                      ┌────────▼─────────┐                          │
│                      │  CPU/AXI Domain  │                          │
│                      │   (100 MHz)      │                          │
│                      └──────────────────┘                          │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Lessons Learned

1. **Algorithmic Reuse > Code Reuse**: The histogram-based rate detection algorithm transferred perfectly - only constants changed.

2. **NCO is Universal**: Phase accumulator architecture works for any frequency with appropriate frequency words.

3. **FSM Patterns Transfer Well**: State machine structures (seek, discovery) provided excellent templates even when signal details changed.

4. **Physical Layer is the Barrier**: Most new code addresses physical differences (differential signaling, higher rates, new cables).

5. **100% Reuse Modules are Gold**: MFM codec, CRC, basic DPLL components required zero changes.

---

## Summary Table

| Leverage Level | Modules | Lines Saved | Key Examples |
|----------------|---------|-------------|--------------|
| **100% Reuse** | 8 | ~500 | MFM codec, CRC, edge/phase detectors |
| **90-95% Reuse** | 2 | ~100 | NCO, NCO multirate |
| **70-80% Reuse** | 2 | ~250 | flux_analyzer → rate_detector, zone calc |
| **50% Reuse** | 1 | ~130 | step_controller → seek_controller |
| **Pattern Reuse** | 5 | ~600 | DPLL structure, register interface |
| **Concept Only** | 4 | ~200 | Physical layer adaptations |
| **Genuinely New** | 5 | 0 | Phase 0 detection (no FDD analog) |

**Bottom Line:** ~1,800 lines of FDD code directly contributed to HDD support, saving approximately 40% of the implementation effort.
