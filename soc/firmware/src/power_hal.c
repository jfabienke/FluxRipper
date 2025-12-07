/**
 * FluxRipper Power Monitoring HAL - Implementation
 *
 * Driver for INA3221 triple-channel power monitors.
 *
 * Created: 2025-12-04 10:50
 */

#include "power_hal.h"
#include "uart.h"

/*============================================================================
 * Internal State
 *============================================================================*/

static struct {
    bool initialized;
    uint8_t ina3221_present[4];     /* Device presence flags (A, B, C, D) */
    uint16_t shunt_mohm[PMU_RAIL_COUNT];  /* Shunt resistances */
} pmu_state;

/* Shunt resistor values for each rail (milliohms) */
static const uint16_t rail_shunts[PMU_RAIL_COUNT] = {
    [PMU_RAIL_5V_DRV01]   = SHUNT_5V_DRIVE,
    [PMU_RAIL_12V_DRV01]  = SHUNT_12V_DRIVE,
    [PMU_RAIL_5V_LOGIC_A] = SHUNT_5V_LOGIC,
    [PMU_RAIL_5V_DRV23]   = SHUNT_5V_DRIVE,
    [PMU_RAIL_12V_DRV23]  = SHUNT_12V_DRIVE,
    [PMU_RAIL_12V_HDD]    = SHUNT_12V_HDD,
    [PMU_RAIL_3V3_IO]     = SHUNT_3V3_FPGA,
    [PMU_RAIL_5V_LOGIC]   = SHUNT_5V_LOGIC,
    [PMU_RAIL_1V0_CORE]   = SHUNT_1V0_CORE,
    [PMU_RAIL_24V_8INCH]  = SHUNT_24V_DRIVE,
    [PMU_RAIL_5V_8INCH]   = SHUNT_5V_DRIVE,
    [PMU_RAIL_AUX]        = SHUNT_5V_LOGIC
};

/* Nominal voltages (millivolts) */
static const uint16_t rail_nominal[PMU_RAIL_COUNT] = {
    [PMU_RAIL_5V_DRV01]   = 5000,
    [PMU_RAIL_12V_DRV01]  = 12000,
    [PMU_RAIL_5V_LOGIC_A] = 5000,
    [PMU_RAIL_5V_DRV23]   = 5000,
    [PMU_RAIL_12V_DRV23]  = 12000,
    [PMU_RAIL_12V_HDD]    = 12000,
    [PMU_RAIL_3V3_IO]     = 3300,
    [PMU_RAIL_5V_LOGIC]   = 5000,
    [PMU_RAIL_1V0_CORE]   = 1000,
    [PMU_RAIL_24V_8INCH]  = 24000,
    [PMU_RAIL_5V_8INCH]   = 5000,
    [PMU_RAIL_AUX]        = 5000
};

/* Rail names */
static const char *rail_names[PMU_RAIL_COUNT] = {
    [PMU_RAIL_5V_DRV01]   = "5V Drv 0/1",
    [PMU_RAIL_12V_DRV01]  = "12V Drv 0/1",
    [PMU_RAIL_5V_LOGIC_A] = "5V Logic A",
    [PMU_RAIL_5V_DRV23]   = "5V Drv 2/3",
    [PMU_RAIL_12V_DRV23]  = "12V Drv 2/3",
    [PMU_RAIL_12V_HDD]    = "12V HDD",
    [PMU_RAIL_3V3_IO]     = "3.3V IO",
    [PMU_RAIL_5V_LOGIC]   = "5V Logic",
    [PMU_RAIL_1V0_CORE]   = "1.0V Core",
    [PMU_RAIL_24V_8INCH]  = "24V 8-inch",
    [PMU_RAIL_5V_8INCH]   = "5V 8-inch",
    [PMU_RAIL_AUX]        = "Auxiliary"
};

