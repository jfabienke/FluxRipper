/*-----------------------------------------------------------------------------
 * diagnostics_protocol.h
 * FluxRipper Instrumentation and Diagnostics Protocol
 *
 * Created: 2025-12-05 17:10
 *
 * Extended diagnostics and instrumentation commands for:
 *   - Real-time performance monitoring
 *   - Signal quality analysis
 *   - PLL/clock diagnostics
 *   - Drive characterization
 *   - Error tracking and analysis
 *   - Histogram and statistical data
 *   - Debug/trace capabilities
 *---------------------------------------------------------------------------*/

#ifndef DIAGNOSTICS_PROTOCOL_H
#define DIAGNOSTICS_PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>

/*---------------------------------------------------------------------------
 * Diagnostic Command Opcodes (0x80-0xFF range)
 *---------------------------------------------------------------------------*/

/* System Diagnostics (0x80-0x8F) */
#define DIAG_CMD_GET_VERSION        0x80    /* Detailed version info */
#define DIAG_CMD_GET_BUILD_INFO     0x81    /* Build date, git hash, etc. */
#define DIAG_CMD_GET_UPTIME         0x82    /* System uptime counters */
#define DIAG_CMD_GET_TEMPERATURE    0x83    /* FPGA/board temperature */
#define DIAG_CMD_GET_POWER_STATUS   0x84    /* Voltage rails, current */
#define DIAG_CMD_SELF_TEST          0x85    /* Run self-test sequence */
#define DIAG_CMD_GET_ERROR_LOG      0x86    /* Error history */
#define DIAG_CMD_CLEAR_ERROR_LOG    0x87    /* Clear error history */

/* Performance Counters (0x90-0x9F) */
#define DIAG_CMD_GET_PERF_COUNTERS  0x90    /* All performance counters */
#define DIAG_CMD_RESET_PERF_COUNTERS 0x91   /* Reset counters */
#define DIAG_CMD_GET_USB_STATS      0x92    /* USB transfer statistics */
#define DIAG_CMD_GET_DMA_STATS      0x93    /* DMA transfer statistics */
#define DIAG_CMD_GET_FIFO_STATS     0x94    /* FIFO high-water marks */
#define DIAG_CMD_GET_IRQ_STATS      0x95    /* Interrupt statistics */

/* Signal Analysis (0xA0-0xAF) */
#define DIAG_CMD_GET_SIGNAL_STATS   0xA0    /* Comprehensive signal stats */
#define DIAG_CMD_GET_FLUX_HISTOGRAM 0xA1    /* Flux timing histogram */
#define DIAG_CMD_GET_AMPLITUDE_HIST 0xA2    /* Signal amplitude histogram */
#define DIAG_CMD_GET_JITTER_STATS   0xA3    /* Jitter analysis */
#define DIAG_CMD_GET_BIT_TIMING     0xA4    /* Bit cell timing stats */
#define DIAG_CMD_GET_WEAK_BIT_MAP   0xA5    /* Weak bit locations */
#define DIAG_CMD_CAPTURE_WAVEFORM   0xA6    /* Capture raw ADC waveform */
#define DIAG_CMD_GET_EYE_DIAGRAM    0xA7    /* Eye diagram data */

/* PLL/Clock Diagnostics (0xB0-0xBF) */
#define DIAG_CMD_GET_PLL_DETAILED   0xB0    /* Detailed PLL status */
#define DIAG_CMD_GET_CLOCK_STATS    0xB1    /* Clock frequency stats */
#define DIAG_CMD_GET_PHASE_ERROR    0xB2    /* Phase error histogram */
#define DIAG_CMD_GET_LOCK_HISTORY   0xB3    /* PLL lock/unlock events */
#define DIAG_CMD_SET_PLL_PARAMS     0xB4    /* Configure PLL parameters */
#define DIAG_CMD_GET_RPM_STATS      0xB5    /* Spindle RPM statistics */
#define DIAG_CMD_GET_INDEX_TIMING   0xB6    /* Index pulse timing */

