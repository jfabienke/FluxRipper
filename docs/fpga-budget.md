# FluxRipper FPGA Resource Budget

**Target Device:** AMD Spartan UltraScale+ XCSU35P
**Package:** BGA-625 (SBVB625)
**Recommended Variant:** XCSU35P-1LI (Low Power, 0.72V)
**Alternative Variant:** XCSU35P-2E (Standard, 0.85V)
**Created:** 2025-12-04 16:48
**Updated:** 2025-12-07 12:19

---

## Device Specifications

| Resource | Available | Notes |
|----------|-----------|-------|
| Logic Cells | 36,000 | 36K LUTs |
| Flip-Flops | 36,000 | 36K FFs |
| Block RAM | 106 × 18Kb | 1.93 Mb total (53 × 36Kb configurable) |
| DSP Slices | 48 | DSP48E2 |
| User I/O | 304 | After power/config pins |
| Clock Resources | 2 MMCM, 4 PLL | 2 CMTs (1 MMCM + 2 PLLs each) |

---

## Speed Grade Selection

### Recommended: -1LI Low Power Variant (0.72V)

The FluxRipper design is **fully compatible** with the Low Power XCSU35P-1LI at V<sub>CCINT</sub> = 0.72V.
All timing requirements have significant margin against -1LI limits.

| Subsystem | Design Requirement | -1LI Limit (0.72V) | Margin |
|-----------|-------------------|-------------------|--------|
| HDD Core Clock | 300 MHz | 667 MHz (BUFG) | ~55% |
| DSP (Signal Monitor) | 300 MHz | 600 MHz | ~50% |
| System Clock | 200 MHz | 667 MHz | ~70% |
| USB ULPI Clock | 60 MHz | 667 MHz | ~91% |
| HyperRAM | 166 MHz DDR | >400 MHz | >58% |

### Speed Grade Comparison

| Parameter | -1LI (Low Power) | -2E (Standard) |
|-----------|------------------|----------------|
| V<sub>CCINT</sub> | 0.72V | 0.85V |
| Max GTH Rate | 10.3125 Gb/s | 16.375 Gb/s |
| GTH Transceivers | 0 | 0 |
| Power | Lower | Higher |
| Thermal | Reduced | Standard |
| Part Number | xcsu35p-sbvb625-1LI-i | xcsu35p-2sbvb625e |

### Implementation Notes for -1LI

1. **Power Regulator:** Board PMIC must provide 0.72V on V<sub>CCINT</sub> rail
2. **Vivado Settings:** Select part `xcsu35p-sbvb625-1LI-i` and configure voltage properties
3. **Host Interface:** USB 2.0 HS as primary host interface
4. **I/O Banks:** HD I/O banks still support 3.3V LVCMOS for level shifter interface
5. **Eval Kit Note:** SCU35 kit runs at 0.85V; custom board needed for 0.72V operation

### Bandwidth Validation

| Parameter | Value | Notes |
|-----------|-------|-------|
| Flux stream (per drive) | ~2 MB/s | 500 kHz × 32-bit timestamps |
| Dual drive capture | ~4 MB/s | Both interfaces simultaneous |
| USB 2.0 HS throughput | ~40 MB/s | Practical (480 Mbps theoretical) |
| **Bandwidth margin** | **10×** | USB easily handles dual capture |
| HyperRAM buffer | 8 MB | ~2 seconds at full capture rate |

USB 2.0 HS provides sufficient bandwidth with 10× margin over dual-drive flux capture requirements.

---

## Resource Utilization Summary

### Current Design (Full System with USB 2.0 HS)

| Resource | Used | Available | Utilization | Headroom |
|----------|------|-----------|-------------|----------|
| **LUTs** | ~16,480 | 36,000 | **45.8%** | 19,520 (54%) |
| **FFs** | ~9,090 | 36,000 | **25.3%** | 26,910 (75%) |
| **BRAM (18Kb)** | ~69 | 106 | **65.1%** | 37 (35%) |
| **DSP** | 6 | 48 | **12.5%** | 42 (87.5%) |

---

## Module Breakdown

