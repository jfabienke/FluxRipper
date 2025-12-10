# FluxRipper Development Workflow

**Created:** 2025-12-07 16:40
**Version:** 1.0

---

## Overview

This document describes the tight-loop development workflow for FluxRipper, optimized for rapid iteration with hardware-in-the-loop testing.

### Key Principles

1. **Minimize iteration time** - Firmware changes deploy in seconds, not minutes
2. **Continuous verification** - Every change triggers automated tests
3. **Fail fast** - Quick smoke tests catch regressions immediately
4. **Background builds** - RTL synthesis runs while you continue working
5. **Layer isolation** - Debug issues at the lowest failing layer

---

## Development Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EDIT PHASE                                        │
│                                                                             │
│    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                  │
│    │  Firmware   │     │    RTL      │     │   Tests     │                  │
│    │   (.c/.h)   │     │   (.v/.sv)  │     │   (.py)     │                  │
│    └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                  │
│           │                   │                   │                         │
└───────────┼───────────────────┼───────────────────┼─────────────────────────┘
            │                   │                   │
            ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BUILD PHASE                                       │
│                                                                             │
│    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                  │
│    │  GCC Build  │     │   Vivado    │     │   pytest    │                  │
│    │   ~2 sec    │     │  ~15 min    │     │   ~0 sec    │                  │
│    │ FOREGROUND  │     │ BACKGROUND  │     │             │                  │
│    └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                  │
│           │                   │                   │                         │
└───────────┼───────────────────┼───────────────────┼─────────────────────────┘
            │                   │                   │
            ▼                   │                   ▼
┌───────────────────────────────┼─────────────────────────────────────────────┐
│                         DEPLOY PHASE                                        │
│                               │                                             │
│    ┌─────────────┐            │            ┌─────────────┐                  │
│    │ Hot Reload  │            │            │ Test Runner │                  │
│    │ via Debug   │            │            │ via CDC     │                  │
│    │  ~100 ms    │            │            │             │                  │
│    └──────┬──────┘            │            └──────┬──────┘                  │
│           │                   │                   │                         │
│           │         ┌─────────┴─────────┐         │                         │
│           │         │  FPGA Reprogram   │         │                         │
│           │         │     ~5 sec        │         │                         │
│           │         │  (when ready)     │         │                         │
│           │         └─────────┬─────────┘         │                         │
│           │                   │                   │                         │
└───────────┼───────────────────┼───────────────────┼─────────────────────────┘
            │                   │                   │
            ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VERIFY PHASE                                       │
│                                                                             │
│         ┌───────────────────────────────────────────────────┐               │
│         │              Hardware Target                      │               │
│         │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐    │               │
│         │  │ Signal  │  │  Trace  │  │  Automated      │    │               │
│         │  │  Tap    │  │ Buffer  │  │  Tests          │    │               │
│         │  └────┬────┘  └────┬────┘  └────────┬────────┘    │               │
│         │       │            │                │             │               │
│         │       └────────────┴────────────────┘             │               │
│         │                    │                              │               │
│         │            Pass/Fail Result                       │               │
│         └────────────────────┼──────────────────────────────┘               │
│                              │                                              │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │
                               ▼
                        ┌─────────────┐
                        │  Continue   │◄─── Loop back to EDIT
                        │  or Debug   │
                        └─────────────┘
```

---

## Iteration Times

| Change Type | Build | Deploy | Test | Total |
|-------------|-------|--------|------|-------|
| Firmware only | 2s | 0.1s | 5s | **~7 seconds** |
| Test only | 0s | 0s | 5s | **~5 seconds** |
| RTL (minor) | 15min | 5s | 5s | ~15 min (background) |
| RTL (major) | 30min | 5s | 5s | ~30 min (background) |

**Key insight:** 90% of development iterations are firmware-only or test-only, completing in under 10 seconds.

---

## Quick Start

### 1. Start Development Console

```bash
cd FluxRipper/tools/devloop
./fluxripper_dev.py

# Or with specific port
./fluxripper_dev.py --port /dev/ttyACM0
```

### 2. Check Status

```
dev> status

============================================================
FluxRipper Development Status
============================================================
Layer: 8
  cpu: running
  uptime: 00:15:42
  errors: 0

RTL Build: idle
============================================================
```

### 3. Edit-Reload-Test Cycle

```
# Make firmware changes in editor...

dev> reload
Building firmware...
Firmware built in 1.8s
Deploying firmware (32768 bytes)...
Firmware deployed successfully
Firmware running, layer: 8

