/**
 * FluxRipper Instrumentation CLI Commands - Header
 *
 * Command-line interface for diagnostic instrumentation
 *
 * Created: 2025-12-04 14:15
 */

#ifndef INSTRUMENTATION_CLI_H
#define INSTRUMENTATION_CLI_H

#include "cli.h"

/**
 * Main diagnostics command handler
 * Dispatches to subcommands (errors, pll, fifo, capture, seek, clear, all)
 */
int cmd_diag(int argc, char *argv[]);

/**
 * Initialize and register instrumentation CLI commands
 * Call this from main() or cli_init()
 */
void instrumentation_cli_init(void);

/**
 * Instrumentation CLI command definition (for external registration)
 */
extern const cli_cmd_t diag_cli_cmd;

#endif /* INSTRUMENTATION_CLI_H */
