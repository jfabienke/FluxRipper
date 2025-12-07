/**
 * FluxRipper HAL Driver - Implementation
 *
 * Hardware Abstraction Layer for FluxRipper FDC
 * Milestone 1: Register-level access, no DMA
 *
 * Target: AMD Spartan UltraScale+ SCU35
 * Updated: 2025-12-03 15:30:00
 */

#include "fluxripper_hal.h"
#include "platform.h"
#include <string.h>

/*============================================================================
 * Internal State
 *============================================================================*/

static struct {
    bool initialized;
    hal_mode_t mode[MAX_DRIVES];
    uint8_t current_track[MAX_DRIVES];
    bool motor_running[MAX_DRIVES];
    flux_cb_t flux_callback[MAX_DRIVES];
} hal_state = {
    .initialized = false,
    .mode = {MODE_IDLE, MODE_IDLE},
    .current_track = {0, 0},
    .motor_running = {false, false},
    .flux_callback = {NULL, NULL}
};

/*============================================================================
 * Internal Helper Functions
 *============================================================================*/

/**
 * Get current time in milliseconds (simple implementation)
 * Note: Requires timer to be initialized
 */
static uint32_t get_time_ms(void)
{
    /* Timer counts down from 0xFFFFFFFF at CPU_FREQ_HZ (100 MHz) */
    uint32_t timer_val = TIMER_TCR0;
    uint32_t elapsed_cycles = 0xFFFFFFFF - timer_val;
    return elapsed_cycles / (CPU_FREQ_HZ / 1000);
}

/**
 * Delay in milliseconds
 */
static void delay_ms(uint32_t ms)
{
    uint32_t start = get_time_ms();
    while ((get_time_ms() - start) < ms) {
        /* Busy wait */
    }
}

/**
 * Read 32-bit register
 */
static inline uint32_t read_reg32(uint32_t addr)
{
    return REG32(addr);
}

/**
 * Write 32-bit register
 */
static inline void write_reg32(uint32_t addr, uint32_t value)
{
    REG32(addr) = value;
}

/**
 * Get MSR register address for drive
 */
static inline uint32_t get_msr_addr(uint8_t drive)
{
    return (drive == DRIVE_A) ? FDC_MSR_DSR : FDC_B_MSR_DSR;
}

/**
 * Get DATA register address for drive
 */
static inline uint32_t get_data_addr(uint8_t drive)
{
    return (drive == DRIVE_A) ? FDC_DATA : FDC_B_DATA;
}

/**
 * Get flux control register address for drive
 */
static inline uint32_t get_flux_ctrl_addr(uint8_t drive)
{
    return (drive == DRIVE_A) ? FDC_FLUX_CTRL_A : FDC_FLUX_CTRL_B;
}

/**
 * Get flux status register address for drive
 */
static inline uint32_t get_flux_stat_addr(uint8_t drive)
{
    return (drive == DRIVE_A) ? FDC_FLUX_STAT_A : FDC_FLUX_STAT_B;
}

/**
 * Unpack drive profile from register value
 */
static void unpack_profile(uint32_t reg_val, drive_profile_t *profile)
{
    /* Extract form factor */
    uint8_t ff = reg_val & PROFILE_FF_MASK;
    profile->form_factor = ff;

    /* Extract density */
    uint8_t dens = (reg_val & PROFILE_DENS_MASK) >> 2;
    profile->density = dens;

    /* Extract tracks */
    uint8_t trk = (reg_val & PROFILE_TRACKS_MASK) >> 4;
    switch (trk) {
        case 0: profile->tracks = 40; break;
        case 1: profile->tracks = 80; break;
        case 2: profile->tracks = 77; break;
        default: profile->tracks = 0; break;
    }

    /* Extract encoding */
    uint8_t enc = (reg_val & PROFILE_ENC_MASK) >> PROFILE_ENC_SHIFT;
    profile->encoding = enc;

    /* Extract flags */
    profile->valid = (reg_val & PROFILE_VALID) != 0;
    profile->locked = (reg_val & PROFILE_LOCKED) != 0;

    /* Extract RPM (stored as RPM/10) */
    uint8_t rpm_div10 = (reg_val & PROFILE_RPM_MASK) >> PROFILE_RPM_SHIFT;
    profile->rpm = rpm_div10 * 10;

    /* Extract quality */
    profile->quality = (reg_val & PROFILE_QUALITY_MASK) >> PROFILE_QUALITY_SHIFT;
}

