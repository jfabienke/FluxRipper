#!/usr/bin/env python3
"""
FluxRipper HDD BIOS ROM Checksum Calculator

Calculates and updates the ROM checksum byte so that all bytes in the ROM
sum to 00h (mod 256), as required by the IBM PC ROM scan.

SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 FluxRipper Project
"""

import sys
import os

def calculate_checksum(data: bytes) -> int:
    """Calculate the sum of all bytes mod 256."""
    return sum(data) & 0xFF

def fix_checksum(rom_path: str) -> bool:
    """
    Read ROM, calculate checksum, and update the last byte so sum = 0.

    Returns True if successful, False on error.
    """
    if not os.path.exists(rom_path):
        print(f"Error: File not found: {rom_path}")
        return False

    with open(rom_path, 'rb') as f:
        data = bytearray(f.read())

    if len(data) < 3:
        print(f"Error: ROM too small ({len(data)} bytes)")
        return False

    # Verify ROM signature
    if data[0] != 0x55 or data[1] != 0xAA:
        print(f"Warning: Invalid ROM signature (got {data[0]:02X} {data[1]:02X}, expected 55 AA)")

    # Calculate current checksum (excluding last byte)
    current_sum = sum(data[:-1]) & 0xFF

    # Calculate required checksum byte (so total sum = 0)
    checksum_byte = (0x100 - current_sum) & 0xFF

    # Update the last byte
    old_byte = data[-1]
    data[-1] = checksum_byte

    # Write back
    with open(rom_path, 'wb') as f:
        f.write(data)

    # Verify
    final_sum = calculate_checksum(data)

    print(f"ROM: {rom_path}")
    print(f"  Size: {len(data)} bytes ({len(data) // 1024}KB)")
    print(f"  Checksum byte: 0x{old_byte:02X} -> 0x{checksum_byte:02X}")
    print(f"  Final sum: 0x{final_sum:02X} {'(OK)' if final_sum == 0 else '(ERROR)'}")

    return final_sum == 0

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <rom_file>")
        print("  Updates ROM checksum byte so all bytes sum to 0x00")
        sys.exit(1)

    success = fix_checksum(sys.argv[1])
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
