// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vjtag_tap_controller.h for the primary calling header

#ifndef VERILATED_VJTAG_TAP_CONTROLLER___024ROOT_H_
#define VERILATED_VJTAG_TAP_CONTROLLER___024ROOT_H_  // guard

#include "verilated.h"


class Vjtag_tap_controller__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vjtag_tap_controller___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(tck,0,0);
    VL_IN8(trst_n,0,0);
    VL_IN8(tms,0,0);
    VL_IN8(tdi,0,0);
    VL_OUT8(tdo,0,0);
    VL_OUT8(ir_value,4,0);
    VL_OUT8(ir_capture,0,0);
    VL_OUT8(ir_shift,0,0);
    VL_OUT8(ir_update,0,0);
    VL_IN8(dr_shift_in,0,0);
    VL_OUT8(dr_shift_out,0,0);
    VL_OUT8(dr_capture,0,0);
    VL_OUT8(dr_shift,0,0);
    VL_OUT8(dr_update,0,0);
    VL_OUT8(dr_length,6,0);
    CData/*3:0*/ jtag_tap_controller__DOT__state;
    CData/*3:0*/ jtag_tap_controller__DOT__next_state;
    CData/*4:0*/ jtag_tap_controller__DOT__ir_shift_reg;
    CData/*4:0*/ jtag_tap_controller__DOT__ir_hold_reg;
    CData/*0:0*/ jtag_tap_controller__DOT__bypass_reg;
    CData/*4:0*/ __Vdly__jtag_tap_controller__DOT__ir_shift_reg;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VicoFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tck__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__trst_n__0;
    IData/*31:0*/ __VactIterCount;
    VL_IN64(dr_capture_data,63,0);
    QData/*63:0*/ jtag_tap_controller__DOT__dr_shift_reg;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VicoTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vjtag_tap_controller__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vjtag_tap_controller___024root(Vjtag_tap_controller__Syms* symsp, const char* v__name);
    ~Vjtag_tap_controller___024root();
    VL_UNCOPYABLE(Vjtag_tap_controller___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
