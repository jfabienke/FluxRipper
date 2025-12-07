/**
 * FluxRipper SoC - CLI Header
 *
 * Command-line interface for bare-metal firmware
 *
 * Updated: 2025-12-03 18:00
 */

#ifndef CLI_H
#define CLI_H

#include <stdint.h>

/* Maximum command line length */
#define CLI_MAX_LINE    128

/* Maximum number of arguments */
#define CLI_MAX_ARGS    8

/* Command handler function type */
typedef int (*cli_handler_t)(int argc, char *argv[]);

/* Command definition */
typedef struct {
    const char *name;           /* Command name */
    const char *help;           /* Help text */
    cli_handler_t handler;      /* Handler function */
} cli_cmd_t;

/**
 * Initialize CLI subsystem
 */
void cli_init(void);

/**
 * Run CLI main loop (never returns)
 */
void cli_run(void);

/**
 * Process a single command line
 * @param line command line to process
 * @return command return value, or -1 if not found
 */
int cli_process(char *line);

/**
 * Register a command
 * @param cmd command definition
 * @return 0 on success, -1 if table full
 */
int cli_register(const cli_cmd_t *cmd);

/*============================================================================
 * Built-in Commands (Milestone 0)
 *============================================================================*/

/* help - Show available commands */
int cmd_help(int argc, char *argv[]);

/* echo - Echo arguments */
int cmd_echo(int argc, char *argv[]);

/* memtest - Memory test */
int cmd_memtest(int argc, char *argv[]);

/* read - Read memory address */
int cmd_read(int argc, char *argv[]);

/* write - Write memory address */
int cmd_write(int argc, char *argv[]);

/* info - Show system info */
int cmd_info(int argc, char *argv[]);

/* reset - Software reset */
int cmd_reset(int argc, char *argv[]);

#endif /* CLI_H */