/* Drive Characterization (0xC0-0xCF) */
#define DIAG_CMD_GET_DRIVE_TIMING   0xC0    /* Step/settle timing */
#define DIAG_CMD_GET_HEAD_PROFILE   0xC1    /* Head switching profile */
#define DIAG_CMD_GET_TRACK_PROFILE  0xC2    /* Track geometry profile */
#define DIAG_CMD_GET_WRITE_PRECOMP  0xC3    /* Write precomp settings */
#define DIAG_CMD_MEASURE_STEP_TIME  0xC4    /* Measure actual step time */
#define DIAG_CMD_MEASURE_SETTLE     0xC5    /* Measure head settle time */
#define DIAG_CMD_GET_MOTOR_PROFILE  0xC6    /* Motor spin-up/down profile */
#define DIAG_CMD_TRACK_ECCENTRICITY 0xC7    /* Track eccentricity analysis */

/* Debug/Trace (0xD0-0xDF) */
#define DIAG_CMD_SET_TRACE_MASK     0xD0    /* Configure trace capture */
#define DIAG_CMD_GET_TRACE_DATA     0xD1    /* Read trace buffer */
#define DIAG_CMD_SET_TRIGGER        0xD2    /* Set debug trigger */
#define DIAG_CMD_ARM_TRIGGER        0xD3    /* Arm trigger */
#define DIAG_CMD_GET_TRIGGER_STATUS 0xD4    /* Check trigger status */
#define DIAG_CMD_READ_REG           0xD5    /* Read arbitrary register */
#define DIAG_CMD_WRITE_REG          0xD6    /* Write arbitrary register */
#define DIAG_CMD_GET_STATE_MACHINE  0xD7    /* State machine status */

/* Calibration (0xE0-0xEF) */
#define DIAG_CMD_RUN_CALIBRATION    0xE0    /* Run calibration sequence */
#define DIAG_CMD_GET_CAL_DATA       0xE1    /* Read calibration data */
#define DIAG_CMD_SET_CAL_DATA       0xE2    /* Write calibration data */
#define DIAG_CMD_SAVE_CAL_DATA      0xE3    /* Save to EEPROM */
#define DIAG_CMD_LOAD_CAL_DATA      0xE4    /* Load from EEPROM */
#define DIAG_CMD_FACTORY_RESET      0xE5    /* Reset to factory defaults */

/* Stress Test (0xF0-0xFF) */
#define DIAG_CMD_STRESS_USB         0xF0    /* USB stress test */
#define DIAG_CMD_STRESS_DMA         0xF1    /* DMA stress test */
#define DIAG_CMD_STRESS_SEEK        0xF2    /* Seek stress test */
#define DIAG_CMD_STRESS_RW          0xF3    /* Read/write stress test */
#define DIAG_CMD_LOOPBACK_TEST      0xF4    /* Data loopback test */
#define DIAG_CMD_PATTERN_TEST       0xF5    /* Pattern generator test */

/*---------------------------------------------------------------------------
 * Data Structures - System Info
 *---------------------------------------------------------------------------*/

/**
 * Detailed Version Information
 */
typedef struct __attribute__((packed)) {
    uint16_t    fw_major;
    uint16_t    fw_minor;
    uint16_t    fw_patch;
    uint16_t    fw_build;
    uint16_t    hw_major;
    uint16_t    hw_minor;
    uint32_t    fpga_version;
    uint32_t    fpga_build_date;    /* YYYYMMDD */
    char        git_hash[8];        /* Short git hash */
    uint32_t    capabilities;       /* Feature flags */
} diag_version_info_t;

/**
 * Build Information
 */
typedef struct __attribute__((packed)) {
    uint32_t    build_timestamp;    /* Unix timestamp */
    char        build_date[16];     /* "YYYY-MM-DD" */
    char        build_time[16];     /* "HH:MM:SS" */
    char        compiler[16];       /* Compiler version */
    char        target[16];         /* Build target */
    uint32_t    code_size;          /* Code size in bytes */
    uint32_t    data_size;          /* Data size in bytes */
} diag_build_info_t;

/**
 * Uptime Counters
 */
typedef struct __attribute__((packed)) {
    uint32_t    uptime_seconds;     /* Total uptime in seconds */
    uint32_t    uptime_ms;          /* Milliseconds portion */
    uint32_t    reset_count;        /* Number of resets */
    uint32_t    last_reset_reason;  /* Last reset cause */
    uint32_t    power_cycles;       /* Power cycle count */
    uint32_t    total_run_hours;    /* Cumulative hours */
} diag_uptime_t;

/**
 * Temperature and Power Status
 */
