// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table implementation internals

#include "Vjtag_tap_controller__pch.h"
#include "Vjtag_tap_controller.h"
#include "Vjtag_tap_controller___024root.h"

// FUNCTIONS
Vjtag_tap_controller__Syms::~Vjtag_tap_controller__Syms()
{
}

Vjtag_tap_controller__Syms::Vjtag_tap_controller__Syms(VerilatedContext* contextp, const char* namep, Vjtag_tap_controller* modelp)
    : VerilatedSyms{contextp}
    // Setup internal state of the Syms class
    , __Vm_modelp{modelp}
    // Setup module instances
    , TOP{this, namep}
{
    // Check resources
    Verilated::stackCheck(280);
    // Configure time unit / time precision
    _vm_contextp__->timeunit(-12);
    _vm_contextp__->timeprecision(-12);
    // Setup each module's pointers to their submodules
    // Setup each module's pointer back to symbol table (for public functions)
    TOP.__Vconfigure(true);
}
