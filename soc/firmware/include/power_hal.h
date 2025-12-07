/**
 * FluxRipper Power Monitoring HAL
 *
 * Driver for INA3221 triple-channel power monitors.
 * Provides voltage, current, and power readings for all system rails.
 *
 * Supports 6 drive connectors (4 FDD + 2 HDD) with per-connector monitoring.
 * Uses 6x INA3221 across 2 I2C buses for 18 monitoring channels.
 *
 * Created: 2025-12-04 10:45
 * Updated: 2025-12-07 10:50 - Expanded to 6-connector architecture
 */

#ifndef POWER_HAL_H
#define POWER_HAL_H

#include <stdint.h>
#include <stdbool.h>
#include "platform.h"

/*============================================================================
 * I2C Controller Registers (Dual I2C Bus)
 *============================================================================*/

/* I2C Bus 0: FDD power monitoring (INA3221 A, B, C) */
#define I2C0_CTRL        (*(volatile uint32_t *)(I2C0_BASE + 0x00))
#define I2C0_STATUS      (*(volatile uint32_t *)(I2C0_BASE + 0x04))
#define I2C0_ADDR        (*(volatile uint32_t *)(I2C0_BASE + 0x08))
#define I2C0_TX_DATA     (*(volatile uint32_t *)(I2C0_BASE + 0x0C))
#define I2C0_RX_DATA     (*(volatile uint32_t *)(I2C0_BASE + 0x10))
#define I2C0_PRESCALE    (*(volatile uint32_t *)(I2C0_BASE + 0x14))
#define I2C0_CMD         (*(volatile uint32_t *)(I2C0_BASE + 0x18))

/* I2C Bus 1: HDD + System power monitoring (INA3221 D, E, F) */
#define I2C1_CTRL        (*(volatile uint32_t *)(I2C1_BASE + 0x00))
#define I2C1_STATUS      (*(volatile uint32_t *)(I2C1_BASE + 0x04))
#define I2C1_ADDR        (*(volatile uint32_t *)(I2C1_BASE + 0x08))
#define I2C1_TX_DATA     (*(volatile uint32_t *)(I2C1_BASE + 0x0C))
#define I2C1_RX_DATA     (*(volatile uint32_t *)(I2C1_BASE + 0x10))
#define I2C1_PRESCALE    (*(volatile uint32_t *)(I2C1_BASE + 0x14))
#define I2C1_CMD         (*(volatile uint32_t *)(I2C1_BASE + 0x18))

/* Legacy single-bus compatibility */
#define I2C_CTRL        I2C0_CTRL
#define I2C_STATUS      I2C0_STATUS
#define I2C_ADDR        I2C0_ADDR
#define I2C_TX_DATA     I2C0_TX_DATA
#define I2C_RX_DATA     I2C0_RX_DATA
#define I2C_PRESCALE    I2C0_PRESCALE
#define I2C_CMD         I2C0_CMD

/* I2C Control Register bits */
#define I2C_CTRL_ENABLE     (1 << 0)
#define I2C_CTRL_IE         (1 << 1)
#define I2C_CTRL_FAST_MODE  (1 << 2)

/* I2C Status Register bits */
#define I2C_STAT_BUSY       (1 << 0)
#define I2C_STAT_ACK        (1 << 1)
#define I2C_STAT_ERROR      (1 << 2)
#define I2C_STAT_TX_EMPTY   (1 << 3)
#define I2C_STAT_RX_VALID   (1 << 4)
#define I2C_STAT_ARB_LOST   (1 << 5)

/* I2C Commands */
#define I2C_CMD_NOP         0
#define I2C_CMD_START       1
#define I2C_CMD_STOP        2
#define I2C_CMD_WRITE       3
#define I2C_CMD_READ_ACK    4
#define I2C_CMD_READ_NACK   5

/*============================================================================
 * INA3221 Definitions (6x INA3221 across 2 I2C buses)
 *============================================================================*/

