/**
 * FluxRipper WD Controller Emulation - Implementation
 *
 * Emulates WD1003/WD1006/WD1007 compatible hard disk controllers.
 *
 * Target: AMD Spartan UltraScale+ SCU35
 * Created: 2025-12-04 21:35
 */

#include "wd_emu.h"
#include "hdd_hal.h"
#include "platform.h"
#include <string.h>

/*============================================================================
 * Private Data
 *============================================================================*/

/* Controller configuration */
static wd_config_t g_wd_config = {
    .variant = WD_VARIANT_GENERIC,
    .features = WD_FEAT_BIG_BUFFER | WD_FEAT_SET_GET_PARAMS |
                WD_FEAT_GET_DIAG | WD_FEAT_GET_ID | WD_FEAT_MULTIPLE_SECT,
    .step_rate = 3,
    .head_settle = 15,
    .irq_enabled = true,
    .buffer_enabled = true
};

/* Controller state */
static wd_controller_state_t g_wd_state = {
    .state = WD_STATE_IDLE,
    .status = WD_STATUS_RDY | WD_STATUS_SC,
    .error = 0,
    .command = 0,
    .drive = 0,
    .head = 0,
    .cylinder = 0,
    .sector = 1,
    .sector_count = 0,
    .bytes_pending = 0,
    .irq_pending = false
};

/* Last diagnostic result */
static wd_diag_result_t g_diag_result = {
    .code = WD_DIAG_OK,
    .drive0_ok = true,
    .drive1_ok = false,
    .controller_ok = true,
    .buffer_ok = true,
    .error_count = 0
};

/* Per-drive geometry (configurable via SET_PARAMS) */
static struct {
    uint16_t cylinders;
    uint8_t  heads;
    uint8_t  sectors;
    bool     valid;
} g_drive_geometry[2] = {
    { 615, 4, 17, false },  /* Default: ST-225 geometry */
    { 615, 4, 17, false }
};

/* Sector buffer pointer for data transfers */
static uint16_t g_buffer_offset = 0;

/*============================================================================
 * Private Function Declarations
 *============================================================================*/

static void wd_update_status(void);
static int  wd_exec_restore(uint8_t step_rate);
static int  wd_exec_read_sectors(bool with_retry, bool long_mode);
static int  wd_exec_write_sectors(bool with_retry, bool long_mode);
static int  wd_exec_verify(bool with_retry);
static int  wd_exec_format_track(void);
static int  wd_exec_seek(uint8_t step_rate);
static int  wd_exec_diagnostics(void);
static int  wd_exec_set_params(void);
static int  wd_exec_identify(void);
static void wd_set_error(uint8_t error);
static void wd_complete_command(void);

/*============================================================================
 * Initialization
 *============================================================================*/

int wd_init(void)
{
    /* Initialize HDD HAL if not already done */
    int ret = hdd_hal_init();
    if (ret != HAL_OK && ret != HAL_ERR_ALREADY_INIT) {
        return ret;
    }

    /* Reset controller to known state */
    wd_reset();

    /* Check for connected drives and update geometry from discovery */
    for (int drive = 0; drive < 2; drive++) {
        hdd_profile_t profile;
        if (hdd_get_profile(drive, &profile) == HAL_OK && profile.valid) {
            g_drive_geometry[drive].cylinders = profile.geometry.cylinders;
            g_drive_geometry[drive].heads = profile.geometry.heads;
            g_drive_geometry[drive].sectors = profile.geometry.sectors;
            g_drive_geometry[drive].valid = true;
        }
    }

    return HAL_OK;
}

int wd_reset(void)
{
    /* Reset controller state */
    g_wd_state.state = WD_STATE_IDLE;
    g_wd_state.status = WD_STATUS_RDY | WD_STATUS_SC;
    g_wd_state.error = 0;
    g_wd_state.command = 0;
    g_wd_state.bytes_pending = 0;
    g_wd_state.irq_pending = false;
    g_buffer_offset = 0;

    /* Reset diagnostic result */
    g_diag_result.code = WD_DIAG_OK;
    g_diag_result.error_count = 0;

    /* Invalidate track buffer */
    wd_invalidate_buffer();

    return HAL_OK;
}

/*============================================================================
 * Variant and Feature Management
 *============================================================================*/

int wd_set_variant(wd_variant_t variant)
{
    g_wd_config.variant = variant;
    g_wd_config.features = wd_variant_default_features(variant);

    /* Write to hardware register */
    REG32(WD_CONFIG) = (uint32_t)variant | (g_wd_config.features << 8);

    return HAL_OK;
}

wd_variant_t wd_get_variant(void)
{
    return g_wd_config.variant;
}

int wd_set_features(uint32_t features)
{
    g_wd_config.features = features;
    REG32(WD_CONFIG) = (uint32_t)g_wd_config.variant | (features << 8);
    return HAL_OK;
}

uint32_t wd_get_features(void)
{
    return g_wd_config.features;
}

bool wd_feature_enabled(wd_feature_t feature)
{
    return (g_wd_config.features & feature) != 0;
}

