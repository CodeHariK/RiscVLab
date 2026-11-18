package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the M extension (core/rv64m.odin): the special cases of
// the spec's division table, the high-half multiplies, and the W forms.
// The riscv-tests rv64um suite covers the ordinary cases.

@(private = "file")
Muldiv :: enum u32 {
	Mul    = 0b000,
	Mulh   = 0b001,
	Mulhsu = 0b010,
	Mulhu  = 0b011,
	Div    = 0b100,
	Divu   = 0b101,
	Rem    = 0b110,
	Remu   = 0b111,
}

// Runs one M instruction (rd = x5, rs1 = x6, rs2 = x7) on `a` and `b`
// and returns rd. `word` selects the W form (OP-32 opcode).
@(private = "file")
run :: proc(kind: Muldiv, a: u64, b: u64, word := false) -> u64 {
	opcode: u32 = rv.OPCODE_OP_32 if word else rv.OPCODE_OP
	instruction := rv.FUNCT7_MULDIV << 25 | 7 << 20 | 6 << 15 | u32(kind) << 12 | 5 << 7 | opcode
	machine := rv.machine_create(64 * 1024, 0)
	defer rv.machine_destroy(&machine)
	machine.cpu.pc = rv.RAM_BASE
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(instruction))
	machine.cpu.regs[6] = a
	machine.cpu.regs[7] = b
	rv.machine_step(&machine)
	return machine.cpu.regs[5]
}

MIN_I64 :: u64(0x8000_0000_0000_0000)
ALL_ONES :: max(u64)

@(test)
divide_by_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, run(.Div, 7, 0), ALL_ONES) // -1
	testing.expect_value(t, run(.Divu, 7, 0), ALL_ONES) // 2^64 - 1
	testing.expect_value(t, run(.Rem, 7, 0), 7) // the dividend
	testing.expect_value(t, run(.Remu, 7, 0), 7)
}

@(test)
signed_overflow :: proc(t: ^testing.T) {
	// -2^63 / -1 doesn't fit: the quotient is the dividend, remainder 0.
	testing.expect_value(t, run(.Div, MIN_I64, ALL_ONES), MIN_I64)
	testing.expect_value(t, run(.Rem, MIN_I64, ALL_ONES), 0)
}

@(test)
division_rounds_toward_zero :: proc(t: ^testing.T) {
	minus_seven := transmute(u64)i64(-7)
	testing.expect_value(t, run(.Div, minus_seven, 2), transmute(u64)i64(-3)) // -7 / 2 = -3
	testing.expect_value(t, run(.Rem, minus_seven, 2), ALL_ONES) // remainder -1
}

@(test)
high_half_multiplies :: proc(t: ^testing.T) {
	// -1 x -1 = 1: high half 0 when both are signed.
	testing.expect_value(t, run(.Mulh, ALL_ONES, ALL_ONES), 0)
	// (2^64 - 1) x (2^64 - 1) unsigned = 2^128 - 2^65 + 1: high half 2^64 - 2.
	testing.expect_value(t, run(.Mulhu, ALL_ONES, ALL_ONES), ALL_ONES - 1)
	// -1 (signed) x (2^64 - 1) (unsigned) = -(2^64 - 1): high half -1.
	testing.expect_value(t, run(.Mulhsu, ALL_ONES, ALL_ONES), ALL_ONES)
	testing.expect_value(t, run(.Mul, ALL_ONES, ALL_ONES), 1) // low half
}

@(test)
word_forms :: proc(t: ^testing.T) {
	// MULW: 0x10000 x 0x10000 = 2^32, low 32 bits 0.
	testing.expect_value(t, run(.Mul, 0x10000, 0x10000, word = true), 0)
	// DIVW by zero: -1, sign-extended.
	testing.expect_value(t, run(.Div, 7, 0, word = true), ALL_ONES)
	// DIVUW by zero: 2^32 - 1, then sign-extended: all ones.
	testing.expect_value(t, run(.Divu, 7, 0, word = true), ALL_ONES)
	// DIVW overflow: -2^31 / -1 = -2^31, sign-extended.
	testing.expect_value(t, run(.Div, 0x8000_0000, ALL_ONES, word = true), 0xffff_ffff_8000_0000)
	// Only the low 32 bits of the operands count: 0x1_0000_0006 / 3 = 2.
	testing.expect_value(t, run(.Div, 0x1_0000_0006, 3, word = true), 2)
	// REMUW by zero: the dividend's low 32 bits, sign-extended.
	testing.expect_value(t, run(.Remu, 0x8000_0001, 0, word = true), 0xffff_ffff_8000_0001)
}

@(test)
mulhsu_and_mulhu_on_word_opcode_are_illegal :: proc(t: ^testing.T) {
	// OP-32 has no MULH* forms: funct3 001..011 with funct7 = 1 is illegal.
	instruction := rv.FUNCT7_MULDIV << 25 | 7 << 20 | 6 << 15 | 0b001 << 12 | 5 << 7 | rv.OPCODE_OP_32
	machine := rv.machine_create(64 * 1024, 0)
	defer rv.machine_destroy(&machine)
	machine.cpu.pc = rv.RAM_BASE
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(instruction))
	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Illegal_Instruction)
}