### Floppy Disk Controller (Dual FDC)

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| DPLL Core (×2) | 626 | 384 | 0 | 0 | Phase-locked loop for data recovery |
| AM Detector + Shifter (×2) | 360 | 192 | 0 | 0 | Address mark detection |
| CRC-CCITT (×2) | 170 | 64 | 1 | 0 | CRC calculation |
| 16-byte FIFO (×2) | 240 | 288 | 0 | 0 | Data buffering |
| MFM Encode/Decode (×2) | 160 | 0 | 18 | 0 | MFM codec tables |
| FM/GCR Tables (×2) | 400 | 0 | 17 | 0 | Additional encoding support |
| Command FSM (×2) | 1,020 | 560 | 0 | 0 | Command processing |
| Register Interface (×2) | 300 | 192 | 0 | 0 | AXI-Lite registers |
| Step Controller (×2) | 440 | 208 | 0 | 0 | Stepper motor control |
| Motor Controller (×2) | 360 | 240 | 0 | 0 | Spindle motor control |
| Write Precompensation (×2) | 340 | 96 | 0 | 0 | Write timing adjustment |
| Index Handler (×2) | 240 | 160 | 0 | 0 | Index pulse processing |
| Flux Capture (×2) | 400 | 96 | 17 | 0 | Raw flux capture buffer |
| Signal Quality Monitor (×2) | 300 | 160 | 0 | 2 | PLL lock detection |
| AXI-Stream Flux (×2) | 500 | 400 | 2 | 0 | DMA interface |
| AXI4-Lite FDC (×2) | 550 | 420 | 0 | 0 | Register interface |
| **Subtotal (Dual FDC)** | **~6,630** | **~3,780** | **~56** | **2** | |

### SoC Infrastructure

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| MicroBlaze V | 3,500 | 2,000 | 16 | 3 | Soft processor |
| AXI Interconnect | 800 | 400 | 0 | 0 | Bus fabric |
| AXI DMA Controller (2ch) | 900 | 450 | 4 | 0 | High-speed DMA |
| HyperRAM Controller | 400 | 200 | 0 | 0 | External memory interface |
| **Subtotal (SoC)** | **~5,600** | **~3,050** | **~20** | **3** | |

### HDD Support (ST-506/ESDI)

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| Clock Wizard HDD (300 MHz) | 50 | 30 | 0 | 0 | MMCME4_BASE |
| NCO HDD | 150 | 80 | 0 | 0 | 5-15 MHz rates |
| RLL(2,7) Codec | 380 | 140 | 4 | 0 | Encode/decode tables |
| ESDI Codec | 500 | 210 | 4 | 0 | Higher rate encoding |
| ST-506 Interface (×2) | 360 | 200 | 0 | 0 | Dual drive control |
| HDD Seek Controller (×2) | 400 | 240 | 0 | 0 | SEEK_COMPLETE FSM |
| ESDI PHY (×2) | 500 | 200 | 0 | 0 | Differential interface |
| HDD Discovery Pipeline | 470 | 230 | 1 | 0 | PHY probe + rate + geometry |
| HDD Health Monitor | 150 | 80 | 0 | 0 | Mechanical diagnostics |
| **Subtotal (HDD)** | **~2,960** | **~1,410** | **~9** | **0** | |

### Interface Detection (Phase 0)

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| Interface Detector FSM | 280 | 150 | 0 | 0 | Master detection FSM |
| Data Path Sniffer | 250 | 120 | 0 | 0 | SE/Diff signal capture |
| Correlation Calculator | 160 | 80 | 0 | 0 | A/B wire correlation |
| Signal Quality Scorer | 200 | 100 | 0 | 0 | Edge quality analysis |
| Index Frequency Counter | 120 | 60 | 0 | 0 | Floppy vs HDD discrimination |
| **Subtotal (Detection)** | **~1,010** | **~510** | **0** | **0** | |

### FluxStat Statistical Recovery

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| Flux Histogram | 200 | 120 | 2 | 0 | 256-bin real-time histogram |
| Multipass Capture | 280 | 180 | 1 | 0 | Up to 64 passes with metadata |
| **Subtotal (FluxStat)** | **~480** | **~300** | **~3** | **0** | |

