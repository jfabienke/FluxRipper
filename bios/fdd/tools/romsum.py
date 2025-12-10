#!/usr/bin/env python3
"""
FluxRipper FDD BIOS - ROM Checksum Tool

Calculates and fixes the checksum byte for ISA Option ROMs.
Option ROMs must have all bytes sum to 0 (mod 256).

Usage:
    romsum.py <romfile>          - Fix checksum in place
    romsum.py --check <romfile>  - Verify checksum
    romsum.py --info <romfile>   - Show ROM information

SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 FluxRipper Project
"""

import sys
import argparse


def read_rom(filename):
    """Read ROM file into bytearray."""
    with open(filename, 'rb') as f:
        return bytearray(f.read())


def write_rom(filename, data):
    """Write bytearray to ROM file."""
    with open(filename, 'wb') as f:
        f.write(data)


def calculate_checksum(data):
    """Calculate current checksum (sum of all bytes mod 256)."""
    return sum(data) & 0xFF


def fix_checksum(data):
    """
    Fix checksum by adjusting the last byte.
    Returns the adjustment value.
    """
    # Calculate current sum excluding last byte
    current_sum = sum(data[:-1]) & 0xFF

    # Calculate required last byte to make total sum 0
    required = (256 - current_sum) & 0xFF

    # Store in last byte
    data[-1] = required

    return required


def verify_signature(data):
    """Verify ROM signature (55 AA)."""
    if len(data) < 3:
        return False
    return data[0] == 0x55 and data[1] == 0xAA


def get_rom_size(data):
    """Get declared ROM size in bytes."""
    if len(data) < 3:
        return 0
    return data[2] * 512


def show_info(filename, data):
    """Display ROM information."""
    print(f"ROM File: {filename}")
    print(f"File Size: {len(data)} bytes ({len(data) // 1024}KB)")

    if verify_signature(data):
        print("Signature: Valid (55 AA)")
        declared = get_rom_size(data)
        print(f"Declared Size: {declared} bytes ({declared // 1024}KB)")
    else:
        print("Signature: INVALID (expected 55 AA)")

    checksum = calculate_checksum(data)
    print(f"Checksum: {'VALID (0x00)' if checksum == 0 else f'INVALID (0x{checksum:02X})'}")

    # Show entry point
    if len(data) >= 6:
        if data[3] == 0xE9:  # JMP near
            offset = data[4] | (data[5] << 8)
            target = 6 + offset
            if offset & 0x8000:  # Signed
                target = 6 - (0x10000 - offset)
            print(f"Entry Point: JMP to 0x{target:04X}")
        elif data[3] == 0xEB:  # JMP short
            offset = data[4]
            if offset & 0x80:
                offset -= 256
            target = 5 + offset
            print(f"Entry Point: JMP short to 0x{target:04X}")

    # Look for PnP header
    for i in range(0, min(len(data), 256)):
        if data[i:i+4] == b'$PnP':
            print(f"PnP Header: Found at offset 0x{i:04X}")
            break
    else:
        print("PnP Header: Not found")

    # Calculate code size (everything before FF padding)
    code_end = len(data) - 1
    while code_end > 0 and data[code_end-1] == 0xFF:
        code_end -= 1
    code_size = code_end
    utilization = (code_size / len(data)) * 100
    print(f"Code Size: {code_size} bytes ({utilization:.1f}% utilized)")


def main():
    parser = argparse.ArgumentParser(
        description='FluxRipper FDD BIOS ROM Checksum Tool'
    )
    parser.add_argument('romfile', help='ROM file to process')
    parser.add_argument('--check', action='store_true',
                       help='Verify checksum without modifying')
    parser.add_argument('--info', action='store_true',
                       help='Show ROM information')

    args = parser.parse_args()

    try:
        data = read_rom(args.romfile)
    except FileNotFoundError:
        print(f"Error: File not found: {args.romfile}", file=sys.stderr)
        return 1
    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        return 1

    if args.info:
        show_info(args.romfile, data)
        return 0

    if args.check:
        checksum = calculate_checksum(data)
        if checksum == 0:
            print("VALID")
            return 0
        else:
            print(f"INVALID (sum=0x{checksum:02X})")
            return 1

    # Fix checksum
    if not verify_signature(data):
        print("Warning: ROM signature invalid (55 AA not found)", file=sys.stderr)

    old_last = data[-1]
    new_last = fix_checksum(data)

    try:
        write_rom(args.romfile, data)
    except IOError as e:
        print(f"Error writing file: {e}", file=sys.stderr)
        return 1

    print(f"Checksum fixed: 0x{old_last:02X} -> 0x{new_last:02X}")

    # Verify
    checksum = calculate_checksum(data)
    if checksum != 0:
        print(f"Error: Verification failed (sum=0x{checksum:02X})", file=sys.stderr)
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
