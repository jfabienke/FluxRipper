/**
 * FluxRipper HDD HAL Driver - Implementation
 *
 * Hardware Abstraction Layer for ST-506/ESDI Hard Drives
 * Dual-drive support for independent drive operations.
 *
 * Target: AMD Spartan UltraScale+ SCU35
 * Created: 2025-12-04 09:27:34
 * Updated: 2025-12-04 18:20 - Added ESDI configuration support (GET_DEV_CONFIG)
 */

#include "hdd_hal.h"
#include "platform.h"
#include <string.h>

/*============================================================================
 * Internal State - Per-Drive
 *============================================================================*/

typedef struct {
    hdd_profile_t   profile;
    uint16_t        current_cylinder;
    uint8_t         current_head;
    bool            detection_done;
} hdd_drive_state_t;

static struct {
    bool                initialized;
    uint8_t             active_drive;       /* Currently selected drive for NCO */
    hdd_drive_state_t   drive[HDD_NUM_DRIVES];
} hdd_state = {
    .initialized = false,
    .active_drive = HDD_DRIVE_0
};

/*============================================================================
 * Internal Helper Functions
 *============================================================================*/

/**
 * Get current time in milliseconds
 */
extern uint32_t get_time_ms(void);

/**
 * Delay in milliseconds
 */
extern void delay_ms(uint32_t ms);

/**
 * Read 32-bit register
 */
static inline uint32_t hdd_read_reg(uint32_t addr)
{
    return REG32(addr);
}

/**
 * Write 32-bit register
 */
static inline void hdd_write_reg(uint32_t addr, uint32_t value)
{
    REG32(addr) = value;
}

/**
 * Validate drive number
 */
static inline bool valid_drive(uint8_t drive)
{
    return drive < HDD_NUM_DRIVES;
}

/**
 * Wait for detection to complete
 */
static int wait_detection_done(uint32_t timeout_ms)
{
    uint32_t start = get_time_ms();

    while ((get_time_ms() - start) < timeout_ms) {
        uint32_t status = hdd_read_reg(HDD_DETECT_STATUS);
        if (status & DETECT_STAT_DONE) {
            return HAL_OK;
        }
        if (status & DETECT_STAT_ERROR) {
            return HAL_ERR_HARDWARE;
        }
        delay_ms(10);
    }

    return HAL_ERR_TIMEOUT;
}

/**
 * Wait for discovery to complete
 */
static int wait_discovery_done(uint32_t timeout_ms)
{
    uint32_t start = get_time_ms();

    while ((get_time_ms() - start) < timeout_ms) {
        uint32_t status = hdd_read_reg(HDD_DISCOVER_STATUS);
        if (status & DISCOVER_STAT_DONE) {
            return HAL_OK;
        }
        delay_ms(50);
    }

    return HAL_ERR_TIMEOUT;
}

/**
 * Wait for seek to complete on specified drive
 */
static int wait_seek_done(uint8_t drive, uint32_t timeout_ms)
{
    uint32_t start = get_time_ms();

    while ((get_time_ms() - start) < timeout_ms) {
        uint32_t status = hdd_read_reg(HDD_STATUS(drive));
        if (status & HDD_STAT_SEEK_DONE) {
            return HAL_OK;
        }
        if (status & HDD_STAT_SEEK_ERROR) {
            return HAL_ERR_HARDWARE;
        }
        delay_ms(1);
    }

    return HAL_ERR_TIMEOUT;
}

/**
 * Unpack detection result from register
 */
static void unpack_detection(uint32_t reg_val, uint32_t scores_val,
                             hdd_detection_t *result)
{
    result->type = (hdd_type_t)(reg_val & DETECT_RESULT_TYPE_MASK);
    result->confidence = (reg_val >> 4) & 0x0F;
    result->phy_mode = (hdd_phy_mode_t)((reg_val >> 8) & 0x03);
    result->rate = (hdd_rate_t)((reg_val >> 12) & 0x07);
    result->was_forced = (reg_val & DETECT_RESULT_FORCED) != 0;

    /* Unpack evidence scores */
    result->score_floppy = (scores_val >> 0) & 0xFF;
    result->score_hdd = (scores_val >> 8) & 0xFF;
    result->score_st506 = (scores_val >> 16) & 0xFF;
    result->score_esdi = (scores_val >> 24) & 0xFF;

    /* MFM/RLL scores from extended register (if available) */
    result->score_mfm = 0;
    result->score_rll = 0;
}

