package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the A extension (core/rv64a.odin): LR / SC reservations,
// alignment traps, .W sign extension, and undo of the reservation. The
// riscv-tests rv64ua suite covers the ordinary cases.
//
// Registers by number: x5 = t0 (rd: the result), x6 = t1 (rs1: the
// address), x7 = t2 (rs2: the value). mtvec is 0 unless a test sets it,
// so a trap comes back from machine_step for the test to check.

@(private = "file")
DATA :: rv.RAM_BASE + 0x100 // the memory the atomics work on (8-byte aligned)

// An AMO instruction: rd = x5, rs1 = x6 (the address), rs2 = x7.
//   bits 31..27 operation (funct5) | 26 aq | 25 rl | 24..20 rs2 | 19..15 rs1
//   | 14..12 width (010 .w, 011 .d) | 11..7 rd | 6..0 opcode
// aq / rl are ordering hints (docs: memory-ordering); this one-hart
// emulator ignores them.
@(private = "file")
amo :: proc(operation: u32, double: bool, acquire := false, release := false) -> u32 {
	width: u32 = rv.AMO_DOUBLE if double else rv.AMO_WORD
	order := u32(acquire) << 1 | u32(release)
	return operation << 27 | order << 25 | 7 << 20 | 6 << 15 | width << 12 | 5 << 7 | rv.OPCODE_AMO
}

// A machine running `program` from the start of RAM, x6 = DATA, with
// undo history. DATA starts as 0.
@(private = "file")
machine_running :: proc(program: ..u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	machine.cpu.pc = rv.RAM_BASE
	for instruction, index in program {
		rv.machine_store(&machine, rv.RAM_BASE + u64(index) * 4, 4, u64(instruction))
	}
	machine.cpu.regs[6] = DATA
	return machine
}

// LR has no rs2: the field must be 0.
@(private = "file")
LR_D :: proc() -> u32 { return amo(rv.AMO_LR, true) &~ (0x1f << 20) }
@(private = "file")
SC_D :: proc() -> u32 { return amo(rv.AMO_SC, true) }

@(test)
lr_then_sc_succeeds :: proc(t: ^testing.T) {
	machine := machine_running(LR_D(), SC_D())
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, DATA, 8, 0x11)
	machine.cpu.regs[7] = 0x22

	// lr.d: load DATA and reserve it (8 bytes at DATA).
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[5], 0x11) // loaded
	// sc.d: the reservation holds (same address and size, nothing in
	// between), so it stores x7 and writes 0, "success", to rd.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[5], 0) // success
	value, _ := rv.machine_load(&machine, DATA, 8)
	testing.expect_value(t, value, 0x22)
	testing.expect(t, !machine.cpu.reservation.valid) // used up
}

@(test)
sc_without_lr_fails :: proc(t: ^testing.T) {
	machine := machine_running(SC_D())
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[7] = 0x22

	// No lr before it, so no reservation: the sc doesn't store, and
	// writes 1, "failure", to rd. (Not a trap: code retries in a loop.)
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[5], 1) // failure
	value, _ := rv.machine_load(&machine, DATA, 8)
	testing.expect_value(t, value, 0) // memory unchanged
}

@(test)
faulting_sc_changes_nothing :: proc(t: ^testing.T) {
	// LR, then an SC to an address outside RAM with no handler: the SC
	// stops the machine, and must leave the reservation (and x5) alone,
	// since a step that stops the machine isn't recorded for undo.
	machine := machine_running(LR_D(), SC_D())
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // lr: a valid reservation
	// Move the reservation (and the sc's address) outside RAM, so the
	// sc's reservation check would pass but bus_is_ram fails.
	machine.cpu.reservation.address = 0x1000 // as if LR had reserved there
	machine.cpu.regs[6] = 0x1000
	before := machine.cpu.reservation
	x5 := machine.cpu.regs[5]

	// The sc faults: it must check everything before changing anything,
	// so the reservation isn't used up and rd isn't written.
	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Store_Access_Fault)
	testing.expect(t, machine.cpu.reservation == before)
	testing.expect_value(t, machine.cpu.regs[5], x5)
}

@(test)
second_sc_fails :: proc(t: ^testing.T) {
	// lr, sc, sc: the first sc succeeds and uses the reservation up
	// (every sc clears it, success or not), so the second has none.
	machine := machine_running(LR_D(), SC_D(), SC_D())
	defer rv.machine_destroy(&machine)
	for _ in 0 ..< 3 {
		rv.machine_step(&machine)
	}
	testing.expect_value(t, machine.cpu.regs[5], 1) // the second sc failed
}

@(test)
trap_clears_the_reservation :: proc(t: ^testing.T) {
	// LR, then an ecall into a handler that is the SC itself.
	// trap_enter clears the reservation: the handler may have changed the
	// memory, so an sc after a trap must not succeed on a stale lr.
	ecall: u32 = 0x0000_0073
	machine := machine_running(LR_D(), ecall, SC_D())
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mtvec = rv.RAM_BASE + 8 // the sc's address

	rv.machine_step(&machine) // lr
	testing.expect(t, machine.cpu.reservation.valid)
	rv.machine_step(&machine) // ecall -> handler
	testing.expect(t, !machine.cpu.reservation.valid)
	rv.machine_step(&machine) // sc
	testing.expect_value(t, machine.cpu.regs[5], 1)
}

@(test)
misaligned_atomics_trap :: proc(t: ^testing.T) {
	// amoadd.w on DATA + 2: atomics must be naturally aligned (a word on
	// a multiple of 4), unlike ordinary loads and stores here.
	machine := machine_running(amo(rv.AMO_ADD, false))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = DATA + 2

	// An AMO writes, so it is a store fault; mtval (trap.value) holds the
	// address.
	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Store_Address_Misaligned)
	testing.expect_value(t, trap.value, DATA + 2)
}

@(test)
word_amo_sign_extends_and_compares_32_bits :: proc(t: ^testing.T) {
	// The .w forms work on 32 bits: the old value comes back
	// sign-extended to 64, and the operation only sees the low 32 bits.
	machine := machine_running(amo(rv.AMO_ADD, false), amo(rv.AMO_MINU, false))
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, DATA, 4, 0x8000_0000) // bit 31 set: negative as a word
	machine.cpu.regs[7] = 1

	rv.machine_step(&machine) // amoadd.w
	testing.expect_value(t, machine.cpu.regs[5], 0xffff_ffff_8000_0000) // old value, sign-extended
	value, _ := rv.machine_load(&machine, DATA, 4)
	testing.expect_value(t, value, 0x8000_0001)

	machine.cpu.regs[7] = 0xffff_ffff_0000_0002 // only the low 32 bits count: 2
	rv.machine_step(&machine) // amominu.w
	value, _ = rv.machine_load(&machine, DATA, 4)
	testing.expect_value(t, value, 2) // 2 < 0x80000001 unsigned
}

@(test)
step_back_restores_the_reservation :: proc(t: ^testing.T) {
	// The reservation is machine state too: reservation_set saves its
	// old value in the undo record the first time a step changes it.
	machine := machine_running(LR_D(), SC_D())
	defer rv.machine_destroy(&machine)

	rv.machine_step(&machine) // lr: reserve
	rv.machine_step(&machine) // sc: succeed, reservation used up
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect(t, machine.cpu.reservation.valid) // back as after the lr
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect(t, !machine.cpu.reservation.valid)
}