### JTAG Debug Subsystem (Simulation Validated)

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| TAP Controller | 180 | 120 | 0 | 0 | IEEE 1149.1 16-state FSM |
| Debug Transport Module | 220 | 160 | 0 | 0 | DTMCS + 41-bit DMI |
| Debug Module | 350 | 240 | 0 | 0 | RISC-V DM 0.13 system bus |
| System Bus Fabric | 280 | 180 | 0 | 0 | 6-slave address decoder |
| Clock/Reset Manager | 150 | 100 | 0 | 0 | MMCM + reset sync |
| Disk Controller | 320 | 200 | 1 | 0 | Flux capture + DMA |
| USB Controller | 180 | 120 | 0 | 0 | Status/control stub |
| Signal Tap | 400 | 280 | 2 | 0 | 256-entry capture buffer |
| **Subtotal (Debug)** | **~2,080** | **~1,400** | **~3** | **0** | All layers validated |

### USB 2.0 High-Speed Stack (ULPI PHY)

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| ulpi_wrapper_v2 | 250 | 150 | 0 | 0 | UTMI+ to ULPI translation |
| usb_hs_negotiator | 180 | 120 | 0 | 0 | HS chirp FSM (MIT) |
| usb_device_core_v2 | 500 | 300 | 1 | 0 | Packet engine, CRC16/CRC5 |
| usb_control_ep | 400 | 250 | 0 | 0 | EP0: Standard + Vendor + CDC |
| usb_cdc_ep | 350 | 400 | 0 | 0 | TX FIFO (256B), RX FIFO (64B) |
| usb_bulk_ep (×2) | 400 | 200 | 2 | 0 | EP1 cmd/rsp, EP2 flux stream |
| usb_descriptor_rom | 600 | 100 | 2 | 0 | 5 personalities × ~256 bytes |
| usb3320_features | 200 | 150 | 0 | 0 | VBUS, OTG, charger detection |
| **Subtotal (USB 2.0 HS)** | **~2,880** | **~1,670** | **~5** | **0** | 480 Mbps, MIT licensed |

**USB 2.0 HS Features:**
- 480 Mbps High-Speed via USB3320 ULPI PHY
- IAD composite device (Vendor + CDC ACM)
- 5 USB personalities (Greaseweazle, HxC, KryoFlux, Native, MSC)
- KryoFlux-compatible control transfers (bmRequestType=0xC3)
- CDC ACM virtual COM port for debug console
- All code BSD-3-Clause or MIT licensed

### Host Interface Controllers

| Block | LUTs | FFs | BRAM | DSP | Notes |
|-------|------|-----|------|-----|-------|
| ISA Bus Controller | 800 | 400 | 2 | 0 | 8-bit I/O space, DMA support |
| SPI Slave Controller | 150 | 80 | 0 | 0 | Up to 50 MHz |
| I2C Master/Slave | 200 | 100 | 0 | 0 | 100/400 kHz |
| UART Controller | 100 | 60 | 0 | 0 | 115200-921600 baud |
| HyperRAM Controller | 400 | 200 | 0 | 0 | 166 MHz DDR |
| **Subtotal (All Host)** | **~1,650** | **~840** | **~2** | **0** | Excludes USB (in main) |

---

## Pin Budget

### Connector Pins vs FPGA Pins

**Important:** Physical connector pins do NOT map 1:1 to FPGA I/O pins. Many connector pins are:

| Pin Type | FPGA Connection | Handling |
|----------|-----------------|----------|
| **Ground (GND)** | None | Connect to board ground plane |
| **Power (+5V, +12V, -5V, -12V)** | None | Connect to power rails |
| **No Connection (NC)** | None | Leave floating or tie to ground |
| **Unused active-low** | None | Tie high via 10kΩ pull-up |
| **Static control** | None (or 1) | Tie high/low via resistor, or jumper-selectable |
| **Signal pins** | 1 per signal | Directly connected to FPGA I/O |

### Connector vs FPGA Pin Breakdown

| Interface | Connector | Physical Pins | GND/PWR/NC | FPGA Pins |
|-----------|-----------|---------------|------------|-----------|
| Floppy A (34-pin Shugart) | J3 | 34 | 17 GND (odd) | **17** |
| Floppy B (50-pin Apple/Mac) | J5 | 50 | 25 GND (odd) | **19** |
| HDD Control (34-pin ST-506) | J10 | 34 | 17 GND (odd) | **14** |
| HDD Data 0 (20-pin ST-506) | J11 | 20 | 10 GND | **6** |
| HDD Data 1 (20-pin ST-506) | J13 | 20 | 10 GND | **6** |
| ISA 8-bit (62-pin edge) | Edge | 62 | 16 GND/PWR | **24** |
| ISA 16-bit ext (36-pin) | Edge | 36 | 8 GND/PWR | **18** |
| USB 2.0 HS (ULPI) | USB3320 | 13 | 0 | **13** |
| SPI | Header | 6 | 0 | **6** |
| I2C | Header | 2 | 0 | **2** |
| UART | Header | 2 | 0 | **2** |
| HyperRAM | Chip | 24 | 12 | **12** |

