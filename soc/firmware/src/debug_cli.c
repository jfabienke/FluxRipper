/**
 * FluxRipper Debug CLI Commands
 *
 * Command-line interface for the unified debug subsystem.
 * Provides comprehensive access to all debug features for bring-up
 * and development.
 *
 * Created: 2025-12-07 15:30
 * License: BSD-3-Clause
 */

#include "cli.h"
#include "debug_hal.h"
#include "uart.h"
#include <string.h>
#include <stdlib.h>

/*============================================================================
 * Memory Commands
 *============================================================================*/

static int cmd_dbg_read(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: dbg r <addr> [count]\n");
        uart_puts("  Read 32-bit word(s) from address\n");
        return -1;
    }

    uint32_t addr;
    if (!dbg_parse_hex(argv[1], &addr)) {
        uart_puts("Invalid address\n");
        return -1;
    }

    uint32_t count = 1;
    if (argc >= 3) {
        count = strtoul(argv[2], NULL, 0);
        if (count == 0) count = 1;
        if (count > 256) count = 256;
    }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t data;
        int ret = dbg_mem_read(addr + i * 4, &data);
        if (ret != DBG_OK) {
            uart_printf("%08lX: ERR(%d)\n", addr + i * 4, ret);
        } else {
            uart_printf("%08lX: %08lX\n", addr + i * 4, data);
        }
    }

    return 0;
}

static int cmd_dbg_write(int argc, char *argv[])
{
    if (argc < 3) {
        uart_puts("Usage: dbg w <addr> <data>\n");
        uart_puts("  Write 32-bit word to address\n");
        return -1;
    }

    uint32_t addr, data;
    if (!dbg_parse_hex(argv[1], &addr)) {
        uart_puts("Invalid address\n");
        return -1;
    }
    if (!dbg_parse_hex(argv[2], &data)) {
        uart_puts("Invalid data\n");
        return -1;
    }

    int ret = dbg_mem_write(addr, data);
    if (ret == DBG_OK) {
        uart_printf("%08lX <- %08lX OK\n", addr, data);
    } else {
        uart_printf("Write failed: %d\n", ret);
    }

    return ret;
}

static int cmd_dbg_dump(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: dbg dump <addr> [len]\n");
        uart_puts("  Hex dump of memory region (len in bytes, default 64)\n");
        return -1;
    }

    uint32_t addr;
    if (!dbg_parse_hex(argv[1], &addr)) {
        uart_puts("Invalid address\n");
        return -1;
    }

    uint32_t len = 64;
    if (argc >= 3) {
        len = strtoul(argv[2], NULL, 0);
        if (len == 0) len = 64;
        if (len > 1024) len = 1024;
    }

    dbg_hexdump(addr, len, uart_puts);

    return 0;
}

static int cmd_dbg_fill(int argc, char *argv[])
{
    if (argc < 4) {
        uart_puts("Usage: dbg fill <addr> <len> <pattern>\n");
        return -1;
    }

    uint32_t addr, len, pattern;
    if (!dbg_parse_hex(argv[1], &addr) ||
        !dbg_parse_hex(argv[2], &len) ||
        !dbg_parse_hex(argv[3], &pattern)) {
        uart_puts("Invalid argument\n");
        return -1;
    }

    int ret = dbg_mem_fill(addr, pattern, len / 4);
    uart_printf("Filled %lu words with %08lX: %s\n",
        len / 4, pattern, ret == DBG_OK ? "OK" : "FAIL");

    return ret;
}

static int cmd_dbg_test(int argc, char *argv[])
{
    if (argc < 3) {
        uart_puts("Usage: dbg test <addr> <len>\n");
        uart_puts("  Memory test (write/read/verify)\n");
        return -1;
    }

    uint32_t addr, len;
    if (!dbg_parse_hex(argv[1], &addr) ||
        !dbg_parse_hex(argv[2], &len)) {
        uart_puts("Invalid argument\n");
        return -1;
    }

    uart_printf("Testing %08lX - %08lX...\n", addr, addr + len);
    int ret = dbg_mem_test(addr, len / 4);
    uart_printf("Result: %s\n", ret == DBG_OK ? "PASS" : "FAIL");

    return ret;
}

/*============================================================================
 * Signal Tap Commands
 *============================================================================*/