/* I2C Bus 0 Addresses (FDD monitoring) */
#define INA3221_ADDR_A      0x40    /* FDD0 (5V, 12V) + FDD1 (5V) */
#define INA3221_ADDR_B      0x41    /* FDD1 (12V) + FDD2 (5V, 12V) */
#define INA3221_ADDR_C      0x42    /* FDD3 (5V, 12V) + 24V 8" */

/* I2C Bus 1 Addresses (HDD + System monitoring) */
#define INA3221_ADDR_D      0x40    /* HDD0 (5V, 12V) + HDD1 (5V) */
#define INA3221_ADDR_E      0x41    /* HDD1 (12V) + 3.3V IO + 5V Logic */
#define INA3221_ADDR_F      0x42    /* 1.0V Core + AUX1 + AUX2 */

/* Number of INA3221 devices */
#define INA3221_COUNT_BUS0  3       /* A, B, C on I2C0 */
#define INA3221_COUNT_BUS1  3       /* D, E, F on I2C1 */
#define INA3221_COUNT_TOTAL 6

/* INA3221 Register Addresses */
#define INA3221_REG_CONFIG      0x00
#define INA3221_REG_CH1_SHUNT   0x01
#define INA3221_REG_CH1_BUS     0x02
#define INA3221_REG_CH2_SHUNT   0x03
#define INA3221_REG_CH2_BUS     0x04
#define INA3221_REG_CH3_SHUNT   0x05
#define INA3221_REG_CH3_BUS     0x06
#define INA3221_REG_CRIT_CH1    0x07
#define INA3221_REG_WARN_CH1    0x08
#define INA3221_REG_CRIT_CH2    0x09
#define INA3221_REG_WARN_CH2    0x0A
#define INA3221_REG_CRIT_CH3    0x0B
#define INA3221_REG_WARN_CH3    0x0C
#define INA3221_REG_SHUNT_SUM   0x0D
#define INA3221_REG_SHUNT_LIM   0x0E
#define INA3221_REG_MASK_EN     0x0F
#define INA3221_REG_PWR_VALID   0x10
#define INA3221_REG_MFG_ID      0xFE
#define INA3221_REG_DIE_ID      0xFF

/* INA3221 Configuration bits */
#define INA3221_CFG_RST         (1 << 15)
#define INA3221_CFG_CH1_EN      (1 << 14)
#define INA3221_CFG_CH2_EN      (1 << 13)
#define INA3221_CFG_CH3_EN      (1 << 12)
#define INA3221_CFG_AVG_MASK    (0x7 << 9)
#define INA3221_CFG_VBUS_CT     (0x7 << 6)
#define INA3221_CFG_VSH_CT      (0x7 << 3)
#define INA3221_CFG_MODE_MASK   0x7

/* Averaging modes */
#define INA3221_AVG_1           (0 << 9)
#define INA3221_AVG_4           (1 << 9)
#define INA3221_AVG_16          (2 << 9)
#define INA3221_AVG_64          (3 << 9)
#define INA3221_AVG_128         (4 << 9)
#define INA3221_AVG_256         (5 << 9)
#define INA3221_AVG_512         (6 << 9)
#define INA3221_AVG_1024        (7 << 9)

/* Operating modes */
#define INA3221_MODE_POWER_DOWN     0
#define INA3221_MODE_SHUNT_TRIG     1
#define INA3221_MODE_BUS_TRIG       2
#define INA3221_MODE_SHUNT_BUS_TRIG 3
#define INA3221_MODE_SHUNT_CONT     5
#define INA3221_MODE_BUS_CONT       6
#define INA3221_MODE_SHUNT_BUS_CONT 7

/* Expected IDs */
#define INA3221_MFG_ID          0x5449  /* "TI" */
#define INA3221_DIE_ID          0x3220

