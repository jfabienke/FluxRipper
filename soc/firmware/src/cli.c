/**
 * FluxRipper SoC - CLI Implementation
 *
 * Command-line interface for bare-metal firmware
 *
 * Updated: 2025-12-03 18:00
 */

#include "cli.h"
#include "uart.h"
#include "timer.h"
#include "platform.h"
#include <string.h>

/*============================================================================
 * Command Table
 *============================================================================*/

#define MAX_COMMANDS    16

static cli_cmd_t cmd_table[MAX_COMMANDS];
static int num_commands = 0;

/* Built-in commands */
static const cli_cmd_t builtin_commands[] = {
    { "help",    "Show available commands",          cmd_help    },
    { "?",       "Alias for help",                   cmd_help    },
    { "echo",    "Echo arguments",                   cmd_echo    },
    { "memtest", "Test memory region",               cmd_memtest },
    { "read",    "Read memory: read <addr> [count]", cmd_read    },
    { "write",   "Write memory: write <addr> <val>", cmd_write   },
    { "info",    "Show system information",          cmd_info    },
    { "reset",   "Software reset",                   cmd_reset   },
    { NULL, NULL, NULL }
};

/*============================================================================
 * String Utilities
 *============================================================================*/

static uint32_t parse_hex(const char *s)
{
    uint32_t val = 0;

    /* Skip 0x prefix */
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        s += 2;

    while (*s) {
        char c = *s++;
        uint8_t digit;

        if (c >= '0' && c <= '9')
            digit = c - '0';
        else if (c >= 'a' && c <= 'f')
            digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            digit = c - 'A' + 10;
        else
            break;

        val = (val << 4) | digit;
    }

    return val;
}

static uint32_t parse_num(const char *s)
{
    /* Hex if starts with 0x */
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        return parse_hex(s);

    /* Otherwise decimal */
    uint32_t val = 0;
    while (*s >= '0' && *s <= '9') {
        val = val * 10 + (*s++ - '0');
    }
    return val;
}

static int tokenize(char *line, char *argv[], int max_args)
{
    int argc = 0;
    char *p = line;

    while (*p && argc < max_args) {
        /* Skip whitespace */
        while (*p == ' ' || *p == '\t')
            p++;

        if (*p == '\0')
            break;

        /* Start of token */
        argv[argc++] = p;

        /* Find end of token */
        while (*p && *p != ' ' && *p != '\t')
            p++;

        if (*p) {
            *p++ = '\0';
        }
    }

    return argc;
}

/*============================================================================
 * CLI Core
 *============================================================================*/

void cli_init(void)
{
    num_commands = 0;

    /* Register built-in commands */
    for (int i = 0; builtin_commands[i].name != NULL; i++) {
        cli_register(&builtin_commands[i]);
    }
}

int cli_register(const cli_cmd_t *cmd)
{
    if (num_commands >= MAX_COMMANDS)
        return -1;

    cmd_table[num_commands++] = *cmd;
    return 0;
}

int cli_process(char *line)
{
    char *argv[CLI_MAX_ARGS];
    int argc;

    /* Tokenize */
    argc = tokenize(line, argv, CLI_MAX_ARGS);
    if (argc == 0)
        return 0;

    /* Find command */
    for (int i = 0; i < num_commands; i++) {
        if (strcmp(argv[0], cmd_table[i].name) == 0) {
            return cmd_table[i].handler(argc, argv);
        }
    }

    uart_printf("Unknown command: %s\n", argv[0]);
    uart_puts("Type 'help' for available commands.\n");
    return -1;
}

void cli_run(void)
{
    char line[CLI_MAX_LINE];

    uart_puts("\n");
    uart_puts("========================================\n");
    uart_puts("  FluxRipper SoC - Milestone 0\n");
    uart_puts("  MicroBlaze V @ 100 MHz\n");
    uart_puts("========================================\n");
    uart_puts("Type 'help' for available commands.\n\n");

    while (1) {
        uart_puts("> ");
        uart_readline(line, sizeof(line));
        cli_process(line);
    }
}

/*============================================================================
 * Built-in Command Implementations
 *============================================================================*/

int cmd_help(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("Available commands:\n");
    for (int i = 0; i < num_commands; i++) {
        uart_printf("  %-10s %s\n", cmd_table[i].name, cmd_table[i].help);
    }
    return 0;
}

int cmd_echo(int argc, char *argv[])
{
    for (int i = 1; i < argc; i++) {
        if (i > 1)
            uart_putc(' ');
        uart_puts(argv[i]);
    }
    uart_puts("\n");
    return 0;
}

