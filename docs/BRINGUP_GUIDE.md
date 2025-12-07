# FluxRipper FPGA Bring-Up Guide

**Created:** 2025-12-07 16:15
**Updated:** 2025-12-08 00:25
**Version:** 1.1
**Debug Subsystem:** v1.6.0
**Simulation Status:** All Layers (0-6) Validated

---

## Overview

This document describes the systematic layer-by-layer bring-up procedure for the FluxRipper FPGA system. The approach ensures each hardware layer is verified before adding complexity, making root cause analysis straightforward when issues arise.

### Bring-Up Philosophy

```
Never debug Layer N until Layers 0 through N-1 are verified.
```

Each layer builds on the previous, providing confidence that the foundation is solid before adding complexity.

### Required Equipment

| Item | Purpose |
|------|---------|
| AMD/Xilinx Vivado 2023.x+ | Synthesis and programming |
| Black Magic Probe (BMP) or FTDI JTAG | JTAG debug access (Layers 0-6) |
| OpenOCD 0.12+ | JTAG TAP communication |
| USB cable (Type-C) | Host connection (Layers 5+) |
| Serial terminal | CDC console access (Layers 7+) |
| Multimeter | Power rail verification |
| Oscilloscope (optional) | Clock/signal verification |
| Test floppy drive | FDC verification |
| Test hard drive | HDD verification |

---

## Phase 0: Synthesis and Programming

Before hardware bring-up, the design must be synthesized and programmed onto the FPGA.

### 0.1 Update Pin Constraints

Edit `soc/constraints/fluxripper_pinout.xdc` for your specific board:

```bash
# Check board schematic for actual pin assignments
vim soc/constraints/fluxripper_pinout.xdc

# Key pins to configure:
# - clk_25m: 25 MHz oscillator input
# - rst_n: Active-low reset button
# - JTAG pins (tck, tms, tdi, tdo, trst_n): GPIO header for BMP
# - Disk interface: flux_in, index_in, motor_on, etc.
```

### 0.2 Run Synthesis

```bash
cd FluxRipper/soc
vivado -mode batch -source scripts/synth_fluxripper.tcl
```

**Expected output:**
- Synthesis complete with no critical warnings
- Implementation passes timing (check timing_summary.rpt)
- Bitstream generated at `vivado_proj/fluxripper_rtl.runs/impl_1/fluxripper_top.bit`

### 0.3 Program FPGA

```bash
# Connect USB cable to board (for Vivado programming)
vivado -mode batch -source scripts/program_fpga.tcl

# Or use openFPGALoader:
openFPGALoader -b spartan_usp vivado_proj/fluxripper_rtl.runs/impl_1/fluxripper_top.bit
```

### 0.4 Quick JTAG Validation

Before detailed Layer 0 testing, verify basic JTAG connectivity:

```bash
# Using OpenOCD
openocd -f debug/openocd_fluxripper.cfg -c "init; scan_chain; shutdown"

# Expected output:
#    TapName             Enabled  IdCode     Expected   IrLen IrCap IrMask
# -- ------------------- -------- ---------- ---------- ----- ----- ------
#  0 fluxripper.tap         Y     0xfb010001 0xfb010001    5  0x01  0x03
```

If JTAG scan succeeds with correct IDCODE (0xFB010001), proceed to Layer 0.

### Layer Summary

| Layer | Name | Primary Tool | Key Verification |
|-------|------|--------------|------------------|
| 0 | RESET | BMP/JTAG | FPGA configured, TAP responds |
| 1 | JTAG | BMP/JTAG | IDCODE readable |
| 2 | MEMORY | BMP/JTAG | BRAM read/write works |
| 3 | GPIO | BMP/JTAG | I/O pins functional |
| 4 | CLOCKS | BMP/JTAG | All PLLs locked |
| 5 | USB_PHY | BMP/JTAG | ULPI communication works |
| 6 | USB_ENUM | BMP/JTAG | USB enumeration complete |
| 7 | CDC_CONSOLE | CDC terminal | Text console active |
| 8 | FULL_SYSTEM | CDC terminal | All subsystems operational |

---

## Pre-Power Checklist

Before applying power:

- [ ] Verify FPGA bitstream is current version
- [ ] Check all power rail voltages at test points (unpowered)
- [ ] Verify no shorts on power rails
- [ ] Connect Black Magic Probe to external JTAG header
- [ ] Ensure USB cable is NOT connected (for clean power-up)