/* Map rail to INA3221 address and channel */
static const struct {
    uint8_t addr;
    uint8_t channel;
} rail_map[PMU_RAIL_COUNT] = {
    [PMU_RAIL_5V_DRV01]   = { INA3221_ADDR_A, 1 },
    [PMU_RAIL_12V_DRV01]  = { INA3221_ADDR_A, 2 },
    [PMU_RAIL_5V_LOGIC_A] = { INA3221_ADDR_A, 3 },
    [PMU_RAIL_5V_DRV23]   = { INA3221_ADDR_B, 1 },
    [PMU_RAIL_12V_DRV23]  = { INA3221_ADDR_B, 2 },
    [PMU_RAIL_12V_HDD]    = { INA3221_ADDR_B, 3 },
    [PMU_RAIL_3V3_IO]     = { INA3221_ADDR_C, 1 },
    [PMU_RAIL_5V_LOGIC]   = { INA3221_ADDR_C, 2 },
    [PMU_RAIL_1V0_CORE]   = { INA3221_ADDR_C, 3 },
    [PMU_RAIL_24V_8INCH]  = { INA3221_ADDR_D, 1 },
    [PMU_RAIL_5V_8INCH]   = { INA3221_ADDR_D, 2 },
    [PMU_RAIL_AUX]        = { INA3221_ADDR_D, 3 }
};

/*============================================================================
 * I2C Low-Level Functions
 *============================================================================*/

static void i2c_wait_idle(void)
{
    while (I2C_STATUS & I2C_STAT_BUSY) {
        /* Spin wait */
    }
}

int i2c_init(bool fast_mode)
{
    /* Set prescaler for 100 kHz or 400 kHz */
    /* For 100 MHz system clock:
     *   100 kHz: 100M / (4 * 100K) - 1 = 249
     *   400 kHz: 100M / (4 * 400K) - 1 = 62
     */
    I2C_PRESCALE = fast_mode ? 62 : 249;

    /* Enable I2C */
    I2C_CTRL = I2C_CTRL_ENABLE | (fast_mode ? I2C_CTRL_FAST_MODE : 0);

    return PMU_OK;
}

static int i2c_send_byte(uint8_t byte)
{
    I2C_TX_DATA = byte;
    I2C_CMD = I2C_CMD_WRITE;
    i2c_wait_idle();

    if (I2C_STATUS & I2C_STAT_ERROR) {
        return PMU_ERR_I2C;
    }

    return PMU_OK;
}

static int i2c_recv_byte(uint8_t *byte, bool ack)
{
    I2C_CMD = ack ? I2C_CMD_READ_ACK : I2C_CMD_READ_NACK;
    i2c_wait_idle();

    if (I2C_STATUS & I2C_STAT_RX_VALID) {
        *byte = I2C_RX_DATA & 0xFF;
        return PMU_OK;
    }

    return PMU_ERR_I2C;
}

int i2c_write(uint8_t addr, const uint8_t *data, uint8_t len)
{
    int ret;

    /* START condition */
    I2C_CMD = I2C_CMD_START;
    i2c_wait_idle();

    /* Send address with write bit */
    ret = i2c_send_byte((addr << 1) | 0);
    if (ret != PMU_OK) {
        I2C_CMD = I2C_CMD_STOP;
        return ret;
    }

    /* Send data bytes */
    for (uint8_t i = 0; i < len; i++) {
        ret = i2c_send_byte(data[i]);
        if (ret != PMU_OK) {
            I2C_CMD = I2C_CMD_STOP;
            return ret;
        }
    }

    /* STOP condition */
    I2C_CMD = I2C_CMD_STOP;
    i2c_wait_idle();

    return PMU_OK;
}

int i2c_read(uint8_t addr, uint8_t *data, uint8_t len)
{
    int ret;

    /* START condition */
    I2C_CMD = I2C_CMD_START;
    i2c_wait_idle();

    /* Send address with read bit */
    ret = i2c_send_byte((addr << 1) | 1);
    if (ret != PMU_OK) {
        I2C_CMD = I2C_CMD_STOP;
        return ret;
    }

    /* Read data bytes */
    for (uint8_t i = 0; i < len; i++) {
        bool ack = (i < len - 1);  /* NACK on last byte */
        ret = i2c_recv_byte(&data[i], ack);
        if (ret != PMU_OK) {
            I2C_CMD = I2C_CMD_STOP;
            return ret;
        }
    }

    /* STOP condition */
    I2C_CMD = I2C_CMD_STOP;
    i2c_wait_idle();

    return PMU_OK;
}

