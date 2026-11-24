package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the CSR instructions (core/zicsr.odin): the cases a
// test program can't check yet because they trap, plus undo.
//
// Each test runs one CSR instruction in machine mode (the reset level)
// unless it says otherwise. mtvec is 0, so an illegal instruction isn't
// handled: the step returns the trap, and the test checks its cause.
// Registers by number: 5 = t0, 6 = t1.

// Encodes a CSR instruction (I-type, SYSTEM opcode), as in the
// diagram in docs encodings#CSR instructions:
//   bits 31..20 csr | 19..15 rs1 (or uimm) | 14..12 kind (funct3) | 11..7 rd | 6..0 opcode
// `kind` picks the instruction: rv.ZICSR_CSRRW, ZICSR_CSRRS, ...
@(private = "file")
csr_instruction :: proc(kind: u32, rd: u32, rs1: u32, csr: u32) -> u32 {
	return csr << 20 | rs1 << 15 | kind << 12 | rd << 7 | rv.OPCODE_SYSTEM
}

// A machine with undo history and `instruction` at the start of RAM,
// where the pc starts. Machine mode, mtvec = 0 (no handler).
@(private = "file")
machine_with :: proc(instruction: u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	machine.cpu.pc = rv.RAM_BASE
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(instruction))
	return machine
}

@(test)
writing_a_read_only_csr_is_illegal :: proc(t: ^testing.T) {
	// csrrw t0, mhartid, t1. mhartid is 0xf14: bits 11..10 = 11, read-
	// only, so the write half makes it illegal, even in machine mode.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 5, 6, rv.CSR_MHARTID))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = 1

	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Illegal_Instruction)
	// A trapping instruction changes nothing: not the pc, and not t0
	// (the read half didn't happen either).
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE) // nothing changed
	testing.expect_value(t, machine.cpu.regs[5], 0)
}

@(test)
unknown_csr_is_illegal_even_without_a_read :: proc(t: ^testing.T) {
	// CSRRW with rd = x0 doesn't read, but the CSR must still exist.
	// 0x7c0 is in a range left for custom CSRs, and this hart has none.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 0, 6, 0x7C0))
	defer rv.machine_destroy(&machine)

	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Illegal_Instruction)
}

@(test)
reading_a_read_only_csr_is_allowed :: proc(t: ^testing.T) {
	// CSRRS with rs1 = x0 doesn't write, so a read-only CSR is fine (csrr).
	// csrr t0, mhartid: 0xf14, bits 11..10 = 11, read-only.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRS, 5, 0, rv.CSR_MHARTID))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[5] = 0xdead // so the read visibly changes t0

	testing.expect(t, rv.machine_step(&machine) == nil) // no trap
	testing.expect_value(t, machine.cpu.regs[5], 0) // hart 0
}

@(test)
swap_with_rd_equal_to_rs1 :: proc(t: ^testing.T) {
	// csrrw t0, mscratch, t0: the old rs1 value is written, rd gets the old CSR.
	// The instruction must read t0 before writing it, or the swap would
	// write the CSR's own value back. Trap handlers use exactly this to
	// swap a register with mscratch.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 5, 5, rv.CSR_MSCRATCH))
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mscratch = 1
	machine.cpu.regs[5] = 2

	testing.expect(t, rv.machine_step(&machine) == nil)
	// Swapped: mscratch = t0's 2, t0 = mscratch's 1.
	testing.expect_value(t, machine.cpu.csr.mscratch, 2)
	testing.expect_value(t, machine.cpu.regs[5], 1)
}

@(test)
undo_restores_the_csr :: proc(t: ^testing.T) {
	// csrrw t0, mscratch, t1: writes a CSR and a register in one step.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 5, 6, rv.CSR_MSCRATCH))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = 99

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.csr.mscratch, 99)

	// The undo record holds the CSR's old value and the register's, so
	// stepping back restores both, and the pc.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mscratch, 0)
	testing.expect_value(t, machine.cpu.regs[5], 0)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE)
}

@(test)
counter_write_is_not_counted_by_its_own_instruction :: proc(t: ^testing.T) {
	// csrw minstret, x6: the next instruction must read exactly x6, not
	// x6 + 1. mcycle, not written, still counts the csrw.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRW, 0, 6, rv.CSR_MINSTRET))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = 100

	// minstret_written stops cpu_step's +1 for this step: exactly 100.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.csr.minstret, 100)
	testing.expect_value(t, machine.cpu.csr.mcycle, 1)

	// The undo record keeps both counters from before the step.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.minstret, 0)
	testing.expect_value(t, machine.cpu.csr.mcycle, 0)
}

@(test)
user_mode_cannot_touch_machine_csrs :: proc(t: ^testing.T) {
	// csrr t0, mstatus (machine level: address bits 9:8 = 3) from user mode.
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRS, 5, 0, rv.CSR_MSTATUS))
	defer rv.machine_destroy(&machine)
	// Set the level directly, as a fixture (user_mode_test.odin gets
	// there the real way, with mret).
	machine.cpu.privilege = .User

	// csr_allowed: 0 >= 3 is false, so Illegal_Instruction before
	// anything is read.
	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Illegal_Instruction)
}

@(test)
user_mode_can_read_the_user_counters :: proc(t: ^testing.T) {
	// csrr t0, instret (user level: address bits 9:8 = 0).
	// instret is the read-only user name of minstret (0xc02).
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRS, 5, 0, rv.CSR_INSTRET))
	defer rv.machine_destroy(&machine)
	machine.cpu.privilege = .User
	testing.expect(t, rv.machine_step(&machine) == nil) // 0 >= 0: allowed
}

@(test)
undo_restores_mstatus_exactly :: proc(t: ^testing.T) {
	// csrrsi zero, mstatus, 8 then undo: mstatus must be back to its reset
	// value, bit for bit (lesson 13 found this: undo used to re-apply the
	// write rules on the way back).
	machine := machine_with(csr_instruction(rv.ZICSR_CSRRSI, 0, 8, rv.CSR_MSTATUS))
	defer rv.machine_destroy(&machine)
	before := machine.cpu.csr.mstatus // 0x1800: MPP = machine

	// csrrsi with uimm 8 sets bit 3: MIE on.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect(t, machine.cpu.csr.mstatus != before)
	// Undo writes the saved value back as it was (csr_restore), without
	// going through csr_write's WARL rules again.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mstatus, before)
}
