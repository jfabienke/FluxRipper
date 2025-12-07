#!/usr/bin/env python3
"""
FluxRipper Development Loop Controller

Provides tight-loop development workflow with hardware-in-the-loop testing.
Supports hot firmware reload, automated testing, and continuous verification.

Created: 2025-12-07 16:30
License: BSD-3-Clause
"""

import serial
import subprocess
import time
import os
import sys
import argparse
import hashlib
import json
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Callable
from dataclasses import dataclass
from enum import Enum
import threading
import queue

#==============================================================================
# Configuration
#==============================================================================

@dataclass
class Config:
    """Development environment configuration."""
    project_root: Path = Path(__file__).parent.parent.parent
    rtl_dir: Path = None
    fw_dir: Path = None
    build_dir: Path = None

    # Hardware
    cdc_port: str = "/dev/ttyACM0"
    cdc_baud: int = 460800
    jtag_port: str = "/dev/ttyACM1"  # Black Magic Probe

    # Vivado
    vivado_path: str = "/opt/Xilinx/Vivado/2024.1/bin/vivado"
    vivado_project: str = "fluxripper.xpr"

    # Timing
    fw_build_timeout: int = 30
    rtl_build_timeout: int = 3600  # 1 hour max
    test_timeout: int = 60

    def __post_init__(self):
        self.rtl_dir = self.project_root / "rtl"
        self.fw_dir = self.project_root / "soc" / "firmware"
        self.build_dir = self.project_root / "build"


#==============================================================================
# CDC Console Interface
#==============================================================================

class CDCConsole:
    """Interface to FluxRipper CDC debug console."""

    def __init__(self, port: str, baud: int = 460800):
        self.port = port
        self.baud = baud
        self.serial: Optional[serial.Serial] = None
        self.response_queue = queue.Queue()
        self.reader_thread: Optional[threading.Thread] = None
        self.running = False

    def connect(self) -> bool:
        """Connect to CDC console."""
        try:
            self.serial = serial.Serial(
                self.port,
                self.baud,
                timeout=0.1,
                write_timeout=1.0
            )
            self.running = True
            self.reader_thread = threading.Thread(target=self._reader_loop, daemon=True)
            self.reader_thread.start()
            time.sleep(0.5)  # Wait for connection
            return True
        except Exception as e:
            print(f"CDC connect failed: {e}")
            return False

    def disconnect(self):
        """Disconnect from CDC console."""
        self.running = False
        if self.reader_thread:
            self.reader_thread.join(timeout=1.0)
        if self.serial:
            self.serial.close()
            self.serial = None

    def _reader_loop(self):
        """Background thread to read responses."""
        buffer = ""
        while self.running:
            try:
                if self.serial and self.serial.in_waiting:
                    data = self.serial.read(self.serial.in_waiting).decode('utf-8', errors='replace')
                    buffer += data

                    # Split on newlines
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        line = line.strip()
                        if line:
                            self.response_queue.put(line)
                else:
                    time.sleep(0.01)
            except Exception as e:
                if self.running:
                    print(f"Reader error: {e}")
                time.sleep(0.1)

    def send(self, command: str) -> List[str]:
        """Send command and collect response lines."""
        if not self.serial:
            return []

        # Clear queue
        while not self.response_queue.empty():
            try:
                self.response_queue.get_nowait()
            except queue.Empty:
                break

        # Send command
        self.serial.write(f"{command}\r\n".encode())
        self.serial.flush()

        # Collect response (wait for prompt or timeout)
        responses = []
        deadline = time.time() + 2.0

        while time.time() < deadline:
            try:
                line = self.response_queue.get(timeout=0.1)
                if line.startswith('>'):
                    break
                responses.append(line)
            except queue.Empty:
                continue

        return responses

    def command(self, cmd: str) -> str:
        """Send command, return single response string."""
        lines = self.send(cmd)
        return '\n'.join(lines)

    def read_memory(self, addr: int) -> Optional[int]:
        """Read 32-bit word from memory."""
        response = self.command(f"dbg r {addr:08x}")
        if response.startswith("OK:"):
            try:
                return int(response.split(":")[1].strip(), 16)
            except:
                pass
        return None

    def write_memory(self, addr: int, data: int) -> bool:
        """Write 32-bit word to memory."""
        response = self.command(f"dbg w {addr:08x} {data:08x}")
        return "OK" in response

    def write_block(self, addr: int, data: bytes) -> bool:
        """Write block of data to memory."""
        # Convert bytes to 32-bit words
        words = []
        for i in range(0, len(data), 4):
            chunk = data[i:i+4]
            while len(chunk) < 4:
                chunk += b'\x00'
            words.append(int.from_bytes(chunk, 'little'))

        # Write each word
        for i, word in enumerate(words):
            if not self.write_memory(addr + i * 4, word):
                return False
        return True

    def get_layer(self) -> int:
        """Get current bring-up layer."""
        value = self.read_memory(0x44A80074)
        return value & 0xF if value is not None else -1

    def get_status(self) -> Dict:
        """Get full system status."""
        response = self.command("dbg status")
        status = {}
        for line in response.split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                status[key.strip().lower()] = value.strip()
        return status

    def probe(self, group: int = 0) -> Optional[int]:
        """Read signal tap probe group."""
        response = self.command(f"dbg probe {group}")
        if response.startswith("P:"):
            try:
                return int(response[2:].strip(), 16)
            except:
                pass
        return None

    def trace_start(self):
        """Start trace capture."""
        self.command("dbg trace start")

    def trace_stop(self) -> List[str]:
        """Stop trace and return entries."""
        self.command("dbg trace stop")
        return self.send("dbg trace dump")

    def cpu_halt(self) -> bool:
        """Halt CPU."""
        return "OK" in self.command("dbg cpu halt")

    def cpu_run(self) -> bool:
        """Resume CPU."""
        return "OK" in self.command("dbg cpu run")

    def cpu_reset(self) -> bool:
        """Reset CPU."""
        return "OK" in self.command("dbg cpu reset")