static int cmd_dbg_probe(int argc, char *argv[])
{
    probe_group_t group = PROBE_GROUP_USB;

    if (argc >= 2) {
        int g = atoi(argv[1]);
        if (g >= 0 && g <= 3) {
            group = (probe_group_t)g;
        }
    }

    const char *group_names[] = {"USB", "FDC", "HDD", "SYS"};
    dbg_probe_select(group);
    uint32_t val = dbg_probe_read();

    uart_printf("Probe Group %d (%s): %08lX\n", group, group_names[group], val);

    /* Decode group-specific bits */
    switch (group) {
        case PROBE_GROUP_USB:
            uart_printf("  ULPI State:  %lu\n", (val >> 0) & 0xF);
            uart_printf("  USB State:   %lu\n", (val >> 4) & 0xF);
            uart_printf("  EP0 State:   %lu\n", (val >> 8) & 0xF);
            uart_printf("  Packet PID:  %lu\n", (val >> 20) & 0xF);
            uart_printf("  SOF=%lu SETUP=%lu IN=%lu OUT=%lu\n",
                (val >> 24) & 1, (val >> 25) & 1,
                (val >> 26) & 1, (val >> 27) & 1);
            uart_printf("  ACK=%lu NAK=%lu STALL=%lu ERR=%lu\n",
                (val >> 28) & 1, (val >> 29) & 1,
                (val >> 30) & 1, (val >> 31) & 1);
            break;

        case PROBE_GROUP_FDC:
            uart_printf("  Command:     %lu\n", (val >> 0) & 0xF);
            uart_printf("  State:       %lu\n", (val >> 4) & 0xF);
            uart_printf("  Track:       %lu\n", (val >> 8) & 0xFF);
            uart_printf("  Sector:      %lu\n", (val >> 16) & 0x1F);
            uart_printf("  Head=%lu Motor=%lu Busy=%lu\n",
                (val >> 21) & 1, (val >> 22) & 1, (val >> 23) & 1);
            uart_printf("  Index=%lu TRK0=%lu WP=%lu RDY=%lu\n",
                (val >> 24) & 1, (val >> 25) & 1,
                (val >> 26) & 1, (val >> 27) & 1);
            break;

        case PROBE_GROUP_HDD:
            uart_printf("  Command:     %lu\n", (val >> 0) & 0xF);
            uart_printf("  State:       %lu\n", (val >> 4) & 0xF);
            uart_printf("  Cylinder:    %lu\n", (val >> 8) & 0x3FF);
            uart_printf("  Head:        %lu\n", (val >> 18) & 0xF);
            uart_printf("  Sector:      %lu\n", (val >> 22) & 0x3F);
            uart_printf("  SeekCmp=%lu Index=%lu RDY=%lu ERR=%lu\n",
                (val >> 28) & 1, (val >> 29) & 1,
                (val >> 30) & 1, (val >> 31) & 1);
            break;

        case PROBE_GROUP_SYSTEM:
            uart_printf("  Clocks OK:   100M=%lu 60M=%lu 200M=%lu PLL=%lu\n",
                (val >> 0) & 1, (val >> 1) & 1,
                (val >> 2) & 1, (val >> 3) & 1);
            uart_printf("  RST=%lu USBconn=%lu USBcfg=%lu USBsusp=%lu\n",
                (val >> 4) & 1, (val >> 5) & 1,
                (val >> 6) & 1, (val >> 7) & 1);
            uart_printf("  Personality: %lu\n", (val >> 8) & 0xF);
            uart_printf("  Power State: %lu\n", (val >> 12) & 0xF);
            uart_printf("  Temperature: %lu\n", (val >> 16) & 0xFF);
            uart_printf("  Error Flags: %02lX\n", (val >> 24) & 0xFF);
            break;
    }

    return 0;
}

static int cmd_dbg_watch(int argc, char *argv[])
{
    probe_group_t group = PROBE_GROUP_USB;
    if (argc >= 2) {
        int g = atoi(argv[1]);
        if (g >= 0 && g <= 3) {
            group = (probe_group_t)g;
        }
    }

    uart_puts("Watching probes (press any key to stop)...\n");
    dbg_probe_select(group);

    uint32_t last_val = 0;
    while (!uart_rx_ready()) {
        uint32_t val = dbg_probe_read();
        if (val != last_val) {
            uart_printf("%08lX\n", val);
            last_val = val;
        }
    }
    uart_getc();  /* Consume the key */

    return 0;
}

/*============================================================================
 * Trace Commands
 *============================================================================*/