---

## Layer 0: Reset Complete

**Goal:** Verify FPGA has configured successfully and basic TAP communication works.

### Procedure

1. Apply power to board
2. Verify DONE LED illuminates (FPGA configured)
3. Connect Black Magic Probe

```
$ arm-none-eabi-gdb
(gdb) target extended-remote /dev/ttyACM0
(gdb) monitor jtag_scan
```

### Expected Result

```
Target voltage: 3.3V
Available Targets:
No. Att Driver
 1      FluxRipper Debug v1
```

### Verification Commands

```
BMP> jtag_scan
→ Found 1 device in chain
→ IDCODE: FB010001 (FluxRipper Debug v1)
```

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| No device found | FPGA not configured | Check bitstream, DONE pin |
| Wrong IDCODE | Old bitstream | Reprogram FPGA |
| No target voltage | Power issue | Check 3.3V rail |
| Intermittent scan | JTAG signal integrity | Check cable, reduce speed |

### Success Criteria

- [ ] JTAG scan finds exactly 1 device
- [ ] IDCODE = FB010001
- [ ] No communication errors

**Layer 0 → Layer 1: PASS**

---

## Layer 1: JTAG Communication

**Goal:** Verify full JTAG TAP functionality including IR/DR operations.

### Procedure

```
# Test instruction register
BMP> jtag_ir IDCODE
BMP> jtag_dr_read 32
→ FB010001

# Test BYPASS instruction
BMP> jtag_ir BYPASS
BMP> jtag_dr_write 1 0x1
BMP> jtag_dr_read 1
→ 1

# Verify TAP state machine
BMP> jtag_ir STATUS
BMP> jtag_dr_read 32
→ 00000001  (Layer 1 indicated)
```

### Verification Commands

| Command | Expected Result | Meaning |
|---------|-----------------|---------|
| `jtag_ir IDCODE` | Success | IR shift works |
| `jtag_dr_read 32` | FB010001 | DR shift works |
| `jtag_ir BYPASS` | Success | Instruction decode works |
| `jtag_ir STATUS` + read | 0x0000000X | Status register accessible |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| IR shift fails | TAP clock issue | Check TCK frequency |
| DR reads zeros | TDO not connected | Check TDO path |
| Wrong data | Bit order | Verify MSB/LSB first setting |

### Success Criteria

- [ ] IDCODE reads correctly
- [ ] BYPASS mode works
- [ ] STATUS register shows Layer 1

**Layer 1 → Layer 2: PASS**

---

## Layer 2: Memory Access

**Goal:** Verify debug memory port can read/write system memory.

### Procedure

```
# Test scratch register (always accessible)
BMP> mem_write 0x44A8006C 0xDEADBEEF
BMP> mem_read 0x44A8006C
→ DEADBEEF

# Test BRAM base
BMP> mem_write 0x40000000 0x12345678
BMP> mem_read 0x40000000
→ 12345678

# Walking ones test
BMP> mem_write 0x40000000 0x00000001
BMP> mem_read 0x40000000
→ 00000001

BMP> mem_write 0x40000000 0x80000000
BMP> mem_read 0x40000000
→ 80000000

# Block test
BMP> mem_fill 0x40000000 0x100 0xAAAA5555
BMP> mem_test 0x40000000 0x100
→ PASS (256 words verified)
```

### Memory Map Reference

| Address Range | Peripheral | Access |
|---------------|------------|--------|
| 0x40000000-0x4000FFFF | BRAM (64KB) | R/W |
| 0x40010000-0x400100FF | GPIO | R/W |
| 0x40020000-0x400200FF | Clock Control | R/W |
| 0x40030000-0x400300FF | Instrumentation | R/O |
| 0x44000000-0x440000FF | USB Controller | R/W |
| 0x44100000-0x441000FF | FDC Controller | R/W |
| 0x44200000-0x442000FF | HDD Controller | R/W |
| 0x44A80000-0x44A800FF | Debug Registers | R/W |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| Timeout on read | AXI bus hung | Check interconnect |
| Wrong data | Address decode | Verify memory map |
| Writes don't stick | Write strobe | Check AXI WSTRB |
| Bus error | Invalid address | Check address range |

### Success Criteria

