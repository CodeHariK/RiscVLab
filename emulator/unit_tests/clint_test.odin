package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for the CLINT (devices/clint.odin) and interrupts
// (core/interrupts.odin): the clock, the alarm, taking a timer interrupt,
// msip, and undo across an interrupt.

MTIME :: rv.CLINT_BASE + devices.CLINT_MTIME
MTIMECMP :: rv.CLINT_BASE + devices.CLINT_MTIMECMP
MSIP :: rv.CLINT_BASE + devices.CLINT_MSIP
ADDI_A0_A0_1 :: u32(0x0015_0513) // addi a0, a0, 1
NOP :: u32(0x0000_0013)

// A machine with a CLINT, RAM filled with `addi a0, a0, 1`, a handler
// address in mtvec (nothing is there but more addis), and undo history.
@(private = "file")
machine_with_clint :: proc() -> (rv.Machine, ^devices.Clint) {
	machine := rv.machine_create(64 * 1024, 64)
	for index in 0 ..< 1024 {
		rv.machine_store(&machine, rv.RAM_BASE + u64(index) * 4, 4, u64(ADDI_A0_A0_1))
	}
	clint := devices.clint_attach(&machine.bus)
	machine.cpu.csr.mtvec = rv.RAM_BASE + 0x800
	return machine, clint
}

@(private = "file")
steps :: proc(machine: ^rv.Machine, count: int) {
	for _ in 0 ..< count {
		rv.machine_step(machine)
	}
}

@(test)
mtime_counts_instructions :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	steps(&machine, 5)
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 5)
}

@(test)
writing_mtime_sets_the_clock :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	steps(&machine, 3)
	rv.machine_store(&machine, MTIME, 8, 1000)
	steps(&machine, 2)
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 1002)
}

@(test)
alarm_sets_mtip_but_no_trap_while_disabled :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, MTIMECMP, 8, 3)
	steps(&machine, 2)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, 0)
	steps(&machine, 1)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, rv.MIP_MTIP) // pending
	steps(&machine, 3)
	testing.expect_value(t, machine.cpu.regs[10], 6) // never interrupted: MIE is off
}

@(test)
timer_interrupt_is_taken_between_instructions :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 4)
	steps(&machine, 4) // 4 addis: mtime is now 4, the alarm time
	testing.expect_value(t, machine.cpu.regs[10], 4)

	steps(&machine, 1) // the interrupt, instead of the 5th addi
	testing.expect_value(t, machine.cpu.regs[10], 4)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Machine_Timer_Interrupt))
	testing.expect_value(t, machine.cpu.csr.mepc, rv.RAM_BASE + 16) // the addi that didn't run
	testing.expect_value(t, machine.cpu.csr.mtval, 0)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 0x800)
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_MIE, 0) // off in the handler
}

@(test)
vectored_mtvec_sends_interrupts_to_base_plus_4_times_cause :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mtvec = rv.RAM_BASE + 0x800 | 1 // vectored
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 0)
	steps(&machine, 1)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 0x800 + 4 * 7)
}

@(test)
msip_raises_a_software_interrupt :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mie = rv.MIP_MSIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MSIP, 4, 1)
	steps(&machine, 1)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Machine_Software_Interrupt))
}

@(test)
mtimecmp_halves :: proc(t: ^testing.T) {
	machine, clint := machine_with_clint()
	defer rv.machine_destroy(&machine)
	testing.expect(t, rv.machine_store(&machine, MTIMECMP, 4, 0x1111_2222))
	testing.expect(t, rv.machine_store(&machine, MTIMECMP + 4, 4, 0x3333_4444))
	testing.expect_value(t, clint.mtimecmp, 0x3333_4444_1111_2222)
	high, _ := rv.machine_load(&machine, MTIMECMP + 4, 4)
	testing.expect_value(t, high, 0x3333_4444)
	_, loaded := rv.machine_load(&machine, MTIMECMP, 1)
	testing.expect(t, !loaded) // bytes aren't allowed
}

@(test)
undo_steps_back_over_an_interrupt :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 2)
	steps(&machine, 3) // addi, addi, interrupt
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 0x800)

	testing.expect(t, rv.machine_step_back(&machine)) // back before the interrupt
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 8)
	testing.expect_value(t, machine.cpu.csr.mcause, 0)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, rv.MIP_MTIP) // still pending
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, 0) // before the alarm time
}

@(test)
wfi_does_nothing_and_time_goes_on :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(rv.ENCODING_WFI))
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 4)
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 1)
}

@(test)
a_front_end_store_updates_mip_at_once :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, MTIMECMP, 8, 0) // the alarm time has come
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, rv.MIP_MTIP)
}

// The step clock, not mcycle, drives mtime: writing mcycle (as a program
// may, to time some code) doesn't move the timer.
@(test)
writing_mcycle_does_not_move_mtime :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	CSRW_MCYCLE_ZERO :: u32(0xb000_1073) // csrrw zero, mcycle, zero
	rv.machine_store(&machine, rv.RAM_BASE + 8, 4, u64(CSRW_MCYCLE_ZERO))
	steps(&machine, 3) // addi, addi, csrw mcycle
	testing.expect_value(t, machine.cpu.cycle, 0)
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 3)
	steps(&machine, 1)
	testing.expect_value(t, machine.cpu.cycle, 1)
	testing.expect_value(t, rv.cpu_clock(&machine.cpu), 4)

	// Undo puts mcycle back, and the clock with it.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect(t, rv.machine_step_back(&machine)) // the csrw
	testing.expect_value(t, machine.cpu.cycle, 2)
	testing.expect_value(t, rv.cpu_clock(&machine.cpu), 2)
	testing.expect_value(t, machine.cpu.clock_offset, 0)
}

// Taking an interrupt is a step: it takes a cycle and a tick of the step
// clock, but no instruction retires.
@(test)
an_interrupt_takes_a_cycle_but_retires_nothing :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 2)
	steps(&machine, 3) // addi, addi, interrupt
	testing.expect_value(t, machine.cpu.instret, 2)
	testing.expect_value(t, machine.cpu.cycle, 3)
	testing.expect_value(t, rv.cpu_clock(&machine.cpu), 3)
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.cycle, 2)
	testing.expect_value(t, rv.cpu_clock(&machine.cpu), 2)
}

// mtvec = 1 is vectored mode with base 0: no handler, so the machine
// stops rather than jumping to address 0x1c.
@(test)
vectored_mtvec_with_base_0_is_no_handler :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mtvec = 1
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 0)
	trap, stopped := rv.machine_step(&machine).?
	testing.expect(t, stopped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Machine_Timer_Interrupt)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE)
}

// Atomics work on RAM only: an AMO on a device faults and leaves the
// device as it was.
@(test)
atomics_on_a_device_fault :: proc(t: ^testing.T) {
	machine, clint := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mtvec = 0
	AMOADD_D :: u32(0x0073_32af) // amoadd.d t0, t2, (t1)
	LR_D :: u32(0x1003_32af) // lr.d t0, (t1)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(AMOADD_D))
	machine.cpu.regs[6] = MTIMECMP
	machine.cpu.regs[7] = 5
	trap, stopped := rv.machine_step(&machine).?
	testing.expect(t, stopped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Store_Access_Fault)
	testing.expect_value(t, clint.mtimecmp, max(u64))

	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(LR_D))
	trap, stopped = rv.machine_step(&machine).?
	testing.expect(t, stopped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Load_Access_Fault)
}
