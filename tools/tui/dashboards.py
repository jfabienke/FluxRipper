#!/usr/bin/env python3
"""
FluxRipper TUI Dashboards
Mock dashboard layouts for instrumentation visualization

Created: 2025-12-05 17:50

These dashboards demonstrate the visualization of FluxRipper
diagnostics and instrumentation data in a terminal interface.
"""

import curses
import time
import random
from dataclasses import dataclass
from typing import List, Optional

# =============================================================================
# Data Structures (matching C structures)
# =============================================================================

@dataclass
class SystemInfo:
    fw_version: str = "1.0.0"
    hw_version: str = "1.0"
    fpga_version: str = "0x00010000"
    uptime_sec: int = 0
    temperature_c: float = 45.0
    vcc_int: float = 1.0
    vcc_aux: float = 1.8
    v5_rail: float = 5.0
    v12_rail: float = 12.0
    current_ma: int = 500

@dataclass
class USBStats:
    rx_bytes: int = 0
    tx_bytes: int = 0
    rx_packets: int = 0
    tx_packets: int = 0
    errors: int = 0
    retries: int = 0

@dataclass
class SignalStats:
    amplitude_min: int = 0
    amplitude_max: int = 0
    amplitude_avg: int = 0
    noise_floor: int = 0
    snr_db: float = 0.0
    jitter_pp_ns: int = 0
    jitter_rms_ns: int = 0
    quality_score: int = 0
    weak_bits: int = 0
    bit_error_rate: int = 0

@dataclass
class PLLStats:
    locked: bool = True
    frequency_hz: int = 500000
    lock_count: int = 0
    unlock_count: int = 0
    phase_error_deg: float = 0.0

@dataclass
class DriveStats:
    drive_type: str = "FDD"
    drive_num: int = 0
    present: bool = True
    write_protected: bool = False
    current_track: int = 0
    rpm: int = 300
    sectors_read: int = 0
    sectors_written: int = 0
    seek_count: int = 0
    errors: int = 0

# =============================================================================
# Dashboard Base Class
# =============================================================================

class Dashboard:
    """Base class for TUI dashboards"""

    def __init__(self, stdscr):
        self.stdscr = stdscr
        self.height, self.width = stdscr.getmaxyx()
        curses.start_color()
        curses.use_default_colors()

        # Define color pairs
        curses.init_pair(1, curses.COLOR_GREEN, -1)   # Good/OK
        curses.init_pair(2, curses.COLOR_YELLOW, -1)  # Warning
        curses.init_pair(3, curses.COLOR_RED, -1)     # Error/Bad
        curses.init_pair(4, curses.COLOR_CYAN, -1)    # Info
        curses.init_pair(5, curses.COLOR_MAGENTA, -1) # Highlight
        curses.init_pair(6, curses.COLOR_WHITE, -1)   # Normal

    def draw_box(self, y, x, height, width, title=""):
        """Draw a box with optional title"""
        # Corners
        self.stdscr.addch(y, x, curses.ACS_ULCORNER)
        self.stdscr.addch(y, x + width - 1, curses.ACS_URCORNER)
        self.stdscr.addch(y + height - 1, x, curses.ACS_LLCORNER)
        self.stdscr.addch(y + height - 1, x + width - 1, curses.ACS_LRCORNER)

        # Horizontal lines
        for i in range(1, width - 1):
            self.stdscr.addch(y, x + i, curses.ACS_HLINE)
            self.stdscr.addch(y + height - 1, x + i, curses.ACS_HLINE)

        # Vertical lines
        for i in range(1, height - 1):
            self.stdscr.addch(y + i, x, curses.ACS_VLINE)
            self.stdscr.addch(y + i, x + width - 1, curses.ACS_VLINE)

        # Title
        if title:
            self.stdscr.addstr(y, x + 2, f" {title} ", curses.A_BOLD)

    def draw_progress_bar(self, y, x, width, value, max_value, color_pair=1):
        """Draw a horizontal progress bar"""
        filled = int((value / max_value) * (width - 2)) if max_value > 0 else 0
        bar = "█" * filled + "░" * (width - 2 - filled)
        self.stdscr.addstr(y, x, "[", curses.color_pair(6))
        self.stdscr.addstr(y, x + 1, bar, curses.color_pair(color_pair))
        self.stdscr.addstr(y, x + width - 1, "]", curses.color_pair(6))

    def draw_histogram(self, y, x, width, height, bins, title=""):
        """Draw a vertical bar histogram"""
        if not bins:
            return

        max_val = max(bins) if bins else 1
        bar_width = (width - 2) // len(bins)

        self.draw_box(y, x, height, width, title)

        for i, val in enumerate(bins):
            bar_height = int((val / max_val) * (height - 3)) if max_val > 0 else 0
            bx = x + 1 + i * bar_width

            for h in range(bar_height):
                by = y + height - 2 - h
                if by > y and bx < x + width - 1:
                    self.stdscr.addstr(by, bx, "█" * (bar_width - 1),
                                       curses.color_pair(4))

    def draw_sparkline(self, y, x, width, values):
        """Draw a sparkline chart"""
        if not values:
            return

        chars = "▁▂▃▄▅▆▇█"
        max_val = max(values) if values else 1
        min_val = min(values) if values else 0
        range_val = max_val - min_val if max_val != min_val else 1

        line = ""
        for v in values[-width:]:
            idx = int(((v - min_val) / range_val) * 7)
            idx = max(0, min(7, idx))
            line += chars[idx]

        self.stdscr.addstr(y, x, line, curses.color_pair(4))

    def format_bytes(self, bytes_val):
        """Format bytes to human readable"""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_val < 1024:
                return f"{bytes_val:.1f}{unit}"
            bytes_val /= 1024
        return f"{bytes_val:.1f}PB"

    def format_uptime(self, seconds):
        """Format uptime to human readable"""
        days = seconds // 86400
        hours = (seconds % 86400) // 3600
        mins = (seconds % 3600) // 60
        secs = seconds % 60

        if days > 0:
            return f"{days}d {hours:02d}:{mins:02d}:{secs:02d}"
        else:
            return f"{hours:02d}:{mins:02d}:{secs:02d}"