uint32_t wd_variant_default_features(wd_variant_t variant)
{
    switch (variant) {
        case WD_VARIANT_1003:
            return WD_FEAT_NONE;

        case WD_VARIANT_1006:
            return WD_FEAT_RLL27 | WD_FEAT_SET_GET_PARAMS | WD_FEAT_GET_DIAG |
                   WD_FEAT_BIG_BUFFER;

        case WD_VARIANT_1007:
            return WD_FEAT_RLL27 | WD_FEAT_SET_GET_PARAMS | WD_FEAT_GET_DIAG |
                   WD_FEAT_GET_ID | WD_FEAT_ESDI | WD_FEAT_BIG_BUFFER |
                   WD_FEAT_READ_WRITE_LONG;

        case WD_VARIANT_GENERIC:
        default:
            return WD_FEAT_RLL27 | WD_FEAT_SET_GET_PARAMS | WD_FEAT_GET_DIAG |
                   WD_FEAT_GET_ID | WD_FEAT_ESDI | WD_FEAT_BIG_BUFFER |
                   WD_FEAT_READ_WRITE_LONG | WD_FEAT_MULTIPLE_SECT |
                   WD_FEAT_CORRECTED_STAT;
    }
}

/*============================================================================
 * Geometry Management
 *============================================================================*/

int wd_set_geometry(uint8_t drive, uint16_t cylinders, uint8_t heads, uint8_t sectors)
{
    if (drive > 1) {
        return HAL_ERR_PARAM;
    }

    g_drive_geometry[drive].cylinders = cylinders;
    g_drive_geometry[drive].heads = heads;
    g_drive_geometry[drive].sectors = sectors;
    g_drive_geometry[drive].valid = true;

    /* Update hardware geometry register */
    uint32_t geom = ((uint32_t)cylinders << 16) | ((uint32_t)heads << 8) | sectors;
    REG32(WD_GEOMETRY) = geom;

    return HAL_OK;
}

int wd_get_geometry(uint8_t drive, uint16_t *cylinders, uint8_t *heads, uint8_t *sectors)
{
    if (drive > 1) {
        return HAL_ERR_PARAM;
    }

    if (cylinders) *cylinders = g_drive_geometry[drive].cylinders;
    if (heads) *heads = g_drive_geometry[drive].heads;
    if (sectors) *sectors = g_drive_geometry[drive].sectors;

    return HAL_OK;
}

/*============================================================================
 * Register Access
 *============================================================================*/

uint8_t wd_read_reg(uint8_t reg)
{
    switch (reg) {
        case 0: /* DATA - low byte (use wd_read_data for 16-bit) */
            return (uint8_t)wd_read_data();

        case 1: /* ERROR */
            return g_wd_state.error;

        case 2: /* SECTOR_COUNT */
            return g_wd_state.sector_count;

        case 3: /* SECTOR_NUMBER */
            return g_wd_state.sector;

        case 4: /* CYL_LOW */
            return (uint8_t)(g_wd_state.cylinder & 0xFF);

        case 5: /* CYL_HIGH */
            return (uint8_t)((g_wd_state.cylinder >> 8) & 0xFF);

        case 6: /* SDH */
            return (0x02 << 5) |  /* 512-byte sectors */
                   (g_wd_state.drive << 4) |
                   (g_wd_state.head & 0x0F);

        case 7: /* STATUS */
            /* Reading status clears interrupt */
            wd_irq_ack();
            return g_wd_state.status;

        default:
            return 0xFF;
    }
}

void wd_write_reg(uint8_t reg, uint8_t value)
{
    /* Cannot write while busy (except reset via control register) */
    if ((g_wd_state.status & WD_STATUS_BSY) && reg != 7) {
        return;
    }

    switch (reg) {
        case 0: /* DATA - low byte (use wd_write_data for 16-bit) */
            wd_write_data((uint16_t)value);
            break;

        case 1: /* FEATURES (write) */
            /* Feature register value stored for command use */
            break;

        case 2: /* SECTOR_COUNT */
            g_wd_state.sector_count = value;
            break;

        case 3: /* SECTOR_NUMBER */
            g_wd_state.sector = value;
            break;

        case 4: /* CYL_LOW */
            g_wd_state.cylinder = (g_wd_state.cylinder & 0xFF00) | value;
            break;

        case 5: /* CYL_HIGH */
            g_wd_state.cylinder = (g_wd_state.cylinder & 0x00FF) | ((uint16_t)value << 8);
            break;

        case 6: /* SDH */
            g_wd_state.drive = (value >> 4) & 0x01;
            g_wd_state.head = value & 0x0F;
            /* Select drive in HDD HAL */
            hdd_select_drive(g_wd_state.drive);
            break;

        case 7: /* COMMAND */
            wd_process_command(value);
            break;
    }
}

