/**
 * FluxRipper System HAL Implementation
 *
 * Hardware abstraction for system-level diagnostics
 *
 * Created: 2025-12-07 14:15
 * License: BSD-3-Clause
 */

#include "system_hal.h"
#include <string.h>

/*============================================================================
 * Hardware Register Definitions
 *============================================================================*/

/* Base addresses (adjust for your memory map) */
#define SYS_BASE_ADDR        0x44A00000
#define XADC_BASE_ADDR       0x44A10000
#define I2C0_BASE_ADDR       0x44A20000
#define I2C1_BASE_ADDR       0x44A30000
#define FDD_BASE_ADDR        0x44A50000
#define HDD_BASE_ADDR        0x44A60000

/* System registers */
#define REG_DEVICE_ID        0x00
#define REG_BITSTREAM_ID     0x04
#define REG_BITSTREAM_DATE   0x08
#define REG_BITSTREAM_CRC    0x0C
#define REG_STATUS           0x10
#define REG_UPTIME           0x14
#define REG_BOOT_COUNT       0x18
#define REG_CLK_STATUS       0x1C
#define REG_CLK_FREQ(n)      (0x20 + (n) * 4)
#define REG_GPIO_IN          0x40
#define REG_GPIO_OUT         0x44
#define REG_BRAM_STATUS      0x48
#define REG_DDR_STATUS       0x4C

/* I2C registers */
#define I2C_REG_CONTROL      0x00
#define I2C_REG_STATUS       0x04
#define I2C_REG_DATA         0x08
#define I2C_REG_ADDR         0x0C
#define I2C_REG_TX_COUNT     0x10
#define I2C_REG_ERR_COUNT    0x14
#define I2C_REG_NAK_COUNT    0x18
#define I2C_REG_TIMEOUT      0x1C

/* XADC registers */
#define XADC_REG_TEMP        0x200
#define XADC_REG_VCCINT      0x204
#define XADC_REG_VCCAUX      0x208

/* FDD/HDD drive status registers */
#define DRV_REG_STATUS(n)    (0x00 + (n) * 0x20)
#define DRV_REG_TRACK(n)     (0x04 + (n) * 0x20)
#define DRV_REG_RPM(n)       (0x08 + (n) * 0x20)
#define DRV_REG_TYPE(n)      (0x0C + (n) * 0x20)

/*============================================================================
 * Register Access Macros
 *============================================================================*/

#define SYS_REG(offset)      (*(volatile uint32_t*)(SYS_BASE_ADDR + (offset)))
#define XADC_REG(offset)     (*(volatile uint32_t*)(XADC_BASE_ADDR + (offset)))
#define I2C_REG(bus, offset) (*(volatile uint32_t*)((bus == 0 ? I2C0_BASE_ADDR : I2C1_BASE_ADDR) + (offset)))
#define FDD_REG(offset)      (*(volatile uint32_t*)(FDD_BASE_ADDR + (offset)))
#define HDD_REG(offset)      (*(volatile uint32_t*)(HDD_BASE_ADDR + (offset)))

/*============================================================================
 * Module State
 *============================================================================*/

static bool g_initialized = false;
static uint32_t g_boot_time = 0;  /* Timestamp at boot */

/* Session statistics */
static uptime_stats_t g_session_stats = {0};

/* Temperature min/max tracking */
static int16_t g_temp_min[TEMP_SENSOR_COUNT];
static int16_t g_temp_max[TEMP_SENSOR_COUNT];

/* Clock names */
static const char *g_clock_names[CLK_COUNT] = {
    "SYS 100MHz",
    "USB 60MHz",
    "CAP 200MHz",
    "CAP 300MHz",
    "REF 25MHz"
};

/* Clock nominal frequencies */
static const uint32_t g_clock_nominal[CLK_COUNT] = {
    100000000,
    60000000,
    200000000,
    300000000,
    25000000
};

