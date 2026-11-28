package rv

// Trap return: MRET and SRET, back down to the level a trap came from
// (privileged spec, "Trap-Return Instructions"). The way up:
// trap_entry.odin. The levels and MPP / SPP: privilege.odin.
//
// MRET: return from a machine-mode trap handler. Undoes what trap entry
// did:
//
//   1. pc        = mepc (the handler usually adds 4 first, to skip the
//                  instruction that trapped, e.g. an ECALL)
//   2. privilege = mstatus.MPP (the level the trap came from)
//   3. MIE = MPIE (interrupts back to how they were), then MPIE = 1
//   4. MPP = the least-privileged mode this hart supports (user), so a
//      stale MPP can't be reused by a later MRET
//
// Only machine mode may execute MRET; anywhere else it is illegal.

ENCODING_MRET :: u32(0x3020_0073)

exec_mret :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Mret)
	}

	if cpu.privilege != .Machine {
		return illegal_instruction(instruction)
	}

	when DEBUG_RECORD_STEPS {
		cpu.debug_undo.csr_changed = true
		cpu.debug_undo.csr_address = CSR_MSTATUS
		cpu.debug_undo.csr_old = cpu.csr.mstatus
	}

	csr := &cpu.csr

	cpu.privilege = mstatus_mpp(csr.mstatus) // where mret goes: the level the trap came from
	cpu.next_pc = csr.mepc // cpu_step moves the pc here

	csr.mstatus &= ~MSTATUS_MIE // MIE = MPIE: clear it first,
	if csr.mstatus & MSTATUS_MPIE != 0 {
		csr.mstatus |= MSTATUS_MIE // then set it if interrupts were on before the trap
	}
	csr.mstatus |= MSTATUS_MPIE // MPIE = 1: the saved slot is emptied to "on"
	csr.mstatus = mstatus_with_mpp(csr.mstatus, LEAST_PRIVILEGED_MODE) // MPP = user: a second mret can't go back up

	return nil
}

// SRET: return from a supervisor-mode trap handler (a trap delegated by
// medeleg). MRET's twin, with the supervisor fields:
//
//   1. pc        = sepc
//   2. privilege = mstatus.SPP (user or supervisor)
//   3. SIE = SPIE (supervisor interrupts back to how they were), then
//      SPIE = 1
//   4. SPP = the least privileged mode (user), so a stale SPP can't be
//      reused by a later SRET
//
// Supervisor and machine mode may execute SRET; user mode may not. (A
// mstatus.TSR bit can make it illegal in supervisor mode too, for
// hypervisors; it reads 0 here.)

ENCODING_SRET :: u32(0x1020_0073)

exec_sret :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Sret)
	}

	if cpu.privilege == .User {
		return illegal_instruction(instruction)
	}

	when DEBUG_RECORD_STEPS {
		cpu.debug_undo.csr_changed = true
		cpu.debug_undo.csr_address = CSR_MSTATUS
		cpu.debug_undo.csr_old = cpu.csr.mstatus
	}

	csr := &cpu.csr

	cpu.privilege = mstatus_spp(csr.mstatus) // where sret goes: user or supervisor, never machine
	cpu.next_pc = csr.sepc // cpu_step moves the pc here

	csr.mstatus &= ~MSTATUS_SIE // SIE = SPIE: clear it first,
	if csr.mstatus & MSTATUS_SPIE != 0 {
		csr.mstatus |= MSTATUS_SIE // then set it if supervisor interrupts were on before the trap
	}
	csr.mstatus |= MSTATUS_SPIE // SPIE = 1: the saved slot is emptied to "on"
	csr.mstatus = mstatus_with_spp(csr.mstatus, LEAST_PRIVILEGED_MODE) // SPP = user: a second sret can't go back up

	return nil
}