dev> quick
Quick tests: PASS

dev> test
============================================================
Running tests (current layer: 8)
============================================================
  PASS  bram_basic (0.45s)
  PASS  bram_addr_lines (2.12s)
  PASS  clock_freq (0.89s)
  ...
============================================================
Results: 18 passed, 0 failed, 2 skipped
```

### 4. Watch Mode (Auto-Reload)

```
dev> watch
Watching for changes (Ctrl+C to stop)...

# Edit firmware file...
Firmware change detected...
Building firmware...
Firmware built in 1.9s
Deploying firmware (32768 bytes)...
Firmware deployed successfully
Quick tests passed

# Edit RTL file...
RTL change detected, starting background build...

# Continue working...
# 15 minutes later:
RTL build complete in 14.2 minutes
New bitstream ready! Program FPGA with:
  vivado -mode batch -source program.tcl
```

---

## Detailed Workflows

### Firmware Development

Firmware changes are the fastest iteration path:

```
┌──────────────────────────────────────────────────────────────┐
│  1. Edit firmware source                                     │
│     vim soc/firmware/src/my_module.c                         │
│                                                              │
│  2. Build (automatic or manual)                              │
│     dev> reload                                              │
│     # OR: watch mode auto-detects changes                    │
│                                                              │
│  3. Deploy via debug port                                    │
│     - CPU halted                                             │
│     - Binary written to BRAM                                 │
│     - CPU reset and resumed                                  │
│     - ~100ms total                                           │
│                                                              │
│  4. Verify                                                   │
│     dev> quick           # Smoke test                        │
│     dev> test            # Full test suite                   │
│                                                              │
│  5. Debug if needed                                          │
│     dev> probe 1         # Check FDC signals                 │
│     dev> trace           # Capture events                    │
│     dev> r 44100000      # Read register                     │
└──────────────────────────────────────────────────────────────┘
```

### RTL Development

RTL changes require synthesis but can run in background:

```
┌──────────────────────────────────────────────────────────────┐
│  1. Edit RTL source                                          │
│     vim rtl/fdc/command_fsm.v                                │
│                                                              │
│  2. Start background build                                   │
│     dev> watch                                               │
│     # Detects change, starts Vivado in background            │
│                                                              │
│  3. Continue other work                                      │
│     - Firmware development                                   │
│     - Documentation                                          │
│     - Test development                                       │
│                                                              │
│  4. When build completes (notification appears):             │
│     # Program FPGA                                           │
│     vivado -mode batch -source program.tcl                   │
│                                                              │
│  5. Reconnect and verify                                     │
│     dev> status          # Check layer                       │
│     dev> test            # Full test suite                   │
└──────────────────────────────────────────────────────────────┘
```

### Debug Session

When something isn't working:

```
┌──────────────────────────────────────────────────────────────┐
│  1. Identify failing layer                                   │
│     dev> status                                              │
│     Layer: 5   # USB PHY - issue is here or below            │
│                                                              │
│  2. Check signals at that layer                              │
│     dev> probe 0         # USB signals                       │
│     P:00000000           # Nothing - PHY not responding      │
│                                                              │
│  3. Capture trace around the problem                         │
│     dev> dbg trace clear                                     │
│     dev> dbg trace start                                     │
│     # Trigger the problem                                    │
│     dev> dbg trace stop                                      │
│     dev> dbg trace dump                                      │
│                                                              │
│  4. Examine state                                            │
│     dev> r 44000000      # ULPI command reg                  │
│     dev> r 44000004      # ULPI data reg                     │
│     dev> dump 44000000 40  # Full USB register block         │
│                                                              │
│  5. Form hypothesis, fix, verify                             │
│     # Edit code based on findings                            │
│     dev> reload          # If firmware                       │
│     dev> test            # Verify fix                        │
└──────────────────────────────────────────────────────────────┘
```

---

## Command Reference

### Development Console Commands

| Command | Description |
|---------|-------------|
| `status` | Show current system status and layer |
| `reload` | Rebuild and deploy firmware |
| `test` | Run full test suite |
| `quick` | Run quick smoke tests only |
| `watch` | Auto-reload on file changes |
| `probe <n>` | Read signal tap group (0-3) |
| `trace` | Capture and dump trace |
| `r <addr>` | Read memory word |
| `w <addr> <data>` | Write memory word |
| `quit` | Exit console |

### Direct CDC Commands

Any command not recognized is passed through to the CDC console:

```
dev> diag version
FluxRipper v1.5.0
Build: 2025-12-07 16:00:00

