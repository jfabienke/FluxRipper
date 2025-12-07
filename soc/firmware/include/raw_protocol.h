/*-----------------------------------------------------------------------------
 * raw_protocol.h
 * USB Vendor-Specific Raw Mode Protocol Definitions
 *
 * Created: 2025-12-05 16:30
 *
 * Defines the command and response format for the FluxRipper Raw Mode
 * USB interface. Used for flux capture, diagnostics, and low-level access.
 *---------------------------------------------------------------------------*/

#ifndef RAW_PROTOCOL_H
#define RAW_PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>

/*---------------------------------------------------------------------------
 * Protocol Constants
 *---------------------------------------------------------------------------*/

#define RAW_SIGNATURE           0x46525751  /* "FRWQ" - FluxRipper Wireless Query */
#define RAW_CMD_PACKET_SIZE     16          /* 16 bytes = 4 words */
#define RAW_RSP_HEADER_SIZE     8           /* Minimum response size */

/*---------------------------------------------------------------------------
 * Command Opcodes
 *---------------------------------------------------------------------------*/

#define RAW_CMD_NOP                 0x00    /* Status query */
#define RAW_CMD_GET_INFO            0x01    /* Device/version info */
#define RAW_CMD_SELECT_DRIVE        0x02    /* Select physical drive (0-3) */
#define RAW_CMD_MOTOR_CTRL          0x03    /* Motor on/off */
#define RAW_CMD_SEEK                0x05    /* Seek to track */
#define RAW_CMD_CAPTURE_START       0x10    /* Begin flux capture */
#define RAW_CMD_CAPTURE_STOP        0x11    /* End flux capture */
#define RAW_CMD_READ_FLUX           0x13    /* Stream flux data */
#define RAW_CMD_READ_TRACK_RAW      0x20    /* Read track with metadata */
#define RAW_CMD_GET_PLL_STATUS      0x30    /* PLL diagnostics */
#define RAW_CMD_GET_SIGNAL_QUAL     0x31    /* Signal quality metrics */
#define RAW_CMD_GET_DRIVE_PROFILE   0x40    /* Detected drive parameters */

/*---------------------------------------------------------------------------
 * Response Codes
 *---------------------------------------------------------------------------*/

#define RAW_RSP_OK                  0x00    /* Success */
#define RAW_RSP_ERR_INVALID_CMD     0x01    /* Invalid command opcode */
#define RAW_RSP_ERR_INVALID_PARAM   0x02    /* Invalid parameter */
#define RAW_RSP_ERR_NO_DRIVE        0x03    /* No drive selected/connected */
#define RAW_RSP_ERR_NOT_READY       0x04    /* Drive not ready */
#define RAW_RSP_ERR_OVERFLOW        0x05    /* Buffer overflow */
#define RAW_RSP_ERR_TIMEOUT         0x06    /* Operation timeout */
#define RAW_RSP_ERR_BUSY            0x07    /* Device busy */

/*---------------------------------------------------------------------------
 * Flux Data Format (32-bit per transition)
 *---------------------------------------------------------------------------*/

#define FLUX_FLAG_INDEX         (1 << 31)   /* INDEX pulse marker */
#define FLUX_FLAG_OVERFLOW      (1 << 30)   /* Timer overflow warning */
#define FLUX_FLAG_WEAK          (1 << 29)   /* Weak bit detected */
#define FLUX_TIMESTAMP_MASK     0x07FFFFFF  /* 27-bit timestamp (~5ns @ 200MHz) */

/*---------------------------------------------------------------------------
 * Data Structures
 *---------------------------------------------------------------------------*/

/**
 * Command Packet (16 bytes)
 */
typedef struct __attribute__((packed)) {
    uint32_t    signature;      /* RAW_SIGNATURE */
    uint8_t     opcode;         /* Command opcode */
    uint8_t     param1;         /* First parameter */
    uint16_t    param2;         /* Second parameter */
    uint32_t    param3;         /* Extended parameter */
    uint32_t    param4;         /* Extended parameter */
} raw_cmd_packet_t;

/**
 * Response Header (8 bytes, always sent)
 */
typedef struct __attribute__((packed)) {
    uint32_t    signature;      /* RAW_SIGNATURE */
    uint8_t     status;         /* Response code */
    uint8_t     opcode;         /* Echo of command opcode */
    uint16_t    data_len;       /* Following data length in bytes */
} raw_rsp_header_t;

/**
 * GET_INFO Response Data (24 bytes)
 */
typedef struct __attribute__((packed)) {
    uint32_t    device_id;      /* "FLUX" = 0x464C5558 */
    uint16_t    fw_version;     /* Firmware version (major.minor) */
    uint16_t    hw_version;     /* Hardware version (major.minor) */
    uint8_t     max_luns;       /* Maximum LUNs supported */
    uint8_t     max_fdds;       /* Maximum FDD drives */
    uint8_t     max_hdds;       /* Maximum HDD drives */
    uint8_t     reserved1;
    uint8_t     status_flags;   /* Bit flags for device status */
    uint8_t     reserved2[3];
    uint8_t     selected_drive; /* Currently selected drive */
    uint8_t     drive_type;     /* 0=FDD, 1=HDD */
    uint8_t     current_track;  /* Current head position (FDD) */
    uint8_t     reserved3;
    uint32_t    capacity;       /* Drive capacity in sectors */
} raw_info_data_t;