/**
 * Unpack geometry from per-drive register
 */
static void unpack_geometry(uint8_t drive, hdd_geometry_t *geom)
{
    /* Read geometry registers */
    uint32_t geom_a = hdd_read_reg(HDD_GEOMETRY_A);
    uint32_t geom_b = hdd_read_reg(HDD_GEOMETRY_B);
    uint32_t encode_result = hdd_read_reg(HDD_ENCODE_RESULT);

    geom->cylinders = (geom_a >> 16) & 0xFFFF;
    geom->heads = geom_a & 0x0F;
    geom->sectors = geom_b & 0xFF;
    geom->interleave = (geom_b >> 8) & 0xFF;
    geom->skew = (geom_b >> 16) & 0xFF;
    geom->sector_size = 512;  /* Default */

    /* Check if geometry came from ESDI config */
    geom->from_esdi_config = (encode_result & ENCODE_RESULT_ESDI_CONFIG) != 0;

    /* Calculate totals */
    geom->total_sectors = (uint32_t)geom->cylinders * geom->heads * geom->sectors;
    geom->capacity_mb = (geom->total_sectors * geom->sector_size) / (1024 * 1024);
}

/**
 * Unpack health from per-drive register
 */
static void unpack_health(uint8_t drive, hdd_health_t *health)
{
    uint32_t health_reg = hdd_read_reg(HDD_HEALTH(drive));
    uint32_t status = hdd_read_reg(HDD_STATUS(drive));

    health->rpm = health_reg & 0xFFFF;
    health->rpm_variance = (health_reg >> 16) & 0xFFFF;
    health->seek_avg_ms = 0;  /* Would need additional register */
    health->seek_max_ms = 0;
    health->signal_quality = 0;
    health->error_rate = 0;
    health->ready = (status & HDD_STAT_READY) != 0;
    health->spinning = health->ready;  /* Assume spinning if ready */
}

/*============================================================================
 * HDD HAL API Implementation - Dual-Drive
 *============================================================================*/

int hdd_hal_init(void)
{
    if (hdd_state.initialized) {
        return HAL_OK;
    }

    /* Reset HDD subsystem */
    hdd_write_reg(HDD_CTRL, 0);
    hdd_write_reg(HDD_DETECT_CTRL, 0);
    delay_ms(10);

    /* Initialize per-drive state */
    for (int i = 0; i < HDD_NUM_DRIVES; i++) {
        memset(&hdd_state.drive[i].profile, 0, sizeof(hdd_profile_t));
        hdd_state.drive[i].current_cylinder = 0;
        hdd_state.drive[i].current_head = 0;
        hdd_state.drive[i].detection_done = false;
    }

    hdd_state.active_drive = HDD_DRIVE_0;
    hdd_state.initialized = true;

    /* Enable HDD subsystem */
    hdd_write_reg(HDD_CTRL, HDD_CTRL_ENABLE);

    return HAL_OK;
}

int hdd_select_drive(uint8_t drive)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive)) {
        return HAL_ERR_INVALID;
    }

    /* Update active drive for NCO/decoder */
    uint32_t ctrl = hdd_read_reg(HDD_CTRL);
    ctrl &= ~(HDD_CTRL_DRIVE0_ACTIVE | HDD_CTRL_DRIVE1_ACTIVE);
    if (drive == HDD_DRIVE_0) {
        ctrl |= HDD_CTRL_DRIVE0_ACTIVE;
    } else {
        ctrl |= HDD_CTRL_DRIVE1_ACTIVE;
    }
    hdd_write_reg(HDD_CTRL, ctrl);

    hdd_state.active_drive = drive;
    return HAL_OK;
}

uint8_t hdd_get_active_drive(void)
{
    return hdd_state.active_drive;
}

int hdd_detect_interface(uint8_t drive, hdd_detection_t *result)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || result == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Select drive for detection */
    uint32_t ctrl = DETECT_CTRL_START;
    if (drive == HDD_DRIVE_1) {
        ctrl |= BIT(8);  /* Select drive 1 for detection */
    }
    hdd_write_reg(HDD_DETECT_CTRL, ctrl);

    /* Wait for completion (timeout ~2 seconds for full detection) */
    int ret = wait_detection_done(2000);
    if (ret != HAL_OK) {
        hdd_write_reg(HDD_DETECT_CTRL, DETECT_CTRL_ABORT);
        return ret;
    }

    /* Read results */
    uint32_t result_reg = hdd_read_reg(HDD_DETECT_RESULT);
    uint32_t scores_reg = hdd_read_reg(HDD_DETECT_SCORES);

    unpack_detection(result_reg, scores_reg, result);

    /* Store in per-drive profile */
    memcpy(&hdd_state.drive[drive].profile.detection, result, sizeof(*result));
    hdd_state.drive[drive].detection_done = true;

    return HAL_OK;
}

