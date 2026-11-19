package rv

// Field extractors for the 32-bit instruction formats (docs: encodings).
//
//   31        25 24   20 19   15 14  12 11         7 6      0
//  |   funct7   |  rs2  |  rs1  |funct3|     rd     | opcode |  R-type
//  |       imm[11:0]    |  rs1  |funct3|     rd     | opcode |  I-type
//  | imm[11:5]  |  rs2  |  rs1  |funct3|  imm[4:0]  | opcode |  S-type
//  |imm[12|10:5]|  rs2  |  rs1  |funct3| imm[4:1|11]| opcode |  B-type
//  |             imm[31:12]            |     rd     | opcode |  U-type
//  |     imm[20|10:1|11|19:12]         |     rd     | opcode |  J-type
//
// Register and funct fields sit in the same place in every format, which is
// why decoding RISC-V is cheap. Immediates are returned sign-extended to
// 64 bits (as u64, so adding them to registers wraps like the hardware).

opcode :: #force_inline proc(instruction: u32) -> u32 {
	return instruction & 0x7F
}

rd :: #force_inline proc(instruction: u32) -> u32 {
	return (instruction >> 7) & 0x1F
}

rs1 :: #force_inline proc(instruction: u32) -> u32 {
	return (instruction >> 15) & 0x1F
}

rs2 :: #force_inline proc(instruction: u32) -> u32 {
	return (instruction >> 20) & 0x1F
}

funct3 :: #force_inline proc(instruction: u32) -> u32 {
	return (instruction >> 12) & 0x7
}

funct7 :: #force_inline proc(instruction: u32) -> u32 {
	return instruction >> 25
}

// Sign-extends a 32-bit value to 64 bits. Used by every "word" (*W)
// instruction, which computes on 32 bits and sign-extends the result.
sign_extend_32 :: #force_inline proc(value: u64) -> u64 {
	return u64(i64(i32(u32(value))))
}

// The trick used below: put the immediate's top bit at bit 31 of an i32,
// then arithmetic-shift right, so the sign bit copies itself downwards.

imm_i :: #force_inline proc(instruction: u32) -> u64 {
	return u64(i64(i32(instruction) >> 20))
}

imm_s :: #force_inline proc(instruction: u32) -> u64 {
	high := i32(instruction & 0xFE00_0000) >> 20 // imm[11:5]
	low := i32((instruction >> 7) & 0x1F) // imm[4:0]
	return u64(i64(high | low))
}

imm_b :: #force_inline proc(instruction: u32) -> u64 {
	bit_12 := i32(instruction & 0x8000_0000) >> 19
	bit_11 := i32((instruction & 0x80) << 4)
	bits_10_5 := i32((instruction >> 20) & 0x7E0)
	bits_4_1 := i32((instruction >> 7) & 0x1E)
	return u64(i64(bit_12 | bit_11 | bits_10_5 | bits_4_1))
}

imm_u :: #force_inline proc(instruction: u32) -> u64 {
	return u64(i64(i32(instruction & 0xFFFF_F000)))
}

imm_j :: #force_inline proc(instruction: u32) -> u64 {
	bit_20 := i32(instruction & 0x8000_0000) >> 11
	bits_19_12 := i32(instruction & 0x000F_F000)
	bit_11 := i32((instruction >> 9) & 0x800)
	bits_10_1 := i32((instruction >> 20) & 0x7FE)
	return u64(i64(bit_20 | bits_19_12 | bit_11 | bits_10_1))
}
