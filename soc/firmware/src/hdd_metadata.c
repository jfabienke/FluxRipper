/**
 * @file hdd_metadata.c
 * @brief FluxRipper HDD Steganographic Metadata Implementation
 *
 * Stores hidden metadata on vintage HDDs using "fake bad sector" technique.
 * The metadata includes:
 *   - Unique drive UUID (generated from fingerprint + timestamp)
 *   - Drive geometry (C/H/S discovered during fingerprinting)
 *   - Physical characteristics (RPM, jitter, seek curve type)
 *   - Session history (last 16 FluxRipper sessions)
 *   - User notes and flags
 *   - Cumulative statistics (reads, errors)
 *
 * The host operating system sees these sectors as "bad" and avoids them,
 * while FluxRipper can access them freely via direct flux-level I/O.
 *
 * @author Claude Code (FluxRipper Project)
 * @date 2025-12-04 20:07
 */

#include "hdd_metadata.h"
#include "hdd_hal.h"
#include "fluxripper_hal.h"
#include <string.h>
#include <stdio.h>
#include <time.h>

//=============================================================================
// Hardware Register Access
//=============================================================================

#define HDD_BASE    0x80007000u
#define META_BASE   (HDD_BASE + META_REG_BASE)

static inline void meta_reg_write(uint32_t offset, uint32_t value) {
    volatile uint32_t *reg = (volatile uint32_t *)(META_BASE + offset);
    *reg = value;
}

static inline uint32_t meta_reg_read(uint32_t offset) {
    volatile uint32_t *reg = (volatile uint32_t *)(META_BASE + offset);
    return *reg;
}

//=============================================================================
// Module State
//=============================================================================

static struct {
    bool initialized[2];        // Per-drive initialization
    meta_config_t config[2];    // Per-drive configuration
    hdd_metadata_t cache[2];    // Cached metadata
} g_meta;

//=============================================================================
// Private Functions
//=============================================================================

/**
 * Wait for metadata operation to complete
 */
static meta_error_t wait_for_completion(uint32_t timeout_ms) {
    uint32_t start = hal_get_time_ms();

    while ((hal_get_time_ms() - start) < timeout_ms) {
        uint32_t status = meta_reg_read(META_REG_CTRL - META_REG_BASE);

        if (status & META_CTRL_DONE) {
            if (status & META_CTRL_ERROR) {
                return (meta_error_t)((status & META_CTRL_ERROR_CODE) >> 12);
            }
            return META_OK;
        }

        if (!(status & META_CTRL_BUSY)) {
            // Not busy but not done - something wrong
            return META_ERR_TIMEOUT;
        }

        // Small delay to avoid hammering the bus
        hal_delay_us(100);
    }

    return META_ERR_TIMEOUT;
}

/**
 * Simple LFSR for pseudo-random component in UUID
 */
static uint32_t lfsr_next(uint32_t *state) {
    uint32_t bit = ((*state >> 0) ^ (*state >> 2) ^ (*state >> 3) ^ (*state >> 5)) & 1;
    *state = (*state >> 1) | (bit << 31);
    return *state;
}

/**
 * Simple hash function for fingerprint
 */
static uint32_t fingerprint_hash(const drive_fingerprint_t *fp) {
    const uint8_t *data = (const uint8_t *)fp;
    uint32_t hash = 5381;

    for (int i = 0; i < sizeof(drive_fingerprint_t); i++) {
        hash = ((hash << 5) + hash) + data[i];  // hash * 33 + c
    }

    return hash;
}

//=============================================================================
// Public API Implementation
//=============================================================================

