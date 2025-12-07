// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vjtag_tap_controller__pch.h"

//============================================================
// Constructors

Vjtag_tap_controller::Vjtag_tap_controller(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vjtag_tap_controller__Syms(contextp(), _vcname__, this)}
    , tck{vlSymsp->TOP.tck}
    , trst_n{vlSymsp->TOP.trst_n}
    , tms{vlSymsp->TOP.tms}
    , tdi{vlSymsp->TOP.tdi}
    , tdo{vlSymsp->TOP.tdo}
    , ir_value{vlSymsp->TOP.ir_value}
    , ir_capture{vlSymsp->TOP.ir_capture}
    , ir_shift{vlSymsp->TOP.ir_shift}
    , ir_update{vlSymsp->TOP.ir_update}
    , dr_shift_in{vlSymsp->TOP.dr_shift_in}
    , dr_shift_out{vlSymsp->TOP.dr_shift_out}
    , dr_capture{vlSymsp->TOP.dr_capture}
    , dr_shift{vlSymsp->TOP.dr_shift}
    , dr_update{vlSymsp->TOP.dr_update}
    , dr_length{vlSymsp->TOP.dr_length}
    , dr_capture_data{vlSymsp->TOP.dr_capture_data}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vjtag_tap_controller::Vjtag_tap_controller(const char* _vcname__)
    : Vjtag_tap_controller(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vjtag_tap_controller::~Vjtag_tap_controller() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vjtag_tap_controller___024root___eval_debug_assertions(Vjtag_tap_controller___024root* vlSelf);
#endif  // VL_DEBUG
void Vjtag_tap_controller___024root___eval_static(Vjtag_tap_controller___024root* vlSelf);
void Vjtag_tap_controller___024root___eval_initial(Vjtag_tap_controller___024root* vlSelf);
void Vjtag_tap_controller___024root___eval_settle(Vjtag_tap_controller___024root* vlSelf);
void Vjtag_tap_controller___024root___eval(Vjtag_tap_controller___024root* vlSelf);

void Vjtag_tap_controller::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vjtag_tap_controller::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vjtag_tap_controller___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vjtag_tap_controller___024root___eval_static(&(vlSymsp->TOP));
        Vjtag_tap_controller___024root___eval_initial(&(vlSymsp->TOP));
        Vjtag_tap_controller___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vjtag_tap_controller___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vjtag_tap_controller::eventsPending() { return false; }

uint64_t Vjtag_tap_controller::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vjtag_tap_controller::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vjtag_tap_controller___024root___eval_final(Vjtag_tap_controller___024root* vlSelf);

VL_ATTR_COLD void Vjtag_tap_controller::final() {
    Vjtag_tap_controller___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vjtag_tap_controller::hierName() const { return vlSymsp->name(); }
const char* Vjtag_tap_controller::modelName() const { return "Vjtag_tap_controller"; }
unsigned Vjtag_tap_controller::threads() const { return 1; }
void Vjtag_tap_controller::prepareClone() const { contextp()->prepareClone(); }
void Vjtag_tap_controller::atClone() const {
    contextp()->threadPoolpOnClone();
}