uint16_t wd_read_data(void)
{
    uint16_t data = 0;

    if (g_wd_state.state == WD_STATE_DATA_OUT &&
        (g_wd_state.status & WD_STATUS_DRQ)) {
        /* Read from hardware buffer */
        REG32(WD_BUFFER_ADDR) = g_buffer_offset;
        data = (uint16_t)REG32(WD_BUFFER_DATA);
        g_buffer_offset += 2;
        g_wd_state.bytes_pending -= 2;

        if (g_wd_state.bytes_pending == 0) {
            /* Sector complete */
            g_wd_state.sector_count--;
            if (g_wd_state.sector_count == 0) {
                /* All sectors transferred */
                wd_complete_command();
            } else {
                /* More sectors - advance to next */
                g_wd_state.sector++;
                if (g_wd_state.sector > g_drive_geometry[g_wd_state.drive].sectors) {
                    g_wd_state.sector = 1;
                    g_wd_state.head++;
                    if (g_wd_state.head >= g_drive_geometry[g_wd_state.drive].heads) {
                        g_wd_state.head = 0;
                        g_wd_state.cylinder++;
                    }
                }
                g_wd_state.bytes_pending = 512;
                g_buffer_offset = 0;
                /* Read next sector */
                hdd_read_sector(g_wd_state.drive, g_wd_state.cylinder,
                               g_wd_state.head, g_wd_state.sector, NULL);
            }
        }
    }

    return data;
}

void wd_write_data(uint16_t value)
{
    if (g_wd_state.state == WD_STATE_DATA_IN &&
        (g_wd_state.status & WD_STATUS_DRQ)) {
        /* Write to hardware buffer */
        REG32(WD_BUFFER_ADDR) = g_buffer_offset;
        REG32(WD_BUFFER_DATA) = value;
        g_buffer_offset += 2;
        g_wd_state.bytes_pending -= 2;

        if (g_wd_state.bytes_pending == 0) {
            /* Sector complete - write to disk */
            g_wd_state.status &= ~WD_STATUS_DRQ;
            g_wd_state.status |= WD_STATUS_BSY;
            g_wd_state.state = WD_STATE_WRITE;
            /* Hardware will handle actual write */
        }
    }
}

/*============================================================================
 * Command Processing
 *============================================================================*/

int wd_process_command(uint8_t cmd)
{
    /* Store command */
    g_wd_state.command = cmd;
    g_wd_state.status |= WD_STATUS_BSY;
    g_wd_state.status &= ~(WD_STATUS_DRQ | WD_STATUS_ERR);
    g_wd_state.error = 0;
    g_wd_state.state = WD_STATE_COMMAND;

    /* Write command to hardware */
    REG32(WD_STATUS_CMD) = cmd;

    /* Decode command class */
    if ((cmd & WD_CMD_RESTORE_MASK) == WD_CMD_RESTORE_BASE) {
        /* RESTORE (0x10-0x1F) - step rate in low nibble */
        return wd_exec_restore(cmd & 0x0F);
    }

    if ((cmd & WD_CMD_SEEK_MASK) == WD_CMD_SEEK_BASE) {
        /* SEEK (0x70-0x7F) - step rate in low nibble */
        return wd_exec_seek(cmd & 0x0F);
    }

    /* Specific commands */
    switch (cmd) {
        case WD_CMD_READ_SECTORS:
        case WD_CMD_READ_SECTORS_NR:
            return wd_exec_read_sectors(cmd == WD_CMD_READ_SECTORS, false);

        case WD_CMD_READ_LONG:
        case WD_CMD_READ_LONG_NR:
            if (!wd_feature_enabled(WD_FEAT_READ_WRITE_LONG)) {
                wd_set_error(WD_ERROR_ABRT);
                return HAL_ERR_NOT_SUPPORTED;
            }
            return wd_exec_read_sectors(cmd == WD_CMD_READ_LONG, true);

        case WD_CMD_WRITE_SECTORS:
        case WD_CMD_WRITE_SECTORS_NR:
            return wd_exec_write_sectors(cmd == WD_CMD_WRITE_SECTORS, false);

        case WD_CMD_WRITE_LONG:
        case WD_CMD_WRITE_LONG_NR:
            if (!wd_feature_enabled(WD_FEAT_READ_WRITE_LONG)) {
                wd_set_error(WD_ERROR_ABRT);
                return HAL_ERR_NOT_SUPPORTED;
            }
            return wd_exec_write_sectors(cmd == WD_CMD_WRITE_LONG, true);

        case WD_CMD_VERIFY:
        case WD_CMD_VERIFY_NR:
            return wd_exec_verify(cmd == WD_CMD_VERIFY);

        case WD_CMD_FORMAT_TRACK:
            return wd_exec_format_track();

        case WD_CMD_EXEC_DIAG:
            if (!wd_feature_enabled(WD_FEAT_GET_DIAG)) {
                wd_set_error(WD_ERROR_ABRT);
                return HAL_ERR_NOT_SUPPORTED;
            }
            return wd_exec_diagnostics();

        case WD_CMD_SET_PARAMS:
            if (!wd_feature_enabled(WD_FEAT_SET_GET_PARAMS)) {
                wd_set_error(WD_ERROR_ABRT);
                return HAL_ERR_NOT_SUPPORTED;
            }
            return wd_exec_set_params();

        case WD_CMD_IDENTIFY:
            if (!wd_feature_enabled(WD_FEAT_GET_ID)) {
                wd_set_error(WD_ERROR_ABRT);
                return HAL_ERR_NOT_SUPPORTED;
            }
            return wd_exec_identify();

        default:
            /* Unknown command */
            wd_set_error(WD_ERROR_ABRT);
            return HAL_ERR_CMD;
    }
}