#==============================================================================
# Firmware Builder
#==============================================================================

class FirmwareBuilder:
    """Firmware compilation and deployment."""

    def __init__(self, config: Config):
        self.config = config
        self.last_hash: Optional[str] = None

    def get_source_hash(self) -> str:
        """Calculate hash of all firmware sources."""
        hasher = hashlib.sha256()

        for pattern in ["**/*.c", "**/*.h", "**/Makefile"]:
            for f in self.config.fw_dir.glob(pattern):
                hasher.update(f.read_bytes())

        return hasher.hexdigest()[:16]

    def needs_rebuild(self) -> bool:
        """Check if firmware needs rebuilding."""
        current_hash = self.get_source_hash()
        return current_hash != self.last_hash

    def build(self) -> bool:
        """Build firmware."""
        print("Building firmware...")
        start = time.time()

        result = subprocess.run(
            ["make", "-j4"],
            cwd=self.config.fw_dir,
            capture_output=True,
            timeout=self.config.fw_build_timeout
        )

        elapsed = time.time() - start

        if result.returncode == 0:
            self.last_hash = self.get_source_hash()
            print(f"Firmware built in {elapsed:.1f}s")
            return True
        else:
            print(f"Firmware build failed:\n{result.stderr.decode()}")
            return False

    def get_binary(self) -> Optional[bytes]:
        """Get compiled firmware binary."""
        bin_path = self.config.fw_dir / "build" / "firmware.bin"
        if bin_path.exists():
            return bin_path.read_bytes()
        return None

    def deploy(self, console: CDCConsole) -> bool:
        """Deploy firmware to target via debug console."""
        binary = self.get_binary()
        if not binary:
            print("No firmware binary found")
            return False

        print(f"Deploying firmware ({len(binary)} bytes)...")

        # Halt CPU
        if not console.cpu_halt():
            print("Failed to halt CPU")
            return False

        # Write firmware to RAM
        fw_base = 0x40000000  # BRAM base
        if not console.write_block(fw_base, binary):
            print("Failed to write firmware")
            return False

        # Reset and run
        if not console.cpu_reset():
            print("Failed to reset CPU")
            return False

        time.sleep(0.1)

        if not console.cpu_run():
            print("Failed to start CPU")
            return False

        print("Firmware deployed successfully")
        return True


