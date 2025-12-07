/**
 * FluxRipper Power CLI Commands
 *
 * Command-line interface for power monitoring.
 * Supports 6 drive connectors (4 FDD + 2 HDD) with per-connector monitoring.
 *
 * Created: 2025-12-04 11:00
 * Updated: 2025-12-07 11:00 - 6-connector architecture with USB-C/ATX input
 */

#include "cli.h"
#include "power_hal.h"
#include "uart.h"
#include <string.h>

/*============================================================================
 * Helper Functions
 *============================================================================*/

static void print_voltage(uint16_t mv)
{
    uart_printf("%u.%02uV", mv / 1000, (mv % 1000) / 10);
}

static void print_current(int16_t ma)
{
    if (ma < 0) {
        uart_printf("-%umA", (uint16_t)(-ma));
    } else {
        uart_printf("%umA", (uint16_t)ma);
    }
}

static void print_power(uint32_t mw)
{
    if (mw >= 1000) {
        uart_printf("%lu.%02luW", mw / 1000, (mw % 1000) / 10);
    } else {
        uart_printf("%lumW", mw);
    }
}

static const char *get_conn_status(pwr_conn_status_t *c)
{
    if (c->fault) return "FAULT!";
    if (!c->enabled) return "OFF";
    if (!c->present) return "N/C";
    if (c->total_power_mw > 15000) return "ACTIVE";
    if (c->total_power_mw > 5000) return "SPIN";
    if (c->total_power_mw < 500) return "IDLE";
    return "OK";
}

static const char *get_source_str(pwr_source_t src)
{
    switch (src) {
        case PWR_SRC_USB_C: return "USB-C PD";
        case PWR_SRC_ATX:   return "ATX PSU";
        case PWR_SRC_BOTH:  return "USB-C + ATX";
        default:            return "NONE";
    }
}

/*============================================================================
 * CLI Command Implementations
 *============================================================================*/

/**
 * power status - Show complete power status (input, connectors, system)
 */
