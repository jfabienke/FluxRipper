/**
 * FluxRipper Debug HAL
 *
 * Hardware abstraction for the unified debug subsystem.
 * Provides high-level access to all debug features via the
 * debug register bank.
 *
 * Created: 2025-12-07 15:25
 * License: BSD-3-Clause
 */

#ifndef DEBUG_HAL_H
#define DEBUG_HAL_H

#include <stdint.h>
#include <stdbool.h>

/*============================================================================
 * Debug Register Base Address
 *============================================================================*/

#define DEBUG_BASE_ADDR     0x44A80000

/*============================================================================
 * Return Codes
 *============================================================================*/

#define DBG_OK              0
#define DBG_ERR_TIMEOUT     -1
#define DBG_ERR_BUS         -2
#define DBG_ERR_INVALID     -3
#define DBG_ERR_NOT_READY   -4

/*============================================================================
 * Bring-up Layer Definitions
 *============================================================================*/

typedef enum {
    LAYER_RESET = 0,        /* Reset complete, nothing verified */
    LAYER_JTAG,             /* JTAG IDCODE readable */
    LAYER_MEMORY,           /* Memory read/write works */
    LAYER_GPIO,             /* GPIO accessible */
    LAYER_CLOCKS,           /* PLLs locked */
    LAYER_USB_PHY,          /* ULPI communication works */
    LAYER_USB_ENUM,         /* USB enumeration complete */
    LAYER_CDC_CONSOLE,      /* CDC console active */
    LAYER_FULL_SYSTEM       /* All features operational */
} debug_layer_t;

/*============================================================================
 * Signal Tap Probe Groups
 *============================================================================*/

typedef enum {
    PROBE_GROUP_USB = 0,    /* USB signals */
    PROBE_GROUP_FDC,        /* FDC signals */
    PROBE_GROUP_HDD,        /* HDD signals */
    PROBE_GROUP_SYSTEM      /* System signals */
} probe_group_t;

/*============================================================================
 * Trace Event Types
 *============================================================================*/

typedef enum {
    TRACE_IDLE = 0x00,
    TRACE_STATE_CHANGE = 0x01,
    TRACE_REG_WRITE = 0x02,
    TRACE_REG_READ = 0x03,
    TRACE_INTERRUPT = 0x04,
    TRACE_ERROR = 0x05,
    TRACE_USB_PACKET = 0x06,
    TRACE_FDC_CMD = 0x07,
    TRACE_HDD_CMD = 0x08,
    TRACE_MEM_ACCESS = 0x09,
    TRACE_DMA = 0x0A,
    TRACE_PLL = 0x0B,
    TRACE_POWER = 0x0C,
    TRACE_USER1 = 0x0D,
    TRACE_USER2 = 0x0E,
    TRACE_TRIGGER = 0x0F
} trace_event_t;

/*============================================================================
 * Trace Event Sources
 *============================================================================*/

typedef enum {
    SOURCE_SYSTEM = 0x00,
    SOURCE_USB = 0x01,
    SOURCE_FDC0 = 0x02,
    SOURCE_FDC1 = 0x03,
    SOURCE_HDD0 = 0x04,
    SOURCE_HDD1 = 0x05,
    SOURCE_POWER = 0x06,
    SOURCE_CLOCK = 0x07,
    SOURCE_CPU = 0x08,
    SOURCE_DEBUG = 0x09
} trace_source_t;

/*============================================================================
 * Status Structures
 *============================================================================*/

typedef struct {
    debug_layer_t   layer;
    bool            cpu_halted;
    bool            cpu_running;
    bool            trace_triggered;
    bool            trace_wrapped;
    uint32_t        uptime_seconds;
    uint32_t        error_code;
} debug_status_t;

typedef struct {
    uint8_t         num_probe_groups;
    uint8_t         probe_width;
    uint8_t         trace_depth_log2;
    uint8_t         trace_width;
    uint8_t         num_breakpoints;
    uint8_t         mem_addr_width;
    uint8_t         features;
    uint8_t         version;
} debug_caps_t;

typedef struct {
    uint16_t        timestamp;      /* 16-bit relative timestamp */
    trace_event_t   event_type;
    trace_source_t  source;
    uint32_t        data;
} trace_entry_t;

/*============================================================================
 * Initialization
 *============================================================================*/

/**
 * Initialize debug subsystem
 * @return DBG_OK on success
 */
int dbg_init(void);

/**
 * Get debug subsystem capabilities
 * @param caps Output structure
 */
void dbg_get_caps(debug_caps_t *caps);

/**
 * Get current system status
 * @param status Output structure
 */
void dbg_get_status(debug_status_t *status);

/**
 * Get current bring-up layer
 * @return Current layer number
 */
debug_layer_t dbg_get_layer(void);

/*============================================================================
 * Memory Access (via debug port)
 *============================================================================*/

/**
 * Read 32-bit word from address
 * @param addr Memory address
 * @param data Output data
 * @return DBG_OK on success, error code on failure
 */
int dbg_mem_read(uint32_t addr, uint32_t *data);

/**
 * Write 32-bit word to address
 * @param addr Memory address
 * @param data Data to write
 * @return DBG_OK on success
 */
int dbg_mem_write(uint32_t addr, uint32_t data);

/**
 * Read multiple words
 * @param addr Start address
 * @param buf Output buffer
 * @param count Number of words
 * @return Number of words read, or negative error code
 */
int dbg_mem_read_block(uint32_t addr, uint32_t *buf, uint32_t count);