int i2c_write_read(uint8_t addr, uint8_t reg, uint8_t *data, uint8_t len)
{
    int ret;

    /* START condition */
    I2C_CMD = I2C_CMD_START;
    i2c_wait_idle();

    /* Send address with write bit */
    ret = i2c_send_byte((addr << 1) | 0);
    if (ret != PMU_OK) {
        I2C_CMD = I2C_CMD_STOP;
        return ret;
    }

    /* Send register address */
    ret = i2c_send_byte(reg);
    if (ret != PMU_OK) {
        I2C_CMD = I2C_CMD_STOP;
        return ret;
    }

    /* Repeated START */
    I2C_CMD = I2C_CMD_START;
    i2c_wait_idle();

    /* Send address with read bit */
    ret = i2c_send_byte((addr << 1) | 1);
    if (ret != PMU_OK) {
        I2C_CMD = I2C_CMD_STOP;
        return ret;
    }

    /* Read data bytes */
    for (uint8_t i = 0; i < len; i++) {
        bool ack = (i < len - 1);
        ret = i2c_recv_byte(&data[i], ack);
        if (ret != PMU_OK) {
            I2C_CMD = I2C_CMD_STOP;
            return ret;
        }
    }

    /* STOP condition */
    I2C_CMD = I2C_CMD_STOP;
    i2c_wait_idle();

    return PMU_OK;
}

/*============================================================================
 * INA3221 Functions
 *============================================================================*/

static int ina3221_read_reg(uint8_t addr, uint8_t reg, uint16_t *value)
{
    uint8_t data[2];
    int ret = i2c_write_read(addr, reg, data, 2);
    if (ret != PMU_OK) {
        return ret;
    }

    /* INA3221 is big-endian */
    *value = ((uint16_t)data[0] << 8) | data[1];
    return PMU_OK;
}

static int ina3221_write_reg(uint8_t addr, uint8_t reg, uint16_t value)
{
    uint8_t data[3];
    data[0] = reg;
    data[1] = (value >> 8) & 0xFF;
    data[2] = value & 0xFF;
    return i2c_write(addr, data, 3);
}

int ina3221_probe(uint8_t addr)
{
    uint16_t mfg_id, die_id;

    if (ina3221_read_reg(addr, INA3221_REG_MFG_ID, &mfg_id) != PMU_OK) {
        return PMU_ERR_NO_DEVICE;
    }

    if (ina3221_read_reg(addr, INA3221_REG_DIE_ID, &die_id) != PMU_OK) {
        return PMU_ERR_NO_DEVICE;
    }

    if (mfg_id != INA3221_MFG_ID || die_id != INA3221_DIE_ID) {
        return PMU_ERR_NO_DEVICE;
    }

    return PMU_OK;
}

int ina3221_init(uint8_t addr, uint16_t avg)
{
    /* Configure:
     * - All 3 channels enabled
     * - Specified averaging
     * - 1.1ms conversion time for both shunt and bus
     * - Continuous shunt and bus measurement
     */
    uint16_t config = INA3221_CFG_CH1_EN | INA3221_CFG_CH2_EN | INA3221_CFG_CH3_EN |
                      avg |
                      (4 << 6) |  /* 1.1ms bus conversion time */
                      (4 << 3) |  /* 1.1ms shunt conversion time */
                      INA3221_MODE_SHUNT_BUS_CONT;

    return ina3221_write_reg(addr, INA3221_REG_CONFIG, config);
}

int ina3221_read_shunt(uint8_t addr, uint8_t channel, int16_t *value)
{
    if (channel < 1 || channel > 3) {
        return PMU_ERR_INVALID;
    }

    uint8_t reg = INA3221_REG_CH1_SHUNT + ((channel - 1) * 2);
    uint16_t raw;

    int ret = ina3221_read_reg(addr, reg, &raw);
    if (ret != PMU_OK) {
        return ret;
    }

    /* Shunt voltage register is signed, bits [15:3] contain value */
    *value = ((int16_t)raw) >> 3;
    return PMU_OK;
}

int ina3221_read_bus(uint8_t addr, uint8_t channel, uint16_t *value)
{
    if (channel < 1 || channel > 3) {
        return PMU_ERR_INVALID;
    }

    uint8_t reg = INA3221_REG_CH1_BUS + ((channel - 1) * 2);
    uint16_t raw;

    int ret = ina3221_read_reg(addr, reg, &raw);
    if (ret != PMU_OK) {
        return ret;
    }

    /* Bus voltage register bits [15:3] contain value */
    *value = raw >> 3;
    return PMU_OK;
}