# =============================================================================
# Main Overview Dashboard
# =============================================================================

class MainDashboard(Dashboard):
    """Main system overview dashboard"""

    def draw(self, sys_info: SystemInfo, usb_stats: USBStats,
             signal_stats: SignalStats, pll_stats: PLLStats,
             drive_stats: List[DriveStats]):

        self.stdscr.clear()

        # Header
        self.stdscr.addstr(0, 0, "═" * self.width, curses.color_pair(4))
        title = "FluxRipper Dashboard"
        self.stdscr.addstr(0, (self.width - len(title)) // 2,
                          f" {title} ", curses.A_BOLD | curses.color_pair(5))

        # System Info Box (top left)
        self.draw_box(2, 0, 10, 40, "System Info")
        self.stdscr.addstr(3, 2, f"FW Version:  {sys_info.fw_version}")
        self.stdscr.addstr(4, 2, f"HW Version:  {sys_info.hw_version}")
        self.stdscr.addstr(5, 2, f"Uptime:      {self.format_uptime(sys_info.uptime_sec)}")
        self.stdscr.addstr(6, 2, f"Temperature: {sys_info.temperature_c:.1f}°C",
                          curses.color_pair(1 if sys_info.temperature_c < 60 else
                                           2 if sys_info.temperature_c < 80 else 3))
        self.stdscr.addstr(7, 2, f"VCC_INT:     {sys_info.vcc_int:.2f}V")
        self.stdscr.addstr(8, 2, f"5V Rail:     {sys_info.v5_rail:.2f}V")
        self.stdscr.addstr(9, 2, f"12V Rail:    {sys_info.v12_rail:.2f}V")
        self.stdscr.addstr(10, 2, f"Current:     {sys_info.current_ma}mA")

        # USB Stats Box (top middle)
        self.draw_box(2, 42, 10, 38, "USB Statistics")
        self.stdscr.addstr(3, 44, f"RX Bytes:   {self.format_bytes(usb_stats.rx_bytes):>12}")
        self.stdscr.addstr(4, 44, f"TX Bytes:   {self.format_bytes(usb_stats.tx_bytes):>12}")
        self.stdscr.addstr(5, 44, f"RX Packets: {usb_stats.rx_packets:>12,}")
        self.stdscr.addstr(6, 44, f"TX Packets: {usb_stats.tx_packets:>12,}")
        self.stdscr.addstr(7, 44, f"Errors:     {usb_stats.errors:>12}",
                          curses.color_pair(1 if usb_stats.errors == 0 else 3))
        self.stdscr.addstr(8, 44, f"Retries:    {usb_stats.retries:>12}")

        # Throughput bar
        self.stdscr.addstr(10, 44, "Throughput: ")
        self.draw_progress_bar(10, 56, 22, usb_stats.rx_bytes % 10000000, 10000000)

        # PLL Status Box (top right)
        self.draw_box(2, 82, 10, 36, "PLL Status")
        lock_status = "LOCKED" if pll_stats.locked else "UNLOCKED"
        lock_color = 1 if pll_stats.locked else 3
        self.stdscr.addstr(3, 84, f"Status:      ", curses.color_pair(6))
        self.stdscr.addstr(3, 97, f"{lock_status:>12}", curses.color_pair(lock_color) | curses.A_BOLD)
        self.stdscr.addstr(4, 84, f"Frequency:   {pll_stats.frequency_hz/1000:.1f} kHz")
        self.stdscr.addstr(5, 84, f"Lock Count:  {pll_stats.lock_count:>12}")
        self.stdscr.addstr(6, 84, f"Unlock Cnt:  {pll_stats.unlock_count:>12}")
        self.stdscr.addstr(7, 84, f"Phase Err:   {pll_stats.phase_error_deg:>10.1f}°")

        # Lock quality bar
        self.stdscr.addstr(9, 84, "Lock Quality:")
        quality = 100 if pll_stats.locked else 0
        self.draw_progress_bar(9, 98, 18, quality, 100, 1 if quality > 80 else 2 if quality > 50 else 3)

        # Drive Status Box (middle)
        self.draw_box(13, 0, 12, 80, "Drive Status")

        # Header row
        self.stdscr.addstr(14, 2, "Drive", curses.A_BOLD)
        self.stdscr.addstr(14, 12, "Type", curses.A_BOLD)
        self.stdscr.addstr(14, 20, "Status", curses.A_BOLD)
        self.stdscr.addstr(14, 32, "Track", curses.A_BOLD)
        self.stdscr.addstr(14, 40, "RPM", curses.A_BOLD)
        self.stdscr.addstr(14, 48, "Reads", curses.A_BOLD)
        self.stdscr.addstr(14, 58, "Writes", curses.A_BOLD)
        self.stdscr.addstr(14, 68, "Errors", curses.A_BOLD)

        self.stdscr.addstr(15, 2, "─" * 76)

        # Drive rows
        for i, drv in enumerate(drive_stats[:4]):
            row = 16 + i * 2

            # Drive indicator
            indicator = "●" if drv.present else "○"
            self.stdscr.addstr(row, 2, f"{indicator} ",
                              curses.color_pair(1 if drv.present else 6))
            self.stdscr.addstr(row, 4, f"Drive {drv.drive_num}")

            self.stdscr.addstr(row, 12, drv.drive_type)

            status = "Ready" if drv.present else "Empty"
            if drv.write_protected:
                status = "WP"
            self.stdscr.addstr(row, 20, f"{status:8}",
                              curses.color_pair(1 if drv.present else 6))

            self.stdscr.addstr(row, 32, f"{drv.current_track:3}" if drv.drive_type == "FDD" else "N/A")
            self.stdscr.addstr(row, 40, f"{drv.rpm:4}" if drv.drive_type == "FDD" else "N/A")
            self.stdscr.addstr(row, 48, f"{drv.sectors_read:7,}")
            self.stdscr.addstr(row, 58, f"{drv.sectors_written:7,}")
            self.stdscr.addstr(row, 68, f"{drv.errors:6}",
                              curses.color_pair(1 if drv.errors == 0 else 3))

        # Signal Quality Box (right side)
        self.draw_box(13, 82, 12, 36, "Signal Quality")

        score = signal_stats.quality_score
        score_color = 1 if score > 80 else 2 if score > 50 else 3
        self.stdscr.addstr(14, 84, f"Quality Score: ", curses.color_pair(6))
        self.stdscr.addstr(14, 99, f"{score:3}%", curses.color_pair(score_color) | curses.A_BOLD)

        self.draw_progress_bar(15, 84, 32, score, 100, score_color)

        self.stdscr.addstr(17, 84, f"Amplitude Min: {signal_stats.amplitude_min:5} mV")
        self.stdscr.addstr(18, 84, f"Amplitude Max: {signal_stats.amplitude_max:5} mV")
        self.stdscr.addstr(19, 84, f"SNR:           {signal_stats.snr_db:5.1f} dB")
        self.stdscr.addstr(20, 84, f"Jitter RMS:    {signal_stats.jitter_rms_ns:5} ns")
        self.stdscr.addstr(21, 84, f"Weak Bits:     {signal_stats.weak_bits:5}")
        self.stdscr.addstr(22, 84, f"BER:           {signal_stats.bit_error_rate:5} ppm")

        # Footer
        self.stdscr.addstr(self.height - 2, 0, "─" * self.width, curses.color_pair(6))
        self.stdscr.addstr(self.height - 1, 2,
                          "[1]Main [2]Signal [3]Performance [4]Drive [Q]Quit",
                          curses.color_pair(4))

        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        self.stdscr.addstr(self.height - 1, self.width - len(timestamp) - 2, timestamp)

        self.stdscr.refresh()