typedef struct __attribute__((packed)) {
    int16_t     fpga_temp_c;        /* FPGA temperature (0.1°C units) */
    int16_t     board_temp_c;       /* Board temperature */
    uint16_t    vcc_int_mv;         /* VCCINT voltage (mV) */
    uint16_t    vcc_aux_mv;         /* VCCAUX voltage (mV) */
    uint16_t    vcc_bram_mv;        /* VCCBRAM voltage (mV) */
    uint16_t    v5_rail_mv;         /* 5V rail */
    uint16_t    v3v3_rail_mv;       /* 3.3V rail */
    uint16_t    v12_rail_mv;        /* 12V rail (drive power) */
    uint16_t    current_ma;         /* Total current draw */
    uint8_t     fan_speed_pct;      /* Fan speed percentage */
    uint8_t     thermal_throttle;   /* Thermal throttling active */
} diag_power_status_t;

/*---------------------------------------------------------------------------
 * Data Structures - Performance Counters
 *---------------------------------------------------------------------------*/

/**
 * Performance Counters
 */
typedef struct __attribute__((packed)) {
    /* USB Statistics */
    uint64_t    usb_bytes_rx;       /* Total bytes received */
    uint64_t    usb_bytes_tx;       /* Total bytes transmitted */
    uint32_t    usb_packets_rx;     /* Packets received */
    uint32_t    usb_packets_tx;     /* Packets transmitted */
    uint32_t    usb_errors;         /* USB errors */
    uint32_t    usb_retries;        /* USB retries */

    /* DMA Statistics */
    uint64_t    dma_bytes_total;    /* Total DMA bytes */
    uint32_t    dma_transfers;      /* DMA transfer count */
    uint32_t    dma_errors;         /* DMA errors */

    /* Disk Operations */
    uint32_t    sectors_read;       /* Total sectors read */
    uint32_t    sectors_written;    /* Total sectors written */
    uint32_t    seeks_total;        /* Total seek operations */
    uint32_t    seek_errors;        /* Failed seeks */
    uint32_t    read_errors;        /* Read errors */
    uint32_t    write_errors;       /* Write errors */
    uint32_t    crc_errors;         /* CRC/checksum errors */

    /* Timing */
    uint32_t    max_latency_us;     /* Maximum latency */
    uint32_t    avg_latency_us;     /* Average latency */
    uint32_t    min_latency_us;     /* Minimum latency */
} diag_perf_counters_t;

/**
 * FIFO Statistics
 */
typedef struct __attribute__((packed)) {
    uint16_t    rx_fifo_hwm;        /* RX FIFO high water mark */
    uint16_t    tx_fifo_hwm;        /* TX FIFO high water mark */
    uint16_t    flux_fifo_hwm;      /* Flux FIFO high water mark */
    uint16_t    sector_fifo_hwm;    /* Sector buffer high water mark */
    uint32_t    rx_fifo_overflows;  /* RX overflow count */
    uint32_t    tx_fifo_underruns;  /* TX underrun count */
    uint32_t    flux_fifo_overflows;/* Flux overflow count */
} diag_fifo_stats_t;

/*---------------------------------------------------------------------------
 * Data Structures - Signal Analysis
 *---------------------------------------------------------------------------*/

/**
 * Comprehensive Signal Statistics
 */
typedef struct __attribute__((packed)) {
    /* Amplitude */
    uint16_t    amplitude_min_mv;   /* Minimum amplitude */
    uint16_t    amplitude_max_mv;   /* Maximum amplitude */
    uint16_t    amplitude_avg_mv;   /* Average amplitude */
    uint16_t    amplitude_stddev;   /* Standard deviation */

    /* Noise */
    uint16_t    noise_floor_mv;     /* Noise floor */
    uint16_t    snr_db;             /* Signal-to-noise ratio (0.1 dB) */

    /* Timing */
    uint16_t    bit_cell_ns;        /* Nominal bit cell time */
    uint16_t    jitter_peak_ns;     /* Peak-to-peak jitter */
    uint16_t    jitter_rms_ns;      /* RMS jitter */

    /* Quality Metrics */
    uint8_t     quality_score;      /* Overall quality 0-100 */
    uint8_t     weak_bit_count;     /* Weak bits detected */
    uint16_t    bit_error_rate;     /* BER (parts per million) */

    /* Samples */
    uint32_t    total_transitions;  /* Total flux transitions */
    uint32_t    valid_bits;         /* Valid decoded bits */
    uint32_t    sync_losses;        /* Sync loss count */
} diag_signal_stats_t;

