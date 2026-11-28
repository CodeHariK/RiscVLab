package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for user mode (core/trap_return.odin, trap_entry.odin,
// csr.odin, interrupts.odin): MRET down to user mode, ECALL and illegal
// instructions back up to machine mode, undo across the switch, and
// machine interrupts reaching user mode.

@(private = "file")
MRET :: u32(0x3020_0073)
@(private = "file")
ECALL :: u32(0x0000_0073)
@(private = "file")
CSRR_T0_MSTATUS :: u32(0x3000_22f3) // csrrs t0, mstatus, zero
@(private = "file")
USER_CODE :: rv.RAM_BASE + 0x100 // where MRET sends the hart
@(private = "file")
HANDLER :: rv.RAM_BASE + 0x800 // mtvec

// A machine whose first instruction is MRET, with mepc = USER_CODE and
// MPP = user, so one step drops into user mode; `user_code` is placed at
// USER_CODE.
@(private = "file")
machine_entering_user_mode :: proc(user_code: ..u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(MRET))
	for instruction, index in user_code {
		rv.machine_store(&machine, USER_CODE + u64(index) * 4, 4, u64(instruction))
	}
	machine.cpu.csr.mepc = USER_CODE
	machine.cpu.csr.mtvec = HANDLER
	machine.cpu.csr.mstatus = 0 // MPP = user
	return machine
}

// Step 1 is always the MRET at RAM_BASE (machine mode), dropping into
// user mode at USER_CODE; step 2 is the instruction under test.

@(test)
mret_drops_into_user_mode :: proc(t: ^testing.T) {
	// A NOP waits at USER_CODE: this test only checks where MRET lands.
	machine := machine_entering_user_mode(NOP)
	defer rv.machine_destroy(&machine)

	// MRET: privilege = MPP (user), pc = mepc (USER_CODE).
	testing.expect(t, rv.machine_step(&machine) == nil) // no trap
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, USER_CODE)
	// MRET also empties the return slot: MPP = the least privileged
	// mode, which is user itself here (docs: mret, "Why step 4").
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.User)
}

@(test)
ecall_from_user_mode_traps_to_machine_mode :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U

	// Step 2: ecall, a system call. The cause says which level called:
	// 8 from user (9 from supervisor), so the handler knows who asked.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Ecall_From_U_Mode))
	// mepc = the ecall itself; the handler adds 4 before returning.
	testing.expect_value(t, machine.cpu.csr.mepc, USER_CODE)
	// Up to machine mode, at the handler in mtvec.
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, HANDLER)
	// MPP remembers where the trap came from, for the handler's mret.
	testing.expect_value(t, rv.mstatus_mpp(machine.cpu.csr.mstatus), rv.Privilege.User)
}

@(test)
machine_csr_from_user_mode_is_illegal :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(CSRR_T0_MSTATUS)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U

	// Step 2: csrr t0, mstatus. mstatus is 0x300: bits 9..8 = 11,
	// machine only (csr_allowed: 0 >= 3 is false), so Illegal_Instruction.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	// For an illegal instruction, mtval holds its 32 bits.
	testing.expect_value(t, machine.cpu.csr.mtval, u64(CSRR_T0_MSTATUS))
	// A trapping instruction changes nothing: t0 never got mstatus.
	testing.expect_value(t, machine.cpu.regs[5], 0)
}

@(test)
mret_from_user_mode_is_illegal :: proc(t: ^testing.T) {
	// A second MRET waits at USER_CODE.
	machine := machine_entering_user_mode(MRET)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1: mret into U (allowed: machine mode)

	// Step 2: mret again, now from U. MRET sets the level to MPP, so only
	// machine mode may run it (exec_mret), or a user program could jump
	// itself into machine mode.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine) // the trap took it up
}

@(test)
undo_steps_back_across_the_switch :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // step 1, mret: machine -> user
	rv.machine_step(&machine) // step 2, ecall: user -> machine

	// Back over the ecall: the undo record kept the level from before
	// the step, so the hart is in user mode again, at the ecall.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, USER_CODE)

	// Back over the mret: machine mode, at the first instruction, and
	// mstatus exactly as the helper set it. The mret had changed it
	// (MPIE = 1), and undo puts the old value back (MPP = user, the
	// rest 0).
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE)
	testing.expect_value(t, machine.cpu.csr.mstatus, 0)
}

// In user mode, machine interrupts are always on: mstatus.MIE only
// switches them off while the hart is in machine mode (interrupt_to_take).
// Otherwise a user program could stop the timer from ever taking the CPU
// back.
@(test)
machine_interrupts_reach_user_mode_even_with_mie_off :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(NOP, NOP)
	defer rv.machine_destroy(&machine)
	devices.clint_attach(&machine)

	// Timer interrupts wanted (mie.MTIE), and the alarm already due:
	// mtimecmp = 0, so mtime >= mtimecmp and MTIP is pending at once.
	machine.cpu.csr.mie = rv.MIP_MTIP
	rv.machine_store(&machine, rv.CLINT_BASE + devices.CLINT_MTIMECMP, 8, 0)

	// Step 1, mret into U. MIE = MPIE = 0: interrupts stay "off".
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_MIE, 0)

	// Step 2: the interrupt is taken anyway, before the first nop runs,
	// because the hart is below machine mode.
	rv.machine_step(&machine)
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Machine_Timer_Interrupt))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
}

@(test)
user_mode_reads_time :: proc(t: ^testing.T) {
	// time is 0xc01: bits 9..8 = 00, so any mode may read it, once
	// machine mode allows it: TM in mcounteren (for supervisor mode) and
	// scounteren (passing it on to user mode). csrr t0, time in U.
	machine := machine_entering_user_mode(CSRR_T0_TIME)
	defer rv.machine_destroy(&machine)
	devices.clint_attach(&machine) // the clock time reads
	machine.cpu.csr.mcounteren = rv.COUNTEREN_TM
	machine.cpu.csr.scounteren = rv.COUNTEREN_TM
	rv.machine_step(&machine) // step 1: mret into U

	// Step 2: allowed, no trap. One step (the mret) has gone by.
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.regs[5], 1)
}

@(test)
user_mode_needs_both_counter_enables :: proc(t: ^testing.T) {
	// Only mcounteren.TM: supervisor mode could read time, but hasn't
	// passed it on (scounteren = 0), so user mode can't.
	machine := machine_entering_user_mode(CSRR_T0_TIME)
	defer rv.machine_destroy(&machine)
	devices.clint_attach(&machine)
	machine.cpu.csr.mcounteren = rv.COUNTEREN_TM
	rv.machine_step(&machine) // step 1: mret into U

	rv.machine_step(&machine) // step 2: refused
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
}
