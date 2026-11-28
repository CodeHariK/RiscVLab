package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for exception delegation (medeleg; core/trap_entry.odin
// trap_target, trap_enter; core/trap_return.odin exec_sret): which mode takes a trap, what a
// trap into supervisor mode writes, how SRET returns from one, and undo
// across both.
//
// Each test starts in machine mode with an MRET at RAM_BASE that drops
// into `mode` at CODE (step 1), where the instruction under test waits
// (step 2). Both handlers are set up, at different addresses, so the pc
// after the trap says which mode took it.

@(private = "file")
MRET :: u32(0x3020_0073)
@(private = "file")
ECALL :: u32(0x0000_0073)
@(private = "file")
ILLEGAL :: u32(0x0000_0000) // all zeros: not a valid instruction
@(private = "file")
SRET :: u32(0x1020_0073)
@(private = "file")
CODE :: rv.RAM_BASE + 0x100 // where MRET sends the hart
@(private = "file")
M_HANDLER :: rv.RAM_BASE + 0x800 // mtvec
@(private = "file")
S_HANDLER :: rv.RAM_BASE + 0xc00 // stvec

// Bit for a cause in medeleg.
@(private = "file")
delegate :: proc(cause: rv.Trap_Cause) -> u64 {
	return u64(1) << rv.trap_cause_number(cause)
}

// A machine that drops into `mode` with its first step, with `code` at
// CODE, both trap vectors set, and medeleg = `medeleg`.
@(private = "file")
machine_dropping_to :: proc(mode: rv.Privilege, medeleg: u64, code: ..u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(MRET))
	for instruction, index in code {
		rv.machine_store(&machine, CODE + u64(index) * 4, 4, u64(instruction))
	}
	machine.cpu.csr.mepc = CODE
	machine.cpu.csr.mtvec = M_HANDLER
	machine.cpu.csr.stvec = S_HANDLER
	machine.cpu.csr.medeleg = medeleg
	machine.cpu.csr.mstatus = rv.mstatus_with_mpp(0, mode)
	return machine
}

@(test)
delegated_ecall_from_user_goes_to_supervisor :: proc(t: ^testing.T) {
	machine := machine_dropping_to(.User, delegate(.Ecall_From_U_Mode), ECALL)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mstatus |= rv.MSTATUS_SIE // supervisor interrupts on, to see SPIE save it
	rv.machine_step(&machine) // step 1: mret into U

	// Step 2: ecall. Its medeleg bit (8) is set and the hart is in user
	// mode, so supervisor mode takes it.
	testing.expect(t, rv.machine_step(&machine) == nil) // taken, not stopped
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.pc, S_HANDLER) // stvec, not mtvec
	// The supervisor trio says where, why and what.
	testing.expect_value(t, machine.cpu.csr.sepc, CODE)
	testing.expect_value(t, machine.cpu.csr.scause, u64(rv.Trap_Cause.Ecall_From_U_Mode))
	testing.expect_value(t, machine.cpu.csr.stval, 0)
	// Supervisor interrupts off in the handler, the old SIE kept in SPIE,
	// and SPP = 0: the trap came from user mode.
	status := machine.cpu.csr.mstatus
	testing.expect_value(t, status & rv.MSTATUS_SIE, 0)
	testing.expect_value(t, status & rv.MSTATUS_SPIE, rv.MSTATUS_SPIE)
	testing.expect_value(t, status & rv.MSTATUS_SPP, 0)
	// Machine mode's trap CSRs are left alone.
	testing.expect_value(t, machine.cpu.csr.mepc, CODE) // still what the helper set
	testing.expect_value(t, machine.cpu.csr.mcause, 0)
}

@(test)
ecall_without_its_bit_goes_to_machine :: proc(t: ^testing.T) {
	// Only illegal instructions are delegated: the ecall still goes to
	// machine mode, as before medeleg existed.
	machine := machine_dropping_to(.User, delegate(.Illegal_Instruction), ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U

	rv.machine_step(&machine) // step 2: ecall
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, M_HANDLER)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Ecall_From_U_Mode))
	testing.expect_value(t, machine.cpu.csr.scause, 0) // supervisor's trio untouched
}

@(test)
exceptions_in_machine_mode_ignore_medeleg :: proc(t: ^testing.T) {
	// Everything delegated, and an illegal instruction in machine mode.
	// A trap never goes down a level: machine mode takes it anyway.
	machine := rv.machine_create(64 * 1024, 16)
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(ILLEGAL))
	machine.cpu.csr.mtvec = M_HANDLER
	machine.cpu.csr.stvec = S_HANDLER
	machine.cpu.csr.medeleg = rv.MEDELEG_WRITABLE

	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, M_HANDLER)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
}

@(test)
delegated_ecall_from_supervisor_stays_in_supervisor :: proc(t: ^testing.T) {
	// medeleg bit 9: ecall from supervisor mode. The trap goes to
	// supervisor mode's own handler, from supervisor mode.
	machine := machine_dropping_to(.Supervisor, delegate(.Ecall_From_S_Mode), ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S

	rv.machine_step(&machine) // step 2: ecall
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.pc, S_HANDLER)
	testing.expect_value(t, machine.cpu.csr.scause, u64(rv.Trap_Cause.Ecall_From_S_Mode))
	// SPP = 1: this time the trap came from supervisor mode.
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_SPP, rv.MSTATUS_SPP)
}