/**
 * Histogram Data (64 bins)
 */
#define DIAG_HISTOGRAM_BINS     64

typedef struct __attribute__((packed)) {
    uint32_t    bin_min;            /* Minimum value for bin 0 */
    uint32_t    bin_max;            /* Maximum value for last bin */
    uint32_t    bin_width;          /* Width of each bin */
    uint32_t    total_samples;      /* Total samples in histogram */
    uint32_t    underflow;          /* Samples below min */
    uint32_t    overflow;           /* Samples above max */
    uint32_t    bins[DIAG_HISTOGRAM_BINS];  /* Bin counts */
} diag_histogram_t;

/**
 * Jitter Analysis
 */
typedef struct __attribute__((packed)) {
    uint16_t    jitter_pp_ns;       /* Peak-to-peak jitter */
    uint16_t    jitter_rms_ns;      /* RMS jitter */
    int16_t     jitter_mean_ns;     /* Mean deviation from nominal */
    uint16_t    jitter_1sigma_ns;   /* 1-sigma jitter */
    uint16_t    jitter_3sigma_ns;   /* 3-sigma jitter */
    uint32_t    outlier_count;      /* Samples beyond 3-sigma */
    uint32_t    sample_count;       /* Total samples analyzed */
} diag_jitter_stats_t;

/**
 * Bit Timing Statistics
 */
typedef struct __attribute__((packed)) {
    uint16_t    nominal_ns;         /* Nominal bit cell time */
    uint16_t    measured_avg_ns;    /* Measured average */
    uint16_t    measured_min_ns;    /* Minimum observed */
    uint16_t    measured_max_ns;    /* Maximum observed */
    uint16_t    clock_variation_ppm;/* Clock variation in PPM */
    uint16_t    reserved;
    uint32_t    short_bits;         /* Bits shorter than nominal */
    uint32_t    long_bits;          /* Bits longer than nominal */
    uint32_t    missing_clocks;     /* Missing clock events */
    uint32_t    extra_clocks;       /* Extra clock events */
} diag_bit_timing_t;

/*---------------------------------------------------------------------------
 * Data Structures - PLL/Clock
 *---------------------------------------------------------------------------*/

/**
 * Detailed PLL Status
 */
typedef struct __attribute__((packed)) {
    /* Lock Status */
    uint8_t     locked;             /* Currently locked */
    uint8_t     lock_quality;       /* Lock quality 0-100 */
    uint16_t    lock_time_us;       /* Time to acquire lock */

    /* Frequency */
    uint32_t    target_freq_hz;     /* Target frequency */
    uint32_t    actual_freq_hz;     /* Measured frequency */
    int32_t     freq_error_ppm;     /* Frequency error in PPM */

    /* Phase */
    int16_t     phase_error_deg;    /* Phase error (0.1 degree) */
    uint16_t    phase_margin_deg;   /* Phase margin */

    /* Loop Filter */
    uint16_t    loop_bandwidth_hz;  /* Loop bandwidth */
    uint16_t    damping_factor;     /* Damping factor (x100) */

    /* Statistics */
    uint32_t    lock_count;         /* Lock acquisitions */
    uint32_t    unlock_count;       /* Lock losses */
    uint32_t    total_locked_ms;    /* Total time locked */
    uint32_t    longest_lock_ms;    /* Longest lock duration */
} diag_pll_detailed_t;

/**
 * RPM Statistics
 */
typedef struct __attribute__((packed)) {
    uint16_t    target_rpm;         /* Target RPM */
    uint16_t    measured_rpm;       /* Measured RPM */
    uint16_t    rpm_min;            /* Minimum observed */
    uint16_t    rpm_max;            /* Maximum observed */
    uint16_t    rpm_stddev;         /* Standard deviation */
    uint16_t    rpm_variation_pct;  /* Variation percentage (x10) */
    uint32_t    index_period_ns;    /* Index pulse period */
    uint32_t    index_jitter_ns;    /* Index timing jitter */
} diag_rpm_stats_t;

/**
 * Index Pulse Timing
 */