static int cmd_dbg_trace(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: dbg trace <cmd>\n");
        uart_puts("  start   - Start capture\n");
        uart_puts("  stop    - Stop capture\n");
        uart_puts("  clear   - Clear buffer\n");
        uart_puts("  status  - Show status\n");
        uart_puts("  dump [n]- Show last n entries\n");
        return 0;
    }

    if (strcmp(argv[1], "start") == 0) {
        dbg_trace_start();
        uart_puts("Trace started\n");
    } else if (strcmp(argv[1], "stop") == 0) {
        dbg_trace_stop();
        uart_puts("Trace stopped\n");
    } else if (strcmp(argv[1], "clear") == 0) {
        dbg_trace_clear();
        uart_puts("Trace cleared\n");
    } else if (strcmp(argv[1], "status") == 0) {
        uint32_t count;
        bool triggered, wrapped;
        dbg_trace_status(&count, &triggered, &wrapped);
        uart_printf("Entries:   %lu\n", count);
        uart_printf("Triggered: %s\n", triggered ? "YES" : "no");
        uart_printf("Wrapped:   %s\n", wrapped ? "yes" : "no");
    } else if (strcmp(argv[1], "dump") == 0) {
        uint32_t n = 20;
        if (argc >= 3) {
            n = strtoul(argv[2], NULL, 0);
            if (n == 0) n = 20;
            if (n > 100) n = 100;
        }

        uint32_t count;
        bool triggered, wrapped;
        dbg_trace_status(&count, &triggered, &wrapped);

        uart_puts("Time(us)  Type         Source      Data\n");
        uart_puts("--------  -----------  ----------  --------\n");

        uint32_t start = (count > n) ? count - n : 0;
        for (uint32_t i = start; i < count; i++) {
            trace_entry_t entry;
            if (dbg_trace_read(i, &entry) == DBG_OK) {
                uart_printf("%8u  %-11s  %-10s  %08lX\n",
                    entry.timestamp,
                    dbg_event_name(entry.event_type),
                    dbg_source_name(entry.source),
                    entry.data);
            }
        }
    }

    return 0;
}

/*============================================================================
 * CPU Commands
 *============================================================================*/

static int cmd_dbg_cpu(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: dbg cpu <cmd>\n");
        uart_puts("  halt    - Halt CPU\n");
        uart_puts("  run     - Resume execution\n");
        uart_puts("  step    - Single step\n");
        uart_puts("  reset   - Reset CPU\n");
        uart_puts("  status  - Show CPU state\n");
        uart_puts("  reg [n] - Show register(s)\n");
        uart_puts("  bp <addr> - Set breakpoint\n");
        uart_puts("  bp clear  - Clear breakpoint\n");
        return 0;
    }

    if (strcmp(argv[1], "halt") == 0) {
        dbg_cpu_halt();
        uart_printf("CPU halted at PC=%08lX\n", dbg_cpu_get_pc());
    } else if (strcmp(argv[1], "run") == 0 || strcmp(argv[1], "go") == 0) {
        dbg_cpu_run();
        uart_puts("CPU running\n");
    } else if (strcmp(argv[1], "step") == 0) {
        dbg_cpu_step();
        uart_printf("Stepped to PC=%08lX\n", dbg_cpu_get_pc());
    } else if (strcmp(argv[1], "reset") == 0) {
        dbg_cpu_reset();
        uart_puts("CPU reset\n");
    } else if (strcmp(argv[1], "status") == 0) {
        uart_printf("Halted:  %s\n", dbg_cpu_is_halted() ? "YES" : "no");
        uart_printf("PC:      %08lX\n", dbg_cpu_get_pc());
    } else if (strcmp(argv[1], "reg") == 0) {
        if (argc >= 3) {
            int r = atoi(argv[2]);
            if (r >= 0 && r < 32) {
                uart_printf("x%d = %08lX\n", r, dbg_cpu_get_reg(r));
            }
        } else {
            /* Show all registers */
            for (int i = 0; i < 32; i += 4) {
                uart_printf("x%2d=%08lX x%2d=%08lX x%2d=%08lX x%2d=%08lX\n",
                    i, dbg_cpu_get_reg(i),
                    i+1, dbg_cpu_get_reg(i+1),
                    i+2, dbg_cpu_get_reg(i+2),
                    i+3, dbg_cpu_get_reg(i+3));
            }
        }
    } else if (strcmp(argv[1], "bp") == 0) {
        if (argc >= 3) {
            if (strcmp(argv[2], "clear") == 0) {
                dbg_cpu_clear_bp();
                uart_puts("Breakpoint cleared\n");
            } else {
                uint32_t addr;
                if (dbg_parse_hex(argv[2], &addr)) {
                    dbg_cpu_set_bp(addr);
                    uart_printf("Breakpoint set at %08lX\n", addr);
                }
            }
        }
    }

    return 0;
}

/*============================================================================
 * Status Commands
 *============================================================================*/

