package rv

// Trap causes, numbered as in the privileged spec's `mcause` table:
// exceptions (caused by an instruction), then interrupts, which have bit
// 63 set (interrupts.odin).
Trap_Cause :: enum u64 {
	Instruction_Address_Misaligned = 0,
	Instruction_Access_Fault       = 1,
	Illegal_Instruction            = 2,
	Breakpoint                     = 3,
	Load_Address_Misaligned        = 4,
	Load_Access_Fault              = 5,
	Store_Address_Misaligned       = 6,
	Store_Access_Fault             = 7,
	Ecall_From_U_Mode              = 8,
	Ecall_From_S_Mode              = 9,
	Ecall_From_M_Mode              = 11,
	// Interrupts: bit 63, then the interrupt's number (its bit in mie / mip).
	Machine_Software_Interrupt     = INTERRUPT_BIT | 3,
	Machine_Timer_Interrupt        = INTERRUPT_BIT | 7,
	Machine_External_Interrupt     = INTERRUPT_BIT | 11,
}

// mcause bit 63: the trap was an interrupt, not an exception. The rest
// of mcause is the number: the exception code, or the interrupt's bit in
// mie / mip.
//
//   cause                     mcause               bit 63  kind
//   Illegal_Instruction       0x2                  0       exception
//   Ecall_From_M_Mode         0xb                  0       exception
//   Machine_Timer_Interrupt   0x8000000000000007   1       interrupt
INTERRUPT_BIT :: u64(1) << 63

// True if the trap is an interrupt (from outside: the timer, a device)
// rather than an exception (caused by the instruction). They are taken
// the same way, except where the spec tells them apart: vectored mtvec
// (trap_enter), and mepc pointing at an instruction that hasn't run.
trap_is_interrupt :: proc(cause: Trap_Cause) -> bool {
	return u64(cause) & INTERRUPT_BIT != 0
}

// The cause's number without the interrupt bit: 7 for the timer
// interrupt (mcause 0x8000000000000007), 2 for Illegal_Instruction.
trap_cause_number :: #force_inline proc(cause: Trap_Cause) -> u64 {
	return u64(cause) &~ INTERRUPT_BIT
}

// A raised exception: why it happened, plus the value that will go into
// the `mtval` CSR (the faulting address, or the bad instruction bits).
Trap :: struct {
	cause: Trap_Cause,
	value: u64,
}

// Outcome of executing one instruction: nil when it completed normally,
// otherwise the trap it raised.
Step_Result :: Maybe(Trap)

trap_make :: #force_inline proc(cause: Trap_Cause, value: u64) -> Trap {
	return Trap{cause = cause, value = value}
}

// Shorthand for the most common trap: an encoding we don't recognise.
// `mtval` gets the instruction bits, as the spec recommends.
illegal_instruction :: #force_inline proc(instruction: u32) -> Step_Result {
	return trap_make(.Illegal_Instruction, u64(instruction))
}
