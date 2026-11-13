package rv

// RV64-only "word" instructions (the W suffix): compute on the low 32 bits
// and sign-extend the 32-bit result to 64 bits. Compilers use them for C
// `int` arithmetic. Shift amounts are 5 bits here, not 6.

// ADDIW / SLLIW / SRLIW / SRAIW.
exec_op_imm_32 :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	a := reg_read(cpu, rs1(instruction))

	// ADDIW: funct3 = 000, and the upper bits are all immediate.
	if funct3(instruction) == 0b000 {
		reg_write(cpu, rd(instruction), sign_extend_32(a + imm_i(instruction)))
		return nil
	}

	// The shifts: the 5-bit shift amount sits where rs2 would be,
	// and funct7 picks logical or arithmetic.
	shift_amount := rs2(instruction)

	result: u64
	switch (funct7(instruction) << 3) | funct3(instruction) {
	case (FUNCT7_BASE << 3) | 0b001:
		result = sign_extend_32(u64(u32(a) << shift_amount)) // SLLIW
	case (FUNCT7_BASE << 3) | 0b101:
		result = sign_extend_32(u64(u32(a) >> shift_amount)) // SRLIW
	case (FUNCT7_ALT << 3) | 0b101:
		result = u64(i64(i32(u32(a)) >> shift_amount)) // SRAIW
	case:
		return illegal_instruction(instruction)
	}

	reg_write(cpu, rd(instruction), result)
	return nil
}

// ADDW / SUBW / SLLW / SRLW / SRAW.
exec_op_32 :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	a := reg_read(cpu, rs1(instruction))
	b := reg_read(cpu, rs2(instruction))
	shift_amount := b & 0x1F

	result: u64
	switch (funct7(instruction) << 3) | funct3(instruction) {
	case (FUNCT7_BASE << 3) | 0b000:
		result = sign_extend_32(a + b) // ADDW
	case (FUNCT7_ALT << 3) | 0b000:
		result = sign_extend_32(a - b) // SUBW
	case (FUNCT7_BASE << 3) | 0b001:
		result = sign_extend_32(u64(u32(a) << shift_amount)) // SLLW
	case (FUNCT7_BASE << 3) | 0b101:
		result = sign_extend_32(u64(u32(a) >> shift_amount)) // SRLW
	case (FUNCT7_ALT << 3) | 0b101:
		result = u64(i64(i32(u32(a)) >> shift_amount)) // SRAW
	case:
		return illegal_instruction(instruction)
	}

	reg_write(cpu, rd(instruction), result)
	return nil
}