static int cmd_power_status(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    pmu_system_t sys;
    int ret = pmu_read_all(&sys);

    if (ret != PMU_OK) {
        uart_puts("Failed to read power status\n");
        return -1;
    }

    /* Input Power Sources */
    uart_puts("\n╔═══════════════════════════════════════════════════════════════╗\n");
    uart_puts("║                    POWER INPUT STATUS                         ║\n");
    uart_puts("╠═══════════════════════════════════════════════════════════════╣\n");

    uart_printf("║  Active Source: %-12s", get_source_str(sys.active_source));

    if (sys.active_source == PWR_SRC_USB_C || sys.active_source == PWR_SRC_BOTH) {
        uart_printf("  USB-C: ");
        print_voltage(sys.usbc_status.voltage_mv);
        uart_printf(" @ %umA (PD%u.%u)\n",
            sys.usbc_status.current_ma,
            sys.usbc_status.pd_version / 10,
            sys.usbc_status.pd_version % 10);
    } else {
        uart_puts("\n");
    }

    if (sys.active_source == PWR_SRC_ATX || sys.active_source == PWR_SRC_BOTH) {
        uart_printf("║  ATX 12V: ");
        print_voltage(sys.atx_12v_mv);
        uart_printf("    ATX 5V: ");
        print_voltage(sys.atx_5v_mv);
        uart_puts("\n");
    }

    uart_printf("║  Input Power: ");
    print_power(sys.input_power_mw);
    uart_puts("\n");

    /* Drive Connectors (6 total) */
    uart_puts("╠═══════════════════════════════════════════════════════════════╣\n");
    uart_puts("║                  DRIVE CONNECTORS (6)                         ║\n");
    uart_puts("╠═══════════════════════════════════════════════════════════════╣\n");
    uart_puts("║  Conn    5V Rail       12V Rail       Power    Status        ║\n");
    uart_puts("╟───────────────────────────────────────────────────────────────╢\n");

    for (int i = 0; i < PWR_CONN_COUNT; i++) {
        pwr_conn_status_t *c = &sys.connectors[i];

        uart_printf("║  %-5s  ", pwr_conn_name((pwr_conn_t)i));

        /* 5V rail */
        if (c->rail_5v.valid) {
            print_voltage(c->rail_5v.voltage_mv);
            uart_printf("/%4umA  ", c->rail_5v.current_ma);
        } else {
            uart_puts("  --/--    ");
        }

        /* 12V rail (or 24V for 8" mode on FDD3) */
        if (c->rail_12v.valid) {
            print_voltage(c->rail_12v.voltage_mv);
            uart_printf("/%4umA  ", c->rail_12v.current_ma);
        } else {
            uart_puts("  --/--    ");
        }

        /* Total power */
        if (c->enabled && (c->rail_5v.valid || c->rail_12v.valid)) {
            print_power(c->total_power_mw);
        } else {
            uart_puts("   --");
        }
        uart_puts("   ");

        /* Status */
        uart_printf("%-6s", get_conn_status(c));

        /* Special indicators */
        if (i == PWR_CONN_FDD3 && pwr_conn_is_8inch_mode()) {
            uart_puts(" [24V]");
        }
        uart_puts("  ║\n");
    }

    /* System Rails */
    uart_puts("╠═══════════════════════════════════════════════════════════════╣\n");
    uart_puts("║                      SYSTEM RAILS                             ║\n");
    uart_puts("╟───────────────────────────────────────────────────────────────╢\n");

    /* 24V 8" drive rail */
    pmu_reading_t *r24 = &sys.rails[PMU_RAIL_24V_8INCH];
    uart_puts("║  24V 8\":  ");
    if (r24->valid) {
        print_voltage(r24->voltage_mv);
        uart_printf(" @ %umA", r24->current_ma);
    } else {
        uart_puts("-- (disabled)");
    }

    /* 3.3V FPGA I/O */
    pmu_reading_t *r33 = &sys.rails[PMU_RAIL_3V3_IO];
    uart_puts("    3.3V IO: ");
    if (r33->valid) {
        print_voltage(r33->voltage_mv);
        uart_printf("/%umA", r33->current_ma);
    } else {
        uart_puts("--");
    }
    uart_puts("  ║\n");

    /* 1.0V Core */
    pmu_reading_t *r10 = &sys.rails[PMU_RAIL_1V0_CORE];
    uart_puts("║  1.0V Core: ");
    if (r10->valid) {
        print_voltage(r10->voltage_mv);
        uart_printf(" @ %umA", r10->current_ma);
    } else {
        uart_puts("--");
    }
    uart_puts("\n");

    /* Power Summary */
    uart_puts("╠═══════════════════════════════════════════════════════════════╣\n");
    uart_puts("║                     POWER SUMMARY                             ║\n");
    uart_puts("╟───────────────────────────────────────────────────────────────╢\n");

    uart_puts("║  FDD Power: ");
    print_power(sys.fdd_power_mw);
    uart_puts("   HDD Power: ");
    print_power(sys.hdd_power_mw);
    uart_puts("   System: ");
    print_power(sys.system_power_mw);
    uart_puts("  ║\n");

    /* Power budget */
    uint32_t available, allocated, remaining;
    pwr_budget_report(&available, &allocated, &remaining);

    uart_puts("║  Budget: ");
    print_power(allocated);
    uart_puts(" / ");
    print_power(available);
    uart_printf(" (%lu%% used)", (allocated * 100) / (available ? available : 1));
    uart_puts("                   ║\n");

    uart_puts("║  TOTAL: ");
    print_power(sys.total_power_mw);
    uart_puts("\n");

    uart_puts("╚═══════════════════════════════════════════════════════════════╝\n");

    /* INA3221 presence */
    uart_puts("\nPower Monitors: ");
    int found = 0;
    const char *names[] = {"A", "B", "C", "D", "E", "F"};
    for (int i = 0; i < INA3221_COUNT_TOTAL; i++) {
        if (sys.ina3221_present[i]) {
            uart_printf("%s ", names[i]);
            found++;
        }
    }
    uart_printf("(%d/6 INA3221)\n", found);

    return 0;
}

/**
 * power connector <name> - Show specific connector details
 */