@(test)
delegated_trap_with_no_stvec_stops :: proc(t: ^testing.T) {
	// Delegated, but stvec's base is 0: supervisor mode has no handler,
	// so the machine stops (the emulator's convention, as for mtvec = 0).
	machine := machine_dropping_to(.User, delegate(.Ecall_From_U_Mode), ECALL)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.stvec = 0
	rv.machine_step(&machine) // step 1: mret into U

	trap, stopped := rv.machine_step(&machine).?
	testing.expect(t, stopped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Ecall_From_U_Mode)
	// Nothing changed: still in user mode, at the ecall.
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, CODE)
}

@(test)
undo_steps_back_over_a_delegated_trap :: proc(t: ^testing.T) {
	machine := machine_dropping_to(.User, delegate(.Ecall_From_U_Mode), ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U
	status_before := machine.cpu.csr.mstatus
	rv.machine_step(&machine) // step 2: the delegated ecall
	testing.expect_value(t, machine.cpu.csr.scause, u64(rv.Trap_Cause.Ecall_From_U_Mode))

	// Back over the trap: the undo record held the supervisor trio (it
	// knows which mode took the trap) and mstatus, as they were.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, CODE)
	testing.expect_value(t, machine.cpu.csr.sepc, 0)
	testing.expect_value(t, machine.cpu.csr.scause, 0)
	testing.expect_value(t, machine.cpu.csr.mstatus, status_before)
	testing.expect_value(t, machine.cpu.csr.mepc, CODE) // the machine trio never changed
}

// ---------------------------------------------------------------- SRET

@(test)
sret_returns_from_a_delegated_ecall :: proc(t: ^testing.T) {
	// The full round trip: user code makes a system call, supervisor mode
	// handles it and returns to the instruction after the ecall.
	machine := machine_dropping_to(
		.User,
		delegate(.Ecall_From_U_Mode),
		ECALL,
		0x0070_0513, // addi a0, x0, 7: proof that user code carries on
	)
	defer rv.machine_destroy(&machine)
	// The supervisor handler. sepc holds the ecall's own address, so the
	// handler adds 4 before returning, or SRET would run the ecall again.
	handler := [?]u32 {
		0x1410_22f3, // csrr t0, sepc
		0x0042_8293, // addi t0, t0, 4
		0x1412_9073, // csrw sepc, t0
		SRET,
	}
	for instruction, index in handler {
		rv.machine_store(&machine, S_HANDLER + u64(index) * 4, 4, u64(instruction))
	}
	machine.cpu.csr.mstatus |= rv.MSTATUS_SIE // to watch SIE go off and come back

	rv.machine_step(&machine) // step 1: mret into U
	rv.machine_step(&machine) // step 2: ecall -> supervisor handler
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_SIE, 0) // off in the handler
	for _ in 0 ..< 3 {
		rv.machine_step(&machine) // steps 3-5: sepc += 4
	}
	testing.expect_value(t, machine.cpu.csr.sepc, CODE + 4)

	// Step 6: sret. Back to the mode in SPP (user), at sepc.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, CODE + 4)
	// SIE = SPIE (on again), SPIE = 1, SPP = user.
	status := machine.cpu.csr.mstatus
	testing.expect_value(t, status & rv.MSTATUS_SIE, rv.MSTATUS_SIE)
	testing.expect_value(t, status & rv.MSTATUS_SPIE, rv.MSTATUS_SPIE)
	testing.expect_value(t, status & rv.MSTATUS_SPP, 0)
	// The machine trap CSRs were never involved.
	testing.expect_value(t, machine.cpu.csr.mcause, 0)

	// Step 7: user code runs on after the system call.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.regs[10], 7) // a0
}

@(test)
sret_with_spp_supervisor_stays_in_supervisor :: proc(t: ^testing.T) {
	// SPP = 1 means "the trap came from supervisor mode", so SRET goes
	// back to supervisor mode, then resets SPP to user.
	machine := machine_dropping_to(.Supervisor, 0, SRET)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mstatus |= rv.MSTATUS_SPP
	machine.cpu.csr.sepc = CODE + 0x40
	rv.machine_step(&machine) // step 1: mret into S (MRET leaves SPP alone)

	testing.expect(t, rv.machine_step(&machine) == nil) // step 2: sret
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.pc, CODE + 0x40)
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_SPP, 0)
}

@(test)
sret_from_user_is_illegal :: proc(t: ^testing.T) {
	// User mode has no trap to return from. Nothing is delegated, so the
	// illegal instruction goes to machine mode.
	machine := machine_dropping_to(.User, 0, SRET)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U

	testing.expect(t, rv.machine_step(&machine) == nil) // step 2: sret -> trap
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, M_HANDLER)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.csr.mepc, CODE)
	testing.expect_value(t, machine.cpu.csr.mtval, u64(SRET)) // the bad instruction
}

@(test)
sret_from_machine_is_allowed :: proc(t: ^testing.T) {
	// A higher mode may run a lower mode's return: machine mode's SRET
	// uses the supervisor fields like any other.
	machine := machine_dropping_to(.User, 0)
	defer rv.machine_destroy(&machine)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(SRET)) // replace the MRET
	machine.cpu.csr.sepc = CODE // SPP is 0: return to user mode

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, CODE)
}

@(test)
undo_steps_back_over_sret :: proc(t: ^testing.T) {
	machine := machine_dropping_to(.Supervisor, 0, SRET)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mstatus |= rv.MSTATUS_SPP
	machine.cpu.csr.sepc = CODE + 0x40
	rv.machine_step(&machine) // step 1: mret into S
	status_before := machine.cpu.csr.mstatus
	rv.machine_step(&machine) // step 2: sret

	// SRET changed mstatus (SPP, SIE, SPIE), privilege and pc; the undo
	// record kept all three.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mstatus, status_before)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.pc, CODE)
}
