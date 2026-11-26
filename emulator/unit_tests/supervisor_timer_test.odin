package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for the supervisor timer (Sstc; core/interrupts.odin
// supervisor_timer, core/machine.odin machine_update_interrupts): with
// menvcfg.STCE on, STIP is a wire, 1 while time >= stimecmp, like MTIP
// for the CLINT's mtimecmp.
//
// Time is the CLINT's mtime: one tick per step, so "after 3 steps,
// time = 3". RAM is full of NOPs unless a test puts code in.

@(private = "file")
SRET :: u32(0x1020_0073)
@(private = "file")
CSRW_STIMECMP_T0 :: u32(0x14d2_9073) // csrrw zero, stimecmp, t0
@(private = "file")
S_HANDLER :: rv.RAM_BASE + 0xc00

// A machine with a CLINT (the clock), NOPs everywhere, and Sstc on.
@(private = "file")
machine_with_sstc :: proc() -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 64)
	for index in 0 ..< 1024 {
		rv.machine_store(&machine, rv.RAM_BASE + u64(index) * 4, 4, u64(NOP))
	}
	devices.clint_attach(&machine)
	machine.cpu.csr.menvcfg = rv.MENVCFG_STCE
	return machine
}

@(private = "file")
run :: proc(machine: ^rv.Machine, count: int) {
	for _ in 0 ..< count {
		rv.machine_step(machine)
	}
}

@(test)
stip_rises_when_time_reaches_stimecmp :: proc(t: ^testing.T) {
	machine := machine_with_sstc()
	defer rv.machine_destroy(&machine)
	// The alarm at time 3. Written from outside, as a fixture: the next
	// step works mip out again (the write set interrupts_change_at = 0).
	rv.csr_write(&machine.cpu, rv.CSR_STIMECMP, 3)

	run(&machine, 2) // time 2: not yet
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, 0)
	run(&machine, 1) // time 3: time >= stimecmp
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, rv.MIP_STIP)
	// It stays pending: time only moves on.
	run(&machine, 5)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, rv.MIP_STIP)
}

@(test)
a_later_stimecmp_lowers_stip :: proc(t: ^testing.T) {
	// The kernel's way of acknowledging a tick: set the next alarm. Step
	// 4 is csrw stimecmp, t0 with t0 = 100.
	machine := machine_with_sstc()
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, rv.RAM_BASE + 12, 4, u64(CSRW_STIMECMP_T0))
	machine.cpu.regs[5] = 100
	rv.csr_write(&machine.cpu, rv.CSR_STIMECMP, 0) // already due

	run(&machine, 3)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, rv.MIP_STIP)
	run(&machine, 1) // the csrw: STIP falls right after it
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, 0)
	testing.expect_value(t, machine.cpu.csr.stimecmp, 100)
}

@(test)
stip_ignores_writes_while_sstc_is_on :: proc(t: ^testing.T) {
	machine := machine_with_sstc()
	defer rv.machine_destroy(&machine)
	// With STCE on, STIP belongs to the timer: a write can't raise it
	// (SSIP and SEIP are still software's).
	testing.expect(t, rv.csr_write(&machine.cpu, rv.CSR_MIP, rv.MIP_STIP | rv.MIP_SSIP))
	testing.expect_value(t, machine.cpu.csr.mip, rv.MIP_SSIP)

	// Sstc off: STIP is software's again, as before Sstc.
	machine.cpu.csr.menvcfg = 0
	testing.expect(t, rv.csr_write(&machine.cpu, rv.CSR_MIP, rv.MIP_STIP))
	testing.expect_value(t, machine.cpu.csr.mip, rv.MIP_STIP)
}

@(test)
stimecmp_does_nothing_with_sstc_off :: proc(t: ^testing.T) {
	machine := machine_with_sstc()
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.menvcfg = 0
	rv.csr_write(&machine.cpu, rv.CSR_STIMECMP, 0) // due at once, if it counted
	run(&machine, 3)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, 0)
}

@(test)
kernel_takes_its_timer_tick_and_sets_the_next :: proc(t: ^testing.T) {
	// xv6's timer, end to end. Supervisor mode runs NOPs at RAM_BASE with
	// STIP delegated and enabled (and SIE on); the alarm is at time 3.
	// The handler sets the next alarm (time + 10) and returns:
	//
	//   csrr t0, time; addi t0, t0, 10; csrw stimecmp, t0; sret
	machine := machine_with_sstc()
	defer rv.machine_destroy(&machine)
	handler := [?]u32{CSRR_T0_TIME, 0x00a2_8293, CSRW_STIMECMP_T0, SRET}
	for instruction, index in handler {
		rv.machine_store(&machine, S_HANDLER + u64(index) * 4, 4, u64(instruction))
	}
	cpu := &machine.cpu
	cpu.privilege = .Supervisor // a fixture: as if mret had dropped here
	cpu.csr.stvec = S_HANDLER
	cpu.csr.mideleg = rv.MIP_STIP
	cpu.csr.mie = rv.MIP_STIP
	cpu.csr.mstatus |= rv.MSTATUS_SIE
	cpu.csr.mcounteren = rv.COUNTEREN_TM // the handler reads time
	rv.csr_write(cpu, rv.CSR_STIMECMP, 3)

	run(&machine, 3) // three NOPs, time 0..2
	testing.expect_value(t, cpu.pc, rv.RAM_BASE + 12)
	run(&machine, 1) // time 3: the tick, before the 4th NOP
	testing.expect_value(t, cpu.pc, S_HANDLER)
	testing.expect_value(t, cpu.csr.scause, u64(rv.Trap_Cause.Supervisor_Timer_Interrupt))
	testing.expect_value(t, cpu.csr.sepc, rv.RAM_BASE + 12)

	run(&machine, 1) // csrr t0, time: 4 (the interrupt took a step)
	testing.expect_value(t, cpu.regs[5], 4)
	run(&machine, 2) // addi, csrw: next alarm at 14, STIP falls
	testing.expect_value(t, cpu.csr.stimecmp, 14)
	testing.expect_value(t, cpu.csr.mip & rv.MIP_STIP, 0)
	run(&machine, 1) // sret: back to the NOP the tick came before
	testing.expect_value(t, cpu.pc, rv.RAM_BASE + 12)
	testing.expect_value(t, cpu.privilege, rv.Privilege.Supervisor)

	// The next tick comes at time 14, before the instruction at that
	// step. The clock is 8 now (3 NOPs, the tick, 4 handler steps).
	run(&machine, 5) // time 8..12: NOPs
	testing.expect(t, cpu.pc != S_HANDLER)
	run(&machine, 1) // time 13: still a NOP
	testing.expect(t, cpu.pc != S_HANDLER)
	run(&machine, 1) // time 14: the second tick
	testing.expect_value(t, cpu.pc, S_HANDLER)
}

@(test)
undo_brings_stip_back_with_the_clock :: proc(t: ^testing.T) {
	machine := machine_with_sstc()
	defer rv.machine_destroy(&machine)
	rv.csr_write(&machine.cpu, rv.CSR_STIMECMP, 2)
	run(&machine, 2) // time 2: STIP up
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, rv.MIP_STIP)

	// STIP isn't recorded for undo: it is worked out again from time and
	// stimecmp. One step back, the clock is 1: before the alarm.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, 0)
	// Forward again: it rises again at the same step.
	run(&machine, 1)
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, rv.MIP_STIP)
}