int hdd_force_interface(hdd_type_t type)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    /* Set force personality and lock */
    uint32_t ctrl = DETECT_CTRL_LOCK |
                    ((type << DETECT_CTRL_FORCE_SHIFT) & DETECT_CTRL_FORCE_MASK);
    hdd_write_reg(HDD_DETECT_CTRL, ctrl);

    /* Start detection (will immediately use forced value) */
    hdd_write_reg(HDD_DETECT_CTRL, ctrl | DETECT_CTRL_START);

    /* Wait briefly */
    int ret = wait_detection_done(100);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Update state for both drives */
    for (int i = 0; i < HDD_NUM_DRIVES; i++) {
        hdd_state.drive[i].profile.detection.type = type;
        hdd_state.drive[i].profile.detection.was_forced = true;
        hdd_state.drive[i].detection_done = true;
    }

    return HAL_OK;
}

int hdd_discover(uint8_t drive, hdd_profile_t *profile)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || profile == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Run detection first if not done */
    if (!hdd_state.drive[drive].detection_done) {
        int ret = hdd_detect_interface(drive, &profile->detection);
        if (ret != HAL_OK) {
            return ret;
        }
    }

    /* Don't discover floppy drives */
    if (hdd_state.drive[drive].profile.detection.type == HDD_TYPE_FLOPPY) {
        return HAL_ERR_INVALID;
    }

    /* Configure PHY based on detection */
    uint32_t ctrl = hdd_read_reg(HDD_CTRL);
    if (hdd_state.drive[drive].profile.detection.phy_mode == HDD_PHY_DIFF) {
        ctrl |= HDD_CTRL_DIFF_MODE;
    } else {
        ctrl &= ~HDD_CTRL_DIFF_MODE;
    }
    hdd_write_reg(HDD_CTRL, ctrl);

    /* Start discovery pipeline on selected drive */
    uint32_t discover_ctrl = DISCOVER_CTRL_START | DISCOVER_CTRL_FULL;
    if (drive == HDD_DRIVE_1) {
        discover_ctrl |= DISCOVER_CTRL_DRIVE_SEL;
    }
    hdd_write_reg(HDD_DISCOVER_CTRL, discover_ctrl);

    /* Wait for completion (can take 30+ seconds for full scan) */
    int ret = wait_discovery_done(60000);
    if (ret != HAL_OK) {
        hdd_write_reg(HDD_DISCOVER_CTRL, DISCOVER_CTRL_ABORT);
        return ret;
    }

    /* Read geometry from per-drive register */
    unpack_geometry(drive, &profile->geometry);

    /* Read health */
    unpack_health(drive, &profile->health);

    /* Copy detection results */
    memcpy(&profile->detection, &hdd_state.drive[drive].profile.detection,
           sizeof(profile->detection));

    profile->valid = true;

    /* Store in state */
    memcpy(&hdd_state.drive[drive].profile, profile, sizeof(*profile));

    return HAL_OK;
}

int hdd_get_profile(uint8_t drive, hdd_profile_t *profile)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || profile == NULL) {
        return HAL_ERR_INVALID;
    }

    memcpy(profile, &hdd_state.drive[drive].profile, sizeof(*profile));
    return HAL_OK;
}

int hdd_seek(uint8_t drive, uint16_t cylinder)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive)) {
        return HAL_ERR_INVALID;
    }

    /* Check if drive is ready */
    uint32_t status = hdd_read_reg(HDD_STATUS(drive));
    if (!(status & HDD_STAT_READY)) {
        return HAL_ERR_NOT_READY;
    }

    /* Set target cylinder */
    hdd_write_reg(HDD_TARGET_CYL(drive), cylinder);

    /* Start seek via command register */
    hdd_write_reg(HDD_CMD(drive), HDD_CMD_SEEK);

    /* Wait for completion */
    int ret = wait_seek_done(drive, 5000);
    if (ret != HAL_OK) {
        return ret;
    }

    hdd_state.drive[drive].current_cylinder = cylinder;
    return HAL_OK;
}

