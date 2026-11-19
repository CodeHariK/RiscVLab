package rv

// MRET: return from a machine-mode trap handler (privileged spec,
// "Trap-Return Instructions"). Undoes what trap entry did:
//
//   1. pc        = mepc (the handler usually adds 4 first, to skip the
//                  instruction that trapped, e.g. an ECALL)
//   2. privilege = mstatus.MPP (the level the trap came from)
//   3. MIE = MPIE (interrupts back to how they were), then MPIE = 1
//   4. MPP = the least-privileged mode this hart supports (machine, for
//      now), so a stale MPP can't be reused by a later MRET
//
// Only machine mode may execute MRET; anywhere else it is illegal.

ENCODING_MRET :: u32(0x3020_0073)

exec_mret :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	if cpu.privilege != .Machine {
		return illegal_instruction(instruction)
	}
	csr := &cpu.csr
	old_mstatus := csr.mstatus

	previous := Privilege((old_mstatus & MSTATUS_MPP) >> MSTATUS_MPP_SHIFT)
	new_mstatus := old_mstatus &~ (MSTATUS_MIE | MSTATUS_MPP)
	if old_mstatus & MSTATUS_MPIE != 0 {
		new_mstatus |= MSTATUS_MIE
	}
	new_mstatus |= MSTATUS_MPIE
	new_mstatus |= u64(LEAST_PRIVILEGED_MODE) << MSTATUS_MPP_SHIFT

	when DEBUG_RECORD_STEPS {
		cpu.undo.csr_changed = true
		cpu.undo.csr_address = CSR_MSTATUS
		cpu.undo.csr_old = old_mstatus
	}
	csr.mstatus = new_mstatus
	cpu.privilege = previous
	cpu.next_pc = csr.mepc
	return nil
}
