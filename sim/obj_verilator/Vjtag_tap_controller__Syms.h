// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VJTAG_TAP_CONTROLLER__SYMS_H_
#define VERILATED_VJTAG_TAP_CONTROLLER__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vjtag_tap_controller.h"

// INCLUDE MODULE CLASSES
#include "Vjtag_tap_controller___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vjtag_tap_controller__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vjtag_tap_controller* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vjtag_tap_controller___024root TOP;

    // CONSTRUCTORS
    Vjtag_tap_controller__Syms(VerilatedContext* contextp, const char* namep, Vjtag_tap_controller* modelp);
    ~Vjtag_tap_controller__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
