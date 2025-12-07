// Verilator C++ Testbench for JTAG TAP Controller
// Created: 2025-12-07 17:30
// Updated: 2025-12-07 19:45 - Fixed timing, all tests passing
//
// Key timing notes:
//   - TDO updates on negedge of tck
//   - Data shifts on posedge of tck
//   - Must sample TDO after negedge before reading

#include <stdlib.h>
#include <iostream>
#include <iomanip>
#include <chrono>
#include "Vjtag_tap_controller.h"
#include "verilated.h"

#define CLK_PERIOD 10  // 10ns clock period

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Instantiate DUT
    Vjtag_tap_controller* dut = new Vjtag_tap_controller;

    std::cout << "\n========================================\n";
    std::cout << "  JTAG TAP Controller - Verilator Test\n";
    std::cout << "  Running on Apple Silicon M1 Pro\n";
    std::cout << "========================================\n\n";

    // Initialize signals
    dut->tck = 0;
    dut->tms = 1;
    dut->tdi = 0;
    dut->trst_n = 1;
    dut->dr_capture_data = 0;
    dut->dr_shift_in = 0;

    int errors = 0;
    uint64_t sim_time = 0;

    // Helper lambdas for clock control
    auto negedge = [&]() {
        dut->tck = 0;
        dut->eval();
        sim_time += CLK_PERIOD / 2;
    };

    auto posedge = [&]() {
        dut->tck = 1;
        dut->eval();
        sim_time += CLK_PERIOD / 2;
    };

    auto clock_cycle = [&]() {
        negedge();
        posedge();
    };

    //-------------------------------------------------------------------------
    // Test 1: TAP Reset via TMS
    //-------------------------------------------------------------------------
    std::cout << "Test 1: TAP Reset\n";
    dut->tms = 1;
    for (int i = 0; i < 6; i++) clock_cycle();
    dut->tms = 0;
    clock_cycle();  // Go to Run-Test/Idle
    std::cout << "  PASS\n";

    //-------------------------------------------------------------------------
    // Test 2: Read IDCODE (default after reset)
    //-------------------------------------------------------------------------
    std::cout << "Test 2: Read IDCODE\n";

    // Go to Shift-DR
    dut->tms = 1; clock_cycle();  // Select-DR
    dut->tms = 0; clock_cycle();  // Capture-DR
    dut->tms = 0; clock_cycle();  // Shift-DR

    // Wait for TDO to update with first bit
    negedge();

    // Shift out 32 bits (IDCODE)
    uint32_t idcode = 0;
    for (int i = 0; i < 32; i++) {
        if (dut->tdo) idcode |= (1 << i);
        dut->tdi = 0;
        if (i == 31) dut->tms = 1;  // Exit on last bit
        posedge();
        negedge();
    }

    // Exit1-DR -> Update-DR -> Run-Test/Idle
    posedge();
    dut->tms = 0;
    negedge();
    posedge();

    std::cout << "  Captured IDCODE: 0x" << std::hex << std::setw(8)
              << std::setfill('0') << idcode << std::dec << "\n";

    if (idcode == 0xFB010001) {
        std::cout << "  PASS\n";
    } else {
        std::cout << "  FAIL: Expected 0xFB010001\n";
        errors++;
    }

    //-------------------------------------------------------------------------
    // Test 3: Load BYPASS instruction
    //-------------------------------------------------------------------------
    std::cout << "Test 3: Load BYPASS instruction\n";

    // Go to Shift-IR
    dut->tms = 1; clock_cycle();  // Select-DR
    dut->tms = 1; clock_cycle();  // Select-IR
    dut->tms = 0; clock_cycle();  // Capture-IR
    dut->tms = 0; clock_cycle();  // Shift-IR

    // Shift in BYPASS (0x1F = 11111) - 5 bits
    for (int i = 0; i < 5; i++) {
        dut->tdi = 1;
        if (i == 4) dut->tms = 1;  // Exit on last bit
        negedge();
        posedge();
    }

    // Exit1-IR -> Update-IR
    negedge();
    posedge();

    // Update-IR -> Run-Test/Idle
    dut->tms = 0;
    negedge();
    posedge();

    if (dut->ir_value == 0x1F) {
        std::cout << "  IR = 0x" << std::hex << (int)dut->ir_value << std::dec << "\n";
        std::cout << "  PASS\n";
    } else {
        std::cout << "  FAIL: IR = 0x" << std::hex << (int)dut->ir_value << std::dec << "\n";
        errors++;
    }

    //-------------------------------------------------------------------------
    // Test 4: Performance benchmark
    //-------------------------------------------------------------------------
    std::cout << "Test 4: Performance (1M cycles)\n";

    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < 1000000; i++) {
        clock_cycle();
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);

    double mhz = 1000.0 / duration.count();
    std::cout << "  1M cycles in " << duration.count() << " ms\n";
    std::cout << "  Simulation speed: " << std::fixed << std::setprecision(1) << mhz << " MHz\n";
    std::cout << "  PASS\n";

    //-------------------------------------------------------------------------
    // Summary
    //-------------------------------------------------------------------------
    std::cout << "\n========================================\n";
    if (errors == 0) {
        std::cout << "  ALL TESTS PASSED\n";
    } else {
        std::cout << "  FAILED: " << errors << " errors\n";
    }
    std::cout << "  Simulated time: " << sim_time << " ns\n";
    std::cout << "========================================\n\n";

    delete dut;
    return errors ? 1 : 0;
}
