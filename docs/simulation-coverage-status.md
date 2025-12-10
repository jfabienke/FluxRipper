# FluxRipper Simulation Coverage Status

**Date:** 2025-12-07
**Overall Coverage:** 23.8% (53/223 modules)

---

## Executive Summary

The FluxRipper project currently has 223 unique RTL modules with 53 testbenches providing coverage. This represents a 23.8% coverage rate, up from the initial 16.96% baseline.

---

## Coverage by Subsystem

| Subsystem | Modules | Tested | Coverage | Status |
|-----------|---------|--------|----------|--------|
| Bus | 1 | 1 | **100%** | ✅ Complete |
| Clocking | 3 | 2 | **66.7%** | ✅ Good |
| Debug | 10 | 6 | **60%** | ✅ Good |
| CRC | 2 | 1 | **50%** | ⚠️ Partial |
| Top | 4 | 2 | **50%** | ⚠️ Partial |
| AXI | 8 | 3 | **37.5%** | ⚠️ Partial |
| USB | 32 | 12 | **37.5%** | ⚠️ Partial |
| HDD Controller | 3 | 1 | **33%** | ⚠️ Limited |
| DSP | 13 | 4 | **31%** | ⚠️ Limited |
| Data Separator | 20 | 4 | **20%** | ❌ Poor |
| Detection | 9 | 1 | **11%** | ❌ Poor |
| Drive Control | 10 | 1 | **10%** | ❌ Poor |
| Diagnostics | 28 | 2 | **7%** | ❌ Poor |
| Encoding | 41 | 1 | **2.4%** | ❌ Critical |
| AM Detector | 3 | 0 | **0%** | ❌ None |
| Disk | 1 | 0 | **0%** | ❌ None |
| Drive Interface | 10 | 0 | **0%** | ❌ None |
| FDC Core | 5 | 0 | **0%** | ❌ None |
| Host (ISA) | 9 | 0 | **0%** | ❌ None |
| Peripherals | 1 | 0 | **0%** | ❌ None |
| Recovery | 4 | 0 | **0%** | ❌ None |
| Write Path | 3 | 0 | **0%** | ❌ None |

---

## Test Infrastructure

### Testbench Locations
- `/sim/unit/` - Unit-level tests for specific modules
- `/sim/layer1-6/` - Layered integration tests
- `/sim/integration/` - Cross-subsystem tests
- `/tb/` - High-level system and macro tests

### Test Count by Location
- `/tb/` directory: 19 testbenches
- `/sim/` directory: 34 testbenches

---

## Critical Gaps (Priority Order)

### Priority 1: Critical Infrastructure (0% coverage)
| Subsystem | Modules | Impact |
|-----------|---------|--------|
| Host/ISA | 9 | PC compatibility, Option ROM boot |
| Drive Interface | 10 | ST506/ESDI physical drive control |
| FDC Core | 5 | Legacy floppy disk support |
| Recovery | 4 | Data recovery, multipass capture |

### Priority 2: Core Functionality (< 15% coverage)
| Subsystem | Modules | Impact |
|-----------|---------|--------|
| Encoding | 41 | FM/MFM/GCR/RLL codec variants |
| Diagnostics | 28 | Drive health, fingerprinting |
| Detection | 9 | Auto-detection of formats |
| Drive Control | 10 | Motor/stepper control |

### Priority 3: Supporting Systems (< 35% coverage)
| Subsystem | Modules | Impact |
|-----------|---------|--------|
| Data Separator | 20 | PLL, clock recovery |
| DSP | 13 | Signal processing chain |

---

## Modules Without Test Coverage (170 total)

### Host/ISA (9 modules - all untested)
- `isa_addr_decode`
- `isa_addr_decode_default`
- `isa_bus_bridge`
- `isa_option_rom`
- `isa_pnp_controller`
- `isa_pnp_rom`
- `isa_pnp_rom_extended`
- `option_rom_async`
- `option_rom_bram`

### Drive Interface (10 modules - all untested)
- `esdi_cmd`
- `esdi_config_parser`
- `esdi_phy`
- `esdi_termination_ctrl`
- `hdd_data_mux`
- `hdd_drive_mux`
- `hdd_seek_controller`
- `st506_head_selector`
- `st506_interface`
- `st506_step_generator`

### FDC Core (5 modules - all untested)
- `command_fsm`
- `fdc_core_instance`
- `fdc_fifo`
- `fdc_registers`
- `fdc_status`

### Recovery (4 modules - all untested)
- `flux_histogram`
- `flux_histogram_dual`
- `multipass_capture`
- `multipass_capture_regs`

