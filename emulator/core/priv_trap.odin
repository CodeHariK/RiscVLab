package rv

// Trap entry in machine mode (privileged spec, "Machine-Mode Exception
// Handling"). When an instruction raises a trap, the hart:
//
//   1. mepc   = address of the instruction that trapped
//   2. mcause = why (Trap_Cause; bit 63 would mark an interrupt)
//   3. mtval  = extra information (bad address, or the instruction bits)
//   4. mstatus: MPIE = MIE, then MIE = 0 (interrupts off in the handler),
//      MPP = the privilege level it was running at
//   5. switches to machine mode and jumps to the handler at mtvec
//
// mtvec's low two bits are its mode: 0 = direct (every trap goes to the
// base address), 1 = vectored (interrupts go to base + 4 * cause). These
// are all exceptions, which always go to the base.
//
// Emulator convention, not hardware: if mtvec is 0, no handler has been
// set up, so the trap stops the machine instead (real hardware would jump
// to address 0). That keeps simple test programs, which just end with
// EBREAK, working.

// Privilege levels, numbered as in mstatus.MPP.
Privilege :: enum u8 {
	User       = 0,
	Supervisor = 1,
	Machine    = 3,
}

MSTATUS_MPP_SHIFT :: 11

trap_has_handler :: proc(cpu: ^Cpu) -> bool {
	return cpu.csr.mtvec != 0
}

// Enters the trap handler. The caller has already saved, for undo, the
// state this changes (see `machine_step`).
trap_enter :: proc(cpu: ^Cpu, trap: Trap) {
	csr := &cpu.csr
	csr.mepc = cpu.pc
	csr.mcause = u64(trap.cause)
	csr.mtval = trap.value

	interrupts_were_enabled := csr.mstatus & MSTATUS_MIE != 0
	csr.mstatus &~= MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP
	if interrupts_were_enabled {
		csr.mstatus |= MSTATUS_MPIE
	}
	csr.mstatus |= u64(cpu.privilege) << MSTATUS_MPP_SHIFT

	cpu.privilege = .Machine
	cpu.pc = csr.mtvec &~ 0b11
}

// The environment-call cause for the current privilege level.
ecall_cause :: proc(privilege: Privilege) -> Trap_Cause {
	switch privilege {
	case .User:
		return .Ecall_From_U_Mode
	case .Supervisor:
		return .Ecall_From_S_Mode
	case .Machine:
	}
	return .Ecall_From_M_Mode
}