bool wd_poll(void)
{
    /* Check hardware status for completion */
    uint32_t hw_status = REG32(WD_STATUS_CMD);

    if (!(hw_status & WD_STATUS_BSY)) {
        /* Command complete */
        if (g_wd_state.state != WD_STATE_IDLE &&
            g_wd_state.state != WD_STATE_DATA_IN &&
            g_wd_state.state != WD_STATE_DATA_OUT) {
            wd_complete_command();
        }
        return true;
    }

    return false;
}

/*============================================================================
 * Command Execution Helpers
 *============================================================================*/

static int wd_exec_restore(uint8_t step_rate)
{
    (void)step_rate;

    g_wd_state.state = WD_STATE_SEEK;
    g_wd_state.cylinder = 0;

    /* Recalibrate via HDD HAL */
    int ret = hdd_recalibrate(g_wd_state.drive);
    if (ret != HAL_OK) {
        wd_set_error(WD_ERROR_TK0NF);
        return ret;
    }

    return HAL_OK;
}

static int wd_exec_read_sectors(bool with_retry, bool long_mode)
{
    (void)with_retry;
    (void)long_mode;

    /* Validate parameters */
    if (g_wd_state.sector == 0 ||
        g_wd_state.sector > g_drive_geometry[g_wd_state.drive].sectors) {
        wd_set_error(WD_ERROR_IDNF);
        return HAL_ERR_PARAM;
    }

    g_wd_state.state = WD_STATE_READ;
    g_buffer_offset = 0;
    g_wd_state.bytes_pending = 512;  /* One sector at a time */

    /* Start read via HDD HAL */
    int ret = hdd_read_sector(g_wd_state.drive, g_wd_state.cylinder,
                              g_wd_state.head, g_wd_state.sector, NULL);
    if (ret != HAL_OK) {
        wd_set_error(WD_ERROR_IDNF);
        return ret;
    }

    /* Set DRQ - data ready for host */
    g_wd_state.status &= ~WD_STATUS_BSY;
    g_wd_state.status |= WD_STATUS_DRQ;
    g_wd_state.state = WD_STATE_DATA_OUT;

    /* Generate interrupt if enabled */
    if (g_wd_config.irq_enabled) {
        g_wd_state.irq_pending = true;
    }

    return HAL_OK;
}

static int wd_exec_write_sectors(bool with_retry, bool long_mode)
{
    (void)with_retry;
    (void)long_mode;

    /* Validate parameters */
    if (g_wd_state.sector == 0 ||
        g_wd_state.sector > g_drive_geometry[g_wd_state.drive].sectors) {
        wd_set_error(WD_ERROR_IDNF);
        return HAL_ERR_PARAM;
    }

    g_wd_state.state = WD_STATE_DATA_IN;
    g_buffer_offset = 0;
    g_wd_state.bytes_pending = 512;

    /* Set DRQ - ready for data from host */
    g_wd_state.status &= ~WD_STATUS_BSY;
    g_wd_state.status |= WD_STATUS_DRQ;

    return HAL_OK;
}

static int wd_exec_verify(bool with_retry)
{
    (void)with_retry;

    g_wd_state.state = WD_STATE_VERIFY;

    /* Verify reads data but doesn't transfer to host */
    /* Hardware handles verification */

    return HAL_OK;
}

static int wd_exec_format_track(void)
{
    g_wd_state.state = WD_STATE_FORMAT;

    /* Format is handled by hardware */
    /* Set DRQ for format data (interleave table) */
    g_wd_state.status &= ~WD_STATUS_BSY;
    g_wd_state.status |= WD_STATUS_DRQ;
    g_wd_state.bytes_pending = 512;  /* Format data buffer */
    g_buffer_offset = 0;

    return HAL_OK;
}

static int wd_exec_seek(uint8_t step_rate)
{
    (void)step_rate;

    g_wd_state.state = WD_STATE_SEEK;

    /* Seek via HDD HAL */
    int ret = hdd_seek(g_wd_state.drive, g_wd_state.cylinder);
    if (ret != HAL_OK) {
        wd_set_error(WD_ERROR_IDNF);
        return ret;
    }

    return HAL_OK;
}

static int wd_exec_diagnostics(void)
{
    g_wd_state.state = WD_STATE_DIAG;

    /* Run diagnostics */
    wd_run_diagnostics(&g_diag_result);

    /* Diagnostic result goes in error register */
    g_wd_state.error = g_diag_result.code;

    wd_complete_command();

    return HAL_OK;
}