static int cmd_dbg_status(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    debug_status_t status;
    debug_caps_t caps;

    dbg_get_status(&status);
    dbg_get_caps(&caps);

    uart_puts("\nFluxRipper Debug Status\n");
    uart_puts("===============================================\n");

    uart_printf("Bring-up Layer:  %d (%s)\n",
        status.layer, dbg_layer_name(status.layer));
    uart_printf("Uptime:          %lu seconds\n", status.uptime_seconds);
    uart_printf("JTAG Connected:  %s\n", dbg_jtag_connected() ? "YES" : "no");
    uart_printf("IDCODE:          %08lX\n", dbg_jtag_idcode());

    uart_puts("\nCPU Status:\n");
    uart_printf("  Halted:        %s\n", status.cpu_halted ? "YES" : "no");
    uart_printf("  Running:       %s\n", status.cpu_running ? "yes" : "no");

    uart_puts("\nTrace Buffer:\n");
    uart_printf("  Triggered:     %s\n", status.trace_triggered ? "YES" : "no");
    uart_printf("  Wrapped:       %s\n", status.trace_wrapped ? "yes" : "no");

    if (status.error_code) {
        uart_printf("\nLast Error:      0x%08lX\n", status.error_code);
    }

    uart_puts("\nCapabilities:\n");
    uart_printf("  Version:       %d\n", caps.version);
    uart_printf("  Probe Groups:  %d x %d bits\n",
        caps.num_probe_groups, caps.probe_width);
    uart_printf("  Trace Depth:   %d entries x %d bits\n",
        1 << caps.trace_depth_log2, caps.trace_width);
    uart_printf("  Breakpoints:   %d\n", caps.num_breakpoints);
    uart_puts("===============================================\n");

    return 0;
}

static int cmd_dbg_layer(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    debug_layer_t layer = dbg_get_layer();

    uart_puts("\nBring-up Layer Status\n");
    uart_puts("-----------------------------------------\n");

    const char *layers[] = {
        "Reset complete",
        "JTAG IDCODE readable",
        "Memory access works",
        "GPIO accessible",
        "PLLs locked",
        "USB PHY responding",
        "USB enumeration complete",
        "CDC console active",
        "Full system operational"
    };

    for (int i = 0; i <= LAYER_FULL_SYSTEM; i++) {
        uart_printf("  [%c] Layer %d: %s\n",
            (i <= layer) ? 'X' : ' ',
            i, layers[i]);
    }

    uart_puts("-----------------------------------------\n");
    uart_printf("Current: Layer %d - %s\n", layer, dbg_layer_name(layer));

    return 0;
}

/*============================================================================
 * Main Debug Command Dispatcher
 *============================================================================*/

int cmd_dbg(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Debug Commands:\n");
        uart_puts("  Memory:\n");
        uart_puts("    dbg r <addr> [n]     - Read word(s)\n");
        uart_puts("    dbg w <addr> <data>  - Write word\n");
        uart_puts("    dbg dump <addr> [len]- Hex dump\n");
        uart_puts("    dbg fill <a> <l> <p> - Fill memory\n");
        uart_puts("    dbg test <addr> <len>- Memory test\n");
        uart_puts("  Signal Tap:\n");
        uart_puts("    dbg probe [group]    - Read probes\n");
        uart_puts("    dbg watch [group]    - Watch probes\n");
        uart_puts("  Trace:\n");
        uart_puts("    dbg trace <cmd>      - Trace control\n");
        uart_puts("  CPU:\n");
        uart_puts("    dbg cpu <cmd>        - CPU control\n");
        uart_puts("  System:\n");
        uart_puts("    dbg status           - System status\n");
        uart_puts("    dbg layer            - Bring-up layer\n");
        uart_puts("    dbg id               - JTAG IDCODE\n");
        return 0;
    }

    /* Dispatch */
    if (strcmp(argv[1], "r") == 0) {
        return cmd_dbg_read(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "w") == 0) {
        return cmd_dbg_write(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "dump") == 0) {
        return cmd_dbg_dump(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "fill") == 0) {
        return cmd_dbg_fill(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "test") == 0) {
        return cmd_dbg_test(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "probe") == 0) {
        return cmd_dbg_probe(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "watch") == 0) {
        return cmd_dbg_watch(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "trace") == 0) {
        return cmd_dbg_trace(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "cpu") == 0) {
        return cmd_dbg_cpu(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "status") == 0) {
        return cmd_dbg_status(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "layer") == 0) {
        return cmd_dbg_layer(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "id") == 0) {
        uart_printf("IDCODE: %08lX\n", dbg_jtag_idcode());
        return 0;
    } else {
        uart_printf("Unknown debug command: %s\n", argv[1]);
        return -1;
    }
}

/*============================================================================
 * CLI Registration
 *============================================================================*/

const cli_cmd_t dbg_cli_cmd = {
    "dbg", "Debug subsystem (r/w/dump/probe/trace/cpu/status)",
    cmd_dbg
};

void debug_cli_init(void)
{
    dbg_init();
    cli_register(&dbg_cli_cmd);
}