### FPGA Pin Allocation Summary

| Category | FPGA Pins | Status | Notes |
|----------|-----------|--------|-------|
| **Storage Interfaces** | | | |
| Floppy Interface A (34-pin) | 17 | Assigned | Shugart (J3) |
| Floppy Interface B (50-pin) | 19 | Assigned | Apple/Mac (J5) |
| HDD Control (34-pin) | 14 | Assigned | ST-506 control (J10) |
| HDD Data 0 (20-pin) | 6 | Assigned | ST-506 data drive 0 (J11) |
| HDD Data 1 (20-pin) | 6 | Assigned | ST-506 data drive 1 (J13) |
| **Host Interfaces** | | | |
| USB 2.0 HS (ULPI) | 13 | Assigned | USB3320 PHY |
| ISA Bus (8-bit) | 24 | Assigned | 62-pin edge |
| ISA Bus (16-bit ext) | 18 | Assigned | 36-pin edge |
| SPI | 6 | Planned | Config & debug |
| I2C | 2 | Planned | Sensors & EEPROM |
| UART | 2 | Planned | Debug console |
| ~~PCIe x1~~ | 0 | Removed | XCSU35P has no GTH |
| **Memory** | | | |
| HyperRAM | 12 | Assigned | 8MB track buffer |
| **Misc** | | | |
| System (CLK, Reset) | 2 | Assigned | |
| Status LEDs | 5 | Assigned | |
| **Totals** | | | |
| Core (2×FDD + HDD + USB) | 75 | Required | Storage + USB 2.0 HS |
| + ISA 16-bit | +42 | Assigned | 8-bit + 16-bit extension |
| + Peripherals (SPI/I2C/UART) | +10 | Planned | Debug & config |
| + System/LEDs | +7 | Assigned | Clock, reset, status |
| **Current Config** | **134** | ~45% | FDD + HDD + USB + ISA |
| + HyperRAM | +12 | Required | 8MB track buffer |
| **Full Config** | **146** | ~48% | All interfaces |
| **Available I/O** | 304 | | BGA-625 package |

### Detailed Pin Assignments

#### System Signals (2 pins)

| Pin | Signal | Direction | Standard |
|-----|--------|-----------|----------|
| R4 | `clk_200mhz` | Input | LVCMOS33 |
| T4 | `reset_n` | Input | LVCMOS33 |

#### Floppy Interface A - J3 Header (20 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| A12 | `if_a_step` | Output | Step pulse |
| B12 | `if_a_dir` | Output | Step direction |
| A13 | `if_a_motor_0` | Output | Drive 0 motor |
| B13 | `if_a_motor_1` | Output | Drive 1 motor |
| C12 | `if_a_head_sel` | Output | Head select |
| D12 | `if_a_write_gate` | Output | Write enable |
| C13 | `if_a_write_data` | Output | Write data stream |
| D13 | `if_a_drive_sel` | Output | Drive select |
| A14 | `if_a_read_data` | Input | Read data (critical timing) |
| B14 | `if_a_index` | Input | Index pulse |
| C14 | `if_a_track0` | Input | Track 0 sensor |
| D14 | `if_a_wp` | Input | Write protect |
| A15 | `if_a_ready` | Input | Drive ready |
| B15 | `if_a_dskchg` | Input | Disk change |
| C15 | `if_a_head_load` | Output | Head load |
| D15 | `if_a_tg43` | Output | Track > 43 |
| A16 | `if_a_density` | Output | Density select |
| B16 | `if_a_sector` | Input | Sector pulse |