dev> power status
USB-C: 5V @ 1.2A (6.0W)
...

dev> dbg cpu halt
OK
```

---

## Test Categories

### Quick Tests (< 5 seconds)

Run automatically after every firmware reload:

- Memory basic read/write
- PLL lock status
- USB enumeration
- Debug IDCODE

### Full Tests (< 60 seconds)

Run manually or in CI:

- All memory tests (patterns, address/data lines)
- Clock frequency verification
- USB PHY registers
- All debug subsystem features
- FDC/HDD register access
- Power monitoring

### Stress Tests (minutes)

Run for release validation:

- Memory stress (rapid access)
- Console stress (rapid commands)
- Long-term stability

---

## Continuous Integration

### Hardware-in-the-Loop CI

```yaml
# .github/workflows/hil-test.yml
name: Hardware-in-the-Loop Tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  hardware-test:
    runs-on: self-hosted  # Runner with FluxRipper attached

    steps:
      - uses: actions/checkout@v4

      - name: Build Firmware
        run: |
          cd soc/firmware
          make clean
          make -j4

      - name: Deploy and Test
        run: |
          cd tools/devloop
          python3 fluxripper_dev.py reload
          python3 fluxripper_dev.py test

      - name: Upload Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: tools/devloop/results/
```

### Nightly RTL Build

```yaml
# .github/workflows/nightly-rtl.yml
name: Nightly RTL Build

on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM daily

jobs:
  rtl-build:
    runs-on: vivado-runner

    steps:
      - uses: actions/checkout@v4

      - name: Synthesize
        run: |
          cd build
          vivado -mode batch -source build.tcl

      - name: Upload Bitstream
        uses: actions/upload-artifact@v4
        with:
          name: bitstream
          path: build/fluxripper.bit
```

---

## Best Practices

### 1. Start with Firmware

When adding a new feature:
1. Implement in firmware first (fast iteration)
2. Verify functionality
3. Move performance-critical parts to RTL
4. Verify again

### 2. Layer-by-Layer Development

When bringing up new hardware:
1. Verify each layer before moving up
2. Never skip layers
3. Document any layer-specific quirks

### 3. Test Everything

- Write tests alongside code
- Run quick tests after every change
- Run full tests before commits

### 4. Use Watch Mode

- Leave `watch` running during development
- Get instant feedback on changes
- Background RTL builds don't block you

### 5. Capture Before Debugging

Before diving into a bug:
1. Start trace capture
2. Reproduce the issue
3. Stop capture
4. Analyze events

---

## Troubleshooting

### "Failed to connect"

```
dev> status
Not connected
```

- Check USB cable
- Verify `/dev/ttyACM0` exists
- Check permissions (`sudo chmod 666 /dev/ttyACM0`)
- Try different port (`--port /dev/ttyACM1`)

### "Firmware deploy failed"

```
dev> reload
Failed to halt CPU
```

- CPU may be stuck in bad state
- Try: `dev> dbg cpu reset`
- If that fails, power cycle and start from layer 0

### "Tests failing after RTL change"

- Verify FPGA was actually reprogrammed
- Check layer status (`dev> status`)
- Run bring-up verification from layer 0

### "Watch mode not detecting changes"

- Check file patterns in `fluxripper_dev.py`
- Verify files are being saved
- Check filesystem events (`inotify` on Linux)

---

## Appendix: File Structure

```
FluxRipper/
├── docs/
│   ├── BRINGUP_GUIDE.md       # Layer-by-layer bring-up
│   ├── DEVELOPMENT_WORKFLOW.md # This document
│   └── STACK_STATUS.md        # Component status
│
├── rtl/                       # Verilog source
│   ├── debug/                 # Debug subsystem
│   ├── fdc/                   # FDC controller
│   ├── hdd/                   # HDD controller
│   └── usb/                   # USB stack
│
├── soc/
│   └── firmware/              # Firmware source
│       ├── include/           # Headers
│       ├── src/               # Source files
│       └── Makefile
│
├── build/                     # Vivado project
│   ├── build.tcl              # Synthesis script
│   └── program.tcl            # Programming script
│
└── tools/
    └── devloop/               # Development tools
        ├── fluxripper_dev.py  # Main dev console
        └── tests/
            └── test_hardware.py # Hardware tests
```

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-07 | 1.0 | Initial workflow documentation |
