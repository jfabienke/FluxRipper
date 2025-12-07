// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vjtag_tap_controller.h for the primary calling header

#include "Vjtag_tap_controller__pch.h"

VL_ATTR_COLD void Vjtag_tap_controller___024root___eval_static(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_static\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__tck__0 = vlSelfRef.tck;
    vlSelfRef.__Vtrigprevexpr___TOP__trst_n__0 = vlSelfRef.trst_n;
}

VL_ATTR_COLD void Vjtag_tap_controller___024root___eval_initial(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_initial\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vjtag_tap_controller___024root___eval_final(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_final\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vjtag_tap_controller___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vjtag_tap_controller___024root___eval_phase__stl(Vjtag_tap_controller___024root* vlSelf);

VL_ATTR_COLD void Vjtag_tap_controller___024root___eval_settle(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_settle\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vjtag_tap_controller___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("rtl/debug/jtag_tap_controller.v", 36, "", "Settle region did not converge after 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
    } while (Vjtag_tap_controller___024root___eval_phase__stl(vlSelf));
}

VL_ATTR_COLD void Vjtag_tap_controller___024root___eval_triggers__stl(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_triggers__stl\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    vlSelfRef.__VstlFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vjtag_tap_controller___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
}

VL_ATTR_COLD bool Vjtag_tap_controller___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vjtag_tap_controller___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vjtag_tap_controller___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vjtag_tap_controller___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___trigger_anySet__stl\n"); );
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
extern const VlUnpacked<CData/*6:0*/, 32> Vjtag_tap_controller__ConstPool__TABLE_h3056bfd2_0;

VL_ATTR_COLD void Vjtag_tap_controller___024root___stl_sequent__TOP__0(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___stl_sequent__TOP__0\n"); );
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
    vlSelfRef.ir_value = vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg;
    vlSelfRef.ir_capture = (0x0aU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.ir_shift = (0x0bU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.ir_update = (0x0fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_capture = (3U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_shift = (4U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_update = (8U == (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.dr_shift_out = (1U & ((0x1fU == (IData)(vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg))
                                     ? (IData)(vlSelfRef.jtag_tap_controller__DOT__bypass_reg)
                                     : (IData)(vlSelfRef.jtag_tap_controller__DOT__dr_shift_reg)));
    __Vtableidx1 = (((IData)(vlSelfRef.tms) << 4U) 
                    | (IData)(vlSelfRef.jtag_tap_controller__DOT__state));
    vlSelfRef.jtag_tap_controller__DOT__next_state 
        = Vjtag_tap_controller__ConstPool__TABLE_h9f6336a8_0
        [__Vtableidx1];
    __Vtableidx2 = vlSelfRef.jtag_tap_controller__DOT__ir_hold_reg;
    jtag_tap_controller__DOT__current_dr_length = Vjtag_tap_controller__ConstPool__TABLE_h3056bfd2_0
        [__Vtableidx2];
    vlSelfRef.dr_length = jtag_tap_controller__DOT__current_dr_length;
}

VL_ATTR_COLD void Vjtag_tap_controller___024root___eval_stl(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_stl\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
        Vjtag_tap_controller___024root___stl_sequent__TOP__0(vlSelf);
    }
}

VL_ATTR_COLD bool Vjtag_tap_controller___024root___eval_phase__stl(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___eval_phase__stl\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    Vjtag_tap_controller___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = Vjtag_tap_controller___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        Vjtag_tap_controller___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool Vjtag_tap_controller___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vjtag_tap_controller___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ (IData)(Vjtag_tap_controller___024root___trigger_anySet__ico(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

bool Vjtag_tap_controller___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vjtag_tap_controller___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vjtag_tap_controller___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge tck)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @(negedge trst_n)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 2U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 2 is active: @(negedge tck)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vjtag_tap_controller___024root___ctor_var_reset(Vjtag_tap_controller___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vjtag_tap_controller___024root___ctor_var_reset\n"); );
    Vjtag_tap_controller__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    vlSelf->tck = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6569849850908635776ull);
    vlSelf->tms = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17214653973820629263ull);
    vlSelf->tdi = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5932740720198680006ull);
    vlSelf->tdo = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 18330757414367728858ull);
    vlSelf->trst_n = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 18137605539201232597ull);
    vlSelf->ir_value = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 6834391164134167251ull);
    vlSelf->ir_capture = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2425339358459725965ull);
    vlSelf->ir_shift = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 18134202648561527815ull);
    vlSelf->ir_update = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6470278823567192489ull);
    vlSelf->dr_capture_data = VL_SCOPED_RAND_RESET_Q(64, __VscopeHash, 6063609987893359224ull);
    vlSelf->dr_shift_in = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 849818146662338704ull);
    vlSelf->dr_shift_out = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 10714348414628600196ull);
    vlSelf->dr_capture = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1815183306986934129ull);
    vlSelf->dr_shift = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16091125206883183653ull);
    vlSelf->dr_update = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14639235287923892456ull);
    vlSelf->dr_length = VL_SCOPED_RAND_RESET_I(7, __VscopeHash, 17896273574699087489ull);
    vlSelf->jtag_tap_controller__DOT__state = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 3822662466220977674ull);
    vlSelf->jtag_tap_controller__DOT__next_state = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 8969961444454457585ull);
    vlSelf->jtag_tap_controller__DOT__ir_shift_reg = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 11712325238575548098ull);
    vlSelf->jtag_tap_controller__DOT__ir_hold_reg = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 3579469408817087651ull);
    vlSelf->jtag_tap_controller__DOT__dr_shift_reg = VL_SCOPED_RAND_RESET_Q(64, __VscopeHash, 5383757449779872470ull);
    vlSelf->jtag_tap_controller__DOT__bypass_reg = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13885039785523975985ull);
    vlSelf->__Vdly__jtag_tap_controller__DOT__ir_shift_reg = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 15247362530839593025ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VicoTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__tck__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9882339438006513255ull);
    vlSelf->__Vtrigprevexpr___TOP__trst_n__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 123103580346115562ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
}