# =============================================================================
# Signal Analysis Dashboard
# =============================================================================

class SignalDashboard(Dashboard):
    """Signal quality and flux analysis dashboard"""

    def draw(self, signal_stats: SignalStats, flux_histogram: List[int],
             amplitude_history: List[int], jitter_history: List[int]):

        self.stdscr.clear()

        # Header
        self.stdscr.addstr(0, 0, "═" * self.width, curses.color_pair(4))
        title = "Signal Analysis Dashboard"
        self.stdscr.addstr(0, (self.width - len(title)) // 2,
                          f" {title} ", curses.A_BOLD | curses.color_pair(5))

        # Quality Score (large display)
        self.draw_box(2, 0, 8, 30, "Quality Score")
        score = signal_stats.quality_score

        # Large ASCII number
        large_score = f"{score:3d}%"
        self.stdscr.addstr(4, 5, large_score,
                          curses.A_BOLD | curses.color_pair(
                              1 if score > 80 else 2 if score > 50 else 3))

        grade = "EXCELLENT" if score > 90 else "GOOD" if score > 75 else \
                "FAIR" if score > 50 else "POOR"
        self.stdscr.addstr(6, 5, grade, curses.color_pair(
            1 if score > 80 else 2 if score > 50 else 3))

        # Amplitude Stats
        self.draw_box(2, 32, 8, 42, "Signal Amplitude")
        self.stdscr.addstr(3, 34, f"Minimum:  {signal_stats.amplitude_min:6} mV")
        self.stdscr.addstr(4, 34, f"Maximum:  {signal_stats.amplitude_max:6} mV")
        self.stdscr.addstr(5, 34, f"Average:  {signal_stats.amplitude_avg:6} mV")
        self.stdscr.addstr(6, 34, f"Noise:    {signal_stats.noise_floor:6} mV")
        self.stdscr.addstr(7, 34, f"SNR:      {signal_stats.snr_db:6.1f} dB")

        # Visual amplitude meter
        self.stdscr.addstr(3, 58, "├")
        for i in range(12):
            level = (i + 1) * 100
            char = "█" if signal_stats.amplitude_avg >= level else "░"
            color = 1 if i < 8 else 2 if i < 10 else 3
            self.stdscr.addstr(3, 59 + i, char, curses.color_pair(color))
        self.stdscr.addstr(3, 71, "┤")

        # Jitter Stats
        self.draw_box(2, 76, 8, 42, "Timing Jitter")
        self.stdscr.addstr(3, 78, f"Peak-Peak: {signal_stats.jitter_pp_ns:6} ns")
        self.stdscr.addstr(4, 78, f"RMS:       {signal_stats.jitter_rms_ns:6} ns")
        self.stdscr.addstr(5, 78, f"Weak Bits: {signal_stats.weak_bits:6}")
        self.stdscr.addstr(6, 78, f"BER:       {signal_stats.bit_error_rate:6} ppm")

        # Flux Timing Histogram
        self.draw_box(11, 0, 14, 60, "Flux Timing Histogram (μs)")

        if flux_histogram:
            max_val = max(flux_histogram) if flux_histogram else 1

            for i, val in enumerate(flux_histogram[:32]):
                bar_height = int((val / max_val) * 10) if max_val > 0 else 0

                for h in range(bar_height):
                    self.stdscr.addstr(22 - h, 2 + i * 2, "█", curses.color_pair(4))

        # X-axis labels
        self.stdscr.addstr(23, 2, "1.0")
        self.stdscr.addstr(23, 30, "4.0")
        self.stdscr.addstr(23, 56, "8.0")

        # Amplitude Trend
        self.draw_box(11, 62, 7, 56, "Amplitude Trend")
        if amplitude_history:
            self.draw_sparkline(14, 64, 52, amplitude_history)

        # Jitter Trend
        self.draw_box(18, 62, 7, 56, "Jitter Trend")
        if jitter_history:
            self.draw_sparkline(21, 64, 52, jitter_history)

        # Eye Diagram (ASCII representation)
        self.draw_box(26, 0, 12, 60, "Eye Diagram")

        # Simple ASCII eye pattern
        eye_pattern = [
            "              ╱‾‾‾‾‾‾‾╲      ╱‾‾‾‾‾‾‾╲              ",
            "           ╱           ╲  ╱           ╲           ",
            "        ╱                ╳                ╲        ",
            "      ╱                  │                  ╲      ",
            "    ╱                    │                    ╲    ",
            "  ─────────────────────────────────────────────── ",
            "    ╲                    │                    ╱    ",
            "      ╲                  │                  ╱      ",
            "        ╲                ╳                ╱        ",
            "           ╲           ╱  ╲           ╱           ",
        ]

        for i, line in enumerate(eye_pattern):
            self.stdscr.addstr(27 + i, 4, line, curses.color_pair(4))

        # Bit Cell Timing
        self.draw_box(26, 62, 12, 56, "Bit Cell Analysis")
        self.stdscr.addstr(27, 64, "Nominal:     2000 ns")
        self.stdscr.addstr(28, 64, "Measured:    2003 ns")
        self.stdscr.addstr(29, 64, "Min:         1942 ns")
        self.stdscr.addstr(30, 64, "Max:         2061 ns")
        self.stdscr.addstr(31, 64, "Deviation:   ±30 ns (1.5%)")

        self.stdscr.addstr(33, 64, "Short Bits:  23")
        self.stdscr.addstr(34, 64, "Long Bits:   18")
        self.stdscr.addstr(35, 64, "Missing:     0")

        # Footer
        self.stdscr.addstr(self.height - 2, 0, "─" * self.width, curses.color_pair(6))
        self.stdscr.addstr(self.height - 1, 2,
                          "[1]Main [2]Signal [3]Performance [4]Drive [Q]Quit",
                          curses.color_pair(4))

        self.stdscr.refresh()


