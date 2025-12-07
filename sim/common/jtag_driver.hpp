// FluxRipper JTAG Driver - C++ Class for Verilator
// Created: 2025-12-07 20:35
//
// Template class that works with any Verilator-generated DUT that has
// standard JTAG signals (tck, tms, tdi, tdo, trst_n).
//
// Usage:
//   #include "jtag_driver.hpp"
//   JtagDriver<Vjtag_tap_controller> jtag(dut);
//   jtag.reset();
//   uint32_t idcode = jtag.read_idcode();

#pragma once
#include <cstdint>
#include <vector>

// JTAG Instruction codes
namespace JTAG {
    constexpr uint8_t BYPASS    = 0x1F;
    constexpr uint8_t IDCODE    = 0x01;
    constexpr uint8_t DTMCS     = 0x10;
    constexpr uint8_t DMI       = 0x11;
    constexpr uint8_t MEM_READ  = 0x02;
    constexpr uint8_t MEM_WRITE = 0x03;
    constexpr uint8_t SIG_TAP   = 0x04;
    constexpr uint8_t STATUS    = 0x07;
    constexpr uint8_t CAPS      = 0x08;
}

template<typename DUT>
class JtagDriver {
private:
    DUT* dut;
    uint64_t& sim_time;
    static constexpr int CLK_PERIOD = 10;

    void negedge() {
        dut->tck = 0;
        dut->eval();
        sim_time += CLK_PERIOD / 2;
    }

    void posedge() {
        dut->tck = 1;
        dut->eval();
        sim_time += CLK_PERIOD / 2;
    }

    void clock_cycle() {
        negedge();
        posedge();
    }

    void goto_shift_ir() {
        dut->tms = 1; clock_cycle();  // Select-DR
        dut->tms = 1; clock_cycle();  // Select-IR
        dut->tms = 0; clock_cycle();  // Capture-IR
        dut->tms = 0; clock_cycle();  // Shift-IR
    }

    void goto_shift_dr() {
        dut->tms = 1; clock_cycle();  // Select-DR
        dut->tms = 0; clock_cycle();  // Capture-DR
        dut->tms = 0; clock_cycle();  // Shift-DR
        negedge();  // TDO now valid
    }

    void exit_to_idle() {
        posedge();       // Exit1
        dut->tms = 0;
        negedge();
        posedge();       // Run-Test/Idle
    }

public:
    JtagDriver(DUT* dut_, uint64_t& sim_time_) 
        : dut(dut_), sim_time(sim_time_) {}

    //-------------------------------------------------------------------------
    // TAP Reset
    //-------------------------------------------------------------------------
    void reset() {
        dut->tms = 1;
        for (int i = 0; i < 6; i++) clock_cycle();
        dut->tms = 0;
        clock_cycle();
    }

    //-------------------------------------------------------------------------
    // Shift IR (5-bit)
    //-------------------------------------------------------------------------
    void shift_ir(uint8_t ir) {
        goto_shift_ir();
        for (int i = 0; i < 5; i++) {
            dut->tdi = (ir >> i) & 1;
            if (i == 4) dut->tms = 1;
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
    }

    //-------------------------------------------------------------------------
    // Shift DR (32-bit)
    //-------------------------------------------------------------------------
    uint32_t shift_dr_32(uint32_t data_in) {
        goto_shift_dr();
        uint32_t data_out = 0;
        for (int i = 0; i < 32; i++) {
            if (dut->tdo) data_out |= (1 << i);
            dut->tdi = (data_in >> i) & 1;
            if (i == 31) dut->tms = 1;
            posedge();
            negedge();
        }
        exit_to_idle();
        return data_out;
    }

    //-------------------------------------------------------------------------
    // Shift DR (41-bit for DMI)
    //-------------------------------------------------------------------------
    uint64_t shift_dr_41(uint64_t data_in) {
        goto_shift_dr();
        uint64_t data_out = 0;
        for (int i = 0; i < 41; i++) {
            if (dut->tdo) data_out |= (1ULL << i);
            dut->tdi = (data_in >> i) & 1;
            if (i == 40) dut->tms = 1;
            posedge();
            negedge();
        }
        exit_to_idle();
        return data_out;
    }

    //-------------------------------------------------------------------------
    // Shift DR (64-bit)
    //-------------------------------------------------------------------------
    uint64_t shift_dr_64(uint64_t data_in) {
        goto_shift_dr();
        uint64_t data_out = 0;
        for (int i = 0; i < 64; i++) {
            if (dut->tdo) data_out |= (1ULL << i);
            dut->tdi = (data_in >> i) & 1;
            if (i == 63) dut->tms = 1;
            posedge();
            negedge();
        }
        exit_to_idle();
        return data_out;
    }

    //-------------------------------------------------------------------------
    // Read IDCODE
    //-------------------------------------------------------------------------
    uint32_t read_idcode() {
        shift_ir(JTAG::IDCODE);
        return shift_dr_32(0);
    }

    //-------------------------------------------------------------------------
    // DMI Read (Layer 1+)
    //   DMI format: [40:34]=addr, [33:2]=data, [1:0]=op
    //   op: 0=nop, 1=read, 2=write
    //-------------------------------------------------------------------------
    uint32_t dmi_read(uint8_t addr) {
        shift_ir(JTAG::DMI);
        // Send read request: addr[6:0], data[31:0]=0, op[1:0]=1
        uint64_t dmi_in = ((uint64_t)addr << 34) | 0x01;
        shift_dr_41(dmi_in);
        // Get result with nop
        uint64_t dmi_out = shift_dr_41(0);
        return (dmi_out >> 2) & 0xFFFFFFFF;
    }

    //-------------------------------------------------------------------------
    // DMI Write (Layer 1+)
    //-------------------------------------------------------------------------
    void dmi_write(uint8_t addr, uint32_t data) {
        shift_ir(JTAG::DMI);
        // addr[6:0], data[31:0], op[1:0]=2 (write)
        uint64_t dmi_in = ((uint64_t)addr << 34) | ((uint64_t)data << 2) | 0x02;
        shift_dr_41(dmi_in);
    }

    //-------------------------------------------------------------------------
    // Memory Read via Debug Module (Layer 2+)
    //-------------------------------------------------------------------------
    uint32_t mem_read(uint32_t addr) {
        // Write address to sbaddress0 (DM register 0x39)
        dmi_write(0x39, addr);
        // Read data from sbdata0 (DM register 0x3C)
        return dmi_read(0x3C);
    }

    //-------------------------------------------------------------------------
    // Memory Write via Debug Module (Layer 2+)
    //-------------------------------------------------------------------------
    void mem_write(uint32_t addr, uint32_t data) {
        dmi_write(0x39, addr);  // sbaddress0
        dmi_write(0x3C, data);  // sbdata0 (triggers write)
    }

    //-------------------------------------------------------------------------
    // Bulk Memory Read
    //-------------------------------------------------------------------------
    std::vector<uint32_t> mem_read_bulk(uint32_t addr, size_t count) {
        std::vector<uint32_t> data;
        data.reserve(count);
        // Enable auto-increment in sbcs if not already done
        for (size_t i = 0; i < count; i++) {
            data.push_back(mem_read(addr + i * 4));
        }
        return data;
    }
};