int hdd_select_head(uint8_t drive, uint8_t head)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || head > 15) {
        return HAL_ERR_INVALID;
    }

    /* Head select is part of command register */
    uint32_t cmd = (head << HDD_CMD_HEAD_SHIFT) & HDD_CMD_HEAD_MASK;
    hdd_write_reg(HDD_CMD(drive), cmd);

    hdd_state.drive[drive].current_head = head;
    return HAL_OK;
}

int hdd_recalibrate(uint8_t drive)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive)) {
        return HAL_ERR_INVALID;
    }

    /* Start recalibrate */
    hdd_write_reg(HDD_CMD(drive), HDD_CMD_RECAL);

    /* Wait for seek complete and track 0 */
    uint32_t start = get_time_ms();
    while ((get_time_ms() - start) < 10000) {
        uint32_t status = hdd_read_reg(HDD_STATUS(drive));
        if ((status & HDD_STAT_SEEK_DONE) && (status & HDD_STAT_TRACK00)) {
            hdd_state.drive[drive].current_cylinder = 0;
            return HAL_OK;
        }
        if (status & HDD_STAT_SEEK_ERROR) {
            return HAL_ERR_HARDWARE;
        }
        delay_ms(10);
    }

    return HAL_ERR_TIMEOUT;
}

int hdd_read_sector(uint8_t drive, uint16_t cylinder, uint8_t head,
                    uint8_t sector, void *buf)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || buf == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Select this drive for NCO/decoder if not already */
    if (hdd_state.active_drive != drive) {
        int ret = hdd_select_drive(drive);
        if (ret != HAL_OK) {
            return ret;
        }
    }

    /* Seek if needed */
    if (hdd_state.drive[drive].current_cylinder != cylinder) {
        int ret = hdd_seek(drive, cylinder);
        if (ret != HAL_OK) {
            return ret;
        }
    }

    /* Select head */
    int ret = hdd_select_head(drive, head);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Set up sector buffer for read */
    hdd_write_reg(HDD_SECTOR_ADDR, sector);
    hdd_write_reg(HDD_SECTOR_CTRL, BIT(0));  /* Start read */

    /* Wait for sector data */
    uint32_t start = get_time_ms();
    while ((get_time_ms() - start) < 1000) {
        uint32_t status = hdd_read_reg(HDD_SECTOR_STATUS);
        if (status & BIT(1)) {  /* Data ready */
            break;
        }
        delay_ms(1);
    }

    /* Check for timeout */
    uint32_t status = hdd_read_reg(HDD_SECTOR_STATUS);
    if (!(status & BIT(1))) {
        return HAL_ERR_TIMEOUT;
    }

    /* Read sector data from buffer */
    uint32_t *buf32 = (uint32_t *)buf;
    uint32_t sector_size = hdd_state.drive[drive].profile.geometry.sector_size;
    if (sector_size == 0) sector_size = 512;

    for (uint32_t i = 0; i < sector_size / 4; i++) {
        buf32[i] = hdd_read_reg(HDD_SECTOR_DATA);
    }

    return HAL_OK;
}

int hdd_read_lba(uint8_t drive, uint32_t lba, uint32_t count, void *buf)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || !hdd_state.drive[drive].profile.valid) {
        return HAL_ERR_NOT_READY;
    }

    if (buf == NULL || count == 0) {
        return HAL_ERR_INVALID;
    }

    uint8_t *buf8 = (uint8_t *)buf;
    uint32_t sector_size = hdd_state.drive[drive].profile.geometry.sector_size;
    if (sector_size == 0) sector_size = 512;

    for (uint32_t i = 0; i < count; i++) {
        uint16_t cyl;
        uint8_t head, sec;

        hdd_lba_to_chs(lba + i, &cyl, &head, &sec,
                       &hdd_state.drive[drive].profile.geometry);

        int ret = hdd_read_sector(drive, cyl, head, sec, buf8);
        if (ret != HAL_OK) {
            return ret;
        }

        buf8 += sector_size;
    }

    return HAL_OK;
}

bool hdd_is_ready(uint8_t drive)
{
    if (!hdd_state.initialized || !valid_drive(drive)) {
        return false;
    }

    uint32_t status = hdd_read_reg(HDD_STATUS(drive));
    return (status & HDD_STAT_READY) != 0;
}