static int wd_exec_set_params(void)
{
    /* SET_PARAMS uses sector count and SDH to set max values */
    uint8_t max_head = g_wd_state.head;
    uint8_t max_sector = g_wd_state.sector_count;

    /* Cylinder count comes from CYL registers */
    uint16_t max_cylinder = g_wd_state.cylinder;

    wd_set_geometry(g_wd_state.drive, max_cylinder, max_head + 1, max_sector);

    wd_complete_command();

    return HAL_OK;
}

static int wd_exec_identify(void)
{
    g_wd_state.state = WD_STATE_DATA_OUT;
    g_buffer_offset = 0;
    g_wd_state.bytes_pending = 512;  /* 256 words */

    /* Build identify data in buffer */
    /* This is a simplified identify block */
    uint16_t *id_buf = (uint16_t *)0x80007200;  /* Buffer address */

    memset(id_buf, 0, 512);

    /* Word 0: General config (fixed disk) */
    id_buf[0] = 0x0040;

    /* Word 1: Number of cylinders */
    id_buf[1] = g_drive_geometry[g_wd_state.drive].cylinders;

    /* Word 3: Number of heads */
    id_buf[3] = g_drive_geometry[g_wd_state.drive].heads;

    /* Word 6: Sectors per track */
    id_buf[6] = g_drive_geometry[g_wd_state.drive].sectors;

    /* Words 10-19: Serial number (ASCII) */
    memcpy(&id_buf[10], "FLUXRIPPER0001  ", 20);

    /* Words 23-26: Firmware revision (ASCII) */
    memcpy(&id_buf[23], "1.00    ", 8);

    /* Words 27-46: Model number (ASCII) */
    memcpy(&id_buf[27], "FluxRipper WD Emulation         ", 40);

    /* Word 47: Max sectors per interrupt */
    id_buf[47] = 1;

    /* Word 49: Capabilities */
    id_buf[49] = 0x0200;  /* LBA supported */

    /* Set DRQ - data ready for host */
    g_wd_state.status &= ~WD_STATUS_BSY;
    g_wd_state.status |= WD_STATUS_DRQ;

    if (g_wd_config.irq_enabled) {
        g_wd_state.irq_pending = true;
    }

    return HAL_OK;
}

static void wd_set_error(uint8_t error)
{
    g_wd_state.error = error;
    g_wd_state.status |= WD_STATUS_ERR;
    g_wd_state.status &= ~(WD_STATUS_BSY | WD_STATUS_DRQ);
    g_wd_state.state = WD_STATE_ERROR;

    if (g_wd_config.irq_enabled) {
        g_wd_state.irq_pending = true;
    }
}

static void wd_complete_command(void)
{
    g_wd_state.status &= ~(WD_STATUS_BSY | WD_STATUS_DRQ);
    g_wd_state.status |= WD_STATUS_RDY | WD_STATUS_SC;
    g_wd_state.state = WD_STATE_IDLE;

    if (g_wd_config.irq_enabled) {
        g_wd_state.irq_pending = true;
    }
}

static void wd_update_status(void)
{
    /* Update status from hardware */
    uint32_t hw_status = REG32(WD_STATUS_CMD);
    g_wd_state.status = (uint8_t)hw_status;

    /* Update drive status from HDD HAL */
    bool ready;
    uint16_t cylinder;
    bool seeking;

    if (hdd_get_status(g_wd_state.drive, &ready, &cylinder, &seeking) == HAL_OK) {
        if (ready) {
            g_wd_state.status |= WD_STATUS_RDY;
        } else {
            g_wd_state.status &= ~WD_STATUS_RDY;
        }

        if (!seeking) {
            g_wd_state.status |= WD_STATUS_SC;
        } else {
            g_wd_state.status &= ~WD_STATUS_SC;
        }
    }
}

/*============================================================================
 * State and Status Functions
 *============================================================================*/

int wd_get_state(wd_controller_state_t *state)
{
    if (!state) {
        return HAL_ERR_PARAM;
    }

    wd_update_status();
    memcpy(state, &g_wd_state, sizeof(wd_controller_state_t));

    return HAL_OK;
}

int wd_abort_command(void)
{
    g_wd_state.status &= ~(WD_STATUS_BSY | WD_STATUS_DRQ);
    g_wd_state.status |= WD_STATUS_RDY;
    g_wd_state.error = WD_ERROR_ABRT;
    g_wd_state.status |= WD_STATUS_ERR;
    g_wd_state.state = WD_STATE_IDLE;

    return HAL_OK;
}

uint8_t wd_get_status(void)
{
    wd_update_status();
    return g_wd_state.status;
}

uint8_t wd_get_error(void)
{
    return g_wd_state.error;
}

bool wd_is_busy(void)
{
    return (g_wd_state.status & WD_STATUS_BSY) != 0;
}

bool wd_drq_pending(void)
{
    return (g_wd_state.status & WD_STATUS_DRQ) != 0;
}

/*============================================================================
 * Track Buffer Functions
 *============================================================================*/