/* Known I2C device addresses and names */
static const struct {
    uint8_t addr;
    const char *name;
} g_known_i2c_devices[] = {
    { 0x40, "INA3221-A" },
    { 0x41, "INA3221-B" },
    { 0x42, "INA3221-C" },
    { 0x43, "INA3221-D" },
    { 0x44, "INA3221-E" },
    { 0x45, "INA3221-F" },
    { 0x48, "TMP117" },
    { 0x50, "EEPROM" },
    { 0x68, "DS3231" },
    { 0x00, NULL }
};

/*============================================================================
 * Initialization
 *============================================================================*/

int sys_init(void)
{
    if (g_initialized) {
        return 0;
    }

    /* Initialize temperature min/max */
    for (int i = 0; i < TEMP_SENSOR_COUNT; i++) {
        g_temp_min[i] = 0x7FFF;
        g_temp_max[i] = -0x7FFF;
    }

    /* Clear session stats */
    memset(&g_session_stats, 0, sizeof(g_session_stats));

    /* Read boot count and increment */
    g_session_stats.boot_count = SYS_REG(REG_BOOT_COUNT);

    g_initialized = true;
    return 0;
}

/*============================================================================
 * Version Information
 *============================================================================*/

void sys_get_version(version_info_t *ver)
{
    if (!ver) return;

    ver->major = FIRMWARE_VERSION_MAJOR;
    ver->minor = FIRMWARE_VERSION_MINOR;
    ver->patch = FIRMWARE_VERSION_PATCH;

    strncpy(ver->build_date, FIRMWARE_BUILD_DATE, sizeof(ver->build_date) - 1);
    ver->build_date[sizeof(ver->build_date) - 1] = '\0';

    strncpy(ver->build_time, FIRMWARE_BUILD_TIME, sizeof(ver->build_time) - 1);
    ver->build_time[sizeof(ver->build_time) - 1] = '\0';

    strncpy(ver->git_hash, FIRMWARE_GIT_HASH, sizeof(ver->git_hash) - 1);
    ver->git_hash[sizeof(ver->git_hash) - 1] = '\0';

    strncpy(ver->git_branch, FIRMWARE_GIT_BRANCH, sizeof(ver->git_branch) - 1);
    ver->git_branch[sizeof(ver->git_branch) - 1] = '\0';

    /* Git dirty flag would be set by build system */
    ver->git_dirty = false;
}

void sys_get_fpga_info(fpga_info_t *info)
{
    if (!info) return;

    info->device_id = SYS_REG(REG_DEVICE_ID);
    info->bitstream_id = SYS_REG(REG_BITSTREAM_ID);
    info->bitstream_crc = SYS_REG(REG_BITSTREAM_CRC);

    /* Decode date from packed format YYYYMMDD */
    uint32_t date = SYS_REG(REG_BITSTREAM_DATE);
    snprintf(info->bitstream_date, sizeof(info->bitstream_date),
             "%04lu-%02lu-%02lu",
             (date >> 16) & 0xFFFF,
             (date >> 8) & 0xFF,
             date & 0xFF);

    uint32_t status = SYS_REG(REG_STATUS);
    info->config_done = (status & 0x01) != 0;
    info->init_done = (status & 0x02) != 0;
}

/*============================================================================
 * Drive Status
 *============================================================================*/

int sys_get_drive_count(bool is_fdd)
{
    return is_fdd ? 4 : 2;  /* 4 FDD slots, 2 HDD slots */
}

