/**
 * FluxRipper Power CLI Commands - Header
 *
 * Command-line interface for power monitoring.
 *
 * Created: 2025-12-04 11:05
 */

#ifndef POWER_CLI_H
#define POWER_CLI_H

#include "cli.h"

/**
 * Main power command handler
 * Dispatches to subcommands (status, rail, total, init)
 */
int cmd_power(int argc, char *argv[]);

/**
 * Initialize and register power CLI commands
 * Call this from main() or cli_init()
 */
void power_cli_init(void);

/**
 * Power CLI command definition (for external registration)
 */
extern const cli_cmd_t power_cli_cmd;

#endif /* POWER_CLI_H */
