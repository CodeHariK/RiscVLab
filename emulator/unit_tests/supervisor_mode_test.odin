package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for supervisor mode existing (core/privilege.odin, csr.odin):
// MRET into it, what it may and may not touch, ECALL back up, and its own
// CSRs (sscratch, sstatus, sie). Nothing is delegated here, so every trap
// goes to machine mode (delegation_test.odin has the delegated ones).

@(private = "file")
MRET :: u32(0x3020_0073)
@(private = "file")
ECALL :: u32(0x0000_0073)
@(private = "file")
CSRR_T0_MSTATUS :: u32(0x3000_22f3) // csrrs t0, mstatus, zero
@(private = "file")
CSRR_T0_CYCLE :: u32(0xc000_22f3) // csrrs t0, cycle, zero
@(private = "file")
CSRW_SSCRATCH_T1 :: u32(0x1403_1073) // csrrw zero, sscratch, t1
@(private = "file")
CSRR_T0_SSCRATCH :: u32(0x1400_22f3) // csrrs t0, sscratch, zero
@(private = "file")
CSRS_SSTATUS_T1 :: u32(0x1003_2073) // csrrs zero, sstatus, t1: set the bits in t1
@(private = "file")
CSRW_SIE_T1 :: u32(0x1043_1073) // csrrw zero, sie, t1
@(private = "file")
S_CODE :: rv.RAM_BASE + 0x100 // where MRET sends the hart
@(private = "file")
HANDLER :: rv.RAM_BASE + 0x800 // mtvec

// A machine whose first instruction is MRET, with mepc = S_CODE and
// MPP = supervisor, so one step drops into supervisor mode; `code` is
// placed at S_CODE.
@(private = "file")
machine_entering_supervisor_mode :: proc(code: ..u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(MRET))
	for instruction, index in code {
		rv.machine_store(&machine, S_CODE + u64(index) * 4, 4, u64(instruction))
	}
	machine.cpu.csr.mepc = S_CODE
	machine.cpu.csr.mtvec = HANDLER
	machine.cpu.csr.mstatus = rv.mstatus_with_mpp(0, .Supervisor)
	return machine
}

// Step 1 is always the MRET at RAM_BASE (machine mode), dropping into
// supervisor mode at S_CODE; step 2 is the instruction under test.

@(test)
mret_drops_into_supervisor_mode :: proc(t: ^testing.T) {
	// A NOP waits at S_CODE: this test only checks where MRET lands.
	machine := machine_entering_supervisor_mode(NOP)
	defer rv.machine_destroy(&machine)

	// MRET: privilege = MPP (supervisor), pc = mepc (S_CODE).
	testing.expect(t, rv.machine_step(&machine) == nil) // no trap
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)
	testing.expect_value(t, machine.cpu.pc, S_CODE)
	// MRET also empties the return slot: MPP = the least privileged
	// mode, user (docs: mret, "Why step 4").
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.User)
}

@(test)
supervisor_mode_reads_cycle :: proc(t: ^testing.T) {
	machine := machine_entering_supervisor_mode(CSRR_T0_CYCLE)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mcounteren = rv.COUNTEREN_CY // machine mode allows it
	rv.machine_step(&machine) // step 1: mret into S

	// Step 2: csrr t0, cycle. cycle is 0xc00: bits 9..8 = 00, so any
	// level may read it (csr_allowed: 1 >= 0), and mcounteren.CY is set.
	testing.expect(t, rv.machine_step(&machine) == nil) // no trap
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor) // still in S
	// t0 (x5) got mcycle as it was when the csrr ran: one step (the
	// mret) had passed; the csrr's own cycle counted after.
	testing.expect_value(t, machine.cpu.regs[5], machine.cpu.csr.mcycle - 1)
}

@(test)
machine_csr_from_supervisor_mode_is_illegal :: proc(t: ^testing.T) {
	machine := machine_entering_supervisor_mode(CSRR_T0_MSTATUS)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S

	// Step 2: csrr t0, mstatus. mstatus is 0x300: bits 9..8 = 11,
	// machine only (csr_allowed: 1 >= 3 is false), so Illegal_Instruction.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	// The trap took the hart up to machine mode...
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	// ...and saved where it came from, for the handler's mret.
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.Supervisor)
}

@(test)
ecall_from_supervisor_mode_is_cause_9 :: proc(t: ^testing.T) {
	machine := machine_entering_supervisor_mode(ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S

	// Step 2: ecall. The cause says which level called: 8 from user,
	// 9 from supervisor (ecall_cause), so the handler knows who asked.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Ecall_From_S_Mode))
	// mepc = the ecall itself; the handler adds 4 before returning.
	testing.expect_value(t, machine.cpu.csr.mepc, S_CODE)
	// Up to machine mode, at the handler (no delegation yet: every trap
	// goes to machine mode).
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, HANDLER)
	// MPP remembers where the trap came from, for the handler's mret.
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.Supervisor)
}