/*============================================================================
 * Conversion Functions
 *============================================================================*/

int16_t pmu_shunt_to_current(int16_t raw, uint16_t shunt_mohm)
{
    /* Shunt LSB = 40µV
     * Current = Shunt_Voltage / Shunt_Resistance
     * Current_mA = (raw * 40µV) / (shunt_mohm * 1mΩ)
     *            = (raw * 40) / shunt_mohm  [in µA, need to convert to mA]
     *            = (raw * 40) / (shunt_mohm * 1000) [in mA]
     *
     * Simplified: Current_mA = raw * 40 / shunt_mohm / 1000
     *                        = raw * 4 / shunt_mohm / 100
     */
    int32_t current_ua = ((int32_t)raw * 40);
    int32_t current_ma = current_ua / shunt_mohm;
    return (int16_t)current_ma;
}

uint16_t pmu_bus_to_voltage(uint16_t raw)
{
    /* Bus LSB = 8mV */
    return raw * 8;
}

/*============================================================================
 * Power Monitor HAL Functions
 *============================================================================*/

int pmu_init(void)
{
    int ret;

    /* Initialize I2C at 400 kHz */
    ret = i2c_init(true);
    if (ret != PMU_OK) {
        return ret;
    }

    /* Probe for INA3221 devices */
    pmu_state.ina3221_present[0] = (ina3221_probe(INA3221_ADDR_A) == PMU_OK);
    pmu_state.ina3221_present[1] = (ina3221_probe(INA3221_ADDR_B) == PMU_OK);
    pmu_state.ina3221_present[2] = (ina3221_probe(INA3221_ADDR_C) == PMU_OK);
    pmu_state.ina3221_present[3] = (ina3221_probe(INA3221_ADDR_D) == PMU_OK);

    /* Initialize found devices with 64-sample averaging */
    if (pmu_state.ina3221_present[0]) {
        ina3221_init(INA3221_ADDR_A, INA3221_AVG_64);
    }
    if (pmu_state.ina3221_present[1]) {
        ina3221_init(INA3221_ADDR_B, INA3221_AVG_64);
    }
    if (pmu_state.ina3221_present[2]) {
        ina3221_init(INA3221_ADDR_C, INA3221_AVG_64);
    }
    if (pmu_state.ina3221_present[3]) {
        ina3221_init(INA3221_ADDR_D, INA3221_AVG_64);
    }

    /* Copy shunt values */
    for (int i = 0; i < PMU_RAIL_COUNT; i++) {
        pmu_state.shunt_mohm[i] = rail_shunts[i];
    }

    pmu_state.initialized = true;

    return PMU_OK;
}

int pmu_read_rail(pmu_rail_t rail, pmu_reading_t *reading)
{
    if (!pmu_state.initialized || rail >= PMU_RAIL_COUNT) {
        return PMU_ERR_INVALID;
    }

    uint8_t addr = rail_map[rail].addr;
    uint8_t channel = rail_map[rail].channel;
    uint8_t ina_idx = addr - INA3221_ADDR_A;

    /* Check if device is present */
    if (!pmu_state.ina3221_present[ina_idx]) {
        reading->valid = 0;
        return PMU_ERR_NO_DEVICE;
    }

    int16_t shunt_raw;
    uint16_t bus_raw;
    int ret;

    /* Read shunt voltage (current) */
    ret = ina3221_read_shunt(addr, channel, &shunt_raw);
    if (ret != PMU_OK) {
        reading->valid = 0;
        return ret;
    }

    /* Read bus voltage */
    ret = ina3221_read_bus(addr, channel, &bus_raw);
    if (ret != PMU_OK) {
        reading->valid = 0;
        return ret;
    }

    /* Convert to engineering units */
    reading->voltage_mv = pmu_bus_to_voltage(bus_raw);
    reading->current_ma = pmu_shunt_to_current(shunt_raw, pmu_state.shunt_mohm[rail]);
    reading->power_mw = (uint16_t)(((uint32_t)reading->voltage_mv *
                                     (uint32_t)reading->current_ma) / 1000);
    reading->valid = 1;
    reading->alert = 0;  /* TODO: check alert registers */

    return PMU_OK;
}