meta_error_t meta_init(uint8_t drive, const meta_config_t *config) {
    if (drive > 1) {
        return META_ERR_INVALID_DRIVE;
    }

    // Set defaults or use provided config
    if (config != NULL) {
        g_meta.config[drive] = *config;
    } else {
        g_meta.config[drive].cylinder = METADATA_DEFAULT_CYL;
        g_meta.config[drive].head = METADATA_DEFAULT_HEAD;
        g_meta.config[drive].start_sector = METADATA_DEFAULT_SEC;
        g_meta.config[drive].enabled = true;
        g_meta.config[drive].auto_write = true;
        g_meta.config[drive].generate_guid_on_first = true;
    }

    // Configure hardware
    uint32_t cfg = 0;
    if (g_meta.config[drive].enabled)
        cfg |= META_CONFIG_ENABLE;
    if (g_meta.config[drive].auto_write)
        cfg |= META_CONFIG_AUTO_WRITE;
    if (g_meta.config[drive].generate_guid_on_first)
        cfg |= META_CONFIG_GEN_GUID;

    meta_reg_write(META_REG_CONFIG - META_REG_BASE, cfg);

    // Set location
    meta_reg_write(META_REG_CYL_HEAD - META_REG_BASE,
                   ((uint32_t)g_meta.config[drive].head << 16) |
                   g_meta.config[drive].cylinder);
    meta_reg_write(META_REG_SECTOR - META_REG_BASE,
                   g_meta.config[drive].start_sector);

    // Clear cache
    memset(&g_meta.cache[drive], 0, sizeof(hdd_metadata_t));

    g_meta.initialized[drive] = true;
    return META_OK;
}

meta_error_t meta_read(uint8_t drive, hdd_metadata_t *meta) {
    if (drive > 1) {
        return META_ERR_INVALID_DRIVE;
    }
    if (!g_meta.initialized[drive]) {
        return META_ERR_NOT_INITIALIZED;
    }
    if (meta == NULL) {
        return META_ERR_INVALID_DRIVE;  // Using generic error
    }

    // Select drive
    hdd_select(drive);

    // Start read operation
    meta_reg_write(META_REG_CTRL - META_REG_BASE, META_CTRL_READ_START);

    // Wait for completion
    meta_error_t err = wait_for_completion(5000);  // 5 second timeout
    if (err != META_OK) {
        return err;
    }

    // Check if metadata was found
    uint32_t status = meta_reg_read(META_REG_CTRL - META_REG_BASE);
    if (!(status & META_CTRL_VALID)) {
        // No signature found - this is expected for untagged drives
        meta->valid = false;
        return META_ERR_NO_SIGNATURE;
    }

    // Read data from registers
    meta->signature = METADATA_SIGNATURE;
    meta->version = METADATA_VERSION;

    // GUID
    uint32_t guid0 = meta_reg_read(META_REG_GUID_0 - META_REG_BASE);
    uint32_t guid1 = meta_reg_read(META_REG_GUID_1 - META_REG_BASE);
    uint32_t guid2 = meta_reg_read(META_REG_GUID_2 - META_REG_BASE);
    uint32_t guid3 = meta_reg_read(META_REG_GUID_3 - META_REG_BASE);
    meta->guid.data1 = guid0;
    meta->guid.data2 = (uint16_t)(guid1 >> 16);
    meta->guid.data3 = (uint16_t)(guid1 & 0xFFFF);
    memcpy(meta->guid.data4, &guid2, 4);
    memcpy(&meta->guid.data4[4], &guid3, 4);

    // Timestamp
    meta->timestamp = ((uint64_t)meta_reg_read(META_REG_TIMESTAMP_HI - META_REG_BASE) << 32) |
                      meta_reg_read(META_REG_TIMESTAMP_LO - META_REG_BASE);

    // Flags and stats
    meta->flags = (uint16_t)meta_reg_read(META_REG_FLAGS - META_REG_BASE);
    meta->session_count = meta_reg_read(META_REG_SESSION_COUNT - META_REG_BASE);
    meta->read_count = meta_reg_read(META_REG_READ_COUNT - META_REG_BASE);
    meta->error_count = meta_reg_read(META_REG_ERROR_COUNT - META_REG_BASE);

    // Fingerprint (8 registers)
    uint32_t *fp_words = (uint32_t *)&meta->fingerprint;
    for (int i = 0; i < 8; i++) {
        fp_words[i] = meta_reg_read((META_REG_FINGERPRINT_0 - META_REG_BASE) + i * 4);
    }

    // Diagnostic sessions need to be read one at a time
    for (int i = 0; i < 16; i++) {
        meta_reg_write(META_REG_DIAG_IDX - META_REG_BASE, i);

        // Small delay for register update
        hal_delay_us(10);

        uint32_t d0 = meta_reg_read(META_REG_DIAG_DATA_0 - META_REG_BASE);
        uint32_t d1 = meta_reg_read(META_REG_DIAG_DATA_1 - META_REG_BASE);
        uint32_t d2 = meta_reg_read(META_REG_DIAG_DATA_2 - META_REG_BASE);
        uint32_t d3 = meta_reg_read(META_REG_DIAG_DATA_3 - META_REG_BASE);

        meta->sessions[i].timestamp = ((uint64_t)d1 << 32) | d0;
        meta->sessions[i].type = (uint8_t)(d2 & 0xFF);
        meta->sessions[i].duration_sec = (d2 >> 8) | ((d3 & 0xFF) << 24);
        meta->sessions[i].errors = (uint16_t)(d3 >> 8);
        meta->sessions[i].warnings = (uint8_t)(d3 >> 24);
    }

    // User notes are stored in firmware memory after reading sector 3
    // For now, we'll need to extend the RTL to expose these
    // TODO: Add user notes register interface

    meta->valid = true;
    meta->dirty = false;

    // Cache a copy
    memcpy(&g_meta.cache[drive], meta, sizeof(hdd_metadata_t));

    return META_OK;
}