### Encoding (40 modules - mostly untested)
- FM: `fm_decoder`, `fm_encoder`
- MFM: `mfm_decoder`, `mfm_decoder_lut`, `mfm_decoder_serial`, `mfm_decoder_sync`, `mfm_decoder_sync_parallel`, `mfm_encoder`, `mfm_encoder_lut`, `mfm_encoder_serial`, `mfm_encoder_sync`
- GCR: `gcr_apple5_decoder`, `gcr_apple5_encoder`, `gcr_apple6_decoder`, `gcr_apple6_encoder`, `gcr_cbm_decoder`, `gcr_cbm_encoder`
- M2FM: `m2fm_decoder`, `m2fm_encoder`
- RLL: `rll_2_7_am_detector`, `rll_2_7_decoder`, `rll_2_7_encoder`, `rll_2_7_sync_generator`
- ESDI: `esdi_decoder`, `esdi_encoder`, `esdi_sector_buffer`
- Detection: `encoding_auto_select`, `encoding_detector`, `encoding_mux`
- Sync: `agat_sync_detector`, `apple_sync_detector`, `tandy_sync_detector`

### Diagnostics (26 modules - mostly untested)
- `capture_timing`, `data_rate_detector`, `density_capability_analyzer`
- `density_probe_ctrl`, `drive_profile_detector`, `error_counters`
- `fifo_statistics`, `flux_analyzer`, `flux_capture`
- `hdd_decode_tester`, `hdd_discovery_registers`, `hdd_fingerprint`
- `hdd_geometry_profile`, `hdd_geometry_scanner`, `hdd_health_monitor`
- `hdd_metadata_store`, `hdd_phy_mode_ctrl`, `hdd_phy_probe`
- `hdd_rate_detector`, `hdd_rate_to_nco`, `instrumentation_regs`
- `metadata_guid_generator`, `pll_diagnostics`, `seek_histogram`
- `signal_quality_monitor`, `track_error_stats`, `track_width_analyzer`

### Data Separator (16 modules - mostly untested)
- `data_sampler`, `data_sampler_mfm`, `digital_pll_simple`
- `edge_detector`, `edge_detector_filtered`, `lock_detector`
- `loop_filter`, `loop_filter_adaptive`, `loop_filter_auto`
- `nco_hdd`, `nco_hdd_multirate`, `nco_hdd_zoned`
- `nco_multirate`, `nco_rpm_compensated`
- `phase_detector_bangbang`, `phase_detector_robust`, `zone_calculator`

### USB (17 modules - partially untested)
- `usb_controller`, `usb_device_core`
- `usb_top_v2_with_logger`, `usb_traffic_logger`, `usb_passthrough_analyzer`
- `msc_protocol`, `msc_scsi_engine`, `msc_sector_buffer`, `msc_config_regs`
- `native_protocol`, `raw_interface`, `hfe_protocol`
- `async_fifo`, `crc16_usb`, `drive_lun_mapper`

### Other Untested
- **AM Detector (3):** `am_detector`, `am_detector_with_shifter`, `sync_fsm`
- **Write Path (3):** `write_precompensation`, `write_driver`, `erase_controller`
- **Drive Control (9):** `index_handler`, `index_handler_dual`, `motor_controller`, etc.
- **Detection (8):** `correlation_calc`, `data_path_sniffer`, `index_freq_counter`, etc.

---

## Well-Tested Areas

### Fully Tested (100%)
- **Bus:** `system_bus`

### Well Covered (> 50%)
- **Debug:** JTAG TAP, DTM, debug module, signal tap, trace buffer
- **Clocking:** Clock wizard, reset manager
- **Top:** Main integration modules

### Adequately Covered (35-50%)
- **USB:** Device core v2, HS negotiator, control/bulk/CDC endpoints, descriptor ROM, protocol handlers (GW, KF)
- **AXI:** Stream flux capture, FDC peripheral
- **CRC:** CRC16 CCITT

---

## Target: 90%+ Coverage

### Estimated New Tests Required
- ~50 new testbenches
- ~23,600 lines of test code

### Implementation Plan
See `/Users/jvindahl/.claude/plans/humming-growing-oasis.md` for detailed test implementation plan.

---

## Recent Fixes (2025-12-07)

Fixed 19 RTL files with compilation errors:
- USB: `drive_lun_mapper.v`, `msc_scsi_engine.v`, `usb_device_core.v`, `usb_top.v`
- Diagnostics: 8 files (variable declarations, reserved keywords)
- DSP: `prml_decoder.v` (output port types)
- Host: `isa_option_rom.v` (integer scope)
- Recovery: `multipass_capture.v` (array port interface)

All modules now compile cleanly with Icarus Verilog (`iverilog -g2005`).