typedef struct __attribute__((packed)) {
    uint32_t    period_ns;          /* Period between pulses */
    uint32_t    pulse_width_ns;     /* Index pulse width */
    uint32_t    min_period_ns;      /* Minimum period seen */
    uint32_t    max_period_ns;      /* Maximum period seen */
    uint32_t    period_stddev_ns;   /* Period standard deviation */
    uint32_t    pulse_count;        /* Total pulses counted */
    uint32_t    missing_count;      /* Missing pulses detected */
} diag_index_timing_t;

/*---------------------------------------------------------------------------
 * Data Structures - Drive Characterization
 *---------------------------------------------------------------------------*/

/**
 * Drive Timing Profile
 */
typedef struct __attribute__((packed)) {
    uint16_t    step_pulse_us;      /* Step pulse width */
    uint16_t    step_rate_us;       /* Time between steps */
    uint16_t    settle_time_ms;     /* Head settle time */
    uint16_t    motor_on_delay_ms;  /* Motor spin-up time */
    uint16_t    motor_off_delay_ms; /* Motor spin-down time */
    uint16_t    head_load_us;       /* Head load time */
    uint16_t    head_unload_us;     /* Head unload time */
    uint16_t    write_gate_delay_us;/* Write gate delay */
    uint16_t    track0_seek_ms;     /* Time to seek to track 0 */
    uint16_t    full_seek_ms;       /* Full stroke seek time */
} diag_drive_timing_t;

/**
 * Head Profile
 */
typedef struct __attribute__((packed)) {
    uint8_t     head_count;         /* Number of heads */
    uint8_t     current_head;       /* Currently selected head */
    uint16_t    head_switch_us;     /* Head switch time */
    uint16_t    head_settle_us;     /* Head settle after switch */
    int8_t      head0_offset_ns;    /* Head 0 timing offset */
    int8_t      head1_offset_ns;    /* Head 1 timing offset */
    uint16_t    head_skew_us;       /* Head-to-head skew */
} diag_head_profile_t;

/**
 * Track Eccentricity Analysis
 */
typedef struct __attribute__((packed)) {
    uint8_t     track;              /* Track number analyzed */
    uint8_t     head;               /* Head used */
    uint16_t    eccentricity_pct;   /* Eccentricity percentage (x100) */
    int16_t     offset_min_ns;      /* Minimum timing offset */
    int16_t     offset_max_ns;      /* Maximum timing offset */
    uint16_t    variation_ns;       /* Peak-to-peak variation */
    uint32_t    samples;            /* Samples analyzed */
} diag_eccentricity_t;

/*---------------------------------------------------------------------------
 * Data Structures - Debug/Trace
 *---------------------------------------------------------------------------*/

/**
 * Trace Configuration
 */
typedef struct __attribute__((packed)) {
    uint32_t    trace_mask;         /* Which events to trace */
    uint32_t    trigger_mask;       /* Trigger conditions */
    uint32_t    trigger_value;      /* Trigger value to match */
    uint16_t    pre_trigger_depth;  /* Pre-trigger samples */
    uint16_t    post_trigger_depth; /* Post-trigger samples */
    uint8_t     trigger_mode;       /* 0=immediate, 1=edge, 2=pattern */
    uint8_t     enabled;            /* Trace enabled */
    uint16_t    reserved;
} diag_trace_config_t;

/* Trace mask bits */
#define TRACE_MASK_USB_RX       (1 << 0)
#define TRACE_MASK_USB_TX       (1 << 1)
#define TRACE_MASK_DMA          (1 << 2)
#define TRACE_MASK_IRQ          (1 << 3)
#define TRACE_MASK_FDD_CMD      (1 << 4)
#define TRACE_MASK_FDD_DATA     (1 << 5)
#define TRACE_MASK_HDD_CMD      (1 << 6)
#define TRACE_MASK_HDD_DATA     (1 << 7)
#define TRACE_MASK_FLUX         (1 << 8)
#define TRACE_MASK_PLL          (1 << 9)
#define TRACE_MASK_STATE        (1 << 10)
#define TRACE_MASK_ERROR        (1 << 11)

/**
 * Trace Entry
 */
typedef struct __attribute__((packed)) {
    uint32_t    timestamp;          /* Timestamp (clock cycles) */
    uint8_t     event_type;         /* Event type */
    uint8_t     flags;              /* Event flags */
    uint16_t    data_len;           /* Data length following */
    uint32_t    data[4];            /* Event-specific data */
} diag_trace_entry_t;

/**
 * State Machine Status
 */