/* Status flags for raw_info_data_t.status_flags */
#define RAW_STATUS_DISK_PRESENT     (1 << 0)
#define RAW_STATUS_WRITE_PROTECTED  (1 << 1)
#define RAW_STATUS_HDD_READY        (1 << 2)
#define RAW_STATUS_CAPTURE_ACTIVE   (1 << 3)
#define RAW_STATUS_CAPTURE_OVERFLOW (1 << 4)
#define RAW_STATUS_PLL_LOCKED       (1 << 5)

/**
 * PLL Status Response Data (8 bytes)
 */
typedef struct __attribute__((packed)) {
    uint16_t    frequency;      /* Current PLL frequency (kHz) */
    uint8_t     locked;         /* PLL lock status */
    uint8_t     lock_count;     /* Lock acquire count */
    uint16_t    reserved;
    uint8_t     reserved2;
    uint8_t     error_count;    /* PLL error count */
} raw_pll_status_t;

/**
 * Signal Quality Response Data (12 bytes)
 */
typedef struct __attribute__((packed)) {
    uint16_t    amplitude;      /* Signal amplitude (mV) */
    uint16_t    noise;          /* Noise level (mV) */
    uint8_t     reserved;
    uint8_t     bit_error_rate; /* BER estimate (0-255) */
    uint16_t    jitter_ns;      /* Timing jitter (ns) */
    uint8_t     overflow;       /* Capture overflow flag */
    uint8_t     reserved2[3];
} raw_signal_qual_t;

/**
 * Drive Profile Response Data (16 bytes)
 */
typedef struct __attribute__((packed)) {
    uint8_t     drive_num;      /* Drive number (0-3) */
    uint8_t     drive_type;     /* 0=FDD, 1=HDD */
    uint8_t     disk_present;   /* Disk inserted (FDD) */
    uint8_t     write_protected;/* Write protection */
    uint8_t     at_track0;      /* At track 0 (FDD) */
    uint8_t     current_track;  /* Current track (FDD) */
    uint8_t     reserved[2];
    uint32_t    capacity;       /* Total sectors */
    uint32_t    block_size;     /* Bytes per sector */
} raw_drive_profile_t;

/**
 * Extended Drive Profile (for FDD geometry)
 */
typedef struct __attribute__((packed)) {
    uint8_t     tracks;         /* Number of tracks */
    uint8_t     heads;          /* Number of heads */
    uint8_t     sectors;        /* Sectors per track */
    uint8_t     reserved;
} raw_fdd_geometry_t;

/**
 * Flux Capture Info
 */
typedef struct __attribute__((packed)) {
    uint32_t    sample_count;   /* Number of flux samples */
    uint32_t    index_count;    /* Number of index pulses */
    uint32_t    overflow_count; /* Number of overflow events */
    uint32_t    duration_us;    /* Capture duration in microseconds */
} raw_capture_info_t;

/*---------------------------------------------------------------------------
 * Utility Macros
 *---------------------------------------------------------------------------*/

/* Extract fields from flux data word */
#define FLUX_IS_INDEX(x)        (((x) & FLUX_FLAG_INDEX) != 0)
#define FLUX_IS_OVERFLOW(x)     (((x) & FLUX_FLAG_OVERFLOW) != 0)
#define FLUX_IS_WEAK(x)         (((x) & FLUX_FLAG_WEAK) != 0)
#define FLUX_TIMESTAMP(x)       ((x) & FLUX_TIMESTAMP_MASK)

/* Convert timestamp to nanoseconds (assuming 200MHz = 5ns per tick) */
#define FLUX_TO_NS(x)           (FLUX_TIMESTAMP(x) * 5)

/* Build command packet */
#define RAW_BUILD_CMD(cmd, p1, p2, p3, p4) \
    { .signature = RAW_SIGNATURE, \
      .opcode = (cmd), \
      .param1 = (p1), \
      .param2 = (p2), \
      .param3 = (p3), \
      .param4 = (p4) }

/*---------------------------------------------------------------------------
 * Host-side Constants (for documentation)
 *---------------------------------------------------------------------------*/

/* Typical flux capture parameters */
#define RAW_DEFAULT_SAMPLE_RATE     200000000   /* 200 MHz */
#define RAW_DEFAULT_INDEX_TIMEOUT   500000      /* 500ms per revolution */
#define RAW_DEFAULT_CAPTURE_REVS    3           /* Capture 3 revolutions */

/* Maximum values */
#define RAW_MAX_FLUX_SAMPLES        (4 * 1024 * 1024)  /* 4M samples */
#define RAW_MAX_TRACK_SIZE          (64 * 1024)        /* 64KB per track */

#endif /* RAW_PROTOCOL_H */