# =============================================================================
# Performance Dashboard
# =============================================================================

class PerformanceDashboard(Dashboard):
    """Performance monitoring dashboard"""

    def draw(self, usb_stats: USBStats, latency_min: int, latency_max: int,
             latency_avg: int, fifo_levels: dict, throughput_history: List[int]):

        self.stdscr.clear()

        # Header
        self.stdscr.addstr(0, 0, "═" * self.width, curses.color_pair(4))
        title = "Performance Monitor"
        self.stdscr.addstr(0, (self.width - len(title)) // 2,
                          f" {title} ", curses.A_BOLD | curses.color_pair(5))

        # Throughput meters
        self.draw_box(2, 0, 10, 58, "Throughput")

        rx_rate = (usb_stats.rx_bytes % 10000000) / 10000000 * 100
        tx_rate = (usb_stats.tx_bytes % 10000000) / 10000000 * 100

        self.stdscr.addstr(3, 2, "USB RX:")
        self.draw_progress_bar(3, 10, 35, int(rx_rate), 100, 4)
        self.stdscr.addstr(3, 46, f"{rx_rate:.1f} MB/s")

        self.stdscr.addstr(4, 2, "USB TX:")
        self.draw_progress_bar(4, 10, 35, int(tx_rate), 100, 4)
        self.stdscr.addstr(4, 46, f"{tx_rate:.1f} MB/s")

        self.stdscr.addstr(6, 2, "Throughput History:")
        if throughput_history:
            self.draw_sparkline(7, 2, 54, throughput_history)

        self.stdscr.addstr(9, 2, f"Total RX: {self.format_bytes(usb_stats.rx_bytes):>12}  "
                                f"Total TX: {self.format_bytes(usb_stats.tx_bytes):>12}")

        # Latency
        self.draw_box(2, 60, 10, 58, "Latency (μs)")

        self.stdscr.addstr(3, 62, f"Minimum: {latency_min:8} μs")
        self.stdscr.addstr(4, 62, f"Maximum: {latency_max:8} μs")
        self.stdscr.addstr(5, 62, f"Average: {latency_avg:8} μs")

        # Latency distribution bar
        self.stdscr.addstr(7, 62, "Distribution:")
        ranges = [(0, 100, "< 100"), (100, 500, "100-500"),
                  (500, 1000, "500-1K"), (1000, 10000, "> 1K")]

        for i, (lo, hi, label) in enumerate(ranges):
            pct = 25  # Mock percentage
            color = 1 if i < 2 else 2 if i < 3 else 3
            self.stdscr.addstr(8, 62 + i * 14, f"{label}:")
            self.draw_progress_bar(8, 70 + i * 14, 8, pct, 100, color)

        # FIFO Status
        self.draw_box(13, 0, 12, 58, "FIFO Status")

        fifos = [
            ("RX FIFO", fifo_levels.get('rx', 0), 512, "green"),
            ("TX FIFO", fifo_levels.get('tx', 0), 512, "green"),
            ("Flux FIFO", fifo_levels.get('flux', 0), 4096, "cyan"),
            ("Sector Buffer", fifo_levels.get('sector', 0), 256, "green"),
        ]

        for i, (name, level, capacity, color) in enumerate(fifos):
            row = 14 + i * 2
            pct = (level / capacity * 100) if capacity > 0 else 0
            bar_color = 1 if pct < 70 else 2 if pct < 90 else 3

            self.stdscr.addstr(row, 2, f"{name:14}")
            self.draw_progress_bar(row, 17, 25, int(pct), 100, bar_color)
            self.stdscr.addstr(row, 43, f"{level:5}/{capacity}")

        # High-Water Marks
        self.stdscr.addstr(22, 2, "High-Water Marks:", curses.A_BOLD)
        self.stdscr.addstr(23, 2, f"RX: {fifo_levels.get('rx_hwm', 0):4}  "
                                 f"TX: {fifo_levels.get('tx_hwm', 0):4}  "
                                 f"Flux: {fifo_levels.get('flux_hwm', 0):5}  "
                                 f"Sector: {fifo_levels.get('sector_hwm', 0):4}")

        # DMA Statistics
        self.draw_box(13, 60, 12, 58, "DMA Statistics")

        self.stdscr.addstr(14, 62, f"Total Bytes:     {self.format_bytes(usb_stats.rx_bytes):>12}")
        self.stdscr.addstr(15, 62, f"Transfers:       {usb_stats.rx_packets:>12,}")
        self.stdscr.addstr(16, 62, f"Avg Size:        {512:>12} bytes")
        self.stdscr.addstr(17, 62, f"Errors:          {0:>12}")

        self.stdscr.addstr(19, 62, "Channel Activity:")
        channels = ["CH0 [████████░░]", "CH1 [██████░░░░]",
                   "CH2 [░░░░░░░░░░]", "CH3 [░░░░░░░░░░]"]
        for i, ch in enumerate(channels):
            self.stdscr.addstr(20 + i, 62, ch, curses.color_pair(4))

        # Error Summary
        self.draw_box(26, 0, 10, 58, "Error Summary")

        errors = [
            ("USB Errors", usb_stats.errors),
            ("DMA Errors", 0),
            ("CRC Errors", 0),
            ("Timeouts", 0),
            ("FIFO Overflows", 0),
        ]

        for i, (name, count) in enumerate(errors):
            color = 1 if count == 0 else 3
            self.stdscr.addstr(27 + i, 2, f"{name:16} {count:8}", curses.color_pair(color))

        # IRQ Statistics
        self.draw_box(26, 60, 10, 58, "IRQ Statistics")

        irqs = [
            ("USB", 12345),
            ("DMA", 5432),
            ("Timer", 100000),
            ("FDD", 234),
            ("HDD", 0),
        ]

        for i, (name, count) in enumerate(irqs):
            self.stdscr.addstr(27 + i, 62, f"{name:8} {count:12,}")

        # Footer
        self.stdscr.addstr(self.height - 2, 0, "─" * self.width, curses.color_pair(6))
        self.stdscr.addstr(self.height - 1, 2,
                          "[1]Main [2]Signal [3]Performance [4]Drive [Q]Quit",
                          curses.color_pair(4))

        self.stdscr.refresh()