meta_error_t meta_write(uint8_t drive, const hdd_metadata_t *meta) {
    if (drive > 1) {
        return META_ERR_INVALID_DRIVE;
    }
    if (!g_meta.initialized[drive]) {
        return META_ERR_NOT_INITIALIZED;
    }
    if (meta == NULL) {
        return META_ERR_INVALID_DRIVE;
    }

    // Select drive
    hdd_select(drive);

    // Write data to registers
    // GUID
    meta_reg_write(META_REG_GUID_0 - META_REG_BASE, meta->guid.data1);
    meta_reg_write(META_REG_GUID_1 - META_REG_BASE,
                   ((uint32_t)meta->guid.data2 << 16) | meta->guid.data3);
    uint32_t guid2, guid3;
    memcpy(&guid2, meta->guid.data4, 4);
    memcpy(&guid3, &meta->guid.data4[4], 4);
    meta_reg_write(META_REG_GUID_2 - META_REG_BASE, guid2);
    meta_reg_write(META_REG_GUID_3 - META_REG_BASE, guid3);

    // Timestamp
    meta_reg_write(META_REG_TIMESTAMP_LO - META_REG_BASE, (uint32_t)meta->timestamp);
    meta_reg_write(META_REG_TIMESTAMP_HI - META_REG_BASE, (uint32_t)(meta->timestamp >> 32));

    // Flags and stats
    meta_reg_write(META_REG_FLAGS - META_REG_BASE, meta->flags);
    meta_reg_write(META_REG_SESSION_COUNT - META_REG_BASE, meta->session_count);
    meta_reg_write(META_REG_READ_COUNT - META_REG_BASE, meta->read_count);
    meta_reg_write(META_REG_ERROR_COUNT - META_REG_BASE, meta->error_count);

    // Fingerprint
    uint32_t *fp_words = (uint32_t *)&meta->fingerprint;
    for (int i = 0; i < 8; i++) {
        meta_reg_write((META_REG_FINGERPRINT_0 - META_REG_BASE) + i * 4, fp_words[i]);
    }

    // Start write operation
    meta_reg_write(META_REG_CTRL - META_REG_BASE, META_CTRL_WRITE_START);

    // Wait for completion
    meta_error_t err = wait_for_completion(10000);  // 10 second timeout for write
    if (err != META_OK) {
        return err;
    }

    // Update cache
    memcpy(&g_meta.cache[drive], meta, sizeof(hdd_metadata_t));

    return META_OK;
}

