package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for taking supervisor interrupts (core/interrupts.odin
// interrupt_to_take, core/trap_entry.odin trap_target): which mode an
// interrupt goes to (mideleg), when that mode allows it, which one wins
// when several are ready, and the round trip back with sret.
//
// The supervisor interrupt bits in mip belong to software (docs: mie
// mip), so the tests set them directly: no device is needed. (The machine
// bits would be wiped by the first step: they follow the devices, and
// there are none here.)
//
// As in delegation_test.odin, step 1 is an MRET at RAM_BASE that drops
// into `mode` at CODE, where NOPs wait. Both handlers are set up, at
// different addresses, so the pc after the interrupt says which mode
// took it.

@(private = "file")
MRET :: u32(0x3020_0073)
@(private = "file")
SRET :: u32(0x1020_0073)
@(private = "file")
CSRCI_SIP_2 :: u32(0x1441_7073) // csrrci zero, sip, 2: clear SSIP
@(private = "file")
CODE :: rv.RAM_BASE + 0x100 // where MRET sends the hart
@(private = "file")
M_HANDLER :: rv.RAM_BASE + 0x800 // mtvec
@(private = "file")
S_HANDLER :: rv.RAM_BASE + 0xc00 // stvec

// A machine that drops into `mode` with its first step, NOPs at CODE,
// both trap vectors set, and the interrupt CSRs as given: `delegated` in
// mideleg, `enabled` in mie, `pending` in mip.
@(private = "file")
machine_with_interrupts :: proc(mode: rv.Privilege, delegated, enabled, pending: u64) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(MRET))
	for index in 0 ..< 8 {
		rv.machine_store(&machine, CODE + u64(index) * 4, 4, u64(NOP))
	}
	machine.cpu.csr.mepc = CODE
	machine.cpu.csr.mtvec = M_HANDLER
	machine.cpu.csr.stvec = S_HANDLER
	machine.cpu.csr.mstatus = rv.mstatus_with_mpp(0, mode) // MIE, SIE off
	machine.cpu.csr.mideleg = delegated
	machine.cpu.csr.mie = enabled
	machine.cpu.csr.mip = pending
	return machine
}

@(test)
delegated_timer_interrupt_from_user_goes_to_supervisor :: proc(t: ^testing.T) {
	stip := rv.MIP_STIP
	machine := machine_with_interrupts(.User, stip, stip, stip)
	defer rv.machine_destroy(&machine)

	// Step 1: mret into U. The interrupt was ready all along, but it is
	// delegated and the hart was in machine mode: never taken there.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.pc, CODE)

	// Step 2: from user mode a supervisor interrupt is always taken
	// (sstatus.SIE only matters in supervisor mode).
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.pc, S_HANDLER)
	// sepc: the NOP that hadn't run yet. scause: bit 63 (an interrupt),
	// then 5, STIP's bit.
	testing.expect_value(t, machine.cpu.csr.sepc, CODE)
	testing.expect_value(t, machine.cpu.csr.scause, u64(0x8000_0000_0000_0005))
	testing.expect_value(t, machine.cpu.csr.scause, u64(rv.Trap_Cause.Supervisor_Timer_Interrupt))
	testing.expect_value(t, machine.cpu.csr.stval, 0)
	testing.expect_value(t, rv.mstatus_spp(machine.cpu.csr.mstatus), rv.Privilege.User)
	// Machine mode's trap CSRs aren't touched.
	testing.expect_value(t, machine.cpu.csr.mcause, 0)
}

@(test)
supervisor_mode_holds_its_interrupts_back_with_sie :: proc(t: ^testing.T) {
	stip := rv.MIP_STIP
	machine := machine_with_interrupts(.Supervisor, stip, stip, stip)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S

	// Step 2: SIE is 0, so supervisor mode isn't interrupted: the NOP
	// runs.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.pc, CODE + 4)
	testing.expect_value(t, machine.cpu.csr.scause, 0)

	// The kernel turns SIE on (as csrsi sstatus, 2 would): step 3 takes
	// the interrupt before the second NOP.
	machine.cpu.csr.mstatus |= rv.MSTATUS_SIE
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.pc, S_HANDLER)
	testing.expect_value(t, machine.cpu.csr.sepc, CODE + 4)
	// SPIE keeps the SIE the handler interrupted (1); SIE is off inside
	// the handler; SPP = supervisor, where it came from.
	status := machine.cpu.csr.mstatus
	testing.expect_value(t, status & rv.MSTATUS_SIE, 0)
	testing.expect_value(t, status & rv.MSTATUS_SPIE, rv.MSTATUS_SPIE)
	testing.expect_value(t, rv.mstatus_spp(status), rv.Privilege.Supervisor)
}

@(test)
machine_mode_never_takes_a_delegated_interrupt :: proc(t: ^testing.T) {
	stip := rv.MIP_STIP
	machine := machine_with_interrupts(.User, stip, stip, stip)
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(NOP)) // stay in machine mode
	// Every switch on: still not taken. A delegated interrupt goes to
	// supervisor mode, and a trap never goes down a level.
	machine.cpu.csr.mstatus |= rv.MSTATUS_MIE | rv.MSTATUS_SIE

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 4) // the NOP ran
	testing.expect_value(t, machine.cpu.csr.scause, 0)
	testing.expect_value(t, machine.cpu.csr.mcause, 0)
}