- [ ] Scratch register read/write works
- [ ] BRAM read/write works
- [ ] Block memory test passes
- [ ] No bus errors or timeouts

**Layer 2 → Layer 3: PASS**

---

## Layer 3: GPIO Access

**Goal:** Verify I/O ring and GPIO controller functionality.

### Procedure

```
# Read GPIO input register
BMP> mem_read 0x40010000
→ 00000000  (baseline, no drives)

# Test output (debug LED)
BMP> mem_write 0x40010004 0x00000001
# Visually verify LED turns ON

BMP> mem_write 0x40010004 0x00000000
# Visually verify LED turns OFF

# Read drive detect pins
# (Connect a floppy drive to FDD0)
BMP> mem_read 0x40010000
→ 00000001  (FDD0 detected)

# Test direction control
BMP> mem_read 0x40010008   # Direction register
BMP> mem_write 0x40010008 0x000000FF  # Set lower 8 as outputs
```

### GPIO Register Map

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | GPIO_IN | Input pin states (read-only) |
| 0x04 | GPIO_OUT | Output pin states |
| 0x08 | GPIO_DIR | Direction (1=output, 0=input) |
| 0x0C | GPIO_IRQ | Interrupt status |

### GPIO Bit Assignments

| Bit | Signal | Direction |
|-----|--------|-----------|
| 0 | FDD0_DETECT | Input |
| 1 | FDD1_DETECT | Input |
| 2 | FDD2_DETECT | Input |
| 3 | FDD3_DETECT | Input |
| 4 | HDD0_DETECT | Input |
| 5 | HDD1_DETECT | Input |
| 8 | DEBUG_LED0 | Output |
| 9 | DEBUG_LED1 | Output |
| 10 | DEBUG_LED2 | Output |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| All pins read 0 | I/O not configured | Check constraints |
| LED doesn't toggle | Wrong pin | Verify pinout |
| Drive not detected | Cable issue | Check 34-pin cable |
| Stuck high/low | I/O buffer issue | Check voltage levels |

### Success Criteria

- [ ] GPIO input register readable
- [ ] Debug LED toggles correctly
- [ ] Drive detect pins respond to cable connection
- [ ] No I/O conflicts

**Layer 3 → Layer 4: PASS**

---

## Layer 4: Clock System

**Goal:** Verify all PLLs are locked and clock frequencies are correct.

### Procedure

```
# Read PLL lock status
BMP> mem_read 0x40020000
→ 0000001F  (all 5 PLLs locked)

# Bit 0: 60 MHz (ULPI)
# Bit 1: 100 MHz (System)
# Bit 2: 200 MHz (FDD capture)
# Bit 3: 300 MHz (HDD capture)
# Bit 4: 48 MHz (USB reference)

# Read frequency counters (counts per 100ms gate)
BMP> mem_read 0x40030000  # 60 MHz counter
→ 005B8D80  (6,000,000 = 60 MHz)

BMP> mem_read 0x40030004  # 100 MHz counter
→ 00989680  (10,000,000 = 100 MHz)

BMP> mem_read 0x40030008  # 200 MHz counter
→ 01312D00  (20,000,000 = 200 MHz)

BMP> mem_read 0x4003000C  # 300 MHz counter
→ 01C9C380  (30,000,000 = 300 MHz)

# Check via signal tap
BMP> probe_select 3  # System group
BMP> probe_read
→ 1F000000  (PLL locks in bits 28-24)
```

### PLL Configuration

| PLL | Frequency | Source | Purpose |
|-----|-----------|--------|---------|
| 0 | 60 MHz | ULPI CLK | USB PHY interface |
| 1 | 100 MHz | Crystal | System clock |
| 2 | 200 MHz | PLL1 | FDD flux capture |
| 3 | 300 MHz | PLL1 | HDD flux capture |
| 4 | 48 MHz | PLL1 | USB reference |

### Frequency Tolerance

| Clock | Nominal | Min | Max |
|-------|---------|-----|-----|
| 60 MHz | 60.00 | 59.94 | 60.06 |
| 100 MHz | 100.00 | 99.90 | 100.10 |
| 200 MHz | 200.00 | 199.80 | 200.20 |
| 300 MHz | 300.00 | 299.70 | 300.30 |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| PLL not locked | Input clock missing | Check crystal/oscillator |
| Wrong frequency | PLL misconfigured | Check MMCM settings |
| Intermittent lock | Jitter/noise | Check power supply |
| Lock then unlock | Thermal issue | Check FPGA temperature |

