package rv

// Trap entry: which mode takes a trap, and what the hardware does the
// moment it is taken (privileged spec, "Machine-Mode Exception Handling"
// and "Machine Trap Delegation"). What a trap is: trap.odin. Coming back
// down: trap_return.odin. The levels and MPP / SPP: privilege.odin.
//
// When an instruction raises a trap, or an interrupt is taken, the hart:
//
//   1. mepc   = address of the instruction that trapped
//   2. mcause = why (Trap_Cause; bit 63 would mark an interrupt)
//   3. mtval  = extra information (bad address, or the instruction bits)
//   4. mstatus: MPIE = MIE, then MIE = 0 (interrupts off in the handler),
//      MPP = the privilege level it was running at
//   5. switches to machine mode and jumps to the handler at mtvec
//
// A trap delegated to supervisor mode (medeleg) does the same with the
// supervisor CSRs and fields: sepc, scause, stval, SPIE / SIE / SPP,
// stvec.

// Which mode takes the trap: supervisor mode if its delegation bit is
// set, machine mode otherwise.
//
//   exceptions: medeleg, and only below machine mode. A trap never goes
//               down a level: an exception in machine mode stays there
//               whatever medeleg says.
//   interrupts: mideleg. A delegated interrupt is never taken in machine
//               mode at all (interrupt_to_take holds it back), so the
//               same rule holds.
trap_target :: proc(cpu: ^Cpu, trap: Trap) -> Privilege {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Trap_Target)
	}
	bit := u64(1) << trap_cause_number(trap.cause)
	if trap_is_interrupt(trap.cause) {
		return .Supervisor if cpu.csr.mideleg & bit != 0 else .Machine
	}
	if cpu.privilege == .Machine {
		return .Machine
	}
	if cpu.csr.medeleg & bit != 0 {
		return .Supervisor
	}
	return .Machine
}

// Whether the mode taking the trap has a handler: its trap vector
// (mtvec, or stvec for supervisor mode) has a base address other than 0.
//
// Emulator convention, not hardware: if the base address is 0, no
// handler has been set up, so the trap stops the machine instead (real
// hardware would jump to address 0). That keeps simple test programs,
// which just end with EBREAK, working. The base, not the whole CSR:
// mtvec = 1 (vectored, base 0) has no handler either.
trap_has_handler :: proc(cpu: ^Cpu, target: Privilege) -> bool {
	vector := cpu.csr.stvec if target == .Supervisor else cpu.csr.mtvec
	return mtvec_base(vector) != 0
}

// Enters the trap handler of `target` (trap_target): what the hardware
// does the moment a trap is taken. The caller has already saved, for
// undo, the state this changes (see `machine_step`).
trap_enter :: proc(cpu: ^Cpu, trap: Trap, target: Privilege) {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Trap_Enter)
	}
	if target == .Supervisor {
		trap_enter_supervisor(cpu, trap)
	} else {
		trap_enter_machine(cpu, trap)
	}
	// Cancel any LR reservation: an SC after the handler returns must
	// fail, since the handler may have changed the memory (rv64a.odin,
	// lesson 18).
	reservation_set(cpu, Reservation{})
}

// A trap into machine mode.
@(private = "file")
trap_enter_machine :: proc(cpu: ^Cpu, trap: Trap) {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Trap_Enter_Machine)
	}

	csr := &cpu.csr

	// 1. Remember where, why and what, for the handler.
	//    mepc:   the instruction that trapped; for an interrupt, the one
	//            that hadn't run yet (it runs after mret).
	//    mcause: e.g. 2 = Illegal_Instruction, 0x8000000000000007 = the
	//            timer interrupt (bit 63 set: an interrupt).
	//    mtval:  the bad address or instruction bits; 0 for interrupts.
	csr.mepc = cpu.pc
	csr.mcause = u64(trap.cause)
	csr.mtval = trap.value

	// 2. Interrupts off inside the handler, keeping how they were, so mret
	//    can put it back: MPIE = the old MIE, MIE = 0, MPP = the privilege
	//    level the trap came from. With MIE = 0 no interrupt can arrive in
	//    the middle of the handler (it would overwrite mepc and mcause).
	interrupts_were_enabled := csr.mstatus & MSTATUS_MIE != 0
	csr.mstatus &= ~MSTATUS_TRAP_FIELDS_M // MIE and MPIE off, then MPIE as MIE was
	if interrupts_were_enabled {
		csr.mstatus |= MSTATUS_MPIE
	}
	csr.mstatus = mstatus_with_mpp(csr.mstatus, cpu.privilege)

	// 3. Machine mode, and jump to the handler. mtvec's low 2 bits are its
	//    mode, not part of the address:
	//      0 direct:   every trap goes to the base address; one handler
	//                  reads mcause and decides.
	//      1 vectored: interrupts go to base + 4 * their number, so each
	//                  kind gets its own entry point (the timer, number 7,
	//                  to base + 28). Exceptions still go to the base.
	cpu.privilege = .Machine
	cpu.pc = mtvec_base(csr.mtvec)
	if mtvec_mode(csr.mtvec) == MTVEC_VECTORED && trap_is_interrupt(trap.cause) {
		cpu.pc += 4 * trap_cause_number(trap.cause)
	}
}

// A trap into supervisor mode (delegated by medeleg): the same three
// steps as trap_enter_machine, with the supervisor CSRs and fields.
// Machine mode's mepc, mcause, mtval, MIE, MPIE and MPP are left alone.
@(private = "file")
trap_enter_supervisor :: proc(cpu: ^Cpu, trap: Trap) {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Trap_Enter_Supervisor)
	}
	csr := &cpu.csr

	// 1. Where, why and what: sepc, scause, stval.
	csr.sepc = cpu.pc
	csr.scause = u64(trap.cause)
	csr.stval = trap.value

	// 2. Supervisor interrupts off, keeping how they were: SPIE = the old
	//    SIE, SIE = 0, SPP = the level the trap came from. SPP is one bit:
	//    the trap came from user (0) or supervisor (1) mode, never from
	//    machine mode (trap_target).
	interrupts_were_enabled := csr.mstatus & MSTATUS_SIE != 0
	csr.mstatus &= ~MSTATUS_TRAP_FIELDS_S // SIE and SPIE off, then SPIE as SIE was
	if interrupts_were_enabled {
		csr.mstatus |= MSTATUS_SPIE
	}
	csr.mstatus = mstatus_with_spp(csr.mstatus, cpu.privilege)

	// 3. Supervisor mode, and jump to stvec's handler (same layout as
	//    mtvec).
	cpu.privilege = .Supervisor
	cpu.pc = mtvec_base(csr.stvec)
	if mtvec_mode(csr.stvec) == MTVEC_VECTORED && trap_is_interrupt(trap.cause) {
		cpu.pc += 4 * trap_cause_number(trap.cause)
	}
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