int sys_get_drive_status(bool is_fdd, uint8_t slot, drive_status_t *status)
{
    if (!status) return -1;

    uint8_t max_slots = is_fdd ? 4 : 2;
    if (slot >= max_slots) return -1;

    memset(status, 0, sizeof(*status));
    status->slot = slot;
    status->is_fdd = is_fdd;

    uint32_t base_reg = is_fdd ? FDD_REG(DRV_REG_STATUS(slot))
                               : HDD_REG(DRV_REG_STATUS(slot));

    uint32_t stat = is_fdd ? FDD_REG(DRV_REG_STATUS(slot))
                           : HDD_REG(DRV_REG_STATUS(slot));

    /* Decode status register */
    status->state = (stat >> 0) & 0x0F;
    status->motor_on = (stat >> 4) & 0x01;
    status->write_protected = (stat >> 5) & 0x01;
    status->track0 = (stat >> 6) & 0x01;
    status->index = (stat >> 7) & 0x01;

    /* Current track */
    uint32_t track_reg = is_fdd ? FDD_REG(DRV_REG_TRACK(slot))
                                : HDD_REG(DRV_REG_TRACK(slot));
    status->current_track = track_reg & 0xFFFF;

    /* RPM measurement */
    uint32_t rpm_reg = is_fdd ? FDD_REG(DRV_REG_RPM(slot))
                              : HDD_REG(DRV_REG_RPM(slot));
    status->rpm = rpm_reg & 0xFFFF;

    /* Drive type */
    uint32_t type_reg = is_fdd ? FDD_REG(DRV_REG_TYPE(slot))
                               : HDD_REG(DRV_REG_TYPE(slot));
    status->type = type_reg & 0x0F;

    /* HDD geometry (from identification) */
    if (!is_fdd && status->state != DRIVE_STATE_NOT_PRESENT) {
        status->cylinders = (type_reg >> 8) & 0xFFFF;
        status->heads = (type_reg >> 24) & 0xFF;
        /* Sectors would come from separate register or identification */
    }

    /* Determine if present based on state */
    if (status->state == DRIVE_STATE_NOT_PRESENT) {
        status->type = DRIVE_TYPE_NONE;
    }

    return 0;
}

const char* sys_drive_type_name(drive_type_t type)
{
    switch (type) {
        case DRIVE_TYPE_NONE:     return "None";
        case DRIVE_TYPE_FDD_35:   return "3.5\" FDD";
        case DRIVE_TYPE_FDD_525:  return "5.25\" FDD";
        case DRIVE_TYPE_FDD_8:    return "8\" FDD";
        case DRIVE_TYPE_HDD_MFM:  return "MFM HDD";
        case DRIVE_TYPE_HDD_RLL:  return "RLL HDD";
        case DRIVE_TYPE_HDD_ESDI: return "ESDI HDD";
        default:                  return "Unknown";
    }
}

const char* sys_drive_state_name(drive_state_t state)
{
    switch (state) {
        case DRIVE_STATE_NOT_PRESENT: return "Not Present";
        case DRIVE_STATE_PRESENT:     return "Present";
        case DRIVE_STATE_SPINNING_UP: return "Spinning Up";
        case DRIVE_STATE_READY:       return "Ready";
        case DRIVE_STATE_SEEKING:     return "Seeking";
        case DRIVE_STATE_READING:     return "Reading";
        case DRIVE_STATE_WRITING:     return "Writing";
        case DRIVE_STATE_ERROR:       return "Error";
        case DRIVE_STATE_NOT_READY:   return "Not Ready";
        default:                      return "???";
    }
}

/*============================================================================
 * Uptime and Statistics
 *============================================================================*/

void sys_get_uptime(uptime_stats_t *stats)
{
    if (!stats) return;

    /* Copy session stats */
    memcpy(stats, &g_session_stats, sizeof(*stats));

    /* Update uptime */
    stats->uptime_seconds = SYS_REG(REG_UPTIME);
}

uint32_t sys_get_uptime_seconds(void)
{
    return SYS_REG(REG_UPTIME);
}

void sys_reset_session_stats(void)
{
    g_session_stats.session_errors = 0;
    g_session_stats.session_retries = 0;
}

/*============================================================================
 * Clock Monitoring
 *============================================================================*/

