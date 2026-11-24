package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for the CLINT (devices/clint.odin) and interrupts
// (core/interrupts.odin): the clock, the alarm, taking a timer interrupt,
// msip, and undo across an interrupt.
//
// Time here is the step clock: one tick of mtime per step
// (CLINT_TICKS_PER_STEP = 1), so "after 4 steps, mtime = 4". Most tests
// set an alarm (mtimecmp), run a few steps, and check mip, the trap
// CSRs, or a0, which counts the instructions that actually ran.

// The CLINT's registers, by address (docs: clint).
MTIME :: rv.CLINT_BASE + devices.CLINT_MTIME // the clock (+0xbff8)
MTIMECMP :: rv.CLINT_BASE + devices.CLINT_MTIMECMP // the alarm (+0x4000): MTIP while mtime >= mtimecmp
MSIP :: rv.CLINT_BASE + devices.CLINT_MSIP // software interrupt (+0): bit 0 = MSIP
ADDI_A0_A0_1 :: u32(0x0015_0513) // addi a0, a0, 1
NOP :: u32(0x0000_0013) // addi zero, zero, 0

// A machine with a CLINT, RAM filled with `addi a0, a0, 1`, a handler
// address in mtvec (nothing is there but more addis), and undo history.
// Every instruction that runs adds 1 to a0, so a0 says how many ran: an
// interrupt taken instead of an instruction doesn't add to it.
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

// Runs `count` steps (instructions, or interrupts taken).
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
	// mtime = step clock * 1: five steps, five ticks. Nothing stored
	// mtime; clint_mtime works it out when it is read.
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 5)
}

@(test)
writing_mtime_sets_the_clock :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	steps(&machine, 3)
	// Storing mtime doesn't save the value: it changes mtime_offset so
	// that mtime reads 1000 now, and keeps counting from there.
	rv.machine_store(&machine, MTIME, 8, 1000)
	steps(&machine, 2)
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 1002)
}

@(test)
alarm_sets_mtip_but_no_trap_while_disabled :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	// The alarm at mtime 3. mie and mstatus.MIE stay 0 (as at reset).
	rv.machine_store(&machine, MTIMECMP, 8, 3)
	steps(&machine, 2) // mtime 2: not yet
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, 0)
	steps(&machine, 1) // mtime 3: the alarm time
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, rv.MIP_MTIP) // pending
	// Pending but not enabled: it waits in mip, and the addis keep
	// running. All 6 steps were instructions.
	steps(&machine, 3)
	testing.expect_value(t, machine.cpu.regs[10], 6) // never interrupted: MIE is off
}

@(test)
timer_interrupt_is_taken_between_instructions :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	// All three switches on: mie.MTIE, mstatus.MIE, and (soon) MTIP.
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 4)
	steps(&machine, 4) // 4 addis: mtime is now 4, the alarm time
	testing.expect_value(t, machine.cpu.regs[10], 4)

	// The next step takes the interrupt before the 5th addi runs, so a0
	// stays 4. The trap CSRs say what happened and where to come back.
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
	// mtimecmp = 0: the alarm is due at once, so the first step takes it.
	rv.machine_store(&machine, MTIMECMP, 8, 0)
	steps(&machine, 1)
	// Vectored mode: interrupt n goes to base + 4 * n. The timer is
	// interrupt 7, so base + 28.
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 0x800 + 4 * 7)
}

@(test)
msip_raises_a_software_interrupt :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mie = rv.MIP_MSIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	// Writing 1 to msip raises MSIP (on a multi-hart machine, another
	// hart does this to poke this one). The next step takes it.
	rv.machine_store(&machine, MSIP, 4, 1)
	steps(&machine, 1)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Machine_Software_Interrupt))
}

@(test)
mtimecmp_halves :: proc(t: ^testing.T) {
	machine, clint := machine_with_clint()
	defer rv.machine_destroy(&machine)
	// A 32-bit program can only store 4 bytes at a time, so it sets the
	// 8-byte mtimecmp in two halves: the low one at +0, the high one at
	// +4 (little-endian). Each store replaces its half, keeps the other.
	testing.expect(t, rv.machine_store(&machine, MTIMECMP, 4, 0x1111_2222))
	testing.expect(t, rv.machine_store(&machine, MTIMECMP + 4, 4, 0x3333_4444))
	testing.expect_value(t, clint.mtimecmp, 0x3333_4444_1111_2222)
	// A 4-byte load at +4 reads the high half.
	high, _ := rv.machine_load(&machine, MTIMECMP + 4, 4)
	testing.expect_value(t, high, 0x3333_4444)
	// 1 and 2 bytes aren't allowed: ok = false (an access fault).
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

	// Back over the interrupt: the pc is the 3rd addi again (the one it
	// came before), and the trap CSRs are as they were.
	testing.expect(t, rv.machine_step_back(&machine)) // back before the interrupt
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 8)
	testing.expect_value(t, machine.cpu.csr.mcause, 0)
	// mip isn't recorded for undo: it is worked out again from the clock.
	// The clock is 2, the alarm time, so MTIP is still pending...
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, rv.MIP_MTIP) // still pending
	// ...and one more step back the clock is 1, before the alarm.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_MTIP, 0) // before the alarm time
}

