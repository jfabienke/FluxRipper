# FluxRipper Power Monitoring Subsystem

*Created: 2025-12-04 10:15*
*Updated: 2025-12-04 12:30*

## Overview

The FluxRipper Universal Card includes comprehensive power monitoring using Texas Instruments INA3221 triple-channel current/voltage monitors plus DC-DC converter instrumentation. This enables real-time measurement of power consumption across all system rails, connected drives, and converter efficiency.

## Hardware Architecture

### Power Monitoring ICs

| IC | I2C Address | Channels | Purpose |
|----|-------------|----------|---------|
| U30 (INA3221-A) | 0x40 | 3 | Drive power (5V/12V for drives 0-1) |
| U31 (INA3221-B) | 0x41 | 3 | Drive power (5V/12V for drives 2-3, HDD 12V) |
| U32 (INA3221-C) | 0x42 | 3 | System rails (3.3V FPGA, 5V logic, 1.0V core) |
| U33 (INA3221-D) | 0x43 | 3 | 8" drive rails (24V, 5V) + auxiliary |

### Channel Assignments

```
INA3221-A (0x40) - Floppy Interface A
├── CH1: +5V Drive 0/1 supply
├── CH2: +12V Drive 0/1 supply
└── CH3: +5V Floppy logic (active termination, buffers)

INA3221-B (0x41) - Floppy Interface B + HDD
├── CH1: +5V Drive 2/3 supply
├── CH2: +12V Drive 2/3 supply
└── CH3: +12V HDD supply (ST-506/ESDI motor)

INA3221-C (0x42) - System Rails
├── CH1: +3.3V FPGA I/O (LVCMOS33)
├── CH2: +5V Logic (level shifters, RS-422)
└── CH3: +1.0V FPGA Core (Spartan UltraScale+)

INA3221-D (0x43) - 8" Floppy / Auxiliary
├── CH1: +24V 8-inch floppy drive supply
├── CH2: +5V 8-inch floppy logic
└── CH3: Auxiliary / expansion rail
```

### Shunt Resistor Selection