uint16_t hdd_get_cylinder(uint8_t drive)
{
    if (!valid_drive(drive)) {
        return 0;
    }

    /* Read current cylinder from status register */
    uint32_t status = hdd_read_reg(HDD_STATUS(drive));
    return (status & HDD_STAT_CYL_MASK) >> HDD_STAT_CYL_SHIFT;
}

uint8_t hdd_get_head(uint8_t drive)
{
    if (!valid_drive(drive)) {
        return 0;
    }
    return hdd_state.drive[drive].current_head;
}

int hdd_get_health(uint8_t drive, hdd_health_t *health)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || health == NULL) {
        return HAL_ERR_INVALID;
    }

    unpack_health(drive, health);
    return HAL_OK;
}

int hdd_get_status(uint8_t drive, bool *ready, uint16_t *cylinder, bool *seeking)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive)) {
        return HAL_ERR_INVALID;
    }

    uint32_t status = hdd_read_reg(HDD_STATUS(drive));

    if (ready) {
        *ready = (status & HDD_STAT_READY) != 0;
    }
    if (cylinder) {
        *cylinder = (status & HDD_STAT_CYL_MASK) >> HDD_STAT_CYL_SHIFT;
    }
    if (seeking) {
        *seeking = (status & HDD_STAT_SEEK_BUSY) != 0;
    }

    return HAL_OK;
}

int hdd_set_rate(hdd_rate_t rate)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    uint32_t ctrl = hdd_read_reg(HDD_CTRL);
    ctrl = (ctrl & ~HDD_CTRL_RATE_MASK) | ((rate << HDD_CTRL_RATE_SHIFT) & HDD_CTRL_RATE_MASK);
    hdd_write_reg(HDD_CTRL, ctrl);

    return HAL_OK;
}

int hdd_set_encoding(hdd_encoding_t encoding)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    uint32_t ctrl = hdd_read_reg(HDD_CTRL);
    ctrl = (ctrl & ~HDD_CTRL_MODE_MASK) | ((encoding << HDD_CTRL_MODE_SHIFT) & HDD_CTRL_MODE_MASK);
    hdd_write_reg(HDD_CTRL, ctrl);

    return HAL_OK;
}

int hdd_set_termination(bool enable)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    uint32_t ctrl = hdd_read_reg(HDD_CTRL);
    if (enable) {
        ctrl |= HDD_CTRL_DIFF_MODE;  /* Enable differential/termination */
    } else {
        ctrl &= ~HDD_CTRL_DIFF_MODE;
    }
    hdd_write_reg(HDD_CTRL, ctrl);

    return HAL_OK;
}

/*============================================================================
 * ESDI-Specific Functions
 *============================================================================*/

/**
 * Wait for ESDI command completion
 */
static int wait_esdi_cmd_done(uint32_t timeout_ms)
{
    uint32_t start = get_time_ms();

    while ((get_time_ms() - start) < timeout_ms) {
        uint32_t status = hdd_read_reg(HDD_ESDI_CMD_STATUS);
        if (status & ESDI_STAT_DONE) {
            if (status & ESDI_STAT_ERROR) {
                return HAL_ERR_HARDWARE;
            }
            return HAL_OK;
        }
        delay_ms(1);
    }

    return HAL_ERR_TIMEOUT;
}