int cmd_memtest(int argc, char *argv[])
{
    uint32_t base, size;

    if (argc < 3) {
        uart_puts("Usage: memtest <base> <size>\n");
        uart_puts("Example: memtest 0x00010000 0x1000\n");
        return -1;
    }

    base = parse_num(argv[1]);
    size = parse_num(argv[2]);

    uart_printf("Testing memory: 0x%x - 0x%x (%u bytes)\n",
                base, base + size - 1, size);

    volatile uint32_t *p = (volatile uint32_t *)base;
    uint32_t words = size / 4;
    uint32_t errors = 0;

    /* Pattern test: walking ones */
    uart_puts("  Walking ones... ");
    for (uint32_t i = 0; i < words && errors < 10; i++) {
        uint32_t pattern = 1 << (i & 31);
        p[i] = pattern;
        if (p[i] != pattern) {
            if (errors == 0)
                uart_puts("FAIL\n");
            uart_printf("    [0x%x] wrote 0x%x, read 0x%x\n",
                       base + i * 4, pattern, p[i]);
            errors++;
        }
    }
    if (errors == 0)
        uart_puts("OK\n");

    /* Pattern test: address as data */
    uart_puts("  Address pattern... ");
    for (uint32_t i = 0; i < words; i++) {
        p[i] = base + i * 4;
    }
    for (uint32_t i = 0; i < words && errors < 20; i++) {
        uint32_t expected = base + i * 4;
        if (p[i] != expected) {
            if (errors == 0 || errors == 10)
                uart_puts("FAIL\n");
            uart_printf("    [0x%x] expected 0x%x, read 0x%x\n",
                       base + i * 4, expected, p[i]);
            errors++;
        }
    }
    if (errors < 10)
        uart_puts("OK\n");

    uart_printf("Memory test complete: %u errors\n", errors);
    return errors ? -1 : 0;
}

int cmd_read(int argc, char *argv[])
{
    uint32_t addr, count = 1;

    if (argc < 2) {
        uart_puts("Usage: read <addr> [count]\n");
        return -1;
    }

    addr = parse_num(argv[1]);
    if (argc >= 3)
        count = parse_num(argv[2]);

    /* Align to 4 bytes */
    addr &= ~3;

    if (count == 1) {
        uint32_t val = REG32(addr);
        uart_printf("[0x%x] = 0x%x\n", addr, val);
    } else {
        uart_hexdump((void *)addr, count);
    }

    return 0;
}

int cmd_write(int argc, char *argv[])
{
    uint32_t addr, val;

    if (argc < 3) {
        uart_puts("Usage: write <addr> <value>\n");
        return -1;
    }

    addr = parse_num(argv[1]);
    val = parse_num(argv[2]);

    /* Align to 4 bytes */
    addr &= ~3;

    uart_printf("[0x%x] <- 0x%x\n", addr, val);
    REG32(addr) = val;

    /* Read back */
    uint32_t readback = REG32(addr);
    if (readback != val) {
        uart_printf("Warning: readback = 0x%x\n", readback);
    }

    return 0;
}

int cmd_info(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("\nFluxRipper SoC Information\n");
    uart_puts("--------------------------\n");
    uart_printf("  CPU:        MicroBlaze V (RV32IMC)\n");
    uart_printf("  CPU Freq:   %u MHz\n", CPU_FREQ_HZ / 1000000);
    uart_printf("  Code BRAM:  %u KB @ 0x%x\n",
                CODE_BRAM_SIZE / 1024, CODE_BRAM_BASE);
    uart_printf("  Data BRAM:  %u KB @ 0x%x\n",
                DATA_BRAM_SIZE / 1024, DATA_BRAM_BASE);
    uart_printf("  Uptime:     %u ms\n", timer_uptime_ms());
    uart_puts("\nPeripherals:\n");
    uart_printf("  UART:       0x%x (115200 baud)\n", UART_BASE);
    uart_printf("  Timer:      0x%x\n", TIMER_BASE);
    uart_printf("  GPIO:       0x%x\n", GPIO_BASE);
    uart_puts("\nMilestone 0 - Basic SoC (no FDC, no HyperRAM)\n");

    return 0;
}

int cmd_reset(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("Resetting...\n");
    timer_delay_ms(100);  /* Allow UART to flush */

    /* Trigger software reset via GPIO or watchdog */
    /* For now, just halt - actual reset depends on HW design */
    uart_puts("Reset not implemented in M0. Halting.\n");
    while (1)
        ;

    return 0;
}