int sys_get_clock_status(clock_id_t clk, clock_status_t *status)
{
    if (!status || clk >= CLK_COUNT) return -1;

    status->id = clk;
    status->name = g_clock_names[clk];
    status->nominal_hz = g_clock_nominal[clk];

    /* Read measured frequency from hardware */
    status->measured_hz = SYS_REG(REG_CLK_FREQ(clk));

    /* Calculate PPM offset */
    if (status->nominal_hz > 0) {
        int32_t diff = (int32_t)status->measured_hz - (int32_t)status->nominal_hz;
        status->ppm_offset = (int16_t)((diff * 1000000LL) / status->nominal_hz);
    } else {
        status->ppm_offset = 0;
    }

    /* PLL lock status from status register */
    uint32_t clk_status = SYS_REG(REG_CLK_STATUS);
    status->pll_locked = (clk_status & (1 << clk)) != 0;
    status->present = status->measured_hz > 0;

    return 0;
}

int sys_get_all_clocks(clock_status_t *clocks, uint8_t max_count)
{
    if (!clocks) return -1;

    int count = (max_count < CLK_COUNT) ? max_count : CLK_COUNT;
    for (int i = 0; i < count; i++) {
        sys_get_clock_status((clock_id_t)i, &clocks[i]);
    }
    return count;
}

bool sys_all_clocks_locked(void)
{
    uint32_t clk_status = SYS_REG(REG_CLK_STATUS);
    /* Check all 5 clock PLLs are locked */
    return (clk_status & 0x1F) == 0x1F;
}

/*============================================================================
 * I2C Diagnostics
 *============================================================================*/

/**
 * Probe a single I2C address
 */
static bool i2c_probe_addr(uint8_t bus, uint8_t addr)
{
    /* Write address with read bit */
    I2C_REG(bus, I2C_REG_ADDR) = (addr << 1) | 0x01;

    /* Start transaction */
    I2C_REG(bus, I2C_REG_CONTROL) = 0x01;  /* START */

    /* Wait for completion (with timeout) */
    for (int i = 0; i < 1000; i++) {
        uint32_t status = I2C_REG(bus, I2C_REG_STATUS);
        if (status & 0x02) {  /* Done flag */
            return (status & 0x04) == 0;  /* No NAK = device present */
        }
    }
    return false;
}

/**
 * Find device name from known list
 */
static const char* i2c_device_name(uint8_t addr)
{
    for (int i = 0; g_known_i2c_devices[i].name != NULL; i++) {
        if (g_known_i2c_devices[i].addr == addr) {
            return g_known_i2c_devices[i].name;
        }
    }
    return "Unknown";
}

int sys_i2c_scan(uint8_t bus_id, i2c_bus_status_t *status)
{
    if (!status || bus_id >= I2C_BUS_COUNT) return -1;

    memset(status, 0, sizeof(*status));
    status->bus_id = bus_id;
    status->bus_ok = true;
    status->clock_hz = 100000;  /* 100 kHz standard */

    /* Scan all 7-bit addresses (skip reserved ranges) */
    uint8_t count = 0;
    for (uint8_t addr = 0x08; addr < 0x78 && count < I2C_MAX_DEVICES; addr++) {
        if (i2c_probe_addr(bus_id, addr)) {
            status->devices[count].address = addr;
            status->devices[count].present = true;
            strncpy(status->devices[count].name, i2c_device_name(addr),
                    sizeof(status->devices[count].name) - 1);
            count++;
        }
    }
    status->device_count = count;

    return count;
}

int sys_i2c_get_stats(uint8_t bus_id, i2c_bus_status_t *status)
{
    if (!status || bus_id >= I2C_BUS_COUNT) return -1;

    status->bus_id = bus_id;
    status->tx_count = I2C_REG(bus_id, I2C_REG_TX_COUNT);
    status->error_count = I2C_REG(bus_id, I2C_REG_ERR_COUNT);
    status->nak_count = I2C_REG(bus_id, I2C_REG_NAK_COUNT);
    status->timeout_count = I2C_REG(bus_id, I2C_REG_TIMEOUT);
    status->bus_ok = (status->error_count == 0);

    return 0;
}

