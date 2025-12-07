/**
 * FluxStat CLI - Command Line Interface for Statistical Recovery
 *
 * CLI commands for multi-pass flux capture and analysis.
 *
 * Created: 2025-12-04 19:15
 */

#ifndef FLUXSTAT_CLI_H
#define FLUXSTAT_CLI_H

#include "cli.h"

/**
 * FluxStat CLI command definition for registration
 */
extern const cli_cmd_t fluxstat_cli_cmd;

/**
 * Initialize and register FluxStat CLI commands
 */
void fluxstat_cli_init(void);

#endif /* FLUXSTAT_CLI_H */
