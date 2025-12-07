/**
 * @file hdd_metadata.h
 * @brief FluxRipper HDD Steganographic Metadata API
 *
 * Provides functions for storing and retrieving hidden metadata on vintage
 * hard drives. Metadata is stored in "fake bad sectors" that appear as
 * defective to the host operating system but are readable by FluxRipper.
 *
 * Storage Strategy:
 *   - Reserve 4 sectors at configurable C/H/S (default: cyl 0, head 1, sec 1-4)
 *   - Report these sectors as "defective" to WD controller emulation
 *   - Host OS avoids them; FluxRipper accesses directly via flux-level I/O
 *   - Signature "FLXR" identifies FluxRipper metadata vs. actual bad sectors
 *
 * @author Claude Code (FluxRipper Project)
 * @date 2025-12-04 20:07
 */

#ifndef HDD_METADATA_H
#define HDD_METADATA_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

//=============================================================================
// Constants
//=============================================================================

#define METADATA_SIGNATURE      0x464C5852u  // "FLXR"
#define METADATA_VERSION        0x01u
#define METADATA_NUM_SECTORS    4
#define METADATA_SECTOR_SIZE    512

// Default storage location (avoids track 0 conflicts with boot sectors)
#define METADATA_DEFAULT_CYL    0
#define METADATA_DEFAULT_HEAD   1
#define METADATA_DEFAULT_SEC    1

// Diagnostic session types
typedef enum {
    DIAG_TYPE_UNKNOWN       = 0x00,
    DIAG_TYPE_DISCOVERY     = 0x01,
    DIAG_TYPE_FINGERPRINT   = 0x02,
    DIAG_TYPE_FULL_IMAGE    = 0x03,
    DIAG_TYPE_PARTIAL_IMAGE = 0x04,
    DIAG_TYPE_VERIFY        = 0x05,
    DIAG_TYPE_HEALTH_CHECK  = 0x06,
    DIAG_TYPE_REPAIR        = 0x07,
    DIAG_TYPE_USER_SESSION  = 0x08,
} diag_session_type_t;

// Error codes
typedef enum {
    META_OK                 = 0,
    META_ERR_SEEK_FAILED    = 1,
    META_ERR_HEAD_SELECT    = 2,
    META_ERR_SECTOR_READ    = 3,
    META_ERR_CRC_FAILURE    = 4,
    META_ERR_NO_SIGNATURE   = 5,
    META_ERR_VERSION_MISMATCH = 6,
    META_ERR_WRITE_FAILED   = 7,
    META_ERR_DISABLED       = 8,
    META_ERR_TIMEOUT        = 9,
    META_ERR_INVALID_DRIVE  = 10,
    META_ERR_NOT_INITIALIZED = 11,
    META_ERR_BUSY           = 12,
} meta_error_t;

// User flags (stored in metadata)
typedef enum {
    META_FLAG_NONE          = 0x0000,
    META_FLAG_WRITE_PROTECT = 0x0001,  // User requested write protection
    META_FLAG_IMAGED        = 0x0002,  // Drive has been fully imaged
    META_FLAG_VERIFIED      = 0x0004,  // Image has been verified
    META_FLAG_ERRORS_FOUND  = 0x0008,  // Errors were found during imaging
    META_FLAG_USER_NOTES    = 0x0010,  // User notes present
    META_FLAG_CRITICAL_DATA = 0x0020,  // Contains critical data (handle with care)
    META_FLAG_ARCHIVED      = 0x0040,  // Has been archived to external storage
    META_FLAG_DIRTY         = 0x0080,  // Metadata needs to be written
} meta_flags_t;

//=============================================================================
// Data Structures
//=============================================================================

/**
 * @brief 128-bit UUID/GUID structure
 */
typedef struct {
    uint32_t data1;
    uint16_t data2;
    uint16_t data3;
    uint8_t  data4[8];
} uuid_t;

/**
 * @brief Diagnostic session record (16 bytes)
 */
typedef struct __attribute__((packed)) {
    uint64_t timestamp;     // Unix timestamp
    uint8_t  type;          // diag_session_type_t
    uint32_t duration_sec;  // Session duration in seconds
    uint16_t errors;        // Errors encountered
    uint8_t  warnings;      // Warnings encountered
} diag_session_t;

/**
 * @brief Drive fingerprint (256 bits = 32 bytes)
 *
 * Packed representation of hdd_fingerprint module output.
 */
