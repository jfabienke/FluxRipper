#!/usr/bin/env python3
"""
FluxRipper Hardware-in-the-Loop Tests

Comprehensive test suite for verifying hardware functionality
via the debug subsystem.

Created: 2025-12-07 16:35
License: BSD-3-Clause
"""

import time
import sys
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from fluxripper_dev import (
    TestCase, TestResult, TestRunner, CDCConsole, Config
)

#==============================================================================
# Layer 2: Memory Tests
#==============================================================================

def test_bram_basic(runner: TestRunner) -> TestResult:
    """Basic BRAM read/write at multiple addresses."""
    test_addrs = [0x40000000, 0x40001000, 0x40002000, 0x4000F000]
    test_value = 0xA5A5A5A5

    for addr in test_addrs:
        if not runner.console.write_memory(addr, test_value):
            return TestResult.FAIL
        if runner.console.read_memory(addr) != test_value:
            return TestResult.FAIL

    return TestResult.PASS


def test_bram_address_lines(runner: TestRunner) -> TestResult:
    """Verify all address lines work (no stuck/shorted lines)."""
    base = 0x40000000

    # Write unique pattern to power-of-2 offsets
    for i in range(14):  # 64KB BRAM = 2^14 words
        addr = base + (1 << i) * 4
        if not runner.console.write_memory(addr, 1 << i):
            return TestResult.FAIL

    # Read back and verify
    for i in range(14):
        addr = base + (1 << i) * 4
        value = runner.console.read_memory(addr)
        if value != (1 << i):
            print(f"Address line test failed at bit {i}: "
                  f"addr={addr:08X}, expected={1<<i:08X}, got={value:08X}")
            return TestResult.FAIL

    return TestResult.PASS


def test_bram_data_lines(runner: TestRunner) -> TestResult:
    """Verify all data lines work."""
    addr = 0x40000100

    # Walking ones
    for bit in range(32):
        pattern = 1 << bit
        if not runner.console.write_memory(addr, pattern):
            return TestResult.FAIL
        if runner.console.read_memory(addr) != pattern:
            print(f"Data line {bit} stuck/shorted")
            return TestResult.FAIL

    # Walking zeros
    for bit in range(32):
        pattern = ~(1 << bit) & 0xFFFFFFFF
        if not runner.console.write_memory(addr, pattern):
            return TestResult.FAIL
        if runner.console.read_memory(addr) != pattern:
            return TestResult.FAIL

    return TestResult.PASS


def test_bram_retention(runner: TestRunner) -> TestResult:
    """Verify BRAM retains data over time."""
    patterns = [
        (0x40000200, 0x12345678),
        (0x40000204, 0x87654321),
        (0x40000208, 0xAAAA5555),
        (0x4000020C, 0x5555AAAA),
    ]

    # Write patterns
    for addr, pattern in patterns:
        runner.console.write_memory(addr, pattern)

    # Wait
    time.sleep(0.5)

    # Verify
    for addr, pattern in patterns:
        if runner.console.read_memory(addr) != pattern:
            return TestResult.FAIL

    return TestResult.PASS


#==============================================================================
# Layer 3: GPIO Tests
#==============================================================================

def test_gpio_loopback(runner: TestRunner) -> TestResult:
    """Test GPIO output-to-input loopback (requires loopback jumper)."""
    # This test requires physical loopback connection
    # Skip if not configured
    return TestResult.SKIP


def test_gpio_debug_led(runner: TestRunner) -> TestResult:
    """Toggle debug LEDs."""
    gpio_out = 0x40010004

    # Toggle each LED
    for led in range(3):
        # LED on
        runner.console.write_memory(gpio_out, 1 << (led + 8))
        time.sleep(0.1)
        # LED off
        runner.console.write_memory(gpio_out, 0)
        time.sleep(0.1)

    return TestResult.PASS


#==============================================================================
# Layer 4: Clock Tests
#==============================================================================

def test_clock_frequencies(runner: TestRunner) -> TestResult:
    """Verify clock frequencies are within tolerance."""
    expected = [
        (0x40030000, 6000000, 0.001),   # 60 MHz ±0.1%
        (0x40030004, 10000000, 0.001),  # 100 MHz ±0.1%
        (0x40030008, 20000000, 0.001),  # 200 MHz ±0.1%
        (0x4003000C, 30000000, 0.001),  # 300 MHz ±0.1%
    ]

    for addr, nominal, tolerance in expected:
        count = runner.console.read_memory(addr)
        if count is None:
            return TestResult.ERROR

        deviation = abs(count - nominal) / nominal
        if deviation > tolerance:
            print(f"Clock at {addr:08X}: expected {nominal}, got {count} "
                  f"(deviation {deviation*100:.3f}%)")
            return TestResult.FAIL

    return TestResult.PASS