#### Floppy Interface B - J4 Header (20 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| E12 | `if_b_step` | Output | Step pulse |
| F12 | `if_b_dir` | Output | Step direction |
| E13 | `if_b_motor_0` | Output | Drive 0 motor |
| F13 | `if_b_motor_1` | Output | Drive 1 motor |
| G12 | `if_b_head_sel` | Output | Head select |
| H12 | `if_b_write_gate` | Output | Write enable |
| G13 | `if_b_write_data` | Output | Write data stream |
| H13 | `if_b_drive_sel` | Output | Drive select |
| E14 | `if_b_read_data` | Input | Read data (critical timing) |
| F14 | `if_b_index` | Input | Index pulse |
| G14 | `if_b_track0` | Input | Track 0 sensor |
| H14 | `if_b_wp` | Input | Write protect |
| E15 | `if_b_ready` | Input | Drive ready |
| F15 | `if_b_dskchg` | Input | Disk change |
| G15 | `if_b_head_load` | Output | Head load |
| H15 | `if_b_tg43` | Output | Track > 43 |
| E16 | `if_b_density` | Output | Density select |
| F16 | `if_b_sector` | Input | Sector pulse |

#### Floppy Interface B (Alternate) - J5 Header (50-pin Apple/Mac)

The 50-pin interface shares FPGA pins with the 34-pin J4 connector via mux/buffer logic.
Only one can be active at a time. The 50-pin adds Apple/Mac specific signals.

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| 1, 3, 5... | GND | - | 25 ground pins (odd positions) |
| 2 | `if_b_phase0` | Output | Stepper phase 0 |
| 4 | `if_b_phase1` | Output | Stepper phase 1 |
| 6 | `if_b_phase2` | Output | Stepper phase 2 |
| 8 | `if_b_phase3` | Output | Stepper phase 3 |
| 10 | `if_b_write_req` | Output | Write request |
| 12 | `if_b_sel_ca0` | Output | CA0 select |
| 14 | `if_b_sel_ca1` | Output | CA1 select |
| 16 | `if_b_sel_ca2` | Output | CA2 select |
| 18 | `if_b_sel_lstrb` | Output | Latch strobe |
| 20 | `if_b_motor_on` | Output | Motor on |
| 22 | NC | - | Not connected |
| 24 | NC | - | Not connected |
| 26 | `if_b_read_data` | Input | Read data (shared with J4) |
| 28 | `if_b_wr_protect` | Input | Write protect (shared) |
| 30 | `if_b_sense` | Input | Sense line |
| 32 | NC | - | Not connected |
| 34 | `if_b_ready` | Input | Drive ready (shared) |
| 36 | NC | - | Not connected |
| 38 | NC | - | Not connected |
| 40 | `if_b_write_data` | Output | Write data (shared) |
| 42 | NC | - | Not connected |
| 44 | NC | - | Not connected |
| 46 | NC | - | Not connected |
| 48 | NC | - | Not connected |
| 50 | +12V | - | Power (optional) |

**Note:** Signals marked "shared" use the same FPGA pins as the 34-pin interface.
Additional Apple-specific signals (phase0-3, CA0-2, etc.) require ~5 extra FPGA pins
when the 50-pin mode is selected via a mux controlled by one additional GPIO.

#### HDD Interface 0 - J10/J11 Headers (18 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `hdd0_head_sel_n[3:0]` | Output | 4-bit head select (active-low) |
| TBD | `hdd0_step_n` | Output | Step pulse (active-low) |
| TBD | `hdd0_dir_n` | Output | Direction (active-low) |
| TBD | `hdd0_write_gate_n` | Output | Write gate (active-low) |
| TBD | `hdd0_drive_sel_n[1:0]` | Output | Drive select (active-low) |
| TBD | `hdd0_seek_complete_n` | Input | Seek complete (active-low) |
| TBD | `hdd0_track00_n` | Input | Track 0 (active-low) |
| TBD | `hdd0_write_fault_n` | Input | Write fault (active-low) |
| TBD | `hdd0_index_n` | Input | Index pulse (active-low) |
| TBD | `hdd0_ready_n` | Input | Drive ready (active-low) |
| TBD | `hdd0_read_data` | Input | Read data (SE) |
| TBD | `hdd0_read_data_p` | Input | Read data+ (Diff) |
| TBD | `hdd0_read_data_n` | Input | Read data- (Diff) |
| TBD | `hdd0_write_data` | Output | Write data |

