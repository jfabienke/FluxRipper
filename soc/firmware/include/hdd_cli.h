/**
 * FluxRipper HDD CLI Commands - Header
 *
 * Command-line interface for HDD operations
 *
 * Created: 2025-12-04 09:27:34
 */

#ifndef HDD_CLI_H
#define HDD_CLI_H

#include "cli.h"

/**
 * Main HDD command handler
 * Dispatches to subcommands (detect, discover, status, etc.)
 */
int cmd_hdd(int argc, char *argv[]);

/**
 * Initialize and register HDD CLI commands
 * Call this from main() or cli_init()
 */
void hdd_cli_init(void);

/**
 * HDD CLI command definition (for external registration)
 */
extern const cli_cmd_t hdd_cli_cmd;

#endif /* HDD_CLI_H */
