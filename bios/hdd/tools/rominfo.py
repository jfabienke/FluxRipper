#!/usr/bin/env python3
"""
FluxRipper HDD BIOS ROM Information Dumper

Displays information about an Option ROM including:
- Size and checksum
- ROM signature
- PnP header (if present)
- Entry points

SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 FluxRipper Project
"""

import sys
import os
import struct

def read_string(data: bytes, offset: int, max_len: int = 32) -> str:
    """Read a null-terminated or fixed-length ASCII string."""
    end = offset + max_len
    result = []
    for i in range(offset, min(end, len(data))):
        if data[i] == 0:
            break
        if 0x20 <= data[i] <= 0x7E:
            result.append(chr(data[i]))
        else:
            break
    return ''.join(result)

def dump_rom_info(rom_path: str) -> bool:
    """Display ROM information."""
    if not os.path.exists(rom_path):
        print(f"Error: File not found: {rom_path}")
        return False

    with open(rom_path, 'rb') as f:
        data = f.read()

    if len(data) < 3:
        print(f"Error: ROM too small ({len(data)} bytes)")
        return False

    print("=" * 60)
    print(f"ROM: {rom_path}")
    print("=" * 60)

    # Basic info
    size_kb = len(data) // 1024
    checksum = sum(data) & 0xFF
    print(f"Size:     {len(data)} bytes ({size_kb}KB)")
    print(f"Checksum: 0x{checksum:02X} {'(VALID)' if checksum == 0 else '(INVALID)'}")

    # ROM signature
    sig = (data[0] << 8) | data[1]
    print(f"\nSignature: 0x{sig:04X} {'(VALID)' if sig == 0x55AA else '(INVALID)'}")

    # Size in header (in 512-byte blocks)
    size_blocks = data[2]
    declared_size = size_blocks * 512
    print(f"Declared:  {size_blocks} blocks = {declared_size} bytes ({declared_size // 1024}KB)")

    # Entry point (offset 3)
    if len(data) >= 6:
        # Could be a JMP instruction
        if data[3] == 0xEB:  # Short JMP
            target = 3 + 2 + struct.unpack('<b', bytes([data[4]]))[0]
            print(f"Entry:     0x{target:04X} (short JMP)")
        elif data[3] == 0xE9:  # Near JMP
            if len(data) >= 6:
                offset = struct.unpack('<h', data[4:6])[0]
                target = 3 + 3 + offset
                print(f"Entry:     0x{target:04X} (near JMP)")
        else:
            print(f"Entry:     0x0003 (immediate)")

    # Look for PnP header
    pnp_offset = None
    for i in range(0, min(len(data) - 4, 256), 16):
        if data[i:i+4] == b'$PnP':
            pnp_offset = i
            break

    if pnp_offset is not None:
        print(f"\nPnP Header at 0x{pnp_offset:04X}:")
        if len(data) >= pnp_offset + 26:
            pnp = data[pnp_offset:pnp_offset + 32]
            version = pnp[4]
            print(f"  Version:      {version >> 4}.{version & 0xF}")
            print(f"  Header Len:   {pnp[5]} bytes")

            device_id = struct.unpack('>I', pnp[8:12])[0]
            vendor = ''.join([chr(((device_id >> 26) & 0x1F) + 0x40),
                              chr(((device_id >> 21) & 0x1F) + 0x40),
                              chr(((device_id >> 16) & 0x1F) + 0x40)])
            product = (device_id >> 4) & 0xFFF
            rev = device_id & 0xF
            print(f"  Device ID:    {vendor}{product:03X}{rev:X}")

            mfg_str = struct.unpack('<H', pnp[16:18])[0]
            if mfg_str != 0:
                mfg = read_string(data, mfg_str)
                print(f"  Manufacturer: {mfg}")

            prod_str = struct.unpack('<H', pnp[18:20])[0]
            if prod_str != 0:
                prod = read_string(data, prod_str)
                print(f"  Product:      {prod}")
    else:
        print("\nNo PnP header found (legacy ROM)")

    # Look for identifying strings
    print("\nStrings found:")
    for pattern in [b'FluxRipper', b'WD100', b'ST-506', b'ESDI', b'Copyright']:
        idx = data.find(pattern)
        if idx != -1:
            s = read_string(data, idx, 64)
            print(f"  0x{idx:04X}: {s[:60]}")

    print("=" * 60)
    return True

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <rom_file>")
        print("  Displays information about an Option ROM")
        sys.exit(1)

    success = dump_rom_info(sys.argv[1])
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