int hdd_esdi_get_config(uint8_t drive, esdi_config_t *config)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive) || config == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Check if drive is ESDI */
    if (hdd_state.drive[drive].profile.detection.type != HDD_TYPE_ESDI) {
        return HAL_ERR_NOT_SUPPORTED;
    }

    /* Select the drive */
    hdd_select_drive(drive);

    /* Send GET_DEV_CONFIG command */
    uint32_t cmd_ctrl = ESDI_CMD_START |
                        ((ESDI_CMD_GET_CONFIG << ESDI_CMD_OP_SHIFT) & ESDI_CMD_OP_MASK);
    hdd_write_reg(HDD_ESDI_CMD_CTRL, cmd_ctrl);

    /* Wait for completion */
    int ret = wait_esdi_cmd_done(1000);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Check if config data is valid */
    uint32_t status = hdd_read_reg(HDD_ESDI_CMD_STATUS);
    if (!(status & ESDI_STAT_CONFIG_VALID)) {
        config->valid = false;
        return HAL_ERR_HARDWARE;
    }

    /* Read configuration from registers */
    uint32_t config_a = hdd_read_reg(HDD_ESDI_CONFIG_A);
    uint32_t config_b = hdd_read_reg(HDD_ESDI_CONFIG_B);

    config->cylinders = config_a & 0xFFFF;
    config->heads = (config_b >> 8) & 0xFF;
    config->sectors_per_track = config_b & 0xFF;

    /* Calculate total sectors */
    config->total_sectors = (uint32_t)config->cylinders *
                            config->heads *
                            config->sectors_per_track;

    /* Transfer rate from high byte of config_a (if available) */
    config->transfer_rate = (config_a >> 24) & 0x03;
    config->soft_sectored = ((config_a >> 21) & 0x01) != 0;
    config->fixed_drive = ((config_a >> 22) & 0x01) != 0;

    config->valid = true;

    /* Store in profile */
    memcpy(&hdd_state.drive[drive].profile.esdi_config, config, sizeof(*config));

    /* Also update geometry if this is better than probed */
    if (config->cylinders > 0 && config->heads > 0 && config->sectors_per_track > 0) {
        hdd_state.drive[drive].profile.geometry.cylinders = config->cylinders;
        hdd_state.drive[drive].profile.geometry.heads = config->heads;
        hdd_state.drive[drive].profile.geometry.sectors = config->sectors_per_track;
        hdd_state.drive[drive].profile.geometry.total_sectors = config->total_sectors;
        hdd_state.drive[drive].profile.geometry.capacity_mb =
            (config->total_sectors * 512) / (1024 * 1024);
        hdd_state.drive[drive].profile.geometry.from_esdi_config = true;
    }

    return HAL_OK;
}

int hdd_esdi_command(uint8_t drive, uint8_t opcode, uint16_t param)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (!valid_drive(drive)) {
        return HAL_ERR_INVALID;
    }

    /* Check if drive is ESDI */
    if (hdd_state.drive[drive].profile.detection.type != HDD_TYPE_ESDI) {
        return HAL_ERR_NOT_SUPPORTED;
    }

    /* Select the drive */
    hdd_select_drive(drive);

    /* Build command with parameter */
    /* Parameter would be set via additional register if needed */
    uint32_t cmd_ctrl = ESDI_CMD_START |
                        ((opcode << ESDI_CMD_OP_SHIFT) & ESDI_CMD_OP_MASK);
    hdd_write_reg(HDD_ESDI_CMD_CTRL, cmd_ctrl);

    return HAL_OK;
}

int hdd_esdi_wait(uint32_t timeout_ms)
{
    return wait_esdi_cmd_done(timeout_ms);
}

bool hdd_esdi_config_valid(uint8_t drive)
{
    if (!hdd_state.initialized || !valid_drive(drive)) {
        return false;
    }

    return hdd_state.drive[drive].profile.esdi_config.valid;
}

/*============================================================================
 * Dual-Drive Convenience Functions
 *============================================================================*/

int hdd_seek_both(uint16_t cyl_0, uint16_t cyl_1)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    /* Check both drives are ready */
    uint32_t status_0 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_0));
    uint32_t status_1 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_1));

    if (!(status_0 & HDD_STAT_READY) || !(status_1 & HDD_STAT_READY)) {
        return HAL_ERR_NOT_READY;
    }

    /* Set target cylinders */
    hdd_write_reg(HDD_TARGET_CYL(HDD_DRIVE_0), cyl_0);
    hdd_write_reg(HDD_TARGET_CYL(HDD_DRIVE_1), cyl_1);

    /* Start both seeks simultaneously */
    hdd_write_reg(HDD_CMD(HDD_DRIVE_0), HDD_CMD_SEEK);
    hdd_write_reg(HDD_CMD(HDD_DRIVE_1), HDD_CMD_SEEK);

    return HAL_OK;
}

