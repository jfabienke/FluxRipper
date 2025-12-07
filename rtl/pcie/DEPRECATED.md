# PCIe Module - DEPRECATED

**Date:** 2025-12-07

## Status: NOT USED

These PCIe RTL files are **deprecated and not part of the FluxRipper build**.

## Reason

The target FPGA (AMD Spartan UltraScale+ **XCSU35P**) has **zero GTH transceivers**,
making PCIe impossible on this device.

## Alternative

USB 2.0 High-Speed (480 Mbps) via ULPI PHY is the primary high-speed host interface.
See `rtl/usb/` for the active USB stack.

## Files in this Directory

| File | Description | Status |
|------|-------------|--------|
| pcie_axi_bridge.v | AXI-to-PCIe bridge | Unused |
| pcie_bar_decode.v | BAR address decoder | Unused |
| pcie_cfg_space.v | Configuration space | Unused |
| pcie_dma_engine.v | DMA engine | Unused |
| pcie_msi_ctrl.v | MSI/MSI-X controller | Unused |

## If You Need PCIe

Upgrade to **XCSU50P** (same package, 4 GTH transceivers) or larger device.