def test_pll_stability(runner: TestRunner) -> TestResult:
    """Check PLLs remain locked over time."""
    pll_status_addr = 0x40020000

    for _ in range(10):
        status = runner.console.read_memory(pll_status_addr)
        if (status & 0x1F) != 0x1F:
            return TestResult.FAIL
        time.sleep(0.1)

    return TestResult.PASS


#==============================================================================
# Layer 5: USB PHY Tests
#==============================================================================

def test_ulpi_registers(runner: TestRunner) -> TestResult:
    """Read ULPI PHY identification registers."""
    # These are the expected values for USB3320
    expected = [
        (0x00, 0x24),  # Vendor ID low
        (0x01, 0x04),  # Vendor ID high
        (0x02, 0x04),  # Product ID low (USB3320)
    ]

    for reg, expected_val in expected:
        # Write register address
        runner.console.write_memory(0x44000000, reg)
        time.sleep(0.01)
        # Read result
        value = runner.console.read_memory(0x44000004)
        if value != expected_val:
            print(f"ULPI reg {reg:02X}: expected {expected_val:02X}, got {value:02X}")
            return TestResult.FAIL

    return TestResult.PASS


#==============================================================================
# Layer 6: USB Enumeration Tests
#==============================================================================

def test_usb_speed(runner: TestRunner) -> TestResult:
    """Verify High-Speed mode achieved."""
    state = runner.console.read_memory(0x44000020)
    if not (state & 0x08):  # HS bit
        return TestResult.FAIL
    return TestResult.PASS


def test_usb_address(runner: TestRunner) -> TestResult:
    """Verify USB address was assigned."""
    addr = runner.console.read_memory(0x44000024)
    if addr == 0:
        return TestResult.FAIL
    return TestResult.PASS


def test_usb_configuration(runner: TestRunner) -> TestResult:
    """Verify device is configured."""
    state = runner.console.read_memory(0x44000020)
    if (state & 0x07) != 0x05:  # Configured state
        return TestResult.FAIL
    return TestResult.PASS


#==============================================================================
# Layer 7: Debug Subsystem Tests
#==============================================================================

def test_debug_idcode(runner: TestRunner) -> TestResult:
    """Verify debug IDCODE."""
    idcode = runner.console.read_memory(0x44A80070)
    if idcode != 0xFB010001:
        print(f"Wrong IDCODE: {idcode:08X}")
        return TestResult.FAIL
    return TestResult.PASS


def test_debug_uptime(runner: TestRunner) -> TestResult:
    """Verify uptime counter increments."""
    uptime1 = runner.console.read_memory(0x44A80064)
    time.sleep(1.1)
    uptime2 = runner.console.read_memory(0x44A80064)

    if uptime2 <= uptime1:
        return TestResult.FAIL
    return TestResult.PASS


def test_signal_tap_all_groups(runner: TestRunner) -> TestResult:
    """Read all signal tap groups."""
    for group in range(4):
        value = runner.console.probe(group)
        if value is None:
            print(f"Failed to read probe group {group}")
            return TestResult.FAIL
    return TestResult.PASS


def test_trace_capture(runner: TestRunner) -> TestResult:
    """Test trace capture and readback."""
    # Clear and start
    runner.console.command("dbg trace clear")
    runner.console.command("dbg trace start")

    # Generate some activity
    for _ in range(5):
        runner.console.read_memory(0x40000000)

    # Stop and check
    entries = runner.console.trace_stop()

    if len(entries) < 3:
        print(f"Expected trace entries, got {len(entries)}")
        return TestResult.FAIL

    return TestResult.PASS


def test_cpu_halt_resume(runner: TestRunner) -> TestResult:
    """Test CPU halt and resume."""
    # Halt
    if not runner.console.cpu_halt():
        return TestResult.FAIL

    # Verify halted (check status)
    status = runner.console.read_memory(0x44A80048)
    if not (status & 0x01):  # Halted bit
        return TestResult.FAIL

    # Resume
    if not runner.console.cpu_run():
        return TestResult.FAIL

    time.sleep(0.1)

    # Verify running
    status = runner.console.read_memory(0x44A80048)
    if not (status & 0x02):  # Running bit
        return TestResult.FAIL

    return TestResult.PASS


#==============================================================================
# Layer 8: Subsystem Tests
#==============================================================================

def test_fdc_registers(runner: TestRunner) -> TestResult:
    """Verify FDC register access."""
    # Read status register
    status = runner.console.read_memory(0x44100000)
    if status is None:
        return TestResult.ERROR

    # Write/read track register
    runner.console.write_memory(0x44100008, 42)
    if runner.console.read_memory(0x44100008) != 42:
        return TestResult.FAIL

    return TestResult.PASS


def test_hdd_registers(runner: TestRunner) -> TestResult:
    """Verify HDD register access."""
    # Read status register
    status = runner.console.read_memory(0x44200000)
    if status is None:
        return TestResult.ERROR

    # Write/read cylinder register
    runner.console.write_memory(0x44200008, 100)
    if runner.console.read_memory(0x44200008) != 100:
        return TestResult.FAIL

    return TestResult.PASS