int hdd_wait_seeks(uint32_t timeout_ms)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    uint32_t start = get_time_ms();

    while ((get_time_ms() - start) < timeout_ms) {
        uint32_t status_0 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_0));
        uint32_t status_1 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_1));

        bool seek_busy_0 = (status_0 & HDD_STAT_SEEK_BUSY) != 0;
        bool seek_busy_1 = (status_1 & HDD_STAT_SEEK_BUSY) != 0;

        /* Check for errors */
        if ((status_0 & HDD_STAT_SEEK_ERROR) || (status_1 & HDD_STAT_SEEK_ERROR)) {
            return HAL_ERR_HARDWARE;
        }

        /* Both done? */
        if (!seek_busy_0 && !seek_busy_1) {
            /* Update cached positions */
            hdd_state.drive[HDD_DRIVE_0].current_cylinder =
                (status_0 & HDD_STAT_CYL_MASK) >> HDD_STAT_CYL_SHIFT;
            hdd_state.drive[HDD_DRIVE_1].current_cylinder =
                (status_1 & HDD_STAT_CYL_MASK) >> HDD_STAT_CYL_SHIFT;
            return HAL_OK;
        }

        delay_ms(1);
    }

    return HAL_ERR_TIMEOUT;
}

bool hdd_any_seeking(void)
{
    if (!hdd_state.initialized) {
        return false;
    }

    uint32_t status_0 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_0));
    uint32_t status_1 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_1));

    return ((status_0 & HDD_STAT_SEEK_BUSY) != 0) ||
           ((status_1 & HDD_STAT_SEEK_BUSY) != 0);
}

int hdd_get_dual_status(bool *ready_0, bool *ready_1,
                        uint16_t *cyl_0, uint16_t *cyl_1)
{
    if (!hdd_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    uint32_t status_0 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_0));
    uint32_t status_1 = hdd_read_reg(HDD_STATUS(HDD_DRIVE_1));

    if (ready_0) {
        *ready_0 = (status_0 & HDD_STAT_READY) != 0;
    }
    if (ready_1) {
        *ready_1 = (status_1 & HDD_STAT_READY) != 0;
    }
    if (cyl_0) {
        *cyl_0 = (status_0 & HDD_STAT_CYL_MASK) >> HDD_STAT_CYL_SHIFT;
    }
    if (cyl_1) {
        *cyl_1 = (status_1 & HDD_STAT_CYL_MASK) >> HDD_STAT_CYL_SHIFT;
    }

    return HAL_OK;
}

/*============================================================================
 * Utility Functions
 *============================================================================*/

const char *hdd_type_to_string(hdd_type_t type)
{
    switch (type) {
        case HDD_TYPE_UNKNOWN:  return "Unknown";
        case HDD_TYPE_FLOPPY:   return "Floppy";
        case HDD_TYPE_MFM:      return "ST-506 MFM";
        case HDD_TYPE_RLL:      return "ST-506 RLL";
        case HDD_TYPE_ESDI:     return "ESDI";
        default:                return "Invalid";
    }
}

const char *hdd_rate_to_string(hdd_rate_t rate)
{
    switch (rate) {
        case HDD_RATE_UNKNOWN:  return "Unknown";
        case HDD_RATE_5M:       return "5 Mbps";
        case HDD_RATE_7_5M:     return "7.5 Mbps";
        case HDD_RATE_10M:      return "10 Mbps";
        case HDD_RATE_15M:      return "15 Mbps";
        case HDD_RATE_20M:      return "20 Mbps";
        case HDD_RATE_24M:      return "24 Mbps";
        default:                return "Invalid";
    }
}

const char *hdd_encoding_to_string(hdd_encoding_t encoding)
{
    switch (encoding) {
        case HDD_ENC_UNKNOWN:   return "Unknown";
        case HDD_ENC_MFM:       return "MFM";
        case HDD_ENC_RLL_2_7:   return "RLL(2,7)";
        case HDD_ENC_ESDI_NRZ:  return "ESDI NRZ";
        default:                return "Invalid";
    }
}

uint32_t hdd_chs_to_lba(uint16_t cylinder, uint8_t head, uint8_t sector,
                        const hdd_geometry_t *geom)
{
    if (geom == NULL || geom->heads == 0 || geom->sectors == 0) {
        return 0;
    }

    return ((uint32_t)cylinder * geom->heads + head) * geom->sectors +
           (sector - 1);
}

void hdd_lba_to_chs(uint32_t lba, uint16_t *cylinder, uint8_t *head,
                    uint8_t *sector, const hdd_geometry_t *geom)
{
    if (geom == NULL || geom->heads == 0 || geom->sectors == 0) {
        if (cylinder) *cylinder = 0;
        if (head) *head = 0;
        if (sector) *sector = 1;
        return;
    }

    uint32_t temp = lba / geom->sectors;
    if (sector) *sector = (lba % geom->sectors) + 1;
    if (head) *head = temp % geom->heads;
    if (cylinder) *cylinder = temp / geom->heads;
}