typedef struct __attribute__((packed)) {
    uint16_t rpm_x10;           // RPM * 10
    uint8_t  rpm_jitter;        // RPM stability (0-255)
    uint16_t max_cylinder;      // Mechanical cylinder limit
    uint8_t  heads;             // Number of valid heads
    uint8_t  spt_outer;         // Sectors per track (outer zone)
    uint8_t  spt_mid;           // Sectors per track (mid zone)
    uint8_t  spt_inner;         // Sectors per track (inner zone)
    uint8_t  jitter_outer;      // Bit jitter at outer cylinder
    uint8_t  jitter_inner;      // Bit jitter at inner cylinder
    uint8_t  seek_curve_type;   // 0=unknown, 1=voice coil, 2=stepper
    uint16_t seek_time_short;   // Short seek time (clocks)
    uint16_t seek_time_long;    // Long seek time (clocks)
    uint16_t defect_hash;       // Hash of defect locations
    uint8_t  is_zoned;          // 1 if ZBR detected
    uint8_t  reserved[13];      // Padding to 32 bytes
} drive_fingerprint_t;

/**
 * @brief User-supplied drive identification
 *
 * Fields for manually entering drive label information that isn't
 * electronically readable on vintage ST-506/ESDI drives.
 */
typedef struct __attribute__((packed)) {
    char vendor[16];            // e.g., "Seagate", "Miniscribe", "CDC"
    char model[24];             // e.g., "ST-225", "3425", "Wren III"
    char serial[20];            // Serial number from label
    char date_code[8];          // Manufacturing date code
    char revision[8];           // Firmware/PCB revision
    uint8_t reserved[20];       // Padding to 96 bytes
} drive_identity_t;

/**
 * @brief Complete metadata structure
 *
 * This is the in-memory representation of all metadata stored on the drive.
 * Total storage: 4 sectors (2048 bytes)
 *
 * Sector 0 (512 bytes): Header + Identity
 *   - Signature, version, GUID, timestamp, flags (34 bytes)
 *   - Drive identity (96 bytes)
 *   - Reserved (382 bytes)
 *
 * Sector 1 (512 bytes): Profile + Stats
 *   - Fingerprint (32 bytes)
 *   - Stats (12 bytes)
 *   - Reserved (468 bytes)
 *
 * Sector 2 (512 bytes): Diagnostic sessions 0-7
 *   - 8 sessions x 16 bytes = 128 bytes
 *   - Reserved (384 bytes)
 *
 * Sector 3 (512 bytes): Diagnostic sessions 8-15 + User notes
 *   - 8 sessions x 16 bytes = 128 bytes
 *   - User notes (64 bytes)
 *   - Reserved (320 bytes)
 */
typedef struct {
    // Header (Sector 0)
    uint32_t signature;         // Must be METADATA_SIGNATURE
    uint8_t  version;           // METADATA_VERSION
    uuid_t   guid;              // Unique drive identifier
    uint64_t timestamp;         // Last update timestamp
    uint16_t flags;             // meta_flags_t

    // User-supplied drive identification (Sector 0, offset 34)
    drive_identity_t identity;  // Vendor, model, serial from label

    // Profile (Sector 1)
    drive_fingerprint_t fingerprint;
    uint32_t session_count;     // Total FluxRipper sessions
    uint32_t read_count;        // Total sectors read
    uint32_t error_count;       // Cumulative errors

    // Diagnostic History (Sectors 2-3)
    diag_session_t sessions[16];

    // User notes (end of Sector 3) - expanded to 64 bytes
    char user_notes[64];        // ASCII, null-terminated

    // Runtime state (not stored)
    bool     valid;             // Metadata was successfully read
    bool     dirty;             // Needs to be written back
} hdd_metadata_t;

/**
 * @brief Metadata storage configuration
 */
typedef struct {
    uint16_t cylinder;          // Storage cylinder (0 = default)
    uint8_t  head;              // Storage head (0xFF = default)
    uint8_t  start_sector;      // Starting sector (0xFF = default)
    bool     enabled;           // Metadata storage enabled
    bool     auto_write;        // Auto-write on session end
    bool     generate_guid_on_first; // Generate GUID if not present
} meta_config_t;

//=============================================================================
// Function Prototypes
//=============================================================================

/**
 * @brief Initialize metadata subsystem
 *
 * Must be called before any other metadata functions.
 *
 * @param drive Drive number (0 or 1)
 * @param config Configuration (NULL for defaults)
 * @return META_OK on success, error code otherwise
 */