#### HDD Interface 1 - J12/J13 Headers (17 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `hdd1_head_sel_n[3:0]` | Output | 4-bit head select |
| TBD | `hdd1_step_n` | Output | Step pulse |
| TBD | `hdd1_dir_n` | Output | Direction |
| TBD | `hdd1_write_gate_n` | Output | Write gate |
| TBD | `hdd1_drive_sel_n[1:0]` | Output | Drive select |
| TBD | `hdd1_seek_complete_n` | Input | Seek complete |
| TBD | `hdd1_track00_n` | Input | Track 0 |
| TBD | `hdd1_write_fault_n` | Input | Write fault |
| TBD | `hdd1_index_n` | Input | Index pulse |
| TBD | `hdd1_ready_n` | Input | Drive ready |
| TBD | `hdd1_read_data` | Input | Read data (SE) |
| TBD | `hdd1_read_data_p` | Input | Read data+ (Diff) |
| TBD | `hdd1_read_data_n` | Input | Read data- (Diff) |
| TBD | `hdd1_write_data` | Output | Write data |

#### Status LEDs (5 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| J15 | `led_activity_a` | Output | 8mA drive |
| K15 | `led_activity_b` | Output | 8mA drive |
| L15 | `led_error` | Output | 8mA drive |
| M15 | `led_pll_lock_a` | Output | 8mA drive |
| N15 | `led_pll_lock_b` | Output | 8mA drive |

#### Host Interfaces

##### ISA Bus Interface - 8-bit (24 pins) - PC/XT Compatible

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `isa_d[7:0]` | Bidir | 8-bit data bus |
| TBD | `isa_a[9:0]` | Input | Address bus (I/O decode) |
| TBD | `isa_ior_n` | Input | I/O Read strobe |
| TBD | `isa_iow_n` | Input | I/O Write strobe |
| TBD | `isa_aen` | Input | DMA address enable |
| TBD | `isa_irq` | Output | Interrupt request (IRQ6) |
| TBD | `isa_drq` | Output | DMA request (DRQ2) |
| TBD | `isa_dack_n` | Input | DMA acknowledge |

##### ISA Bus Interface - 16-bit Extension (18 pins) - AT Compatible

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `isa_d[15:8]` | Bidir | Upper 8-bit data bus |
| TBD | `isa_a[23:10]` | Input | Extended address bus (memory decode) |
| TBD | `isa_la[23:17]` | Input | Latched address (optional) |
| TBD | `isa_memr_n` | Input | Memory Read strobe |
| TBD | `isa_memw_n` | Input | Memory Write strobe |
| TBD | `isa_sbhe_n` | Input | System Bus High Enable |
| TBD | `isa_iocs16_n` | Output | 16-bit I/O cycle |
| TBD | `isa_memcs16_n` | Output | 16-bit memory cycle |
| TBD | `isa_irq[15:9]` | Output | Extended IRQs (optional) |
| TBD | `isa_drq[7:5]` | Output | Extended DMA (optional) |
| TBD | `isa_dack_n[7:5]` | Input | Extended DMA ack |
| TBD | `isa_master_n` | Output | Bus master request |
| TBD | `isa_iochrdy` | Output | I/O channel ready (wait states) |
| TBD | `isa_0ws_n` | Output | Zero wait state |

##### SPI Interface - Configuration & Debug (6 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `spi_sck` | Input | SPI clock (up to 50 MHz) |
| TBD | `spi_mosi` | Input | Master Out Slave In |
| TBD | `spi_miso` | Output | Master In Slave Out |
| TBD | `spi_cs_n` | Input | Chip select |
| TBD | `spi_flash_cs_n` | Output | Configuration flash CS |
| TBD | `spi_flash_hold_n` | Output | Configuration flash hold |

##### I2C Interface - Sensors & EEPROM (2 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `i2c_scl` | Bidir | I2C clock (100/400 kHz) |
| TBD | `i2c_sda` | Bidir | I2C data |

##### UART Interface - Debug Console (2 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `uart_tx` | Output | Serial transmit |
| TBD | `uart_rx` | Input | Serial receive |