int pmu_read_all(pmu_system_t *system)
{
    if (!pmu_state.initialized) {
        return PMU_ERR_INVALID;
    }

    uint32_t total = 0;
    uint32_t drive = 0;
    uint32_t sys = 0;

    for (int i = 0; i < PMU_RAIL_COUNT; i++) {
        pmu_read_rail((pmu_rail_t)i, &system->rails[i]);

        if (system->rails[i].valid) {
            total += system->rails[i].power_mw;

            /* Categorize power */
            if (i <= PMU_RAIL_12V_HDD) {
                drive += system->rails[i].power_mw;
            } else {
                sys += system->rails[i].power_mw;
            }
        }
    }

    system->total_power_mw = total;
    system->drive_power_mw = drive;
    system->system_power_mw = sys;

    for (int i = 0; i < 4; i++) {
        system->ina3221_present[i] = pmu_state.ina3221_present[i];
    }

    /* Read DC-DC converter statuses */
    dcdc_read_all(system->converters);

    return PMU_OK;
}

uint32_t pmu_get_total_power_mw(void)
{
    pmu_system_t sys;
    if (pmu_read_all(&sys) != PMU_OK) {
        return 0;
    }
    return sys.total_power_mw;
}

uint32_t pmu_get_drive_power_mw(void)
{
    pmu_system_t sys;
    if (pmu_read_all(&sys) != PMU_OK) {
        return 0;
    }
    return sys.drive_power_mw;
}

const char *pmu_rail_name(pmu_rail_t rail)
{
    if (rail >= PMU_RAIL_COUNT) {
        return "Unknown";
    }
    return rail_names[rail];
}

uint16_t pmu_rail_nominal_mv(pmu_rail_t rail)
{
    if (rail >= PMU_RAIL_COUNT) {
        return 0;
    }
    return rail_nominal[rail];
}

int pmu_set_alert(pmu_rail_t rail, const pmu_alert_t *alert)
{
    if (!pmu_state.initialized || rail >= PMU_RAIL_COUNT) {
        return PMU_ERR_INVALID;
    }

    uint8_t addr = rail_map[rail].addr;
    uint8_t channel = rail_map[rail].channel;

    /* Convert current threshold to shunt voltage */
    /* Shunt_mV = Current_mA * Shunt_mΩ / 1000 */
    /* Register = Shunt_mV / 0.040mV = Shunt_mV * 25 */
    int32_t warn_shunt = ((int32_t)alert->warn_current_ma *
                          pmu_state.shunt_mohm[rail]) / 1000;
    int32_t crit_shunt = ((int32_t)alert->crit_current_ma *
                          pmu_state.shunt_mohm[rail]) / 1000;

    /* Convert to register value and shift left 3 (register format) */
    uint16_t warn_reg = (uint16_t)((warn_shunt * 25) << 3);
    uint16_t crit_reg = (uint16_t)((crit_shunt * 25) << 3);

    /* Write warning and critical thresholds */
    uint8_t warn_addr = INA3221_REG_WARN_CH1 + ((channel - 1) * 2);
    uint8_t crit_addr = INA3221_REG_CRIT_CH1 + ((channel - 1) * 2);

    int ret = ina3221_write_reg(addr, warn_addr, warn_reg);
    if (ret != PMU_OK) return ret;

    ret = ina3221_write_reg(addr, crit_addr, crit_reg);
    if (ret != PMU_OK) return ret;

    return PMU_OK;
}

uint16_t pmu_check_alerts(void)
{
    /* TODO: Read mask/enable register from each INA3221 */
    /* For now, return 0 (no alerts) */
    return 0;
}

/*============================================================================
 * DC-DC Converter Functions
 *============================================================================*/

/* DC-DC converter names */
static const char *dcdc_names[DCDC_COUNT] = {
    [DCDC_24V_BOOST] = "24V Boost",
    [DCDC_5V_BUCK]   = "5V Buck",
    [DCDC_3V3_BUCK]  = "3.3V Buck",
    [DCDC_1V0_BUCK]  = "1.0V Buck"
};