| Rail | Expected Current | Shunt Value | Max Current | Resolution |
|------|------------------|-------------|-------------|------------|
| 5V Drive | 100-500mA | 50mΩ | 3.28A | 1.25mA |
| 12V Drive | 200-1500mA | 20mΩ | 8.19A | 3.125mA |
| 12V HDD | 500-2000mA | 10mΩ | 16.38A | 6.25mA |
| 24V 8" Drive | 100-800mA | 10mΩ | 16.38A | 6.25mA |
| 3.3V FPGA | 100-400mA | 100mΩ | 1.64A | 0.625mA |
| 5V Logic | 50-200mA | 100mΩ | 1.64A | 0.625mA |
| 1.0V Core | 200-800mA | 50mΩ | 3.28A | 1.25mA |

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     FluxRipper Power Monitoring                             │
│                                                                             │
│  ┌────────────────┐                                                         │
│  │   MicroBlaze V │◄──── AXI4-Lite ────┐                                    │
│  │    (RISC-V)    │                    │                                    │
│  └────────────────┘                    │                                    │
│         │                              ▼                                    │
│         │                  ┌──────────────────────┐                         │
│         │ GPIO             │   AXI I2C Master     │                         │
│         ▼                  │   (100/400 kHz)      │                         │
│  ┌──────────────┐          └──────────┬───────────┘                         │
│  │ DC-DC Status │                     │                                     │
│  │  PGOOD/FAULT │         ┌───────────┼───────────┬────────────┐            │
│  │   EN/MODE    │         │           │           │            │            │
│  └──────┬───────┘  ┌──────▼──────┐ ┌──▼───────┐ ┌─▼────────┐ ┌─▼────────┐   │
│         │          │ INA3221-A   │ │INA3221-B │ │INA3221-C │ │INA3221-D │   │
│         │          │ (0x40)      │ │(0x41)    │ │(0x42)    │ │(0x43)    │   │
│         │          │ Drv 0/1     │ │Drv 2/3   │ │System    │ │8" / Aux  │   │
│         │          └──────┬──────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘   │
│         │                 │             │            │            │         │
└─────────┼─────────────────┼─────────────┼────────────┼────────────┼─────────┘
          │                 │             │            │            │
    ┌─────▼─────────────────▼─────────────▼────────────▼────────────▼─────────┐
    │                       POWER DISTRIBUTION                                │
    │                                                                         │
    │  ┌───────────┐   ┌──────────┐   ┌────────────┐   ┌───────────────────┐  │
    │  │ 24V Boost │   │ 5V Buck  │   │  3.3V Buck │   │  1.0V Buck        │  │
    │  │ 12V→24V   │   │ 12V→5V   │   │ 5V→3.3V    │   │  3.3V→1.0V        │  │
    │  │ (8" drv)  │   │ (drives) │   │ (FPGA IO)  │   │  (FPGA core)      │  │
    │  └─────┬─────┘   └─────┬────┘   └─────┬──────┘   └────────┬──────────┘  │
    │       │                │              │                   │             │
    │       ▼                ▼              ▼                   ▼             │
    │   8" Floppy       Floppy/HDD      FPGA I/O            FPGA Core         │
    │    Drives           Drives          Banks               Logic           │
    └─────────────────────────────────────────────────────────────────────────┘
```

## DC-DC Converter Instrumentation

### Converter Overview

| Converter | Type | Input | Output | Purpose |
|-----------|------|-------|--------|---------|
| 24V Boost | Boost | 12V | 24V | 8" floppy drive motors |
| 5V Buck | Buck | 12V | 5V | Floppy/HDD drive logic |
| 3.3V Buck | Buck | 5V | 3.3V | FPGA I/O banks |
| 1.0V Buck | Buck | 3.3V | 1.0V | FPGA core logic |

### GPIO Signal Mapping

| Signal | GPIO Bit | Direction | Description |
|--------|----------|-----------|-------------|
| DCDC_24V_PGOOD | GPIO2[0] | Input | 24V boost power good |
| DCDC_24V_ENABLE | GPIO2[1] | Output | 24V boost enable |
| DCDC_24V_FAULT | GPIO2[2] | Input | 24V boost fault |
| DCDC_5V_PGOOD | GPIO2[4] | Input | 5V buck power good |
| DCDC_5V_ENABLE | GPIO2[5] | Output | 5V buck enable |
| DCDC_5V_FAULT | GPIO2[6] | Input | 5V buck fault |
| DCDC_5V_MODE | GPIO2[7] | Output | 5V mode (0=auto, 1=PWM) |
| DCDC_3V3_PGOOD | GPIO2[8] | Input | 3.3V buck power good |
| DCDC_3V3_ENABLE | GPIO2[9] | Output | 3.3V buck enable |
| DCDC_3V3_FAULT | GPIO2[10] | Input | 3.3V buck fault |
| DCDC_1V0_PGOOD | GPIO2[12] | Input | 1.0V buck power good |
| DCDC_1V0_ENABLE | GPIO2[13] | Output | 1.0V buck enable |
| DCDC_1V0_FAULT | GPIO2[14] | Input | 1.0V buck fault |

### Instrumentation Capabilities

| Metric | Source | Notes |
|--------|--------|-------|
| Power Good | GPIO | Each converter reports regulation status |
| Enable State | GPIO | Read back actual enable state |
| Fault Status | GPIO | OVP, OCP, OTP combined fault |
| Output Voltage | INA3221 | Actual measured Vout via power monitors |
| Input Voltage | INA3221 | Calculated from upstream rail |
| Efficiency | Calculated | Pout/Pin from INA3221 measurements |
| Operating Mode | GPIO | 5V buck: auto PFM/PWM or forced PWM |

### Efficiency Calculation

The system calculates real-time efficiency for each converter using INA3221 measurements:

```
Input Rail    →  DC-DC  →  Output Rail
(measured)                  (measured)

Efficiency = (Vout × Iout) / (Vin × Iin) × 100%
```

| Converter | Input Rail | Output Rail |
|-----------|------------|-------------|
| 24V Boost | 12V HDD | 24V 8-inch |
| 5V Buck | 12V Drv 0/1 | 5V Drv 0/1 |
| 3.3V Buck | 5V Logic | 3.3V IO |
| 1.0V Buck | 3.3V IO | 1.0V Core |

## INA3221 Register Map

### Key Registers (per channel)

| Register | Address | Description |
|----------|---------|-------------|
| Configuration | 0x00 | Operating mode, averaging, conversion time |
| CH1 Shunt Voltage | 0x01 | Channel 1 shunt voltage (current) |
| CH1 Bus Voltage | 0x02 | Channel 1 bus voltage |
| CH2 Shunt Voltage | 0x03 | Channel 2 shunt voltage |
| CH2 Bus Voltage | 0x04 | Channel 2 bus voltage |
| CH3 Shunt Voltage | 0x05 | Channel 3 shunt voltage |
| CH3 Bus Voltage | 0x06 | Channel 3 bus voltage |
| Manufacturer ID | 0xFE | Should read 0x5449 ("TI") |
| Die ID | 0xFF | Should read 0x3220 |

### Configuration Register (0x00)

```
Bit 15:   RST     - Reset (write 1 to reset)
Bit 14:   CH1_EN  - Channel 1 enable
Bit 13:   CH2_EN  - Channel 2 enable
Bit 12:   CH3_EN  - Channel 3 enable
Bit 11-9: AVG     - Averaging mode (0=1, 1=4, 2=16, 3=64, 4=128, 5=256, 6=512, 7=1024)
Bit 8-6:  VBUS_CT - Bus voltage conversion time
Bit 5-3:  VSH_CT  - Shunt voltage conversion time
Bit 2-0:  MODE    - Operating mode (7=continuous shunt+bus)
```

### Voltage Calculations

**Shunt Voltage (Current):**
```
Shunt_Voltage_mV = Register_Value * 40µV / 1000
Current_mA = Shunt_Voltage_mV / Shunt_Resistance_mΩ
```

**Bus Voltage:**
```
Bus_Voltage_V = Register_Value * 8mV / 1000
```

**Power:**
```
Power_mW = Bus_Voltage_V * Current_mA
```

## Memory Map

### I2C Controller Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | I2C_CTRL | R/W | Control register |
| 0x04 | I2C_STATUS | R | Status register |
| 0x08 | I2C_ADDR | R/W | Slave address (7-bit) |
| 0x0C | I2C_TX_DATA | W | Transmit data |
| 0x10 | I2C_RX_DATA | R | Receive data |
| 0x14 | I2C_PRESCALE | R/W | Clock prescaler |
| 0x18 | I2C_CMD | W | Command register |

### Power Monitor Registers (Cached/Processed)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | PMU_CTRL | R/W | PMU control (enable, scan rate) |
| 0x04 | PMU_STATUS | R | PMU status (ready, error) |
| 0x10 | RAIL_5V_DRV01 | R | 5V Drive 0/1: [31:16]=mV, [15:0]=mA |
| 0x14 | RAIL_12V_DRV01 | R | 12V Drive 0/1: [31:16]=mV, [15:0]=mA |
| 0x18 | RAIL_5V_DRV23 | R | 5V Drive 2/3: [31:16]=mV, [15:0]=mA |
| 0x1C | RAIL_12V_DRV23 | R | 12V Drive 2/3: [31:16]=mV, [15:0]=mA |
| 0x20 | RAIL_12V_HDD | R | 12V HDD: [31:16]=mV, [15:0]=mA |
| 0x24 | RAIL_3V3_IO | R | 3.3V FPGA I/O: [31:16]=mV, [15:0]=mA |
| 0x28 | RAIL_5V_LOGIC | R | 5V Logic: [31:16]=mV, [15:0]=mA |
| 0x2C | RAIL_1V0_CORE | R | 1.0V Core: [31:16]=mV, [15:0]=mA |
| 0x30 | RAIL_24V_8INCH | R | 24V 8" drive: [31:16]=mV, [15:0]=mA |
| 0x34 | RAIL_5V_8INCH | R | 5V 8" drive: [31:16]=mV, [15:0]=mA |
| 0x38 | RAIL_AUX | R | Auxiliary: [31:16]=mV, [15:0]=mA |
| 0x40 | POWER_TOTAL | R | Total system power in mW |
| 0x44 | POWER_DRIVES | R | Total drive power in mW |

## Firmware API

### Initialization

```c
int pmu_init(void);                    // Initialize I2C and detect INA3221s
int ina3221_probe(uint8_t addr);       // Probe for INA3221 at address
int dcdc_gpio_init(void);              // Initialize DC-DC GPIO signals
```

### Rail Reading Functions

```c
// Read individual rail
int pmu_read_rail(pmu_rail_t rail, pmu_reading_t *reading);

// Read all rails
int pmu_read_all(pmu_system_t *system);

// Get total power
uint32_t pmu_get_total_power_mw(void);
uint32_t pmu_get_drive_power_mw(void);
```

### DC-DC Converter Functions

```c
// Read converter status
int dcdc_read_status(dcdc_id_t id, dcdc_status_t *status);
int dcdc_read_all(dcdc_status_t statuses[DCDC_COUNT]);

// Control converters
int dcdc_set_enable(dcdc_id_t id, bool enable);

// Status checks
bool dcdc_all_pgood(void);
uint8_t dcdc_check_faults(void);

// Information
const char *dcdc_name(dcdc_id_t id);
void dcdc_get_specs(dcdc_id_t id, uint16_t *vin_mv, uint16_t *vout_mv);
```

### Data Structures

```c
typedef enum {
    PMU_RAIL_5V_DRV01 = 0,
    PMU_RAIL_12V_DRV01,
    PMU_RAIL_5V_LOGIC_A,
    PMU_RAIL_5V_DRV23,
    PMU_RAIL_12V_DRV23,
    PMU_RAIL_12V_HDD,
    PMU_RAIL_3V3_IO,
    PMU_RAIL_5V_LOGIC,
    PMU_RAIL_1V0_CORE,
    PMU_RAIL_24V_8INCH,
    PMU_RAIL_5V_8INCH,
    PMU_RAIL_AUX,
    PMU_RAIL_COUNT
} pmu_rail_t;

typedef struct {
    uint16_t voltage_mv;      // Bus voltage in mV
    int16_t  current_ma;      // Current in mA (signed for bidirectional)
    uint16_t power_mw;        // Power in mW
    uint8_t  valid;           // Reading is valid
    uint8_t  alert;           // Alert condition active
} pmu_reading_t;

typedef enum {
    DCDC_24V_BOOST = 0,       // 12V → 24V boost for 8" drives
    DCDC_5V_BUCK,             // 12V → 5V buck for drives
    DCDC_3V3_BUCK,            // 5V → 3.3V buck for FPGA I/O
    DCDC_1V0_BUCK,            // 3.3V → 1.0V buck for FPGA core
    DCDC_COUNT
} dcdc_id_t;

typedef struct {
    uint8_t  power_good;      // PGOOD signal state
    uint8_t  enabled;         // Enable state
    uint8_t  fault;           // Fault condition
    uint8_t  mode;            // Operating mode (PWM/PFM/etc)
    uint16_t vin_mv;          // Input voltage (millivolts)
    uint16_t vout_mv;         // Output voltage (millivolts)
    int8_t   temp_c;          // Temperature (-128 = not available)
    uint8_t  efficiency;      // Efficiency % (0-100)
} dcdc_status_t;

typedef struct {
    pmu_reading_t rails[PMU_RAIL_COUNT];
    dcdc_status_t converters[DCDC_COUNT];
    uint32_t total_power_mw;
    uint32_t drive_power_mw;
    uint32_t system_power_mw;
    uint8_t  ina3221_present[4];
} pmu_system_t;
```

## CLI Commands

```
power status              Show all rails and DC-DC converters
power rail <name>         Show specific rail details
power dcdc                Show DC-DC converter status
power dcdc enable <name>  Enable converter (24v, 5v, 3v3, 1v0)
power dcdc disable <name> Disable converter
power total               Show total power consumption
power init                Re-initialize power monitoring
```

### Example Output

```
FluxRipper> power status

Power Rails Status
=======================================================
  Rail           Voltage   Current   Power     Status
-------------------------------------------------------
  5V Drv 0/1      5.02V     312mA    1.57W     OK
  12V Drv 0/1    12.08V     890mA   10.78W     ACTIVE
  5V Logic A      5.01V      85mA    0.43W     OK
  5V Drv 2/3      5.01V       0mA    0.00W     IDLE
  12V Drv 2/3    11.95V      45mA    0.54W     IDLE
  12V HDD        12.12V    1250mA   15.15W     ACTIVE
  3.3V IO         3.31V     187mA    0.62W     OK
  5V Logic        5.04V      95mA    0.48W     OK
  1.0V Core       1.01V     425mA    0.43W     OK
  24V 8-inch     24.02V     320mA    7.69W     ACTIVE
  5V 8-inch       5.00V     180mA    0.90W     OK
  Auxiliary       5.01V       0mA    0.00W     IDLE
-------------------------------------------------------
  Drive Power:  35.73W
  System Power:  1.53W
  Total Power:  37.26W
=======================================================

Power Monitor ICs: [A:0x40] [B:0x41] [C:0x42] [D:0x43]

DC-DC Converters:
  Converter     Vin      Vout     Eff    EN   PGOOD  FAULT
  ---------------------------------------------------------
  24V Boost    12.00V   24.02V    91%   ON     OK    --
  5V Buck      12.00V    5.02V    88%   ON     OK    --
  3.3V Buck     5.00V    3.31V    92%   ON     OK    --
  1.0V Buck     3.30V    1.01V    85%   ON     OK    --
```

### DC-DC Detailed Status

```
FluxRipper> power dcdc

DC-DC Converter Status
===========================================================
  Converter     Type   Vin      Vout     Eff    Status
-----------------------------------------------------------
  24V Boost    Boost  12.00V   24.02V    91%   OK
  5V Buck      Buck   12.00V    5.02V    88%   OK
  3.3V Buck    Buck    5.00V    3.31V    92%   OK
  1.0V Buck    Buck    3.30V    1.01V    85%   OK
-----------------------------------------------------------
All enabled converters: POWER GOOD
```

## Alert Thresholds

| Rail | Warning | Critical | Shutdown |
|------|---------|----------|----------|
| 5V Drive | >600mA | >800mA | >1000mA |
| 12V Drive | >1200mA | >1500mA | >2000mA |
| 12V HDD | >1800mA | >2200mA | >2500mA |
| 24V 8" Drive | >600mA | >800mA | >1000mA |
| 3.3V FPGA | >350mA | >400mA | >500mA |
| 5V Logic | >180mA | >220mA | >300mA |
| 1.0V Core | >700mA | >850mA | >1000mA |

## Under/Over Voltage Protection

| Rail | Min | Nominal | Max |
|------|-----|---------|-----|
| 5V | 4.75V | 5.0V | 5.25V |
| 12V | 11.4V | 12.0V | 12.6V |
| 24V | 22.8V | 24.0V | 25.2V |
| 3.3V | 3.14V | 3.3V | 3.47V |
| 1.0V | 0.95V | 1.0V | 1.05V |

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Hardware spec | ✅ Complete | INA3221 A-D placement defined |
| I2C RTL | ✅ Complete | AXI-Lite I2C master |
| PMU HAL | ✅ Complete | C driver for INA3221 |
| DC-DC GPIO | ✅ Complete | PGOOD/FAULT/ENABLE signals |
| DC-DC HAL | ✅ Complete | Status reading, enable control |
| CLI commands | ✅ Complete | power status/rail/dcdc/total/init |
| Alert system | 📋 Planned | Interrupt-driven alerts |
| Power logging | 📋 Planned | Historical power data |