typedef struct __attribute__((packed)) {
    uint8_t     usb_state;          /* USB state machine */
    uint8_t     msc_state;          /* MSC protocol state */
    uint8_t     scsi_state;         /* SCSI engine state */
    uint8_t     raw_state;          /* Raw mode state */
    uint8_t     fdd_state;          /* FDD controller state */
    uint8_t     hdd_state;          /* HDD controller state */
    uint8_t     pll_state;          /* PLL state */
    uint8_t     capture_state;      /* Capture state */
    uint32_t    flags;              /* Status flags */
} diag_state_machine_t;

/*---------------------------------------------------------------------------
 * Data Structures - Error Log
 *---------------------------------------------------------------------------*/

/**
 * Error Log Entry
 */
typedef struct __attribute__((packed)) {
    uint32_t    timestamp;          /* Uptime when error occurred */
    uint16_t    error_code;         /* Error code */
    uint8_t     severity;           /* 0=info, 1=warn, 2=error, 3=fatal */
    uint8_t     source;             /* Error source module */
    uint32_t    context[2];         /* Context-specific data */
} diag_error_entry_t;

#define DIAG_ERROR_LOG_SIZE     32  /* Number of entries in error log */

/* Error severity levels */
#define DIAG_SEV_INFO           0
#define DIAG_SEV_WARNING        1
#define DIAG_SEV_ERROR          2
#define DIAG_SEV_FATAL          3

/* Error source modules */
#define DIAG_SRC_USB            0
#define DIAG_SRC_MSC            1
#define DIAG_SRC_SCSI           2
#define DIAG_SRC_RAW            3
#define DIAG_SRC_FDD            4
#define DIAG_SRC_HDD            5
#define DIAG_SRC_DMA            6
#define DIAG_SRC_PLL            7
#define DIAG_SRC_CAPTURE        8
#define DIAG_SRC_SYSTEM         9

/*---------------------------------------------------------------------------
 * Data Structures - Self Test
 *---------------------------------------------------------------------------*/

/**
 * Self Test Results
 */
typedef struct __attribute__((packed)) {
    uint32_t    test_mask;          /* Tests performed */
    uint32_t    pass_mask;          /* Tests passed */
    uint32_t    fail_mask;          /* Tests failed */
    uint32_t    skip_mask;          /* Tests skipped */
    uint32_t    duration_ms;        /* Total test duration */
    uint8_t     overall_result;     /* 0=pass, 1=warn, 2=fail */
    uint8_t     reserved[3];
} diag_self_test_result_t;

/* Self test bit definitions */
#define SELFTEST_RAM            (1 << 0)
#define SELFTEST_FLASH          (1 << 1)
#define SELFTEST_USB            (1 << 2)
#define SELFTEST_DMA            (1 << 3)
#define SELFTEST_FDD_CTRL       (1 << 4)
#define SELFTEST_HDD_CTRL       (1 << 5)
#define SELFTEST_PLL            (1 << 6)
#define SELFTEST_ADC            (1 << 7)
#define SELFTEST_EEPROM         (1 << 8)
#define SELFTEST_LOOPBACK       (1 << 9)

/*---------------------------------------------------------------------------
 * Waveform Capture
 *---------------------------------------------------------------------------*/

/**
 * Waveform Capture Configuration
 */
typedef struct __attribute__((packed)) {
    uint32_t    sample_rate_hz;     /* ADC sample rate */
    uint16_t    sample_count;       /* Number of samples to capture */
    uint8_t     trigger_source;     /* 0=manual, 1=index, 2=flux */
    uint8_t     trigger_edge;       /* 0=rising, 1=falling */
    int16_t     trigger_level;      /* Trigger threshold */
    uint16_t    pre_trigger;        /* Pre-trigger samples */
} diag_waveform_config_t;

/**
 * Waveform Data Header
 */
typedef struct __attribute__((packed)) {
    uint32_t    sample_rate_hz;     /* Actual sample rate */
    uint16_t    sample_count;       /* Samples following */
    uint16_t    bits_per_sample;    /* 8, 10, 12, or 16 */
    int16_t     offset_mv;          /* DC offset */
    uint16_t    scale_uv;           /* Microvolts per LSB */
    uint32_t    trigger_pos;        /* Trigger position in buffer */
} diag_waveform_header_t;

#endif /* DIAGNOSTICS_PROTOCOL_H */