int wd_get_buffer_status(wd_buffer_status_t *status)
{
    if (!status) {
        return HAL_ERR_PARAM;
    }

    /* Read from hardware */
    uint32_t buf_status = REG32(WD_BASE + 0x74);  /* Buffer status register */

    status->current_track = (buf_status >> 16) & 0xFFFF;
    status->current_head = (buf_status >> 12) & 0x0F;
    status->buffer_state = (buf_status >> 8) & 0x03;
    status->valid_bitmap = REG32(WD_BASE + 0x78);
    status->dirty_bitmap = REG32(WD_BASE + 0x7C);
    status->fill_count = 0;  /* Not tracked in this implementation */
    status->flush_count = 0;

    return HAL_OK;
}

int wd_flush_buffer(void)
{
    /* Command hardware to flush dirty sectors */
    REG32(WD_CTRL) |= BIT(8);  /* Flush bit */

    /* Wait for flush complete */
    for (int i = 0; i < 1000; i++) {
        if (!(REG32(WD_CTRL) & BIT(8))) {
            return HAL_OK;
        }
        /* Small delay */
        for (volatile int j = 0; j < 100; j++);
    }

    return HAL_ERR_TIMEOUT;
}

int wd_invalidate_buffer(void)
{
    /* Command hardware to invalidate buffer */
    REG32(WD_CTRL) |= BIT(9);  /* Invalidate bit */
    REG32(WD_CTRL) &= ~BIT(9);

    return HAL_OK;
}

/*============================================================================
 * Diagnostics
 *============================================================================*/

int wd_run_diagnostics(wd_diag_result_t *result)
{
    if (!result) {
        return HAL_ERR_PARAM;
    }

    result->code = WD_DIAG_OK;
    result->controller_ok = true;
    result->buffer_ok = true;
    result->error_count = 0;

    /* Check drive 0 */
    bool ready0 = hdd_is_ready(HDD_DRIVE_0);
    result->drive0_ok = ready0;
    if (!ready0) {
        result->code |= WD_DIAG_DRIVE0_FAIL;
        result->error_count++;
    }

    /* Check drive 1 */
    bool ready1 = hdd_is_ready(HDD_DRIVE_1);
    result->drive1_ok = ready1;
    if (!ready1) {
        result->code |= WD_DIAG_DRIVE1_FAIL;
        result->error_count++;
    }

    /* Test buffer by writing and reading pattern */
    REG32(WD_BUFFER_ADDR) = 0;
    REG32(WD_BUFFER_DATA) = 0xA5A5;
    REG32(WD_BUFFER_ADDR) = 0;
    if (REG32(WD_BUFFER_DATA) != 0xA5A5) {
        result->buffer_ok = false;
        result->code = WD_DIAG_BUFFER_ERROR;
        result->error_count++;
    }

    /* Store result */
    memcpy(&g_diag_result, result, sizeof(wd_diag_result_t));

    return HAL_OK;
}

int wd_get_diag_result(wd_diag_result_t *result)
{
    if (!result) {
        return HAL_ERR_PARAM;
    }

    memcpy(result, &g_diag_result, sizeof(wd_diag_result_t));
    return HAL_OK;
}

/*============================================================================
 * Interrupt Management
 *============================================================================*/

int wd_set_irq_enable(bool enable)
{
    g_wd_config.irq_enabled = enable;

    if (enable) {
        REG32(WD_IRQ_MASK) = 0xFFFFFFFF;  /* Enable all IRQ sources */
    } else {
        REG32(WD_IRQ_MASK) = 0;
    }

    return HAL_OK;
}

bool wd_irq_pending(void)
{
    return g_wd_state.irq_pending;
}

void wd_irq_ack(void)
{
    g_wd_state.irq_pending = false;
    REG32(WD_IRQ_STATUS) = 0xFFFFFFFF;  /* Clear all pending IRQs */
}

/*============================================================================
 * Configuration
 *============================================================================*/

int wd_get_config(wd_config_t *config)
{
    if (!config) {
        return HAL_ERR_PARAM;
    }

    memcpy(config, &g_wd_config, sizeof(wd_config_t));
    return HAL_OK;
}

int wd_set_config(const wd_config_t *config)
{
    if (!config) {
        return HAL_ERR_PARAM;
    }

    memcpy(&g_wd_config, config, sizeof(wd_config_t));

    /* Apply configuration to hardware */
    uint32_t cfg = (uint32_t)config->variant |
                   (config->features << 8);
    REG32(WD_CONFIG) = cfg;

    wd_set_irq_enable(config->irq_enabled);

    return HAL_OK;
}

/*============================================================================
 * Utility Functions
 *============================================================================*/

const char *wd_variant_to_string(wd_variant_t variant)
{
    switch (variant) {
        case WD_VARIANT_1003:   return "WD1003";
        case WD_VARIANT_1006:   return "WD1006";
        case WD_VARIANT_1007:   return "WD1007";
        case WD_VARIANT_GENERIC: return "Generic";
        default:                return "Unknown";
    }
}

