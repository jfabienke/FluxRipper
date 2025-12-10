# FluxRipper Firmware: Rust/Embassy Port Assessment

*Created: 2025-12-09*

## Overview

This document assesses the feasibility and effort required to port the FluxRipper SoC firmware from C to Rust using the [Embassy](https://embassy.dev/) async embedded framework.

**Bottom Line**: A full production port is feasible in **12-18 weeks** with manageable risks.

---

## Current Firmware Architecture

### Platform

| Aspect | Value |
|--------|-------|
| **Processor** | MicroBlaze V (AMD's RISC-V soft core) |
| **ISA** | RV32IMC (32-bit, integer, multiply, compressed) |
| **FPGA** | AMD Spartan UltraScale+ SCU35 |
| **Clock** | 100 MHz CPU, 200 MHz FDC, 300 MHz HDD |

### Memory Layout

```
┌──────────────────────────────────────────────────────────────┐
│ Address Range          │ Size   │ Purpose                    │
├──────────────────────────────────────────────────────────────┤
│ 0x0000_0000-0x0000_7FFF │ 32 KB  │ Code BRAM (instructions)  │
│ 0x0001_0000-0x0001_3FFF │ 16 KB  │ Data BRAM (stack, BSS)    │
│ 0x4000_0000-0x40FF_FFFF │ 8 MB   │ HyperRAM (track buffers)  │
│ 0x8000_0000+            │ varies │ Memory-mapped peripherals │
└──────────────────────────────────────────────────────────────┘
```

**Key Constraint**: 32 KB code BRAM limit. Rust binaries tend to be 30-50% larger than C.

### Execution Model

- **Bare-metal** - no RTOS
- **Single-threaded** - one execution context
- **Interrupt-driven** - peripherals trigger ISRs
- **Polling CLI** - main loop blocks on UART input

### Codebase Statistics

| Component | Files | Lines | Notes |
|-----------|-------|-------|-------|
| Core runtime | 3 | 550 | main.c, crt0.S, link.ld |
| Drivers (UART, Timer) | 4 | 350 | Direct register access |
| CLI framework | 2 | 300 | Command tokenization/dispatch |
| FluxRipper HAL (FDC) | 2 | 1,500 | Floppy control, flux capture |
| HDD HAL | 4 | 2,800 | ST-506/ESDI, geometry detection |
| MSC HAL (USB) | 4 | 2,400 | USB Mass Storage config |
| Power HAL (I2C) | 2 | 2,300 | INA3221 power monitoring |
| Protocol handlers | 4 | 3,500 | SCSI, raw mode, diagnostics |
| CLI commands | 5 | 3,500 | User interface commands |
| **Total** | **~48** | **~15,000** | C + headers |

### Dependencies

The current firmware has minimal external dependencies:

| Dependency | Usage | Rust Equivalent |
|------------|-------|-----------------|
| `stdint.h` | Fixed-width integers | Built-in (`u32`, `i16`, etc.) |
| `stdbool.h` | Boolean type | Built-in (`bool`) |
| `string.h` | `strcmp`, `memset`, `strlen` | `core::str`, `heapless` |
| `stdarg.h` | Variadic printf | `core::fmt`, `ufmt`, `defmt` |

**No RTOS, no heap, no floating-point** - all favorable for Rust embedded.

---

## Embassy Compatibility Assessment

### What is Embassy?

Embassy is an async/await-based embedded framework for Rust. It provides:
- Cooperative task scheduling (no preemption)
- Interrupt-driven async I/O
- Timer-based delays without busy-waiting
- Hardware abstraction traits

### Compatibility Matrix

| Requirement | Embassy Support | Notes |
|-------------|-----------------|-------|
| RISC-V RV32 | ✅ Experimental | `embassy-riscv` crate exists |
| No heap | ✅ Full support | Embassy works with `#![no_std]` |
| Async I/O | ✅ Core strength | Perfect for interrupt-driven design |
| Single-threaded | ✅ Default model | Embassy executor is single-core |
| Real-time timing | ⚠️ Requires care | Hot paths may need inline asm |

### Challenges

| Challenge | Severity | Mitigation Strategy |
|-----------|----------|---------------------|
| **Custom PAC required** | HIGH | MicroBlaze V peripherals aren't in any existing crate. Must write `fluxripper-pac` from scratch using `platform.h` definitions. |
| **No HAL crate** | HIGH | No `embassy-microblaze`. Use `embedded-hal` traits with custom implementations. |
| **32KB code size** | MEDIUM | Enable LTO, `opt-level = "z"`, `panic = "abort"`, strip symbols. May need to move to HyperRAM execution. |
| **Flux capture timing** | MEDIUM | Keep timing-critical code in assembly or use `critical_section` for deterministic paths. |
| **Embassy RISC-V maturity** | MEDIUM | Experimental but functional. Fallback to bare-metal Rust if issues arise. |

---

## Porting Strategy

### Phase 0: Feasibility Spike (1-2 weeks)

**Goal**: Prove Rust can run on MicroBlaze V with Embassy.

**Tasks**:
1. Set up Rust toolchain for `riscv32imc-unknown-none-elf`
2. Create minimal `fluxripper-pac` crate with UART register definitions
3. Port startup code using `riscv-rt` crate
4. Implement basic UART driver
5. Print "Hello, FluxRipper!" over serial
6. Measure binary size (must fit in 32KB)

**Success Criteria**:
- Binary runs on actual SCU35 hardware
- Embassy executor initializes without panic
- UART output works
- Binary size < 28KB (leaves room for growth)

**If Phase 0 fails**: Reassess options (bare-metal Rust, stay with C, or HyperRAM execution).

### Phase 1: Core Drivers (2-3 weeks)

**Goal**: Replace C drivers with Rust equivalents.

**Tasks**:
1. UART driver with Embassy async read/write
2. Timer driver with `embassy::time::Timer`
3. RISC-V interrupt dispatch in Rust
4. Basic CLI loop (async readline)

**Deliverables**:
- `uart.rs` - Async serial I/O
- `timer.rs` - Delays, uptime tracking
- Interrupt handler framework

### Phase 2: HAL Layer (4-6 weeks)

**Goal**: Port hardware abstraction for all peripherals.

**FDC HAL** (`fdc.rs`):
- Register definitions from `platform.h`
- Drive state machine as Embassy task
- Flux capture with async stream

**HDD HAL** (`hdd.rs`):
- ST-506/ESDI register access
- Seek/read/write as async operations
- Geometry auto-detection

**Power HAL** (`power.rs`):
- Embassy I2C driver
- INA3221 async reads for 6 power channels

**MSC HAL** (`msc.rs`):
- USB endpoint configuration
- Media change interrupt handling

### Phase 3: Protocol & CLI (3-4 weeks)

**Goal**: Port high-level protocol handlers.

**CLI Framework** (`cli.rs`):
- Heapless command parser
- Async command dispatch
- History (optional)

**Protocol Handlers**:
- `handlers/scsi.rs` - USB MSC SCSI responder
- `handlers/raw.rs` - Flux streaming
- `handlers/diagnostics.rs` - Instrumentation access

### Phase 4: Integration & Optimization (2-3 weeks)

**Goal**: Achieve feature parity and optimize.

**Tasks**:
1. Side-by-side testing vs C firmware
2. Binary size optimization
3. Performance benchmarking
4. Documentation updates

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Binary exceeds 32KB BRAM | Medium | High | Aggressive LTO, `panic_halt`, strip debug. Fallback: execute from HyperRAM. |
| Embassy RISC-V bugs | Medium | Medium | Report upstream, use bare-metal Rust as fallback. |
| Flux capture timing jitter | Low | High | Keep ISR in assembly, use `critical_section`. |
| Development takes longer | High | Medium | Keep C firmware as production fallback. |
| Rust learning curve | Low | Low | Team familiar with embedded Rust. |

---

## Estimated Effort

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Phase 0: Feasibility | 1-2 weeks | Hello World on hardware |
| Phase 1: Core Drivers | 2-3 weeks | UART + Timer + interrupts |
| Phase 2: HAL Layer | 4-6 weeks | FDC + HDD + I2C + MSC |
| Phase 3: Protocol/CLI | 3-4 weeks | Full CLI + handlers |
| Phase 4: Integration | 2-3 weeks | Feature parity, optimized |
| **Total** | **12-18 weeks** | Production-ready Rust firmware |

---

## File Structure

```
soc/firmware-rs/
├── Cargo.toml                  # Workspace manifest
├── .cargo/
│   └── config.toml             # Target, linker, runner
├── memory.x                    # Linker script (from link.ld)
├── build.rs                    # Build script
│
├── src/
│   ├── main.rs                 # Entry point + Embassy executor
│   ├── uart.rs                 # UART driver (async)
│   ├── timer.rs                # Timer driver (async delays)
│   ├── fdc.rs                  # FDC HAL
│   ├── hdd.rs                  # HDD HAL
│   ├── power.rs                # I2C + INA3221
│   ├── msc.rs                  # USB MSC config
│   ├── cli.rs                  # CLI framework
│   └── handlers/
│       ├── mod.rs
│       ├── scsi.rs             # SCSI protocol
│       ├── raw.rs              # Raw flux capture
│       └── diagnostics.rs      # Instrumentation
│
└── fluxripper-pac/             # Peripheral Access Crate
    ├── Cargo.toml
    └── src/
        ├── lib.rs              # PAC root
        ├── uart.rs             # UART registers
        ├── timer.rs            # Timer registers
        ├── gpio.rs             # GPIO registers
        ├── fdc.rs              # FDC registers
        ├── hdd.rs              # HDD registers
        └── intc.rs             # Interrupt controller
```

---

## Key Dependencies

```toml
[dependencies]
embassy-executor = { version = "0.5", features = ["arch-riscv32"] }
embassy-time = { version = "0.3", features = ["tick-hz-1_000_000"] }
embassy-sync = "0.5"
embedded-hal = "1.0"
embedded-hal-async = "1.0"
critical-section = { version = "1.1", features = ["restore-state-bool"] }
heapless = "0.8"
ufmt = "0.2"                    # Lightweight formatting
riscv = "0.11"
riscv-rt = "0.12"

[profile.release]
opt-level = "z"                 # Optimize for size
lto = true                      # Link-time optimization
codegen-units = 1               # Better optimization
panic = "abort"                 # No unwinding
strip = true                    # Remove symbols
```

---

## C-to-Rust Translation Patterns

### Register Access

**C (current)**:
```c
#define UART_TX_FIFO (*(volatile uint32_t *)(UART_BASE + 0x04))
UART_TX_FIFO = (uint32_t)c;
```

**Rust (target)**:
```rust
use volatile_register::RW;

#[repr(C)]
struct UartRegs {
    rx_fifo: RW<u32>,
    tx_fifo: RW<u32>,
    status: RW<u32>,
    control: RW<u32>,
}

impl Uart {
    fn write_byte(&mut self, c: u8) {
        unsafe { self.regs.tx_fifo.write(c as u32) };
    }
}
```

### Interrupt Handling

**C (current)**:
```c
void external_interrupt_handler(void) {
    if (pending & IRQ_UART) { uart_isr(); }
    if (pending & IRQ_TIMER) { timer_isr(); }
}
```

**Rust (target)**:
```rust
#[interrupt]
fn EXTERNAL() {
    let pending = INTC.pending();
    if pending.contains(Interrupt::UART) {
        UART_SIGNAL.signal(());
    }
    if pending.contains(Interrupt::TIMER) {
        TIMER_SIGNAL.signal(());
    }
}

#[embassy_executor::task]
async fn uart_task() {
    loop {
        UART_SIGNAL.wait().await;
        // Handle UART interrupt
    }
}
```

### State Machines

**C (current)**: Switch statements with explicit state variables

**Rust (target)**: Async/await with natural control flow
```rust
async fn seek_and_read(&mut self, cylinder: u16, head: u8, sector: u8) -> Result<[u8; 512], Error> {
    self.seek(cylinder).await?;      // Async seek with settle time
    self.select_head(head);
    self.wait_for_index().await;     // Wait for index pulse
    self.read_sector(sector).await   // Read with timeout
}
```

---

## Recommendation

Given the project goals (full production port, no time pressure, hardware available):

**Start with Phase 0 feasibility spike** targeting Embassy directly.

### Guiding Principles

1. **Keep C firmware** as reference and fallback throughout development
2. **Prioritize Rust idioms** - don't do a line-by-line translation
3. **Use Embassy from the start** - the async model fits this project perfectly
4. **Test on hardware early and often** - catch issues before they compound

### First Milestone

Get UART "Hello World" running on SCU35 with Embassy executor.

This validates:
- Rust toolchain for RV32IMC works
- Binary fits in 32KB BRAM
- Embassy executor runs on MicroBlaze V
- Interrupt dispatch functional

If this succeeds, the full port is highly likely to succeed.

---

## Advanced: FPGA-Accelerated Executor

An intriguing enhancement would be to offload Embassy executor functions to dedicated FPGA logic, creating a hybrid hardware/software async runtime.

### Concept

Instead of the software executor polling and dispatching tasks, FPGA modules handle:

| Function | Software (Embassy) | Hardware (FPGA) |
|----------|-------------------|-----------------|
| Event detection | ISR + signal | Dedicated comparators |
| Timer management | Sorted queue in RAM | Hardware timer array |
| Task wakeup | Polling ready queue | Hardware priority encoder |
| Priority scheduling | O(n) scan | O(1) combinational logic |

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FPGA Logic                                   │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                   Hardware Executor Core                        ││
│  │  ┌───────────────┐  ┌──────────────┐  ┌───────────────────────┐ ││
│  │  │ Timer Array   │  │ Event Queue  │  │ Priority Encoder      │ ││
│  │  │ (16 channels) │  │ (32 entries) │  │ (8 priority levels)   │ ││
│  │  │               │  │              │  │                       │ ││
│  │  │ Compare vs    │  │ FIFO with    │  │ Bitmap → highest set  │ ││
│  │  │ free-running  │  │ event type   │  │ bit in O(1)           │ ││
│  │  │ counter       │  │ + task ID    │  │                       │ ││
│  │  └───────┬───────┘  └──────┬───────┘  └───────────┬───────────┘ ││
│  │          │                 │                      │             ││
│  │          └────────────┬────┴──────────────────────┘             ││
│  │                       ▼                                         ││
│  │              ┌────────────────┐                                 ││
│  │              │ Task Ready Reg │◄── IRQ to CPU when task ready   ││
│  │              │ (bitmap)       │                                 ││
│  │              └────────────────┘                                 ││
│  └─────────────────────────────────────────────────────────────────┘│
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                   MicroBlaze V (Rust)                           ││
│  │                                                                 ││
│  │   loop {                                                        ││
│  │       let task_id = HW_EXECUTOR.next_ready();  // One read!     ││
│  │       tasks[task_id].poll();                                    ││
│  │   }                                                             ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

### FPGA Modules to Implement

#### 1. Hardware Timer Array (`hw_timer_array.v`)

```verilog
module hw_timer_array #(
    parameter NUM_TIMERS = 16,
    parameter COUNTER_WIDTH = 64
)(
    input  wire        clk,
    input  wire        reset_n,

    // Free-running counter
    output reg [COUNTER_WIDTH-1:0] now,

    // Timer programming interface
    input  wire [3:0]  timer_sel,
    input  wire [COUNTER_WIDTH-1:0] timer_deadline,
    input  wire        timer_arm,
    input  wire        timer_cancel,

    // Expiry outputs
    output wire [NUM_TIMERS-1:0] timer_expired,  // Bitmap of expired
    output wire        any_expired               // OR of all
);
```

**Benefits**:
- No software overhead for timer maintenance
- Nanosecond precision without polling
- 16 concurrent timers in ~200 LUTs

#### 2. Event Queue (`hw_event_queue.v`)

```verilog
module hw_event_queue #(
    parameter DEPTH = 32,
    parameter EVENT_WIDTH = 16  // Event type + task ID
)(
    input  wire        clk,
    input  wire        reset_n,

    // Push interface (from peripheral interrupts)
    input  wire [EVENT_WIDTH-1:0] event_data,
    input  wire        event_valid,
    output wire        event_ready,

    // Pop interface (to CPU)
    output wire [EVENT_WIDTH-1:0] head_data,
    output wire        head_valid,
    input  wire        head_pop,

    // Status
    output wire [5:0]  queue_depth,
    output wire        queue_full,
    output wire        queue_empty
);
```

**Benefits**:
- Interrupt coalescing - batch events for CPU
- No lost interrupts during handler execution
- Hardware ordering guarantees

#### 3. Priority Scheduler (`hw_priority_sched.v`)

```verilog
module hw_priority_sched #(
    parameter NUM_TASKS = 32,
    parameter NUM_PRIORITIES = 8
)(
    input  wire        clk,
    input  wire        reset_n,

    // Task ready bitmap (one bit per task)
    input  wire [NUM_TASKS-1:0] task_ready,

    // Priority assignment (set once at task creation)
    input  wire [4:0]  task_id,
    input  wire [2:0]  task_priority,
    input  wire        priority_set,

    // Next task to run (highest priority ready task)
    output wire [4:0]  next_task_id,
    output wire        next_task_valid
);

    // Priority encoder finds highest-priority ready task in O(1)
    // Using priority bitmaps - one per level
```

**Benefits**:
- O(1) task selection regardless of task count
- No software priority queue overhead
- Deterministic scheduling latency

### Integration with Embassy

The Rust executor becomes minimal:

```rust
#[embassy_executor::main]
async fn main(spawner: Spawner) {
    // Embassy tasks register with hardware scheduler
    spawner.spawn(fdc_task()).unwrap();
    spawner.spawn(hdd_task()).unwrap();
    spawner.spawn(usb_task()).unwrap();

    // Main loop is trivial - hardware does the work
    loop {
        // Hardware tells us which task is ready
        let task_id = HW_SCHEDULER.wait_for_ready().await;

        // Poll the task (Embassy internal)
        TASK_TABLE[task_id].poll();
    }
}

// Timer registration goes to hardware
impl Timer {
    pub async fn after(duration: Duration) {
        let deadline = HW_TIMER.now() + duration.as_ticks();
        HW_TIMER.arm(current_task_id(), deadline);

        // Wakeup comes from hardware interrupt
        poll_fn(|cx| {
            if HW_TIMER.expired(current_task_id()) {
                Poll::Ready(())
            } else {
                cx.waker().wake_by_ref();
                Poll::Pending
            }
        }).await
    }
}
```

### Resource Estimate

| Module | LUTs | FFs | BRAM | Notes |
|--------|------|-----|------|-------|
| Timer Array (16ch, 64-bit) | 400 | 1,100 | 0 | 16 comparators |
| Event Queue (32 entries) | 200 | 600 | 1 | Small FIFO |
| Priority Scheduler (32 tasks) | 150 | 100 | 0 | Bitmap + encoder |
| Glue logic | 100 | 50 | 0 | |
| **Total** | **~850** | **~1,850** | **~1** | <3% of SCU35 |

### Benefits Summary

| Metric | Software Executor | Hardware-Accelerated |
|--------|-------------------|---------------------|
| Task wakeup latency | 10-50 cycles | 1-2 cycles |
| Timer precision | ~1 µs | ~10 ns |
| Priority scheduling | O(n) | O(1) |
| Event handling | ISR + queue ops | Zero-copy FIFO |
| CPU overhead | ~5-10% | ~1% |
| Determinism | Good | Excellent |

### Implementation Phases

**Phase A**: Implement `hw_timer_array.v` - most impactful single module
**Phase B**: Add `hw_event_queue.v` - decouple interrupts from handlers
**Phase C**: Add `hw_priority_sched.v` - only if >8 concurrent tasks

This approach turns the FluxRipper into a **hardware-accelerated async runtime** - potentially the first of its kind for embedded Rust!

---

## Advanced: Hardware HAL Layer

Taking the FPGA acceleration concept further, we can offload entire HAL operations to dedicated FPGA state machines. Instead of the CPU bit-banging I2C, SPI, or managing UART byte-by-byte, the FPGA handles complete transactions autonomously.

### Traditional vs Hardware HAL

| Approach | How it Works | CPU Involvement |
|----------|--------------|-----------------|
| **Software HAL** | CPU controls every clock edge, every state transition | 100% - busy-wait or per-byte ISR |
| **Hardware HAL** | CPU issues command, FPGA executes entire operation | ~5% - setup + completion ISR |

### Command/Response Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Hardware HAL Architecture                          │
│                                                                             │
│  ┌─────────────────────┐                    ┌─────────────────────────────┐ │
│  │    MicroBlaze V     │                    │        FPGA Logic           │ │
│  │       (Rust)        │                    │                             │ │
│  │                     │    Command FIFO    │  ┌─────────────────────────┐│ │
│  │  1. Write command   │───────────────────►│  │    I2C State Machine    ││ │
│  │  2. Trigger start   │                    │  │                         ││ │
│  │  3. Wait for IRQ    │                    │  │ START → ADDR → ACK →    ││ │
│  │  4. Read results    │◄───────────────────│  │ DATA → ACK → ... → STOP ││ │
│  │                     │    Response FIFO   │  └─────────────────────────┘│ │
│  └─────────────────────┘                    │                             │ │
│                                             │  ┌─────────────────────────┐│ │
│                                             │  │   SPI State Machine     ││ │
│                                             │  │                         ││ │
│                                             │  │ CS_LOW → CLK+DATA →     ││ │
│                                             │  │ ... → CS_HIGH           ││ │
│                                             │  └─────────────────────────┘│ │
│                                             └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Proposed FPGA Modules

#### 1. Hardware I2C Master (`hw_i2c_master.v`)

A complete I2C master that handles entire read/write transactions autonomously.

```verilog
module hw_i2c_master #(
    parameter CLK_FREQ   = 100_000_000,  // System clock
    parameter I2C_FREQ   = 400_000,      // I2C clock (100K/400K/1M)
    parameter BUFFER_LEN = 32            // Max bytes per transaction
)(
    input  wire        clk,
    input  wire        reset_n,

    // I2C pins
    inout  wire        sda,
    inout  wire        scl,

    // Command interface (from CPU)
    input  wire [6:0]  slave_addr,       // 7-bit I2C address
    input  wire [7:0]  reg_addr,         // Register to access
    input  wire [4:0]  byte_count,       // Bytes to read/write (1-32)
    input  wire        is_write,         // 1=write, 0=read
    input  wire        start,            // Trigger transaction

    // Write data buffer
    input  wire [7:0]  tx_data,
    input  wire        tx_write,
    output wire        tx_full,

    // Read data buffer
    output wire [7:0]  rx_data,
    output wire        rx_valid,
    input  wire        rx_read,
    output wire        rx_empty,

    // Status
    output reg         busy,
    output reg         complete,         // Pulse on completion
    output reg         error,            // NACK received
    output reg [2:0]   error_code        // 0=OK, 1=NACK_ADDR, 2=NACK_DATA, 3=ARB_LOST
);
    // State machine handles:
    // - START condition generation
    // - Address byte + R/W bit transmission
    // - ACK/NACK detection
    // - Data transmission (write) or reception (read)
    // - Repeated START for read-after-write
    // - STOP condition generation
    // - Clock stretching support
```

**Use Case**: Reading INA3221 power monitor (6 bytes from 3 channels):

```rust
// Software HAL: ~600 CPU cycles, multiple ISRs
// Hardware HAL: ~20 CPU cycles (setup only)

pub async fn read_power_channels(&self) -> Result<[PowerReading; 3], Error> {
    // Configure command
    HW_I2C.slave_addr.write(INA3221_ADDR);
    HW_I2C.reg_addr.write(INA3221_SHUNT_CH1);
    HW_I2C.byte_count.write(6);  // 2 bytes × 3 channels
    HW_I2C.is_write.write(false);

    // Fire and forget - FPGA handles everything
    HW_I2C.start.trigger();

    // Wait for completion interrupt
    I2C_COMPLETE_SIGNAL.wait().await;

    // Read results from hardware buffer
    let mut data = [0u8; 6];
    for i in 0..6 {
        data[i] = HW_I2C.rx_data.read();
    }

    Ok(parse_power_readings(&data))
}
```

#### 2. Hardware UART Buffer (`hw_uart_buffer.v`)

Deep FIFOs with line-oriented buffering for CLI applications.

```verilog
module hw_uart_buffer #(
    parameter RX_DEPTH = 1024,           // 1KB RX buffer
    parameter TX_DEPTH = 1024,           // 1KB TX buffer
    parameter BAUD_RATE = 115200,
    parameter CLK_FREQ = 100_000_000
)(
    input  wire        clk,
    input  wire        reset_n,

    // UART pins
    input  wire        uart_rx,
    output wire        uart_tx,

    // RX interface
    output wire [7:0]  rx_data,
    output wire        rx_valid,
    input  wire        rx_read,
    output wire [10:0] rx_level,         // Bytes in RX FIFO

    // Line detection (for CLI)
    output reg         rx_line_ready,    // Full line received (CR or LF)
    output reg [10:0]  rx_line_length,   // Length of pending line

    // TX interface
    input  wire [7:0]  tx_data,
    input  wire        tx_write,
    output wire        tx_full,
    output wire [10:0] tx_level,         // Bytes in TX FIFO

    // DMA interface (for bulk transfer)
    input  wire [31:0] dma_src_addr,     // Source address in memory
    input  wire [10:0] dma_length,       // Bytes to transfer
    input  wire        dma_start,        // Start DMA TX
    output reg         dma_complete,

    // Configuration
    input  wire [1:0]  parity_mode,      // 0=none, 1=odd, 2=even
    input  wire        flow_control      // RTS/CTS enable
);
```

**Benefits**:
- **No lost characters** during command processing (1KB buffer vs 16-byte FIFO)
- **Single interrupt per line** instead of per character
- **DMA support** for bulk output (e.g., hex dumps)

```rust
// CLI readline becomes trivial
pub async fn readline(&self, buf: &mut [u8]) -> usize {
    // Wait for hardware to detect CR/LF
    UART_LINE_SIGNAL.wait().await;

    let len = HW_UART.rx_line_length.read() as usize;
    for i in 0..len.min(buf.len()) {
        buf[i] = HW_UART.rx_data.read();
    }
    len
}

// Bulk output uses DMA
pub async fn print_hex_dump(&self, addr: *const u8, len: usize) {
    HW_UART.dma_src_addr.write(addr as u32);
    HW_UART.dma_length.write(len as u16);
    HW_UART.dma_start.trigger();

    UART_DMA_COMPLETE_SIGNAL.wait().await;
}
```

#### 3. Hardware SPI Controller (`hw_spi_controller.v`)

Multi-byte SPI with automatic chip select management.

```verilog
module hw_spi_controller #(
    parameter MAX_BURST = 64,            // Max bytes per transfer
    parameter CLK_DIV_WIDTH = 8          // Clock divider bits
)(
    input  wire        clk,
    input  wire        reset_n,

    // SPI pins
    output wire        spi_clk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire [3:0]  spi_cs_n,         // Up to 4 chip selects

    // Configuration
    input  wire [1:0]  cs_select,        // Which CS to use
    input  wire        cpol,             // Clock polarity
    input  wire        cpha,             // Clock phase
    input  wire [CLK_DIV_WIDTH-1:0] clk_div,  // Clock divider

    // Transfer interface
    input  wire [5:0]  byte_count,       // Bytes to transfer (1-64)
    input  wire        start,            // Begin transfer

    // TX FIFO
    input  wire [7:0]  tx_data,
    input  wire        tx_write,
    output wire        tx_full,

    // RX FIFO (for simultaneous read)
    output wire [7:0]  rx_data,
    output wire        rx_valid,
    input  wire        rx_read,

    // Status
    output reg         busy,
    output reg         complete
);
    // Handles:
    // - Automatic CS assertion before first bit
    // - Configurable clock polarity and phase
    // - Back-to-back byte transfers without CS gaps
    // - Automatic CS deassertion after last byte
```

**Use Case**: Reading SD card sector (512 bytes):

```rust
pub async fn read_sector(&self, sector: u32) -> Result<[u8; 512], Error> {
    // Send CMD17 (READ_SINGLE_BLOCK)
    let cmd = [0x51, (sector >> 24) as u8, (sector >> 16) as u8,
               (sector >> 8) as u8, sector as u8, 0xFF];

    for &b in &cmd {
        HW_SPI.tx_data.write(b);
    }
    HW_SPI.byte_count.write(6);
    HW_SPI.start.trigger();
    SPI_COMPLETE_SIGNAL.wait().await;

    // Wait for data token, then read 512 bytes
    HW_SPI.byte_count.write(64);  // 8 bursts of 64 bytes
    let mut buf = [0u8; 512];

    for chunk in buf.chunks_mut(64) {
        HW_SPI.start.trigger();
        SPI_COMPLETE_SIGNAL.wait().await;
        for b in chunk {
            *b = HW_SPI.rx_data.read();
        }
    }

    Ok(buf)
}
```

#### 4. Hardware DMA Engine (`hw_dma_engine.v`)

General-purpose DMA for memory-to-peripheral and peripheral-to-memory transfers.

```verilog
module hw_dma_engine #(
    parameter NUM_CHANNELS = 4,
    parameter DESC_DEPTH = 8             // Scatter-gather descriptors per channel
)(
    input  wire        clk,
    input  wire        reset_n,

    // AXI-Lite master interface (memory access)
    // ... AXI signals ...

    // Channel configuration
    input  wire [1:0]  ch_select,
    input  wire [31:0] src_addr,
    input  wire [31:0] dst_addr,
    input  wire [15:0] length,           // Bytes to transfer
    input  wire        src_incr,         // Increment source address
    input  wire        dst_incr,         // Increment destination address
    input  wire        start,

    // Scatter-gather (optional)
    input  wire [31:0] desc_addr,        // Descriptor chain base
    input  wire        sg_mode,          // Use scatter-gather

    // Status
    output wire [NUM_CHANNELS-1:0] busy,
    output wire [NUM_CHANNELS-1:0] complete,
    output wire [NUM_CHANNELS-1:0] error
);
```

**Use Case**: HDD sector read to track buffer:

```rust
// Move 512 bytes from HDD data register to track buffer
// without any CPU involvement

pub async fn dma_read_sector(&self, buffer_offset: usize) {
    HW_DMA.src_addr.write(HDD_DATA_REG);  // Fixed source
    HW_DMA.dst_addr.write(TRACK_BUFFER + buffer_offset);
    HW_DMA.length.write(512);
    HW_DMA.src_incr.write(false);  // Same register
    HW_DMA.dst_incr.write(true);   // Sequential memory
    HW_DMA.start.trigger();

    DMA_COMPLETE_SIGNAL.wait().await;
}
```

### Performance Comparison

| Operation | Software HAL | Hardware HAL | Speedup |
|-----------|-------------|--------------|---------|
| I2C read 6 bytes (400 kHz) | ~600 cycles | ~20 cycles | 30× |
| I2C write 2 bytes | ~300 cycles | ~15 cycles | 20× |
| UART readline (80 chars) | 80 ISRs | 1 ISR | 80× less overhead |
| SPI transfer 64 bytes | 64 ISRs or 640 cycles | ~30 cycles | 20× |
| DMA 512 bytes | ~1,000 cycles | ~10 cycles | 100× |

### Resource Estimate

| Module | LUTs | FFs | BRAM | Notes |
|--------|------|-----|------|-------|
| `hw_i2c_master` | 400 | 300 | 0 | 32-byte buffer |
| `hw_uart_buffer` | 200 | 100 | 2 | 1KB RX + 1KB TX |
| `hw_spi_controller` | 300 | 200 | 0 | 64-byte FIFO |
| `hw_dma_engine` (4ch) | 600 | 400 | 1 | Descriptor storage |
| **Total Hardware HAL** | **~1,500** | **~1,000** | **~3** | <5% of SCU35 |

### Combined with FPGA Executor

When paired with the hardware-accelerated executor from the previous section:

| Component | Resources |
|-----------|-----------|
| FPGA Executor (timer, queue, scheduler) | 850 LUTs, 1,850 FFs, 1 BRAM |
| Hardware HAL (I2C, UART, SPI, DMA) | 1,500 LUTs, 1,000 FFs, 3 BRAM |
| **Total FPGA Acceleration** | **~2,350 LUTs, ~2,850 FFs, ~4 BRAM** |

This represents approximately **7%** of the SCU35's logic resources - a small price for:
- Near-zero CPU overhead for peripheral operations
- Deterministic, jitter-free I/O timing
- Ability to handle concurrent peripheral operations while CPU sleeps
- Perfect match for Embassy's async/await model

### File Structure Addition

```
rtl/
├── ... (existing)
└── hw_hal/                      # Hardware HAL modules
    ├── hw_i2c_master.v
    ├── hw_uart_buffer.v
    ├── hw_spi_controller.v
    ├── hw_dma_engine.v
    └── hw_hal_top.v             # Integration wrapper
```

---

## References

- [Embassy Documentation](https://embassy.dev/book/)
- [Embassy GitHub](https://github.com/embassy-rs/embassy)
- [Rust Embedded Book](https://docs.rust-embedded.org/book/)
- [RISC-V Rust Guide](https://docs.rust-embedded.org/discovery/microbit/03-setup/index.html)
- [svd2rust](https://docs.rs/svd2rust/) - Generate PAC from SVD files