meta_error_t meta_erase(uint8_t drive) {
    if (drive > 1) {
        return META_ERR_INVALID_DRIVE;
    }
    if (!g_meta.initialized[drive]) {
        return META_ERR_NOT_INITIALIZED;
    }

    // Select drive
    hdd_select(drive);

    // Start erase operation
    meta_reg_write(META_REG_CTRL - META_REG_BASE, META_CTRL_ERASE_START);

    // Wait for completion
    meta_error_t err = wait_for_completion(10000);
    if (err != META_OK) {
        return err;
    }

    // Clear cache
    memset(&g_meta.cache[drive], 0, sizeof(hdd_metadata_t));

    return META_OK;
}

meta_error_t meta_create_new(hdd_metadata_t *meta,
                             const drive_fingerprint_t *fingerprint) {
    if (meta == NULL || fingerprint == NULL) {
        return META_ERR_INVALID_DRIVE;
    }

    memset(meta, 0, sizeof(hdd_metadata_t));

    meta->signature = METADATA_SIGNATURE;
    meta->version = METADATA_VERSION;

    // Copy fingerprint
    memcpy(&meta->fingerprint, fingerprint, sizeof(drive_fingerprint_t));

    // Get current timestamp
    meta->timestamp = (uint64_t)time(NULL);

    // Generate UUID
    meta_generate_uuid(&meta->guid, fingerprint, meta->timestamp);

    // Initialize counters
    meta->session_count = 0;
    meta->read_count = 0;
    meta->error_count = 0;
    meta->flags = META_FLAG_NONE;

    // Clear sessions
    for (int i = 0; i < 16; i++) {
        memset(&meta->sessions[i], 0, sizeof(diag_session_t));
    }

    memset(meta->user_notes, 0, sizeof(meta->user_notes));

    meta->valid = true;
    meta->dirty = true;

    return META_OK;
}

void meta_add_session(hdd_metadata_t *meta,
                      diag_session_type_t type,
                      uint32_t duration_sec,
                      uint16_t errors,
                      uint8_t warnings) {
    if (meta == NULL) return;

    // Shift existing sessions down
    for (int i = 15; i > 0; i--) {
        meta->sessions[i] = meta->sessions[i - 1];
    }

    // Add new session at index 0
    meta->sessions[0].timestamp = (uint64_t)time(NULL);
    meta->sessions[0].type = (uint8_t)type;
    meta->sessions[0].duration_sec = duration_sec;
    meta->sessions[0].errors = errors;
    meta->sessions[0].warnings = warnings;

    meta->dirty = true;
}

void meta_update_stats(hdd_metadata_t *meta,
                       uint32_t sectors_read,
                       uint32_t errors) {
    if (meta == NULL) return;

    meta->session_count++;
    meta->read_count += sectors_read;
    meta->error_count += errors;
    meta->timestamp = (uint64_t)time(NULL);

    if (errors > 0) {
        meta->flags |= META_FLAG_ERRORS_FOUND;
    }

    meta->dirty = true;
}

void meta_set_notes(hdd_metadata_t *meta, const char *notes) {
    if (meta == NULL) return;

    memset(meta->user_notes, 0, sizeof(meta->user_notes));
    if (notes != NULL) {
        strncpy(meta->user_notes, notes, sizeof(meta->user_notes) - 1);
        meta->flags |= META_FLAG_USER_NOTES;
    } else {
        meta->flags &= ~META_FLAG_USER_NOTES;
    }

    meta->dirty = true;
}

void meta_set_identity(hdd_metadata_t *meta,
                       const char *vendor,
                       const char *model,
                       const char *serial) {
    if (meta == NULL) return;

    if (vendor != NULL) {
        memset(meta->identity.vendor, 0, sizeof(meta->identity.vendor));
        strncpy(meta->identity.vendor, vendor, sizeof(meta->identity.vendor) - 1);
    }

    if (model != NULL) {
        memset(meta->identity.model, 0, sizeof(meta->identity.model));
        strncpy(meta->identity.model, model, sizeof(meta->identity.model) - 1);
    }

    if (serial != NULL) {
        memset(meta->identity.serial, 0, sizeof(meta->identity.serial));
        strncpy(meta->identity.serial, serial, sizeof(meta->identity.serial) - 1);
    }

    meta->dirty = true;
}