##### USB 2.0 High-Speed Interface - ULPI (13 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `ulpi_clk` | Input | 60 MHz clock from USB3320 |
| TBD | `ulpi_data[0]` | Bidir | ULPI data bit 0 |
| TBD | `ulpi_data[1]` | Bidir | ULPI data bit 1 |
| TBD | `ulpi_data[2]` | Bidir | ULPI data bit 2 |
| TBD | `ulpi_data[3]` | Bidir | ULPI data bit 3 |
| TBD | `ulpi_data[4]` | Bidir | ULPI data bit 4 |
| TBD | `ulpi_data[5]` | Bidir | ULPI data bit 5 |
| TBD | `ulpi_data[6]` | Bidir | ULPI data bit 6 |
| TBD | `ulpi_data[7]` | Bidir | ULPI data bit 7 |
| TBD | `ulpi_dir` | Input | Direction (1=PHY driving) |
| TBD | `ulpi_nxt` | Input | Next (PHY ready) |
| TBD | `ulpi_stp` | Output | Stop (terminate transfer) |
| TBD | `ulpi_rst_n` | Output | PHY reset (active low) |

**ULPI Timing Requirements:**
- Clock: 60 MHz (16.667 ns period)
- I/O Standard: LVCMOS33
- Input delay: 5.0 ns max, 0.5 ns min
- Output delay: 5.0 ns max, 0.5 ns min
- Bus skew: 1.0 ns max across data[7:0]
- Drive strength: 8 mA (FAST slew for data/STP, SLOW for RST)

##### HyperRAM Interface (12 pins)

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| TBD | `hram_dq[7:0]` | Bidir | 8-bit data bus |
| TBD | `hram_rwds` | Bidir | Read/Write data strobe |
| TBD | `hram_ck` | Output | Clock |
| TBD | `hram_ck_n` | Output | Clock complement |
| TBD | `hram_cs_n` | Output | Chip select |

---

## Timing Constraints

### Clock Domains

| Clock | Frequency | Period | Source |
|-------|-----------|--------|--------|
| `clk_200mhz` | 200 MHz | 5.0 ns | External oscillator |
| `clk_fdd` | 200 MHz | 5.0 ns | MMCM output |
| `clk_hdd` | 300 MHz | 3.33 ns | MMCM output |
| `clk_cpu` | 100 MHz | 10.0 ns | MMCM output |
| `ulpi_clk` | 60 MHz | 16.67 ns | USB3320 PHY (async) |

**Note:** `ulpi_clk` is asynchronous to all other clock domains. CDC synchronizers are used for all signals crossing between USB and system clock domains.

### Critical Path Constraints

| Signal Group | Max Delay | Min Delay | Notes |
|--------------|-----------|-----------|-------|
| Read data (flux) | 2.0 ns | 0.5 ns | Most critical |
| Step pulse output | 3.0 ns | 0.5 ns | |
| Index pulse input | 5.0 ns | 0.5 ns | |
| Write data output | 2.0 ns | 0.5 ns | |

### Relaxed Path Constraints

| Signal Group | Max Delay | Notes |
|--------------|-----------|-------|
| Motor control | 10.0 ns | Slow-changing |
| Status signals | 10.0 ns | track0, wp, ready, dskchg |
| LED outputs | N/A | False path |

---

## Growth Projections

### Configuration Scenarios

| Configuration | LUTs | FFs | BRAM | Utilization |
|--------------|------|-----|------|-------------|
| Base (Dual FDC + SoC) | 10,350 | 5,800 | 54 | 28.7% |
| + HDD Support | 13,310 | 7,210 | 63 | 37.0% |
| + Phase 0 Detection | 14,320 | 7,720 | 63 | 39.8% |
| + FluxStat | 14,800 | 8,020 | 66 | 41.1% |
| + USB 2.0 HS Stack | 16,480 | 9,090 | 69 | 45.8% |
| **Current Full System** | **16,480** | **9,090** | **69** | **45.8%** |

### Host Interface Configurations

| Configuration | LUTs | FFs | BRAM | Total Util |
|--------------|------|-----|------|------------|
| Current (incl. USB 2.0 HS) | 16,480 | 9,090 | 69 | 45.8% |
| + SPI/I2C/UART | +450 | +240 | 0 | 47.0% |
| + ISA Bus | +800 | +400 | +2 | 48.1% |
| **Full Host Suite** | **+1,650** | **+840** | **+2** | **~51%** |

**Note:** USB 2.0 HS is included in base configuration.

### Future Expansion Headroom