static int cmd_power_connector(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: power connector <name>\n");
        uart_puts("Connectors: fdd0, fdd1, fdd2, fdd3, hdd0, hdd1\n");
        return -1;
    }

    /* Find connector by name */
    pwr_conn_t conn = PWR_CONN_COUNT;
    const char *name = argv[1];

    if (strcmp(name, "fdd0") == 0) conn = PWR_CONN_FDD0;
    else if (strcmp(name, "fdd1") == 0) conn = PWR_CONN_FDD1;
    else if (strcmp(name, "fdd2") == 0) conn = PWR_CONN_FDD2;
    else if (strcmp(name, "fdd3") == 0) conn = PWR_CONN_FDD3;
    else if (strcmp(name, "hdd0") == 0) conn = PWR_CONN_HDD0;
    else if (strcmp(name, "hdd1") == 0) conn = PWR_CONN_HDD1;

    if (conn == PWR_CONN_COUNT) {
        uart_printf("Unknown connector: %s\n", name);
        return -1;
    }

    pwr_conn_status_t status;
    int ret = pwr_conn_get_status(conn, &status);

    if (ret != PMU_OK) {
        uart_printf("Failed to read connector: %d\n", ret);
        return -1;
    }

    uart_printf("\n%s Connector Details\n", pwr_conn_name(conn));
    uart_puts("-----------------------------------\n");

    /* 5V Rail */
    uart_puts("  5V Rail:  ");
    if (status.rail_5v.valid) {
        print_voltage(status.rail_5v.voltage_mv);
        uart_puts(" @ ");
        print_current(status.rail_5v.current_ma);
        uart_puts(" (");
        print_power(status.rail_5v.power_mw);
        uart_puts(")\n");
    } else {
        uart_puts("N/C\n");
    }

    /* 12V Rail (or 24V for 8" mode) */
    if (conn == PWR_CONN_FDD3 && pwr_conn_is_8inch_mode()) {
        uart_puts("  24V Rail: ");
    } else {
        uart_puts("  12V Rail: ");
    }
    if (status.rail_12v.valid) {
        print_voltage(status.rail_12v.voltage_mv);
        uart_puts(" @ ");
        print_current(status.rail_12v.current_ma);
        uart_puts(" (");
        print_power(status.rail_12v.power_mw);
        uart_puts(")\n");
    } else {
        uart_puts("N/C\n");
    }

    /* Total power */
    uart_puts("  Total:    ");
    print_power(status.total_power_mw);
    uart_puts("\n");

    /* Status flags */
    uart_puts("  Enabled:  ");
    uart_puts(status.enabled ? "Yes" : "No");
    uart_puts("\n");

    uart_puts("  Present:  ");
    uart_puts(status.present ? "Yes" : "No");
    uart_puts("\n");

    uart_puts("  Fault:    ");
    uart_puts(status.fault ? "YES!" : "No");
    uart_puts("\n");

    uart_puts("  Status:   ");
    uart_puts(get_conn_status(&status));
    uart_puts("\n");

    /* Power budget */
    if (pwr_budget_check(conn)) {
        uart_puts("  Budget:   Within limits\n");
    } else {
        uart_puts("  Budget:   OVER BUDGET!\n");
    }

    uart_puts("-----------------------------------\n");

    return 0;
}

/**
 * power rail <name> - Show specific rail details
 */