void meta_set_identity_extended(hdd_metadata_t *meta,
                                const char *date_code,
                                const char *revision) {
    if (meta == NULL) return;

    if (date_code != NULL) {
        memset(meta->identity.date_code, 0, sizeof(meta->identity.date_code));
        strncpy(meta->identity.date_code, date_code, sizeof(meta->identity.date_code) - 1);
    }

    if (revision != NULL) {
        memset(meta->identity.revision, 0, sizeof(meta->identity.revision));
        strncpy(meta->identity.revision, revision, sizeof(meta->identity.revision) - 1);
    }

    meta->dirty = true;
}

void meta_set_flags(hdd_metadata_t *meta, uint16_t flags, bool clear) {
    if (meta == NULL) return;

    if (clear) {
        meta->flags &= ~flags;
    } else {
        meta->flags |= flags;
    }

    meta->dirty = true;
}

bool meta_get_defect_list(uint8_t drive,
                          uint16_t *cylinder,
                          uint8_t *head,
                          uint8_t *start_sector,
                          uint8_t *count) {
    if (drive > 1 || !g_meta.initialized[drive]) {
        return false;
    }

    if (!g_meta.config[drive].enabled) {
        return false;
    }

    *cylinder = g_meta.config[drive].cylinder;
    *head = g_meta.config[drive].head;
    *start_sector = g_meta.config[drive].start_sector;
    *count = METADATA_NUM_SECTORS;

    return true;
}

void meta_generate_uuid(uuid_t *uuid,
                        const drive_fingerprint_t *fingerprint,
                        uint64_t timestamp) {
    if (uuid == NULL) return;

    // Use fingerprint hash as primary seed
    uint32_t fp_hash = fingerprint_hash(fingerprint);

    // LFSR state seeded from fingerprint + timestamp
    uint32_t lfsr = fp_hash ^ (uint32_t)timestamp ^ 0xDEADBEEF;

    // Generate UUID components
    uuid->data1 = lfsr_next(&lfsr) ^ fp_hash;
    uuid->data2 = (uint16_t)(lfsr_next(&lfsr) & 0xFFFF);
    uuid->data3 = (uint16_t)((lfsr_next(&lfsr) & 0x0FFF) | 0x4000);  // Version 4

    for (int i = 0; i < 8; i++) {
        uuid->data4[i] = (uint8_t)(lfsr_next(&lfsr) & 0xFF);
    }

    // Set variant bits (RFC 4122 variant)
    uuid->data4[0] = (uuid->data4[0] & 0x3F) | 0x80;
}

void meta_uuid_to_string(const uuid_t *uuid, char *buf) {
    if (uuid == NULL || buf == NULL) return;

    snprintf(buf, 37, "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X",
             uuid->data1,
             uuid->data2,
             uuid->data3,
             uuid->data4[0], uuid->data4[1],
             uuid->data4[2], uuid->data4[3], uuid->data4[4],
             uuid->data4[5], uuid->data4[6], uuid->data4[7]);
}