@(test)
wfi_does_nothing_and_time_goes_on :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	// wfi ("wait for interrupt") is only a hint: here it is a nop. It
	// still takes a step, so the clock moves on.
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
	// No step runs: a store from outside the program (the debugger, or a
	// test) that reaches a device updates mip straight away
	// (after_front_end_access), so the tabs never show a stale mip.
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
	// The 3rd step writes mcycle = 0. The written value stands (no +1 for
	// that step), but the step clock still moves on: step_clock_offset
	// takes up the difference (csr_write), so mtime reads 3, not 0.
	steps(&machine, 3) // addi, addi, csrw mcycle
	testing.expect_value(t, machine.cpu.csr.mcycle, 0)
	now, _ := rv.machine_load(&machine, MTIME, 8)
	testing.expect_value(t, now, 3)
	// From there both count on together: mcycle 1, clock 4.
	steps(&machine, 1)
	testing.expect_value(t, machine.cpu.csr.mcycle, 1)
	testing.expect_value(t, rv.step_clock(&machine.cpu), 4)

	// Undo puts mcycle back, and the clock with it: back over the csrw,
	// csr_restore resets mcycle to 2 and the offset to 0.
	testing.expect(t, rv.machine_step_back(&machine)) // the 4th addi
	testing.expect(t, rv.machine_step_back(&machine)) // the csrw
	testing.expect_value(t, machine.cpu.csr.mcycle, 2)
	testing.expect_value(t, rv.step_clock(&machine.cpu), 2)
	testing.expect_value(t, machine.cpu.step_clock_offset, 0)
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
	// Two instructions retired; three steps took a cycle each.
	// mcycle - minstret = 1: the one interrupt taken.
	testing.expect_value(t, machine.cpu.csr.minstret, 2)
	testing.expect_value(t, machine.cpu.csr.mcycle, 3)
	testing.expect_value(t, rv.step_clock(&machine.cpu), 3)
	// Stepping back over the interrupt takes its cycle back too.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mcycle, 2)
	testing.expect_value(t, rv.step_clock(&machine.cpu), 2)
}

// mtvec = 1 is vectored mode with base 0: no handler, so the machine
// stops rather than jumping to address 0x1c.
@(test)
vectored_mtvec_with_base_0_is_no_handler :: proc(t: ^testing.T) {
	machine, _ := machine_with_clint()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mtvec = 1 // MODE 1 (vectored), BASE 0
	machine.cpu.csr.mie = rv.MIP_MTIP
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE
	rv.machine_store(&machine, MTIMECMP, 8, 0) // due at once
	// trap_has_handler looks at the base only (mtvec_base), which is 0:
	// the step returns the trap instead of jumping, and nothing changes.
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
	machine.cpu.csr.mtvec = 0 // no handler: a trap stops the step, so it can be checked
	AMOADD_D :: u32(0x0073_32af) // amoadd.d t0, t2, (t1)
	LR_D :: u32(0x1003_32af) // lr.d t0, (t1)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(AMOADD_D))
	machine.cpu.regs[6] = MTIMECMP // t1: the address, a CLINT register
	machine.cpu.regs[7] = 5 // t2: what to add
	// The address is 8-byte aligned, so it passes that check; then
	// bus_is_ram says no: Store_Access_Fault (an AMO writes).
	trap, stopped := rv.machine_step(&machine).?
	testing.expect(t, stopped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Store_Access_Fault)
	// mtimecmp is untouched: still all ones, as at reset (no alarm).
	testing.expect_value(t, clint.mtimecmp, max(u64))

	// lr only reads, so it is a Load_Access_Fault. The pc didn't move
	// (the trap changed nothing), so the lr goes in the same place.
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(LR_D))
	trap, stopped = rv.machine_step(&machine).?
	testing.expect(t, stopped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Load_Access_Fault)
}