### Success Criteria

- [ ] All 5 PLLs report locked (0x1F)
- [ ] Frequency counters within tolerance
- [ ] No lock/unlock cycling
- [ ] Signal tap shows stable lock bits

**Layer 4 → Layer 5: PASS**

---

## Layer 5: USB PHY Communication

**Goal:** Verify ULPI interface to USB3300/USB3320 PHY.

### Procedure

```
# Read ULPI Vendor ID (register 0x00)
BMP> mem_write 0x44000000 0x00000000  # ULPI read, addr 0
BMP> mem_read 0x44000004
→ 00000024  (SMSC vendor ID low)

# Read ULPI Product ID (register 0x02)
BMP> mem_write 0x44000000 0x00000002  # ULPI read, addr 2
BMP> mem_read 0x44000004
→ 00000004  (USB3300 product ID)

# Check line state (no host connected)
BMP> mem_read 0x44000010
→ 00000000  (SE0 - no host)

# Enable signal tap for USB
BMP> probe_select 0  # USB group
BMP> probe_read
→ 00000100  (ULPI idle, no activity)

# Start trace for USB events
BMP> trace_clear
BMP> trace_set_trigger 0x06 0x01  # USB packet events
BMP> trace_start
```

### ULPI Register Map

| Register | Address | Description |
|----------|---------|-------------|
| Vendor ID Low | 0x00 | 0x24 for SMSC |
| Vendor ID High | 0x01 | 0x04 for SMSC |
| Product ID Low | 0x02 | 0x04 for USB3300 |
| Product ID High | 0x03 | 0x00 |
| Function Control | 0x04 | Operating mode |
| Interface Control | 0x07 | Interface options |
| OTG Control | 0x0A | OTG features |
| Interrupt Status | 0x13 | Interrupt flags |
| Interrupt Latch | 0x14 | Latched interrupts |

### USB Line States

| Line State | Meaning |
|------------|---------|
| SE0 (0x00) | No host connected / Reset |
| J (0x01) | Idle (Full-Speed) |
| K (0x02) | Idle (Low-Speed) |
| SE1 (0x03) | Invalid |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| Wrong vendor ID | ULPI timing | Check clock alignment |
| Read timeout | PHY not powered | Check 3.3V to PHY |
| All zeros | ULPI DIR stuck | Check bidirectional signals |
| Random data | Signal integrity | Check trace lengths |

### Success Criteria

- [ ] ULPI vendor ID reads 0x0424
- [ ] Product ID matches PHY type
- [ ] Line state reads correctly
- [ ] No ULPI bus errors

**Layer 5 → Layer 6: PASS**

---

## Layer 6: USB Enumeration

**Goal:** Complete USB enumeration with host PC.

### Procedure

```
# Connect USB cable to host PC

# Monitor signal tap during enumeration
BMP> probe_select 0
BMP> probe_read
→ 00000204  (Chirp K detected)

# Wait for enumeration (2-3 seconds)
BMP> probe_read
→ 00000307  (High-Speed, Configured)

# Stop and read trace
BMP> trace_stop
BMP> trace_status
→ 156 entries captured

# Dump key events
BMP> trace_dump
```

### Expected Trace Sequence

```
[0001] USB_PACKET   src=USB data=0x00000001  # Bus Reset
[0045] STATE_CHANGE src=USB data=0x00000002  # Chirp K start
[0089] STATE_CHANGE src=USB data=0x00000003  # Chirp J response
[0134] STATE_CHANGE src=USB data=0x00000002  # Chirp K
[0178] STATE_CHANGE src=USB data=0x00000003  # Chirp J
...
[0512] STATE_CHANGE src=USB data=0x80000000  # HS mode entered
[1024] USB_PACKET   src=USB data=0x00002D00  # SETUP (GET_DESCRIPTOR)
[1089] USB_PACKET   src=USB data=0x00004B00  # IN
[1156] USB_PACKET   src=USB data=0x000069D2  # DATA1 (18 bytes)
[1234] USB_PACKET   src=USB data=0x00004B00  # IN (more data)
...
[2048] USB_PACKET   src=USB data=0x00002D05  # SETUP (SET_ADDRESS)
[2560] USB_PACKET   src=USB data=0x00002D09  # SETUP (SET_CONFIGURATION)
```