void sys_i2c_reset_stats(uint8_t bus_id)
{
    if (bus_id >= I2C_BUS_COUNT) return;

    /* Write 1 to clear counters */
    I2C_REG(bus_id, I2C_REG_TX_COUNT) = 0;
    I2C_REG(bus_id, I2C_REG_ERR_COUNT) = 0;
    I2C_REG(bus_id, I2C_REG_NAK_COUNT) = 0;
    I2C_REG(bus_id, I2C_REG_TIMEOUT) = 0;
}

/*============================================================================
 * Temperature
 *============================================================================*/

/* XADC temperature conversion: raw * 503.975 / 4096 - 273.15 (in 0.1°C) */
static int16_t xadc_to_temp(uint32_t raw)
{
    /* Scale for 0.1°C resolution */
    int32_t temp = ((int32_t)raw * 5040) / 4096 - 2732;
    return (int16_t)temp;
}

int sys_get_temperature(temp_sensor_id_t sensor, temp_status_t *status)
{
    if (!status || sensor >= TEMP_SENSOR_COUNT) return -1;

    memset(status, 0, sizeof(*status));
    status->id = sensor;

    switch (sensor) {
        case TEMP_SENSOR_FPGA:
            status->name = "FPGA";
            status->present = true;
            status->temp_c = xadc_to_temp(XADC_REG(XADC_REG_TEMP));
            status->warning_c = 850;   /* 85.0°C */
            status->critical_c = 1000; /* 100.0°C */
            break;

        case TEMP_SENSOR_BOARD:
            status->name = "Board";
            /* TMP117 on I2C bus 0 at 0x48 */
            status->present = i2c_probe_addr(0, 0x48);
            if (status->present) {
                /* Would read from TMP117 register */
                status->temp_c = 250;  /* Placeholder: 25.0°C */
            }
            status->warning_c = 700;
            status->critical_c = 850;
            break;

        case TEMP_SENSOR_USB_PHY:
            status->name = "USB PHY";
            status->present = false;  /* Most USB PHYs don't have temp sensor */
            break;

        default:
            return -1;
    }

    /* Update min/max tracking */
    if (status->present) {
        if (status->temp_c < g_temp_min[sensor]) {
            g_temp_min[sensor] = status->temp_c;
        }
        if (status->temp_c > g_temp_max[sensor]) {
            g_temp_max[sensor] = status->temp_c;
        }
        status->min_c = g_temp_min[sensor];
        status->max_c = g_temp_max[sensor];

        /* Check thresholds */
        status->warning = status->temp_c > status->warning_c;
        status->critical = status->temp_c > status->critical_c;
    }

    return 0;
}

int sys_get_all_temperatures(temp_status_t *temps, uint8_t max_count)
{
    if (!temps) return -1;

    int count = (max_count < TEMP_SENSOR_COUNT) ? max_count : TEMP_SENSOR_COUNT;
    for (int i = 0; i < count; i++) {
        sys_get_temperature((temp_sensor_id_t)i, &temps[i]);
    }
    return count;
}

int16_t sys_get_fpga_temp_c(void)
{
    return xadc_to_temp(XADC_REG(XADC_REG_TEMP));
}

/*============================================================================
 * GPIO
 *============================================================================*/