/*============================================================================
 * HAL API Implementation
 *============================================================================*/

int hal_init(void)
{
    if (hal_state.initialized) {
        return HAL_OK;
    }

    /* Reset the FDC controller */
    write_reg32(FDC_MSR_DSR, DSR_SW_RESET);
    delay_ms(10);

    /* Take FDC out of reset */
    write_reg32(FDC_DOR, DOR_NOT_RESET | DOR_DMA_ENABLE);
    delay_ms(10);

    /* Set default data rate (500 Kbps for HD) */
    write_reg32(FDC_MSR_DSR, DSR_DRATE_500K);
    write_reg32(FDC_DIR_CCR, DSR_DRATE_500K);

    /* Initialize timer for delays */
    TIMER_TLR0 = 0xFFFFFFFF;  /* Load max value */
    TIMER_TCSR0 = TIMER_TCSR_ARHT | TIMER_TCSR_LOAD;  /* Auto-reload, load */
    TIMER_TCSR0 = TIMER_TCSR_ARHT | TIMER_TCSR_ENT;   /* Enable timer */

    /* Initialize state */
    hal_state.initialized = true;
    for (int i = 0; i < MAX_DRIVES; i++) {
        hal_state.mode[i] = MODE_IDLE;
        hal_state.current_track[i] = 0;
        hal_state.motor_running[i] = false;
        hal_state.flux_callback[i] = NULL;
    }

    return HAL_OK;
}

uint32_t hal_get_version(void)
{
    return read_reg32(FDC_VERSION);
}

hal_mode_t hal_get_mode(uint8_t drive)
{
    if (drive >= MAX_DRIVES) {
        return MODE_IDLE;
    }
    return hal_state.mode[drive];
}

int hal_get_profile(uint8_t drive, drive_profile_t *profile)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES || profile == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Read profile register */
    uint32_t profile_addr = (drive == DRIVE_A) ?
                            FDC_DRIVE_PROFILE_A : FDC_DRIVE_PROFILE_B;
    uint32_t reg_val = read_reg32(profile_addr);

    /* Unpack into structure */
    unpack_profile(reg_val, profile);

    return HAL_OK;
}

int hal_motor_on(uint8_t drive)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES) {
        return HAL_ERR_INVALID;
    }

    /* Check if already running */
    if (hal_state.motor_running[drive]) {
        return HAL_OK;
    }

    /* Read current DOR value */
    uint32_t dor = read_reg32(FDC_DOR);

    /* Set motor bit for this drive */
    dor |= (DOR_MOTOR_0 << drive);

    /* Set drive select */
    dor = (dor & ~DOR_DRIVE_SEL_MASK) | drive;

    /* Write DOR */
    write_reg32(FDC_DOR, dor);

    /* Wait for motor spin-up */
    delay_ms(TIMEOUT_MOTOR);

    hal_state.motor_running[drive] = true;

    return HAL_OK;
}

int hal_motor_off(uint8_t drive)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES) {
        return HAL_ERR_INVALID;
    }

    /* Read current DOR value */
    uint32_t dor = read_reg32(FDC_DOR);

    /* Clear motor bit for this drive */
    dor &= ~(DOR_MOTOR_0 << drive);

    /* Write DOR */
    write_reg32(FDC_DOR, dor);

    hal_state.motor_running[drive] = false;

    return HAL_OK;
}

int hal_wait_ready(uint32_t timeout_ms)
{
    uint32_t start = get_time_ms();

    while ((get_time_ms() - start) < timeout_ms) {
        uint32_t msr = read_reg32(FDC_MSR_DSR);
        if (msr & MSR_RQM) {
            return HAL_OK;
        }
        /* Small delay to avoid hammering the bus */
        delay_ms(1);
    }

    return HAL_ERR_TIMEOUT;
}

int hal_send_cmd(uint8_t cmd)
{
    /* Wait for FDC ready */
    int ret = hal_wait_ready(TIMEOUT_READY);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Check that DIO is clear (ready for write) */
    uint32_t msr = read_reg32(FDC_MSR_DSR);
    if (msr & MSR_DIO) {
        return HAL_ERR_NOT_READY;
    }

    /* Write command byte */
    write_reg32(FDC_DATA, cmd);

    return HAL_OK;
}

