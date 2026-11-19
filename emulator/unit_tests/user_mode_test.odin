package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for user mode (core/privilege.odin,
// csr.odin): MRET down to user mode, ECALL and illegal instructions back
// up to machine mode, and undo across the switch.

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

@(test)
mret_drops_into_user_mode :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(NOP)
	defer rv.machine_destroy(&machine)
	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, USER_CODE)
	// MPP is reset to the least privileged mode: user.
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_MPP, 0)
}

@(test)
ecall_from_user_mode_traps_to_machine_mode :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // mret
	rv.machine_step(&machine) // ecall
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Ecall_From_U_Mode))
	testing.expect_value(t, machine.cpu.csr.mepc, USER_CODE)
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, HANDLER)
	// MPP remembers where the trap came from, for the handler's mret.
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_MPP, 0)
}

@(test)
machine_csr_from_user_mode_is_illegal :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(CSRR_T0_MSTATUS)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // mret
	rv.machine_step(&machine) // csrr t0, mstatus
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.csr.mtval, u64(CSRR_T0_MSTATUS))
	testing.expect_value(t, machine.cpu.regs[5], 0) // t0 untouched
}

@(test)
mret_from_user_mode_is_illegal :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(MRET)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // mret, in machine mode
	rv.machine_step(&machine) // mret, in user mode
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Illegal_Instruction))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
}

@(test)
undo_steps_back_across_the_switch :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(ECALL)
	defer rv.machine_destroy(&machine)
	rv.machine_step(&machine) // mret: machine -> user
	rv.machine_step(&machine) // ecall: user -> machine
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.User)
	testing.expect_value(t, machine.cpu.pc, USER_CODE)
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE)
	testing.expect_value(t, machine.cpu.csr.mstatus, 0) // MPP = user again
}

// In user mode, machine interrupts are always on: mstatus.MIE only
// switches them off while the hart is in machine mode.
@(test)
machine_interrupts_reach_user_mode_even_with_mie_off :: proc(t: ^testing.T) {
	machine := machine_entering_user_mode(NOP, NOP)
	defer rv.machine_destroy(&machine)
	devices.clint_attach(&machine.bus)
	machine.cpu.csr.mie = rv.MIP_MTIP
	rv.machine_store(&machine, rv.CLINT_BASE + devices.CLINT_MTIMECMP, 8, 0) // the alarm has come
	rv.machine_step(&machine) // mret; MIE stays 0
	testing.expect_value(t, machine.cpu.csr.mstatus & rv.MSTATUS_MIE, 0)
	rv.machine_step(&machine) // the interrupt, instead of the first nop
	testing.expect_value(t, machine.cpu.csr.mcause, u64(rv.Trap_Cause.Machine_Timer_Interrupt))
	testing.expect_value(t, machine.cpu.privilege, rv.Privilege.Machine)
}
