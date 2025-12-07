# MSC Geometry & Ready Signal Interface Design

**Created:** 2025-12-05 21:45
**Status:** Proposed

---

## Problem Statement

The USB Mass Storage Class (MSC) implementation in `usb_top.v` has hardcoded:
1. FDD geometry (2880 sectors / 1.44MB)
2. HDD geometry (0 sectors / not present)
3. FDD/HDD ready signals (always 1'b1)

This prevents accurate SCSI READ_CAPACITY responses and proper drive status reporting.

---

## Requirements

1. Firmware must communicate detected drive geometry to RTL
2. RTL must report accurate capacity in SCSI responses
3. Ready signals must reflect actual drive state
4. Support hot-plug detection (media change)
5. Minimal resource usage

---

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           fluxripper_dual_top.v                             │
│                                                                             │
│  ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐   │
│  │                  │      │                  │      │                  │   │
│  │  AXI Periph      │◄────►│  msc_config_regs │─────►│    usb_top.v     │   │
│  │  Interconnect    │      │                  │      │                  │   │
│  │                  │      │  (New Module)    │      │  drive_lun_      │   │
│  └──────────────────┘      └──────────────────┘      │  mapper          │   │
│          ▲                         ▲                 │                  │   │
│          │                         │                 └──────────────────┘   │
└──────────┼─────────────────────────┼────────────────────────────────────────┘
           │                         │
           │                         │ Geometry + Status
           ▼                         │
    ┌──────────────┐                 │
    │  Firmware    │─────────────────┘
    │  msc_hal.c   │  AXI writes after
    │              │  profile detection
    └──────────────┘
```

---

## New Module: msc_config_regs.v

### Register Map (Base: 0x4005_0000)

| Offset | Name | Width | Access | Description |
|--------|------|-------|--------|-------------|
| 0x00 | CTRL | 32 | R/W | Control register |
| 0x04 | STATUS | 32 | R | Status register |
| 0x10 | FDD0_GEOMETRY | 32 | R/W | FDD 0 geometry |
| 0x14 | FDD1_GEOMETRY | 32 | R/W | FDD 1 geometry |
| 0x20 | HDD0_CAPACITY_LO | 32 | R/W | HDD 0 capacity (low) |
| 0x24 | HDD0_CAPACITY_HI | 32 | R/W | HDD 0 capacity (high) |
| 0x28 | HDD1_CAPACITY_LO | 32 | R/W | HDD 1 capacity (low) |
| 0x2C | HDD1_CAPACITY_HI | 32 | R/W | HDD 1 capacity (high) |
| 0x30 | DRIVE_STATUS | 32 | R/W | Drive presence/ready |

### Register Definitions

#### CTRL (0x00)
```
[0]     CONFIG_VALID    - Set by firmware when geometry is valid
[1]     FORCE_UPDATE    - Trigger geometry update to RTL
[7:4]   BLOCK_SIZE_SEL  - Block size (0=512, 1=1024, 2=2048, 3=4096)
[31:8]  Reserved
```

#### STATUS (0x04)
```
[0]     FDD0_PRESENT    - FDD 0 media present (from RTL)
[1]     FDD1_PRESENT    - FDD 1 media present (from RTL)
[2]     HDD0_PRESENT    - HDD 0 ready (from RTL)
[3]     HDD1_PRESENT    - HDD 1 ready (from RTL)
[7:4]   Reserved
[11:8]  FDD0_STATE      - FDD 0 state machine
[15:12] FDD1_STATE      - FDD 1 state machine
[31:16] Reserved
```

#### FDDx_GEOMETRY (0x10, 0x14)
```
[15:0]  SECTOR_COUNT    - Total sectors (max 65535 for FDD)
[23:16] TRACKS          - Number of tracks (40, 77, 80)
[27:24] HEADS           - Number of heads (1 or 2)
[31:28] SPT             - Sectors per track (9, 18, 36)
```

#### HDDx_CAPACITY (0x20-0x2C)
```
[31:0]  SECTOR_COUNT    - Total sectors (64-bit across LO/HI)
```

#### DRIVE_STATUS (0x30)
```
[0]     FDD0_READY      - FDD 0 ready for commands
[1]     FDD1_READY      - FDD 1 ready for commands
[2]     HDD0_READY      - HDD 0 ready for commands
[3]     HDD1_READY      - HDD 1 ready for commands
[4]     FDD0_CHANGED    - FDD 0 media changed (write 1 to clear)
[5]     FDD1_CHANGED    - FDD 1 media changed (write 1 to clear)
[6]     HDD0_CHANGED    - HDD 0 changed (write 1 to clear)
[7]     HDD1_CHANGED    - HDD 1 changed (write 1 to clear)
[11:8]  FDD0_WP         - FDD 0 write protect
[15:12] FDD1_WP         - FDD 1 write protect
[31:16] Reserved
```

---

## RTL Changes

### 1. New Module: msc_config_regs.v (~150 lines)

```verilog
module msc_config_regs (
    input  wire        clk,
    input  wire        rst_n,

    // AXI-Lite Slave Interface
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // Configuration Outputs (to usb_top)
    output wire        config_valid,
    output wire [15:0] fdd0_sectors,
    output wire [15:0] fdd1_sectors,
    output wire [31:0] hdd0_sectors,
    output wire [31:0] hdd1_sectors,
    output wire [3:0]  drive_ready,      // [0]=FDD0, [1]=FDD1, [2]=HDD0, [3]=HDD1
    output wire [3:0]  drive_wp,         // Write protect status

    // Status Inputs (from usb_top / HAL)
    input  wire [3:0]  drive_present,    // Physical presence
    input  wire [3:0]  media_changed     // Media change detect
);
```

### 2. usb_top.v Port Additions (~20 lines)

```verilog
module usb_top (
    // ... existing ports ...

    // MSC Configuration Interface (NEW)
    input  wire        msc_config_valid,
    input  wire [15:0] msc_fdd0_sectors,
    input  wire [15:0] msc_fdd1_sectors,
    input  wire [31:0] msc_hdd0_sectors,
    input  wire [31:0] msc_hdd1_sectors,
    input  wire [3:0]  msc_drive_ready,
    input  wire [3:0]  msc_drive_wp,

    // MSC Status Interface (NEW)
    output wire [3:0]  msc_drive_present,
    output wire [3:0]  msc_media_changed
);
```

### 3. usb_top.v Internal Changes (~30 lines)

Replace hardcoded geometry with input signals:

```verilog
// Remove hardcoded arrays
// wire [15:0] fdd_capacity_arr [0:1];
// assign fdd_capacity_arr[0] = 16'd2880;  // DELETE

// Use configuration inputs instead
wire [15:0] fdd_capacity_arr [0:1];
wire [15:0] fdd_block_size_arr [0:1];
assign fdd_capacity_arr[0] = msc_config_valid ? msc_fdd0_sectors : 16'd2880;
assign fdd_capacity_arr[1] = msc_config_valid ? msc_fdd1_sectors : 16'd2880;
assign fdd_block_size_arr[0] = 16'd512;
assign fdd_block_size_arr[1] = 16'd512;

wire [31:0] hdd_capacity_arr [0:1];
assign hdd_capacity_arr[0] = msc_config_valid ? msc_hdd0_sectors : 32'd0;
assign hdd_capacity_arr[1] = msc_config_valid ? msc_hdd1_sectors : 32'd0;

// Replace hardcoded ready signals
.fdd_ready        (msc_drive_ready[1:0] | ~msc_config_valid),
.hdd_ready        (msc_drive_ready[3:2] | ~msc_config_valid),
```

### 4. fluxripper_dual_top.v Changes (~40 lines)

Instantiate and wire the new config register block.

---

## Firmware Changes

### 1. New Header: msc_config.h (~50 lines)

```c
#ifndef MSC_CONFIG_H
#define MSC_CONFIG_H

#include <stdint.h>
#include <stdbool.h>

#define MSC_CONFIG_BASE     0x40050000

/* Register offsets */
#define MSC_CTRL            0x00
#define MSC_STATUS          0x04
#define MSC_FDD0_GEOMETRY   0x10
#define MSC_FDD1_GEOMETRY   0x14
#define MSC_HDD0_CAP_LO     0x20
#define MSC_HDD0_CAP_HI     0x24
#define MSC_HDD1_CAP_LO     0x28
#define MSC_HDD1_CAP_HI     0x2C
#define MSC_DRIVE_STATUS    0x30

/* Control bits */
#define MSC_CTRL_CONFIG_VALID   (1 << 0)
#define MSC_CTRL_FORCE_UPDATE   (1 << 1)

/* Functions */
void msc_config_init(void);
void msc_config_set_fdd_geometry(uint8_t drive, uint16_t sectors,
                                  uint8_t tracks, uint8_t heads, uint8_t spt);
void msc_config_set_hdd_capacity(uint8_t drive, uint64_t sectors);
void msc_config_set_ready(uint8_t drive, bool ready);
void msc_config_validate(void);

#endif
```

### 2. msc_hal.c Integration (~30 lines)

Add calls to update config registers after profile detection:

```c
static void configure_fdd_lun(uint8_t lun_index, uint8_t drive_index)
{
    drive_profile_t profile;

    if (hal_get_profile(drive_index, &profile) == HAL_OK && profile.valid) {
        uint32_t capacity = calculate_fdd_capacity(&profile);

        // Update config registers for RTL
        msc_config_set_fdd_geometry(drive_index,
                                    (uint16_t)capacity,
                                    profile.tracks,
                                    2,  // heads
                                    sectors_per_track(&profile));

        // ... rest of existing code ...
    }
}
```

---

## Data Flow

```
1. System Boot
   └─► Firmware starts
       └─► msc_config_init() - clear registers, config_valid=0

2. Drive Detection
   └─► hal_get_profile() detects drive
       └─► msc_config_set_fdd_geometry() writes to registers

3. Configuration Complete
   └─► msc_config_validate() sets config_valid=1
       └─► RTL reads new geometry values

4. SCSI READ_CAPACITY
   └─► Host sends READ_CAPACITY command
       └─► msc_scsi_engine reads from drive_lun_mapper
           └─► drive_lun_mapper returns configured geometry
               └─► Host receives correct disk size

5. Media Change
   └─► User inserts new disk
       └─► RTL sets media_changed bit
           └─► Firmware detects change via interrupt/poll
               └─► Re-run detection, update geometry
```

---

## Resource Estimates

| Component | LUTs | FFs | BRAM |
|-----------|------|-----|------|
| msc_config_regs.v | ~120 | ~200 | 0 |
| usb_top.v changes | ~20 | ~10 | 0 |
| **Total** | **~140** | **~210** | **0** |

---

## Implementation Order

1. **Phase 1: RTL** (~200 lines)
   - Create `msc_config_regs.v`
   - Add ports to `usb_top.v`
   - Wire in `fluxripper_dual_top.v`

2. **Phase 2: Firmware** (~100 lines)
   - Create `msc_config.h` / `msc_config.c`
   - Integrate with `msc_hal.c`

3. **Phase 3: Testing**
   - Verify geometry updates propagate
   - Test hot-plug scenarios
   - Validate SCSI responses

---

## Alternative Considered: Shared Memory

Instead of dedicated registers, geometry could be stored in shared SRAM at a known address. This was rejected because:
- Requires memory arbitration
- More complex timing
- Harder to debug
- No significant resource savings

---

## Open Questions

1. Should media_changed trigger an interrupt or use polling?
2. Do we need per-LUN block size configuration?
3. Should HDD capacity use 48-bit LBA (ATA-6) or 32-bit?
