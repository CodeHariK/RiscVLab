package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the CSR instructions (core/zicsr.odin): the cases a
// test program can't check yet because they trap, plus undo.

// Encodes a CSR instruction (I-type, SYSTEM opcode).
@(private = "file")
csr_instruction :: proc(kind: u32, rd: u32, rs1: u32, csr: u32) -> u32 {
	return csr << 20 | rs1 << 15 | kind << 12 | rd << 7 | rv.OPCODE_SYSTEM
}

// A machine with undo history and `instruction` at the start of RAM.
@(private = "file")
machine_with :: proc(instruction: u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	machine.cpu.pc = rv.RAM_BASE
	rv.bus_store(&machine.bus, rv.RAM_BASE, 4, u64(instruction))
	return machine
}

@(test)
writing_a_read_only_csr_is_illegal :: proc(t: ^testing.T) {
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 5, 6, rv.CSR_MHARTID))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = 1

	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Illegal_Instruction)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE) // nothing changed
	testing.expect_value(t, machine.cpu.regs[5], 0)
}

@(test)
unknown_csr_is_illegal_even_without_a_read :: proc(t: ^testing.T) {
	// CSRRW with rd = x0 doesn't read, but the CSR must still exist.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 0, 6, 0x7C0))
	defer rv.machine_destroy(&machine)

	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Illegal_Instruction)
}

@(test)
reading_a_read_only_csr_is_allowed :: proc(t: ^testing.T) {
	// CSRRS with rs1 = x0 doesn't write, so a read-only CSR is fine (csrr).
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRS, 5, 0, rv.CSR_MISA))
	defer rv.machine_destroy(&machine)

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.regs[5], rv.MISA_VALUE)
}

@(test)
swap_with_rd_equal_to_rs1 :: proc(t: ^testing.T) {
	// csrrw t0, mscratch, t0: the old rs1 value is written, rd gets the old CSR.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 5, 5, rv.CSR_MSCRATCH))
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mscratch = 1
	machine.cpu.regs[5] = 2

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.csr.mscratch, 2)
	testing.expect_value(t, machine.cpu.regs[5], 1)
}

@(test)
undo_restores_the_csr :: proc(t: ^testing.T) {
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 5, 6, rv.CSR_MSCRATCH))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = 99

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.csr.mscratch, 99)

	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mscratch, 0)
	testing.expect_value(t, machine.cpu.regs[5], 0)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE)
}

@(test)
undo_restores_mstatus_exactly :: proc(t: ^testing.T) {
	// csrrsi zero, mstatus, 8 then undo: mstatus must be back to its reset
	// value, bit for bit (lesson 13 found this: undo used to re-apply the
	// write rules on the way back).
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRSI, 0, 8, rv.CSR_MSTATUS))
	defer rv.machine_destroy(&machine)
	before := machine.cpu.csr.mstatus

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect(t, machine.cpu.csr.mstatus != before)
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mstatus, before)
}