static int cmd_power_rail(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: power rail <name>\n");
        uart_puts("Rails: fdd0_5v, fdd0_12v, fdd1_5v, fdd1_12v,\n");
        uart_puts("       fdd2_5v, fdd2_12v, fdd3_5v, fdd3_12v,\n");
        uart_puts("       hdd0_5v, hdd0_12v, hdd1_5v, hdd1_12v,\n");
        uart_puts("       24v_8inch, usbc_vbus, atx_12v, atx_5v,\n");
        uart_puts("       3v3_io, 1v0_core\n");
        return -1;
    }

    /* Find rail by name */
    pmu_rail_t rail = PMU_RAIL_COUNT;
    const char *name = argv[1];

    /* FDD rails */
    if (strcmp(name, "fdd0_5v") == 0) rail = PMU_RAIL_FDD0_5V;
    else if (strcmp(name, "fdd0_12v") == 0) rail = PMU_RAIL_FDD0_12V;
    else if (strcmp(name, "fdd1_5v") == 0) rail = PMU_RAIL_FDD1_5V;
    else if (strcmp(name, "fdd1_12v") == 0) rail = PMU_RAIL_FDD1_12V;
    else if (strcmp(name, "fdd2_5v") == 0) rail = PMU_RAIL_FDD2_5V;
    else if (strcmp(name, "fdd2_12v") == 0) rail = PMU_RAIL_FDD2_12V;
    else if (strcmp(name, "fdd3_5v") == 0) rail = PMU_RAIL_FDD3_5V;
    else if (strcmp(name, "fdd3_12v") == 0) rail = PMU_RAIL_FDD3_12V;
    /* HDD rails */
    else if (strcmp(name, "hdd0_5v") == 0) rail = PMU_RAIL_HDD0_5V;
    else if (strcmp(name, "hdd0_12v") == 0) rail = PMU_RAIL_HDD0_12V;
    else if (strcmp(name, "hdd1_5v") == 0) rail = PMU_RAIL_HDD1_5V;
    else if (strcmp(name, "hdd1_12v") == 0) rail = PMU_RAIL_HDD1_12V;
    /* Special rails */
    else if (strcmp(name, "24v_8inch") == 0) rail = PMU_RAIL_24V_8INCH;
    else if (strcmp(name, "usbc_vbus") == 0) rail = PMU_RAIL_USB_C_VBUS;
    else if (strcmp(name, "atx_12v") == 0) rail = PMU_RAIL_ATX_12V;
    else if (strcmp(name, "atx_5v") == 0) rail = PMU_RAIL_ATX_5V;
    /* System rails */
    else if (strcmp(name, "3v3_io") == 0) rail = PMU_RAIL_3V3_IO;
    else if (strcmp(name, "1v0_core") == 0) rail = PMU_RAIL_1V0_CORE;

    if (rail == PMU_RAIL_COUNT) {
        uart_printf("Unknown rail: %s\n", name);
        return -1;
    }

    pmu_reading_t reading;
    int ret = pmu_read_rail(rail, &reading);

    if (ret != PMU_OK) {
        uart_printf("Failed to read rail: %d\n", ret);
        return -1;
    }

    uart_printf("\n%s Rail Details\n", pmu_rail_name(rail));
    uart_puts("-----------------------------------\n");
    uart_printf("  Nominal:  ");
    print_voltage(pmu_rail_nominal_mv(rail));
    uart_puts("\n");

    if (reading.valid) {
        uart_printf("  Actual:   ");
        print_voltage(reading.voltage_mv);

        int16_t delta = (int16_t)reading.voltage_mv - (int16_t)pmu_rail_nominal_mv(rail);
        if (delta >= 0) {
            uart_printf(" (+%dmV)\n", delta);
        } else {
            uart_printf(" (%dmV)\n", delta);
        }

        uart_printf("  Current:  ");
        print_current(reading.current_ma);
        uart_puts("\n");

        uart_printf("  Power:    ");
        print_power(reading.power_mw);
        uart_puts("\n");

        /* Determine status */
        const char *status_str;
        uint16_t nominal = pmu_rail_nominal_mv(rail);
        int16_t pct = ((int32_t)(reading.voltage_mv - nominal) * 100) / nominal;
        if (pct < -10 || pct > 10) {
            status_str = "OUT OF RANGE";
        } else if (pct < -5 || pct > 5) {
            status_str = "WARNING";
        } else {
            status_str = "OK";
        }
        uart_printf("  Status:   %s\n", status_str);
    } else {
        uart_puts("  Status:   Not connected\n");
    }
    uart_puts("-----------------------------------\n");

    return 0;
}

/**
 * power dcdc [enable|disable <name>] - Show/control DC-DC converters
 */