/* DC-DC converter voltage specifications */
static const struct {
    uint16_t vin_mv;
    uint16_t vout_mv;
} dcdc_specs[DCDC_COUNT] = {
    [DCDC_24V_BOOST] = { 12000, 24000 },   /* 12V → 24V */
    [DCDC_5V_BUCK]   = { 12000, 5000 },    /* 12V → 5V */
    [DCDC_3V3_BUCK]  = { 5000, 3300 },     /* 5V → 3.3V */
    [DCDC_1V0_BUCK]  = { 3300, 1000 }      /* 3.3V → 1.0V */
};

/* GPIO bit mappings for each converter */
static const struct {
    uint32_t pgood;
    uint32_t enable;
    uint32_t fault;
} dcdc_gpio[DCDC_COUNT] = {
    [DCDC_24V_BOOST] = { DCDC_24V_PGOOD, DCDC_24V_ENABLE, DCDC_24V_FAULT },
    [DCDC_5V_BUCK]   = { DCDC_5V_PGOOD, DCDC_5V_ENABLE, DCDC_5V_FAULT },
    [DCDC_3V3_BUCK]  = { DCDC_3V3_PGOOD, DCDC_3V3_ENABLE, DCDC_3V3_FAULT },
    [DCDC_1V0_BUCK]  = { DCDC_1V0_PGOOD, DCDC_1V0_ENABLE, DCDC_1V0_FAULT }
};

int dcdc_gpio_init(void)
{
    /* Configure GPIO direction for DC-DC signals
     * TRI register: 0 = output, 1 = input
     */
    GPIO_TRI2 = DCDC_GPIO_INPUTS;

    /* Default: enable system-critical converters (3.3V and 1.0V for FPGA)
     * Leave 24V and 5V drive converters off until drive is connected
     */
    GPIO_DATA2 = DCDC_3V3_ENABLE | DCDC_1V0_ENABLE;

    return PMU_OK;
}

int dcdc_read_status(dcdc_id_t id, dcdc_status_t *status)
{
    if (id >= DCDC_COUNT || status == NULL) {
        return PMU_ERR_INVALID;
    }

    uint32_t gpio = GPIO_DATA2;

    /* Read GPIO signals */
    status->power_good = (gpio & dcdc_gpio[id].pgood) ? 1 : 0;
    status->enabled = (gpio & dcdc_gpio[id].enable) ? 1 : 0;
    status->fault = (gpio & dcdc_gpio[id].fault) ? 1 : 0;

    /* Mode is only available for 5V buck */
    if (id == DCDC_5V_BUCK) {
        status->mode = (gpio & DCDC_5V_MODE) ? 1 : 0;  /* 0=auto, 1=forced PWM */
    } else {
        status->mode = 0;
    }

    /* Get nominal voltages from specs */
    status->vin_mv = dcdc_specs[id].vin_mv;
    status->vout_mv = dcdc_specs[id].vout_mv;

    /* Try to get actual voltages from INA3221 if available */
    if (pmu_state.initialized) {
        pmu_reading_t reading;
        pmu_rail_t rail = PMU_RAIL_COUNT;

        /* Map converter to corresponding monitored rail for actual Vout */
        switch (id) {
        case DCDC_24V_BOOST:
            rail = PMU_RAIL_24V_8INCH;
            break;
        case DCDC_5V_BUCK:
            rail = PMU_RAIL_5V_DRV01;
            break;
        case DCDC_3V3_BUCK:
            rail = PMU_RAIL_3V3_IO;
            break;
        case DCDC_1V0_BUCK:
            rail = PMU_RAIL_1V0_CORE;
            break;
        default:
            break;
        }

        if (rail < PMU_RAIL_COUNT && pmu_read_rail(rail, &reading) == PMU_OK) {
            if (reading.valid) {
                status->vout_mv = reading.voltage_mv;
            }
        }
    }

    /* Temperature not directly available without additional sensor
     * Set to invalid value (-128 = not available)
     */
    status->temp_c = -128;

    /* Calculate efficiency if we have valid input and output readings */
    if (status->power_good && pmu_state.initialized) {
        pmu_reading_t in_reading, out_reading;
        pmu_rail_t in_rail = PMU_RAIL_COUNT, out_rail = PMU_RAIL_COUNT;

        /* Find input and output rails for efficiency calculation */
        switch (id) {
        case DCDC_24V_BOOST:
            in_rail = PMU_RAIL_12V_HDD;     /* Uses 12V input */
            out_rail = PMU_RAIL_24V_8INCH;
            break;
        case DCDC_5V_BUCK:
            in_rail = PMU_RAIL_12V_DRV01;   /* Uses 12V input */
            out_rail = PMU_RAIL_5V_DRV01;
            break;
        case DCDC_3V3_BUCK:
            in_rail = PMU_RAIL_5V_LOGIC;    /* Uses 5V input */
            out_rail = PMU_RAIL_3V3_IO;
            break;
        case DCDC_1V0_BUCK:
            in_rail = PMU_RAIL_3V3_IO;      /* Uses 3.3V input */
            out_rail = PMU_RAIL_1V0_CORE;
            break;
        default:
            break;
        }

        if (in_rail < PMU_RAIL_COUNT && out_rail < PMU_RAIL_COUNT) {
            if (pmu_read_rail(in_rail, &in_reading) == PMU_OK &&
                pmu_read_rail(out_rail, &out_reading) == PMU_OK) {
                if (in_reading.valid && out_reading.valid && in_reading.power_mw > 0) {
                    /* Efficiency = Pout / Pin * 100 */
                    uint32_t eff = ((uint32_t)out_reading.power_mw * 100) / in_reading.power_mw;
                    status->efficiency = (eff > 100) ? 100 : (uint8_t)eff;
                } else {
                    status->efficiency = 0;
                }
            } else {
                status->efficiency = 0;
            }
        } else {
            status->efficiency = 0;
        }
    } else {
        status->efficiency = 0;
    }

    return PMU_OK;
}