| Feature | Est. LUTs | Est. FFs | Est. BRAM | New Total |
|---------|-----------|----------|-----------|-----------|
| ML Pattern Recognition | +2,000 | +1,000 | +8 | ~51% |
| Advanced Diagnostics | +1,500 | +800 | +4 | ~55% |
| Additional Storage | +2,000 | +1,000 | +6 | ~61% |
| **Maximum Projected** | **~24,830** | **~13,530** | **~97** | **~69%** |

### Typical Deployment Configurations

| Deployment | Modules Included | LUT Util | Pin Count |
|------------|-----------------|----------|-----------|
| **Standalone USB** | 2×FDD + HDD + USB 2.0 HS + UART | ~47% | ~84 |
| **Retro PC Card** | 2×FDD + HDD + USB 2.0 HS + ISA 16-bit | ~49% | ~134 |
| **Full Featured** | All modules (no PCIe) | ~51% | ~146 |

**Pin Count Breakdown (Retro PC Card):**
- FDD A (34-pin Shugart): 17 pins
- FDD B (50-pin Apple): 19 pins
- HDD (34-pin ctrl + 2×20-pin data): 26 pins
- USB 2.0 HS (ULPI): 13 pins
- ISA 16-bit (8-bit + extension): 42 pins
- System + LEDs: 7 pins
- Peripherals (SPI/I2C/UART): 10 pins
- **Total: 134 pins**

---

## External Components

### Level Shifters (Per Interface)

| Component | Quantity | Purpose |
|-----------|----------|---------|
| 74AHCT125 | 2 | 3.3V → 5V output buffers |
| 74LVC245 | 1 | 5V → 3.3V input buffers |

### HDD-Specific Components

| Component | Quantity | Purpose |
|-----------|----------|---------|
| AM26LS32 | 2 | Differential line receivers (ESDI) |
| AM26LS31 | 2 | Differential line drivers (ESDI) |
| 100Ω resistors | 4 | Termination resistor packs |

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-07 | 1.8 | **PCIe fully removed:** Deleted rtl/pcie/ directory and tb_pcie_bridge.v |
| | | All PCIe references removed from documentation |
| 2025-12-07 | 1.7 | USB 2.0 HS (480 Mbps) sole high-speed host interface |
| | | Freed ~3,500 LUTs, 8 BRAM; utilization drops to ~51% |
| 2025-12-07 | 1.5 | Added -1LI Low Power variant recommendation (0.72V) |
| | | Validated all subsystems compatible with -1LI timing limits |
| | | Added Speed Grade Selection section with margin analysis |
| | | PCIe Gen3 max for -1LI; Gen4 excluded for low power |
| 2025-12-07 | 1.4 | Verified specs against AMD DS930 & Product Selection Guide |
| | | **CORRECTED:** Clock Resources from "4 MMCM, 8 PLL" to "2 MMCM, 4 PLL" |
| | | Architecture: 2 CMTs × (1 MMCM + 2 PLLs) per CMT |
| | | All other specs confirmed correct (36K LUTs, 1.93Mb BRAM, 48 DSP, 304 I/O) |
| 2025-12-08 | 1.3 | Added JTAG Debug Subsystem resources (~2K LUTs) |
| | | All 7 simulation layers validated (Layers 0-6) |
| | | Design ready for FPGA hardware synthesis |
| 2025-12-04 | 1.0 | Initial document creation |
| | | Phase 7 dual-HDD support included |
| | | Full pin budget with HDD allocation |
| 2025-12-04 | 1.1 | Added connector vs FPGA pin clarification |
| | | Added 50-pin Apple/Mac floppy interface (J5) |
| | | Clarified GND/PWR pins don't need FPGA I/O |
| 2025-12-06 | 1.2 | Added USB 2.0 High-Speed stack (ULPI PHY) |
| | | Replaced 2-pin USB with 13-pin ULPI interface |
| | | Updated utilization to 45.8% LUTs with USB |
| | | Added ULPI clock domain (60 MHz async) |
| | | USB now included in base configuration |
| | | Corrected pin counts: FDD A=17, FDD B (50-pin)=19 |
| | | HDD: 14 ctrl + 6+6 data = 26 pins total |
| | | ISA 16-bit: 24+18 = 42 pins |
| | | Current config total: 134 pins (~45%) |