def test_power_monitoring(runner: TestRunner) -> TestResult:
    """Read power monitoring registers."""
    response = runner.console.command("power status")
    if "USB-C" not in response and "ATX" not in response:
        return TestResult.FAIL
    return TestResult.PASS


#==============================================================================
# Stress Tests
#==============================================================================

def test_memory_stress(runner: TestRunner) -> TestResult:
    """Stress test memory with rapid access."""
    addr = 0x40000000
    iterations = 100

    for i in range(iterations):
        pattern = (i * 0x01010101) & 0xFFFFFFFF
        if not runner.console.write_memory(addr + (i % 256) * 4, pattern):
            return TestResult.FAIL
        if runner.console.read_memory(addr + (i % 256) * 4) != pattern:
            return TestResult.FAIL

    return TestResult.PASS


def test_console_stress(runner: TestRunner) -> TestResult:
    """Stress test console with rapid commands."""
    for _ in range(50):
        response = runner.console.command("dbg id")
        if "FB010001" not in response:
            return TestResult.FAIL

    return TestResult.PASS


#==============================================================================
# Test Suite Definition
#==============================================================================

ALL_TESTS = [
    # Layer 2: Memory
    TestCase("bram_basic", "Basic BRAM access", 2, test_bram_basic, 2.0),
    TestCase("bram_addr_lines", "BRAM address lines", 2, test_bram_address_lines, 5.0),
    TestCase("bram_data_lines", "BRAM data lines", 2, test_bram_data_lines, 3.0),
    TestCase("bram_retention", "BRAM data retention", 2, test_bram_retention, 2.0),

    # Layer 3: GPIO
    TestCase("gpio_led", "Debug LED toggle", 3, test_gpio_debug_led, 2.0),
    TestCase("gpio_loopback", "GPIO loopback", 3, test_gpio_loopback, 1.0),

    # Layer 4: Clocks
    TestCase("clock_freq", "Clock frequencies", 4, test_clock_frequencies, 2.0),
    TestCase("pll_stable", "PLL stability", 4, test_pll_stability, 2.0),

    # Layer 5: USB PHY
    TestCase("ulpi_regs", "ULPI registers", 5, test_ulpi_registers, 2.0),

    # Layer 6: USB Enumeration
    TestCase("usb_speed", "USB High-Speed", 6, test_usb_speed, 1.0),
    TestCase("usb_addr", "USB address", 6, test_usb_address, 1.0),
    TestCase("usb_config", "USB configured", 6, test_usb_configuration, 1.0),

    # Layer 7: Debug
    TestCase("dbg_idcode", "Debug IDCODE", 7, test_debug_idcode, 1.0),
    TestCase("dbg_uptime", "Uptime counter", 7, test_debug_uptime, 2.0),
    TestCase("dbg_probes", "Signal tap groups", 7, test_signal_tap_all_groups, 2.0),
    TestCase("dbg_trace", "Trace capture", 7, test_trace_capture, 3.0),
    TestCase("dbg_cpu", "CPU halt/resume", 7, test_cpu_halt_resume, 2.0),

    # Layer 8: Subsystems
    TestCase("fdc_regs", "FDC registers", 8, test_fdc_registers, 2.0),
    TestCase("hdd_regs", "HDD registers", 8, test_hdd_registers, 2.0),
    TestCase("power_mon", "Power monitoring", 8, test_power_monitoring, 2.0),

    # Stress tests
    TestCase("stress_mem", "Memory stress", 7, test_memory_stress, 10.0),
    TestCase("stress_console", "Console stress", 7, test_console_stress, 10.0),
]


def register_all_tests(runner: TestRunner):
    """Register all hardware tests with the runner."""
    for test in ALL_TESTS:
        runner.register(test)


#==============================================================================
# Standalone Test Runner
#==============================================================================

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="FluxRipper Hardware Tests")
    parser.add_argument("--port", default="/dev/ttyACM0", help="CDC port")
    parser.add_argument("--test", help="Run specific test by name")
    parser.add_argument("--layer", type=int, default=0, help="Minimum layer")
    parser.add_argument("--stress", action="store_true", help="Include stress tests")

    args = parser.parse_args()

    # Connect
    config = Config()
    config.cdc_port = args.port

    console = CDCConsole(args.port)
    if not console.connect():
        print("Failed to connect")
        sys.exit(1)

    # Create runner
    runner = TestRunner(console, config)
    register_all_tests(runner)

    # Filter tests
    if args.test:
        runner.tests = [t for t in runner.tests if t.name == args.test]
    if not args.stress:
        runner.tests = [t for t in runner.tests if not t.name.startswith("stress")]

    # Run
    try:
        results = runner.run_all(min_layer=args.layer)
        failed = sum(1 for r in results.values() if r == TestResult.FAIL)
        sys.exit(0 if failed == 0 else 1)
    finally:
        console.disconnect()