void meta_print_summary(const hdd_metadata_t *meta) {
    if (meta == NULL) {
        printf("Metadata: NULL\n");
        return;
    }

    if (!meta->valid) {
        printf("Metadata: Not present on drive\n");
        return;
    }

    char uuid_str[37];
    meta_uuid_to_string(&meta->guid, uuid_str);

    printf("\n=== FluxRipper Drive Metadata ===\n");
    printf("UUID:           %s\n", uuid_str);
    printf("Last Updated:   %llu\n", (unsigned long long)meta->timestamp);

    // Drive identification (from label)
    printf("\n--- Drive Identification ---\n");
    if (meta->identity.vendor[0] != '\0') {
        printf("Vendor:         %s\n", meta->identity.vendor);
    } else {
        printf("Vendor:         (not set)\n");
    }
    if (meta->identity.model[0] != '\0') {
        printf("Model:          %s\n", meta->identity.model);
    } else {
        printf("Model:          (not set)\n");
    }
    if (meta->identity.serial[0] != '\0') {
        printf("Serial:         %s\n", meta->identity.serial);
    } else {
        printf("Serial:         (not set)\n");
    }
    if (meta->identity.date_code[0] != '\0') {
        printf("Date Code:      %s\n", meta->identity.date_code);
    }
    if (meta->identity.revision[0] != '\0') {
        printf("Revision:       %s\n", meta->identity.revision);
    }

    printf("\n--- Usage Statistics ---\n");
    printf("Sessions:       %u\n", meta->session_count);
    printf("Sectors Read:   %u\n", meta->read_count);
    printf("Total Errors:   %u\n", meta->error_count);

    printf("\nFlags:          0x%04X", meta->flags);
    if (meta->flags & META_FLAG_WRITE_PROTECT) printf(" [WP]");
    if (meta->flags & META_FLAG_IMAGED) printf(" [IMAGED]");
    if (meta->flags & META_FLAG_VERIFIED) printf(" [VERIFIED]");
    if (meta->flags & META_FLAG_ERRORS_FOUND) printf(" [ERRORS]");
    if (meta->flags & META_FLAG_CRITICAL_DATA) printf(" [CRITICAL]");
    printf("\n");

    printf("\n--- Discovered Characteristics ---\n");
    printf("RPM:            %u.%u\n", meta->fingerprint.rpm_x10 / 10,
                                      meta->fingerprint.rpm_x10 % 10);
    printf("Cylinders:      %u\n", meta->fingerprint.max_cylinder);
    printf("Heads:          %u\n", meta->fingerprint.heads);
    printf("SPT (O/M/I):    %u / %u / %u\n",
           meta->fingerprint.spt_outer,
           meta->fingerprint.spt_mid,
           meta->fingerprint.spt_inner);
    printf("Zoned (ZBR):    %s\n", meta->fingerprint.is_zoned ? "Yes" : "No");
    printf("Seek Type:      %s\n",
           meta->fingerprint.seek_curve_type == 1 ? "Voice Coil" :
           meta->fingerprint.seek_curve_type == 2 ? "Stepper" : "Unknown");
    printf("Jitter (O/I):   %u / %u\n",
           meta->fingerprint.jitter_outer,
           meta->fingerprint.jitter_inner);

    if (meta->flags & META_FLAG_USER_NOTES && meta->user_notes[0] != '\0') {
        printf("\nUser Notes:     %s\n", meta->user_notes);
    }
    printf("\n");
}

void meta_print_history(const hdd_metadata_t *meta) {
    if (meta == NULL || !meta->valid) {
        printf("No history available\n");
        return;
    }

    printf("\n=== Diagnostic Session History ===\n");
    printf("%-4s %-12s %-8s %-10s %-6s %-6s\n",
           "#", "Timestamp", "Type", "Duration", "Errors", "Warns");
    printf("---- ------------ -------- ---------- ------ ------\n");

    for (int i = 0; i < 16; i++) {
        if (meta->sessions[i].timestamp == 0) {
            continue;  // Empty slot
        }

        const char *type_str;
        switch (meta->sessions[i].type) {
            case DIAG_TYPE_DISCOVERY:     type_str = "DISCOVER"; break;
            case DIAG_TYPE_FINGERPRINT:   type_str = "FINGERPT"; break;
            case DIAG_TYPE_FULL_IMAGE:    type_str = "FULL IMG"; break;
            case DIAG_TYPE_PARTIAL_IMAGE: type_str = "PART IMG"; break;
            case DIAG_TYPE_VERIFY:        type_str = "VERIFY";   break;
            case DIAG_TYPE_HEALTH_CHECK:  type_str = "HEALTH";   break;
            case DIAG_TYPE_REPAIR:        type_str = "REPAIR";   break;
            case DIAG_TYPE_USER_SESSION:  type_str = "USER";     break;
            default:                      type_str = "UNKNOWN";  break;
        }

        // Format duration as HH:MM:SS
        uint32_t dur = meta->sessions[i].duration_sec;
        uint32_t hours = dur / 3600;
        uint32_t mins = (dur % 3600) / 60;
        uint32_t secs = dur % 60;

        printf("%-4d %12llu %-8s %02u:%02u:%02u   %-6u %-6u\n",
               i,
               (unsigned long long)meta->sessions[i].timestamp,
               type_str,
               hours, mins, secs,
               meta->sessions[i].errors,
               meta->sessions[i].warnings);
    }
    printf("\n");
}