### Verification on Host

```bash
# Linux
lsusb -d 1209:fb01
# Expected: Bus 001 Device 003: ID 1209:fb01 FluxRipper

lsusb -d 1209:fb01 -v | head -20
# Should show: FluxRipper Disk Preservation System

# Check CDC device created
ls /dev/ttyACM*
# Expected: /dev/ttyACM0

# macOS
system_profiler SPUSBDataType | grep -A5 FluxRipper

# Windows
# Device Manager → Universal Serial Bus controllers
# Should show: FluxRipper Disk Preservation System
```

### USB State Register

```
BMP> mem_read 0x44000020  # USB state register
```

| Bits | Field | Values |
|------|-------|--------|
| 2:0 | State | 0=Detached, 1=Attached, 2=Powered, 3=Default, 4=Address, 5=Configured |
| 3 | High-Speed | 1=HS negotiated |
| 7:4 | Config | Configuration value |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| No chirp | PHY not in HS mode | Check Function Control reg |
| Chirp but no HS | Host doesn't support HS | Try different port |
| Enumeration fails | Descriptor issue | Check descriptor ROM |
| Address not set | Control EP issue | Check EP0 FSM |
| Not configured | Interface issue | Check IAD/interface descriptors |

### Success Criteria

- [ ] Chirp sequence completes (see in trace)
- [ ] High-Speed mode entered
- [ ] Device appears in host OS
- [ ] Address assigned (non-zero)
- [ ] Configuration set

**Layer 6 → Layer 7: PASS**

---

## Layer 7: CDC Console

**Goal:** Establish text-based debug console over USB CDC.

### Procedure

```bash
# Connect to CDC console
# Linux
screen /dev/ttyACM0 460800

# macOS
screen /dev/tty.usbmodem* 460800

# Windows (use PuTTY or similar)
# COM port at 460800 baud
```

### Expected Output

```
FluxRipper Debug Console v1.5.0
Build: 2025-12-07 16:00:00
Layer: 7 (CDC_CONSOLE)
>
```

### Verification Commands

```
> ?
r w p s h g t

> dbg id
ID: FB010001

> dbg status
Layer: 7 (CDC_CONSOLE)
CPU: running
Trace: stopped, 0 entries
Uptime: 00:01:23
Errors: 0

> dbg layer
Layer 7: CDC_CONSOLE
  [x] Layer 0: RESET
  [x] Layer 1: JTAG
  [x] Layer 2: MEMORY
  [x] Layer 3: GPIO
  [x] Layer 4: CLOCKS
  [x] Layer 5: USB_PHY
  [x] Layer 6: USB_ENUM
  [x] Layer 7: CDC_CONSOLE
  [ ] Layer 8: FULL_SYSTEM

> diag version
FluxRipper v1.5.0
Build: 2025-12-07 16:00:00
Git: abc1234
FPGA: FluxRipper_v1.5.bit
```

### CDC Console Commands Reference

| Command | Description |
|---------|-------------|
| `?` | Quick command list |
| `dbg status` | Full debug status |
| `dbg id` | Show JTAG IDCODE |
| `dbg layer` | Show layer progress |
| `dbg r <addr>` | Read memory word |
| `dbg w <addr> <data>` | Write memory word |
| `dbg dump <addr> [len]` | Hex dump |
| `dbg probe [group]` | Signal tap read |
| `dbg trace start\|stop` | Trace control |
| `diag version` | Firmware version |
| `diag all` | Full diagnostics |

### Troubleshooting

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| No /dev/ttyACM* | CDC not enumerated | Check Interface 2/3 descriptors |
| Garbled output | Wrong baud rate | Use 460800 |
| No response | Console parser hung | Reset via JTAG |
| Partial commands | Buffer overflow | Reduce command rate |

### Success Criteria

- [ ] CDC device appears on host
- [ ] Console banner displayed
- [ ] Commands echo correctly
- [ ] `dbg status` shows Layer 7
- [ ] All previous layers marked complete

**Layer 7 → Layer 8: PASS**

---

## Layer 8: Full System

**Goal:** Verify all subsystems operational.

### FDC Subsystem Test