/*============================================================================
 * Shunt Resistor Values (milliohms)
 *============================================================================*/

#define SHUNT_5V_FDD        50      /* 50 mΩ for FDD 5V rails (up to 1A) */
#define SHUNT_12V_FDD       20      /* 20 mΩ for FDD 12V rails (up to 2A) */
#define SHUNT_5V_HDD        20      /* 20 mΩ for HDD 5V (up to 2A) */
#define SHUNT_12V_HDD       10      /* 10 mΩ for HDD 12V (up to 4A spinup) */
#define SHUNT_24V_8INCH     10      /* 10 mΩ for 24V 8" drive rails */
#define SHUNT_3V3_FPGA      100     /* 100 mΩ for 3.3V FPGA I/O */
#define SHUNT_5V_LOGIC      100     /* 100 mΩ for 5V logic */
#define SHUNT_1V0_CORE      50      /* 50 mΩ for 1.0V core */

/*============================================================================
 * Power Connector Definitions (6 connectors: 4 FDD + 2 HDD)
 *============================================================================*/

typedef enum {
    PWR_CONN_FDD0 = 0,          /* Floppy Drive 0 (3.5"/5.25") */
    PWR_CONN_FDD1,              /* Floppy Drive 1 (3.5"/5.25") */
    PWR_CONN_FDD2,              /* Floppy Drive 2 (5.25"/8") */
    PWR_CONN_FDD3,              /* Floppy Drive 3 (8" - 24V capable) */
    PWR_CONN_HDD0,              /* Hard Drive 0 (ST-506/ESDI) */
    PWR_CONN_HDD1,              /* Hard Drive 1 (ST-506/ESDI) */
    PWR_CONN_COUNT
} pwr_conn_t;

/*============================================================================
 * Power Rail Definitions (18 channels across 6x INA3221)
 *
 * Power Input Sources:
 *   - USB-C PD: Up to 100W (20V @ 5A) - primary/portable power
 *   - ATX 24-pin: 12V + 5V + 5VSB from desktop PSU
 *   - Both can be active simultaneously (OR'd with ideal diodes)
 *
 * Power Output Connectors (6 total):
 *   - FDD0-FDD3: 4-pin Molex (5V + 12V), FDD3 supports 24V for 8"
 *   - HDD0-HDD1: 4-pin Molex (5V + 12V) for ST-506/ESDI
 *   - 8" Drive: Dedicated 24V connector (active when FDD3 = 8" mode)
 *============================================================================*/

typedef enum {
    /* I2C Bus 0: FDD Power Rails + 24V */
    /* INA3221-A: FDD0 + FDD1 partial */
    PMU_RAIL_FDD0_5V = 0,       /* INA3221-A CH1: FDD0 5V */
    PMU_RAIL_FDD0_12V,          /* INA3221-A CH2: FDD0 12V */
    PMU_RAIL_FDD1_5V,           /* INA3221-A CH3: FDD1 5V */

    /* INA3221-B: FDD1 partial + FDD2 */
    PMU_RAIL_FDD1_12V,          /* INA3221-B CH1: FDD1 12V */
    PMU_RAIL_FDD2_5V,           /* INA3221-B CH2: FDD2 5V */
    PMU_RAIL_FDD2_12V,          /* INA3221-B CH3: FDD2 12V */

    /* INA3221-C: FDD3 + 24V 8" drive */
    PMU_RAIL_FDD3_5V,           /* INA3221-C CH1: FDD3 5V */
    PMU_RAIL_FDD3_12V,          /* INA3221-C CH2: FDD3 12V */
    PMU_RAIL_24V_8INCH,         /* INA3221-C CH3: 24V for 8" drives (boost output) */

    /* I2C Bus 1: HDD + System + Input Rails */
    /* INA3221-D: HDD0 + HDD1 partial */
    PMU_RAIL_HDD0_5V,           /* INA3221-D CH1: HDD0 5V */
    PMU_RAIL_HDD0_12V,          /* INA3221-D CH2: HDD0 12V */
    PMU_RAIL_HDD1_5V,           /* INA3221-D CH3: HDD1 5V */

    /* INA3221-E: HDD1 partial + Input Power */
    PMU_RAIL_HDD1_12V,          /* INA3221-E CH1: HDD1 12V */
    PMU_RAIL_USB_C_VBUS,        /* INA3221-E CH2: USB-C VBUS input (5-20V PD) */
    PMU_RAIL_ATX_12V,           /* INA3221-E CH3: ATX 12V input */

    /* INA3221-F: System + ATX 5V */
    PMU_RAIL_ATX_5V,            /* INA3221-F CH1: ATX 5V input */
    PMU_RAIL_3V3_IO,            /* INA3221-F CH2: 3.3V FPGA I/O (regulated) */
    PMU_RAIL_1V0_CORE,          /* INA3221-F CH3: 1.0V FPGA core (regulated) */

    PMU_RAIL_COUNT              /* Total: 18 rails */
} pmu_rail_t;

