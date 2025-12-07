// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vjtag_tap_controller.h for the primary calling header

#include "Vjtag_tap_controller__pch.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vjtag_tap_controller___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vjtag_tap_controller___024root___eval_triggers__ico(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_triggers__ico\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VicoTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VicoTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VicoFirstIteration)));
    vlSelfRef.__VicoFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vjtag_tap_controller___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
}

bool Vjtag_tap_controller___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___trigger_anySet__ico\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

extern const VlUnpacked<CData/*3:0*/, 32> Vjtag_tap_controller__ConstPool__TABLE_h9f6336a8_0;

void Vjtag_tap_controller___024root___ico_sequent__TOP__0(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___ico_sequent__TOP__0\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*4:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    // Body
    __Vtableidx1 = (((IData)(vlSelfRef.tms) << 4U) 
                    | (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.jtag_tap_controller__DOT__next_state 
        = Vjtag_tap_controller__ConstPool__TABLE_h9f6336a8_0
        [__Vtableidx1];
}

void Vjtag_tap_controller___024root___eval_ico(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_ico\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VicoTriggered[0U])) {
        Vjtag_tap_controller___024root___ico_sequent__TOP__0(vlSelf);
    }
}

bool Vjtag_tap_controller___024root___eval_phase__ico(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_phase__ico\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VicoExecute;
    // Body
    Vjtag_tap_controller___024root___eval_triggers__ico(vlSelf);
    __VicoExecute = Vjtag_tap_controller___024root___trigger_anySet__ico(vlSelfRef.__VicoTriggered);
    if (__VicoExecute) {
        Vjtag_tap_controller___024root___eval_ico(vlSelf);
    }
    return (__VicoExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vjtag_tap_controller___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vjtag_tap_controller___024root___eval_triggers__act(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_triggers__act\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                    ((((~ (IData)(vlSelfRef.tck)) 
                                                       & (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tck__0)) 
                                                      << 2U) 
                                                     | ((((~ (IData)(vlSelfRef.trst_n)) 
                                                          & (IData)(vlSelfRef.__Vtrigprevexpr___TOP__trst_n__0)) 
                                                         << 1U) 
                                                        | ((IData)(vlSelfRef.tck) 
                                                           & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tck__0)))))));
    vlSelfRef.__Vtrigprevexpr___TOP__tck__0 = vlSelfRef.tck;
    vlSelfRef.__Vtrigprevexpr___TOP__trst_n__0 = vlSelfRef.trst_n;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vjtag_tap_controller___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
}

bool Vjtag_tap_controller___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vjtag_tap_controller___024root___nba_sequent__TOP__0(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___nba_sequent__TOP__0\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vdly__jtag_tap_controller__DOT__ir_shift_reg 
        = vlSelfRef.jtag_tap_controller__DOT__ir_shift_reg;
}

void Vjtag_tap_controller___024root___nba_sequent__TOP__1(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___nba_sequent__TOP__1\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    QData/*63:0*/ __Vdly__jtag_tap_controller__DOT__dr_shift_reg;
    __Vdly__jtag_tap_controller__DOT__dr_shift_reg = 0;
    // Body
    __Vdly__jtag_tap_controller__DOT__dr_shift_reg 
        = vlSelfRef.jtag_tap_controller__DOT__dr_shift_reg;
    if ((3U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))) {
        if ((0x1fU != (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))) {
            if ((1U == (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))) {
                __Vdly__jtag_tap_controller__DOT__dr_shift_reg 
                    = (0x00000000fb010001ULL | (0xffffffff00000000ULL 
                                                & __Vdly__jtag_tap_controller__DOT__dr_shift_reg));
            } else {
                __Vdly__jtag_tap_controller__DOT__dr_shift_reg 
                    = vlSelfRef.dr_capture_data;
            }
        }
        if ((0x1fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))) {
            vlSelfRef.jtag_tap_controller__DOT__bypass_reg = 0U;
        }
    } else if ((4U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))) {
        if ((0x1fU != (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))) {
            __Vdly__jtag_tap_controller__DOT__dr_shift_reg 
                = (((QData)((IData)(vlSelfRef.tdi)) 
                    << 0x0000003fU) | (vlSelfRef.jtag_tap_controller__DOT__dr_shift_reg 
                                       >> 1U));
        }
        if ((0x1fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))) {
            vlSelfRef.jtag_tap_controller__DOT__bypass_reg 
                = vlSelfRef.tdi;
        }
    }
    vlSelfRef.jtag_tap_controller__DOT__dr_shift_reg 
        = __Vdly__jtag_tap_controller__DOT__dr_shift_reg;
}

void Vjtag_tap_controller___024root___nba_sequent__TOP__2(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___nba_sequent__TOP__2\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.tdo = (1U & ((0x0bU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))
                            ? (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_shift_reg)
                            : ((4U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state)) 
                               && (IData)(vlSelfRef.dr_shift_out))));
}

extern const VlUnpacked<CData/*6:0*/, 32> Vjtag_tap_controller__ConstPool__TABLE_h3056bfd2_0;