int hal_read_result(uint8_t *result)
{
    if (result == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Wait for FDC ready */
    int ret = hal_wait_ready(TIMEOUT_READY);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Check that DIO is set (ready for read) */
    uint32_t msr = read_reg32(FDC_MSR_DSR);
    if (!(msr & MSR_DIO)) {
        return HAL_ERR_NOT_READY;
    }

    /* Read result byte */
    *result = read_reg32(FDC_DATA) & 0xFF;

    return HAL_OK;
}

int hal_seek(uint8_t drive, uint8_t track)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES) {
        return HAL_ERR_INVALID;
    }

    /* Ensure motor is running */
    if (!hal_state.motor_running[drive]) {
        int ret = hal_motor_on(drive);
        if (ret != HAL_OK) {
            return ret;
        }
    }

    /* Send SEEK command (0x0F) */
    int ret = hal_send_cmd(0x0F);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Send head/drive byte (head 0, drive number) */
    ret = hal_send_cmd((0 << 2) | drive);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Send cylinder number */
    ret = hal_send_cmd(track);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Wait for seek to complete (check for interrupt) */
    uint32_t start = get_time_ms();
    while ((get_time_ms() - start) < TIMEOUT_SEEK) {
        uint32_t sra = read_reg32(FDC_SRA_SRB) & 0xFF;
        if (sra & SRA_INT_PENDING) {
            break;
        }
        delay_ms(10);
    }

    /* Send SENSE INTERRUPT STATUS (0x08) */
    ret = hal_send_cmd(0x08);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Read ST0 */
    uint8_t st0;
    ret = hal_read_result(&st0);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Read PCN (Present Cylinder Number) */
    uint8_t pcn;
    ret = hal_read_result(&pcn);
    if (ret != HAL_OK) {
        return ret;
    }

    /* Verify we're at the correct track */
    if (pcn != track) {
        return HAL_ERR_HARDWARE;
    }

    hal_state.current_track[drive] = track;

    return HAL_OK;
}

int hal_read_sectors(uint8_t drive, uint32_t lba, void *buf, uint32_t count)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES || buf == NULL || count == 0) {
        return HAL_ERR_INVALID;
    }

    /* Check if we're in FDC mode */
    if (hal_state.mode[drive] != MODE_IDLE &&
        hal_state.mode[drive] != MODE_FDC) {
        return HAL_ERR_MODE;
    }

    /* Set mode to FDC */
    hal_state.mode[drive] = MODE_FDC;

    /* Milestone 1: Stub implementation - register access only */
    /* Full implementation requires:
     * 1. Convert LBA to CHS (cylinder, head, sector)
     * 2. Seek to cylinder
     * 3. Send READ DATA command (0xE6 or 0x66)
     * 4. Read sector data from FIFO
     * 5. Check result phase
     */

    /* For now, return not implemented */
    hal_state.mode[drive] = MODE_IDLE;
    return HAL_ERR_HARDWARE;
}

int hal_start_flux_capture(uint8_t drive, uint8_t track,
                          uint8_t revolutions, flux_cb_t callback)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES || revolutions == 0 || callback == NULL) {
        return HAL_ERR_INVALID;
    }

    /* Check if we're in IDLE mode */
    if (hal_state.mode[drive] != MODE_IDLE) {
        return HAL_ERR_MODE;
    }

    /* Ensure motor is running */
    if (!hal_state.motor_running[drive]) {
        int ret = hal_motor_on(drive);
        if (ret != HAL_OK) {
            return ret;
        }
    }

    /* Seek to track if needed */
    if (hal_state.current_track[drive] != track) {
        int ret = hal_seek(drive, track);
        if (ret != HAL_OK) {
            return ret;
        }
    }

    /* Store callback */
    hal_state.flux_callback[drive] = callback;

    /* Set mode */
    hal_state.mode[drive] = MODE_FLUX_CAPTURE;

    /* Get flux control register address */
    uint32_t flux_ctrl_addr = get_flux_ctrl_addr(drive);

    /* Reset flux capture logic */
    write_reg32(flux_ctrl_addr, FLUX_CTRL_RESET);
    delay_ms(1);

    /* Start flux capture with revolution count */
    uint32_t ctrl = FLUX_CTRL_START | ((revolutions << 8) & FLUX_CTRL_REV_MASK);
    write_reg32(flux_ctrl_addr, ctrl);

    return HAL_OK;
}