/* Rail group identifiers for reporting */
#define PMU_RAIL_GROUP_INPUT    0x01    /* Input rails (USB-C, ATX) */
#define PMU_RAIL_GROUP_FDD      0x02    /* FDD rails (FDD0-FDD3) */
#define PMU_RAIL_GROUP_HDD      0x04    /* HDD rails (HDD0-HDD1) */
#define PMU_RAIL_GROUP_8INCH    0x08    /* 8" drive 24V rail */
#define PMU_RAIL_GROUP_SYSTEM   0x10    /* System rails (3.3V, 1.0V) */

/*============================================================================
 * Power Input Source Detection
 *============================================================================*/

typedef enum {
    PWR_SRC_NONE = 0,           /* No power source detected */
    PWR_SRC_USB_C,              /* USB-C PD active */
    PWR_SRC_ATX,                /* ATX PSU active */
    PWR_SRC_BOTH                /* Both sources active (OR'd) */
} pwr_source_t;

/* USB-C PD profiles supported */
typedef struct {
    uint8_t  pd_version;        /* USB PD spec version (20=2.0, 30=3.0, 31=3.1) */
    uint16_t voltage_mv;        /* Negotiated voltage (5000-20000 mV) */
    uint16_t current_ma;        /* Max current (up to 5000 mA) */
    uint16_t power_mw;          /* Max power (up to 100000 mW = 100W) */
    uint8_t  pps_supported;     /* Programmable Power Supply available */
    uint8_t  epr_supported;     /* Extended Power Range (>100W) available */
} usbc_pd_status_t;

/*============================================================================
 * Data Structures
 *============================================================================*/

/**
 * Individual rail reading
 */
typedef struct {
    uint16_t voltage_mv;        /* Bus voltage in millivolts */
    int16_t  current_ma;        /* Current in milliamps (signed) */
    uint16_t power_mw;          /* Power in milliwatts */
    uint8_t  valid;             /* Reading is valid */
    uint8_t  alert;             /* Alert condition active */
} pmu_reading_t;

/**
 * DC-DC converter status
 */
typedef struct {
    uint8_t  power_good;        /* PGOOD signal state */
    uint8_t  enabled;           /* Enable state */
    uint8_t  fault;             /* Fault condition */
    uint8_t  mode;              /* Operating mode (PWM/PFM/etc) */
    uint16_t vin_mv;            /* Input voltage (if available) */
    uint16_t vout_mv;           /* Output voltage (if available) */
    int8_t   temp_c;            /* Temperature (if available) */
    uint8_t  efficiency;        /* Efficiency % (if calculable) */
} dcdc_status_t;

/**
 * DC-DC converter identifiers
 */
