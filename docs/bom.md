# FluxRipper Universal Card - Bill of Materials

**Revision:** 1.1
**Date:** 2025-12-07 13:45
**Configuration:** Universal Card (ISA + USB 2.0 HS)
**Target FPGA:** XCSU35P-1LI (Low Power, 0.72V)

---

## Cost Summary

| Category | Component Count | Subtotal |
|----------|-----------------|----------|
| FPGA & Memory | 3 | ~$42.00 |
| USB 2.0 HS Interface | 6 | ~$5.00 |
| Level Shifters & Buffers | 10 | ~$9.70 |
| Power Management | 9 | ~$11.75 |
| Clocking | 1 | ~$1.50 |
| Connectors - Storage | 5 | ~$7.20 |
| Host Interface (ISA) | 0 | $0.00 |
| User Interface | 8 | ~$10.95 |
| Real-Time Clock | 3 | ~$2.00 |
| Passive Components | ~88 | ~$2.16 |
| Mechanical & PCB | 13 | ~$11.80 |
| **Total BOM** | **~104** | **~$104.06** |

*Pricing at qty 100, December 2025. Request distributor quotes for current pricing.*

**Note:** ISA interface uses PCB edge fingers (hard gold plating) - cost included in PCB fabrication.

---

## 1. FPGA & Memory

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| U1 | 1 | Spartan UltraScale+ FPGA | AMD | XCSU35P-1SBVB625I | BGA-625 | DigiKey | $35.00 | $35.00 | XCSU35P-2SBVB625E |
| U2 | 1 | HyperRAM 64Mb (8MB) | Infineon | S27KL0642GABHI020 | FBGA-24 | Mouser | $4.50 | $4.50 | IS66WVH8M8ALL-104NLI |
| U3 | 1 | QSPI Config Flash 128Mb | Winbond | W25Q128JVSIQ | SOIC-8 | DigiKey | $2.50 | $2.50 | IS25LP128-JBLE |

**Subtotal:** ~$42.00

---

## 2. USB 2.0 High-Speed Interface

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| U4 | 1 | USB 2.0 ULPI PHY | Microchip | USB3320C-EZK | QFN-32 | DigiKey | $3.50 | $3.50 | USB3300-EZK |
| U5 | 1 | USB ESD Protection | Nexperia | PRTR5V0U2X | SOT-143B | DigiKey | $0.25 | $0.25 | TPD2E001DRLR |
| J1 | 1 | USB-C Receptacle 16-pin | GCT | USB4110-GF-A | SMD | DigiKey | $0.80 | $0.80 | 10137063-00021LF |
| R_CC1-CC2 | 2 | USB-C CC Pull-down | - | 5.1kΩ 1% | 0402 | DigiKey | $0.01 | $0.02 | - |
| Y2 | 1 | 24 MHz Crystal | Abracon | ABM8-24.000MHZ | 3.2×2.5mm | DigiKey | $0.40 | $0.40 | - |

**Note:** CC1/CC2 pull-downs are **required** for USB-C hosts to provide 5V VBUS power.

**Subtotal:** ~$4.97

---

## 3. Level Shifters & Buffers

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| U10-U13 | 4 | Quad Buffer 3.3V→5V | TI | SN74AHCT125DR | SOIC-14 | DigiKey | $0.45 | $1.80 | 74AHCT125D |
| U14-U15 | 2 | Octal Transceiver 5V→3.3V | TI | SN74LVC245APWR | TSSOP-20 | DigiKey | $0.55 | $1.10 | 74LVC245A |
| U16-U17 | 2 | Quad Diff Line Driver | TI | AM26LS31CDR | SOIC-16 | DigiKey | $1.80 | $3.60 | SN75ALS180 |
| U18-U19 | 2 | Quad Diff Line Receiver | TI | AM26LS32ACDR | SOIC-16 | DigiKey | $1.60 | $3.20 | SN75ALS180 |

**Subtotal:** ~$9.70

---

## 4. Power Management