static int cmd_power_dcdc(int argc, char *argv[])
{
    if (argc >= 3) {
        /* Control a specific converter */
        bool enable;
        if (strcmp(argv[1], "enable") == 0) {
            enable = true;
        } else if (strcmp(argv[1], "disable") == 0) {
            enable = false;
        } else {
            uart_puts("Usage: power dcdc [enable|disable <name>]\n");
            return -1;
        }

        dcdc_id_t id = DCDC_COUNT;
        const char *name = argv[2];

        if (strcmp(name, "24v") == 0 || strcmp(name, "boost") == 0) id = DCDC_24V_BOOST;
        else if (strcmp(name, "5v") == 0) id = DCDC_5V_BUCK;
        else if (strcmp(name, "3v3") == 0) id = DCDC_3V3_BUCK;
        else if (strcmp(name, "1v0") == 0) id = DCDC_1V0_BUCK;

        if (id == DCDC_COUNT) {
            uart_printf("Unknown converter: %s\n", name);
            uart_puts("Valid: 24v, 5v, 3v3, 1v0\n");
            return -1;
        }

        int ret = dcdc_set_enable(id, enable);
        if (ret == PMU_OK) {
            uart_printf("%s: %s\n", dcdc_name(id), enable ? "ENABLED" : "DISABLED");
        } else {
            uart_printf("Failed to %s %s\n", enable ? "enable" : "disable", dcdc_name(id));
        }
        return ret;
    }

    /* Show all DC-DC status */
    uart_puts("\nDC-DC Converter Status\n");
    uart_puts("===========================================================\n");
    uart_puts("  Converter     Type   Vin      Vout     Eff    Status\n");
    uart_puts("-----------------------------------------------------------\n");

    dcdc_status_t status;
    for (int i = 0; i < DCDC_COUNT; i++) {
        dcdc_read_status((dcdc_id_t)i, &status);

        uart_printf("  %-12s ", dcdc_name((dcdc_id_t)i));

        /* Type */
        uart_puts(i == DCDC_24V_BOOST ? "Boost " : "Buck  ");

        /* Input voltage */
        print_voltage(status.vin_mv);
        uart_puts("   ");

        /* Output voltage */
        print_voltage(status.vout_mv);
        uart_puts("   ");

        /* Efficiency */
        if (status.efficiency > 0) {
            uart_printf("%3u%%", status.efficiency);
        } else {
            uart_puts("  --");
        }
        uart_puts("  ");

        /* Status */
        if (!status.enabled) {
            uart_puts("DISABLED");
        } else if (status.fault) {
            uart_puts("FAULT!");
        } else if (!status.power_good) {
            uart_puts("STARTING");
        } else {
            uart_puts("OK");
        }

        uart_puts("\n");
    }
    uart_puts("-----------------------------------------------------------\n");

    /* Summary */
    if (dcdc_all_pgood()) {
        uart_puts("All enabled converters: POWER GOOD\n");
    } else {
        uart_puts("WARNING: Some converters not ready!\n");
    }

    uint8_t faults = dcdc_check_faults();
    if (faults) {
        uart_puts("FAULTS DETECTED: ");
        if (faults & (1 << DCDC_24V_BOOST)) uart_puts("24V ");
        if (faults & (1 << DCDC_5V_BUCK)) uart_puts("5V ");
        if (faults & (1 << DCDC_3V3_BUCK)) uart_puts("3.3V ");
        if (faults & (1 << DCDC_1V0_BUCK)) uart_puts("1.0V ");
        uart_puts("\n");
    }

    return 0;
}

/**
 * power init - Re-initialize power monitoring
 */
static int cmd_power_init(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("Initializing power monitoring...\n");

    int ret = pmu_init();
    if (ret == PMU_OK) {
        uart_puts("Power monitoring initialized.\n");
    } else {
        uart_printf("Initialization failed: %d\n", ret);
    }

    return ret;
}

/**
 * power total - Show total power only
 */
static int cmd_power_total(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uint32_t total = pmu_get_total_power_mw();
    uart_printf("Total system power: ");
    print_power(total);
    uart_puts("\n");

    return 0;
}

/**
 * power enable/disable <connector> - Control connector power
 */