void Vjtag_tap_controller___024root___nba_sequent__TOP__3(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___nba_sequent__TOP__3\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*6:0*/ jtag_tap_controller__DOT__current_dr_length;
    jtag_tap_controller__DOT__current_dr_length = 0;
    CData/*4:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    CData/*4:0*/ __Vtableidx2;
    __Vtableidx2 = 0;
    // Body
    if (vlSelfRef.trst_n) {
        if ((0U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))) {
            vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg = 1U;
        } else if ((0x0aU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))) {
            vlSelfRef.__Vdly__jtag_tap_controller__DOT__ir_shift_reg = 1U;
        } else if ((0x0bU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))) {
            vlSelfRef.__Vdly__jtag_tap_controller__DOT__ir_shift_reg 
                = (((IData)(vlSelfRef.tdi) << 4U) | 
                   (0x0000000fU & ((IData)(vlSelfRef.jtag_tap_controller__DOT__ir_shift_reg) 
                                   >> 1U)));
        } else if ((0x0fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state))) {
            vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg 
                = vlSelfRef.jtag_tap_controller__DOT__ir_shift_reg;
        }
        vlSelfRef.jtag_tap_controller__DOT__state = vlSelfRef.jtag_tap_controller__DOT__next_state;
    } else {
        vlSelfRef.__Vdly__jtag_tap_controller__DOT__ir_shift_reg = 0x1fU;
        vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg = 1U;
        vlSelfRef.jtag_tap_controller__DOT__state = 0U;
    }
    vlSelfRef.jtag_tap_controller__DOT__ir_shift_reg 
        = vlSelfRef.__Vdly__jtag_tap_controller__DOT__ir_shift_reg;
    vlSelfRef.ir_value = vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg;
    __Vtableidx2 = vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg;
    jtag_tap_controller__DOT__current_dr_length = Vjtag_tap_controller__ConstPool__TABLE_h3056bfd2_0
        [__Vtableidx2];
    vlSelfRef.dr_length = jtag_tap_controller__DOT__current_dr_length;
    vlSelfRef.ir_capture = (0x0aU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.ir_shift = (0x0bU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.ir_update = (0x0fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_capture = (3U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_shift = (4U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_update = (8U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    __Vtableidx1 = (((IData)(vlSelfRef.tms) << 4U) 
                    | (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.jtag_tap_controller__DOT__next_state 
        = Vjtag_tap_controller__ConstPool__TABLE_h9f6336a8_0
        [__Vtableidx1];
}

void Vjtag_tap_controller___024root___nba_comb__TOP__0(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___nba_comb__TOP__0\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.dr_shift_out = (1U & ((0x1fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))
                                     ? (IData)(vlSelfRef.jtag_tap_controller__DOT__bypass_reg)
                                     : (IData)(vlSelfRef.jtag_tap_controller__DOT__dr_shift_reg)));
}

void Vjtag_tap_controller___024root___eval_nba(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_nba\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vjtag_tap_controller___024root___nba_sequent__TOP__0(vlSelf);
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vjtag_tap_controller___024root___nba_sequent__TOP__1(vlSelf);
    }
    if ((4ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vjtag_tap_controller___024root___nba_sequent__TOP__2(vlSelf);
    }
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vjtag_tap_controller___024root___nba_sequent__TOP__3(vlSelf);
    }
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vjtag_tap_controller___024root___nba_comb__TOP__0(vlSelf);
    }
}

void Vjtag_tap_controller___024root___trigger_orInto__act(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___trigger_orInto__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vjtag_tap_controller___024root___eval_phase__act(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_phase__act\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vjtag_tap_controller___024root___eval_triggers__act(vlSelf);
    Vjtag_tap_controller___024root___trigger_orInto__act(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vjtag_tap_controller___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vjtag_tap_controller___024root___eval_phase__nba(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_phase__nba\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vjtag_tap_controller___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vjtag_tap_controller___024root___eval_nba(vlSelf);
        Vjtag_tap_controller___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vjtag_tap_controller___024root___eval(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VicoIterCount;
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VicoIterCount = 0U;
    vlSelfRef.__VicoFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VicoIterCount)))) {
#ifdef VL_DEBUG
            Vjtag_tap_controller___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
#endif
            VL_FATAL_MT("../rtl/debug/jtag_tap_controller.v", 36, "", "Input combinational region did not converge after 100 tries");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
    } while (Vjtag_tap_controller___024root___eval_phase__ico(vlSelf));
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vjtag_tap_controller___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("../rtl/debug/jtag_tap_controller.v", 36, "", "NBA region did not converge after 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vjtag_tap_controller___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("../rtl/debug/jtag_tap_controller.v", 36, "", "Active region did not converge after 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
        } while (Vjtag_tap_controller___024root___eval_phase__act(vlSelf));
    } while (Vjtag_tap_controller___024root___eval_phase__nba(vlSelf));
}

#ifdef VL_DEBUG
void Vjtag_tap_controller___024root___eval_debug_assertions(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_debug_assertions\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.tck & 0xfeU)))) {
        Verilated::overWidthError("tck");
    }
    if (VL_UNLIKELY(((vlSelfRef.tms & 0xfeU)))) {
        Verilated::overWidthError("tms");
    }
    if (VL_UNLIKELY(((vlSelfRef.tdi & 0xfeU)))) {
        Verilated::overWidthError("tdi");
    }
    if (VL_UNLIKELY(((vlSelfRef.trst_n & 0xfeU)))) {
        Verilated::overWidthError("trst_n");
    }
    if (VL_UNLIKELY(((vlSelfRef.dr_shift_in & 0xfeU)))) {
        Verilated::overWidthError("dr_shift_in");
    }
}
#endif  // VL_DEBUG
