package rv

// FENCE and the SYSTEM opcode (ECALL, EBREAK; CSR instructions come in
// the Zicsr milestone).

ENCODING_ECALL :: u32(0x0000_0073)
ENCODING_EBREAK :: u32(0x0010_0073)

// FENCE / FENCE.I. This emulator runs one hart and executes memory
// operations in order, so ordering fences have nothing to do.
exec_misc_mem :: proc(instruction: u32) -> Step_Result {
	switch funct3(instruction) {
	case 0b000, 0b001:
		return nil
	}
	return illegal_instruction(instruction)
}

// ECALL raises an environment-call trap (the system-call mechanism).
// EBREAK raises a breakpoint trap; test programs use it to stop.
// The hart always runs in machine mode for now, hence Ecall_From_M_Mode.
exec_system :: proc(instruction: u32) -> Step_Result {
	switch instruction {
	case ENCODING_ECALL:
		return trap_make(.Ecall_From_M_Mode, 0)
	case ENCODING_EBREAK:
		return trap_make(.Breakpoint, 0)
	}
	return illegal_instruction(instruction)
}