int hal_stop_flux_capture(uint8_t drive)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    if (drive >= MAX_DRIVES) {
        return HAL_ERR_INVALID;
    }

    /* Check if we're in flux capture mode */
    if (hal_state.mode[drive] != MODE_FLUX_CAPTURE) {
        return HAL_OK;  /* Already stopped */
    }

    /* Get flux control register address */
    uint32_t flux_ctrl_addr = get_flux_ctrl_addr(drive);

    /* Stop flux capture */
    write_reg32(flux_ctrl_addr, FLUX_CTRL_STOP);

    /* Clear callback */
    hal_state.flux_callback[drive] = NULL;

    /* Reset mode */
    hal_state.mode[drive] = MODE_IDLE;

    return HAL_OK;
}

bool hal_disk_present(uint8_t drive)
{
    if (!hal_state.initialized || drive >= MAX_DRIVES) {
        return false;
    }

    /* Read DIR register (bit 7 = disk change) */
    /* Note: Disk change indicates a change, not presence directly */
    /* For now, assume disk is present if motor can be started */
    /* More sophisticated detection would check index pulses */

    uint32_t dir = read_reg32(FDC_DIR_CCR);
    /* If disk change bit is clear, disk is likely present */
    return !(dir & DIR_DISK_CHANGE);
}

bool hal_write_protected(uint8_t drive)
{
    if (!hal_state.initialized || drive >= MAX_DRIVES) {
        return true;  /* Assume protected on error */
    }

    /* Read SRA/SRB register */
    uint32_t sra_srb = read_reg32(FDC_SRA_SRB);

    /* Check write protect based on drive */
    if (drive == DRIVE_A) {
        return (sra_srb & SRB_DRV0_WP) != 0;
    } else {
        return (sra_srb & SRB_DRV1_WP) != 0;
    }
}

int hal_reset(void)
{
    if (!hal_state.initialized) {
        return HAL_ERR_NOT_READY;
    }

    /* Software reset via DSR */
    write_reg32(FDC_MSR_DSR, DSR_SW_RESET);
    delay_ms(10);

    /* Take FDC out of reset */
    write_reg32(FDC_DOR, DOR_NOT_RESET | DOR_DMA_ENABLE);
    delay_ms(10);

    /* Restore default data rate */
    write_reg32(FDC_MSR_DSR, DSR_DRATE_500K);
    write_reg32(FDC_DIR_CCR, DSR_DRATE_500K);

    /* Reset state */
    for (int i = 0; i < MAX_DRIVES; i++) {
        hal_state.mode[i] = MODE_IDLE;
        hal_state.current_track[i] = 0;
        hal_state.motor_running[i] = false;
        hal_state.flux_callback[i] = NULL;
    }

    return HAL_OK;
}

/*============================================================================
 * Interrupt Handler (to be called from ISR)
 *============================================================================*/

/**
 * Handle flux capture interrupt for a drive
 * This should be called from the main ISR when FDC interrupt occurs.
 *
 * @param drive     Drive number (0-1)
 */
void hal_flux_capture_irq(uint8_t drive)
{
    if (drive >= MAX_DRIVES) {
        return;
    }

    if (hal_state.mode[drive] != MODE_FLUX_CAPTURE) {
        return;
    }

    /* Get flux status register address */
    uint32_t flux_stat_addr = get_flux_stat_addr(drive);
    uint32_t status = read_reg32(flux_stat_addr);

    /* Check if capture is done or error occurred */
    if (status & (FLUX_STAT_DONE | FLUX_STAT_ERROR | FLUX_STAT_OVERFLOW)) {
        /* Notify callback */
        if (hal_state.flux_callback[drive]) {
            /* Milestone 1: No DMA, so data is NULL */
            /* Full implementation will provide actual flux data */
            hal_state.flux_callback[drive](drive, NULL, 0, true);
        }

        /* Stop capture */
        hal_stop_flux_capture(drive);
    }
}