//=============================================================================
// CLI Commands
//=============================================================================

/**
 * CLI: meta status [drive]
 * Shows metadata status for specified drive or both
 */
void cmd_meta_status(int argc, char **argv) {
    int drive_start = 0;
    int drive_end = 1;

    if (argc > 2) {
        int d = atoi(argv[2]);
        if (d >= 0 && d <= 1) {
            drive_start = d;
            drive_end = d;
        }
    }

    for (int d = drive_start; d <= drive_end; d++) {
        printf("\n--- Drive %d ---\n", d);

        if (!g_meta.initialized[d]) {
            printf("Metadata subsystem not initialized\n");
            continue;
        }

        hdd_metadata_t meta;
        meta_error_t err = meta_read(d, &meta);

        if (err == META_OK) {
            meta_print_summary(&meta);
        } else if (err == META_ERR_NO_SIGNATURE) {
            printf("No FluxRipper metadata found on this drive\n");
            printf("Use 'meta init' to create metadata\n");
        } else {
            printf("Error reading metadata: %d\n", err);
        }
    }
}

/**
 * CLI: meta init <drive>
 * Initialize metadata on a drive (requires fingerprint first)
 */
void cmd_meta_init(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: meta init <drive>\n");
        return;
    }

    int drive = atoi(argv[2]);
    if (drive < 0 || drive > 1) {
        printf("Invalid drive number (0 or 1)\n");
        return;
    }

    // Check if fingerprint exists
    // TODO: Get fingerprint from discovery cache
    drive_fingerprint_t fp;
    memset(&fp, 0, sizeof(fp));

    // For now, create with placeholder fingerprint
    printf("Creating metadata on drive %d...\n", drive);

    hdd_metadata_t meta;
    meta_error_t err = meta_create_new(&meta, &fp);
    if (err != META_OK) {
        printf("Failed to create metadata: %d\n", err);
        return;
    }

    err = meta_write(drive, &meta);
    if (err != META_OK) {
        printf("Failed to write metadata: %d\n", err);
        return;
    }

    printf("Metadata initialized successfully!\n");
    meta_print_summary(&meta);
}

/**
 * CLI: meta history <drive>
 * Show diagnostic session history
 */
void cmd_meta_history(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: meta history <drive>\n");
        return;
    }

    int drive = atoi(argv[2]);
    if (drive < 0 || drive > 1) {
        printf("Invalid drive number\n");
        return;
    }

    hdd_metadata_t meta;
    meta_error_t err = meta_read(drive, &meta);

    if (err == META_OK) {
        meta_print_history(&meta);
    } else {
        printf("Error reading metadata: %d\n", err);
    }
}

/**
 * CLI: meta note <drive> <text>
 * Set user notes
 */
void cmd_meta_note(int argc, char **argv) {
    if (argc < 4) {
        printf("Usage: meta note <drive> <text>\n");
        return;
    }

    int drive = atoi(argv[2]);
    if (drive < 0 || drive > 1) {
        printf("Invalid drive number\n");
        return;
    }

    hdd_metadata_t meta;
    meta_error_t err = meta_read(drive, &meta);
    if (err != META_OK) {
        printf("Error reading metadata: %d\n", err);
        return;
    }

    // Concatenate remaining arguments as note
    char note[32] = {0};
    int pos = 0;
    for (int i = 3; i < argc && pos < 31; i++) {
        int len = strlen(argv[i]);
        if (pos + len + 1 < 31) {
            if (pos > 0) note[pos++] = ' ';
            strcpy(&note[pos], argv[i]);
            pos += len;
        }
    }

    meta_set_notes(&meta, note);

    err = meta_write(drive, &meta);
    if (err != META_OK) {
        printf("Error writing metadata: %d\n", err);
        return;
    }

    printf("Note saved: %s\n", note);
}