const char *wd_cmd_to_string(uint8_t cmd)
{
    if ((cmd & WD_CMD_RESTORE_MASK) == WD_CMD_RESTORE_BASE) {
        return "RESTORE";
    }
    if ((cmd & WD_CMD_SEEK_MASK) == WD_CMD_SEEK_BASE) {
        return "SEEK";
    }

    switch (cmd) {
        case WD_CMD_READ_SECTORS:     return "READ SECTORS";
        case WD_CMD_READ_SECTORS_NR:  return "READ SECTORS (NR)";
        case WD_CMD_READ_LONG:        return "READ LONG";
        case WD_CMD_READ_LONG_NR:     return "READ LONG (NR)";
        case WD_CMD_WRITE_SECTORS:    return "WRITE SECTORS";
        case WD_CMD_WRITE_SECTORS_NR: return "WRITE SECTORS (NR)";
        case WD_CMD_WRITE_LONG:       return "WRITE LONG";
        case WD_CMD_WRITE_LONG_NR:    return "WRITE LONG (NR)";
        case WD_CMD_VERIFY:           return "VERIFY";
        case WD_CMD_VERIFY_NR:        return "VERIFY (NR)";
        case WD_CMD_FORMAT_TRACK:     return "FORMAT TRACK";
        case WD_CMD_EXEC_DIAG:        return "DIAGNOSTICS";
        case WD_CMD_SET_PARAMS:       return "SET PARAMS";
        case WD_CMD_IDENTIFY:         return "IDENTIFY";
        default:                      return "UNKNOWN";
    }
}

const char *wd_state_to_string(wd_state_t state)
{
    switch (state) {
        case WD_STATE_IDLE:       return "IDLE";
        case WD_STATE_COMMAND:    return "COMMAND";
        case WD_STATE_DATA_IN:    return "DATA_IN";
        case WD_STATE_DATA_OUT:   return "DATA_OUT";
        case WD_STATE_DRQ_WAIT:   return "DRQ_WAIT";
        case WD_STATE_SEEK:       return "SEEK";
        case WD_STATE_READ:       return "READ";
        case WD_STATE_WRITE:      return "WRITE";
        case WD_STATE_VERIFY:     return "VERIFY";
        case WD_STATE_FORMAT:     return "FORMAT";
        case WD_STATE_DIAG:       return "DIAG";
        case WD_STATE_COMPLETE:   return "COMPLETE";
        case WD_STATE_ERROR:      return "ERROR";
        default:                  return "UNKNOWN";
    }
}

const char *wd_error_to_string(uint8_t error)
{
    if (error == 0) return "No error";
    if (error & WD_ERROR_BBK)   return "Bad Block";
    if (error & WD_ERROR_UNC)   return "Uncorrectable";
    if (error & WD_ERROR_IDNF)  return "ID Not Found";
    if (error & WD_ERROR_ABRT)  return "Command Aborted";
    if (error & WD_ERROR_TK0NF) return "Track 0 Not Found";
    if (error & WD_ERROR_AMNF)  return "Address Mark Not Found";
    return "Unknown error";
}

/*============================================================================
 * Identify Drive Response Building
 *============================================================================*/

/**
 * Copy string to ATA identify field with space padding
 * ATA strings are stored in big-endian word format with space padding
 */
static void ata_string_copy(char *dest, const char *src, size_t len)
{
    size_t i;
    size_t src_len = src ? strlen(src) : 0;

    /* Copy source, swapping bytes within each word */
    for (i = 0; i < len; i += 2) {
        char c1 = (i < src_len) ? src[i] : ' ';
        char c2 = (i + 1 < src_len) ? src[i + 1] : ' ';
        /* ATA uses swapped byte order within words */
        dest[i] = c2;
        dest[i + 1] = c1;
    }
}