int dcdc_read_all(dcdc_status_t statuses[DCDC_COUNT])
{
    for (int i = 0; i < DCDC_COUNT; i++) {
        int ret = dcdc_read_status((dcdc_id_t)i, &statuses[i]);
        if (ret != PMU_OK) {
            return ret;
        }
    }
    return PMU_OK;
}

int dcdc_set_enable(dcdc_id_t id, bool enable)
{
    if (id >= DCDC_COUNT) {
        return PMU_ERR_INVALID;
    }

    uint32_t gpio = GPIO_DATA2;

    if (enable) {
        gpio |= dcdc_gpio[id].enable;
    } else {
        gpio &= ~dcdc_gpio[id].enable;
    }

    GPIO_DATA2 = gpio;

    return PMU_OK;
}

bool dcdc_all_pgood(void)
{
    uint32_t gpio = GPIO_DATA2;
    uint32_t enabled = gpio & DCDC_ALL_ENABLE;
    uint32_t pgood_mask = 0;

    /* Build mask of PGOOD bits for enabled converters */
    if (enabled & DCDC_24V_ENABLE) pgood_mask |= DCDC_24V_PGOOD;
    if (enabled & DCDC_5V_ENABLE)  pgood_mask |= DCDC_5V_PGOOD;
    if (enabled & DCDC_3V3_ENABLE) pgood_mask |= DCDC_3V3_PGOOD;
    if (enabled & DCDC_1V0_ENABLE) pgood_mask |= DCDC_1V0_PGOOD;

    /* Check if all required PGOOD signals are asserted */
    return (gpio & pgood_mask) == pgood_mask;
}

uint8_t dcdc_check_faults(void)
{
    uint32_t gpio = GPIO_DATA2;
    uint8_t faults = 0;

    if (gpio & DCDC_24V_FAULT) faults |= (1 << DCDC_24V_BOOST);
    if (gpio & DCDC_5V_FAULT)  faults |= (1 << DCDC_5V_BUCK);
    if (gpio & DCDC_3V3_FAULT) faults |= (1 << DCDC_3V3_BUCK);
    if (gpio & DCDC_1V0_FAULT) faults |= (1 << DCDC_1V0_BUCK);

    return faults;
}

const char *dcdc_name(dcdc_id_t id)
{
    if (id >= DCDC_COUNT) {
        return "Unknown";
    }
    return dcdc_names[id];
}

void dcdc_get_specs(dcdc_id_t id, uint16_t *vin_mv, uint16_t *vout_mv)
{
    if (id >= DCDC_COUNT) {
        if (vin_mv) *vin_mv = 0;
        if (vout_mv) *vout_mv = 0;
        return;
    }

    if (vin_mv) *vin_mv = dcdc_specs[id].vin_mv;
    if (vout_mv) *vout_mv = dcdc_specs[id].vout_mv;
}
