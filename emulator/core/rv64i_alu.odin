package rv

// Integer arithmetic on full 64-bit registers: OP-IMM (register and
// immediate) and OP (register and register).
//
// Unsigned u64 arithmetic wraps on overflow, which is exactly what the
// hardware does, so ADD / SUB need no special handling.

FUNCT7_BASE :: 0b000_0000
FUNCT7_ALT :: 0b010_0000 // selects SUB instead of ADD, SRA instead of SRL

bool_to_u64 :: #force_inline proc(condition: bool) -> u64 {
	return 1 if condition else 0
}

// ADDI / SLTI / SLTIU / XORI / ORI / ANDI / SLLI / SRLI / SRAI.
exec_op_imm :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	a := reg_read(cpu, rs1(instruction))
	imm := imm_i(instruction)
	// RV64 shifts use a 6-bit amount; bits 31..26 select SRLI vs SRAI.
	shift_amount := imm & 0x3F
	shift_type := instruction >> 26

	result: u64
	switch funct3(instruction) {
	case 0b000:
		result = a + imm // ADDI
	case 0b010:
		result = bool_to_u64(i64(a) < i64(imm)) // SLTI
	case 0b011:
		result = bool_to_u64(a < imm) // SLTIU (imm is sign-extended first)
	case 0b100:
		result = a ~ imm // XORI
	case 0b110:
		result = a | imm // ORI
	case 0b111:
		result = a & imm // ANDI
	case 0b001:
		if shift_type != 0 {
			return illegal_instruction(instruction)
		}
		result = a << shift_amount // SLLI
	case 0b101:
		switch shift_type {
		case 0b00_0000:
			result = a >> shift_amount // SRLI
		case 0b01_0000:
			result = u64(i64(a) >> shift_amount) // SRAI
		case:
			return illegal_instruction(instruction)
		}
	}

	reg_write(cpu, rd(instruction), result)
	return nil
}

// ADD / SUB / SLL / SLT / SLTU / XOR / SRL / SRA / OR / AND.
// The M extension (MUL, DIV, ...) will also live under this opcode,
// selected by funct7 = 1.
exec_op :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	a := reg_read(cpu, rs1(instruction))
	b := reg_read(cpu, rs2(instruction))
	shift_amount := b & 0x3F

	result: u64
	switch (funct7(instruction) << 3) | funct3(instruction) {
	case (FUNCT7_BASE << 3) | 0b000:
		result = a + b // ADD
	case (FUNCT7_ALT << 3) | 0b000:
		result = a - b // SUB
	case (FUNCT7_BASE << 3) | 0b001:
		result = a << shift_amount // SLL
	case (FUNCT7_BASE << 3) | 0b010:
		result = bool_to_u64(i64(a) < i64(b)) // SLT
	case (FUNCT7_BASE << 3) | 0b011:
		result = bool_to_u64(a < b) // SLTU
	case (FUNCT7_BASE << 3) | 0b100:
		result = a ~ b // XOR
	case (FUNCT7_BASE << 3) | 0b101:
		result = a >> shift_amount // SRL
	case (FUNCT7_ALT << 3) | 0b101:
		result = u64(i64(a) >> shift_amount) // SRA
	case (FUNCT7_BASE << 3) | 0b110:
		result = a | b // OR
	case (FUNCT7_BASE << 3) | 0b111:
		result = a & b // AND
	case:
		return illegal_instruction(instruction)
	}

	reg_write(cpu, rd(instruction), result)
	return nil
}
