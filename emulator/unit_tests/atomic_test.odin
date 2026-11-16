package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the A extension (core/rv64a.odin): LR / SC reservations,
// alignment traps, .W sign extension, and undo of the reservation. The
// riscv-tests rv64ua suite covers the ordinary cases.

@(private = "file")
DATA :: rv.RAM_BASE + 0x100

// An AMO instruction: rd = x5, rs1 = x6 (the address), rs2 = x7.
@(private = "file")
amo :: proc(operation: u32, double: bool, acquire := false, release := false) -> u32 {
	width: u32 = rv.AMO_DOUBLE if double else rv.AMO_WORD
	order := u32(acquire) << 1 | u32(release)
	return operation << 27 | order << 25 | 7 << 20 | 6 << 15 | width << 12 | 5 << 7 | rv.OPCODE_AMO
}

// A machine running `program` from the start of RAM, x6 = DATA.
@(private = "file")
machine_running :: proc(program: ..u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	machine.cpu.pc = rv.RAM_BASE
	for instruction, index in program {
		rv.bus_store(&machine.bus, rv.RAM_BASE + u64(index) * 4, 4, u64(instruction))
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
	rv.bus_store(&machine.bus, DATA, 8, 0x11)
	machine.cpu.regs[7] = 0x22

	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[5], 0x11) // loaded
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[5], 0) // success
	value, _ := rv.bus_load(&machine.bus, DATA, 8)
	testing.expect_value(t, value, 0x22)
	testing.expect(t, !machine.cpu.reservation.valid) // used up
}

@(test)
sc_without_lr_fails :: proc(t: ^testing.T) {
	machine := machine_running(SC_D())
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[7] = 0x22

	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[5], 1) // failure
	value, _ := rv.bus_load(&machine.bus, DATA, 8)
	testing.expect_value(t, value, 0) // memory unchanged
}

@(test)
second_sc_fails :: proc(t: ^testing.T) {
	machine := machine_running(LR_D(), SC_D(), SC_D())
	defer rv.machine_destroy(&machine)
	for _ in 0 ..< 3 {
		rv.machine_step(&machine)
	}
	testing.expect_value(t, machine.cpu.regs[5], 1)
}

@(test)
trap_clears_the_reservation :: proc(t: ^testing.T) {
	// LR, then an ecall into a handler that is the SC itself.
	ecall: u32 = 0x0000_0073
	machine := machine_running(LR_D(), ecall, SC_D())
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mtvec = rv.RAM_BASE + 8

	rv.machine_step(&machine) // lr
	testing.expect(t, machine.cpu.reservation.valid)
	rv.machine_step(&machine) // ecall -> handler
	testing.expect(t, !machine.cpu.reservation.valid)
	rv.machine_step(&machine) // sc
	testing.expect_value(t, machine.cpu.regs[5], 1)
}

@(test)
misaligned_atomics_trap :: proc(t: ^testing.T) {
	machine := machine_running(amo(rv.AMO_ADD, false))
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = DATA + 2

	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Store_Address_Misaligned)
	testing.expect_value(t, trap.value, DATA + 2)
}

@(test)
word_amo_sign_extends_and_compares_32_bits :: proc(t: ^testing.T) {
	machine := machine_running(amo(rv.AMO_ADD, false), amo(rv.AMO_MINU, false))
	defer rv.machine_destroy(&machine)
	rv.bus_store(&machine.bus, DATA, 4, 0x8000_0000)
	machine.cpu.regs[7] = 1

	rv.machine_step(&machine) // amoadd.w
	testing.expect_value(t, machine.cpu.regs[5], 0xffff_ffff_8000_0000) // old value, sign-extended
	value, _ := rv.bus_load(&machine.bus, DATA, 4)
	testing.expect_value(t, value, 0x8000_0001)

	machine.cpu.regs[7] = 0xffff_ffff_0000_0002 // only the low 32 bits count: 2
	rv.machine_step(&machine) // amominu.w
	value, _ = rv.bus_load(&machine.bus, DATA, 4)
	testing.expect_value(t, value, 2) // 2 < 0x80000001 unsigned
}

@(test)
step_back_restores_the_reservation :: proc(t: ^testing.T) {
	machine := machine_running(LR_D(), SC_D())
	defer rv.machine_destroy(&machine)

	rv.machine_step(&machine) // lr: reserve
	rv.machine_step(&machine) // sc: succeed, reservation used up
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect(t, machine.cpu.reservation.valid) // back as after the lr
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect(t, !machine.cpu.reservation.valid)
}