```
# Connect floppy drive to FDD0

> diag drives
FDD0: 3.5" HD, Ready, Track 0
FDD1: Not connected
FDD2: Not connected
FDD3: Not connected
HDD0: Not connected
HDD1: Not connected

> dbg probe 1
P:00800000  (FDC: Ready, Track 0)

> dbg r 44100000
OK: 00000080  (FDC status: Ready)

# Insert floppy disk
> diag drives
FDD0: 3.5" HD, Ready, Track 0, Disk Present

# Test seek
> dbg w 44100004 0x0000002A  (Seek to track 42)
> dbg r 44100000
OK: 00000080  (Ready, seek complete)
```

### HDD Subsystem Test

```
# Connect ST-506 drive to HDD0

> diag drives
...
HDD0: ST-225, Ready, Cyl 0, Head 0
HDD1: Not connected

> dbg probe 2
P:00400001  (HDD: Ready, Cylinder 0)

# Test seek
> dbg w 44200004 0x00000064  (Seek to cylinder 100)
> dbg r 44200000
OK: 00000080  (Ready)
```

### Power Subsystem Test

```
> power status
Input Sources:
  USB-C: 5V @ 1.2A (6.0W)
  ATX: Not connected

Drive Connectors:
  FDD0: 5V enabled,  120mA (0.60W)
  FDD1: Disabled
  FDD2: Disabled
  FDD3: Disabled (24V capable)
  HDD0: Disabled
  HDD1: Disabled

System Rails:
  3.3V: 3.31V @ 450mA
  1.0V: 1.01V @ 890mA
  VCCAUX: 1.80V @ 120mA

> power enable hdd0
OK: HDD0 enabled
  12V: 11.95V @ 0mA (spin-up pending)
  5V: 5.02V @ 85mA
```

### Full Diagnostics

```
> diag all
================================================================================
FluxRipper System Diagnostics
================================================================================

Version:
  Firmware: v1.5.0 (2025-12-07)
  FPGA: FluxRipper_v1.5.bit
  Git: abc1234def

Uptime: 00:15:42
Boot Count: 1

Drives:
  FDD0: 3.5" HD, Ready, Disk Present
  FDD1-3: Not connected
  HDD0: ST-225, Ready, 615 cyl x 4 head x 17 spt
  HDD1: Not connected

Clocks:
  60 MHz (ULPI): 60.00 MHz, PLL locked
  100 MHz (System): 100.00 MHz, PLL locked
  200 MHz (FDD): 200.00 MHz, PLL locked
  300 MHz (HDD): 300.00 MHz, PLL locked

USB:
  State: Configured (High-Speed)
  Address: 3
  Endpoints: EP0 (ctrl), EP1 (bulk), EP2 (bulk), EP3 (CDC)
  Packets: TX=1234, RX=5678, Errors=0

Power:
  Input: USB-C 5V @ 2.1A (10.5W)
  System: 3.3V=3.31V, 1.0V=1.01V
  Drives: FDD0=0.6W, HDD0=6.2W

Temperature:
  FPGA: 42°C
  Board: 35°C
  USB PHY: 38°C

Errors:
  None

Layer: 8 (FULL_SYSTEM)
================================================================================
```

### Success Criteria

- [ ] All connected drives detected
- [ ] Drive operations (seek, read) work
- [ ] Power monitoring accurate
- [ ] No errors in diagnostics
- [ ] Layer shows 8 (FULL_SYSTEM)

**BRING-UP COMPLETE**

---

## Iterative Debug Workflow

Once at Layer 8, use this workflow for debugging issues:

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEBUG ITERATION LOOP                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. OBSERVE                                                     │
│     > dbg probe <group>      # Check signal state               │
│     > dbg trace start        # Begin capture                    │
│                                                                 │
│  2. TRIGGER                                                     │
│     > [perform operation]    # The action being debugged        │
│                                                                 │
│  3. CAPTURE                                                     │
│     > dbg trace stop                                            │
│     > dbg trace dump         # Review events                    │
│                                                                 │
│  4. ANALYZE                                                     │
│     > dbg r <addr>           # Read suspect registers           │
│     > dbg dump <addr> <len>  # Examine memory                   │
│                                                                 │
│  5. HYPOTHESIZE                                                 │
│     - Form theory about root cause                              │
│     - Identify code location to fix                             │
│                                                                 │
│  6. FIX                                                         │
│     - Edit RTL or firmware                                      │
│     - Rebuild and reprogram                                     │
│                                                                 │
│  7. VERIFY                                                      │
│     - Return to step 1                                          │
│     - Confirm fix, check for regressions                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Signal Tap Groups