/**
 * Write multiple words
 * @param addr Start address
 * @param buf Data buffer
 * @param count Number of words
 * @return Number of words written, or negative error code
 */
int dbg_mem_write_block(uint32_t addr, const uint32_t *buf, uint32_t count);

/**
 * Fill memory with pattern
 * @param addr Start address
 * @param pattern Pattern to fill
 * @param count Number of words
 * @return DBG_OK on success
 */
int dbg_mem_fill(uint32_t addr, uint32_t pattern, uint32_t count);

/**
 * Test memory (write/read/verify)
 * @param addr Start address
 * @param count Number of words
 * @return DBG_OK if all tests pass
 */
int dbg_mem_test(uint32_t addr, uint32_t count);

/*============================================================================
 * Signal Tap
 *============================================================================*/

/**
 * Select probe group
 * @param group Probe group to select
 */
void dbg_probe_select(probe_group_t group);

/**
 * Read current probe values
 * @return 32-bit probe values for selected group
 */
uint32_t dbg_probe_read(void);

/**
 * Read all probe groups
 * @param values Output array (4 elements)
 */
void dbg_probe_read_all(uint32_t values[4]);

/**
 * Set trigger condition
 * @param mask Bits to compare (1 = compare, 0 = ignore)
 * @param value Value to match
 */
void dbg_probe_set_trigger(uint32_t mask, uint32_t value);

/**
 * Wait for trigger condition
 * @param timeout_ms Timeout in milliseconds
 * @return true if triggered, false if timeout
 */
bool dbg_probe_wait_trigger(uint32_t timeout_ms);

/*============================================================================
 * Trace Buffer
 *============================================================================*/

/**
 * Start trace capture
 */
void dbg_trace_start(void);

/**
 * Stop trace capture
 */
void dbg_trace_stop(void);

/**
 * Clear trace buffer
 */
void dbg_trace_clear(void);

/**
 * Get trace status
 * @param count Output: number of entries captured
 * @param triggered Output: true if trigger occurred
 * @param wrapped Output: true if buffer wrapped
 */
void dbg_trace_status(uint32_t *count, bool *triggered, bool *wrapped);

/**
 * Read trace entry
 * @param index Entry index (0 = oldest)
 * @param entry Output structure
 * @return DBG_OK on success
 */
int dbg_trace_read(uint32_t index, trace_entry_t *entry);

/**
 * Set trace trigger filter
 * @param type_mask Event types to trigger on (bitmask)
 * @param source_mask Sources to trigger on (bitmask)
 */
void dbg_trace_set_trigger(uint8_t type_mask, uint8_t source_mask);

/**
 * Add manual trace entry
 * @param type Event type
 * @param source Event source
 * @param data Event data
 */
void dbg_trace_log(trace_event_t type, trace_source_t source, uint32_t data);

/*============================================================================
 * CPU Debug (VexRiscv)
 *============================================================================*/

/**
 * Halt CPU
 * @return DBG_OK on success
 */
int dbg_cpu_halt(void);

/**
 * Resume CPU execution
 * @return DBG_OK on success
 */
int dbg_cpu_run(void);

/**
 * Single-step CPU
 * @return DBG_OK on success
 */
int dbg_cpu_step(void);

/**
 * Reset CPU (keeps FPGA running)
 * @return DBG_OK on success
 */
int dbg_cpu_reset(void);

/**
 * Check if CPU is halted
 * @return true if halted
 */
bool dbg_cpu_is_halted(void);

/**
 * Read CPU program counter
 * @return Current PC value
 */
uint32_t dbg_cpu_get_pc(void);

/**
 * Read CPU register
 * @param reg Register number (0-31)
 * @return Register value
 */
uint32_t dbg_cpu_get_reg(uint8_t reg);

/**
 * Set breakpoint
 * @param addr Breakpoint address
 * @return DBG_OK on success
 */
int dbg_cpu_set_bp(uint32_t addr);

/**
 * Clear breakpoint
 * @return DBG_OK on success
 */
int dbg_cpu_clear_bp(void);

/*============================================================================
 * JTAG Interface
 *============================================================================*/

/**
 * Check if JTAG probe is connected
 * @return true if connected
 */
bool dbg_jtag_connected(void);

/**
 * Read JTAG IDCODE
 * @return 32-bit IDCODE
 */
uint32_t dbg_jtag_idcode(void);

/*============================================================================
 * Utility Functions
 *============================================================================*/

/**
 * Format memory dump (hex + ASCII)
 * @param addr Start address
 * @param len Length in bytes
 * @param output_fn Callback for each line
 */
void dbg_hexdump(uint32_t addr, uint32_t len,
                 void (*output_fn)(const char *line));

/**
 * Parse hex string to uint32
 * @param str Input string (no 0x prefix needed)
 * @param value Output value
 * @return true on success
 */
bool dbg_parse_hex(const char *str, uint32_t *value);

/**
 * Format uint32 as hex string
 * @param value Input value
 * @param buf Output buffer (9+ bytes)
 */
void dbg_format_hex(uint32_t value, char *buf);

/**
 * Layer name string
 * @param layer Layer number
 * @return String name
 */
const char* dbg_layer_name(debug_layer_t layer);

/**
 * Event type name string
 * @param type Event type
 * @return String name
 */
const char* dbg_event_name(trace_event_t type);

/**
 * Source name string
 * @param source Event source
 * @return String name
 */
const char* dbg_source_name(trace_source_t source);

#endif /* DEBUG_HAL_H */