int wd_build_identify_from_meta(const hdd_metadata_t *meta, wd_identify_t *identify)
{
    if (identify == NULL) {
        return HAL_ERR_PARAM;
    }

    /* Clear structure */
    memset(identify, 0, sizeof(wd_identify_t));

    /* Word 0: Configuration
     * Bit 15: 0 = ATA device
     * Bit 7:  1 = Removable media (0 for HDD)
     * Bit 6:  1 = Fixed drive
     * Bit 0:  0 = Reserved
     */
    identify->config = 0x0040;  /* Fixed drive */

    if (meta != NULL && meta->valid) {
        /* Use discovered geometry from fingerprint */
        identify->cylinders = meta->fingerprint.max_cylinder;
        identify->heads = meta->fingerprint.heads;
        identify->sectors_per_track = meta->fingerprint.spt_outer;  /* Use outer zone SPT */

        /* Use user-supplied serial number if available */
        if (meta->identity.serial[0] != '\0') {
            ata_string_copy(identify->serial_number, meta->identity.serial, 20);
        } else {
            /* Generate from UUID */
            char serial[21];
            snprintf(serial, sizeof(serial), "FLXR%08X%04X",
                     meta->guid.data1, meta->guid.data2);
            ata_string_copy(identify->serial_number, serial, 20);
        }

        /* Build model number from vendor + model */
        char model[41];
        if (meta->identity.vendor[0] != '\0' && meta->identity.model[0] != '\0') {
            snprintf(model, sizeof(model), "%-8s %-24s",
                     meta->identity.vendor, meta->identity.model);
        } else if (meta->identity.model[0] != '\0') {
            snprintf(model, sizeof(model), "%-40s", meta->identity.model);
        } else {
            snprintf(model, sizeof(model), "FluxRipper Virtual HDD       ");
        }
        ata_string_copy(identify->model_number, model, 40);

        /* Firmware revision from metadata or default */
        if (meta->identity.revision[0] != '\0') {
            ata_string_copy(identify->firmware_rev, meta->identity.revision, 8);
        } else {
            ata_string_copy(identify->firmware_rev, "FLXR1.0", 8);
        }

        /* Current geometry matches discovered */
        identify->cur_cylinders = identify->cylinders;
        identify->cur_heads = identify->heads;
        identify->cur_sectors = identify->sectors_per_track;

        /* Calculate capacity */
        uint32_t capacity = (uint32_t)identify->cylinders *
                           (uint32_t)identify->heads *
                           (uint32_t)identify->sectors_per_track;
        identify->cur_capacity = capacity;
        identify->total_sectors_lba = capacity;

    } else {
        /* No metadata - use defaults */
        identify->cylinders = 615;
        identify->heads = 4;
        identify->sectors_per_track = 17;

        ata_string_copy(identify->serial_number, "FLXR00000000", 20);
        ata_string_copy(identify->model_number, "FluxRipper Virtual HDD", 40);
        ata_string_copy(identify->firmware_rev, "FLXR1.0", 8);

        identify->cur_cylinders = 615;
        identify->cur_heads = 4;
        identify->cur_sectors = 17;
        identify->cur_capacity = 615 * 4 * 17;
        identify->total_sectors_lba = 615 * 4 * 17;
    }

    /* Words 4-5: Unformatted bytes per track/sector */
    identify->unformatted_bpt = identify->sectors_per_track * 512;
    identify->unformatted_bps = 512;

    /* Word 20-21: Buffer info */
    identify->buffer_type = 3;      /* Dual-ported, multi-sector */
    identify->buffer_size = 17;     /* 17 sectors (track buffer) */

    /* Word 22: ECC bytes */
    identify->ecc_bytes = 4;        /* 4 ECC bytes per sector */

    /* Word 47: Max multi-sector */
    identify->max_multi_sect = 16;

    /* Word 49: Capabilities
     * Bit 9: LBA supported
     * Bit 8: DMA supported
     */
    identify->capabilities = 0x0000; /* Basic ST-506/ESDI - no LBA, no DMA */

    /* Word 51-52: PIO/DMA timing */
    identify->pio_timing_mode = 0;   /* Mode 0 */
    identify->dma_timing_mode = 0;

    /* Word 53: Field validity (none of the extended fields are valid) */
    identify->field_validity = 0;

    return HAL_OK;
}

int wd_build_identify(uint8_t drive, wd_identify_t *identify)
{
    if (drive > 1 || identify == NULL) {
        return HAL_ERR_PARAM;
    }

    /* Try to read metadata from drive */
    hdd_metadata_t meta;
    meta_error_t err = meta_read(drive, &meta);

    if (err == META_OK) {
        return wd_build_identify_from_meta(&meta, identify);
    } else {
        /* No metadata - build with defaults */
        return wd_build_identify_from_meta(NULL, identify);
    }
}

void wd_print_identify(const wd_identify_t *identify)
{
    if (identify == NULL) {
        printf("Identify: NULL\n");
        return;
    }

    /* Unshuffle ATA strings for printing */
    char serial[21], model[41], firmware[9];
    int i;

    for (i = 0; i < 20; i += 2) {
        serial[i] = identify->serial_number[i + 1];
        serial[i + 1] = identify->serial_number[i];
    }
    serial[20] = '\0';

    for (i = 0; i < 40; i += 2) {
        model[i] = identify->model_number[i + 1];
        model[i + 1] = identify->model_number[i];
    }
    model[40] = '\0';

    for (i = 0; i < 8; i += 2) {
        firmware[i] = identify->firmware_rev[i + 1];
        firmware[i + 1] = identify->firmware_rev[i];
    }
    firmware[8] = '\0';

    printf("\n=== IDENTIFY DRIVE Response ===\n");
    printf("Model:          %.40s\n", model);
    printf("Serial:         %.20s\n", serial);
    printf("Firmware:       %.8s\n", firmware);
    printf("\nGeometry:\n");
    printf("  Cylinders:    %u\n", identify->cylinders);
    printf("  Heads:        %u\n", identify->heads);
    printf("  Sectors/Trk:  %u\n", identify->sectors_per_track);
    printf("  Capacity:     %u sectors (%u MB)\n",
           identify->total_sectors_lba,
           identify->total_sectors_lba / 2048);
    printf("\nBuffer:         %u KB (%u sectors)\n",
           identify->buffer_size / 2, identify->buffer_size);
    printf("ECC Bytes:      %u\n", identify->ecc_bytes);
    printf("\n");
}
