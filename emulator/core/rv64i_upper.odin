package rv

// LUI and AUIPC: build large constants and PC-relative addresses.
// Together with a following ADDI / JALR they reach any 32-bit offset.

// LUI rd, imm: rd = imm << 12 (sign-extended to 64 bits).
exec_lui :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	reg_write(cpu, rd(instruction), imm_u(instruction))
	return nil
}

// AUIPC rd, imm: rd = pc + (imm << 12).
exec_auipc :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	reg_write(cpu, rd(instruction), cpu.pc + imm_u(instruction))
	return nil
}