static int cmd_power_enable(int argc, char *argv[], bool enable)
{
    if (argc < 2) {
        uart_printf("Usage: power %s <connector>\n", enable ? "enable" : "disable");
        uart_puts("Connectors: fdd0, fdd1, fdd2, fdd3, hdd0, hdd1, all\n");
        return -1;
    }

    const char *name = argv[1];

    /* Handle "all" */
    if (strcmp(name, "all") == 0) {
        for (int i = 0; i < PWR_CONN_COUNT; i++) {
            pwr_conn_enable((pwr_conn_t)i, enable);
        }
        uart_printf("All connectors %s\n", enable ? "enabled" : "disabled");
        return 0;
    }

    /* Find connector */
    pwr_conn_t conn = PWR_CONN_COUNT;
    if (strcmp(name, "fdd0") == 0) conn = PWR_CONN_FDD0;
    else if (strcmp(name, "fdd1") == 0) conn = PWR_CONN_FDD1;
    else if (strcmp(name, "fdd2") == 0) conn = PWR_CONN_FDD2;
    else if (strcmp(name, "fdd3") == 0) conn = PWR_CONN_FDD3;
    else if (strcmp(name, "hdd0") == 0) conn = PWR_CONN_HDD0;
    else if (strcmp(name, "hdd1") == 0) conn = PWR_CONN_HDD1;

    if (conn == PWR_CONN_COUNT) {
        uart_printf("Unknown connector: %s\n", name);
        return -1;
    }

    int ret = pwr_conn_enable(conn, enable);
    if (ret == PMU_OK) {
        uart_printf("%s: %s\n", pwr_conn_name(conn), enable ? "ENABLED" : "DISABLED");
    } else {
        uart_printf("Failed to %s %s: %d\n",
            enable ? "enable" : "disable", pwr_conn_name(conn), ret);
    }
    return ret;
}

/**
 * power 8inch [on|off] - Control 24V 8" drive mode
 */
static int cmd_power_8inch(int argc, char *argv[])
{
    if (argc < 2) {
        uart_printf("8\" drive mode: %s\n",
            pwr_conn_is_8inch_mode() ? "ENABLED (24V)" : "DISABLED (12V)");
        return 0;
    }

    bool enable;
    if (strcmp(argv[1], "on") == 0 || strcmp(argv[1], "enable") == 0) {
        enable = true;
    } else if (strcmp(argv[1], "off") == 0 || strcmp(argv[1], "disable") == 0) {
        enable = false;
    } else {
        uart_puts("Usage: power 8inch [on|off]\n");
        return -1;
    }

    int ret = pwr_conn_set_8inch_mode(enable);
    if (ret == PMU_OK) {
        uart_printf("8\" drive mode: %s\n", enable ? "ENABLED (24V on FDD3)" : "DISABLED");
    } else {
        uart_printf("Failed to set 8\" mode: %d\n", ret);
    }
    return ret;
}

/**
 * Main power command dispatcher
 */
int cmd_power(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Power Commands:\n");
        uart_puts("  power status             - Full power status (inputs, connectors, system)\n");
        uart_puts("  power connector <name>   - Connector details (fdd0-3, hdd0-1)\n");
        uart_puts("  power rail <name>        - Specific rail details\n");
        uart_puts("  power enable <conn>      - Enable connector power\n");
        uart_puts("  power disable <conn>     - Disable connector power\n");
        uart_puts("  power 8inch [on|off]     - 24V 8\" drive mode (FDD3)\n");
        uart_puts("  power dcdc               - DC-DC converter status\n");
        uart_puts("  power total              - Total power consumption\n");
        uart_puts("  power init               - Re-initialize power monitoring\n");
        return 0;
    }

    if (strcmp(argv[1], "status") == 0) {
        return cmd_power_status(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "connector") == 0 || strcmp(argv[1], "conn") == 0) {
        return cmd_power_connector(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "rail") == 0) {
        return cmd_power_rail(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "enable") == 0) {
        return cmd_power_enable(argc - 1, &argv[1], true);
    } else if (strcmp(argv[1], "disable") == 0) {
        return cmd_power_enable(argc - 1, &argv[1], false);
    } else if (strcmp(argv[1], "8inch") == 0) {
        return cmd_power_8inch(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "dcdc") == 0) {
        return cmd_power_dcdc(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "total") == 0) {
        return cmd_power_total(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "init") == 0) {
        return cmd_power_init(argc - 1, &argv[1]);
    } else {
        uart_printf("Unknown power command: %s\n", argv[1]);
        uart_puts("Type 'power' for available commands.\n");
        return -1;
    }
}

/*============================================================================
 * CLI Registration
 *============================================================================*/

const cli_cmd_t power_cli_cmd = {
    "power", "Power monitoring (status, rail, total)",
    cmd_power
};

void power_cli_init(void)
{
    /* Initialize DC-DC converter GPIO */
    dcdc_gpio_init();

    /* Initialize power HAL (INA3221 monitors) */
    pmu_init();

    /* Register power command */
    cli_register(&power_cli_cmd);
}