@(test)
mret_from_supervisor_mode_is_illegal :: proc(t: ^testing.T) {
	// A second MRET waits at S_CODE.
	machine := machine_entering_supervisor_mode(MRET)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S (allowed: machine mode)

	// Step 2: mret again, now from S. MRET sets the level to MPP, so it
	// is a "change privilege" instruction: only machine mode may run it
	// (exec_mret: privilege != .Machine -> Illegal_Instruction), or a
	// kernel could jump itself into machine mode. S mode gets sret.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine) // the trap took it up
	// It was this mret that trapped: mepc points at it, mtval holds its
	// bits, and MPP says it ran in supervisor mode.
	testing.expect_value(t, machine.cpu.csr.mepc, S_CODE)
	testing.expect_value(t, machine.cpu.csr.mtval, u64(MRET))
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.Supervisor)
}

@(test)
supervisor_mode_uses_its_own_trap_csrs :: proc(t: ^testing.T) {
	// csrw sscratch, t1 then csrr t0, sscratch, both in supervisor mode.
	machine := machine_entering_supervisor_mode(CSRW_SSCRATCH_T1, CSRR_T0_SSCRATCH)
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = 0x1234 // t1
	rv.machine_step(&machine) // step 1: mret into S

	// sscratch is 0x140: bits 9..8 = 01, supervisor level, so S (1) may
	// use it (csr_allowed: 1 >= 1).
	testing.expect(t, rv.machine_step(&machine) == nil) // the csrw: no trap
	testing.expect(t, rv.machine_step(&machine) == nil) // the csrr: no trap
	testing.expect_value(t, machine.cpu.regs[5], 0x1234) // t0 read it back
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Supervisor)

	// Back over the csrr and the csrw: the undo record restores
	// sscratch like any other CSR.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.sscratch, 0)
}

@(test)
user_mode_cannot_touch_supervisor_csrs :: proc(t: ^testing.T) {
	// The same csrr, from user mode: with MPP = user, the helper's mret
	// drops to user mode instead of supervisor.
	machine := machine_entering_supervisor_mode(CSRR_T0_SSCRATCH)
	defer rv.machine_destroy(&machine)
	machine.cpu.csr.mstatus = rv.mstatus_with_mpp(0, .User)
	rv.machine_step(&machine) // step 1: mret into U

	// csr_allowed: 0 >= 1 is false, so Illegal_Instruction.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.User)
}

@(test)
supervisor_mode_sets_its_fields_through_sstatus :: proc(t: ^testing.T) {
	// csrs sstatus, t1 with t1 = SIE, in supervisor mode.
	machine := machine_entering_supervisor_mode(CSRS_SSTATUS_T1)
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = rv.MSTATUS_SIE // t1
	rv.machine_step(&machine) // step 1: mret into S
	before := machine.cpu.csr.mstatus // after the mret: MPP = user, MPIE = 1

	// Step 2: allowed (sstatus is supervisor level), and it changes only
	// SIE, inside mstatus.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.csr.mstatus, before | rv.MSTATUS_SIE)

	// Undo puts SIE back off, and leaves the machine fields as they were.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mstatus, before)
}

@(test)
supervisor_mode_enables_its_interrupts_through_sie :: proc(t: ^testing.T) {
	// csrw sie, t1 with t1 = all ones, in supervisor mode.
	machine := machine_entering_supervisor_mode(CSRW_SIE_T1)
	defer rv.machine_destroy(&machine)
	machine.cpu.regs[6] = ~u64(0) // t1
	machine.cpu.csr.mideleg = rv.MIP_STIP // the timer is supervisor mode's
	machine.cpu.csr.mie = rv.MIP_MTIP // machine mode wants its own timer (MTIE)
	rv.machine_step(&machine) // step 1: mret into S

	// Step 2: allowed (sie is supervisor level). Only the delegated
	// enable, STIE, turns on; MTIE stays as machine mode left it.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.csr.mie, rv.MIP_MTIP | rv.MIP_STIP)

	// Undo turns STIE off again, and MTIE stays.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.csr.mie, rv.MIP_MTIP)
}

@(test)
supervisor_mode_needs_mcounteren_to_read_cycle :: proc(t: ^testing.T) {
	// The same csrr t0, cycle, with mcounteren = 0 (its reset value):
	// machine mode hasn't allowed it.
	machine := machine_entering_supervisor_mode(CSRR_T0_CYCLE)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into S

	rv.machine_step(&machine) // step 2: refused, to machine mode
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.csr.mtval, u64(CSRR_T0_CYCLE)) // the instruction
	testing.expect_value(t, machine.cpu.regs[5], 0) // t0 not written
}