#==============================================================================
# RTL Builder (Background)
#==============================================================================

class RTLBuilder:
    """RTL synthesis and implementation (runs in background)."""

    def __init__(self, config: Config):
        self.config = config
        self.build_thread: Optional[threading.Thread] = None
        self.build_status = "idle"
        self.last_hash: Optional[str] = None
        self.bitstream_ready = threading.Event()

    def get_source_hash(self) -> str:
        """Calculate hash of all RTL sources."""
        hasher = hashlib.sha256()

        for pattern in ["**/*.v", "**/*.sv", "**/*.xdc"]:
            for f in self.config.rtl_dir.glob(pattern):
                hasher.update(f.read_bytes())

        return hasher.hexdigest()[:16]

    def needs_rebuild(self) -> bool:
        """Check if RTL needs rebuilding."""
        current_hash = self.get_source_hash()
        return current_hash != self.last_hash

    def start_build(self):
        """Start background RTL build."""
        if self.build_thread and self.build_thread.is_alive():
            print("RTL build already in progress")
            return

        self.bitstream_ready.clear()
        self.build_thread = threading.Thread(target=self._build_worker, daemon=True)
        self.build_thread.start()

    def _build_worker(self):
        """Background build worker."""
        self.build_status = "running"
        print("Starting RTL build (background)...")
        start = time.time()

        try:
            # Run Vivado in batch mode
            tcl_script = self.config.build_dir / "build.tcl"

            result = subprocess.run(
                [self.config.vivado_path, "-mode", "batch", "-source", str(tcl_script)],
                cwd=self.config.build_dir,
                capture_output=True,
                timeout=self.config.rtl_build_timeout
            )

            elapsed = time.time() - start

            if result.returncode == 0:
                self.last_hash = self.get_source_hash()
                self.build_status = "success"
                self.bitstream_ready.set()
                print(f"\nRTL build complete in {elapsed/60:.1f} minutes")
            else:
                self.build_status = "failed"
                print(f"\nRTL build failed:\n{result.stderr.decode()[-500:]}")

        except subprocess.TimeoutExpired:
            self.build_status = "timeout"
            print("\nRTL build timed out")
        except Exception as e:
            self.build_status = f"error: {e}"
            print(f"\nRTL build error: {e}")

    def is_building(self) -> bool:
        """Check if build is in progress."""
        return self.build_thread and self.build_thread.is_alive()

    def wait_for_build(self, timeout: float = None) -> bool:
        """Wait for build to complete."""
        return self.bitstream_ready.wait(timeout=timeout)

    def get_bitstream(self) -> Optional[Path]:
        """Get path to built bitstream."""
        bit_path = self.config.build_dir / "fluxripper.bit"
        if bit_path.exists():
            return bit_path
        return None


#==============================================================================
# Test Framework
#==============================================================================