void sys_get_gpio_state(gpio_state_t *state)
{
    if (!state) return;

    memset(state, 0, sizeof(*state));

    /* Read GPIO registers */
    uint32_t gpio_in = SYS_REG(REG_GPIO_IN);
    uint32_t gpio_out = SYS_REG(REG_GPIO_OUT);

    /* FDD control outputs (active low) */
    state->fdd_drive_sel = (~gpio_out >> 0) & 0x0F;
    state->fdd_motor_on = (gpio_out >> 4) & 0x01;
    state->fdd_direction = (gpio_out >> 5) & 0x01;
    state->fdd_step = (gpio_out >> 6) & 0x01;
    state->fdd_write_gate = (gpio_out >> 7) & 0x01;
    state->fdd_side_sel = (gpio_out >> 8) & 0x01;

    /* FDD status inputs (active low) */
    state->fdd_index = (~gpio_in >> 0) & 0x01;
    state->fdd_track0 = (~gpio_in >> 1) & 0x01;
    state->fdd_write_protect = (~gpio_in >> 2) & 0x01;
    state->fdd_ready = (~gpio_in >> 3) & 0x01;
    state->fdd_disk_change = (~gpio_in >> 4) & 0x01;

    /* HDD control outputs */
    state->hdd_drive_sel = (gpio_out >> 16) & 0x03;
    state->hdd_direction = (gpio_out >> 18) & 0x01;
    state->hdd_step = (gpio_out >> 19) & 0x01;
    state->hdd_write_gate = (gpio_out >> 20) & 0x01;
    state->hdd_head_sel = (gpio_out >> 21) & 0x0F;

    /* HDD status inputs */
    state->hdd_index = (gpio_in >> 8) & 0x01;
    state->hdd_track0 = (gpio_in >> 9) & 0x01;
    state->hdd_write_fault = (gpio_in >> 10) & 0x01;
    state->hdd_seek_complete = (gpio_in >> 11) & 0x01;
    state->hdd_ready = (gpio_in >> 12) & 0x01;

    /* USB PHY signals */
    state->usb_vbus = (gpio_in >> 16) & 0x01;
    state->usb_id = (gpio_in >> 17) & 0x01;
    state->usb_suspend = (gpio_in >> 18) & 0x01;

    /* Power control */
    state->pwr_enable = (gpio_out >> 24) & 0x3F;  /* 6 connector enables */
    state->pwr_8inch_mode = (gpio_out >> 30) & 0x01;

    /* LEDs */
    state->led_state = (gpio_out >> 28) & 0x03;  /* 2 LEDs */
}

/*============================================================================
 * Memory
 *============================================================================*/

void sys_get_memory_status(memory_status_t *status)
{
    if (!status) return;

    memset(status, 0, sizeof(*status));

    uint32_t bram_stat = SYS_REG(REG_BRAM_STATUS);
    uint32_t ddr_stat = SYS_REG(REG_DDR_STATUS);

    /* BRAM (typical for Artix-7) */
    status->bram_total_kb = 225;  /* 1,800 Kb = 225 KB for XC7A35T */
    status->bram_used_kb = (bram_stat >> 0) & 0xFF;

    /* Buffer allocations (from design) */
    status->flux_buffer_kb = 64;   /* 64KB flux capture buffer */
    status->sector_buffer_kb = 16; /* 16KB sector buffer */
    status->usb_buffer_kb = 8;     /* 8KB USB buffers */
    status->log_buffer_kb = 8;     /* 8KB USB logger buffer */

    /* DDR presence and size */
    status->ddr_present = (ddr_stat & 0x01) != 0;
    if (status->ddr_present) {
        status->ddr_total_mb = (ddr_stat >> 8) & 0xFF;
        status->ddr_free_mb = (ddr_stat >> 16) & 0xFF;
    }

    /* Health */
    status->bram_test_pass = (bram_stat >> 31) != 0;
    status->bram_ecc_errors = (bram_stat >> 16) & 0xFFFF;
}

int sys_run_memory_test(void)
{
    /* Trigger BRAM self-test */
    SYS_REG(REG_BRAM_STATUS) = 0x01;  /* Start test */

    /* Wait for completion */
    for (int i = 0; i < 1000; i++) {
        if (SYS_REG(REG_BRAM_STATUS) & 0x02) {  /* Test complete */
            return (SYS_REG(REG_BRAM_STATUS) >> 31) ? 0 : -1;
        }
        /* Simple delay */
        for (volatile int j = 0; j < 1000; j++);
    }

    return -1;  /* Timeout */
}