typedef enum {
    DCDC_24V_BOOST = 0,         /* 12V → 24V boost for 8" drives */
    DCDC_5V_BUCK,               /* 12V → 5V buck for drives */
    DCDC_3V3_BUCK,              /* 5V → 3.3V buck for FPGA I/O */
    DCDC_1V0_BUCK,              /* 3.3V → 1.0V buck for FPGA core */
    DCDC_COUNT
} dcdc_id_t;

/**
 * Per-connector power status
 */
typedef struct {
    pmu_reading_t rail_5v;      /* 5V rail reading */
    pmu_reading_t rail_12v;     /* 12V rail reading (or 24V for 8") */
    uint16_t total_power_mw;    /* Combined power for this connector */
    uint8_t  enabled;           /* Connector power enabled */
    uint8_t  fault;             /* Over-current or fault detected */
    uint8_t  present;           /* Drive detected on connector */
} pwr_conn_status_t;

/**
 * Complete system power status
 */
typedef struct {
    /* Per-rail readings (18 channels) */
    pmu_reading_t rails[PMU_RAIL_COUNT];

    /* Per-connector status (6 connectors) */
    pwr_conn_status_t connectors[PWR_CONN_COUNT];

    /* DC-DC converter status */
    dcdc_status_t converters[DCDC_COUNT];

    /* Input power status */
    pwr_source_t active_source;
    usbc_pd_status_t usbc_status;
    uint16_t atx_12v_mv;        /* ATX 12V rail voltage */
    uint16_t atx_5v_mv;         /* ATX 5V rail voltage */

    /* Power summaries */
    uint32_t input_power_mw;    /* Total input power (USB-C + ATX) */
    uint32_t fdd_power_mw;      /* Power for all FDDs */
    uint32_t hdd_power_mw;      /* Power for all HDDs */
    uint32_t system_power_mw;   /* FPGA/logic power */
    uint32_t total_power_mw;    /* Total system consumption */

    /* INA3221 presence (6 devices across 2 buses) */
    uint8_t  ina3221_present[INA3221_COUNT_TOTAL];
} pmu_system_t;

/**
 * Alert thresholds
 */
typedef struct {
    uint16_t warn_current_ma;   /* Warning threshold */
    uint16_t crit_current_ma;   /* Critical threshold */
    uint16_t min_voltage_mv;    /* Under-voltage threshold */
    uint16_t max_voltage_mv;    /* Over-voltage threshold */
} pmu_alert_t;

/*============================================================================
 * HAL Return Codes
 *============================================================================*/

#define PMU_OK              0
#define PMU_ERR_I2C         -1
#define PMU_ERR_TIMEOUT     -2
#define PMU_ERR_NO_DEVICE   -3
#define PMU_ERR_INVALID     -4

/*============================================================================
 * Low-Level I2C Functions
 *============================================================================*/

/**
 * Initialize I2C controller
 * @param fast_mode  true for 400 kHz, false for 100 kHz
 * @return PMU_OK on success
 */
int i2c_init(bool fast_mode);

/**
 * Write bytes to I2C device
 * @param addr      7-bit slave address
 * @param data      Data buffer to write
 * @param len       Number of bytes
 * @return PMU_OK on success
 */
int i2c_write(uint8_t addr, const uint8_t *data, uint8_t len);

/**
 * Read bytes from I2C device
 * @param addr      7-bit slave address
 * @param data      Buffer for read data
 * @param len       Number of bytes to read
 * @return PMU_OK on success
 */
int i2c_read(uint8_t addr, uint8_t *data, uint8_t len);

/**
 * Write then read (typical register access pattern)
 * @param addr      7-bit slave address
 * @param reg       Register address to read from
 * @param data      Buffer for read data
 * @param len       Number of bytes to read
 * @return PMU_OK on success
 */
int i2c_write_read(uint8_t addr, uint8_t reg, uint8_t *data, uint8_t len);

/*============================================================================
 * INA3221 Functions
 *============================================================================*/