**CRITICAL:** Spartan UltraScale+ -1LI mode requires specific voltage rails per DS930 Table 2.

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| U20 | 1 | Triple Power Monitor | TI | INA3221AIRGVR | QFN-16 | DigiKey | $3.50 | $3.50 | - |
| U21 | 1 | 3.3V LDO 1A (VCCO_HD) | TI | TLV1117-33IDCYR | SOT-223 | DigiKey | $0.45 | $0.45 | AMS1117-3.3 |
| U22 | 1 | 1.8V LDO 300mA (VCCAUX) | TI | TLV75718PDBVR | SOT-23-5 | DigiKey | $0.45 | $0.45 | AP2112K-1.8 |
| U23 | 1 | 0.85V LDO 500mA (VCCBRAM) | TI | TPS7A2008PDQNR | SON-8 | DigiKey | $1.20 | $1.20 | - |
| U24 | 1 | 0.72V Buck 1A (VCCINT) | TI | TPS562201DDCR | SOT-23-6 | DigiKey | $0.95 | $0.95 | TLV62568DBVR |
| U25 | 1 | 5V Buck 3A (from USB/ISA) | TI | TPS54331DR | SOIC-8 | DigiKey | $1.80 | $1.80 | LM2596S-5.0 |
| U26 | 1 | 12V→24V Boost (8" drives) | TI | TPS55340RTER | QFN-16 | DigiKey | $2.80 | $2.80 | LM2577 |
| F1-F2 | 2 | Polyfuse 1.5A | Littelfuse | 1206L150THYR | 1206 | DigiKey | $0.30 | $0.60 | - |

**Power Rail Summary (DS930 Compliant for -1LI):**
| Rail | Voltage | Purpose | Regulator |
|------|---------|---------|-----------|
| VCCINT | 0.72V | FPGA Core Logic | U24 (Buck) |
| VCCBRAM | 0.85V | Block RAM | U23 (LDO) |
| VCCAUX | 1.8V | Config, MMCM/PLL, JTAG | U22 (LDO) |
| VCCO_HD | 3.3V | HD I/O Banks, USB PHY | U21 (LDO) |

**Subtotal:** ~$11.75

---

## 5. Clocking

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| Y1 | 1 | 25 MHz MEMS Oscillator | SiTime | SIT1533AI-H4-DCC-25.000E | 2.0×1.6mm | DigiKey | $1.50 | $1.50 | DSC1001CI2-025.0000 |

**Subtotal:** ~$1.50

---

## 6. Connectors - Storage Interfaces

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| J3 | 1 | 34-pin Shugart Header (FDD A) | Amphenol | 10134174-134LF | 2.54mm IDC | DigiKey | $1.20 | $1.20 | - |
| J4 | 1 | 34-pin Shugart Header (FDD B) | Amphenol | 10134174-134LF | 2.54mm IDC | DigiKey | $1.20 | $1.20 | - |
| J5 | 1 | 50-pin Apple/Mac Header | Amphenol | 10150176-150LF | 2.54mm IDC | DigiKey | $1.80 | $1.80 | - |
| J10 | 1 | 34-pin ST-506 Control | Amphenol | 10134174-134LF | 2.54mm IDC | DigiKey | $1.20 | $1.20 | - |
| J11-J12 | 2 | 20-pin ST-506 Data | Amphenol | 10120176-020LF | 2.54mm IDC | DigiKey | $0.90 | $1.80 | - |

**Subtotal:** ~$7.20

---

## 7. Host Interface - ISA Edge Fingers

**Note:** The FluxRipper card plugs directly into an ISA slot. No connector components needed—ISA interface is implemented as **PCB edge fingers** with hard gold plating. See Section 11 for PCB fabrication requirements.

| Ref | Qty | Description | Notes |
|-----|-----|-------------|-------|
| - | - | 62-pin ISA edge (8-bit) | PCB edge fingers, 2.54mm pitch |
| - | - | 36-pin ISA extension (16-bit) | PCB edge fingers, 2.54mm pitch |

**Subtotal:** $0.00 (cost included in PCB fabrication)

---

## 8. User Interface Peripherals

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| OLED1 | 1 | 128×64 OLED Display I2C | Winstar | WEA012864DWPP3N00003 | 0.96" | DigiKey | $8.00 | $8.00 | SSD1306 module |
| SW1 | 1 | Rotary Encoder w/ Button | Bourns | PEC11R-4215F-S0024 | 12mm | DigiKey | $1.50 | $1.50 | EC11 |
| J30 | 1 | MicroSD Card Slot | Molex | 104031-0811 | Push-push | DigiKey | $1.20 | $1.20 | DM3AT-SF-PEJM5 |
| LED1-LED5 | 5 | Status LED 0603 (assorted) | - | Various | 0603 | DigiKey | $0.05 | $0.25 | - |

**Subtotal:** ~$10.95

---

## 9. Real-Time Clock

| Ref | Qty | Description | Manufacturer | MPN | Package | Supplier | Unit Cost | Ext Cost | Alt MPN |
|-----|-----|-------------|--------------|-----|---------|----------|-----------|----------|---------|
| U30 | 1 | RTC I2C | NXP | PCF8563T/5,518 | SO-8 | DigiKey | $1.20 | $1.20 | DS1307Z+ |
| BT1 | 1 | CR2032 Holder | Keystone | 3034 | THT | DigiKey | $0.45 | $0.45 | BAT-HLD-001 |
| Y3 | 1 | 32.768 kHz Crystal | Abracon | ABS07-32.768KHZ-7-T | 3.2×1.5mm | DigiKey | $0.35 | $0.35 | - |

**Subtotal:** ~$2.00

---

## 10. Passive Components

| Ref | Qty | Description | Value | Package | Supplier | Unit Cost | Ext Cost |
|-----|-----|-------------|-------|---------|----------|-----------|----------|
| C1-C30 | 30 | Bypass Capacitor | 100nF 16V X7R | 0402 | DigiKey | $0.008 | $0.24 |
| C31-C40 | 10 | Bulk Capacitor | 10µF 16V X5R | 0805 | DigiKey | $0.03 | $0.30 |
| C41-C45 | 5 | FPGA Decoupling | 4.7µF 6.3V X5R | 0402 | DigiKey | $0.02 | $0.10 |
| C46-C50 | 5 | Power Filter | 22µF 25V | 1206 | DigiKey | $0.10 | $0.50 |
| R1-R20 | 20 | Pull-up/Pull-down | 10kΩ 1% | 0402 | DigiKey | $0.004 | $0.08 |
| R21-R30 | 10 | Series Termination | 33Ω 1% | 0402 | DigiKey | $0.004 | $0.04 |
| R31-R35 | 5 | Current Sense Shunt | Various | 2512 | DigiKey | $0.15 | $0.75 |
| L1-L3 | 3 | Ferrite Bead | 600Ω@100MHz | 0603 | DigiKey | $0.05 | $0.15 |

**Subtotal:** ~$2.16

---

## 11. Mechanical & PCB Fabrication

| Ref | Qty | Description | Manufacturer | MPN | Supplier | Unit Cost | Ext Cost |
|-----|-----|-------------|--------------|-----|----------|-----------|----------|
| PCB | 1 | 4-layer PCB 100×160mm | JLCPCB | - | JLCPCB | $10.00 | $10.00 |
| HDR1-HDR2 | 2 | 2×20 GPIO Header (RPi compat) | - | - | DigiKey | $0.50 | $1.00 |
| TP1-TP10 | 10 | Test Point | Keystone | 5000 | DigiKey | $0.08 | $0.80 |

**PCB Fabrication Requirements (for ISA edge connector):**
- **Hard Gold Plating:** 30µ" (0.76µm) minimum on edge fingers
- **Beveled Edge:** 30° bevel on card edge for smooth insertion
- **Edge Finger Pitch:** 2.54mm (0.1") standard ISA spacing
- **Finger Length:** 6.35mm minimum contact area

**Subtotal:** ~$11.80

---

## Notes

1. **Alternates:** Alt MPN column lists drop-in replacements where available
2. **Pricing:** Estimates based on qty 100 from DigiKey/Mouser, December 2025
3. **FPGA Variant:** -1LI (0.72V low power) is recommended; -2E (0.85V) is footprint-compatible alternate
4. **Assembly:** SMT assembly available via JLCPCB/PCBWay (~$50 for qty 5)
5. **FPGA Pricing:** AMD pricing varies; contact local AMD rep for volume quotes
6. **HyperRAM:** S27KL0642 (3.0V) selected for simpler power (shares 3.3V rail). For higher bandwidth, use S27KS0642 (1.8V) from VCCAUX rail.
7. **ISA Edge Fingers:** PCB requires hard gold plating (30µ" min) and 30° beveling on card edge
8. **VCCINT Buck Regulator:** Critical - do NOT use LDO for 0.72V core; thermal dissipation would exceed 2W
9. **USB-C CC Resistors:** 5.1kΩ pull-downs on CC1/CC2 are mandatory for USB-C host power delivery
10. **Config Flash Bank:** W25Q128JVSIQ (3.3V) must connect to FPGA Bank 0 configured for 3.3V VCCO

---

## Power Budget

**DS930-Compliant Power Tree for -1LI Mode:**

| Rail | Voltage | Max Current | Power | Source | Purpose |
|------|---------|-------------|-------|--------|---------|
| VCCINT | 0.72V | 800mA | 0.58W | U24 (TPS562201 Buck) | FPGA Core Logic |
| VCCBRAM | 0.85V | 200mA | 0.17W | U23 (TPS7A2008 LDO) | Block RAM |
| VCCAUX | 1.8V | 150mA | 0.27W | U22 (TLV75718 LDO) | Config, MMCM/PLL, JTAG |
| VCCO_HD | 3.3V | 400mA | 1.32W | U21 (TLV1117-33 LDO) | HD I/O Banks |
| USB PHY | 3.3V | 100mA | 0.33W | U21 (shared) | USB3320C |
| 5V Rail | 5.0V | 200mA | 1.00W | U25 (TPS54331 Buck) | Level Shifters, Legacy |
| **Total (no drives)** | | | **~3.7W** | |

---

## Revision History

| Date | Rev | Changes |
|------|-----|---------|
| 2025-12-07 | 1.0 | Initial BOM for Universal Card (ISA + USB 2.0 HS) |
| 2025-12-07 | 1.1 | **Critical fixes:** Added 1.8V (VCCAUX) and 0.85V (VCCBRAM) rails per DS930; replaced 0.72V LDO with buck regulator for thermal safety; removed ISA receptacles (now PCB edge fingers with gold plating); added USB-C CC pull-down resistors |