# =============================================================================
# Drive Diagnostics Dashboard
# =============================================================================

class DriveDashboard(Dashboard):
    """Drive diagnostics and characterization dashboard"""

    def draw(self, drives: List[DriveStats], pll_stats: PLLStats,
             index_period: int, rpm_history: List[int]):

        self.stdscr.clear()

        # Header
        self.stdscr.addstr(0, 0, "═" * self.width, curses.color_pair(4))
        title = "Drive Diagnostics"
        self.stdscr.addstr(0, (self.width - len(title)) // 2,
                          f" {title} ", curses.A_BOLD | curses.color_pair(5))

        # Selected Drive (large panel)
        drv = drives[0] if drives else DriveStats()

        self.draw_box(2, 0, 14, 60, f"Drive {drv.drive_num}: {drv.drive_type}")

        # Status indicator
        status_char = "●" if drv.present else "○"
        status_text = "READY" if drv.present else "NOT PRESENT"
        status_color = 1 if drv.present else 6
        self.stdscr.addstr(3, 2, f"Status: {status_char} {status_text}",
                          curses.color_pair(status_color) | curses.A_BOLD)

        # Drive info
        self.stdscr.addstr(5, 2, f"Type:           {drv.drive_type}")
        self.stdscr.addstr(6, 2, f"Write Protect:  {'Yes' if drv.write_protected else 'No'}")
        self.stdscr.addstr(7, 2, f"Current Track:  {drv.current_track}")
        self.stdscr.addstr(8, 2, f"Motor RPM:      {drv.rpm}")

        # Statistics
        self.stdscr.addstr(10, 2, "Statistics:", curses.A_BOLD)
        self.stdscr.addstr(11, 2, f"  Sectors Read:    {drv.sectors_read:10,}")
        self.stdscr.addstr(12, 2, f"  Sectors Written: {drv.sectors_written:10,}")
        self.stdscr.addstr(13, 2, f"  Seek Count:      {drv.seek_count:10,}")
        self.stdscr.addstr(14, 2, f"  Errors:          {drv.errors:10,}")

        # Visual head position
        self.stdscr.addstr(5, 35, "Head Position:")
        track_bar = "─" * 20
        head_pos = min(19, drv.current_track // 4)
        self.stdscr.addstr(6, 35, f"T0 [{track_bar}] T79")
        self.stdscr.addstr(6, 39 + head_pos, "▼", curses.color_pair(5) | curses.A_BOLD)

        # Motor Status
        self.draw_box(2, 62, 14, 56, "Motor / Spindle")

        self.stdscr.addstr(3, 64, f"Target RPM:   {300:6}")
        self.stdscr.addstr(4, 64, f"Actual RPM:   {drv.rpm:6}",
                          curses.color_pair(1 if abs(drv.rpm - 300) < 5 else 2))

        # RPM deviation bar
        deviation = drv.rpm - 300
        self.stdscr.addstr(6, 64, "Deviation: ")
        center = 20
        bar = list(" " * 40)
        bar[center] = "│"
        pos = center + int(deviation / 2)
        pos = max(0, min(39, pos))
        bar[pos] = "█"
        self.stdscr.addstr(7, 64, "".join(bar))
        self.stdscr.addstr(8, 64, "-20       0       +20")

        # RPM History
        self.stdscr.addstr(10, 64, "RPM History:")
        if rpm_history:
            self.draw_sparkline(11, 64, 50, rpm_history)

        self.stdscr.addstr(13, 64, f"Index Period: {index_period:,} ns")
        self.stdscr.addstr(14, 64, f"Period Jitter: ±{500} ns")

        # Timing Characteristics
        self.draw_box(17, 0, 10, 60, "Timing Characteristics")

        timing = [
            ("Step Pulse Width", "3.0 μs"),
            ("Step Rate", "3.0 ms"),
            ("Head Settle Time", "15 ms"),
            ("Motor Spin-up", "500 ms"),
            ("Head Load Time", "1 ms"),
            ("Track 0 Seek", "200 ms"),
            ("Full Seek (T0→T79)", "300 ms"),
        ]

        for i, (name, value) in enumerate(timing):
            self.stdscr.addstr(18 + i, 2, f"{name:24} {value:>10}")

        # Eccentricity Analysis
        self.draw_box(17, 62, 10, 56, "Track Eccentricity")

        self.stdscr.addstr(18, 64, f"Track:         {drv.current_track}")
        self.stdscr.addstr(19, 64, f"Eccentricity:  0.3%")
        self.stdscr.addstr(20, 64, f"Timing Offset: ±150 ns")

        # Visual eccentricity
        self.stdscr.addstr(22, 64, "Per-Revolution Variation:")
        ecc_pattern = "▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁"
        self.stdscr.addstr(23, 64, ecc_pattern[:50], curses.color_pair(4))

        # All Drives Summary
        self.draw_box(28, 0, 8, 118, "All Drives")

        self.stdscr.addstr(29, 2,
            "Drive   Type   Status      Track   RPM    Reads     Writes    Seeks    Errors",
            curses.A_BOLD)
        self.stdscr.addstr(30, 2, "─" * 114)

        for i, d in enumerate(drives[:4]):
            row = 31 + i
            status = "Ready" if d.present else "Empty"
            status_color = 1 if d.present else 6

            self.stdscr.addstr(row, 2, f"  {i}     {d.drive_type:4}   ")
            self.stdscr.addstr(row, 18, f"{status:10}", curses.color_pair(status_color))
            self.stdscr.addstr(row, 30, f"{d.current_track:3}    {d.rpm:4}    "
                                       f"{d.sectors_read:8,}  {d.sectors_written:8,}  "
                                       f"{d.seek_count:6,}  ")
            self.stdscr.addstr(row, 98, f"{d.errors:6}",
                              curses.color_pair(1 if d.errors == 0 else 3))

        # Footer
        self.stdscr.addstr(self.height - 2, 0, "─" * self.width, curses.color_pair(6))
        self.stdscr.addstr(self.height - 1, 2,
                          "[1]Main [2]Signal [3]Performance [4]Drive [Q]Quit",
                          curses.color_pair(4))

        self.stdscr.refresh()


# =============================================================================
# Main Application
# =============================================================================

def generate_mock_data():
    """Generate mock data for demo"""
    sys_info = SystemInfo(
        uptime_sec=random.randint(1000, 100000),
        temperature_c=40 + random.random() * 20,
        current_ma=400 + random.randint(0, 200)
    )

    usb_stats = USBStats(
        rx_bytes=random.randint(1000000, 100000000),
        tx_bytes=random.randint(1000000, 100000000),
        rx_packets=random.randint(10000, 100000),
        tx_packets=random.randint(10000, 100000),
        errors=random.randint(0, 5)
    )

    signal_stats = SignalStats(
        amplitude_min=600 + random.randint(0, 100),
        amplitude_max=900 + random.randint(0, 200),
        amplitude_avg=750 + random.randint(0, 100),
        noise_floor=40 + random.randint(0, 20),
        snr_db=25 + random.random() * 10,
        jitter_pp_ns=40 + random.randint(0, 30),
        jitter_rms_ns=15 + random.randint(0, 10),
        quality_score=random.randint(70, 98),
        weak_bits=random.randint(0, 50),
        bit_error_rate=random.randint(0, 100)
    )

    pll_stats = PLLStats(
        locked=random.random() > 0.05,
        frequency_hz=500000 + random.randint(-5000, 5000),
        lock_count=random.randint(1, 20),
        phase_error_deg=random.random() * 10
    )

    drives = [
        DriveStats(drive_type="FDD", drive_num=0, present=True,
                  current_track=random.randint(0, 79),
                  rpm=300 + random.randint(-3, 3),
                  sectors_read=random.randint(1000, 100000),
                  sectors_written=random.randint(100, 10000),
                  seek_count=random.randint(100, 5000)),
        DriveStats(drive_type="FDD", drive_num=1, present=False),
        DriveStats(drive_type="HDD", drive_num=2, present=True,
                  sectors_read=random.randint(10000, 1000000),
                  sectors_written=random.randint(1000, 100000)),
        DriveStats(drive_type="HDD", drive_num=3, present=False),
    ]

    return sys_info, usb_stats, signal_stats, pll_stats, drives


def main(stdscr):
    """Main application loop"""
    curses.curs_set(0)  # Hide cursor
    stdscr.nodelay(1)   # Non-blocking input

    # Create dashboards
    main_dash = MainDashboard(stdscr)
    signal_dash = SignalDashboard(stdscr)
    perf_dash = PerformanceDashboard(stdscr)
    drive_dash = DriveDashboard(stdscr)

    current_dash = 1

    # History buffers
    throughput_history = [random.randint(0, 100) for _ in range(60)]
    amplitude_history = [random.randint(700, 850) for _ in range(60)]
    jitter_history = [random.randint(10, 30) for _ in range(60)]
    rpm_history = [random.randint(297, 303) for _ in range(60)]
    flux_histogram = [random.randint(100, 10000) for _ in range(32)]

    while True:
        # Generate mock data
        sys_info, usb_stats, signal_stats, pll_stats, drives = generate_mock_data()

        # Update history
        throughput_history.append(random.randint(0, 100))
        throughput_history = throughput_history[-60:]
        amplitude_history.append(random.randint(700, 850))
        amplitude_history = amplitude_history[-60:]
        jitter_history.append(random.randint(10, 30))
        jitter_history = jitter_history[-60:]
        rpm_history.append(random.randint(297, 303))
        rpm_history = rpm_history[-60:]

        # Draw current dashboard
        try:
            if current_dash == 1:
                main_dash.draw(sys_info, usb_stats, signal_stats, pll_stats, drives)
            elif current_dash == 2:
                signal_dash.draw(signal_stats, flux_histogram,
                               amplitude_history, jitter_history)
            elif current_dash == 3:
                fifo_levels = {
                    'rx': random.randint(0, 400),
                    'tx': random.randint(0, 400),
                    'flux': random.randint(0, 3000),
                    'sector': random.randint(0, 200),
                    'rx_hwm': 450,
                    'tx_hwm': 420,
                    'flux_hwm': 3500,
                    'sector_hwm': 230,
                }
                perf_dash.draw(usb_stats, 50, 2500, 320, fifo_levels, throughput_history)
            elif current_dash == 4:
                drive_dash.draw(drives, pll_stats, 200000000, rpm_history)
        except curses.error:
            pass  # Ignore drawing errors at edges

        # Handle input
        try:
            key = stdscr.getch()
            if key == ord('1'):
                current_dash = 1
            elif key == ord('2'):
                current_dash = 2
            elif key == ord('3'):
                current_dash = 3
            elif key == ord('4'):
                current_dash = 4
            elif key == ord('q') or key == ord('Q'):
                break
        except:
            pass

        time.sleep(0.5)


if __name__ == "__main__":
    print("FluxRipper TUI Dashboard Demo")
    print("Press 1-4 to switch views, Q to quit")
    print()
    input("Press Enter to start...")

    curses.wrapper(main)