/**
 * Probe for INA3221 at address
 * @param addr      I2C address (0x40-0x42)
 * @return PMU_OK if found
 */
int ina3221_probe(uint8_t addr);

/**
 * Initialize INA3221
 * @param addr      I2C address
 * @param avg       Averaging mode (INA3221_AVG_*)
 * @return PMU_OK on success
 */
int ina3221_init(uint8_t addr, uint16_t avg);

/**
 * Read shunt voltage (raw)
 * @param addr      I2C address
 * @param channel   Channel 1-3
 * @param value     Output: raw register value
 * @return PMU_OK on success
 */
int ina3221_read_shunt(uint8_t addr, uint8_t channel, int16_t *value);

/**
 * Read bus voltage (raw)
 * @param addr      I2C address
 * @param channel   Channel 1-3
 * @param value     Output: raw register value
 * @return PMU_OK on success
 */
int ina3221_read_bus(uint8_t addr, uint8_t channel, uint16_t *value);

/*============================================================================
 * Power Monitor HAL Functions
 *============================================================================*/

/**
 * Initialize power monitoring subsystem
 * Probes for all INA3221 devices and configures them.
 * @return PMU_OK on success
 */
int pmu_init(void);

/**
 * Read a single power rail
 * @param rail      Rail to read
 * @param reading   Output: voltage, current, power
 * @return PMU_OK on success
 */
int pmu_read_rail(pmu_rail_t rail, pmu_reading_t *reading);

/**
 * Read all power rails
 * @param system    Output: complete system status
 * @return PMU_OK on success
 */
int pmu_read_all(pmu_system_t *system);

/**
 * Get total system power consumption
 * @return Total power in milliwatts
 */
uint32_t pmu_get_total_power_mw(void);

/**
 * Get drive power consumption
 * @return Drive power in milliwatts
 */
uint32_t pmu_get_drive_power_mw(void);

/**
 * Set alert threshold for a rail
 * @param rail      Rail to configure
 * @param alert     Alert thresholds
 * @return PMU_OK on success
 */
int pmu_set_alert(pmu_rail_t rail, const pmu_alert_t *alert);

/**
 * Check for alert conditions
 * @return Bitmask of rails with active alerts
 */
uint16_t pmu_check_alerts(void);

/*============================================================================
 * Utility Functions
 *============================================================================*/

/**
 * Get rail name string
 * @param rail      Rail identifier
 * @return Human-readable name
 */
const char *pmu_rail_name(pmu_rail_t rail);

/**
 * Get expected nominal voltage for rail
 * @param rail      Rail identifier
 * @return Nominal voltage in millivolts
 */
uint16_t pmu_rail_nominal_mv(pmu_rail_t rail);

/**
 * Convert raw shunt value to current
 * @param raw       Raw register value
 * @param shunt_mohm Shunt resistance in milliohms
 * @return Current in milliamps
 */
int16_t pmu_shunt_to_current(int16_t raw, uint16_t shunt_mohm);

/**
 * Convert raw bus value to voltage
 * @param raw       Raw register value
 * @return Voltage in millivolts
 */
uint16_t pmu_bus_to_voltage(uint16_t raw);

/*============================================================================
 * DC-DC Converter Functions
 *============================================================================*/

/**
 * Initialize DC-DC converter GPIO
 * Configures GPIO directions for PGOOD/FAULT inputs and ENABLE outputs.
 * @return PMU_OK on success
 */
int dcdc_gpio_init(void);

/**
 * Read DC-DC converter status
 * @param id        Converter to read
 * @param status    Output: converter status
 * @return PMU_OK on success
 */
int dcdc_read_status(dcdc_id_t id, dcdc_status_t *status);

/**
 * Read all DC-DC converter statuses
 * @param statuses  Output: array of DCDC_COUNT statuses
 * @return PMU_OK on success
 */
int dcdc_read_all(dcdc_status_t statuses[DCDC_COUNT]);