@(test)
undelegated_supervisor_interrupt_goes_to_machine :: proc(t: ^testing.T) {
	// The same timer interrupt, but mideleg = 0: machine mode takes it,
	// as a firmware that handles STIP itself would.
	stip := rv.MIP_STIP
	machine := machine_with_interrupts(.Supervisor, 0, stip, stip)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S

	// Step 2: below machine mode, so taken even though MIE = 0.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, M_HANDLER)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Supervisor_Timer_Interrupt))
	testing.expect_value(t, machine.cpu.csr.mepc, CODE)
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.csr.scause, 0)
}

@(test)
interrupts_for_machine_mode_come_first :: proc(t: ^testing.T) {
	// Two ready from user mode: SSIP not delegated (goes to machine
	// mode), STIP delegated (goes to supervisor mode). Machine mode's
	// come first, even though software and timer are both "lower" kinds.
	ready := rv.MIP_SSIP | rv.MIP_STIP
	machine := machine_with_interrupts(.User, rv.MIP_STIP, ready, ready)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U

	rv.machine_step(&machine) // step 2
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Supervisor_Software_Interrupt))
	// STIP is still pending: it is taken once machine mode returns.
	testing.expect_value(t, machine.cpu.csr.mip & rv.MIP_STIP, rv.MIP_STIP)
}

@(test)
supervisor_external_beats_software_beats_timer :: proc(t: ^testing.T) {
	// All three delegated and ready: external first, as for machine mode.
	all := rv.SUPERVISOR_INTERRUPT_BITS
	machine := machine_with_interrupts(.User, all, all, all)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U
	rv.machine_step(&machine) // step 2
	testing.expect_value(t, machine.cpu.csr.scause, u64(rv.Trap_Cause.Supervisor_External_Interrupt))

	// Without SEIP: software (SSIP) beats timer (STIP).
	machine2 := machine_with_interrupts(.User, all, all, rv.MIP_SSIP | rv.MIP_STIP)
	defer rv.machine_destroy(&machine2)
	rv.machine_step(&machine2)
	rv.machine_step(&machine2)
	testing.expect_value(t, machine2.cpu.csr.scause, u64(rv.Trap_Cause.Supervisor_Software_Interrupt))
}

@(test)
vectored_stvec_sends_each_interrupt_to_its_own_entry :: proc(t: ^testing.T) {
	stip := rv.MIP_STIP
	machine := machine_with_interrupts(.User, stip, stip, stip)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.stvec = S_HANDLER | rv.MTVEC_VECTORED // mode 1
	rv.machine_step(&machine) // step 1: mret into U

	// Step 2: interrupt 5 jumps to BASE + 4 * 5, its own entry in the
	// table (exceptions would still go to BASE).
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.pc, S_HANDLER + 4 * 5)
}

@(test)
sret_returns_from_a_delegated_interrupt :: proc(t: ^testing.T) {
	// The round trip with SSIP, the one supervisor mode can clear itself
	// (through sip). User code: NOPs. Handler: clear SSIP, then sret.
	ssip := rv.MIP_SSIP
	machine := machine_with_interrupts(.User, ssip, ssip, ssip)
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, S_HANDLER, 4, u64(CSRCI_SIP_2))
	rv.machine_store(&machine, S_HANDLER + 4, 4, u64(SRET))

	rv.machine_step(&machine) // step 1: mret into U
	rv.machine_step(&machine) // step 2: SSIP taken, into the handler
	testing.expect_value(t, machine.cpu.csr.scause, u64(rv.Trap_Cause.Supervisor_Software_Interrupt))
	testing.expect_value(t, machine.cpu.csr.sepc, CODE) // the NOP that hadn't run

	// Step 3: the handler clears SSIP; nothing is pending any more.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mip, 0)

	// Step 4: sret, back to user mode at the NOP the interrupt came
	// before.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, CODE)

	// Step 5: the NOP finally runs, and no interrupt comes again.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.pc, CODE + 4)
}

@(test)
undo_steps_back_over_a_delegated_interrupt :: proc(t: ^testing.T) {
	stip := rv.MIP_STIP
	machine := machine_with_interrupts(.User, stip, stip, stip)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U
	status_before := machine.cpu.csr.mstatus
	rv.machine_step(&machine) // step 2: the interrupt, into supervisor mode

	// Back over the interrupt: user mode at the NOP, the supervisor trio
	// and mstatus as they were. STIP is still pending (nothing cleared
	// it), so stepping forward would take it again.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, CODE)
	testing.expect_value(t, machine.cpu.csr.sepc, 0)
	testing.expect_value(t, machine.cpu.csr.scause, 0)
	testing.expect_value(t, machine.cpu.csr.mstatus, status_before)
	testing.expect_value(t, machine.cpu.csr.mip, stip)
}