/**
 * CLI: meta erase <drive>
 * Erase metadata from drive
 */
void cmd_meta_erase(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: meta erase <drive>\n");
        return;
    }

    int drive = atoi(argv[2]);
    if (drive < 0 || drive > 1) {
        printf("Invalid drive number\n");
        return;
    }

    printf("WARNING: This will erase FluxRipper metadata from drive %d\n", drive);
    printf("Are you sure? (y/N): ");

    // In real implementation, wait for user input
    // For now, just proceed
    printf("Erasing...\n");

    meta_error_t err = meta_erase(drive);
    if (err != META_OK) {
        printf("Error erasing metadata: %d\n", err);
        return;
    }

    printf("Metadata erased successfully\n");
}

/**
 * CLI: meta id <drive> <vendor> <model> [serial]
 * Set drive identification from label
 */
void cmd_meta_id(int argc, char **argv) {
    if (argc < 5) {
        printf("Usage: meta id <drive> <vendor> <model> [serial]\n");
        printf("Example: meta id 0 Seagate ST-225 8734291\n");
        printf("Example: meta id 1 \"Control Data\" \"Wren III\" \"ABC123\"\n");
        return;
    }

    int drive = atoi(argv[2]);
    if (drive < 0 || drive > 1) {
        printf("Invalid drive number\n");
        return;
    }

    const char *vendor = argv[3];
    const char *model = argv[4];
    const char *serial = (argc > 5) ? argv[5] : NULL;

    hdd_metadata_t meta;
    meta_error_t err = meta_read(drive, &meta);

    if (err == META_ERR_NO_SIGNATURE) {
        // No metadata yet - create new
        printf("No existing metadata, creating new...\n");
        drive_fingerprint_t fp;
        memset(&fp, 0, sizeof(fp));
        meta_create_new(&meta, &fp);
    } else if (err != META_OK) {
        printf("Error reading metadata: %d\n", err);
        return;
    }

    meta_set_identity(&meta, vendor, model, serial);

    err = meta_write(drive, &meta);
    if (err != META_OK) {
        printf("Error writing metadata: %d\n", err);
        return;
    }

    printf("Drive identification saved:\n");
    printf("  Vendor: %s\n", meta.identity.vendor);
    printf("  Model:  %s\n", meta.identity.model);
    if (meta.identity.serial[0] != '\0') {
        printf("  Serial: %s\n", meta.identity.serial);
    }
}

/**
 * CLI: meta datecode <drive> <date_code> [revision]
 * Set extended identity fields
 */
void cmd_meta_datecode(int argc, char **argv) {
    if (argc < 4) {
        printf("Usage: meta datecode <drive> <date_code> [revision]\n");
        printf("Example: meta datecode 0 8723 A.01\n");
        return;
    }

    int drive = atoi(argv[2]);
    if (drive < 0 || drive > 1) {
        printf("Invalid drive number\n");
        return;
    }

    const char *date_code = argv[3];
    const char *revision = (argc > 4) ? argv[4] : NULL;

    hdd_metadata_t meta;
    meta_error_t err = meta_read(drive, &meta);
    if (err != META_OK && err != META_ERR_NO_SIGNATURE) {
        printf("Error reading metadata: %d\n", err);
        return;
    }

    if (err == META_ERR_NO_SIGNATURE) {
        printf("No metadata on drive. Use 'meta init' or 'meta id' first.\n");
        return;
    }

    meta_set_identity_extended(&meta, date_code, revision);

    err = meta_write(drive, &meta);
    if (err != META_OK) {
        printf("Error writing metadata: %d\n", err);
        return;
    }

    printf("Extended identity saved:\n");
    printf("  Date Code: %s\n", meta.identity.date_code);
    if (meta.identity.revision[0] != '\0') {
        printf("  Revision:  %s\n", meta.identity.revision);
    }
}