meta_error_t meta_init(uint8_t drive, const meta_config_t *config);

/**
 * @brief Read metadata from drive
 *
 * Seeks to metadata location and reads all 4 sectors. If no FluxRipper
 * signature is found, returns META_ERR_NO_SIGNATURE (this is normal for
 * drives that haven't been tagged yet).
 *
 * @param drive Drive number (0 or 1)
 * @param meta Output buffer for metadata (required)
 * @return META_OK on success, error code otherwise
 */
meta_error_t meta_read(uint8_t drive, hdd_metadata_t *meta);

/**
 * @brief Write metadata to drive
 *
 * Writes all 4 metadata sectors to drive. This will make these sectors
 * appear as "bad" to the host operating system.
 *
 * WARNING: This modifies the disk surface. Ensure you have a backup
 * before calling this on valuable drives.
 *
 * @param drive Drive number (0 or 1)
 * @param meta Metadata to write
 * @return META_OK on success, error code otherwise
 */
meta_error_t meta_write(uint8_t drive, const hdd_metadata_t *meta);

/**
 * @brief Erase metadata from drive
 *
 * Writes zeros to metadata sectors, removing the FluxRipper signature.
 * The sectors will still appear as "bad" due to missing valid data.
 *
 * @param drive Drive number (0 or 1)
 * @return META_OK on success, error code otherwise
 */
meta_error_t meta_erase(uint8_t drive);

/**
 * @brief Initialize metadata for first-time storage
 *
 * Creates a new metadata structure with:
 *   - Generated GUID
 *   - Current timestamp
 *   - Fingerprint from discovery
 *   - Zeroed session history
 *
 * @param meta Output metadata structure
 * @param fingerprint Drive fingerprint (from hdd_fingerprint)
 * @return META_OK on success
 */
meta_error_t meta_create_new(hdd_metadata_t *meta,
                             const drive_fingerprint_t *fingerprint);

/**
 * @brief Add diagnostic session to history
 *
 * Shifts existing sessions and adds new one at index 0.
 *
 * @param meta Metadata structure (modified in place)
 * @param type Session type
 * @param duration_sec Session duration
 * @param errors Error count
 * @param warnings Warning count
 */
void meta_add_session(hdd_metadata_t *meta,
                      diag_session_type_t type,
                      uint32_t duration_sec,
                      uint16_t errors,
                      uint8_t warnings);

/**
 * @brief Increment session/read/error counters
 *
 * Call at end of imaging or diagnostic session.
 *
 * @param meta Metadata structure (modified)
 * @param sectors_read Sectors read this session
 * @param errors Errors this session
 */
void meta_update_stats(hdd_metadata_t *meta,
                       uint32_t sectors_read,
                       uint32_t errors);

/**
 * @brief Set user notes
 *
 * @param meta Metadata structure (modified)
 * @param notes Note string (max 63 chars + null)
 */
void meta_set_notes(hdd_metadata_t *meta, const char *notes);

/**
 * @brief Set drive identity (vendor/model/serial from label)
 *
 * Call this to record the information from the drive's physical label.
 * All fields are optional - pass NULL to leave unchanged.
 *
 * @param meta Metadata structure (modified)
 * @param vendor Vendor name (max 15 chars), e.g., "Seagate"
 * @param model Model number (max 23 chars), e.g., "ST-225"
 * @param serial Serial number (max 19 chars)
 */
void meta_set_identity(hdd_metadata_t *meta,
                       const char *vendor,
                       const char *model,
                       const char *serial);

/**
 * @brief Set extended identity fields
 *
 * @param meta Metadata structure (modified)
 * @param date_code Manufacturing date code (max 7 chars)
 * @param revision Firmware/PCB revision (max 7 chars)
 */
void meta_set_identity_extended(hdd_metadata_t *meta,
                                const char *date_code,
                                const char *revision);

/**
 * @brief Set/clear flags
 *
 * @param meta Metadata structure (modified)
 * @param flags Flags to set
 * @param clear If true, clear these flags instead of setting
 */
void meta_set_flags(hdd_metadata_t *meta, uint16_t flags, bool clear);