class TestResult(Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    SKIP = "SKIP"
    ERROR = "ERROR"


@dataclass
class TestCase:
    """A single test case."""
    name: str
    description: str
    layer_required: int
    test_fn: Callable[['TestRunner'], TestResult]
    timeout: float = 10.0


class TestRunner:
    """Automated test execution."""

    def __init__(self, console: CDCConsole, config: Config):
        self.console = console
        self.config = config
        self.tests: List[TestCase] = []
        self.results: Dict[str, TestResult] = {}

    def register(self, test: TestCase):
        """Register a test case."""
        self.tests.append(test)

    def run_all(self, min_layer: int = 0) -> Dict[str, TestResult]:
        """Run all applicable tests."""
        current_layer = self.console.get_layer()
        print(f"\nRunning tests (current layer: {current_layer})")
        print("=" * 60)

        passed = 0
        failed = 0
        skipped = 0

        for test in self.tests:
            if test.layer_required > current_layer:
                self.results[test.name] = TestResult.SKIP
                skipped += 1
                print(f"  SKIP  {test.name} (requires layer {test.layer_required})")
                continue

            if test.layer_required < min_layer:
                continue

            try:
                start = time.time()
                result = test.test_fn(self)
                elapsed = time.time() - start

                self.results[test.name] = result

                if result == TestResult.PASS:
                    passed += 1
                    print(f"  PASS  {test.name} ({elapsed:.2f}s)")
                else:
                    failed += 1
                    print(f"  FAIL  {test.name} ({elapsed:.2f}s)")

            except Exception as e:
                self.results[test.name] = TestResult.ERROR
                failed += 1
                print(f"  ERROR {test.name}: {e}")

        print("=" * 60)
        print(f"Results: {passed} passed, {failed} failed, {skipped} skipped")

        return self.results

    def run_quick(self) -> bool:
        """Run quick smoke tests only."""
        quick_tests = [t for t in self.tests if t.timeout < 5.0]

        for test in quick_tests:
            if test.layer_required > self.console.get_layer():
                continue
            try:
                if test.test_fn(self) != TestResult.PASS:
                    return False
            except:
                return False
        return True


#==============================================================================
# Built-in Tests
#==============================================================================

def test_memory_basic(runner: TestRunner) -> TestResult:
    """Test basic memory read/write."""
    # Write pattern to scratch register
    test_value = 0xCAFEBABE
    if not runner.console.write_memory(0x44A8006C, test_value):
        return TestResult.FAIL

    # Read back
    read_value = runner.console.read_memory(0x44A8006C)
    if read_value != test_value:
        return TestResult.FAIL

    return TestResult.PASS


def test_memory_walking_ones(runner: TestRunner) -> TestResult:
    """Test memory with walking ones pattern."""
    addr = 0x40000100  # Test area in BRAM

    for bit in range(32):
        pattern = 1 << bit
        if not runner.console.write_memory(addr, pattern):
            return TestResult.FAIL
        if runner.console.read_memory(addr) != pattern:
            return TestResult.FAIL

    return TestResult.PASS


def test_pll_locked(runner: TestRunner) -> TestResult:
    """Verify all PLLs are locked."""
    status = runner.console.read_memory(0x40020000)
    if status is None:
        return TestResult.ERROR

    # Check all 5 PLL lock bits
    if (status & 0x1F) != 0x1F:
        return TestResult.FAIL

    return TestResult.PASS


def test_usb_enumerated(runner: TestRunner) -> TestResult:
    """Verify USB is enumerated."""
    state = runner.console.read_memory(0x44000020)
    if state is None:
        return TestResult.ERROR

    # Check configured state (5) and high-speed (bit 3)
    if (state & 0x07) != 0x05:
        return TestResult.FAIL
    if not (state & 0x08):
        return TestResult.FAIL  # Not high-speed

    return TestResult.PASS


def test_fdc_ready(runner: TestRunner) -> TestResult:
    """Test FDC responds (drive not required)."""
    status = runner.console.read_memory(0x44100000)
    if status is None:
        return TestResult.ERROR

    # Just verify register is readable
    return TestResult.PASS


def test_signal_tap(runner: TestRunner) -> TestResult:
    """Verify signal tap works."""
    for group in range(4):
        value = runner.console.probe(group)
        if value is None:
            return TestResult.FAIL
    return TestResult.PASS


def test_trace_buffer(runner: TestRunner) -> TestResult:
    """Verify trace buffer works."""
    runner.console.command("dbg trace clear")
    runner.console.command("dbg trace start")
    time.sleep(0.1)
    entries = runner.console.trace_stop()

    # Should have at least a few entries from normal activity
    if len(entries) < 1:
        return TestResult.FAIL

    return TestResult.PASS


def create_standard_tests() -> List[TestCase]:
    """Create standard test suite."""
    return [
        TestCase("memory_basic", "Basic memory read/write", 2, test_memory_basic, 1.0),
        TestCase("memory_walking", "Walking ones pattern", 2, test_memory_walking_ones, 2.0),
        TestCase("pll_locked", "All PLLs locked", 4, test_pll_locked, 1.0),
        TestCase("usb_enum", "USB enumerated", 6, test_usb_enumerated, 1.0),
        TestCase("fdc_ready", "FDC accessible", 7, test_fdc_ready, 1.0),
        TestCase("signal_tap", "Signal tap works", 7, test_signal_tap, 2.0),
        TestCase("trace_buffer", "Trace buffer works", 7, test_trace_buffer, 2.0),
    ]


#==============================================================================
# Development Loop Controller
#==============================================================================

class DevLoop:
    """Main development loop controller."""

    def __init__(self, config: Config):
        self.config = config
        self.console: Optional[CDCConsole] = None
        self.fw_builder = FirmwareBuilder(config)
        self.rtl_builder = RTLBuilder(config)
        self.test_runner: Optional[TestRunner] = None
        self.running = False

    def connect(self) -> bool:
        """Connect to hardware."""
        self.console = CDCConsole(self.config.cdc_port, self.config.cdc_baud)
        if not self.console.connect():
            return False

        self.test_runner = TestRunner(self.console, self.config)
        for test in create_standard_tests():
            self.test_runner.register(test)

        return True

    def disconnect(self):
        """Disconnect from hardware."""
        if self.console:
            self.console.disconnect()
            self.console = None

    def status(self):
        """Print current status."""
        if not self.console:
            print("Not connected")
            return

        layer = self.console.get_layer()
        status = self.console.get_status()

        print("\n" + "=" * 60)
        print("FluxRipper Development Status")
        print("=" * 60)
        print(f"Layer: {layer}")
        for key, value in status.items():
            print(f"  {key}: {value}")

        if self.rtl_builder.is_building():
            print(f"\nRTL Build: IN PROGRESS")
        elif self.rtl_builder.build_status != "idle":
            print(f"\nRTL Build: {self.rtl_builder.build_status}")

        print("=" * 60)

    def fw_reload(self) -> bool:
        """Rebuild and reload firmware."""
        if not self.console:
            print("Not connected")
            return False

        # Build
        if not self.fw_builder.build():
            return False

        # Deploy
        if not self.fw_builder.deploy(self.console):
            return False

        # Quick verify
        time.sleep(0.5)
        layer = self.console.get_layer()
        print(f"Firmware running, layer: {layer}")

        return True

    def run_tests(self, quick: bool = False) -> bool:
        """Run test suite."""
        if not self.test_runner:
            print("Not connected")
            return False

        if quick:
            return self.test_runner.run_quick()
        else:
            results = self.test_runner.run_all()
            return all(r in (TestResult.PASS, TestResult.SKIP) for r in results.values())

    def watch_and_reload(self):
        """Watch for changes and auto-reload."""
        print("Watching for changes (Ctrl+C to stop)...")
        self.running = True

        last_fw_hash = self.fw_builder.get_source_hash()
        last_rtl_hash = self.rtl_builder.get_source_hash()

        try:
            while self.running:
                # Check firmware changes
                current_fw_hash = self.fw_builder.get_source_hash()
                if current_fw_hash != last_fw_hash:
                    print("\nFirmware change detected...")
                    if self.fw_reload():
                        if self.run_tests(quick=True):
                            print("Quick tests passed")
                        else:
                            print("Quick tests FAILED")
                    last_fw_hash = current_fw_hash

                # Check RTL changes (start background build)
                current_rtl_hash = self.rtl_builder.get_source_hash()
                if current_rtl_hash != last_rtl_hash:
                    if not self.rtl_builder.is_building():
                        print("\nRTL change detected, starting background build...")
                        self.rtl_builder.start_build()
                    last_rtl_hash = current_rtl_hash

                # Check if RTL build completed
                if self.rtl_builder.bitstream_ready.is_set():
                    print("\nNew bitstream ready! Program FPGA with:")
                    print(f"  vivado -mode batch -source program.tcl")
                    self.rtl_builder.bitstream_ready.clear()

                time.sleep(1.0)

        except KeyboardInterrupt:
            print("\nStopped watching")
            self.running = False

    def interactive(self):
        """Interactive development console."""
        print("\nFluxRipper Development Console")
        print("Commands: status, reload, test, quick, watch, probe <n>, trace, quit")
        print()

        while True:
            try:
                cmd = input("dev> ").strip().lower()

                if not cmd:
                    continue
                elif cmd == "quit" or cmd == "exit":
                    break
                elif cmd == "status":
                    self.status()
                elif cmd == "reload":
                    self.fw_reload()
                elif cmd == "test":
                    self.run_tests()
                elif cmd == "quick":
                    if self.run_tests(quick=True):
                        print("Quick tests: PASS")
                    else:
                        print("Quick tests: FAIL")
                elif cmd == "watch":
                    self.watch_and_reload()
                elif cmd.startswith("probe"):
                    parts = cmd.split()
                    group = int(parts[1]) if len(parts) > 1 else 0
                    value = self.console.probe(group)
                    print(f"Probe {group}: {value:08X}" if value else "Failed")
                elif cmd == "trace":
                    self.console.trace_start()
                    time.sleep(0.5)
                    for line in self.console.trace_stop():
                        print(line)
                elif cmd.startswith("r "):
                    addr = int(cmd.split()[1], 16)
                    value = self.console.read_memory(addr)
                    print(f"{addr:08X}: {value:08X}" if value else "Failed")
                elif cmd.startswith("w "):
                    parts = cmd.split()
                    addr = int(parts[1], 16)
                    data = int(parts[2], 16)
                    if self.console.write_memory(addr, data):
                        print("OK")
                    else:
                        print("Failed")
                else:
                    # Pass through to CDC console
                    response = self.console.command(cmd)
                    if response:
                        print(response)

            except KeyboardInterrupt:
                print()
            except Exception as e:
                print(f"Error: {e}")


#==============================================================================
# Main Entry Point
#==============================================================================

def main():
    parser = argparse.ArgumentParser(description="FluxRipper Development Loop")
    parser.add_argument("--port", default="/dev/ttyACM0", help="CDC port")
    parser.add_argument("--baud", type=int, default=460800, help="Baud rate")
    parser.add_argument("command", nargs="?", default="interactive",
                       choices=["interactive", "status", "reload", "test", "watch"],
                       help="Command to run")

    args = parser.parse_args()

    config = Config()
    config.cdc_port = args.port
    config.cdc_baud = args.baud

    dev = DevLoop(config)

    print("Connecting to FluxRipper...")
    if not dev.connect():
        print("Failed to connect")
        sys.exit(1)

    try:
        if args.command == "interactive":
            dev.interactive()
        elif args.command == "status":
            dev.status()
        elif args.command == "reload":
            dev.fw_reload()
        elif args.command == "test":
            success = dev.run_tests()
            sys.exit(0 if success else 1)
        elif args.command == "watch":
            dev.watch_and_reload()
    finally:
        dev.disconnect()


if __name__ == "__main__":
    main()