| Group | Command | Signals |
|-------|---------|---------|
| 0 | `dbg probe 0` | USB: ULPI state, packet type, handshake |
| 1 | `dbg probe 1` | FDC: command, track, sector, status |
| 2 | `dbg probe 2` | HDD: command, cylinder, head, sector |
| 3 | `dbg probe 3` | System: clocks, resets, PLL locks, temp |

### Trace Event Types

| Type | Code | Description |
|------|------|-------------|
| STATE_CHANGE | 0x01 | FSM state transition |
| REG_WRITE | 0x02 | Register write |
| REG_READ | 0x03 | Register read |
| INTERRUPT | 0x04 | Interrupt occurred |
| ERROR | 0x05 | Error condition |
| USB_PACKET | 0x06 | USB packet sent/received |
| FDC_CMD | 0x07 | FDC command issued |
| HDD_CMD | 0x08 | HDD command issued |

---

## Recovery Procedures

### CPU Hang Recovery

```
> dbg cpu halt
OK

> dbg cpu status
PC: 0x40001234
State: Halted

> dbg cpu reg
x0=00000000 x1=40001234 x2=DEADBEEF x3=00000000
...

> dbg cpu bp 40001234
OK: Breakpoint set

> dbg cpu run
# Breaks at suspect address

> dbg cpu step
PC: 0x40001238
```

### USB Recovery (via JTAG)

If USB stops responding, use Black Magic Probe:

```
BMP> mem_read 0x44000020   # Check USB state
→ 00000003  (stuck in Default state)

BMP> mem_write 0x44000024 0x80000000  # Force USB reset
BMP> mem_read 0x44000020
→ 00000000  (Detached)

# Reconnect USB cable
BMP> mem_read 0x44000020
→ 00000005  (Configured)
```

### Full System Reset

```
# CPU reset only (FPGA keeps running)
> dbg cpu reset
OK: CPU reset

# If that fails, via JTAG:
BMP> cpu_reset

# Last resort: power cycle
# Then restart from Layer 0
```

---

## Appendix A: Register Quick Reference

### Debug Registers (0x44A80000)

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | CTRL | R/W | Control register |
| 0x04 | STATUS | R | Status register |
| 0x6C | SCRATCH | R/W | Test register |
| 0x70 | IDCODE | R | JTAG ID (FB010001) |
| 0x74 | LAYER | R | Current layer |

### USB Registers (0x44000000)

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | ULPI_CMD | R/W | ULPI command |
| 0x04 | ULPI_DATA | R | ULPI read data |
| 0x10 | LINE_STATE | R | USB line state |
| 0x20 | USB_STATE | R | USB device state |
| 0x24 | USB_ADDR | R | Assigned address |

### FDC Registers (0x44100000)

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | STATUS | R | FDC status |
| 0x04 | COMMAND | W | FDC command |
| 0x08 | TRACK | R/W | Current track |
| 0x0C | SECTOR | R/W | Current sector |

### HDD Registers (0x44200000)

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | STATUS | R | HDD status |
| 0x04 | COMMAND | W | HDD command |
| 0x08 | CYLINDER | R/W | Current cylinder |
| 0x0C | HEAD | R/W | Current head |

---

## Appendix B: Common Issues Checklist

### "Device not found" (Layer 0-1)
- [ ] FPGA DONE LED lit?
- [ ] JTAG cable connected?
- [ ] BMP firmware updated?
- [ ] TCK frequency reduced?

### "Memory access fails" (Layer 2)
- [ ] Correct address used?
- [ ] AXI interconnect synthesized?
- [ ] Clock domain crossing issue?

### "USB won't enumerate" (Layer 6)
- [ ] PHY powered (3.3V)?
- [ ] ULPI timing met?
- [ ] Descriptors valid?
- [ ] Try different USB port/cable?

### "CDC console garbled" (Layer 7)
- [ ] Baud rate 460800?
- [ ] Flow control off?
- [ ] Correct COM port?

---

## Appendix C: Version History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-12-08 | 1.1 | Claude | Added Phase 0 (Synthesis/Programming), OpenOCD configs, updated equipment list |
| 2025-12-07 | 1.0 | Claude | Initial bring-up guide |