/**
 * @brief Get defect list for WD controller emulation
 *
 * Returns the C/H/S locations that should appear as "bad sectors" to the
 * host operating system. The WD controller emulation uses this to populate
 * the defect list returned by FORMAT TRACK and READ DEFECT commands.
 *
 * @param drive Drive number (0 or 1)
 * @param cylinder Output: defect cylinder
 * @param head Output: defect head
 * @param start_sector Output: first defect sector
 * @param count Output: number of consecutive defect sectors
 * @return true if metadata storage is enabled
 */
bool meta_get_defect_list(uint8_t drive,
                          uint16_t *cylinder,
                          uint8_t *head,
                          uint8_t *start_sector,
                          uint8_t *count);

/**
 * @brief Generate UUID from drive characteristics
 *
 * Creates a reproducible UUID based on fingerprint + timestamp + entropy.
 *
 * @param uuid Output UUID
 * @param fingerprint Drive fingerprint
 * @param timestamp Current timestamp
 */
void meta_generate_uuid(uuid_t *uuid,
                        const drive_fingerprint_t *fingerprint,
                        uint64_t timestamp);

/**
 * @brief Format UUID as string
 *
 * @param uuid UUID to format
 * @param buf Output buffer (must be at least 37 bytes)
 */
void meta_uuid_to_string(const uuid_t *uuid, char *buf);

/**
 * @brief Print metadata summary to console
 *
 * @param meta Metadata to print
 */
void meta_print_summary(const hdd_metadata_t *meta);

/**
 * @brief Print diagnostic history to console
 *
 * @param meta Metadata with session history
 */
void meta_print_history(const hdd_metadata_t *meta);

//=============================================================================
// Register Interface (for direct RTL access)
//=============================================================================

// Base address (relative to HDD controller base 0x80007000)
#define META_REG_BASE           0x100

// Registers
#define META_REG_CTRL           (META_REG_BASE + 0x00)  // Control/status
#define META_REG_CONFIG         (META_REG_BASE + 0x04)  // Configuration
#define META_REG_CYL_HEAD       (META_REG_BASE + 0x08)  // Cylinder/head config
#define META_REG_SECTOR         (META_REG_BASE + 0x0C)  // Sector config
#define META_REG_GUID_0         (META_REG_BASE + 0x10)  // GUID[31:0]
#define META_REG_GUID_1         (META_REG_BASE + 0x14)  // GUID[63:32]
#define META_REG_GUID_2         (META_REG_BASE + 0x18)  // GUID[95:64]
#define META_REG_GUID_3         (META_REG_BASE + 0x1C)  // GUID[127:96]
#define META_REG_TIMESTAMP_LO   (META_REG_BASE + 0x20)  // Timestamp[31:0]
#define META_REG_TIMESTAMP_HI   (META_REG_BASE + 0x24)  // Timestamp[63:32]
#define META_REG_FLAGS          (META_REG_BASE + 0x28)  // User flags
#define META_REG_SESSION_COUNT  (META_REG_BASE + 0x2C)  // Session count
#define META_REG_READ_COUNT     (META_REG_BASE + 0x30)  // Read count
#define META_REG_ERROR_COUNT    (META_REG_BASE + 0x34)  // Error count
#define META_REG_FINGERPRINT_0  (META_REG_BASE + 0x40)  // Fingerprint bytes 0-3
// ... (8 more fingerprint registers)
#define META_REG_DIAG_IDX       (META_REG_BASE + 0x80)  // Diagnostic session index
#define META_REG_DIAG_DATA_0    (META_REG_BASE + 0x84)  // Session data word 0
#define META_REG_DIAG_DATA_1    (META_REG_BASE + 0x88)  // Session data word 1
#define META_REG_DIAG_DATA_2    (META_REG_BASE + 0x8C)  // Session data word 2
#define META_REG_DIAG_DATA_3    (META_REG_BASE + 0x90)  // Session data word 3

// Control register bits
#define META_CTRL_READ_START    (1 << 0)
#define META_CTRL_WRITE_START   (1 << 1)
#define META_CTRL_ERASE_START   (1 << 2)
#define META_CTRL_BUSY          (1 << 8)
#define META_CTRL_DONE          (1 << 9)
#define META_CTRL_ERROR         (1 << 10)
#define META_CTRL_VALID         (1 << 11)
#define META_CTRL_ERROR_CODE    (0xF << 12)

// Config register bits
#define META_CONFIG_ENABLE      (1 << 0)
#define META_CONFIG_AUTO_WRITE  (1 << 1)
#define META_CONFIG_GEN_GUID    (1 << 2)

#ifdef __cplusplus
}
#endif

#endif // HDD_METADATA_H