/**
 * Enable/disable a DC-DC converter
 * @param id        Converter to control
 * @param enable    true to enable, false to disable
 * @return PMU_OK on success
 */
int dcdc_set_enable(dcdc_id_t id, bool enable);

/**
 * Check if all converters have power good
 * @return true if all enabled converters report PGOOD
 */
bool dcdc_all_pgood(void);

/**
 * Check for any converter faults
 * @return Bitmask of converters with faults (bit N = dcdc_id_t N)
 */
uint8_t dcdc_check_faults(void);

/**
 * Get converter name string
 * @param id        Converter identifier
 * @return Human-readable name
 */
const char *dcdc_name(dcdc_id_t id);

/**
 * Get converter input/output voltage specifications
 * @param id        Converter identifier
 * @param vin_mv    Output: nominal input voltage (millivolts)
 * @param vout_mv   Output: nominal output voltage (millivolts)
 */
void dcdc_get_specs(dcdc_id_t id, uint16_t *vin_mv, uint16_t *vout_mv);

/*============================================================================
 * Connector Power Control (6 connectors)
 *============================================================================*/

/**
 * Enable/disable power to a connector
 * Uses high-side switches with current limiting and fault protection.
 * @param conn      Connector to control
 * @param enable    true to enable, false to disable
 * @return PMU_OK on success, PMU_ERR_FAULT if fault detected
 */
int pwr_conn_enable(pwr_conn_t conn, bool enable);

/**
 * Read connector power status
 * @param conn      Connector to read
 * @param status    Output: connector power status
 * @return PMU_OK on success
 */
int pwr_conn_read(pwr_conn_t conn, pwr_conn_status_t *status);

/**
 * Check for over-current fault on connector
 * @param conn      Connector to check
 * @return true if fault detected
 */
bool pwr_conn_fault(pwr_conn_t conn);

/**
 * Clear fault condition on connector (requires disable/enable cycle)
 * @param conn      Connector to clear
 * @return PMU_OK if fault cleared
 */
int pwr_conn_clear_fault(pwr_conn_t conn);

/**
 * Get connector name string
 * @param conn      Connector identifier
 * @return Human-readable name (e.g., "FDD0", "HDD1")
 */
const char *pwr_conn_name(pwr_conn_t conn);

/**
 * Enable 8" drive mode on FDD3 connector
 * Switches FDD3 12V rail to 24V (from boost converter).
 * @param enable    true for 24V (8" drive), false for 12V (5.25")
 * @return PMU_OK on success
 */
int pwr_conn_set_8inch_mode(bool enable);

/**
 * Check if 8" drive mode is active
 * @return true if FDD3 is configured for 24V
 */
bool pwr_conn_is_8inch_mode(void);

/*============================================================================
 * Input Power Functions
 *============================================================================*/

/**
 * Get active power source
 * @return Active power source (USB-C, ATX, both, or none)
 */
pwr_source_t pwr_get_source(void);

/**
 * Get USB-C PD status
 * @param status    Output: USB-C PD negotiation status
 * @return PMU_OK if USB-C active, PMU_ERR_NO_DEVICE if not connected
 */
int pwr_get_usbc_status(usbc_pd_status_t *status);

/**
 * Get total available input power
 * Based on USB-C PD contract and/or ATX PSU capability.
 * @return Available power in milliwatts
 */
uint32_t pwr_get_available_mw(void);

/**
 * Check if power budget allows enabling a connector
 * @param conn      Connector to check
 * @return true if sufficient power available
 */
bool pwr_budget_check(pwr_conn_t conn);

/**
 * Get power budget report
 * @param available Output: available power (mW)
 * @param allocated Output: currently allocated power (mW)
 * @param remaining Output: remaining budget (mW)
 */
void pwr_budget_report(uint32_t *available, uint32_t *allocated, uint32_t *remaining);

#endif /* POWER_HAL_H */
