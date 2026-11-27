package rv

// The M extension: integer multiply and divide (R-type, funct7 = 1).
//
//   OP (64-bit):     MUL MULH MULHSU MULHU DIV DIVU REM REMU
//   OP-32 (32-bit):  MULW DIVW DIVUW REMW REMUW
//
// Multiplication: the full product of two 64-bit numbers is 128 bits. MUL
// gives the low 64 (the same for signed and unsigned numbers); MULH,
// MULHSU and MULHU give the high 64, reading the operands as signed x
// signed, signed x unsigned and unsigned x unsigned.
//
// Division never traps. The spec defines a result for the two cases where
// division has no answer, so software can check afterwards if it cares:
//
//                          DIV / DIVU quotient      REM / REMU remainder
//   divide by zero         all ones (-1 / 2^64-1)   the dividend
//   overflow (DIV only):   the dividend (-2^63)     0
//   -2^63 / -1
//
// Both choices keep dividend = divisor * quotient + remainder true. Signed
// division rounds toward zero, as in C: -7 / 2 = -3, remainder -1.
//
// The W forms work on the low 32 bits and sign-extend the 32-bit result,
// like the other W instructions.

FUNCT7_MULDIV :: 0b000_0001

// MUL ... REMU (called from exec_op when funct7 = 1).
exec_muldiv :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Muldiv)
	}
	a := reg_read(cpu, rs1(instruction))
	b := reg_read(cpu, rs2(instruction))

	result: u64
	switch funct3(instruction) {
	case 0b000:
		result = a * b // MUL
	case 0b001:
		result = u64((i128(i64(a)) * i128(i64(b))) >> 64) // MULH
	case 0b010:
		result = u64((i128(i64(a)) * i128(b)) >> 64) // MULHSU
	case 0b011:
		result = u64((u128(a) * u128(b)) >> 64) // MULHU
	case 0b100:
		result = u64(divide_signed(i64(a), i64(b))) // DIV
	case 0b101:
		result = divide_unsigned(a, b) // DIVU
	case 0b110:
		result = u64(remainder_signed(i64(a), i64(b))) // REM
	case 0b111:
		result = remainder_unsigned(a, b) // REMU
	}
	reg_write(cpu, rd(instruction), result)
	return nil
}

// MULW / DIVW / DIVUW / REMW / REMUW (called from exec_op_32 when
// funct7 = 1).
exec_muldiv_32 :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Muldiv_32)
	}
	a := reg_read(cpu, rs1(instruction))
	b := reg_read(cpu, rs2(instruction))
	a32, b32 := i32(u32(a)), i32(u32(b))

	result: u64
	switch funct3(instruction) {
	case 0b000:
		result = sign_extend_32(a * b) // MULW
	case 0b100:
		result = u64(i64(divide_signed_32(a32, b32))) // DIVW
	case 0b101:
		result = sign_extend_32(u64(divide_unsigned_32(u32(a32), u32(b32)))) // DIVUW
	case 0b110:
		result = u64(i64(remainder_signed_32(a32, b32))) // REMW
	case 0b111:
		result = sign_extend_32(u64(remainder_unsigned_32(u32(a32), u32(b32)))) // REMUW
	case:
		return illegal_instruction(instruction)
	}
	reg_write(cpu, rd(instruction), result)
	return nil
}

// The special cases from the table at the top, then normal division
// (Odin's / and % round toward zero, like RISC-V).

@(private = "file")
divide_signed :: proc(a: i64, b: i64) -> i64 {
	if b == 0 {
		return -1
	}
	if a == min(i64) && b == -1 {
		return a
	}
	return a / b
}

@(private = "file")
remainder_signed :: proc(a: i64, b: i64) -> i64 {
	if b == 0 {
		return a
	}
	if a == min(i64) && b == -1 {
		return 0
	}
	return a % b
}

@(private = "file")
divide_unsigned :: proc(a: u64, b: u64) -> u64 {
	return max(u64) if b == 0 else a / b
}

@(private = "file")
remainder_unsigned :: proc(a: u64, b: u64) -> u64 {
	return a if b == 0 else a % b
}

@(private = "file")
divide_signed_32 :: proc(a: i32, b: i32) -> i32 {
	if b == 0 {
		return -1
	}
	if a == min(i32) && b == -1 {
		return a
	}
	return a / b
}

@(private = "file")
remainder_signed_32 :: proc(a: i32, b: i32) -> i32 {
	if b == 0 {
		return a
	}
	if a == min(i32) && b == -1 {
		return 0
	}
	return a % b
}

@(private = "file")
divide_unsigned_32 :: proc(a: u32, b: u32) -> u32 {
	return max(u32) if b == 0 else a / b
}

@(private = "file")
remainder_unsigned_32 :: proc(a: u32, b: u32) -> u32 {
	return a if b == 0 else a % b
}
