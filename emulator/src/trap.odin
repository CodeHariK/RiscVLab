package emulator

// Synchronous exception causes, numbered as in the privileged spec's
// `mcause` table. Interrupt causes come later with the CLINT and PLIC.
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
